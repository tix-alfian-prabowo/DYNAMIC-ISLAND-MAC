import SwiftUI

// Notch Rush's look: a road through a city at night, seen from just behind the car, heading for the
// horizon. Only plain values go in, so it can be drawn on its own.

/// The player's car: the one accent color.
let rushAccent = Color(red: 1, green: 0.42, blue: 0.66)

private let trafficColors: [Color] = [
    Color(red: 0.42, green: 0.50, blue: 0.62),
    Color(red: 0.30, green: 0.55, blue: 0.56),
    Color(red: 0.72, green: 0.64, blue: 0.50),
    Color(red: 0.60, green: 0.60, blue: 0.63),
    Color(red: 0.80, green: 0.80, blue: 0.82),
]

/// The other player in a duel, drawn as a ghost on your road.
struct RushGhost: Equatable {
    var distance: Double
    var lanePosition: Double
    var name: String
}

struct RushScene: View {
    let race: NotchRushRace
    var ghost: RushGhost?

    var body: some View {
        Canvas { context, size in
            RushPainter(race: race, ghost: ghost, size: size).paint(&context)
        }
    }
}

/// The road from just behind the car, looking ahead: it narrows to the horizon, and everything on
/// it grows as the car comes up to it.
private struct RushPainter {
    let race: NotchRushRace
    let ghost: RushGhost?
    let size: CGSize

    /// Lanes are 3.6 m wide; the camera rides 2.4 m up, 6.5 m behind the car, and looks 160 m ahead.
    static let laneWidth = 3.6
    static let cameraHeight = 2.4
    static let cameraBehind = 6.5
    static let farthest = 160.0

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    var horizon: CGFloat { height * 0.36 }
    /// Points per meter one meter ahead.
    var focal: Double { Double(width) * 0.42 }
    var playerX: Double { (race.lanePosition - 1) * Self.laneWidth }
    /// The camera follows the car between lanes, a little behind.
    var cameraX: Double { playerX * 0.75 }
    /// Where the camera is along the road.
    var cameraAt: Double { race.distance - Self.cameraBehind }

    /// How far the road has bent sideways, every `bendStep` meters ahead of the camera.
    let bendOffsets: [Double]
    static let bendStep = 2.0

    init(race: NotchRushRace, ghost: RushGhost?, size: CGSize) {
        self.race = race
        self.ghost = ghost
        self.size = size
        // Add up the bends ahead: each meter turns the road a little more, which moves it across.
        var offsets: [Double] = [0]
        var slope = 0.0, offset = 0.0
        var ahead = 0.0
        let from = race.distance - Self.cameraBehind
        while ahead < Self.farthest + Self.bendStep {
            // Drawn sharper than they drive, so a bend reads at a glance.
            slope += race.curvature(at: from + ahead + Self.bendStep / 2) * Self.bendStep * 2.6
            offset += slope * Self.bendStep
            ahead += Self.bendStep
            offsets.append(offset)
        }
        bendOffsets = offsets
    }

    /// How far the road has bent sideways `ahead` meters in front of the camera.
    func sideways(_ ahead: Double) -> Double {
        let place = max(ahead, 0) / Self.bendStep
        let index = min(Int(place), bendOffsets.count - 2)
        let fraction = min(place - Double(index), 1)
        return bendOffsets[index] + (bendOffsets[index + 1] - bendOffsets[index]) * fraction
    }

    /// How far the sky has turned past, in points: the road turning right swings it left.
    var skyTurn: CGFloat { CGFloat(race.heading) * width * 0.7 }

    /// A point on the road, `ahead` meters in front of the camera and `side` meters across it,
    /// `up` meters above the road.
    func point(ahead: Double, side: Double, up: Double = 0) -> CGPoint {
        let ahead = max(ahead, 0.3)
        return CGPoint(x: width / 2 + CGFloat((side + sideways(ahead) - cameraX) * focal / ahead),
                       y: horizon + CGFloat((Self.cameraHeight - up) * focal / ahead))
    }

    func pointsPerMeter(_ ahead: Double) -> CGFloat {
        CGFloat(focal / max(ahead, 0.3))
    }

    /// Far things fade into the night.
    func fade(_ ahead: Double) -> Double {
        min(max((Self.farthest - ahead) / 45, 0), 1)
    }

