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
            ]
        case .dog:
            return [
                PetCoat(name: "Golden", base: .rgb(0.9, 0.68, 0.38), dark: .rgb(0.74, 0.5, 0.25), light: .rgb(1, 0.9, 0.74), marking: .none),
                PetCoat(name: "Brown", base: .rgb(0.56, 0.37, 0.23), dark: .rgb(0.38, 0.24, 0.14), light: .rgb(0.86, 0.68, 0.5), marking: .none),
                PetCoat(name: "Black", base: .rgb(0.16, 0.15, 0.16), dark: .rgb(0.09, 0.08, 0.09), light: .rgb(0.78, 0.55, 0.32), marking: .none),
                PetCoat(name: "Spotted", base: .rgb(0.97, 0.96, 0.94), dark: .rgb(0.18, 0.17, 0.18), light: .rgb(0.97, 0.96, 0.94), marking: .patches),
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
    }

    let name: String
    let base: PetRGB
    /// Stripes, patches, ears and the far legs.
    let dark: PetRGB
    /// Belly and muzzle; a calico's orange patches.
    let light: PetRGB
    let marking: Marking
}

/// Someone's pet: what it is, its coat (an index into the kind's coats) and its name.
nonisolated struct PetLook: Codable, Equatable, Sendable {
    var kind: PetKind
    var coat: Int
    var name: String

    var coatStyle: PetCoat {
        let coats = kind.coats
        return coats[min(max(coat, 0), coats.count - 1)]
    }
}

