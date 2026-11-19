import Combine
import Foundation
import OSLog
import QuartzCore
import Supabase

/// Playing with a friend's pet: invite them (or join their invite), and both pets show on both
/// desktops. Each Mac moves its own pet and tells the other where it is a few times a second over
/// a Realtime channel on Poke's Supabase project; invites go through the friends' game inbox
/// (GameInvites). Nothing is stored.
final class PetPlay: ObservableObject {
    static let shared = PetPlay()

    enum State: Equatable {
        case none
        /// Waiting for the friend to join.
        case inviting(PokeService.Friend, id: String)
        /// Joined their invite, waiting to hear their pet.
        case joining(PokeService.Friend, id: String)
        case playing(PokeService.Friend, id: String)

        var friend: PokeService.Friend? {
            switch self {
            case .none: return nil
            case .inviting(let friend, _), .joining(let friend, _), .playing(let friend, _): return friend
            }
        }

        var id: String? {
            switch self {
            case .none: return nil
            case .inviting(_, let id), .joining(_, let id), .playing(_, let id): return id
            }
        }
    }

    struct Invite: Equatable {
        let id: String
        let friend: PokeService.Friend
        let received: Date
    }

    @Published private(set) var state = State.none
    /// Friends' invites waiting, by friend.
    @Published private(set) var invites: [UUID: Invite] = [:]

    static let inviteTimeout: TimeInterval = 90
    private static let positionInterval: TimeInterval = 0.12
    private static let silenceTimeout: TimeInterval = 20

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicIsland", category: "Pet")
    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private var sendTimer: Timer?
    private var lastHeard = Date()
    private var heardFriend = false
    private var positionsSent = 0

    private init() {}

    /// When both pets get the ball at once, the Mac whose user id sorts first keeps it.
    var friendWinsTies: Bool {
        guard let me = PokeService.shared.profile?.id, let friend = state.friend?.id else { return false }
        return friend.uuidString < me.uuidString
    }

    func invite(for friend: PokeService.Friend) -> Invite? {
        invites[friend.id]
    }

    // MARK: Invite, join, leave