    var crashAge: Double? {
        guard let crash = race.lastCrash else { return nil }
        let age = race.time - crash
        return age < 0.5 ? age : nil
    }

    func paint(_ context: inout GraphicsContext) {
        if let age = crashAge {
            context.translateBy(x: CGFloat(sin(age * 90) * 3 * (1 - age / 0.5)), y: CGFloat(cos(age * 70) * 1.5 * (1 - age / 0.5)))
        }
        sky(&context)
        skyline(&context)
        ground(&context)
        road(&context)
        finish(&context)
        headlightBeam(&context)
        things(&context)
        speedLines(&context)
    }

    // MARK: Far away

    private func sky(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: -10, y: -10, width: width + 20, height: horizon + 10)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.02, green: 0.025, blue: 0.055), Color(red: 0.09, green: 0.08, blue: 0.14)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        for index in 0..<45 {
            let seed = hash(index, 9)
            let starX = CGFloat(seed % 10_000) / 10_000 * width
            let starY = CGFloat((seed / 10_000) % 1000) / 1000 * horizon * 0.75
            let twinkle = 0.25 + 0.35 * (0.5 + 0.5 * sin(race.time * 1.7 + Double(index)))
            context.fill(Path(ellipseIn: CGRect(x: starX, y: starY, width: 1.2, height: 1.2)), with: .color(.white.opacity(twinkle)))
        }
        // The moon wanders across as the road turns, coming round again from the other side.
        let round = width * 1.6
        var moonX = (width * 0.8 - skyTurn).truncatingRemainder(dividingBy: round)
        if moonX < -width * 0.3 { moonX += round }
        let moon = CGRect(x: moonX, y: horizon * 0.16, width: horizon * 0.3, height: horizon * 0.3)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .white.opacity(0.5), radius: 10))
            layer.fill(Path(ellipseIn: moon), with: .color(Color(white: 0.92)))
        }
        context.fill(Path(ellipseIn: moon.offsetBy(dx: moon.width * 0.28, dy: -moon.height * 0.08)),
                     with: .color(Color(red: 0.035, green: 0.04, blue: 0.075)))
    }

    /// The city on the horizon, shifting as the road bends.
    private func skyline(_ context: inout GraphicsContext) {
        let shift = -skyTurn
        for layer in 0..<2 {
            let slot: CGFloat = layer == 0 ? 22 : 34
            let color = layer == 0 ? Color(red: 0.09, green: 0.09, blue: 0.145) : Color(red: 0.055, green: 0.06, blue: 0.095)
            let tallest = horizon * (layer == 0 ? 0.42 : 0.6)
            let offset = shift * (layer == 0 ? 0.6 : 1)
            let first = Int(((-offset - 40) / slot).rounded(.down))
            for index in first...(first + Int(width / slot) + 4) {
                let seed = hash(index, layer + 1)
                // Lower toward the middle, where the road leads, taller at the sides.
                let left = CGFloat(index) * slot + offset
                let fromMiddle = abs(left + slot / 2 - width / 2) / (width / 2)
                let buildingHeight = tallest * (0.3 + 0.7 * CGFloat((seed / 30) % 100) / 100) * (0.55 + 0.45 * min(fromMiddle, 1))
                let buildingWidth = slot * (0.75 + CGFloat(seed % 30) / 100)
                let rect = CGRect(x: left, y: horizon - buildingHeight, width: buildingWidth, height: buildingHeight)
                context.fill(Path(rect), with: .color(color))
                let columns = Int(buildingWidth / 4.5), rows = Int(buildingHeight / 5.5)
                guard columns > 0, rows > 0 else { continue }
                for row in 0..<rows {
                    for column in 0..<columns where hash(index * 131 + row * 17 + column, layer + 7) % 1000 < 150 {
                        context.fill(Path(CGRect(x: rect.minX + 1.5 + CGFloat(column) * 4.5, y: rect.minY + 2.5 + CGFloat(row) * 5.5, width: 1.6, height: 2)),
                                     with: .color(Color(red: 1, green: 0.84, blue: 0.55).opacity(layer == 0 ? 0.25 : 0.38)))
                    }
                }
            }
        }
        // A glow of city light along the horizon.
        context.fill(Path(CGRect(x: 0, y: horizon - 18, width: width, height: 22)),
                     with: .linearGradient(Gradient(colors: [.clear, Color(red: 1, green: 0.6, blue: 0.5).opacity(0.08)]),
                                           startPoint: CGPoint(x: 0, y: horizon - 18), endPoint: CGPoint(x: 0, y: horizon + 4)))
    }

    // MARK: Road

    private func ground(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: -10, y: horizon, width: width + 20, height: height - horizon + 10)), with: .color(Color(red: 0.035, green: 0.04, blue: 0.05)))
    }

    /// Bands 6 m long from far to near: the asphalt alternates a shade, the curbs a stripe, and the
    /// lines between lanes are painted on every other band. Their rushing past is the speed.
    private func road(_ context: inout GraphicsContext) {
        let band = 6.0
        let half = Self.laneWidth * 1.5
        let first = ((cameraAt + 1) / band).rounded(.down)
        var bands: [Double] = []
        var start = first * band
        while start - cameraAt < Self.farthest {
            bands.append(start)
            start += band
        }
        for start in bands.reversed() {
            let near = max(start - cameraAt, 1), far = start + band - cameraAt
            guard far > 1 else { continue }
            let index = Int((start / band).rounded())
            let alpha = fade(near)
            // Ground beside the road.
            quad(&context, near: near, far: far, from: -half - 40, to: half + 40,
                 color: Color(white: index % 2 == 0 ? 0.05 : 0.065).opacity(alpha))
            // Asphalt.
            quad(&context, near: near, far: far, from: -half, to: half,
                 color: Color(white: index % 2 == 0 ? 0.115 : 0.135).opacity(alpha))
            // Curbs.
            for side in [-1.0, 1.0] {
                let inner = side * half, outer = side * (half + 0.45)
                quad(&context, near: near, far: far, from: min(inner, outer), to: max(inner, outer),
                     color: Color(white: index % 2 == 0 ? 0.85 : 0.3).opacity(alpha * 0.8))
            }
            // Lane lines, 3 m of paint every other band.
            if index % 2 == 0 {
                for line in [-0.5, 0.5] {
                    let lineX = line * Self.laneWidth
                    quad(&context, near: near, far: min(far, start + 3 - cameraAt), from: lineX - 0.07, to: lineX + 0.07,
                         color: .white.opacity(0.55 * alpha))
                }
            }
        }
        // Haze where the road meets the sky.
        context.fill(Path(CGRect(x: 0, y: horizon - 2, width: width, height: 16)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.09, green: 0.08, blue: 0.14), .clear]),
                                           startPoint: CGPoint(x: 0, y: horizon - 2), endPoint: CGPoint(x: 0, y: horizon + 14)))
    }

    /// A piece of road between two distances ahead and two places across.
    private func quad(_ context: inout GraphicsContext, near: Double, far: Double, from left: Double, to right: Double, color: Color) {
        guard far > near else { return }
        var path = Path()
        path.move(to: point(ahead: near, side: left))
        path.addLine(to: point(ahead: near, side: right))
        path.addLine(to: point(ahead: far, side: right))
        path.addLine(to: point(ahead: far, side: left))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func finish(_ context: inout GraphicsContext) {
        let ahead = NotchRushRace.length - cameraAt
        guard ahead > 1, ahead < Self.farthest else { return }
        let half = Self.laneWidth * 1.5
        let cell = half * 2 / 10
        for row in 0..<2 {
            for column in 0..<10 {
                let near = ahead + Double(row) * 1.2
                quad(&context, near: near, far: near + 1.2, from: -half + Double(column) * cell, to: -half + Double(column + 1) * cell,
                     color: .white.opacity((row + column) % 2 == 0 ? 0.85 * fade(ahead) : 0.08))
            }
        }
        // An arch over the road.
        let poleHeight = 6.0
        for side in [-half - 1, half + 1] {
            var pole = Path()
            pole.move(to: point(ahead: ahead, side: side))
            pole.addLine(to: point(ahead: ahead, side: side, up: poleHeight))
            context.stroke(pole, with: .color(.white.opacity(0.7 * fade(ahead))), lineWidth: max(pointsPerMeter(ahead) * 0.25, 1))
        }
        let left = point(ahead: ahead, side: -half - 1, up: poleHeight), right = point(ahead: ahead, side: half + 1, up: poleHeight - 1)
        let banner = CGRect(x: left.x, y: left.y, width: right.x - left.x, height: right.y - left.y)
        context.fill(Path(banner), with: .color(.white.opacity(0.85 * fade(ahead))))
        if banner.height > 6 {
            context.draw(Text("FINISH").font(.system(size: banner.height * 0.6, weight: .heavy, design: .rounded)).foregroundColor(.black),
                         at: CGPoint(x: banner.midX, y: banner.midY))
        }
    }

    private func headlightBeam(_ context: inout GraphicsContext) {
        var beam = Path()
        // The beam points where the car points: along the road, swung by the wheel.
        let swing = race.steering * 4
        beam.move(to: point(ahead: Self.cameraBehind + 1.5, side: playerX - 0.8))
        beam.addLine(to: point(ahead: Self.cameraBehind + 1.5, side: playerX + 0.8))
        beam.addLine(to: point(ahead: Self.cameraBehind + 40, side: playerX + 3 + swing - sideways(Self.cameraBehind + 40)))
        beam.addLine(to: point(ahead: Self.cameraBehind + 40, side: playerX - 3 + swing - sideways(Self.cameraBehind + 40)))
        beam.closeSubpath()
        let near = point(ahead: Self.cameraBehind + 1.5, side: playerX), far = point(ahead: Self.cameraBehind + 40, side: playerX)
        context.fill(beam, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.82).opacity(0.13), .clear]),
                                                 startPoint: near, endPoint: far))
    }

    // MARK: On the road

    private enum Thing {
        case traffic(Int)
        case pickup(Int)
        case light(Double, Double)
        case ghost
        case player
    }

    /// Everything standing on the road or beside it, drawn from far to near.
    private func things(_ context: inout GraphicsContext) {
        var items: [(ahead: Double, thing: Thing)] = []
        for index in race.traffic.indices {
            let ahead = race.position(of: index) - cameraAt
            if ahead > 1.5, ahead < Self.farthest { items.append((ahead, .traffic(index))) }
        }
        for (index, pickup) in race.pickups.enumerated() where !race.takenPickups.contains(index) {
            let ahead = pickup.position - cameraAt
            if ahead > 1.5, ahead < Self.farthest { items.append((ahead, .pickup(index))) }
        }
        let spacing = 32.0
        var lamp = ((cameraAt + 2) / spacing).rounded(.up) * spacing
        while lamp - cameraAt < Self.farthest {
            items.append((lamp - cameraAt, .light(lamp, -1)))
            items.append((lamp - cameraAt, .light(lamp, 1)))
            lamp += spacing
        }
        if let ghost {
            let ahead = ghost.distance - cameraAt
            if ahead > 1.5, ahead < Self.farthest { items.append((ahead, .ghost)) }
        }
        items.append((Self.cameraBehind, .player))

        for item in items.sorted(by: { $0.ahead > $1.ahead }) {
            let ahead = item.ahead
            switch item.thing {
            case .traffic(let index):
                let car = race.traffic[index]
                drawCar(&context, ahead: ahead, side: (Double(car.lane) - 1) * Self.laneWidth,
                        shape: car.style == 4 ? .van : .sedan, color: trafficColors[Int(car.style) % trafficColors.count],
                        braking: false, opacity: fade(ahead))
            case .pickup(let index):
                pickup(&context, ahead: ahead, lane: race.pickups[index].lane, index: index)
            case .light(_, let side):
                streetLight(&context, ahead: ahead, side: side)
            case .ghost:
                guard let ghost else { continue }
                let side = (ghost.lanePosition - 1) * Self.laneWidth
                context.drawLayer { layer in
                    layer.opacity = 0.42 * fade(ahead)
                    drawCar(&layer, ahead: ahead, side: side, shape: .coupe, color: .white, braking: false, opacity: 1)
                }
                let top = point(ahead: ahead, side: side, up: 1.9)
                context.draw(Text(ghost.name).font(.system(size: max(min(pointsPerMeter(ahead) * 0.55, 11), 7), weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75 * fade(ahead))), at: top)
            case .player:
                if race.isBoosting { boostFlames(&context) }
                // It leans into a turn of the wheel.
                let base = point(ahead: ahead, side: playerX)
                context.drawLayer { layer in
                    layer.translateBy(x: base.x, y: base.y)
                    layer.rotate(by: .degrees(race.steering * 3.5))
                    layer.translateBy(x: -base.x, y: -base.y)
                    drawCar(&layer, ahead: ahead, side: playerX, shape: .coupe, color: rushAccent, braking: race.isBraking, opacity: 1)
                }
                if let age = crashAge { sparks(&context, age: age) }
            }
        }
    }

    private func drawCar(_ context: inout GraphicsContext, ahead: Double, side: Double, shape: RushCarShape, color: Color,
                         braking: Bool, opacity: Double) {
        let base = point(ahead: ahead, side: side)
        context.drawLayer { layer in
            layer.opacity = opacity
            drawRushCarRear(&layer, bottomCenter: base, pointsPerMeter: pointsPerMeter(ahead), shape: shape, color: color, braking: braking)
        }
    }

    private func streetLight(_ context: inout GraphicsContext, ahead: Double, side: Double) {
        let poleX = side * (Self.laneWidth * 1.5 + 1.6)
        let alpha = fade(ahead)
        let foot = point(ahead: ahead, side: poleX), top = point(ahead: ahead, side: poleX, up: 6.5)
        let armEnd = point(ahead: ahead, side: poleX - side * 1.6, up: 6.3)
        let thickness = max(pointsPerMeter(ahead) * 0.14, 0.6)
        var pole = Path()
        pole.move(to: foot)
        pole.addLine(to: top)
        pole.addLine(to: armEnd)
        context.stroke(pole, with: .color(Color(white: 0.3).opacity(alpha)), lineWidth: thickness)
        // The lamp, and its pool of light on the road.
        let glow = pointsPerMeter(ahead) * 1.6
        context.fill(Path(ellipseIn: CGRect(x: armEnd.x - glow, y: armEnd.y - glow * 0.6, width: glow * 2, height: glow * 1.2)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.65).opacity(0.5 * alpha), .clear]),
                                           center: armEnd, startRadius: 0, endRadius: glow))
        let pool = point(ahead: ahead, side: poleX - side * 2.2)
        let poolSize = pointsPerMeter(ahead) * 3.4
        context.fill(Path(ellipseIn: CGRect(x: pool.x - poolSize, y: pool.y - poolSize * 0.25, width: poolSize * 2, height: poolSize * 0.5)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.62).opacity(0.12 * alpha * min(ahead / 25, 1)), .clear]),
                                           center: pool, startRadius: 0, endRadius: poolSize))
    }

    private func pickup(_ context: inout GraphicsContext, ahead: Double, lane: Int, index: Int) {
        let bob = 0.15 * sin(race.time * 4 + Double(index))
        let center = point(ahead: ahead, side: (Double(lane) - 1) * Self.laneWidth, up: 0.8 + bob)
        let radius = pointsPerMeter(ahead) * 0.45
        let alpha = fade(ahead)
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 2.4, y: center.y - radius * 2.4, width: radius * 4.8, height: radius * 4.8)),
                     with: .radialGradient(Gradient(colors: [rushAccent.opacity(0.5 * alpha), .clear]), center: center, startRadius: 0, endRadius: radius * 2.4))
        var bolt = Path()
        bolt.move(to: CGPoint(x: center.x + radius * 0.2, y: center.y - radius))
        bolt.addLine(to: CGPoint(x: center.x - radius * 0.55, y: center.y + radius * 0.12))
        bolt.addLine(to: CGPoint(x: center.x - radius * 0.02, y: center.y + radius * 0.12))
        bolt.addLine(to: CGPoint(x: center.x - radius * 0.2, y: center.y + radius))
        bolt.addLine(to: CGPoint(x: center.x + radius * 0.55, y: center.y - radius * 0.12))
        bolt.addLine(to: CGPoint(x: center.x + radius * 0.02, y: center.y - radius * 0.12))
        bolt.closeSubpath()
        context.fill(bolt, with: .color(.white.opacity(alpha)))
    }

    /// Two flames from the exhausts, toward the camera.
    private func boostFlames(_ context: inout GraphicsContext) {
        let scale = pointsPerMeter(Self.cameraBehind)
        let flicker = 0.8 + 0.2 * sin(race.time * 55)
        for side in [-0.55, 0.55] {
            let center = point(ahead: Self.cameraBehind - 0.1, side: playerX + side, up: 0.28)
            let radius = scale * 0.32 * CGFloat(flicker)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.7, width: radius * 2, height: radius * 1.4)),
                         with: .radialGradient(Gradient(colors: [.white, rushAccent.opacity(0.85), .clear]), center: center, startRadius: 0, endRadius: radius))
        }
    }

    private func sparks(_ context: inout GraphicsContext, age: Double) {
        let front = point(ahead: Self.cameraBehind + 2, side: playerX, up: 0.6)
        let fade = 1 - age / 0.5
        for index in 0..<12 {
            let angle = Double(index) / 12 * .pi * 2
            let reach = CGFloat(6 + age * 70) * (0.6 + CGFloat(hash(index, 3) % 40) / 100)
            var spark = Path()
            spark.move(to: CGPoint(x: front.x + cos(angle) * reach * 0.5, y: front.y + sin(angle) * reach * 0.35))
            spark.addLine(to: CGPoint(x: front.x + cos(angle) * reach, y: front.y + sin(angle) * reach * 0.7))
            context.stroke(spark, with: .color(Color(red: 1, green: 0.82, blue: 0.45).opacity(fade)), lineWidth: 1.3)
        }
    }

    /// Streaks from the horizon toward the edges once the car is fast.
    private func speedLines(_ context: inout GraphicsContext) {
        let strength = (race.speed - 40) / (NotchRushRace.boostSpeed - 40)
        guard strength > 0 else { return }
        let center = CGPoint(x: width / 2, y: horizon)
        for index in 0..<22 {
            let seed = hash(index, 21)
            let angle = Double(seed % 1000) / 1000 * .pi * 2
            let phase = (race.distance * (0.035 + Double((seed / 1000) % 50) / 1000) + Double(seed % 97) / 97).truncatingRemainder(dividingBy: 1)
            let reach = CGFloat(phase) * max(width, height) * 0.75
            let length = CGFloat(10 + 40 * strength) * CGFloat(phase)
            let start = CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach * 0.6)
            let end = CGPoint(x: center.x + cos(angle) * (reach + length), y: center.y + sin(angle) * (reach + length) * 0.6)
            guard start.y > horizon || end.y > horizon else { continue }
            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            context.stroke(line, with: .color(.white.opacity(0.18 * strength * Double(phase))), lineWidth: 0.9)
        }
    }

    private func hash(_ index: Int, _ layer: Int) -> Int {
        var z = UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(layer) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((z ^ (z >> 31)) % 1_000_000_000)
    }
}