/// What the pet is doing, for drawing it.
nonisolated struct PetPose: Equatable, Sendable {
    enum Action: String, Sendable {
        case stand, walk, run, sit, sleep, jump, held
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
    var base: Color { coat.base.color }
    var dark: Color { coat.dark.color }
    var light: Color { coat.light.color }
    var outline: Color { coat.base.color.mix(with: .black, by: 0.45) }
    var farSide: Color { coat.base.color.mix(with: .black, by: 0.22) }
    var lineWidth: CGFloat { 0.7 }

    func draw(_ context: inout GraphicsContext) {
        // A soft shadow on the ground.
        let shadowWidth: CGFloat = pose.action == .jump || pose.action == .held ? 14 : 24
        // Tumbling through the air, it leaves no shadow to turn with it.
        if pose.spin == 0 { context.fill(Path(ellipseIn: CGRect(x: -shadowWidth / 2 - 1, y: -1.2, width: shadowWidth, height: 2.6)), with: .color(.black.opacity(0.28))) }

        switch pose.action {
        case .sit: sitting(&context)
        case .sleep: sleeping(&context)
        default: standing(&context)
        }
    }

    // MARK: Standing, walking, running, jumping

    private func standing(_ context: inout GraphicsContext) {
        let action = pose.action
        let cycle = pose.time * (action == .run ? 3.2 : action == .walk ? 1.9 : 0) * .pi * 2
        let swing: Double = action == .run ? 38 : action == .walk ? 24 : 0
        let lifted = action == .jump || action == .held
        // The body bobs a little with each step, and breathes when still.
        let bob = action == .walk || action == .run ? CGFloat(abs(sin(cycle)) * (action == .run ? 1.2 : 0.6))
            : CGFloat(sin(pose.time * 2.2) * 0.25)
        let lift: CGFloat = lifted ? 2.5 : 0
        var body = context
        body.translateBy(x: 0, y: -bob - lift)
        let legLength: CGFloat = isCat ? 6.5 : 7.2

        func leg(_ x: CGFloat, phase: Double, color: Color, back: Bool) {
            var angle = lifted ? (back ? 30.0 : -30.0) : sin(cycle + phase) * swing
            if action == .held { angle = sin(pose.time * 5 + phase) * 12 }
            var leg = body
            leg.translateBy(x: x, y: -legLength + 0.5)
            leg.rotate(by: .degrees(angle))
            let rect = CGRect(x: -1.6, y: 0, width: 3.2, height: legLength + bob + lift - 0.3)
            leg.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
            leg.fill(Path(ellipseIn: CGRect(x: -1.9, y: rect.maxY - 2, width: 3.8, height: 2.2)), with: .color(color.mix(with: .white, by: 0.12)))
        }

        let bodyY: CGFloat = isCat ? -9.5 : -10.5
        // Far legs, darker, behind the body.
        leg(-8, phase: .pi, color: farSide, back: true)
        leg(4.5, phase: 0, color: farSide, back: false)
        tail(&body, root: CGPoint(x: -11.5, y: bodyY - 2))
        // The body, its belly and markings.
        let bodyRect = CGRect(x: -13, y: bodyY - 5.5, width: 22.5, height: 11)
        body.fill(Path(ellipseIn: bodyRect), with: .color(base))
        body.fill(Path(ellipseIn: CGRect(x: -9, y: bodyY + 0.5, width: 15, height: 5)), with: .color(light.opacity(coat.marking == .patches ? 0 : 0.85)))
        markings(&body, in: bodyRect)
        body.stroke(Path(ellipseIn: bodyRect), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        // Near legs.
        leg(-6, phase: 0, color: base, back: true)
        leg(6.5, phase: .pi, color: base, back: false)
        // The head leans forward a touch when running.
        let headCenter = CGPoint(x: action == .run ? 10.5 : 9.5, y: isCat ? -17 : -18)
        head(&body, center: headCenter)
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
                         with: .color(isCat ? light : dark))
        case .none:
            break
        }
    }

    private func tail(_ context: inout GraphicsContext, root: CGPoint) {
        var path = Path()
        path.move(to: root)
        if isCat {
            // A long tail that curls up and sways slowly, or swishes when happy.
            let sway = sin(pose.time * (pose.isHappy ? 7 : 1.6)) * (pose.isHappy ? 3.5 : 2)
            let low = pose.action == .run
            path.addCurve(to: CGPoint(x: root.x - 6 + sway * 0.5, y: root.y - (low ? 2 : 11)),
                          control1: CGPoint(x: root.x - 6, y: root.y + 1),
                          control2: CGPoint(x: root.x - 8 + sway, y: root.y - (low ? 1 : 6)))
            context.stroke(path, with: .color(base), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            if coat.marking == .stripes {
                let tip = CGPoint(x: root.x - 6 + sway * 0.5, y: root.y - (low ? 2 : 11))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 1.4, y: tip.y - 1.4, width: 2.8, height: 2.8)), with: .color(dark))
            }
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
        }
        context.stroke(Path(ellipseIn: face), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)

        let eyeY = center.y - 0.6
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
            context.fill(Path(ellipseIn: CGRect(x: center.x + 1.5, y: center.y - 0.2, width: 7.5, height: 5.2)), with: .color(light))
            context.fill(Path(ellipseIn: CGRect(x: center.x + 7.3, y: center.y - 0.3, width: 2.6, height: 2.1)), with: .color(Color(white: 0.08)))
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
            } else if pose.isBlinking {
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
        if !isCat {
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
        } else if pose.mouthOpen {
            let mouth = isCat ? CGPoint(x: center.x + 5.6, y: center.y + 2.6) : CGPoint(x: center.x + 6.2, y: center.y + 4.4)
            context.fill(Path(ellipseIn: CGRect(x: mouth.x - 1, y: mouth.y - 0.4, width: 2, height: isCat ? 1.6 : 2.6)), with: .color(Color(red: 0.95, green: 0.42, blue: 0.5)))
        }
    }

    // MARK: Sitting

    private func sitting(_ context: inout GraphicsContext) {
        let breathe = CGFloat(sin(pose.time * 2.2) * 0.25)
        // Tail curled on the ground behind.
        var tail = Path()
        tail.move(to: CGPoint(x: -6, y: -1.5))
        let flick = CGFloat(sin(pose.time * (pose.isHappy ? 8 : 1.4))) * (pose.isHappy ? 2.5 : 1.2)
        tail.addQuadCurve(to: CGPoint(x: -13 + flick, y: isCat ? -5 : -7), control: CGPoint(x: -12, y: 0))
        context.stroke(tail, with: .color(coat.marking == .patches && !isCat ? dark : base), style: StrokeStyle(lineWidth: isCat ? 2.8 : 2.6, lineCap: .round))
        // Haunch and an upright body.
        var body = context
        body.translateBy(x: 0, y: -breathe)
        body.fill(Path(ellipseIn: CGRect(x: -9, y: -9, width: 12, height: 9)), with: .color(farSide))
        let torso = Path(ellipseIn: CGRect(x: -6.5, y: -17, width: 12, height: 16))
        body.fill(torso, with: .color(base))
        body.fill(Path(ellipseIn: CGRect(x: -0.5, y: -14, width: 5.5, height: 11)), with: .color(light.opacity(coat.marking == .patches ? 0 : 0.85)))
        if coat.marking == .patches {
            var clipped = body
            clipped.clip(to: torso)
            clipped.fill(Path(ellipseIn: CGRect(x: -8, y: -12, width: 7, height: 8)), with: .color(isCat ? light : dark))
        }
        body.stroke(torso, with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        body.fill(Path(ellipseIn: CGRect(x: -10, y: -6.5, width: 9, height: 6.5)), with: .color(base))
        // Front legs, straight down.
        for x in [1.0, 3.6] as [CGFloat] {
            body.fill(Path(roundedRect: CGRect(x: x, y: -8, width: 3, height: 8), cornerRadius: 1.4), with: .color(x < 2 ? farSide : base))
            body.fill(Path(ellipseIn: CGRect(x: x - 0.3, y: -2, width: 3.6, height: 2.2)), with: .color(base.mix(with: .white, by: 0.12)))
        }
        head(&body, center: CGPoint(x: 3, y: isCat ? -21 : -22))
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
            clipped.fill(Path(ellipseIn: CGRect(x: loaf.minX + 11, y: loaf.minY, width: 6, height: 5)), with: .color(isCat ? light : dark))
        case .none:
            break
        }
        context.stroke(Path(ellipseIn: loaf), with: .color(outline.opacity(0.5)), lineWidth: lineWidth)
        var tail = Path()
        tail.move(to: CGPoint(x: -11, y: -3))
        tail.addQuadCurve(to: CGPoint(x: 5, y: -0.8), control: CGPoint(x: -6, y: 1.2))
        context.stroke(tail, with: .color(coat.marking == .patches && !isCat ? dark : base.mix(with: .black, by: 0.08)),
                       style: StrokeStyle(lineWidth: isCat ? 2.8 : 2.4, lineCap: .round))
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
            Canvas { context, size in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                var pose = PetPose(action: action, time: time)
                // A blink every few seconds.
                pose.isBlinking = animated && time.truncatingRemainder(dividingBy: 3.7) < 0.14
                let height = min(size.height * 0.92, size.width * 0.78)
                drawPet(&context, look: look, pose: pose, feet: CGPoint(x: size.width / 2 + (action == .sit ? 0 : -height * 0.05), y: size.height * 0.96), height: height)
            }
        }
    }
}
