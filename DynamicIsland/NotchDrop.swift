import AppKit
import Combine
import OSLog
import Supabase

/// Runs Notch Drop in the Game tab: the falling and the keys, alone or in a duel with a friend.
/// A duel goes over Poke's Supabase project as Realtime messages (nothing is stored): the
/// challenge reaches the friend's own channel, then both join one channel for the match, where
/// each side sends its well a few times a second, the rows it sends, and when it lost.
final class NotchDrop: ObservableObject {
    static let shared = NotchDrop()

    enum Phase: Equatable {
        /// Pick solo, or a friend to challenge.
        case menu
        /// Waiting for the friend to take the challenge, or for the match to start.
        case waiting(String)
        case countdown(Int)
        case playing
        /// Solo only; a duel doesn't stop.
        case paused
        /// `won` is nil for a solo game, or a duel that didn't happen.
        case finished(won: Bool?, reason: String)
    }

    /// A challenge from a friend.
    struct Invite: Equatable, Identifiable {
        let id: String
        let friend: PokeService.Friend
        let seed: UInt64
        let received: Date
    }

    struct Record: Codable, Equatable {
        var wins = 0
        var losses = 0
    }

    enum Key {
        case left, right, down, turn, turnBack, drop, hold, pause
    }

    /// Opens the notch on the Game tab, for a duel starting while it's closed (set by the app).
    var showGame: (() -> Void)?

    @Published private(set) var game = NotchDropGame(seed: 1)
    /// Full rows going away: the well stops for a moment while they flash and shrink.
    @Published private(set) var clearing: Clearing?

    struct Clearing: Equatable {
        let rows: Set<Int>
        /// The well with the full rows still in it.
        let cells: [UInt8]
        let started: Date
    }
    static let clearDuration: TimeInterval = 0.4
    @Published private(set) var phase = Phase.menu
    @Published private(set) var isDuel = false
    @Published private(set) var opponent: PokeService.Friend?
    @Published private(set) var opponentCells: [UInt8] = []
    @Published private(set) var opponentScore = 0
    @Published private(set) var opponentRows = 0
    @Published private(set) var invite: Invite?
    @Published private(set) var best = UserDefaults.standard.integer(forKey: NotchDrop.bestKey)
    /// Duels won and lost, by friend.
    @Published private(set) var records: [UUID: Record] = NotchDrop.loadRecords()

    private static let bestKey = "notchDropBest"
    private static let recordsKey = "notchDropRecords"
    /// How long a resting piece can still be moved before it stays.
    private static let lockDelay: TimeInterval = 0.5
    /// Moving a resting piece starts its delay over, this many times at most.
    private static let lockMoves = 15
    /// How often the well goes to the other player at most.
    private static let stateInterval: TimeInterval = 0.15
    /// A challenge nobody took is called off after this long.
    private static let inviteTimeout: TimeInterval = 60
    /// Without a word from the other player for this long, they're gone.
    private static let silenceTimeout: TimeInterval = 15

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicIsland", category: "Game")
    private var loop: Timer?
    private var lastTick: CFTimeInterval = 0
    private var fallTime: TimeInterval = 0
    private var restTime: TimeInterval = 0
    private var restMoves = 0
    private var countdownTask: Task<Void, Never>?