enum RushCarShape {
    case coupe, sedan, van
}

/// A car seen from behind, standing on `bottomCenter`, `pointsPerMeter` big.
func drawRushCarRear(_ context: inout GraphicsContext, bottomCenter: CGPoint, pointsPerMeter scale: CGFloat,
                     shape: RushCarShape, color: Color, braking: Bool) {
    let carWidth = scale * (shape == .van ? 1.95 : 1.85)
    let carHeight = scale * (shape == .van ? 1.95 : shape == .coupe ? 1.25 : 1.42)
    let left = bottomCenter.x - carWidth / 2
    let bottom = bottomCenter.y
    func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: left + u * carWidth, y: bottom - v * carHeight)
    }

    // Shadow under it.
    context.fill(Path(ellipseIn: CGRect(x: left - carWidth * 0.05, y: bottom - carHeight * 0.06, width: carWidth * 1.1, height: carHeight * 0.14)),
                 with: .color(.black.opacity(0.55)))
    // Tires, peeking out below.
    for u in [0.04, 0.78] as [CGFloat] {
        context.fill(Path(roundedRect: CGRect(x: at(u, 0).x, y: at(0, 0.22).y, width: carWidth * 0.18, height: carHeight * 0.22),
                          cornerRadius: carWidth * 0.03), with: .color(Color(white: 0.05)))
    }

    let shoulder: CGFloat = shape == .van ? 0.6 : 0.56
    // The cabin: narrower at the roof, the rear window in it.
    let roofInset: CGFloat = shape == .van ? 0.06 : shape == .coupe ? 0.2 : 0.16
    var cabin = Path()
    cabin.move(to: at(0.08, shoulder))
    cabin.addLine(to: at(roofInset, 1))
    cabin.addLine(to: at(1 - roofInset, 1))
    cabin.addLine(to: at(0.92, shoulder))
    cabin.closeSubpath()
    context.fill(cabin, with: .color(color.mix(with: .black, by: 0.25)))
    var glass = Path()
    glass.move(to: at(0.14, shoulder + 0.04))
    glass.addLine(to: at(roofInset + 0.05, 0.93))
    glass.addLine(to: at(1 - roofInset - 0.05, 0.93))
    glass.addLine(to: at(0.86, shoulder + 0.04))
    glass.closeSubpath()
    context.fill(glass, with: .linearGradient(Gradient(colors: [Color(red: 0.5, green: 0.6, blue: 0.75).opacity(0.85), Color(red: 0.1, green: 0.12, blue: 0.18)]),
                                              startPoint: at(0.5, 0.95), endPoint: at(0.5, shoulder)))

    // The body, lit from above.
    let body = Path(roundedRect: CGRect(x: left, y: at(0, shoulder).y, width: carWidth, height: carHeight * (shoulder - 0.1)),
                    cornerRadius: carHeight * 0.1)
    context.fill(body, with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.2), color, color.mix(with: .black, by: 0.4)]),
                                             startPoint: at(0.5, shoulder), endPoint: at(0.5, 0.1)))
    // Bumper, plate, and a light line along the top of the body.
    context.fill(Path(roundedRect: CGRect(x: left + carWidth * 0.03, y: at(0, 0.2).y, width: carWidth * 0.94, height: carHeight * 0.09),
                      cornerRadius: carHeight * 0.03), with: .color(Color(white: 0.08).opacity(0.8)))
    context.fill(Path(roundedRect: CGRect(x: at(0.39, 0).x, y: at(0, 0.34).y, width: carWidth * 0.22, height: carHeight * 0.09),
                      cornerRadius: carHeight * 0.015), with: .color(Color(white: 0.78)))
    var edge = Path()
    edge.move(to: at(0.04, shoulder - 0.02))
    edge.addLine(to: at(0.96, shoulder - 0.02))
    context.stroke(edge, with: .color(.white.opacity(0.25)), lineWidth: max(scale * 0.03, 0.5))

    // Tail lights, joined by a thin strip; brighter while braking.
    let lightY = at(0, shoulder - 0.07).y
    let lightHeight = carHeight * 0.1
    context.drawLayer { layer in
        layer.addFilter(.shadow(color: .red.opacity(braking ? 1 : 0.6), radius: braking ? scale * 0.5 : scale * 0.2))
        let red = Color(red: 1, green: braking ? 0.22 : 0.15, blue: 0.2)
        layer.fill(Path(roundedRect: CGRect(x: at(0.03, 0).x, y: lightY, width: carWidth * 0.22, height: lightHeight), cornerRadius: lightHeight * 0.3),
                   with: .color(red))
        layer.fill(Path(roundedRect: CGRect(x: at(0.75, 0).x, y: lightY, width: carWidth * 0.22, height: lightHeight), cornerRadius: lightHeight * 0.3),
                   with: .color(red))
        layer.fill(Path(CGRect(x: at(0.25, 0).x, y: lightY + lightHeight * 0.35, width: carWidth * 0.5, height: lightHeight * 0.3)),
                   with: .color(red.opacity(braking ? 0.8 : 0.4)))
    }
}

