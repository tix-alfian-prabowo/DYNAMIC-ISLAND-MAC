import AppKit
import Combine
import OSLog
import Supabase

/// Runs Notch Rush in the Game tab: the race against the clock alone, or against a friend. In a
/// duel both drive the same road (same seed), each seeing the other's car as a ghost; the first
/// over the line wins. It goes over a DuelMatch: positions a few times a second, then the finish.
final class NotchRush: ObservableObject {
    static let shared = NotchRush()

    enum Phase: Equatable {
        case menu
        case waiting(String)
        case countdown(Int)
        case racing
        /// Solo only; a duel doesn't stop.
        case paused
        /// `won` is nil for a solo race, or a duel that didn't happen.
        case finished(won: Bool?, reason: String)

        var isCountdown: Bool {
            if case .countdown = self { return true }
            return false
        }
    }

    struct Record: Codable, Equatable {
        var wins = 0
        var losses = 0
    }

    enum Key {
        case gas, brake, left, right, boost, pause
    }

    /// Opens the notch on the Game tab, for a duel starting while it's closed (set by the app).
    var showGame: (() -> Void)?

    @Published private(set) var race = NotchRushRace(seed: 1)
    @Published private(set) var phase = Phase.menu {
        didSet { GameLibrary.updatePlaying() }
    }
    @Published private(set) var isDuel = false
    @Published private(set) var opponent: PokeService.Friend?
    @Published private(set) var opponentDistance: Double = 0
    @Published private(set) var opponentLane: Double = 1
    @Published private(set) var opponentSpeed: Double = 0
    /// Where the other car is drawn: carried on at its speed between their updates, so it glides
    /// instead of jumping a few meters at a time.
    @Published private(set) var opponentShownDistance: Double = 0
    @Published private(set) var opponentShownLane: Double = 1
    /// The best solo time, in seconds.
    @Published private(set) var best: Double? = UserDefaults.standard.object(forKey: NotchRush.bestKey) as? Double
    @Published private(set) var records: [UUID: Record] = NotchRush.loadRecords()

    private static let bestKey = "notchRushBest"
    private static let recordsKey = "notchRushRecords"
    /// How often the car's place goes to the other player.
    private static let positionInterval: TimeInterval = 0.12
    private static let silenceTimeout: TimeInterval = 15

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicIsland", category: "Game")
    private var loop: Timer?
    private var lastTick: CFTimeInterval = 0
    private var lastPositionSent: CFTimeInterval = 0
    private var held: Set<Key> = []
    private var countdownTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var match: DuelMatch?
    private var opponentFinishTime: Double?
    private var opponentHeardAt: CFTimeInterval = 0

    private init() {}

    var keepsPanelOpen: Bool {
        phase == .racing || phase.isCountdown
    }

    func record(against friend: PokeService.Friend) -> Record {
        records[friend.id] ?? Record()
    }

    // MARK: Solo

    func startSolo() {
        leaveMatch(notify: true)
        isDuel = false
        opponent = nil
        race = NotchRushRace(seed: .random(in: 1...UInt64.max))
        startCountdown()
    }

    func pause() {
        guard phase == .racing, !isDuel else { return }
        phase = .paused
        stopLoop()
    }

    func resume() {
        guard phase == .paused else { return }
        startCountdown()
    }

    /// Back to the menu; a duel going on is given up.
    func backToMenu() {
        if isDuel, phase == .racing || phase.isCountdown {
            match?.send("finish", ["gave_up": .bool(true)])
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

    /// Pedals and the wheel work while held; pause toggles.
    func keyDown(_ key: Key) {
        if key == .pause {
            phase == .paused ? resume() : pause()
        } else {
            held.insert(key)
        }
    }

    func keyUp(_ key: Key) {
        held.remove(key)
    }

    /// Lets go of everything, when the keys go elsewhere.
    func releaseKeys() {
        held.removeAll()
    }

    // MARK: Loop

    private func startCountdown() {
        countdownTask?.cancel()
        stopLoop()
        held.removeAll()
        if isDuel {
            showGame?()
        }
        countdownTask = Task { [weak self] in
            for count in [3, 2, 1] {
                self?.phase = .countdown(count)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.phase = .racing
            self?.startLoop()
        }
    }

    private func startLoop() {
        stopLoop()
        lastTick = CACurrentMediaTime()
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
        let elapsed = min(now - lastTick, 0.05)
        lastTick = now
        guard phase == .racing else { return }
        let steering = (held.contains(.right) ? 1.0 : 0) - (held.contains(.left) ? 1.0 : 0)
        race.step(elapsed, gas: held.contains(.gas), braking: held.contains(.brake), boosting: held.contains(.boost), steering: steering)
        if isDuel {
            let ahead = opponentDistance + opponentSpeed * min(now - opponentHeardAt, 0.3)
            opponentShownDistance = min(max(ahead, opponentShownDistance), NotchRushRace.length)
            opponentShownLane += (opponentLane - opponentShownLane) * min(elapsed * 12, 1)
        }

        if isDuel, let match {
            if now - lastPositionSent >= Self.positionInterval {
                lastPositionSent = now
                match.send("pos", [
                    "d": .double(race.distance),
                    "l": .double(race.lanePosition),
                    "s": .double(race.speed),
                ])
            }
            if Date().timeIntervalSince(match.lastHeard) > Self.silenceTimeout {
                finish(won: true, reason: "\(match.friend.name) is gone")
                return
            }
        }

        if let time = race.finishTime {
            crossedLine(at: time)
        }
    }

    private func crossedLine(at time: Double) {
        if isDuel {
            match?.send("finish", ["t": .double(time)])
            // They finished first only if their time is better (both clocks start together).
            if let theirs = opponentFinishTime, theirs < time {
                finish(won: false, reason: "\(opponent?.name ?? "Your friend") finished first")
            } else {
                finish(won: true, reason: "Finished in \(Self.format(time))")
            }
        } else {
            stopLoop()
            let isBest = best.map { time < $0 } ?? true
            if isBest {
                best = time
                UserDefaults.standard.set(time, forKey: Self.bestKey)
            }
            phase = .finished(won: nil, reason: isBest ? "New best: \(Self.format(time))" : "Time \(Self.format(time))")
        }
    }

    // MARK: Duel

    func challenge(_ friend: PokeService.Friend) {
        guard PokeService.shared.profile != nil else { return }
        backToMenu()
        let id = UUID().uuidString.lowercased()
        let seed = UInt64.random(in: 1...UInt64.max)
        guard join(id: id, seed: seed, friend: friend, isHost: true) else {
            phase = .finished(won: nil, reason: "Poke isn't connected")
            return
        }
        phase = .waiting("Waiting for \(friend.name)…")
        GameInvites.shared.challenge(friend, to: .notchRush, match: id, seed: seed)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GameInvites.timeout))
            guard !Task.isCancelled, let self, self.match?.id == id, case .waiting = self.phase else { return }
            GameInvites.shared.cancelChallenge(match: id, to: friend)
            self.leaveMatch(notify: false)
            self.phase = .finished(won: nil, reason: "\(friend.name) didn't answer")
        }
    }