    /// Asks a friend to play; if they already asked you, joins them instead.
    func invite(_ friend: PokeService.Friend) {
        if invites[friend.id] != nil {
            join(friend)
            return
        }
        guard let me = PokeService.shared.profile, PetStore.shared.look != nil else { return }
        leave()
        let id = UUID().uuidString.lowercased()
        guard open(id: id, friend: friend) else { return }
        state = .inviting(friend, id: id)
        log.info("Inviting a friend's pet")
        GameInvites.shared.sendToInbox("pet_invite", to: friend.id, [
            "match": .string(id),
            "from": .string(me.id.uuidString.lowercased()),
        ])
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.inviteTimeout))
            guard let self, case .inviting(_, let waiting) = self.state, waiting == id else { return }
            GameInvites.shared.sendToInbox("pet_cancel", to: friend.id, ["match": .string(id)])
            self.close()
        }
    }

    /// Takes a friend's invite.
    func join(_ friend: PokeService.Friend) {
        guard let invite = invites[friend.id], PetStore.shared.look != nil else { return }
        invites[friend.id] = nil
        leave()
        guard open(id: invite.id, friend: friend) else { return }
        state = .joining(friend, id: invite.id)
        // Say hello until their pet answers.
        Task { [weak self] in
            for _ in 0..<8 {
                guard let self, case .joining = self.state else { return }
                self.sendHello()
                try? await Task.sleep(for: .seconds(1.5))
            }
            guard let self, case .joining(_, let waiting) = self.state, waiting == invite.id else { return }
            self.close()
        }
    }

    func decline(_ friend: PokeService.Friend) {
        guard let invite = invites[friend.id] else { return }
        invites[friend.id] = nil
        Task {
            guard let channel = PokeService.shared.gameChannel(Self.topic(invite.id)) else { return }
            try? await channel.httpSend(event: "bye", message: [:] as JSONObject)
            await PokeService.shared.removeGameChannel(channel)
        }
    }

    /// Stops playing, or calls off the invite.
    func leave() {
        switch state {
        case .none:
            return
        case .inviting(let friend, let id):
            GameInvites.shared.sendToInbox("pet_cancel", to: friend.id, ["match": .string(id)])
        case .joining, .playing:
            send("bye")
        }
        close()
    }

    /// Your pet changed: the friend's Mac draws it anew.
    func lookChanged() {
        if case .playing = state {
            sendHello()
        }
    }

    // MARK: Inbox (from GameInvites)

    func receivedInbox(_ event: String, _ payload: JSONObject) {
        guard let id = payload["match"]?.stringValue, UUID(uuidString: id) != nil else { return }
        switch event {
        case "pet_invite":
            guard let from = payload["from"]?.stringValue.flatMap(UUID.init(uuidString:)),
                  let friend = PokeService.shared.friends.first(where: { $0.id == from }) else { return }
            // Both asked each other at once: join theirs.
            if case .inviting(let invited, _) = state, invited.id == friend.id, friendWinsTies {
                close()
                invites[friend.id] = Invite(id: id, friend: friend, received: Date())
                join(friend)
                return
            }
            invites[friend.id] = Invite(id: id, friend: friend, received: Date())
            log.info("A friend invited your pet to play")
            let pet = PetStore.shared.look?.name ?? "your pet"
            var notification = AppNotification(type: .pet, title: "\(friend.name) wants to play", body: "Bring \(pet) along", actionTitle: "Join")
            notification.petFriendID = friend.id
            NotificationManager.shared.postActivity(notification)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.inviteTimeout + 5))
                if self?.invites[friend.id]?.id == id { self?.invites[friend.id] = nil }
            }
        case "pet_cancel":
            for (friendID, invite) in invites where invite.id == id {
                invites[friendID] = nil
            }
        default:
            break
        }
    }

    // MARK: The channel

    private static func topic(_ id: String) -> String {
        "pet-play:\(id)"
    }

    private func open(id: String, friend: PokeService.Friend) -> Bool {
        guard let channel = PokeService.shared.gameChannel(Self.topic(id)) else { return false }
        self.channel = channel
        heardFriend = false
        lastHeard = Date()
        for event in ["hello", "pos", "chase", "tag", "ball", "got", "basket", "tossed", "take", "tug", "fight", "lick", "bye"] {
            let stream = channel.broadcastStream(event: event)
            tasks.append(Task { [weak self] in
                for await message in stream {
                    self?.received(event, GameMessage.payload(of: message), match: id)
                }
            })
        }
        tasks.append(Task { [weak self] in
            do {
                try await channel.subscribeWithError()
            } catch {
                self?.log.error("Couldn't join the pets' channel: \(String(describing: error), privacy: .public)")
            }
        })
        return true
    }

    private func close() {
        stopSending()
        tasks.forEach { $0.cancel() }
        tasks = []
        if let channel {
            Task { await PokeService.shared.removeGameChannel(channel) }
        }
        channel = nil
        if state != .none {
            state = .none
        }
        PetWorld.shared.removeFriend()
    }

    func send(_ event: String, _ message: JSONObject = [:]) {
        guard let channel, case .playing = state else { return }
        Task { await channel.broadcast(event: event, message: message) }
    }

    private func sendHello() {
        guard let channel, let look = PetStore.shared.look else { return }
        let message: JSONObject = ["kind": .string(look.kind.rawValue), "coat": .integer(look.coat), "name": .string(look.name),
                                   "size": .double(look.scale), "breed": .string(look.breed.rawValue),
                                   "wear": .string(look.wear.rawValue), "wearc": .integer(look.wearColor)]
        Task { await channel.broadcast(event: "hello", message: message) }
    }

    private func received(_ event: String, _ payload: JSONObject, match id: String) {
        guard state.id == id, let friend = state.friend else { return }
        lastHeard = Date()
        switch event {
        case "hello":
            guard let kind = payload["kind"]?.stringValue.flatMap(PetKind.init(rawValue:)) else { return }
            let name = payload["name"]?.stringValue.map { String($0.prefix(PetStore.nameLimit)) } ?? kind.defaultName
            let look = PetLook(kind: kind, coat: GameMessage.int(payload["coat"]) ?? 0, name: name,
                               scale: PetLook.clampedScale(GameMessage.double(payload["size"])),
                               breed: payload["breed"]?.stringValue.flatMap(PetBreed.init(rawValue:)) ?? .standard,
                               wear: payload["wear"]?.stringValue.flatMap(PetWear.init(rawValue:)) ?? .none,
                               wearColor: GameMessage.int(payload["wearc"]) ?? 0)
            let wasHeard = heardFriend
            heardFriend = true
            if case .inviting = state {
                // They joined: say hello back.
                state = .playing(friend, id: id)
                sendHello()
            } else if case .joining = state {
                state = .playing(friend, id: id)
            }
            if !wasHeard {
                log.info("Playing with a friend's pet")
                // Your pet comes out to play.
                if !PetStore.shared.isOut {
                    PetStore.shared.isOut = true
                }
                startSending()
            }
            PetWorld.shared.showFriend(look: look, owner: friend.name)
            // Your basket shows on their desktop too.
            sendBasket()
        case "pos":
            guard case .playing = state,
                  let x = GameMessage.double(payload["x"]), let y = GameMessage.double(payload["y"]) else { return }
            let action = payload["a"]?.stringValue.flatMap(PetPose.Action.init(rawValue:)) ?? .stand
            PetWorld.shared.updateFriend(position: CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)), action: action,
                                         facingRight: payload["f"]?.boolValue ?? true, happy: payload["h"]?.boolValue ?? false,
                                         bubble: payload["b"]?.stringValue.flatMap(PetActor.Bubble.init(rawValue:)),
                                         ball: payload["c"]?.boolValue ?? false, dizzy: payload["z"]?.boolValue ?? false,
                                         dip: min(max(GameMessage.double(payload["d"]) ?? 0, 0), 2),
                                         flight: min(max(GameMessage.double(payload["l"]) ?? 0, 0), 1),
                                         tilt: min(max(GameMessage.double(payload["t"]) ?? 0, -30), 30),
                                         yawning: payload["y"]?.boolValue ?? false)
            // Their bowl, for your pet to share.
            let bowlX = GameMessage.double(payload["wx"]), bowlY = GameMessage.double(payload["wy"])
            PetWorld.shared.showFriendBowl(at: bowlX.flatMap { x in bowlY.map { CGPoint(x: min(max(x, 0), 1), y: min(max($0, 0), 1)) } },
                                           fill: min(max(GameMessage.double(payload["wf"]) ?? 1, 0), 1))
        case "chase":
            PetWorld.shared.chased()
        case "tag":
            PetWorld.shared.tagged()
        case "ball":
            guard let ball = payload["id"]?.stringValue,
                  let x = GameMessage.double(payload["x"]), let y = GameMessage.double(payload["y"]) else { return }
            // Older versions don't say its color: the same one comes from its id on both Macs.
            let color = GameMessage.int(payload["k"]) ?? PetBallColors.index(for: ball)
            PetWorld.shared.throwBall(id: ball, target: CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)), color: color)
        case "got":
            guard let ball = payload["id"]?.stringValue else { return }
            PetWorld.shared.friendTookBall(id: ball)
        case "basket":
            guard case .playing = state else { return }
            let x = GameMessage.double(payload["x"]), y = GameMessage.double(payload["y"])
            let spot = payload["out"]?.boolValue == true ? x.flatMap { x in y.map { CGPoint(x: min(max(x, 0), 1), y: min(max($0, 0), 1)) } } : nil
            let balls = (payload["b"]?.arrayValue ?? []).compactMap { GameMessage.int($0) }.prefix(PetWorld.maxBalls * 5)
            PetWorld.shared.showFriendBasket(at: spot, balls: Array(balls), owner: friend.name)
        case "tossed":
            // Their pet dropped a ball into your basket.
            guard case .playing = state, let color = GameMessage.int(payload["k"]) else { return }
            PetWorld.shared.friendTossedBall(color: min(max(color, 0), PetBallColors.all.count - 1))
        case "take":
            // They clicked your basket on their desktop.
            guard case .playing = state else { return }
            PetWorld.shared.friendAskedForBall()
        case "tug", "fight":
            guard case .playing = state else { return }
            PetWorld.shared.friendChallenged(fight: event == "fight", seconds: min(max(GameMessage.double(payload["s"]) ?? 4, 2), 8),
                                             win: payload["w"]?.boolValue ?? false)
        case "lick":
            guard case .playing = state else { return }
            PetWorld.shared.licked()
        case "bye":
            log.info("The friend's pet went home")
            close()
        default:
            break
        }
    }

    /// Throws a ball for the pets: both chase it. A new one comes from the notch in a new color;
    /// one from the basket keeps its own.
    func throwBall(color: Int? = nil, from: CGPoint? = nil) {
        guard PetWorld.shared.ballCount < PetWorld.maxBalls else { return }
        let id = UUID().uuidString.lowercased()
        let color = color ?? PetWorld.shared.nextBallColor()
        let target = CGPoint(x: Double.random(in: 0.1...0.9), y: Double.random(in: 0.15...0.75))
        if PetStore.shared.look != nil, !PetStore.shared.isOut {
            PetStore.shared.isOut = true
        }
        PetWorld.shared.throwBall(id: id, target: target, color: color, from: from)
        send("ball", ["id": .string(id), "x": .double(target.x), "y": .double(target.y), "k": .integer(color)])
    }

    /// Your basket for the friend's desktop: where it is and what's in it, or that it's put away.
    /// Sent when it changes and every few seconds, in case a message got lost.
    func sendBasket() {
        guard case .playing = state else { return }
        if let basket = PetWorld.shared.basketState {
            send("basket", ["out": .bool(true), "x": .double(basket.spot.x), "y": .double(basket.spot.y),
                            "b": .array(basket.balls.suffix(PetWorld.maxBalls * 5).map { .integer($0) })])
        } else {
            send("basket", ["out": .bool(false)])
        }
    }

    // MARK: Positions

    private func startSending() {
        stopSending()
        let timer = Timer(timeInterval: Self.positionInterval, repeats: true) { _ in
            MainActor.assumeIsolated { PetPlay.shared.sendPosition() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sendTimer = timer
    }

    private func stopSending() {
        sendTimer?.invalidate()
        sendTimer = nil
    }

    private func sendPosition() {
        guard case .playing(let friend, _) = state else { return }
        positionsSent += 1
        if positionsSent % 40 == 0 {
            sendBasket()
        }
        if Date().timeIntervalSince(lastHeard) > Self.silenceTimeout {
            log.info("Lost the friend's pet")
            NotificationManager.shared.postActivity(AppNotification(type: .pet, title: "\(friend.name)'s pet went home", body: "Lost the connection"))
            close()
            return
        }
        guard let pet = PetWorld.shared.mineState else { return }
        var message: JSONObject = [
            "x": .double(pet.position.x), "y": .double(pet.position.y),
            "a": .string(pet.pose.action.rawValue), "f": .bool(pet.pose.facingRight), "h": .bool(pet.pose.isHappy), "c": .bool(pet.ball), "z": .bool(pet.dizzy),
        ]
        if let bubble = pet.bubble {
            message["b"] = .string(bubble.rawValue)
        }
        // Only what's going on: the head down, a leap, a yawn.
        if pet.pose.headDip > 0 {
            message["d"] = .double((pet.pose.headDip * 100).rounded() / 100)
        }
        if pet.pose.action == .leap {
            message["l"] = .double((pet.pose.flight * 100).rounded() / 100)
            message["t"] = .double(pet.pose.tilt.rounded())
        }
        // Your bowl, while it's out, for their pet to share.
        if let bowl = PetWorld.shared.bowlState {
            message["wx"] = .double(bowl.spot.x)
            message["wy"] = .double(bowl.spot.y)
            message["wf"] = .double((bowl.fill * 100).rounded() / 100)
        }
        if pet.pose.isYawning {
            message["y"] = .bool(true)
        }
        send("pos", message)
    }
}