/// The game's tile and menu picture: the car from behind, its lights on.
struct RushCarIcon: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 2.6, size.height / 2)
            drawRushCarRear(&context, bottomCenter: CGPoint(x: size.width / 2, y: size.height * 0.5 + scale * 0.7),
                            pointsPerMeter: scale, shape: .coupe, color: rushAccent, braking: true)
        }
    }
}

/// How far each car is, as dots on a line to the flag.
struct RushProgress: View {
    let you: Double
    var friend: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 12
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: 3)
                Capsule().fill(Color.white.opacity(0.45)).frame(width: max(3, width * CGFloat(you)), height: 3)
                if let friend {
                    Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2)
                        .frame(width: 8, height: 8)
                        .offset(x: width * CGFloat(min(friend, 1)) - 1)
                }
                Circle().fill(rushAccent).frame(width: 8, height: 8)
                    .offset(x: width * CGFloat(you) - 1)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
                    .offset(x: width + 2)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
    }
}

/// Boost left, as a bar.
struct RushBoostMeter: View {
    let boost: Double
    let isBoosting: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isBoosting ? rushAccent : .white.opacity(0.6))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(isBoosting ? rushAccent : Color.white.opacity(0.85))
                        .frame(width: max(4, geometry.size.width * CGFloat(boost)))
                }
            }
            .frame(width: 90, height: 4)
        }
    }
}
