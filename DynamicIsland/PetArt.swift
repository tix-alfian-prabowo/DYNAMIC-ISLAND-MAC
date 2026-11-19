import SwiftUI

// The pets' look: a cat or a dog seen from the side, drawn with plain shapes so they stay crisp at
// any size. Only plain values go in, so it can be drawn on its own.

nonisolated enum PetKind: String, Codable, CaseIterable, Sendable {
    case cat, dog

    var title: String {
        switch self {
        case .cat: return "Cat"
        case .dog: return "Dog"
        }
    }

    var coats: [PetCoat] {
        switch self {
        case .cat:
            return [
                PetCoat(name: "Ginger", base: .rgb(0.96, 0.63, 0.32), dark: .rgb(0.84, 0.45, 0.18), light: .rgb(1, 0.92, 0.8), marking: .stripes),
                PetCoat(name: "Gray", base: .rgb(0.6, 0.62, 0.67), dark: .rgb(0.44, 0.46, 0.52), light: .rgb(0.86, 0.87, 0.9), marking: .stripes),
                PetCoat(name: "Black", base: .rgb(0.17, 0.17, 0.19), dark: .rgb(0.1, 0.1, 0.11), light: .rgb(0.27, 0.27, 0.3), marking: .none),
                PetCoat(name: "Calico", base: .rgb(0.97, 0.95, 0.91), dark: .rgb(0.2, 0.18, 0.18), light: .rgb(0.94, 0.6, 0.3), marking: .patches),
                PetCoat(name: "White", base: .rgb(0.97, 0.96, 0.94), dark: .rgb(0.8, 0.78, 0.76), light: .rgb(1, 0.92, 0.92), marking: .none),
                PetCoat(name: "Cream", base: .rgb(0.98, 0.87, 0.68), dark: .rgb(0.88, 0.7, 0.48), light: .rgb(1, 0.97, 0.9), marking: .stripes),
                PetCoat(name: "Tuxedo", base: .rgb(0.15, 0.15, 0.17), dark: .rgb(0.08, 0.08, 0.09), light: .rgb(0.97, 0.97, 0.97), marking: .none),
                PetCoat(name: "Siamese", base: .rgb(0.96, 0.9, 0.8), dark: .rgb(0.36, 0.26, 0.2), light: .rgb(1, 0.97, 0.92), marking: .none),
            ] + PetCoat.playful + [
                PetCoat(name: "Tortie", base: .rgb(0.2, 0.16, 0.14), dark: .rgb(0.86, 0.5, 0.2), light: .rgb(0.55, 0.33, 0.18), marking: .patches,
                        accent: .rgb(0.95, 0.75, 0.45)),
                PetCoat(name: "Ginger & White", base: .rgb(0.98, 0.96, 0.93), dark: .rgb(0.94, 0.58, 0.27), light: .rgb(1, 0.92, 0.85), marking: .patches,
                        accent: .rgb(0.94, 0.58, 0.27)),
                PetCoat(name: "Gray & White", base: .rgb(0.98, 0.97, 0.96), dark: .rgb(0.5, 0.52, 0.58), light: .rgb(0.95, 0.92, 0.92), marking: .patches,
                        accent: .rgb(0.5, 0.52, 0.58)),
                PetCoat(name: "Lilac Tabby", base: .rgb(0.8, 0.72, 0.95), dark: .rgb(0.55, 0.42, 0.82), light: .rgb(1, 0.85, 0.92), marking: .stripes),
                PetCoat.cottonCandy,
                PetCoat.confetti,
            ]
        case .dog:
            return [
                PetCoat(name: "Golden", base: .rgb(0.9, 0.68, 0.38), dark: .rgb(0.74, 0.5, 0.25), light: .rgb(1, 0.9, 0.74), marking: .none),
                PetCoat(name: "Brown", base: .rgb(0.56, 0.37, 0.23), dark: .rgb(0.38, 0.24, 0.14), light: .rgb(0.86, 0.68, 0.5), marking: .none),
                PetCoat(name: "Black", base: .rgb(0.16, 0.15, 0.16), dark: .rgb(0.09, 0.08, 0.09), light: .rgb(0.78, 0.55, 0.32), marking: .none),
                PetCoat(name: "Spotted", base: .rgb(0.97, 0.96, 0.94), dark: .rgb(0.18, 0.17, 0.18), light: .rgb(0.97, 0.96, 0.94), marking: .patches),
                PetCoat(name: "White", base: .rgb(0.97, 0.96, 0.93), dark: .rgb(0.85, 0.8, 0.74), light: .rgb(1, 1, 0.98), marking: .none),
                PetCoat(name: "Cream", base: .rgb(0.96, 0.86, 0.68), dark: .rgb(0.84, 0.68, 0.46), light: .rgb(1, 0.96, 0.88), marking: .none),
                PetCoat(name: "Chocolate", base: .rgb(0.4, 0.25, 0.17), dark: .rgb(0.27, 0.16, 0.1), light: .rgb(0.62, 0.44, 0.32), marking: .none),
                PetCoat(name: "Husky", base: .rgb(0.55, 0.57, 0.62), dark: .rgb(0.36, 0.38, 0.43), light: .rgb(0.97, 0.97, 0.98), marking: .none),
            ] + PetCoat.playful + [
                PetCoat(name: "Tricolor", base: .rgb(0.98, 0.97, 0.95), dark: .rgb(0.17, 0.16, 0.17), light: .rgb(0.98, 0.97, 0.95), marking: .patches,
                        accent: .rgb(0.8, 0.55, 0.3)),
                PetCoat(name: "Brindle", base: .rgb(0.6, 0.42, 0.25), dark: .rgb(0.3, 0.2, 0.12), light: .rgb(0.86, 0.7, 0.52), marking: .stripes),
                PetCoat(name: "Merle", base: .rgb(0.66, 0.69, 0.75), dark: .rgb(0.2, 0.2, 0.24), light: .rgb(0.95, 0.95, 0.97), marking: .spots,
                        accent: .rgb(0.88, 0.89, 0.92)),
                PetCoat(name: "Mint Choco", base: .rgb(0.62, 0.9, 0.78), dark: .rgb(0.36, 0.22, 0.15), light: .rgb(0.92, 1, 0.96), marking: .patches,
                        accent: .rgb(0.5, 0.33, 0.22)),
                PetCoat.cottonCandy,
                PetCoat.confetti,
            ]
        }
    }

    /// What it says when clicked.
    var sound: String {
        switch self {
        case .cat: return "meow"
        case .dog: return "woof"
        }
    }

    var defaultName: String {
        switch self {
        case .cat: return "Mochi"
        case .dog: return "Kopi"
        }
    }
}

/// A dog can be a poodle: curly, with pom-poms. Friends on a version without it see a dog.
nonisolated enum PetBreed: String, Codable, CaseIterable, Sendable {
    case standard, poodle
}

