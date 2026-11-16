import Foundation

/// Notch Rush, the Game tab's race: a car on a winding three-lane road at night, weaving through
/// traffic to the finish. Only the rules live here: the controller steps it 60 times a second. The
/// bends, traffic and boost pickups come from the seed and traffic moves with the race's clock, so
/// in a duel both players drive the same road.
nonisolated struct NotchRushRace: Equatable, Sendable {
    static let length: Double = 3500
    static let lanes = 3
    static let carLength: Double = 4.6
    /// Top speed without boost, and with it (m/s).
    static let cruiseSpeed: Double = 52
    static let boostSpeed: Double = 72
    /// How long a crash slows the car.
    static let crashTime: Double = 0.7
    /// Lanes a second the wheel moves the car across the road at speed.
    static let steerRate: Double = 2.8
    /// How hard a bend pushes the car to its outside.
    static let drift: Double = 0.09
    /// Off the lanes, on the shoulder, the car can't go faster than this.
    static let shoulderSpeed: Double = 30

    struct Traffic: Equatable, Sendable {
        let lane: Int
        /// Where it is when the race starts; it drives on at its lane's speed.
        let start: Double
        let speed: Double
        /// Which car it is: 0…3 sedans in different colors, 4 a van.
        let style: UInt8
    }

    struct Pickup: Equatable, Sendable {
        let lane: Int
        let position: Double
    }

    /// A bend: it tightens in, holds, and opens out again. `sharpness` is its curvature at the
    /// tightest (1/m): positive bends right, negative left.
    struct Bend: Equatable, Sendable {
        let start: Double
        let length: Double
        let sharpness: Double
    }

    let traffic: [Traffic]
    let pickups: [Pickup]
    let bends: [Bend]

    private(set) var time: Double = 0
    private(set) var distance: Double = 0
    private(set) var speed: Double = 0
    /// Where the car is across the road, in lanes: 0…2 on the lanes, a little past either on the
    /// shoulder.
    private(set) var lanePosition: Double = 1
    /// The wheel, -1 (left) … 1 (right).
    private(set) var steering: Double = 0
    /// Which way the road has turned since the start (radians, right positive).
    private(set) var heading: Double = 0
    /// Boost left, 0…1: it runs down while boosting and fills slowly, faster from pickups.
    private(set) var boost: Double = 0.5
    private(set) var isBoosting = false
    private(set) var isBraking = false
    /// When the car last hit another (race time).
    private(set) var lastCrash: Double?
    private(set) var hitCars: Set<Int> = []
    private(set) var takenPickups: Set<Int> = []
    private(set) var finishTime: Double?

    var isFinished: Bool { finishTime != nil }
    var progress: Double { min(distance / Self.length, 1) }
    var isStunned: Bool { lastCrash.map { time - $0 < Self.crashTime } ?? false }

    init(seed: UInt64) {
        var random = RushRandom(seed: seed)
        let laneSpeeds: [Double] = [24, 30, 36]
        var traffic: [Traffic] = []
        var position = 110.0
        while position < Self.length {
            let lane = Int(random.next() % 3)
            traffic.append(Traffic(lane: lane, start: position, speed: laneSpeeds[lane], style: UInt8(random.next() % 5)))
            // Now and then a second car beside it; one lane always stays open.
            if random.next() % 4 == 0 {
                let other = (lane + 1 + Int(random.next() % 2)) % 3
                traffic.append(Traffic(lane: other, start: position + Double(random.next() % 8), speed: laneSpeeds[other],
                                       style: UInt8(random.next() % 5)))
            }
            position += 30 + Double(random.next() % 45)
        }
        self.traffic = traffic

        var pickups: [Pickup] = []
        var spot = 260.0
        while spot < Self.length - 150 {
            pickups.append(Pickup(lane: Int(random.next() % 3), position: spot))
            spot += 220 + Double(random.next() % 160)
        }
        self.pickups = pickups

        var bends: [Bend] = []
        var at = 180.0
        var right = random.next() % 2 == 0
        while at < Self.length - 250 {
            let length = 200 + Double(random.next() % 180)
            let sharpness = 0.0026 + Double(random.next() % 30) / 10_000
            bends.append(Bend(start: at, length: length, sharpness: right ? sharpness : -sharpness))
            // Mostly the other way next, now and then the same way again.
            if random.next() % 3 != 0 { right.toggle() }
            at += length + 90 + Double(random.next() % 200)
        }
        self.bends = bends
    }

    /// How sharply the road bends at a place (1/m, right positive).
    func curvature(at place: Double) -> Double {
        for bend in bends where place >= bend.start && place < bend.start + bend.length {
            let along = (place - bend.start) / bend.length
            // In over the first quarter, out over the last.
            let ramp = min(along / 0.25, (1 - along) / 0.25, 1)
            return bend.sharpness * ramp * ramp * (3 - 2 * ramp)
        }
        return 0
    }

    func position(of car: Int) -> Double {
        traffic[car].start + traffic[car].speed * time
    }

    /// `gas` and `braking` are the pedals, `steering` the wheel (-1 left … 1 right); boosting
    /// needs no gas.
    mutating func step(_ elapsed: Double, gas: Bool, braking: Bool, boosting: Bool, steering: Double) {
        guard !isFinished else { return }
        time += elapsed
        isBraking = braking
        self.steering = steering
        isBoosting = boosting && boost > 0.02 && !isStunned && !braking
        if isBoosting {
            boost = max(0, boost - 0.3 * elapsed)
        } else {
            boost = min(1, boost + 0.025 * elapsed)
        }

        let onShoulder = lanePosition < -0.05 || lanePosition > Double(Self.lanes - 1) + 0.05
        var target = braking ? 0 : isBoosting ? Self.boostSpeed : gas ? Self.cruiseSpeed : 0
        if onShoulder { target = min(target, Self.shoulderSpeed) }
        if speed < target {
            let push: Double = isBoosting ? 22 : isStunned ? 6 : 14
            speed = min(target, speed + push * elapsed)
        } else {
            // Braking stops it fast, the shoulder slower, letting go of the gas slowest.
            let slowing: Double = braking ? 38 : onShoulder ? 24 : 9
            speed = max(target, speed - slowing * elapsed)
        }
        distance += speed * elapsed

        // The wheel moves the car across, more the faster it goes; a bend pushes it outward.
        let bend = curvature(at: distance)
        heading += bend * speed * elapsed
        let grip = min(speed / 20, 1)
        lanePosition += (steering * Self.steerRate * grip - bend * speed * speed * Self.drift) * elapsed
        lanePosition = min(max(lanePosition, -0.4), Double(Self.lanes - 1) + 0.4)

        for car in traffic.indices where !hitCars.contains(car) {
            let gap = position(of: car) - distance
            guard abs(gap) < Self.carLength * 0.92, abs(Double(traffic[car].lane) - lanePosition) < 0.55 else { continue }
            hitCars.insert(car)
            lastCrash = time
            speed = min(speed, traffic[car].speed * 0.55)
        }
        for index in pickups.indices where !takenPickups.contains(index) {
            guard abs(pickups[index].position - distance) < 3, abs(Double(pickups[index].lane) - lanePosition) < 0.5 else { continue }
            takenPickups.insert(index)
            boost = min(1, boost + 0.4)
        }

        if distance >= Self.length {
            distance = Self.length
            finishTime = time
        }
    }
}

/// SplitMix64: the same seed gives the same road on every Mac.
private nonisolated struct RushRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