    // Duel
    private var inbox: RealtimeChannelV2?
    private var inboxUserID: UUID?
    private var inboxTasks: [Task<Void, Never>] = []
    private var match: RealtimeChannelV2?
    private var matchID: String?
    private var matchTasks: [Task<Void, Never>] = []
    private var isHost = false
    private var stateIsDirty = false
    private var lastStateSent: CFTimeInterval = 0
    private var lastHeard = Date()
    private var timeoutTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Challenges can come in while Poke is connected.
        PokeService.shared.$state.combineLatest(PokeService.shared.$profile)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, profile in
                self?.listenForChallenges(userID: state == .ready ? profile?.id : nil)
            }
            .store(in: &cancellables)
    }

    /// While a game runs the open notch stays open: the pointer wandering off doesn't close it.
    var keepsPanelOpen: Bool {
        phase == .playing || phase.isCountdown
    }

    func record(against friend: PokeService.Friend) -> Record {
        records[friend.id] ?? Record()
    }

    // MARK: Solo

    func startSolo() {
        leaveMatch(notify: true)
        isDuel = false
        opponent = nil
        game = NotchDropGame(seed: .random(in: 1...UInt64.max))
        clearing = nil
        startCountdown()
    }

    func pause() {
        guard phase == .playing, !isDuel else { return }
        phase = .paused
        stopLoop()
    }

    func resume() {
        guard phase == .paused else { return }
        startCountdown()
    }

    /// Back to picking a game; a duel going on is given up.
    func backToMenu() {
        if isDuel, phase == .playing || phase.isCountdown {
            finish(won: false, reason: "You left")
        }
        leaveMatch(notify: true)
        countdownTask?.cancel()
        stopLoop()
        isDuel = false
        opponent = nil
        phase = .menu
    }

    // MARK: Keys

    func press(_ key: Key) {
        if key == .pause {
            phase == .paused ? resume() : pause()
            return
        }
        guard phase == .playing, clearing == nil else { return }
        var next = game
        switch key {
        case .left, .right:
            if next.move(by: key == .left ? -1 : 1) { restartRestDelay(next) }
        case .turn, .turnBack:
            if next.turn(clockwise: key == .turn) { restartRestDelay(next) }
        case .down:
            if next.softDrop() { fallTime = 0 }
        case .drop:
            let landing = next.hardDrop()
            game = next
            landed(landing)
            return
        case .hold:
            next.hold()
            fallTime = 0
            restTime = 0
            restMoves = 0
        case .pause:
            break
        }
        update(next)
    }

    /// Moving or turning a resting piece gives it a little more time, up to `lockMoves` times.
    private func restartRestDelay(_ game: NotchDropGame) {
        guard game.isResting, restMoves < Self.lockMoves else { return }
        restTime = 0
        restMoves += 1
    }

    // MARK: Loop

    private func startCountdown() {
        countdownTask?.cancel()
        stopLoop()
        if isDuel {
            showGame?()
        }
        countdownTask = Task { [weak self] in
            for count in [3, 2, 1] {
                self?.phase = .countdown(count)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.phase = .playing
            self?.startLoop()
        }
    }

    private func startLoop() {
        stopLoop()
        lastTick = CACurrentMediaTime()
        fallTime = 0
        restTime = 0
        restMoves = 0
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        loop = timer
    }

    private func stopLoop() {
        loop?.invalidate()
        loop = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = min(now - lastTick, 0.1)
        lastTick = now
        guard phase == .playing else { return }
        if isDuel, stateIsDirty, now - lastStateSent >= Self.stateInterval {
            sendState()
        }
        // Nothing falls while full rows go away.
        if let clearing {
            guard Date().timeIntervalSince(clearing.started) >= Self.clearDuration else { return }
            self.clearing = nil
        }

        var next = game
        fallTime += elapsed
        if fallTime >= next.fallInterval {
            fallTime = 0
            next.fall()
        }
        if next.isResting {
            restTime += elapsed
            if restTime >= Self.lockDelay {
                let landing = next.land()
                game = next
                landed(landing)
                return
            }
        } else {
            restTime = 0
        }
        update(next)
    }

    private func update(_ next: NotchDropGame) {
        guard next != game else { return }
        game = next
        stateIsDirty = true
    }

    /// A piece came to rest: rows go to the other player, and the game may be over.
    private func landed(_ landing: NotchDropGame.Landing) {
        fallTime = 0
        restTime = 0
        restMoves = 0
        stateIsDirty = true
        if !landing.fullRows.isEmpty && !game.isOver {
            clearing = Clearing(rows: Set(landing.fullRows), cells: landing.cellsBeforeClearing, started: Date())
        }
        if isDuel && landing.sentRows > 0 {
            send("attack", ["rows": .integer(landing.sentRows), "gap": .integer(game.nextGap())])
        }
        if isDuel {
            sendState()
        }
        if game.isOver {
            if isDuel {
                send("over", [:])
                finish(won: false, reason: "Your well filled up")
            } else {
                finishSolo()
            }
        }
    }

    private func finishSolo() {
        stopLoop()
        let newBest = game.score > best
        if newBest {
            best = game.score
            UserDefaults.standard.set(best, forKey: Self.bestKey)
        }
        phase = .finished(won: nil, reason: newBest ? "New best: \(game.score)" : "Score \(game.score)")
    }

    // MARK: Duel

    /// Sends the challenge to the friend's channel and waits for them on the match's channel.
    func challenge(_ friend: PokeService.Friend) {
        guard let me = PokeService.shared.profile else { return }
        backToMenu()
        let id = UUID().uuidString.lowercased()
        let seed = UInt64.random(in: 1...UInt64.max)
        guard joinMatch(id: id, seed: seed, friend: friend, isHost: true) else {
            phase = .finished(won: nil, reason: "Poke isn't connected")
            return
        }
        phase = .waiting("Waiting for \(friend.name)…")
        log.info("Challenging a friend to a duel")
        Task {
            await sendToInbox(of: friend.id, event: "invite", [
                "match": .string(id),
                "from": .string(me.id.uuidString.lowercased()),
                "seed": .string(String(seed)),
            ])
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.inviteTimeout))
            guard !Task.isCancelled, let self, self.matchID == id, case .waiting = self.phase else { return }
            await self.sendToInbox(of: friend.id, event: "cancel", ["match": .string(id)])
            self.leaveMatch(notify: false)
            self.phase = .finished(won: nil, reason: "\(friend.name) didn't answer")
        }
    }

    func accept() {
        guard let invite else { return }
        self.invite = nil
        backToMenu()
        guard joinMatch(id: invite.id, seed: invite.seed, friend: invite.friend, isHost: false) else {
            phase = .finished(won: nil, reason: "Poke isn't connected")
            return
        }
        phase = .waiting("Starting…")
        // `join` goes once the channel is joined (see joinMatch). No start within a while: gone.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.matchID == invite.id, case .waiting = self.phase else { return }
            self.leaveMatch(notify: true)
            self.phase = .finished(won: nil, reason: "Couldn't reach \(invite.friend.name)")
        }
    }

    func decline() {
        guard let invite else { return }
        self.invite = nil
        Task {
            guard let channel = PokeService.shared.gameChannel("notch-drop:\(invite.id)") else { return }
            try? await channel.httpSend(event: "decline", message: [:] as JSONObject)
            await PokeService.shared.removeGameChannel(channel)
        }
    }

    /// Joins the match's channel; false while Poke isn't connected.
    private func joinMatch(id: String, seed: UInt64, friend: PokeService.Friend, isHost: Bool) -> Bool {
        guard let channel = PokeService.shared.gameChannel("notch-drop:\(id)") else { return false }
        match = channel
        matchID = id
        self.isHost = isHost
        isDuel = true
        opponent = friend
        opponentCells = Array(repeating: 0, count: NotchDropGame.columns * NotchDropGame.rows)
        opponentScore = 0
        opponentRows = 0
        game = NotchDropGame(seed: seed)
        clearing = nil
        lastHeard = Date()

        for event in ["join", "start", "decline", "state", "attack", "over", "leave"] {
            let stream = channel.broadcastStream(event: event)
            matchTasks.append(Task { [weak self] in
                for await message in stream {
                    self?.received(event, Self.payload(of: message), match: id)
                }
            })
        }
        matchTasks.append(Task { [weak self] in
            do {
                try await channel.subscribeWithError()
                // The challenged side says it's here; the challenger then starts the match.
                if !isHost {
                    await channel.broadcast(event: "join", message: [:] as JSONObject)
                }
            } catch {
                self?.log.error("Couldn't join the duel: \(String(describing: error), privacy: .public)")
            }
        })
        // The other player going quiet means they're gone.
        matchTasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.matchID == id else { return }
                if self.phase == .playing, Date().timeIntervalSince(self.lastHeard) > Self.silenceTimeout {
                    self.finish(won: true, reason: "\(friend.name) is gone")
                }
            }
        })
        return true
    }

    private func received(_ event: String, _ payload: JSONObject, match id: String) {
        guard matchID == id else { return }
        lastHeard = Date()
        let name = opponent?.name ?? "Your friend"
        switch event {
        case "join" where isHost:
            guard case .waiting = phase else { return }
            timeoutTask?.cancel()
            send("start", [:])
            startCountdown()
        case "start" where !isHost:
            guard case .waiting = phase else { return }
            timeoutTask?.cancel()
            startCountdown()
        case "decline":
            guard case .waiting = phase else { return }
            timeoutTask?.cancel()
            leaveMatch(notify: false)
            phase = .finished(won: nil, reason: "\(name) can't play now")
        case "state":
            if let text = payload["cells"]?.stringValue, let cells = NotchDropGame.cells(fromSnapshot: text) {
                opponentCells = cells
            }
            opponentScore = Self.int(payload["score"]) ?? opponentScore
            opponentRows = Self.int(payload["rows"]) ?? opponentRows
        case "attack":
            guard phase == .playing || phase.isCountdown, let rows = Self.int(payload["rows"]), rows > 0 else { return }
            var next = game
            next.receive(rows: min(rows, 4), gap: Self.int(payload["gap"]) ?? 0)
            update(next)
        case "over":
            guard phase == .playing || phase.isCountdown else { return }
            finish(won: true, reason: "\(name)'s well filled up")
        case "leave":
            switch phase {
            case .playing, .countdown:
                finish(won: true, reason: "\(name) left")
            case .waiting:
                timeoutTask?.cancel()
                leaveMatch(notify: false)
                phase = .finished(won: nil, reason: "\(name) left")
            default:
                break
            }
        default:
            break
        }
    }

    private func finish(won: Bool, reason: String) {
        countdownTask?.cancel()
        stopLoop()
        if let opponent {
            var record = records[opponent.id] ?? Record()
            if won { record.wins += 1 } else { record.losses += 1 }
            records[opponent.id] = record
            saveRecords()
        }
        phase = .finished(won: won, reason: reason)
        log.info("Duel over: \(won ? "won" : "lost", privacy: .public)")
        // Let the last messages go, then leave the match.
        let id = matchID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.matchID == id else { return }
            self.leaveMatch(notify: false)
        }
    }

    private func sendState() {
        stateIsDirty = false
        lastStateSent = CACurrentMediaTime()
        send("state", [
            "cells": .string(game.snapshot),
            "score": .integer(game.score),
            "rows": .integer(game.clearedRows),
        ])
    }

    private func send(_ event: String, _ message: JSONObject) {
        guard let match else { return }
        Task { await match.broadcast(event: event, message: message) }
    }

    /// Leaves the match's channel, first telling the other player when `notify`.
    private func leaveMatch(notify: Bool) {
        timeoutTask?.cancel()
        matchTasks.forEach { $0.cancel() }
        matchTasks = []
        guard let channel = match else { return }
        match = nil
        matchID = nil
        Task {
            if notify && channel.status == .subscribed {
                await channel.broadcast(event: "leave", message: [:] as JSONObject)
            }
            await PokeService.shared.removeGameChannel(channel)
        }
    }

    // MARK: Challenges

    /// Each player's own channel, where friends' challenges arrive.
    private func listenForChallenges(userID: UUID?) {
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
                    self?.receivedChallenge(event, Self.payload(of: message))
                }
            })
        }
        inboxTasks.append(Task { [weak self] in
            do {
                try await channel.subscribeWithError()
            } catch {
                self?.log.error("Couldn't listen for duels: \(String(describing: error), privacy: .public)")
            }
        })
    }

    private func receivedChallenge(_ event: String, _ payload: JSONObject) {
        guard let id = payload["match"]?.stringValue, UUID(uuidString: id) != nil else { return }
        switch event {
        case "invite":
            // Only friends can challenge, by the name you know them by.
            guard let from = payload["from"]?.stringValue.flatMap(UUID.init(uuidString:)),
                  let friend = PokeService.shared.friends.first(where: { $0.id == from }),
                  let seed = payload["seed"]?.stringValue.flatMap(UInt64.init) else { return }
            invite = Invite(id: id, friend: friend, seed: seed, received: Date())
            log.info("A friend challenged you to a duel")
            let notification = AppNotification(type: .game, title: "\(friend.name) challenges you", body: "Notch Drop duel", actionTitle: "Play")
            NotificationManager.shared.postActivity(notification)
            // A challenge nobody took goes away with the challenger's.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.inviteTimeout + 5))
                if self?.invite?.id == id { self?.invite = nil }
            }
        case "cancel":
            if invite?.id == id { invite = nil }
        default:
            break
        }
    }

    /// To a friend's own channel, over HTTP: without joining it, so their other challenges stay theirs.
    private func sendToInbox(of friendID: UUID, event: String, _ message: JSONObject) async {
        guard let channel = PokeService.shared.gameChannel(Self.inboxTopic(friendID)) else { return }
        do {
            try await channel.httpSend(event: event, message: message)
        } catch {
            // Over the socket instead, joining the channel for a moment.
            log.error("Couldn't send a duel message over HTTP, trying the socket: \(String(describing: error), privacy: .public)")
            do {
                try await channel.subscribeWithError()
                await channel.broadcast(event: event, message: message)
                try? await Task.sleep(for: .milliseconds(500))
            } catch {
                log.error("Couldn't send a duel message: \(String(describing: error), privacy: .public)")
            }
        }
        await PokeService.shared.removeGameChannel(channel)
    }

    private static func inboxTopic(_ userID: UUID) -> String {
        "notch-drop-inbox:\(userID.uuidString.lowercased())"
    }

    // MARK: Helpers

    /// A broadcast arrives wrapped with its event; the message is under `payload`.
    private static func payload(of message: JSONObject) -> JSONObject {
        message["payload"]?.objectValue ?? message
    }

    private static func int(_ value: AnyJSON?) -> Int? {
        value?.intValue ?? value?.doubleValue.map { Int($0) }
    }

    private static func loadRecords() -> [UUID: Record] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let saved = try? JSONDecoder().decode([String: Record].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    private func saveRecords() {
        let saved = Dictionary(uniqueKeysWithValues: records.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.recordsKey)
        }
    }
}

extension NotchDrop.Phase {
    var isCountdown: Bool {
        if case .countdown = self { return true }
        return false
    }
}