    /// Joins a friend's challenge (see GameInvites.accept).
    func accept(_ invite: GameInvites.Invite) {
        backToMenu()
        guard join(id: invite.id, seed: invite.seed, friend: invite.friend, isHost: false) else {
            phase = .finished(won: nil, reason: "Poke isn't connected")
            return
        }
        phase = .waiting("Starting…")
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.match?.id == invite.id, case .waiting = self.phase else { return }
            self.leaveMatch(notify: true)
            self.phase = .finished(won: nil, reason: "Couldn't reach \(invite.friend.name)")
        }
    }

    private func join(id: String, seed: UInt64, friend: PokeService.Friend, isHost: Bool) -> Bool {
        guard let match = DuelMatch(game: .notchRush, id: id, friend: friend, isHost: isHost, events: ["pos", "finish"],
                                    onEvent: { [weak self] event, payload in
                                        MainActor.assumeIsolated { self?.received(event, payload, match: id) }
                                    }) else { return false }
        self.match = match
        isDuel = true
        opponent = friend
        opponentDistance = 0
        opponentLane = 1
        opponentSpeed = 0
        opponentShownDistance = 0
        opponentShownLane = 1
        opponentFinishTime = nil
        race = NotchRushRace(seed: seed)
        return true
    }

    private func received(_ event: String, _ payload: JSONObject, match id: String) {
        guard let match, match.id == id else { return }
        let name = match.friend.name
        switch event {
        case "join" where match.isHost:
            guard case .waiting = phase else { return }
            timeoutTask?.cancel()
            match.send("start")
            startCountdown()
        case "start" where !match.isHost:
            guard case .waiting = phase else { return }
            timeoutTask?.cancel()
            startCountdown()
        case "decline":
            guard case .waiting = phase else { return }
            timeoutTask?.cancel()
            leaveMatch(notify: false)
            phase = .finished(won: nil, reason: "\(name) can't play now")
        case "pos":
            opponentDistance = GameMessage.double(payload["d"]) ?? opponentDistance
            opponentLane = GameMessage.double(payload["l"]) ?? opponentLane
            opponentSpeed = GameMessage.double(payload["s"]) ?? opponentSpeed
            opponentHeardAt = CACurrentMediaTime()
        case "finish":
            if payload["gave_up"]?.boolValue == true {
                guard phase == .racing || phase.isCountdown else { return }
                finish(won: true, reason: "\(name) left")
                return
            }
            guard let time = GameMessage.double(payload["t"]) else { return }
            opponentFinishTime = time
            opponentDistance = NotchRushRace.length
            opponentShownDistance = NotchRushRace.length
            if phase == .racing || phase.isCountdown {
                finish(won: false, reason: "\(name) finished first")
            }
        case "leave":
            switch phase {
            case .racing, .countdown:
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
        log.info("Race over: \(won ? "won" : "lost", privacy: .public)")
        // Let the last messages go, then leave the match.
        let id = match?.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.match?.id == id else { return }
            self.leaveMatch(notify: false)
        }
    }

    private func leaveMatch(notify: Bool) {
        timeoutTask?.cancel()
        match?.leave(notify: notify)
        match = nil
    }

    // MARK: Helpers

    /// "1:02.4".
    static func format(_ time: Double) -> String {
        let tenths = Int((time * 10).rounded(.down))
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
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
