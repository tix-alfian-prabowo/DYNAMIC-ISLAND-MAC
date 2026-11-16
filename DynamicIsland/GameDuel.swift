import Combine
import Foundation
import OSLog
import Supabase

/// Friends' challenges, for every game in the Game tab. Each player has their own Realtime channel
/// on Poke's Supabase project where challenges arrive; a challenge says which game, the match's
/// id and the seed both sides play with. Nothing is stored.
final class GameInvites: ObservableObject {
    static let shared = GameInvites()

    struct Invite: Equatable, Identifiable {
        let id: String
        let game: NotchGame
        let friend: PokeService.Friend
        let seed: UInt64
        let received: Date
    }

    /// The challenge waiting for an answer.
    @Published private(set) var invite: Invite?

    /// A challenge nobody took is called off after this long.
    static let timeout: TimeInterval = 60

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicIsland", category: "Game")
    private var inbox: RealtimeChannelV2?
    private var inboxUserID: UUID?
    private var inboxTasks: [Task<Void, Never>] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Challenges can come in while Poke is connected.
        PokeService.shared.$state.combineLatest(PokeService.shared.$profile)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, profile in
                self?.listen(userID: state == .ready ? profile?.id : nil)
            }
            .store(in: &cancellables)
    }

    func invite(for game: NotchGame) -> Invite? {
        invite?.game == game ? invite : nil
    }

    /// Sends the challenge to the friend's own channel.
    func challenge(_ friend: PokeService.Friend, to game: NotchGame, match: String, seed: UInt64) {
        guard let me = PokeService.shared.profile else { return }
        log.info("Challenging a friend to \(game.rawValue, privacy: .public)")
        Task {
            await send("invite", to: friend.id, [
                "match": .string(match),
                "game": .string(game.rawValue),
                "from": .string(me.id.uuidString.lowercased()),
                "seed": .string(String(seed)),
            ])
        }
    }

    func cancelChallenge(match: String, to friend: PokeService.Friend) {
        Task { await send("cancel", to: friend.id, ["match": .string(match)]) }
    }

    /// Takes the waiting challenge: its game opens and joins the match.
    func accept() {
        guard let invite else { return }
        self.invite = nil
        GameLibrary.shared.current = invite.game
        switch invite.game {
        case .notchDrop: NotchDrop.shared.accept(invite)
        case .notchRush: NotchRush.shared.accept(invite)
        }
    }

    /// Says no to the waiting challenge; the challenger's game hears it on the match's channel.
    func decline() {
        guard let invite else { return }
        self.invite = nil
        Task {
            guard let channel = PokeService.shared.gameChannel(invite.game.matchTopic(invite.id)) else { return }
            try? await channel.httpSend(event: "decline", message: [:] as JSONObject)
            await PokeService.shared.removeGameChannel(channel)
        }
    }

    // MARK: Inbox

    /// Each player's own channel, where friends' challenges arrive.
    private func listen(userID: UUID?) {
        guard userID != inboxUserID else { return }
        inboxTasks.forEach { $0.cancel() }
        inboxTasks = []
        if let inbox {
            Task { await PokeService.shared.removeGameChannel(inbox) }
        }
        inbox = nil
        inboxUserID = userID
        guard let userID, let channel = PokeService.shared.gameChannel(Self.inboxTopic(userID)) else { return }
        inbox = channel
        for event in ["invite", "cancel"] {
            let stream = channel.broadcastStream(event: event)
            inboxTasks.append(Task { [weak self] in
                for await message in stream {
                    self?.received(event, GameMessage.payload(of: message))
                }
            })
        }
        inboxTasks.append(Task { [weak self] in
            do {
                try await channel.subscribeWithError()
            } catch {
                self?.log.error("Couldn't listen for challenges: \(String(describing: error), privacy: .public)")
            }
        })
    }

    private func received(_ event: String, _ payload: JSONObject) {
        guard let id = payload["match"]?.stringValue, UUID(uuidString: id) != nil else { return }
        switch event {
        case "invite":
            // Only friends can challenge, by the name you know them by. A challenge from a version
            // with only Notch Drop doesn't say the game.
            guard let from = payload["from"]?.stringValue.flatMap(UUID.init(uuidString:)),
                  let friend = PokeService.shared.friends.first(where: { $0.id == from }),
                  let seed = payload["seed"]?.stringValue.flatMap(UInt64.init),
                  let game = NotchGame(rawValue: payload["game"]?.stringValue ?? NotchGame.notchDrop.rawValue) else { return }
            invite = Invite(id: id, game: game, friend: friend, seed: seed, received: Date())
            log.info("A friend challenged you to \(game.rawValue, privacy: .public)")
            let notification = AppNotification(type: .game, title: "\(friend.name) challenges you", body: "\(game.title) duel", actionTitle: "Play")
            NotificationManager.shared.postActivity(notification)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.timeout + 5))
                if self?.invite?.id == id { self?.invite = nil }
            }
        case "cancel":
            if invite?.id == id { invite = nil }
        default:
            break
        }
    }

    /// To a friend's own channel, over HTTP: without joining it, so their other challenges stay theirs.
    private func send(_ event: String, to friendID: UUID, _ message: JSONObject) async {
        guard let channel = PokeService.shared.gameChannel(Self.inboxTopic(friendID)) else { return }
        do {
            try await channel.httpSend(event: event, message: message)
        } catch {
            // Over the socket instead, joining the channel for a moment.
            log.error("Couldn't send a challenge over HTTP, trying the socket: \(String(describing: error), privacy: .public)")
            do {
                try await channel.subscribeWithError()
                await channel.broadcast(event: event, message: message)
                try? await Task.sleep(for: .milliseconds(500))
            } catch {
                log.error("Couldn't send a challenge: \(String(describing: error), privacy: .public)")
            }
        }
        await PokeService.shared.removeGameChannel(channel)
    }

    /// The name stays Notch Drop's, the first game, so older versions still get challenges.
    private static func inboxTopic(_ userID: UUID) -> String {
        "notch-drop-inbox:\(userID.uuidString.lowercased())"
    }
}