nonisolated struct PetRGB: Equatable, Sendable {
    let red: Double, green: Double, blue: Double

    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> PetRGB {
        PetRGB(red: red, green: green, blue: blue)
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
}

nonisolated struct PetCoat: Equatable, Sendable {
    enum Marking: Sendable {
        case none, stripes, patches
        /// Round spots, in `spotColors`.
        case spots
    }

    let name: String
    let base: PetRGB
    /// Stripes, patches, ears and the far legs.
    let dark: PetRGB
    /// Belly and muzzle; a calico's orange patches.
    let light: PetRGB
    let marking: Marking
    /// The second patch's color (or the spots' second one); without it, a cat's is `light`, a dog's `dark`.
    var accent: PetRGB? = nil
    /// Spots in several colors.
    var spots: [PetRGB] = []

    var spotColors: [PetRGB] {
        spots.isEmpty ? [dark, accent ?? light] : spots
    }

    func secondPatch(isCat: Bool) -> PetRGB {
        accent ?? (isCat ? light : dark)
    }

    /// Pink with blue and mint patches.
    static let cottonCandy = PetCoat(name: "Cotton Candy", base: .rgb(0.98, 0.72, 0.82), dark: .rgb(0.55, 0.78, 0.98), light: .rgb(1, 0.92, 0.95),
                                     marking: .patches, accent: .rgb(0.62, 0.9, 0.78))
    /// White with spots of every color.
    static let confetti = PetCoat(name: "Confetti", base: .rgb(0.98, 0.97, 0.95), dark: .rgb(0.8, 0.78, 0.76), light: .rgb(1, 0.94, 0.94),
                                  marking: .spots, spots: [.rgb(0.95, 0.36, 0.36), .rgb(1, 0.65, 0.25), .rgb(0.98, 0.83, 0.25),
                                                           .rgb(0.4, 0.8, 0.45), .rgb(0.35, 0.6, 0.98), .rgb(0.68, 0.45, 0.95)])

    /// Colors no real cat or dog has, for both.
    static let playful = [
        PetCoat(name: "Pink", base: .rgb(0.98, 0.7, 0.8), dark: .rgb(0.9, 0.5, 0.64), light: .rgb(1, 0.92, 0.95), marking: .none),
        PetCoat(name: "Mint", base: .rgb(0.62, 0.9, 0.78), dark: .rgb(0.4, 0.74, 0.6), light: .rgb(0.92, 1, 0.96), marking: .none),
        PetCoat(name: "Lavender", base: .rgb(0.76, 0.68, 0.95), dark: .rgb(0.58, 0.48, 0.84), light: .rgb(0.95, 0.92, 1), marking: .none),
        PetCoat(name: "Sky", base: .rgb(0.55, 0.78, 0.98), dark: .rgb(0.35, 0.58, 0.86), light: .rgb(0.9, 0.96, 1), marking: .none),
    ]
}

/// Someone's pet: what it is, its coat (an index into the kind's coats), its name and its size.
nonisolated struct PetLook: Codable, Equatable, Sendable {
    var kind: PetKind
    var coat: Int
    var name: String
    /// How big, against the usual size (about the notch's height).
    var scale: Double = 1
    var breed: PetBreed = .standard

    var isPoodle: Bool { kind == .dog && breed == .poodle }
    var title: String { isPoodle ? "Poodle" : kind.title }
    var defaultName: String { isPoodle ? "Coco" : kind.defaultName }

    /// What the chooser offers: a cat, a dog, a poodle.
    static let choices: [(kind: PetKind, breed: PetBreed)] = [(.cat, .standard), (.dog, .standard), (.dog, .poodle)]

    struct Size: Sendable {
        let name: String
        let short: String
        let scale: Double
    }

    static let sizes = [
        Size(name: "Small", short: "S", scale: 0.75),
        Size(name: "Medium", short: "M", scale: 1),
        Size(name: "Large", short: "L", scale: 1.3),
        Size(name: "Huge", short: "XL", scale: 1.6),
    ]
    static let scaleRange = 0.75...1.6

    var coatStyle: PetCoat {
        let coats = kind.coats
        return coats[min(max(coat, 0), coats.count - 1)]
    }

    static func clampedScale(_ scale: Double?) -> Double {
        guard let scale, scale.isFinite else { return 1 }
        return min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }
}

// Pets saved before sizes came in have none.
nonisolated extension PetLook {
    private enum CodingKeys: String, CodingKey {
        case kind, coat, name, scale, breed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(PetKind.self, forKey: .kind)
        coat = try container.decode(Int.self, forKey: .coat)
        name = try container.decode(String.self, forKey: .name)
        scale = Self.clampedScale(try container.decodeIfPresent(Double.self, forKey: .scale))
        breed = (try? container.decodeIfPresent(PetBreed.self, forKey: .breed)) ?? .standard
    }
}

/// The balls' colors; a ball's is picked when it's thrown, and goes with it to a friend's Mac.
nonisolated enum PetBallColors {
    static let all: [PetRGB] = [
        .rgb(0.86, 0.93, 0.3),
        .rgb(0.95, 0.33, 0.3),
        .rgb(0.3, 0.6, 0.98),
        .rgb(0.35, 0.82, 0.45),
        .rgb(1, 0.6, 0.2),
        .rgb(0.68, 0.45, 0.95),
        .rgb(1, 0.5, 0.72),
        .rgb(0.25, 0.82, 0.82),
    ]

    static func color(_ index: Int) -> PetRGB {
        all[((index % all.count) + all.count) % all.count]
    }

    /// For a ball from an older version, which doesn't say: the same on both Macs.
    static func index(for id: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Int(hash % UInt32(all.count))
    }
}

/// What the pet is doing, for drawing it.
nonisolated struct PetPose: Equatable, Sendable {
    enum Action: String, Sendable {
        case stand, walk, run, sit, sleep, jump, held
        /// Lying down awake, like a sphinx: forelegs out in front, head up.
        case lie
        /// A stretch (a play bow): rear up, chest down, forelegs out along the ground.
        case stretch
        /// Bounding through the air (see `flight` and `tilt`).
        case leap
        /// Low on bent legs, about to pounce, its rear wiggling.
        case crouch
        /// Sitting and washing: a cat licks a paw, a dog scratches an ear with a hind leg.
        case groom
    }

    var action: Action = .stand
    /// Seconds into the action, for the legs, the tail and breathing.
    var time: Double = 0
    var facingRight = true
    var isBlinking = false
    /// Wagging or swishing hard, when happy.
    var isHappy = false
    /// Mouth open: talking or panting.
    var mouthOpen = false
    /// Eyes squeezed shut, being shaken about.
    var isSqueezed = false
    /// Spiral eyes and a wobble, after being shaken.
    var isDizzy = false
    /// Tumbling through the air, in degrees.
    var spin: Double = 0
    /// Head down to the ground, 0 to 1: biting a ball off the floor.
    var headDip: Double = 0
    /// A ball held in its mouth, in this color.
    var ball: PetRGB?
    /// Yawning wide, eyes shut.
    var isYawning = false
    /// The body tipped, in degrees: nose up below 0, nose down above.
    var tilt: Double = 0
    /// Through a leap: 0 pushing off, 1 landing.
    var flight: Double = 0
}

/// Draws a pet standing on `feet`, `height` points tall (to the top of its ears).
func drawPet(_ context: inout GraphicsContext, look: PetLook, pose: PetPose, feet: CGPoint, height: CGFloat) {
    var context = context
    // Drawn in units, 28 to the top of the head, facing right, feet on y = 0.
    let scale = height / 28
    context.translateBy(x: feet.x, y: feet.y)
    if pose.isDizzy && pose.action != .sleep {
        // Swaying on its feet.
        context.rotate(by: .degrees(sin(pose.time * 7) * 7))
    }
    if pose.spin != 0 {
        // Turning round the middle of its body.
        let middle = height * 0.45
        context.translateBy(x: 0, y: -middle)
        context.rotate(by: .degrees(pose.facingRight ? pose.spin : -pose.spin))
        context.translateBy(x: 0, y: middle)
    }
    context.scaleBy(x: pose.facingRight ? scale : -scale, y: scale)
    PetDrawing(look: look, coat: look.coatStyle, pose: pose).draw(&context)
}

private struct PetDrawing {
    let look: PetLook
    let coat: PetCoat
    let pose: PetPose

    var isCat: Bool { look.kind == .cat }
    var isPoodle: Bool { look.isPoodle }
    var base: Color { coat.base.color }
    var dark: Color { coat.dark.color }
    var light: Color { coat.light.color }
    var outline: Color { coat.base.color.mix(with: .black, by: 0.45) }
    var farSide: Color { coat.base.color.mix(with: .black, by: 0.22) }
    var lineWidth: CGFloat { 0.7 }

    func draw(_ context: inout GraphicsContext) {
        // A soft shadow on the ground.
        let shadowWidth: CGFloat = pose.action == .jump || pose.action == .held || pose.action == .leap ? 14 : 24
        // Tumbling through the air, it leaves no shadow to turn with it.
        if pose.spin == 0 { context.fill(Path(ellipseIn: CGRect(x: -shadowWidth / 2 - 1, y: -1.2, width: shadowWidth, height: 2.6)), with: .color(.black.opacity(0.28))) }

        switch pose.action {
        case .sit, .groom: sitting(&context)
        case .sleep: sleeping(&context)
        case .lie: lying(&context)
        case .stretch: stretching(&context)
        case .stand, .walk, .run, .jump, .held, .leap, .crouch: standing(&context)
        }
    }

    private func mix(_ a: Double, _ b: Double, _ p: Double) -> Double {
        a + (b - a) * min(max(p, 0), 1)
    }

    // MARK: Standing, walking, running, jumping

    private func standing(_ context: inout GraphicsContext) {
        let action = pose.action
        let gallop = action == .run
        let leaping = action == .leap
        let crouching = action == .crouch
        let cycle = pose.time * (gallop ? 3.4 : action == .walk ? 1.9 : 0) * .pi * 2
        let swing: Double = gallop ? 44 : action == .walk ? 24 : 0
        let lifted = action == .jump || action == .held
        // The body bobs a little with each step (bounds, galloping), and breathes when still.
        let bob = action == .walk || gallop ? CGFloat(abs(sin(cycle)) * (gallop ? 1.6 : 0.6))
            : CGFloat(sin(pose.time * 2.2) * 0.25)
        let lift: CGFloat = lifted ? 2.5 : leaping ? 1.5 : 0
        let legLength: CGFloat = isCat ? 6.5 : isPoodle ? 8 : 7.2
        // Crouching, its legs fold under it and it sinks.
        let bend: CGFloat = crouching ? 0.42 : 1
        let bodyY: CGFloat = isCat ? -9.5 : isPoodle ? -11.5 : -10.5
        var body = context
        body.translateBy(x: 0, y: -bob - lift + legLength * (1 - bend))
        // Galloping it rocks; leaping it points where it's going; crouching its rear's up and wiggling.
        let pitch = leaping ? pose.tilt : gallop ? sin(cycle) * 6 : crouching ? 5 + sin(pose.time * 15) * 2.5 : 0
        if pitch != 0 {
            body.translateBy(x: -1.5, y: bodyY)
            body.rotate(by: .degrees(pitch))
            body.translateBy(x: 1.5, y: -bodyY)
        }

        /// Through a leap: pushing off, stretched out, then reaching down to land.
        func leapAngle(back: Bool) -> Double {
            let push = back ? 50.0 : -30.0, stretched = back ? 64.0 : -70.0, land = back ? 22.0 : -12.0
            let flight = pose.flight
            return flight < 0.3 ? mix(push, stretched, flight / 0.3) : flight < 0.7 ? stretched : mix(stretched, land, (flight - 0.7) / 0.3)
        }

        func leg(_ x: CGFloat, phase: Double, color: Color, back: Bool) {
            var angle = lifted ? (back ? 30.0 : -30.0) : sin(cycle + phase) * swing
            if leaping { angle = leapAngle(back: back) }
            if crouching { angle = back ? 38 : -22 }
            if action == .held { angle = sin(pose.time * 5 + phase) * 12 }
            var leg = body
            leg.translateBy(x: x, y: -legLength + 0.5)
            leg.rotate(by: .degrees(angle))
            let width: CGFloat = isPoodle ? 2.4 : 3.2
            let rect = CGRect(x: -width / 2, y: 0, width: width, height: legLength * bend + bob + lift - 0.3)
            leg.fill(Path(roundedRect: rect, cornerRadius: width / 2 - 0.1), with: .color(color))
            if isPoodle {
                // A pom-pom cuff for a foot.
                pom(&leg, center: CGPoint(x: 0, y: rect.maxY - 1.4), radius: 2.5, color: color)
            } else {
                leg.fill(Path(ellipseIn: CGRect(x: -1.9, y: rect.maxY - 2, width: 3.8, height: 2.2)), with: .color(color.mix(with: .white, by: 0.12)))
            }
        }

        // Far legs, darker, behind the body. Walking, legs go in diagonal pairs; galloping, the
        // hind pair and the front pair each land close together.
        leg(-8, phase: gallop ? 0.55 : .pi, color: farSide, back: true)
        leg(4.5, phase: gallop ? .pi + 0.55 : 0, color: farSide, back: false)
        tail(&body, root: CGPoint(x: isPoodle ? -10.5 : -11.5, y: bodyY - 2))
        // The body, its belly and markings; a poodle's is trim, with a fluffy chest and hips.
        let bodyRect = isPoodle ? CGRect(x: -12, y: bodyY - 4.5, width: 20, height: 9) : CGRect(x: -13, y: bodyY - 5.5, width: 22.5, height: 11)
        body.fill(Path(ellipseIn: bodyRect), with: .color(base))
        body.fill(Path(ellipseIn: CGRect(x: -9, y: bodyY + 0.5, width: 15, height: 5)), with: .color(light.opacity(coat.marking == .patches || isPoodle ? 0 : 0.85)))
        markings(&body, in: bodyRect)
        body.stroke(Path(ellipseIn: bodyRect), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        if isPoodle {
            pom(&body, center: CGPoint(x: bodyRect.minX + 2.5, y: bodyY - 0.5), radius: 4, color: pomColor(0))
            pom(&body, center: CGPoint(x: bodyRect.maxX - 3.5, y: bodyY - 1.2), radius: 5.8, color: pomColor(1))
        }
        // Near legs.
        leg(-6, phase: 0, color: base, back: true)
        leg(6.5, phase: .pi, color: base, back: false)
        // The head leans forward a touch when running, and goes down to the ground to bite.
        let dip = CGFloat(min(max(pose.headDip, 0), 1))
        // Crouching, the head's low and forward, eyes on what it's after.
        let low: CGFloat = crouching ? 3 : 0
        let headCenter = CGPoint(x: (gallop || leaping ? 10.5 : 9.5) + dip * 2.5 + low * 0.4, y: (isCat ? -17 : isPoodle ? -20.5 : -18) + dip * 4.5 + low)
        var headContext = body
        if dip > 0 {
            headContext.translateBy(x: headCenter.x, y: headCenter.y)
            headContext.rotate(by: .degrees(Double(dip) * 22))
            headContext.translateBy(x: -headCenter.x, y: -headCenter.y)
        }
        head(&headContext, center: headCenter)
    }

    private func markings(_ context: inout GraphicsContext, in rect: CGRect) {
        var clipped = context
        clipped.clip(to: Path(ellipseIn: rect))
        switch coat.marking {
        case .stripes:
            for index in 0..<4 {
                let x = rect.minX + 5 + CGFloat(index) * 4
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: rect.minY - 1))
                stripe.addQuadCurve(to: CGPoint(x: x - 1.5, y: rect.minY + 5.5), control: CGPoint(x: x + 1.5, y: rect.minY + 3))
                clipped.stroke(stripe, with: .color(dark), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        case .patches:
            clipped.fill(Path(ellipseIn: CGRect(x: rect.minX + 2, y: rect.minY - 1, width: 9, height: 7)), with: .color(dark))
            clipped.fill(Path(ellipseIn: CGRect(x: rect.minX + 12, y: rect.minY + 1, width: 7, height: 6)),
                         with: .color(coat.secondPatch(isCat: isCat).color))
        case .spots:
            spots(&clipped, in: rect)
        case .none:
            break
        }
    }

    /// Round spots over `rect`, taking turns at the coat's colors.
    private func spots(_ context: inout GraphicsContext, in rect: CGRect, count: Int = 6, offset: Int = 0) {
        let places: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [(0.2, 0.3, 0.2), (0.45, 0.18, 0.17), (0.68, 0.38, 0.19),
                                                                  (0.33, 0.68, 0.15), (0.84, 0.22, 0.14), (0.58, 0.75, 0.16)]
        let colors = coat.spotColors
        for (index, place) in places.prefix(count).enumerated() {
            let size = max(rect.width, rect.height) * place.size
            let spot = CGRect(x: rect.minX + rect.width * place.x - size / 2, y: rect.minY + rect.height * place.y - size / 2, width: size, height: size)
            context.fill(Path(ellipseIn: spot), with: .color(colors[(index + offset) % colors.count].color))
        }
    }

    private func tail(_ context: inout GraphicsContext, root: CGPoint) {
        var path = Path()
        path.move(to: root)
        if isCat {
            // A long tail that curls up and sways slowly, or swishes when happy.
            let crouching = pose.action == .crouch
            let sway = sin(pose.time * (pose.isHappy ? 7 : crouching ? 9 : 1.6)) * (pose.isHappy ? 3.5 : 2)
            let low = pose.action == .run || pose.action == .leap || crouching
            path.addCurve(to: CGPoint(x: root.x - 6 + sway * 0.5, y: root.y - (low ? 2 : 11)),
                          control1: CGPoint(x: root.x - 6, y: root.y + 1),
                          control2: CGPoint(x: root.x - 8 + sway, y: root.y - (low ? 1 : 6)))
            context.stroke(path, with: .color(base), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            if coat.marking == .stripes {
                let tip = CGPoint(x: root.x - 6 + sway * 0.5, y: root.y - (low ? 2 : 11))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 1.4, y: tip.y - 1.4, width: 2.8, height: 2.8)), with: .color(dark))
            }
        } else if isPoodle {
            // Straight up, with a pom-pom on the end.
            let wag = sin(pose.time * (pose.isHappy ? 22 : 4)) * (pose.isHappy ? 0.4 : 0.12)
            let angle = -1.95 + wag
            let tip = CGPoint(x: root.x + cos(angle) * 6, y: root.y + sin(angle) * 6)
            path.addLine(to: tip)
            context.stroke(path, with: .color(base), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            pom(&context, center: tip, radius: 2.9, color: pomColor(2))
        } else {
            // A short tail that wags, fast when happy.
            let wag = sin(pose.time * (pose.isHappy ? 22 : 4)) * (pose.isHappy ? 0.5 : 0.18)
            let length: CGFloat = 7
            let angle = -2.1 + wag
            let tip = CGPoint(x: root.x + cos(angle) * length, y: root.y + sin(angle) * length)
            path.addQuadCurve(to: tip, control: CGPoint(x: root.x - 4, y: root.y - 1))
            context.stroke(path, with: .color(coat.marking == .patches ? dark : base), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }

    private func head(_ context: inout GraphicsContext, center: CGPoint) {
        let radius: CGFloat = isCat ? 6.4 : 6
        let face = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2 * 0.95)
        if isCat {
            // Pointed ears, pink inside.
            for (tipX, baseX) in [(center.x - 3.6, center.x - 5.6), (center.x + 2.8, center.x + 0.4)] as [(CGFloat, CGFloat)] {
                var ear = Path()
                ear.move(to: CGPoint(x: baseX, y: center.y - 3.5))
                ear.addLine(to: CGPoint(x: tipX, y: center.y - radius - 4.8))
                ear.addLine(to: CGPoint(x: baseX + 5.2, y: center.y - 4.8))
                ear.closeSubpath()
                context.fill(ear, with: .color(coat.marking == .patches && tipX < center.x ? dark : base))
                var inner = Path()
                inner.move(to: CGPoint(x: baseX + 1.4, y: center.y - 4.2))
                inner.addLine(to: CGPoint(x: tipX + 0.2, y: center.y - radius - 2.6))
                inner.addLine(to: CGPoint(x: baseX + 4, y: center.y - 5))
                inner.closeSubpath()
                context.fill(inner, with: .color(Color(red: 1, green: 0.7, blue: 0.72)))
            }
        }
        context.fill(Path(ellipseIn: face), with: .color(base))
        if coat.marking == .patches {
            var clipped = context
            clipped.clip(to: Path(ellipseIn: face))
            clipped.fill(Path(ellipseIn: CGRect(x: face.minX - 2, y: face.minY - 2, width: radius * 1.3, height: radius * 1.2)), with: .color(dark))
        } else if coat.marking == .spots {
            var clipped = context
            clipped.clip(to: Path(ellipseIn: face))
            spots(&clipped, in: CGRect(x: face.minX - 1, y: face.minY - 1, width: face.width * 0.7, height: face.height * 0.6), count: 2, offset: 3)
        }
        context.stroke(Path(ellipseIn: face), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        if isPoodle {
            // The topknot.
            pom(&context, center: CGPoint(x: center.x - 0.6, y: center.y - radius - 0.8), radius: 4.6, color: pomColor(3))
        }

        let eyeY = center.y - 0.6
        if let ball = pose.ball {
            // Held in its jaws: the muzzle, drawn next, covers the top of it.
            let hold = isCat ? CGPoint(x: center.x + 5.4, y: center.y + 4.4) : CGPoint(x: center.x + (isPoodle ? 7.2 : 6.8), y: center.y + 4.6)
            drawPetBall(&context, center: hold, radius: isCat ? 3 : 3.3, color: ball)
        }
        if isCat {
            // Muzzle, nose, whiskers.
            context.fill(Path(ellipseIn: CGRect(x: center.x + 1.8, y: center.y + 0.8, width: 5, height: 3.6)), with: .color(light.opacity(coat.marking == .patches ? 1 : 0.9)))
            var nose = Path()
            nose.move(to: CGPoint(x: center.x + 5.3, y: center.y + 0.9))
            nose.addLine(to: CGPoint(x: center.x + 6.7, y: center.y + 0.9))
            nose.addLine(to: CGPoint(x: center.x + 6, y: center.y + 1.9))
            nose.closeSubpath()
            context.fill(nose, with: .color(Color(red: 0.95, green: 0.5, blue: 0.55)))
            for dy in [-0.2, 1.2] as [CGFloat] {
                var whisker = Path()
                whisker.move(to: CGPoint(x: center.x + 5, y: center.y + 2 + dy * 0.5))
                whisker.addLine(to: CGPoint(x: center.x + 10, y: center.y + 1.2 + dy))
                context.stroke(whisker, with: .color(.white.opacity(0.55)), lineWidth: 0.35)
            }
        } else {
            // Snout and nose; the ear comes after the eyes.
            if isPoodle {
                // Long and narrow.
                context.fill(Path(ellipseIn: CGRect(x: center.x + 2, y: center.y + 0.3, width: 8.2, height: 4.2)), with: .color(base.mix(with: .white, by: 0.08)))
                context.stroke(Path(ellipseIn: CGRect(x: center.x + 2, y: center.y + 0.3, width: 8.2, height: 4.2)), with: .color(outline.opacity(0.3)), lineWidth: 0.5)
                context.fill(Path(ellipseIn: CGRect(x: center.x + 8.6, y: center.y + 0.2, width: 2.3, height: 1.9)), with: .color(Color(white: 0.08)))
            } else {
                context.fill(Path(ellipseIn: CGRect(x: center.x + 1.5, y: center.y - 0.2, width: 7.5, height: 5.2)), with: .color(light))
                context.fill(Path(ellipseIn: CGRect(x: center.x + 7.3, y: center.y - 0.3, width: 2.6, height: 2.1)), with: .color(Color(white: 0.08)))
            }
        }

        // Eyes: two in three-quarter view, shut while blinking or asleep.
        let eyes: [CGFloat] = isCat ? [center.x - 0.4, center.x + 3.6] : [center.x - 0.2, center.x + 3.4]
        for (index, eyeX) in eyes.enumerated() {
            let size: CGFloat = index == 0 ? 1.5 : 1.8
            if pose.isDizzy {
                // A spiral, turning.
                var spiral = Path()
                let turn = pose.time * 9
                for step in 0...24 {
                    let t = Double(step) / 24
                    let angle = turn + t * .pi * 4
                    let radius = CGFloat(t) * size * 0.95
                    let point = CGPoint(x: eyeX + cos(angle) * radius, y: eyeY + sin(angle) * radius)
                    if step == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
                }
                context.stroke(spiral, with: .color(Color(white: 0.08)), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
            } else if pose.isSqueezed {
                // > < : squeezed shut.
                let side: CGFloat = index == 0 ? 1 : -1
                var squeeze = Path()
                squeeze.move(to: CGPoint(x: eyeX - side * size * 0.6, y: eyeY - size * 0.55))
                squeeze.addLine(to: CGPoint(x: eyeX + side * size * 0.5, y: eyeY))
                squeeze.addLine(to: CGPoint(x: eyeX - side * size * 0.6, y: eyeY + size * 0.55))
                context.stroke(squeeze, with: .color(Color(white: 0.08)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
            } else if pose.isBlinking || pose.isYawning {
                var lid = Path()
                lid.move(to: CGPoint(x: eyeX - size * 0.7, y: eyeY))
                lid.addQuadCurve(to: CGPoint(x: eyeX + size * 0.7, y: eyeY), control: CGPoint(x: eyeX, y: eyeY + 0.9))
                context.stroke(lid, with: .color(Color(white: 0.08)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
            } else {
                let eye = CGRect(x: eyeX - size / 2, y: eyeY - size * 0.65, width: size, height: size * 1.3)
                context.fill(Path(ellipseIn: eye), with: .color(isCat && coat.base.red < 0.3 ? Color(red: 0.9, green: 0.82, blue: 0.3) : Color(white: 0.08)))
                if isCat && coat.base.red < 0.3 {
                    context.fill(Path(ellipseIn: eye.insetBy(dx: size * 0.3, dy: size * 0.1)), with: .color(Color(white: 0.05)))
                }
                context.fill(Path(ellipseIn: CGRect(x: eye.minX + size * 0.15, y: eye.minY + size * 0.15, width: size * 0.4, height: size * 0.4)), with: .color(.white.opacity(0.9)))
            }
        }
        if isPoodle {
            // Long curly ears, swinging a little.
            var ear = context
            ear.translateBy(x: center.x - 4.4, y: center.y - 3.2)
            let flap = pose.action == .run ? 22.0 : pose.action == .jump ? 38 : 6 + sin(pose.time * 2) * 3
            ear.rotate(by: .degrees(flap))
            let color = coat.marking == .patches ? dark : base.mix(with: .black, by: 0.07)
            pom(&ear, center: CGPoint(x: 0, y: 2.4), radius: 3.2, color: color)
            pom(&ear, center: CGPoint(x: 0.2, y: 6), radius: 3, color: color)
        } else if !isCat {
            // A floppy ear at the back of the head, flying up when running or jumping.
            var ear = context
            ear.translateBy(x: center.x - 3.2, y: center.y - 4.8)
            let flap = pose.action == .run ? 35.0 : pose.action == .jump ? 55 : 12 + sin(pose.time * 2) * 3
            ear.rotate(by: .degrees(flap))
            let flapRect = CGRect(x: -2.3, y: -0.6, width: 4.6, height: 8.2)
            ear.fill(Path(roundedRect: flapRect, cornerRadius: 2.3), with: .color(dark))
            ear.stroke(Path(roundedRect: flapRect, cornerRadius: 2.3), with: .color(outline.opacity(0.4)), lineWidth: lineWidth)
        }
        // Blush.
        context.fill(Path(ellipseIn: CGRect(x: center.x + 0.5, y: center.y + 1.6, width: 2.4, height: 1.3)), with: .color(Color(red: 1, green: 0.55, blue: 0.6).opacity(pose.isHappy ? 0.55 : 0.25)))
        if pose.isDizzy || pose.isSqueezed {
            // A wobbly mouth.
            let start = isCat ? CGPoint(x: center.x + 4.4, y: center.y + 3) : CGPoint(x: center.x + 4.8, y: center.y + 4.4)
            var mouth = Path()
            mouth.move(to: start)
            for step in 1...4 {
                mouth.addLine(to: CGPoint(x: start.x + CGFloat(step) * 0.75, y: start.y + (step % 2 == 0 ? 0 : 0.6)))
            }
            context.stroke(mouth, with: .color(Color(white: 0.1)), style: StrokeStyle(lineWidth: 0.45, lineCap: .round, lineJoin: .round))
        } else if pose.isYawning {
            // Wide open, tongue curled.
            let mouth = isCat ? CGPoint(x: center.x + 5.2, y: center.y + 3.1) : CGPoint(x: center.x + 6, y: center.y + 4.6)
            let open = CGRect(x: mouth.x - 1.7, y: mouth.y - 1, width: 3.4, height: isCat ? 3.6 : 4.2)
            context.fill(Path(ellipseIn: open), with: .color(Color(red: 0.42, green: 0.1, blue: 0.14)))
            context.fill(Path(ellipseIn: CGRect(x: open.minX + 0.6, y: open.maxY - 1.7, width: 2.2, height: 1.4)), with: .color(Color(red: 0.95, green: 0.45, blue: 0.52)))
        } else if pose.mouthOpen && pose.ball == nil {
            let mouth = isCat ? CGPoint(x: center.x + 5.6, y: center.y + 2.6) : CGPoint(x: center.x + 6.2, y: center.y + 4.4)
            context.fill(Path(ellipseIn: CGRect(x: mouth.x - 1, y: mouth.y - 0.4, width: 2, height: isCat ? 1.6 : 2.6)), with: .color(Color(red: 0.95, green: 0.42, blue: 0.5)))
        }
    }

    /// A mixed coat's poodle wears its colors on its pom-poms: hip 0, chest 1, tail 2, topknot 3.
    private func pomColor(_ slot: Int) -> Color {
        switch coat.marking {
        case .patches: return [dark, base, coat.secondPatch(isCat: false).color, dark][slot % 4]
        case .spots: return coat.spots.isEmpty ? [base, dark, base, coat.spotColors[1].color][slot % 4] : coat.spots[(slot * 2) % coat.spots.count].color
        case .stripes, .none: return base
        }
    }

    /// A curly pom-pom: little puffs round a middle, each edged, for a poodle.
    private func pom(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color? = nil) {
        let color = color ?? base
        var puffs = [CGRect(x: center.x - radius * 0.6, y: center.y - radius * 0.6, width: radius * 1.2, height: radius * 1.2)]
        for index in 0..<7 {
            let angle = Double(index) / 7 * .pi * 2 + 0.3
            let point = CGPoint(x: center.x + cos(angle) * radius * 0.52, y: center.y + sin(angle) * radius * 0.52)
            let puff = radius * 0.48
            puffs.append(CGRect(x: point.x - puff, y: point.y - puff, width: puff * 2, height: puff * 2))
        }
        for puff in puffs {
            context.fill(Path(ellipseIn: puff.insetBy(dx: -0.35, dy: -0.35)), with: .color(outline.opacity(0.4)))
        }
        for puff in puffs {
            context.fill(Path(ellipseIn: puff), with: .color(color))
        }
        // A little shine on the curls, top left.
        for puff in puffs.prefix(4) {
            context.fill(Path(ellipseIn: CGRect(x: puff.minX + puff.width * 0.2, y: puff.minY + puff.height * 0.2, width: puff.width * 0.3, height: puff.height * 0.25)),
                         with: .color(.white.opacity(0.18)))
        }
    }

    // MARK: Sitting

    private func sitting(_ context: inout GraphicsContext) {
        let breathe = CGFloat(sin(pose.time * 2.2) * 0.25)
        // Tail curled on the ground behind.
        var tail = Path()
        let flick = CGFloat(sin(pose.time * (pose.isHappy ? 8 : 1.4))) * (pose.isHappy ? 2.5 : 1.2)
        if isPoodle {
            // Up behind, its pom-pom bobbing.
            let tip = CGPoint(x: -9.5 + flick * 0.5, y: -9.5)
            tail.move(to: CGPoint(x: -5.5, y: -3))
            tail.addLine(to: tip)
            context.stroke(tail, with: .color(base), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            pom(&context, center: tip, radius: 2.9, color: pomColor(2))
        } else {
            tail.move(to: CGPoint(x: -6, y: -1.5))
            tail.addQuadCurve(to: CGPoint(x: -13 + flick, y: isCat ? -5 : -7), control: CGPoint(x: -12, y: 0))
            context.stroke(tail, with: .color(coat.marking == .patches && !isCat ? dark : base), style: StrokeStyle(lineWidth: isCat ? 2.8 : 2.6, lineCap: .round))
        }
        // Haunch and an upright body.
        var body = context
        body.translateBy(x: 0, y: -breathe)
        body.fill(Path(ellipseIn: CGRect(x: -9, y: -9, width: 12, height: 9)), with: .color(farSide))
        let torso = Path(ellipseIn: CGRect(x: -6.5, y: -17, width: 12, height: 16))
        body.fill(torso, with: .color(base))
        body.fill(Path(ellipseIn: CGRect(x: -0.5, y: -14, width: 5.5, height: 11)), with: .color(light.opacity(coat.marking == .patches || isPoodle ? 0 : 0.85)))
        if coat.marking == .patches {
            var clipped = body
            clipped.clip(to: torso)
            clipped.fill(Path(ellipseIn: CGRect(x: -8, y: -12, width: 7, height: 8)), with: .color(coat.secondPatch(isCat: isCat).color))
            clipped.fill(Path(ellipseIn: CGRect(x: -7, y: -19, width: 7, height: 6)), with: .color(dark))
        } else if coat.marking == .spots {
            var clipped = body
            clipped.clip(to: torso)
            spots(&clipped, in: CGRect(x: -6.5, y: -17, width: 12, height: 16))
        }
        body.stroke(torso, with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        if isPoodle {
            // A fluffy hip and chest.
            pom(&body, center: CGPoint(x: -5.5, y: -4), radius: 4.2, color: pomColor(0))
            pom(&body, center: CGPoint(x: 2.2, y: -13.5), radius: 5.4, color: pomColor(1))
        } else {
            body.fill(Path(ellipseIn: CGRect(x: -10, y: -6.5, width: 9, height: 6.5)), with: .color(base))
        }
        let grooming = pose.action == .groom
        if grooming && !isCat {
            // A hind leg up behind the ear, scratching away fast.
            var leg = body
            leg.translateBy(x: -5, y: -4.5)
            leg.rotate(by: .degrees(-168 + sin(pose.time * 50) * 9))
            let shin = Path(roundedRect: CGRect(x: -1.7, y: 0, width: 3.4, height: 14), cornerRadius: 1.6)
            leg.fill(shin, with: .color(base))
            leg.stroke(shin, with: .color(outline.opacity(0.55)), lineWidth: lineWidth)
            if isPoodle {
                pom(&leg, center: CGPoint(x: 0, y: 14), radius: 2.4)
            } else {
                let foot = Path(ellipseIn: CGRect(x: -2, y: 12.4, width: 4, height: 2.6))
                leg.fill(foot, with: .color(base.mix(with: .white, by: 0.12)))
                leg.stroke(foot, with: .color(outline.opacity(0.55)), lineWidth: lineWidth)
            }
        }
        // Front legs, straight down; washing, a cat's near one is up at its mouth.
        for x in [1.0, 3.6] as [CGFloat] {
            if grooming && isCat && x > 2 { continue }
            let color = x < 2 ? farSide : base
            if isPoodle {
                body.fill(Path(roundedRect: CGRect(x: x + 0.3, y: -9, width: 2.4, height: 8.5), cornerRadius: 1.1), with: .color(color))
                pom(&body, center: CGPoint(x: x + 1.5, y: -1.5), radius: 2.3, color: color)
            } else {
                body.fill(Path(roundedRect: CGRect(x: x, y: -8, width: 3, height: 8), cornerRadius: 1.4), with: .color(color))
                body.fill(Path(ellipseIn: CGRect(x: x - 0.3, y: -2, width: 3.6, height: 2.2)), with: .color(base.mix(with: .white, by: 0.12)))
            }
        }
        let headCenter = CGPoint(x: 3, y: isCat ? -21 : isPoodle ? -23 : -22)
        guard grooming else {
            head(&body, center: headCenter)
            return
        }
        // Washing: eyes shut; a cat bends its head to its paw and licks, a dog leans into the scratch.
        var washing = pose
        washing.isBlinking = true
        washing.mouthOpen = isCat ? sin(pose.time * 6) > 0.2 : true
        var tilted = body
        tilted.translateBy(x: headCenter.x, y: headCenter.y)
        tilted.rotate(by: .degrees(isCat ? 16 + sin(pose.time * 6) * 4 : -14))
        tilted.translateBy(x: -headCenter.x, y: -headCenter.y)
        PetDrawing(look: look, coat: coat, pose: washing).head(&tilted, center: headCenter)
        if isCat {
            // The paw being licked, in front of the chin.
            var paw = body
            paw.translateBy(x: 4.6, y: -11)
            paw.rotate(by: .degrees(-158 + sin(pose.time * 6) * 7))
            paw.fill(Path(roundedRect: CGRect(x: -1.5, y: 0, width: 3, height: 7.5), cornerRadius: 1.4), with: .color(base))
            paw.fill(Path(ellipseIn: CGRect(x: -1.8, y: 6.2, width: 3.6, height: 2.4)), with: .color(base.mix(with: .white, by: 0.12)))
        }
    }

    // MARK: Lying down, stretching

    /// A foreleg lying along the ground, from `x` forward.
    private func foreleg(_ context: inout GraphicsContext, x: CGFloat, color: Color) {
        context.fill(Path(roundedRect: CGRect(x: x, y: -2.8, width: 10.5, height: 2.8), cornerRadius: 1.4), with: .color(color))
        if isPoodle {
            pom(&context, center: CGPoint(x: x + 10, y: -1.6), radius: 2.3, color: color)
        } else {
            context.fill(Path(ellipseIn: CGRect(x: x + 8.4, y: -2.7, width: 3.6, height: 2.7)), with: .color(color.mix(with: .white, by: 0.12)))
        }
    }

    /// Lying awake like a sphinx: belly down, forelegs out in front, a hind leg folded, head up.
    private func lying(_ context: inout GraphicsContext) {
        let breathe = CGFloat(sin(pose.time * 1.8)) * 0.35
        let flick = CGFloat(sin(pose.time * (pose.isHappy ? 8 : 1.1))) * (pose.isHappy ? 2.2 : 1)
        // The tail along the ground behind, its tip flicking.
        if isPoodle {
            var stem = Path()
            stem.move(to: CGPoint(x: -10, y: -4))
            stem.addLine(to: CGPoint(x: -13 + flick * 0.4, y: -7))
            context.stroke(stem, with: .color(base), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            pom(&context, center: CGPoint(x: -13 + flick * 0.4, y: -7), radius: 2.8, color: pomColor(2))
        } else {
            var tail = Path()
            tail.move(to: CGPoint(x: -11, y: -3))
            tail.addQuadCurve(to: CGPoint(x: -19 + flick, y: isCat ? -3.5 : -4.5), control: CGPoint(x: -15, y: 0.5))
            context.stroke(tail, with: .color(coat.marking == .patches && !isCat ? dark : base), style: StrokeStyle(lineWidth: isCat ? 2.8 : 2.4, lineCap: .round))
        }
        foreleg(&context, x: 2.5, color: farSide)
        let bodyRect = CGRect(x: -13, y: -9.5 - breathe, width: 21.5, height: 9.5 + breathe)
        context.fill(Path(ellipseIn: bodyRect), with: .color(base))
        markings(&context, in: bodyRect)
        context.stroke(Path(ellipseIn: bodyRect), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        // The folded hind leg: a round haunch, its paw tucked forward.
        if isPoodle {
            pom(&context, center: CGPoint(x: -8, y: -5), radius: 4.4, color: pomColor(0))
            pom(&context, center: CGPoint(x: 5, y: -7.5), radius: 5, color: pomColor(1))
        } else {
            let haunch = Path(ellipseIn: CGRect(x: -12.5, y: -8.2, width: 9.5, height: 8))
            context.fill(haunch, with: .color(base))
            context.stroke(haunch, with: .color(outline.opacity(0.3)), lineWidth: lineWidth)
            context.fill(Path(ellipseIn: CGRect(x: -5.5, y: -2.4, width: 4.4, height: 2.4)), with: .color(base.mix(with: .white, by: 0.12)))
        }
        foreleg(&context, x: 4.5, color: base)
        head(&context, center: CGPoint(x: 9.5, y: (isCat ? -12.5 : isPoodle ? -14.5 : -13) - breathe * 0.5))
    }

    /// The play bow: hind legs straight, rear and tail up, chest down between forelegs stretched
    /// out along the ground, head low and looking ahead.
    private func stretching(_ context: inout GraphicsContext) {
        let hip = CGPoint(x: -7, y: (isCat ? -9.5 : isPoodle ? -11.5 : -10.5) - 1.5)
        func hindLeg(_ x: CGFloat, color: Color) {
            let top = hip.y + 3
            let width: CGFloat = isPoodle ? 2.4 : 3.2
            context.fill(Path(roundedRect: CGRect(x: x - width / 2, y: top, width: width, height: -top - 0.3), cornerRadius: width / 2 - 0.1), with: .color(color))
            if isPoodle {
                pom(&context, center: CGPoint(x: x, y: -1.4), radius: 2.5, color: color)
            } else {
                context.fill(Path(ellipseIn: CGRect(x: x - 1.9, y: -2, width: 3.8, height: 2.2)), with: .color(color.mix(with: .white, by: 0.12)))
            }
        }
        hindLeg(-9, color: farSide)
        foreleg(&context, x: 3, color: farSide)
        var body = context
        body.translateBy(x: hip.x, y: hip.y)
        body.rotate(by: .degrees(22))
        body.translateBy(x: -hip.x, y: -hip.y)
        tail(&body, root: CGPoint(x: isPoodle ? -10.5 : -11.5, y: hip.y - 2))
        let bodyRect = isPoodle ? CGRect(x: -12, y: hip.y - 4.5, width: 20, height: 9) : CGRect(x: -13, y: hip.y - 5.5, width: 22.5, height: 11)
        body.fill(Path(ellipseIn: bodyRect), with: .color(base))
        markings(&body, in: bodyRect)
        body.stroke(Path(ellipseIn: bodyRect), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        if isPoodle {
            pom(&body, center: CGPoint(x: bodyRect.minX + 2.5, y: hip.y - 0.5), radius: 4, color: pomColor(0))
            pom(&body, center: CGPoint(x: bodyRect.maxX - 3.5, y: hip.y - 1.2), radius: 5.8, color: pomColor(1))
        }
        hindLeg(-6.5, color: base)
        foreleg(&context, x: 5, color: base)
        head(&context, center: CGPoint(x: 11.5, y: isCat ? -8.8 : isPoodle ? -10 : -9.2))
    }

    // MARK: Sleeping

    private func sleeping(_ context: inout GraphicsContext) {
        let breathe = CGFloat(sin(pose.time * 1.3)) * 0.5
        // Curled up in a loaf, the tail wrapped round the front.
        let loaf = CGRect(x: -12, y: -9 - breathe, width: 22, height: 9 + breathe)
        context.fill(Path(ellipseIn: loaf), with: .color(base))
        var clipped = context
        clipped.clip(to: Path(ellipseIn: loaf))
        switch coat.marking {
        case .stripes:
            for index in 0..<4 {
                let x = loaf.minX + 5 + CGFloat(index) * 4
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: loaf.minY - 1))
                stripe.addLine(to: CGPoint(x: x - 1, y: loaf.minY + 4))
                clipped.stroke(stripe, with: .color(dark), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        case .patches:
            clipped.fill(Path(ellipseIn: CGRect(x: loaf.minX + 3, y: loaf.minY - 1, width: 8, height: 6)), with: .color(dark))
            clipped.fill(Path(ellipseIn: CGRect(x: loaf.minX + 11, y: loaf.minY, width: 6, height: 5)), with: .color(coat.secondPatch(isCat: isCat).color))
        case .spots:
            spots(&clipped, in: loaf)
        case .none:
            break
        }
        context.stroke(Path(ellipseIn: loaf), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        if isPoodle {
            // Its pom-pom tail on top at the back, and a fluffy hip.
            pom(&context, center: CGPoint(x: -6, y: -6 - breathe), radius: 3.8, color: pomColor(0))
            pom(&context, center: CGPoint(x: -12, y: -8 - breathe), radius: 2.8, color: pomColor(2))
        } else {
            var tail = Path()
            tail.move(to: CGPoint(x: -11, y: -3))
            tail.addQuadCurve(to: CGPoint(x: 5, y: -0.8), control: CGPoint(x: -6, y: 1.2))
            context.stroke(tail, with: .color(coat.marking == .patches && !isCat ? dark : base.mix(with: .black, by: 0.08)),
                           style: StrokeStyle(lineWidth: isCat ? 2.8 : 2.4, lineCap: .round))
        }
        // The head resting at the front, eyes shut.
        var sleepy = PetPose()
        // Lying dazed, its eyes spin instead.
        sleepy.isBlinking = !pose.isDizzy
        sleepy.isDizzy = pose.isDizzy
        sleepy.time = pose.time
        sleepy.action = .sleep
        PetDrawing(look: look, coat: coat, pose: sleepy).head(&context, center: CGPoint(x: 8, y: -6.5 - breathe * 0.5))
    }
}

/// A small heart, for a happy pet.
func drawPetHeart(_ context: inout GraphicsContext, center: CGPoint, size: CGFloat, color: Color) {
    var heart = Path()
    let half = size / 2
    heart.move(to: CGPoint(x: center.x, y: center.y + half * 0.9))
    heart.addCurve(to: CGPoint(x: center.x - half, y: center.y - half * 0.2),
                   control1: CGPoint(x: center.x - half * 0.2, y: center.y + half * 0.5),
                   control2: CGPoint(x: center.x - half, y: center.y + half * 0.3))
    heart.addArc(center: CGPoint(x: center.x - half / 2, y: center.y - half * 0.3), radius: half / 2,
                 startAngle: .degrees(170), endAngle: .degrees(0), clockwise: false)
    heart.addArc(center: CGPoint(x: center.x + half / 2, y: center.y - half * 0.3), radius: half / 2,
                 startAngle: .degrees(180), endAngle: .degrees(10), clockwise: false)
    heart.addCurve(to: CGPoint(x: center.x, y: center.y + half * 0.9),
                   control1: CGPoint(x: center.x + half, y: center.y + half * 0.3),
                   control2: CGPoint(x: center.x + half * 0.2, y: center.y + half * 0.5))
    context.fill(heart, with: .color(color))
}

/// A pet standing still, for pickers and lists.
struct PetPortrait: View {
    let look: PetLook
    var action: PetPose.Action = .sit
    var animated = true
    /// Drawn smaller for a smaller pet, the biggest filling the frame.
    var showsSize = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
            Canvas { context, size in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                var pose = PetPose(action: action, time: time)
                // A blink every few seconds.
                pose.isBlinking = animated && time.truncatingRemainder(dividingBy: 3.7) < 0.14
                let fit = min(size.height * 0.92, size.width * 0.78)
                let height = showsSize ? fit * (0.45 + 0.55 * (look.scale - PetLook.scaleRange.lowerBound)
                    / (PetLook.scaleRange.upperBound - PetLook.scaleRange.lowerBound)) : fit
                drawPet(&context, look: look, pose: pose, feet: CGPoint(x: size.width / 2 + (action == .sit ? 0 : -height * 0.05), y: size.height * 0.96), height: height)
            }
        }
    }
}