/// One match's Realtime channel, shared by both players: `join`, `start`, `decline` and `leave`
/// set the match up and end it; each game sends its own events in between.
final class DuelMatch {
    let id: String
    let friend: PokeService.Friend
    let isHost: Bool
    /// When the other player last said anything.
    private(set) var lastHeard = Date()

    private let channel: RealtimeChannelV2
    private var tasks: [Task<Void, Never>] = []
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicIsland", category: "Game")

    /// Nil while Poke isn't connected. `onEvent` gets every event, the game's and the set-up ones.
    init?(game: NotchGame, id: String, friend: PokeService.Friend, isHost: Bool, events: [String],
          onEvent: @escaping (String, JSONObject) -> Void) {
        guard let channel = PokeService.shared.gameChannel(game.matchTopic(id)) else { return nil }
        self.id = id
        self.friend = friend
        self.isHost = isHost
        self.channel = channel
        for event in ["join", "start", "decline", "leave"] + events {
            let stream = channel.broadcastStream(event: event)
            tasks.append(Task { [weak self] in
                for await message in stream {
                    self?.lastHeard = Date()
                    onEvent(event, GameMessage.payload(of: message))
                }
            })
        }
        tasks.append(Task { [weak self, log] in
            do {
                try await channel.subscribeWithError()
                // The challenged side says it's here; the challenger then starts the match.
                if !isHost {
                    await channel.broadcast(event: "join", message: [:] as JSONObject)
                }
                self?.lastHeard = Date()
            } catch {
                log.error("Couldn't join the duel: \(String(describing: error), privacy: .public)")
            }
        })
    }

    func send(_ event: String, _ message: JSONObject = [:]) {
        let channel = channel
        Task { await channel.broadcast(event: event, message: message) }
    }

    /// Leaves the channel, first telling the other player when `notify`.
    func leave(notify: Bool) {
        tasks.forEach { $0.cancel() }
        tasks = []
        let channel = channel
        Task {
            if notify && channel.status == .subscribed {
                await channel.broadcast(event: "leave", message: [:] as JSONObject)
            }
            await PokeService.shared.removeGameChannel(channel)
        }
    }
}

enum GameMessage {
    /// A broadcast arrives wrapped with its event; the message is under `payload`.
    static func payload(of message: JSONObject) -> JSONObject {
        message["payload"]?.objectValue ?? message
    }

    static func int(_ value: AnyJSON?) -> Int? {
        value?.intValue ?? value?.doubleValue.map { Int($0) }
    }

    static func double(_ value: AnyJSON?) -> Double? {
        value?.doubleValue ?? value?.intValue.map(Double.init)
    }
}
