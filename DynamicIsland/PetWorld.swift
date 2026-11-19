import AppKit
import Combine
import Supabase
import SwiftUI

/// Your pet, kept on this Mac: friends learn it through Poke's online channel, nothing is stored
/// in Supabase.
final class PetStore: ObservableObject {
    static let shared = PetStore()

    @Published private(set) var look: PetLook?
    /// Out on the desktop, or home in the notch.
    @Published var isOut: Bool {
        didSet {
            UserDefaults.standard.set(isOut, forKey: Self.outKey)
            PetWorld.shared.refresh()
        }
    }

    private static let lookKey = "petLook"
    private static let outKey = "petIsOut"
    static let nameLimit = 16

    private init() {
        look = UserDefaults.standard.data(forKey: Self.lookKey).flatMap { try? JSONDecoder().decode(PetLook.self, from: $0) }
        isOut = UserDefaults.standard.object(forKey: Self.outKey) as? Bool ?? true
    }

    /// Takes the pet (or changes it); an empty name becomes the kind's.
    func adopt(_ look: PetLook) {
        var look = look
        look.name = String(look.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.nameLimit))
        if look.name.isEmpty {
            look.name = look.defaultName
        }
        guard look != self.look else { return }
        self.look = look
        if let data = try? JSONEncoder().encode(look) {
            UserDefaults.standard.set(data, forKey: Self.lookKey)
        }
        PokeService.shared.refreshPresence()
        PetWorld.shared.refresh()
        PetPlay.shared.lookChanged()
    }
}

/// A pet on the desktop, yours or a friend's visiting; its window shows it.
final class PetActor: ObservableObject {
    enum Bubble: String, Equatable {
        case heart, sleep, surprise, say
        /// Nobody's played with it for a while: "…".
        case bored
        /// An empty bowl: time to eat.
        case hungry
    }

    let isMine: Bool
    /// A friend's pet says whose it is under it.
    let owner: String?
    @Published var look: PetLook
    @Published var pose = PetPose()
    @Published var bubble: Bubble?
    @Published var isHovered = false
    @Published var carriesBall = false
    /// The color of the ball in its mouth (see PetBallColors).
    @Published var ballColor = 0
    /// Stars going round its head, after being shaken.
    @Published var isDizzy = false
    @Published var opacity: Double = 1
    /// Eating: the bowl, drawn again in front of it so its nose goes into the bowl rather than
    /// over it; where the bowl stands from its feet, and how full it is.
    @Published var bowlInFront: BowlInFront?
    struct BowlInFront: Equatable {
        var offset: CGVector
        var fill: Double
    }
    /// Where its feet are, in screen coordinates.
    var position: CGPoint = .zero
    var bubbleUntil: CFTimeInterval = 0
    fileprivate var window: PetWindow?

    init(look: PetLook, isMine: Bool, owner: String?) {
        self.look = look
        self.isMine = isMine
        self.owner = owner
    }

    func say(_ bubble: Bubble, for seconds: Double, now: CFTimeInterval) {
        self.bubble = bubble
        bubbleUntil = now + seconds
        // It says it out loud too; a friend's a little softer.
        switch bubble {
        case .say: PetSounds.shared.play(.talk, for: look, volume: isMine ? 1 : 0.7)
        case .surprise: PetSounds.shared.play(.surprise, for: look, volume: isMine ? 1 : 0.7)
        case .bored: PetSounds.shared.play(.bored, for: look, volume: isMine ? 1 : 0.5)
        case .hungry: PetSounds.shared.play(.hungry, for: look, volume: isMine ? 1 : 0.5)
        case .heart, .sleep: break
        }
    }

    /// How tall it is, by its size.
    var height: CGFloat { PetWorld.petHeight * CGFloat(look.scale) }

    /// The part of the screen it takes, for the pointer.
    var bounds: CGRect {
        CGRect(x: position.x - height * 0.62, y: position.y - 2, width: height * 1.24, height: height + 4)
    }
}

/// A small window of its own for each pet, moved as the pet goes; clicks pass through everywhere
/// but the pet itself.
private final class PetWindow: NSPanel {
    /// Room for the biggest size, its bubble and its name.
    static let size = CGSize(width: 272, height: 192)
    /// Where the pet's feet are in the window, from its bottom left.
    static let feet = CGPoint(x: 136, y: 26)

    init(actor: PetActor, onMouse: @escaping (PetMouseView.Event) -> Void) {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let mouse = PetMouseView(frame: CGRect(origin: .zero, size: Self.size), area: { [weak actor] in actor?.bounds }, onMouse: onMouse)
        let host = NSHostingView(rootView: PetSprite(actor: actor))
        host.sizingOptions = []
        host.frame = mouse.bounds
        host.autoresizingMask = [.width, .height]
        mouse.addSubview(host)
        contentView = mouse
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Clicks go through it unless the pointer is on the pet.
    func catchesClicks(_ catches: Bool) {
        if ignoresMouseEvents == catches {
            ignoresMouseEvents = !catches
        }
    }

    func place(feet: CGPoint) {
        setFrameOrigin(CGPoint(x: (feet.x - Self.feet.x).rounded(), y: (feet.y - Self.feet.y).rounded()))
    }
}

/// Catches the clicks and drags on a pet (or the basket), and lets everything else through.
private final class PetMouseView: NSView {
    enum Event {
        case down, drag, up(moved: Bool)
    }

    /// Where on the screen it catches the pointer.
    private let area: () -> CGRect?
    private let onMouse: (Event) -> Void
    private var downAt: CGPoint?
    private var moved = false

    init(frame: CGRect, area: @escaping () -> CGRect?, onMouse: @escaping (Event) -> Void) {
        self.area = area
        self.onMouse = onMouse
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window, let area = area() else { return nil }
        let onScreen = window.convertPoint(toScreen: convert(point, to: nil))
        return area.contains(onScreen) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        moved = false
        onMouse(.down)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt else { return }
        let now = NSEvent.mouseLocation
        if hypot(now.x - downAt.x, now.y - downAt.y) > 3 {
            moved = true
        }
        if moved {
            onMouse(.drag)
        }
    }

    override func mouseUp(with event: NSEvent) {
        onMouse(.up(moved: moved))
        downAt = nil
    }
}

/// The pet, its bubble and, on a friend's, whose it is.
private struct PetSprite: View {
    @ObservedObject var actor: PetActor

    var body: some View {
        Canvas { context, size in
            let height = actor.height
            let feet = CGPoint(x: PetWindow.feet.x, y: size.height - PetWindow.feet.y)
            var pose = actor.pose
            if actor.carriesBall {
                pose.ball = PetBallColors.color(actor.ballColor)
            }
            drawPet(&context, look: actor.look, pose: pose, feet: feet, height: height)
            if let bowl = actor.bowlInFront {
                drawPetBowl(&context, feet: CGPoint(x: feet.x + bowl.offset.dx, y: feet.y - bowl.offset.dy), width: 30, fill: bowl.fill)
            }
            let ahead: CGFloat = actor.pose.facingRight ? 1 : -1
            if actor.isDizzy {
                // Little stars circling over its head.
                let head = CGPoint(x: feet.x + ahead * height * 0.3, y: feet.y - height * 1.02)
                for index in 0..<3 {
                    let angle = actor.pose.time * 4 + Double(index) * .pi * 2 / 3
                    let point = CGPoint(x: head.x + cos(angle) * height * 0.32, y: head.y + sin(angle) * height * 0.08)
                    drawPetStar(&context, center: point, radius: height * 0.07, color: Color(red: 1, green: 0.85, blue: 0.3).opacity(0.6 + 0.4 * (sin(angle) + 1) / 2))
                }
            }
            let low = actor.pose.action == .sleep
            let top = CGPoint(x: feet.x + ahead * height * (low ? 0.3 : 0.32), y: feet.y - height * (low ? 0.62 : 1.08))
            switch actor.bubble {
            case .heart:
                drawPetHeart(&context, center: CGPoint(x: top.x, y: top.y - 6), size: 11, color: Color(red: 1, green: 0.4, blue: 0.55))
            case .sleep:
                let drift = CGFloat(actor.pose.time.truncatingRemainder(dividingBy: 2.4))
                for (index, size) in [7.0, 9.0].enumerated() {
                    let rise = (drift + CGFloat(index) * 1.2).truncatingRemainder(dividingBy: 2.4)
                    context.draw(Text("z").font(.system(size: size, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(Double(1 - rise / 2.4))),
                                 at: CGPoint(x: top.x + ahead * (4 + rise * 4), y: top.y - 2 - rise * 7))
                }
            case .hungry:
                // An empty bowl, in a bubble.
                let rect = CGRect(x: top.x - 13, y: top.y - 21, width: 26, height: 17)
                context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(.white))
                drawPetBowl(&context, feet: CGPoint(x: rect.midX, y: rect.maxY - 3.5), width: 15, fill: 0)
            case .surprise, .say, .bored:
                let text = actor.bubble == .say ? actor.look.kind.sound : actor.bubble == .bored ? "…" : "!"
                let resolved = context.resolve(Text(text).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(.black))
                let textSize = resolved.measure(in: CGSize(width: 80, height: 20))
                let rect = CGRect(x: top.x - textSize.width / 2 - 5, y: top.y - textSize.height - 6, width: textSize.width + 10, height: textSize.height + 4)
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(.white))
                context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY))
            case nil:
                break
            }
            if let owner = actor.owner, actor.isHovered || actor.pose.action != .sleep {
                label(&context, "\(owner)'s \(actor.look.name)", at: CGPoint(x: feet.x, y: feet.y + 8))
            } else if actor.isHovered {
                label(&context, actor.look.name, at: CGPoint(x: feet.x, y: feet.y + 8))
            }
        }
        .opacity(actor.opacity)
        .frame(width: PetWindow.size.width, height: PetWindow.size.height)
    }

    private func label(_ context: inout GraphicsContext, _ text: String, at point: CGPoint) {
        let resolved = context.resolve(Text(text).font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundColor(.white))
        let size = resolved.measure(in: CGSize(width: 120, height: 14))
        let rect = CGRect(x: point.x - size.width / 2 - 4, y: point.y - size.height / 2 - 1, width: size.width + 8, height: size.height + 2)
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(.black.opacity(0.55)))
        context.draw(resolved, at: point)
    }
}

/// A small star, for a dizzy pet.
func drawPetStar(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
    var star = Path()
    for point in 0..<10 {
        let angle = Double(point) * .pi / 5 - .pi / 2
        let reach = point % 2 == 0 ? radius : radius * 0.45
        let corner = CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach)
        if point == 0 { star.move(to: corner) } else { star.addLine(to: corner) }
    }
    star.closeSubpath()
    context.fill(star, with: .color(color))
}

/// A ball to fetch.
func drawPetBall(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: PetRGB) {
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    context.fill(Path(ellipseIn: rect), with: .color(color.color))
    // A little shine, top left.
    let shine = CGRect(x: center.x - radius * 0.62, y: center.y - radius * 0.66, width: radius * 0.5, height: radius * 0.38)
    context.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.45)))
    var seam = Path()
    seam.addArc(center: CGPoint(x: center.x - radius * 1.1, y: center.y), radius: radius * 0.85, startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
    seam.addArc(center: CGPoint(x: center.x + radius * 1.1, y: center.y), radius: radius * 0.85, startAngle: .degrees(130), endAngle: .degrees(230), clockwise: false)
    context.stroke(seam, with: .color(.white.opacity(0.9)), lineWidth: max(radius * 0.18, 0.6))
}

private final class PetBallWindow: NSPanel {
    static let size: CGFloat = 24

    init(color: Int) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.size, height: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Canvas { context, size in
            context.fill(Path(ellipseIn: CGRect(x: 4, y: size.height - 4, width: size.width - 8, height: 3)), with: .color(.black.opacity(0.25)))
            drawPetBall(&context, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: 5, color: PetBallColors.color(color))
        }.frame(width: Self.size, height: Self.size))
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
}

/// The food bowl put out by Feed: how much is left in it.
final class PetBowl: ObservableObject {
    @Published var fill: Double = 1
    @Published var opacity: Double = 1
}

private final class PetBowlWindow: NSPanel {
    static let size = CGSize(width: 48, height: 34)
    /// Where its bottom middle is in the window, from the bottom left.
    static let feet = CGPoint(x: 24, y: 6)

    init(bowl: PetBowl) {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Under the pets, like the basket.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let host = NSHostingView(rootView: PetBowlView(bowl: bowl))
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }

    func place(feet: CGPoint) {
        setFrameOrigin(CGPoint(x: (feet.x - Self.feet.x).rounded(), y: (feet.y - Self.feet.y).rounded()))
    }
}

private struct PetBowlView: View {
    @ObservedObject var bowl: PetBowl

    var body: some View {
        Canvas { context, size in
            drawPetBowl(&context, feet: CGPoint(x: PetBowlWindow.feet.x, y: size.height - PetBowlWindow.feet.y), width: 30, fill: bowl.fill)
        }
        .opacity(bowl.opacity)
        .frame(width: PetBowlWindow.size.width, height: PetBowlWindow.size.height)
    }
}

/// A red food bowl standing on `feet`, heaped with kibble as far as `fill` says (0 is empty).
func drawPetBowl(_ context: inout GraphicsContext, feet: CGPoint, width: CGFloat, fill: Double) {
    var context = context
    context.translateBy(x: feet.x, y: feet.y)
    context.scaleBy(x: width / 30, y: width / 30)
    let red = Color(red: 0.9, green: 0.33, blue: 0.33)
    let rim = Color(red: 0.98, green: 0.55, blue: 0.5)
    context.fill(Path(ellipseIn: CGRect(x: -16, y: -1.5, width: 32, height: 3.5)), with: .color(.black.opacity(0.22)))
    // The kibble, heaped: nine pieces when full.
    let pieces: [CGPoint] = [CGPoint(x: -8, y: -10.5), CGPoint(x: -3, y: -11), CGPoint(x: 2.5, y: -11), CGPoint(x: 8, y: -10.5),
                             CGPoint(x: -5.5, y: -13.5), CGPoint(x: 0, y: -14), CGPoint(x: 5.5, y: -13.5),
                             CGPoint(x: -2.5, y: -16.5), CGPoint(x: 3, y: -16.5)]
    let shown = Int((min(max(fill, 0), 1) * Double(pieces.count)).rounded(.up))
    let browns = [Color(red: 0.62, green: 0.38, blue: 0.2), Color(red: 0.72, green: 0.47, blue: 0.25), Color(red: 0.52, green: 0.3, blue: 0.16)]
    for (index, piece) in pieces.prefix(shown).enumerated() {
        context.fill(Path(ellipseIn: CGRect(x: piece.x - 2.6, y: piece.y - 2, width: 5.2, height: 4)), with: .color(browns[index % browns.count]))
    }
    // The bowl: wide at the top, narrow at the foot.
    var body = Path()
    body.move(to: CGPoint(x: -15, y: -10))
    body.addLine(to: CGPoint(x: 15, y: -10))
    body.addQuadCurve(to: CGPoint(x: 9, y: 0), control: CGPoint(x: 14, y: -1))
    body.addLine(to: CGPoint(x: -9, y: 0))
    body.addQuadCurve(to: CGPoint(x: -15, y: -10), control: CGPoint(x: -14, y: -1))
    body.closeSubpath()
    context.fill(body, with: .color(red))
    context.fill(Path(roundedRect: CGRect(x: -15.5, y: -11.5, width: 31, height: 3.2), cornerRadius: 1.6), with: .color(rim))
    // A little white bone on the front.
    var bone = context
    bone.translateBy(x: 0, y: -5)
    bone.fill(Path(roundedRect: CGRect(x: -3.5, y: -0.7, width: 7, height: 1.4), cornerRadius: 0.7), with: .color(.white.opacity(0.9)))
    for x in [-3.6, 3.6] as [CGFloat] {
        for y in [-0.9, 0.9] as [CGFloat] {
            bone.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.9)))
        }
    }
}

/// The basket on the desktop: the balls in it, by color, and whether the pointer is on it.
final class PetBasket: ObservableObject {
    /// A friend's basket says whose it is.
    var owner: String?
    @Published var balls: [Int] = []
    @Published var isHovered = false
    /// Squashes a little as a ball lands in it or it's put down: 0 to 1 and back.
    @Published var bounce: Double = 0
}

/// A wicker basket of your own on the desktop: drag it anywhere, and your pet brings the balls
/// there; click it and a ball comes out again.
private final class PetBasketWindow: NSPanel {
    static let size = CGSize(width: 96, height: 80)
    /// Where its bottom middle is in the window, from the bottom left.
    static let feet = CGPoint(x: 48, y: 20)

    init(basket: PetBasket, area: @escaping () -> CGRect?, onMouse: @escaping (PetMouseView.Event) -> Void) {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Just under the pets and the balls, so they pass in front of it.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let mouse = PetMouseView(frame: CGRect(origin: .zero, size: Self.size), area: area, onMouse: onMouse)
        let host = NSHostingView(rootView: PetBasketView(basket: basket))
        host.sizingOptions = []
        host.frame = mouse.bounds
        host.autoresizingMask = [.width, .height]
        mouse.addSubview(host)
        contentView = mouse
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func catchesClicks(_ catches: Bool) {
        if ignoresMouseEvents == catches {
            ignoresMouseEvents = !catches
        }
    }

    func place(feet: CGPoint) {
        setFrameOrigin(CGPoint(x: (feet.x - Self.feet.x).rounded(), y: (feet.y - Self.feet.y).rounded()))
    }
}

private struct PetBasketView: View {
    @ObservedObject var basket: PetBasket

    var body: some View {
        Canvas { context, size in
            let feet = CGPoint(x: PetBasketWindow.feet.x, y: size.height - PetBasketWindow.feet.y)
            drawPetBasket(&context, feet: feet, balls: basket.balls, squash: basket.bounce)
            if basket.isHovered {
                let count = basket.balls.count
                let text = basket.owner.map { count == 0 ? "\($0)'s basket" : "\($0)'s basket · \(count) ball\(count == 1 ? "" : "s")" }
                    ?? (count == 0 ? "Empty basket" : count == 1 ? "1 ball · click for it" : "\(count) balls · click for one")
                let resolved = context.resolve(Text(text).font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundColor(.white))
                let textSize = resolved.measure(in: CGSize(width: 120, height: 14))
                let point = CGPoint(x: feet.x, y: feet.y + 10)
                let rect = CGRect(x: point.x - textSize.width / 2 - 4, y: point.y - textSize.height / 2 - 1, width: textSize.width + 8, height: textSize.height + 2)
                context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(.black.opacity(0.55)))
                context.draw(resolved, at: point)
            }
        }
        .frame(width: PetBasketWindow.size.width, height: PetBasketWindow.size.height)
    }
}

/// A wicker basket standing on `feet`, with a handle, and the balls in it peeking over the rim.
func drawPetBasket(_ context: inout GraphicsContext, feet: CGPoint, balls: [Int], squash: Double) {
    var context = context
    context.translateBy(x: feet.x, y: feet.y)
    context.scaleBy(x: 1 + CGFloat(squash) * 0.08, y: 1 - CGFloat(squash) * 0.1)
    let wicker = Color(red: 0.8, green: 0.58, blue: 0.33)
    let dark = Color(red: 0.55, green: 0.36, blue: 0.18)
    let light = Color(red: 0.95, green: 0.79, blue: 0.53)
    let width: CGFloat = 56, bottomWidth: CGFloat = 44, rim: CGFloat = -28

    context.fill(Path(ellipseIn: CGRect(x: -width / 2 - 2, y: -2.5, width: width + 4, height: 5)), with: .color(.black.opacity(0.25)))
    // The handle, behind everything.
    var handle = Path()
    handle.move(to: CGPoint(x: -width / 2 + 7, y: rim))
    handle.addCurve(to: CGPoint(x: width / 2 - 7, y: rim), control1: CGPoint(x: -width / 2 + 7, y: rim - 30), control2: CGPoint(x: width / 2 - 7, y: rim - 30))
    context.stroke(handle, with: .color(dark), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
    context.stroke(handle, with: .color(wicker), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    // Inside, in shadow.
    context.fill(Path(ellipseIn: CGRect(x: -width / 2, y: rim - 5, width: width, height: 10)), with: .color(dark.mix(with: .black, by: 0.35)))
    // Up to seven balls show: four in a row, three on top.
    let spots: [CGPoint] = [CGPoint(x: -16, y: -33), CGPoint(x: -5, y: -34.5), CGPoint(x: 6, y: -33), CGPoint(x: 17, y: -34.5),
                            CGPoint(x: -10, y: -41), CGPoint(x: 1.5, y: -42.5), CGPoint(x: 12, y: -41)]
    for (index, color) in balls.prefix(spots.count).enumerated() {
        drawPetBall(&context, center: spots[index], radius: 6, color: PetBallColors.color(color))
    }
    // The front, woven.
    var wall = Path()
    wall.move(to: CGPoint(x: -width / 2, y: rim))
    wall.addLine(to: CGPoint(x: width / 2, y: rim))
    wall.addQuadCurve(to: CGPoint(x: bottomWidth / 2 - 3, y: 0), control: CGPoint(x: bottomWidth / 2 + 1, y: -2))
    wall.addLine(to: CGPoint(x: -bottomWidth / 2 + 3, y: 0))
    wall.addQuadCurve(to: CGPoint(x: -width / 2, y: rim), control: CGPoint(x: -bottomWidth / 2 - 1, y: -2))
    wall.closeSubpath()
    context.fill(wall, with: .color(wicker))
    var weave = context
    weave.clip(to: wall)
    for row in 0..<4 {
        let y = rim + 5 + CGFloat(row) * 6.5
        for column in -6...6 {
            let x = CGFloat(column) * 5 + (row % 2 == 0 ? 0 : 2.5)
            weave.fill(Path(roundedRect: CGRect(x: x - 1.6, y: y - 2.3, width: 3.2, height: 4.6), cornerRadius: 1.3), with: .color(light.opacity(0.55)))
        }
        weave.fill(Path(CGRect(x: -width / 2, y: y + 2.6, width: width, height: 0.9)), with: .color(dark.opacity(0.45)))
    }
    context.stroke(wall, with: .color(dark), lineWidth: 0.9)
    // The rim, a thick braid along the top.
    context.fill(Path(roundedRect: CGRect(x: -width / 2 - 2, y: rim - 2.5, width: width + 4, height: 5.5), cornerRadius: 2.75), with: .color(dark))
    context.fill(Path(roundedRect: CGRect(x: -width / 2 - 1, y: rim - 2, width: width + 2, height: 2.2), cornerRadius: 1.1), with: .color(light.opacity(0.65)))
}

/// The pets on the desktop: yours wandering about and, while playing with a friend, theirs.
/// Yours decides what it does here; a friend's goes where their Mac says (see PetPlay).
final class PetWorld: ObservableObject {
    static let shared = PetWorld()
    static let petHeight: CGFloat = 46
    static let maxBalls = 10
    /// Balls on the desktop now.
    @Published private(set) var ballCount = 0

    private(set) var mine: PetActor?
    private(set) var friend: PetActor?

    private enum Activity {
        case arriving(from: CGPoint, to: CGPoint, start: CFTimeInterval)
        case leaving(from: CGPoint, start: CFTimeInterval)
        case idle(until: CFTimeInterval)
        case walk(to: CGPoint, run: Bool)
        case sit(until: CFTimeInterval)
        case sleep(until: CFTimeInterval)
        case held(grab: CGPoint)
        /// Staggering about after being shaken.
        case dizzy(until: CFTimeInterval)
        /// Thrown: flying until it hits `ground`.
        case flying(velocity: CGVector, ground: CGFloat)
        /// Lying where it fell, seeing stars.
        case dazed(until: CFTimeInterval)
        case drop(from: CGPoint, to: CGPoint, start: CFTimeInterval)
        case hop(start: CFTimeInterval)
        case chase(until: CFTimeInterval)
        case flee(until: CFTimeInterval)
        case fetch(String)
        case carry(to: CGPoint, until: CFTimeInterval)
        /// At the bowl, crunching; `until` 0 is just starting.
        case eat(until: CFTimeInterval)
        /// Head down to a ball on the ground, "hap!", and up again with it.
        case bite(String, start: CFTimeInterval)
        /// Lying down awake, resting, looking about.
        case lie(until: CFTimeInterval)
        /// A good stretch, front down and rear up; `until` 0 is just starting.
        case stretch(until: CFTimeInterval)
        /// Sitting, washing: a cat licks a paw, a dog scratches an ear.
        case groom(until: CFTimeInterval)
        /// A big yawn, sitting.
        case yawn(until: CFTimeInterval)
        /// Low and still but for its rear, about to pounce on `toward`; `until` 0 is just starting.
        case crouch(until: CFTimeInterval, toward: CGPoint)
        /// Bounding through the air.
        case leap(from: CGPoint, to: CGPoint, start: CFTimeInterval, height: CGFloat)
        /// Zoomies: tearing about from one spot to the next, `left` more to go.
        case zoom(to: CGPoint, left: Int)
        /// Ambling along nose to the ground.
        case sniff(to: CGPoint)
    }

    private struct Ball {
        let id: String
        let from: CGPoint
        let to: CGPoint
        let start: CFTimeInterval
        /// Its color (see PetBallColors).
        let color: Int
        var holder: String?
        /// When your pet brought it and put it down; it goes a little later.
        var droppedAt: CFTimeInterval?
        /// Tossed into the basket from your pet's mouth: on its way in.
        var toss: (from: CGPoint, start: CFTimeInterval)?
        let window: PetBallWindow
        static let flight: CFTimeInterval = 1.1
    }

    private var activity = Activity.idle(until: 0)
    /// Started when the current walk ends.
    private var then: Activity?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var nextBlink: CFTimeInterval = 0
    private var awakeSince: CFTimeInterval = 0
    private var wasHovered = false
    /// The pointer's hand over a pet: open over yours, closed while you hold it, pointing over a friend's.
    private var shownCursor: NSCursor?
    private var isPressing = false
    private var lastBallColor = -1
    /// What it does next, in order, once the current thing's done: each made when it starts.
    private var plan: [(CFTimeInterval) -> Activity] = []
    /// When it next looks the other way, resting.
    private var nextLook: CFTimeInterval = 0
    /// A dog pants for a while after running about.
    private var pantUntil: CFTimeInterval = 0

    // Moods: hungry a while after its last meal, bored a while after anyone last played with it.
    @Published private(set) var isHungry = false
    @Published private(set) var isBored = false
    @Published private(set) var isBowlOut = false
    private var lastFed: Date
    private var lastPlayedWith: CFTimeInterval = 0
    /// When it may next say it's hungry or bored, or chat for no reason.
    private var nextMoan: CFTimeInterval = 0
    private var nextChatter: CFTimeInterval = 0
    private var nextMunch: CFTimeInterval = 0
    private var bowl: (window: PetBowlWindow, model: PetBowl, spot: CGPoint)?
    private static let fedKey = "petLastFed"
    static let hungerAfter: TimeInterval = 2.5 * 3600
    private static let boredAfter: CFTimeInterval = 6 * 60
    private static let eatingTime: CFTimeInterval = 4.5

    // The basket: out or put away, where it stands (its bottom middle, on the screen), what's in it.
    let basket = PetBasket()
    @Published private(set) var basketIsOut: Bool
    private var basketWindow: PetBasketWindow?
    private var basketFeet: CGPoint?
    private var basketGrab: CGPoint?
    private var isPressingBasket = false
    private var basketBounceStart: CFTimeInterval?
    /// A friend's basket, while playing: shown where it stands on their desktop, only to look at.
    let friendBasket = PetBasket()
    private var friendBasketWindow: PetBasketWindow?
    private var friendBasketFeet: CGPoint?
    private static let basketOutKey = "petBasketIsOut"
    /// Where it stands, as a fraction of the area.
    private static let basketSpotKey = "petBasketSpot"
    private static let basketBallsKey = "petBasketBalls"
    /// How hard it's being shaken while held: grows with each jerk of the pointer, fades on its own.
    private var shake: Double = 0
    private var lastHeldPointer: CGPoint?
    private var lastHeldVelocity: CGVector = .zero
    /// Shaken this much, it gets dizzy.
    private static let dizzyShake: Double = 6
    /// Let go while the pointer moves this fast (points a second), it's thrown.
    private static let throwSpeed: CGFloat = 900

    /// Each jerk of the pointer the other way adds to the shake, and so does distance; it fades.
    private func measureShake(pointer: CGPoint, elapsed: Double) {
        defer { lastHeldPointer = pointer }
        guard let last = lastHeldPointer, elapsed > 0 else { return }
        let velocity = CGVector(dx: (pointer.x - last.x) / elapsed, dy: (pointer.y - last.y) / elapsed)
        let speed = hypot(velocity.dx, velocity.dy)
        if speed > 200, velocity.dx * lastHeldVelocity.dx + velocity.dy * lastHeldVelocity.dy < 0 {
            shake += 1
        }
        shake += Double(hypot(pointer.x - last.x, pointer.y - last.y)) / 500
        shake *= exp(-elapsed * 0.5)
        // Smoothed, for the throw.
        let blend = min(elapsed * 18, 1)
        lastHeldVelocity = CGVector(dx: lastHeldVelocity.dx + (velocity.dx - lastHeldVelocity.dx) * blend,
                                    dy: lastHeldVelocity.dy + (velocity.dy - lastHeldVelocity.dy) * blend)
    }
    private var screenID: CGDirectDisplayID?
    private var balls: [Ball] = []
    /// The ball your pet has in its mouth.
    private var carried: String?
    /// Where a friend's pet is heading, from their last message.
    private var friendTarget: CGPoint?
    private var friendGoingHome: CFTimeInterval?

    private init() {
        lastFed = UserDefaults.standard.object(forKey: Self.fedKey) as? Date ?? Date()
        basketIsOut = UserDefaults.standard.bool(forKey: Self.basketOutKey)
        basket.balls = (UserDefaults.standard.array(forKey: Self.basketBallsKey) as? [Int]) ?? []
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PetWorld.shared.screensChanged() }
        }
    }

    // MARK: Area

    /// The pets keep to one screen: the notch's when yours came out.
    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == screenID } ?? IslandLayout.notchScreen ?? NSScreen.main
    }

    private var area: CGRect {
        guard let screen else { return CGRect(x: 0, y: 0, width: 800, height: 600) }
        let frame = screen.visibleFrame
        return CGRect(x: frame.minX + 24, y: frame.minY + 6, width: frame.width - 48, height: frame.height - 48)
    }

    /// Just below the notch, where pets come out and go home.
    private var notchDoor: CGPoint {
        guard let screen else { return .zero }
        let top = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        return CGPoint(x: screen.frame.midX, y: screen.frame.maxY - top - Self.petHeight * 0.6)
    }

    /// Positions go between Macs as fractions of the area, since screens differ.
    func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - area.minX) / max(area.width, 1), y: (point.y - area.minY) / max(area.height, 1))
    }

    func denormalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: area.minX + point.x * area.width, y: area.minY + point.y * area.height)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY))
    }

    private func screensChanged() {
        guard mine != nil || friend != nil else { return }
        if screen?.displayID != screenID {
            screenID = IslandLayout.notchScreen?.displayID
        }
        if let mine {
            mine.position = clamped(mine.position)
        }
        if let window = basketWindow {
            let feet = savedBasketSpot
            basketFeet = feet
            window.place(feet: feet)
        }
    }

    // MARK: Yours

    /// Brings your pet out, or sends it home, as the Pet tab says.
    func refresh() {
        if basketIsOut, basketWindow == nil {
            openBasket()
        }
        let store = PetStore.shared
        if let look = store.look, store.isOut {
            if let mine {
                mine.look = look
                if case .leaving = activity {
                    // Called back before it got home.
                    activity = .idle(until: now + 1)
                    mine.opacity = 1
                }
            } else {
                comeOut(look)
            }
        } else if mine != nil {
            goHome()
        }
    }

    private var now: CFTimeInterval { CACurrentMediaTime() }

    private func comeOut(_ look: PetLook) {
        screenID = IslandLayout.notchScreen?.displayID
        let actor = PetActor(look: look, isMine: true, owner: nil)
        actor.window = PetWindow(actor: actor) { [weak self] event in
            MainActor.assumeIsolated { self?.mouse(event) }
        }
        mine = actor
        let door = notchDoor
        actor.position = door
        let landing = clamped(CGPoint(x: door.x + .random(in: -90...90), y: area.maxY - .random(in: 30...80)))
        activity = .arriving(from: door, to: landing, start: now)
        then = nil
        awakeSince = now
        lastPlayedWith = now
        nextMoan = now + 60
        nextChatter = now + 90
        actor.window?.place(feet: door)
        actor.window?.orderFrontRegardless()
        startTimer()
    }

    private func goHome() {
        guard let mine else { return }
        if case .leaving = activity { return }
        if let carried { removeBall(carried) }
        mine.carriesBall = false
        plan = []
        let door = notchDoor
        let below = CGPoint(x: door.x, y: min(area.maxY, door.y - 30))
        activity = .walk(to: below, run: true)
        then = .leaving(from: below, start: 0)
    }

    private func gone() {
        removeBowl()
        mine?.window?.orderOut(nil)
        mine?.window = nil
        mine = nil
        stopTimerIfIdle()
    }

    /// For PetPlay: what your pet is doing, to send.
    var mineState: (position: CGPoint, pose: PetPose, bubble: PetActor.Bubble?, ball: Bool, dizzy: Bool)? {
        guard let mine else { return nil }
        return (normalized(mine.position), mine.pose, mine.bubble, mine.carriesBall, mine.isDizzy)
    }

    // MARK: A friend's

    func showFriend(look: PetLook, owner: String) {
        if let friend {
            friend.look = look
            return
        }
        let actor = PetActor(look: look, isMine: false, owner: owner)
        actor.window = PetWindow(actor: actor) { [weak self] event in
            MainActor.assumeIsolated { self?.friendMouse(event) }
        }
        actor.position = notchDoor
        actor.pose.action = .jump
        friend = actor
        friendTarget = nil
        friendGoingHome = nil
        actor.window?.place(feet: actor.position)
        actor.window?.orderFrontRegardless()
        startTimer()
    }

    func updateFriend(position: CGPoint, action: PetPose.Action, facingRight: Bool, happy: Bool, bubble: PetActor.Bubble?, ball: Bool, dizzy: Bool,
                      dip: Double, flight: Double, tilt: Double, yawning: Bool) {
        guard let friend, friendGoingHome == nil else { return }
        friend.pose.headDip = dip
        friend.pose.flight = flight
        friend.pose.tilt = tilt
        friend.pose.isYawning = yawning
        friend.pose.isDizzy = dizzy
        if friend.isDizzy != dizzy { friend.isDizzy = dizzy }
        friendTarget = denormalized(position)
        friend.pose.action = action
        friend.pose.facingRight = facingRight
        friend.pose.isHappy = happy
        friend.pose.mouthOpen = bubble == .say
        if let bubble, friend.bubble != bubble {
            switch bubble {
            case .say: PetSounds.shared.play(.talk, for: friend.look, volume: 0.6)
            case .hungry: PetSounds.shared.play(.hungry, for: friend.look, volume: 0.45)
            case .bored: PetSounds.shared.play(.bored, for: friend.look, volume: 0.45)
            case .heart, .sleep, .surprise: break
            }
        }
        if friend.bubble != bubble { friend.bubble = bubble }
        if friend.carriesBall != ball { friend.carriesBall = ball }
    }

    /// The friend's pet hops back into the notch and goes.
    func removeFriend() {
        removeFriendBasket()
        guard friend != nil, friendGoingHome == nil else { return }
        friendGoingHome = now
        friendTarget = notchDoor
        friend?.pose.action = .jump
        friend?.carriesBall = false
    }

    // MARK: Playing together

    /// The friend's pet is after yours: run.
    func chased() {
        guard mine != nil, isFree else { return }
        mine?.say(.surprise, for: 0.8, now: now)
        activity = .flee(until: now + .random(in: 3...4.5))
        then = nil
        plan = []
        startTimer()
    }

    /// Caught: stop running.
    func tagged() {
        guard case .flee = activity else { return }
        activity = .hop(start: now)
        mine?.say(.heart, for: 1.2, now: now)
        PetSounds.shared.play(.happy, for: mine?.look)
    }

    /// Throws a ball from the notch to somewhere on the desktop; `target` is a fraction of the area.
    /// At most ten are out at once: a friend's ball past that takes the oldest's place.
    /// `from` is where it comes from on this Mac: the notch, or the basket.
    func throwBall(id: String, target: CGPoint, color: Int, from: CGPoint? = nil) {
        guard !balls.contains(where: { $0.id == id }) else { return }
        while balls.count >= Self.maxBalls, let oldest = balls.firstIndex(where: { $0.id != carried }) {
            removeBall(balls[oldest].id)
        }
        let start = from ?? notchDoor
        let window = PetBallWindow(color: color)
        balls.append(Ball(id: id, from: start, to: clamped(denormalized(target)), start: now, color: color, window: window))
        ballCount = balls.count
        placeBall(window, at: start)
        PetSounds.shared.play(.pop, volume: 0.6)
        noteAttention()
        window.orderFrontRegardless()
        if mine != nil, isFetchable, !isFetching {
            activity = .fetch(id)
            then = nil
            plan = []
        }
        startTimer()
    }

    /// The friend's pet got a ball; if both got it at once, one of the two Macs gives way.
    func friendTookBall(id: String) {
        guard let index = balls.firstIndex(where: { $0.id == id }) else { return }
        if balls[index].holder == "me" {
            guard PetPlay.shared.friendWinsTies else { return }
            if carried == id {
                mine?.carriesBall = false
                carried = nil
                activity = .sit(until: now + 2.5)
            }
        }
        balls[index].holder = "friend"
        balls[index].window.orderOut(nil)
        friend?.ballColor = balls[index].color
        var wasAfterIt = false
        if case .fetch(let fetching) = activity, fetching == id { wasAfterIt = true }
        if case .bite(let biting, _) = activity, biting == id, carried != id { wasAfterIt = true }
        if wasAfterIt {
            mine?.say(.surprise, for: 1, now: now)
            activity = nextFetch() ?? .sit(until: now + 2.5)
        }
    }

    /// A different color from the last ball's.
    func nextBallColor() -> Int {
        var color = Int.random(in: 0..<PetBallColors.all.count)
        if color == lastBallColor {
            color = (color + 1) % PetBallColors.all.count
        }
        lastBallColor = color
        return color
    }

    /// The nearest ball nobody has fetched yet.
    private func nextFetch() -> Activity? {
        guard let mine else { return nil }
        return balls.filter { $0.holder == nil && $0.droppedAt == nil }
            .min { hypot($0.to.x - mine.position.x, $0.to.y - mine.position.y) < hypot($1.to.x - mine.position.x, $1.to.y - mine.position.y) }
            .map { .fetch($0.id) }
    }

    private var isFetching: Bool {
        switch activity {
        case .fetch, .bite, .carry: return true
        default: return false
        }
    }

    private func removeBall(_ id: String) {
        guard let index = balls.firstIndex(where: { $0.id == id }) else { return }
        balls[index].window.orderOut(nil)
        balls.remove(at: index)
        ballCount = balls.count
        if carried == id {
            carried = nil
            mine?.carriesBall = false
        }
    }

    // MARK: Food

    /// Something happened with it: it isn't bored.
    private func noteAttention() {
        lastPlayedWith = now
        if isBored { isBored = false }
    }

    /// Puts a bowl of food out beside your pet (bringing it out first); it runs over and eats.
    func feed() {
        noteAttention()
        if PetStore.shared.look != nil, !PetStore.shared.isOut {
            PetStore.shared.isOut = true
        }
        guard let mine, bowl == nil else { return }
        let side: CGFloat = mine.position.x > area.midX ? -1 : 1
        let spot = clamped(CGPoint(x: mine.position.x + side * (70 + mine.height), y: mine.position.y))
        let model = PetBowl()
        let window = PetBowlWindow(bowl: model)
        window.place(feet: spot)
        window.orderFrontRegardless()
        bowl = (window, model, spot)
        isBowlOut = true
        PetSounds.shared.play(.pop, volume: 0.5)
        // Drops what it's doing, unless it's in your hand or in the air.
        if isFree, !isFetching {
            activity = .walk(to: bowlSpot(spot, for: mine), run: true)
            then = .eat(until: 0)
            plan = []
        }
        startTimer()
    }

    /// Beside the bowl, facing it, close enough to put its nose in.
    private func bowlSpot(_ spot: CGPoint, for pet: PetActor) -> CGPoint {
        let side: CGFloat = pet.position.x < spot.x ? -1 : 1
        return clamped(CGPoint(x: spot.x + side * (pet.height * 0.42 + 12), y: spot.y))
    }

    /// The bowl's empty: full and happy for the next few hours.
    private func fed(_ mine: PetActor, now: CFTimeInterval) {
        lastFed = Date()
        UserDefaults.standard.set(lastFed, forKey: Self.fedKey)
        isHungry = false
        nextMoan = now + .random(in: 240...420)
        removeBowl()
        mine.say(.heart, for: 1.6, now: now)
        PetSounds.shared.play(.happy, for: mine.look)
        activity = .sit(until: now + 3)
    }

    private func removeBowl() {
        bowl?.window.orderOut(nil)
        bowl = nil
        if isBowlOut { isBowlOut = false }
    }

    // MARK: A friend's basket

    /// For PetPlay: your basket, if it's out: where (as a fraction of the area) and its balls.
    var basketState: (spot: CGPoint, balls: [Int])? {
        guard let feet = basketFeet else { return nil }
        return (normalized(feet), basket.balls)
    }

    /// Shows a friend's basket where it stands on their desktop, or takes it away (`spot` nil).
    func showFriendBasket(at spot: CGPoint?, balls: [Int], owner: String) {
        guard let spot else {
            removeFriendBasket()
            return
        }
        let feet = clamped(denormalized(spot))
        friendBasket.owner = owner
        if friendBasket.balls != balls { friendBasket.balls = balls }
        if friendBasketWindow == nil {
            // Only to look at: clicks go through it.
            let window = PetBasketWindow(basket: friendBasket, area: { nil }, onMouse: { _ in })
            window.place(feet: feet)
            window.orderFrontRegardless()
            friendBasketWindow = window
            startTimer()
        } else if friendBasketFeet != feet {
            friendBasketWindow?.place(feet: feet)
        }
        friendBasketFeet = feet
    }

    private func removeFriendBasket() {
        friendBasketWindow?.orderOut(nil)
        friendBasketWindow = nil
        friendBasketFeet = nil
        friendBasket.isHovered = false
    }

    // MARK: Basket

    func toggleBasket() {
        basketIsOut.toggle()
        UserDefaults.standard.set(basketIsOut, forKey: Self.basketOutKey)
        defer { PetPlay.shared.sendBasket() }
        if basketIsOut {
            openBasket()
        } else {
            basketWindow?.orderOut(nil)
            basketWindow = nil
            basketFeet = nil
            basketGrab = nil
            isPressingBasket = false
            basket.isHovered = false
            updateCursor()
        }
    }

    private func openBasket() {
        guard basketWindow == nil else { return }
        if screenID == nil {
            screenID = IslandLayout.notchScreen?.displayID
        }
        let feet = savedBasketSpot
        basketFeet = feet
        let window = PetBasketWindow(basket: basket, area: { PetWorld.shared.basketBounds }) { [weak self] event in
            MainActor.assumeIsolated { self?.basketMouse(event) }
        }
        window.place(feet: feet)
        window.orderFrontRegardless()
        basketWindow = window
        basketBounceStart = now
        startTimer()
    }

    /// Where it was left, or the bottom right corner.
    private var savedBasketSpot: CGPoint {
        if let spot = UserDefaults.standard.array(forKey: Self.basketSpotKey) as? [Double], spot.count == 2 {
            return clamped(denormalized(CGPoint(x: spot[0], y: spot[1])))
        }
        return CGPoint(x: area.maxX - 70, y: area.minY + 8)
    }

    /// The part of the screen it takes, for the pointer.
    var basketBounds: CGRect? {
        basketFeet.map { CGRect(x: $0.x - 31, y: $0.y - 2, width: 62, height: 56) }
    }

    /// Beside the basket, on the side your pet is on, to drop the ball in.
    private func basketSpot(for pet: PetActor) -> CGPoint? {
        guard let feet = basketFeet else { return nil }
        let side: CGFloat = pet.position.x < feet.x ? -1 : 1
        return clamped(CGPoint(x: feet.x + side * (32 + pet.height * 0.3), y: feet.y))
    }

    private func saveBasketBalls() {
        UserDefaults.standard.set(basket.balls, forKey: Self.basketBallsKey)
    }

    private func basketMouse(_ event: PetMouseView.Event) {
        guard let feet = basketFeet else { return }
        let pointer = NSEvent.mouseLocation
        switch event {
        case .down:
            isPressingBasket = true
            basketGrab = CGPoint(x: pointer.x - feet.x, y: pointer.y - feet.y)
        case .drag:
            guard let grab = basketGrab else { break }
            let moved = clamped(CGPoint(x: pointer.x - grab.x, y: pointer.y - grab.y))
            basketFeet = moved
            basketWindow?.place(feet: moved)
        case .up(let moved):
            isPressingBasket = false
            basketGrab = nil
            if moved {
                let spot = normalized(feet)
                UserDefaults.standard.set([Double(spot.x), Double(spot.y)], forKey: Self.basketSpotKey)
                PetPlay.shared.sendBasket()
                basketBounceStart = now
            } else {
                throwFromBasket()
            }
        }
        updateCursor()
        startTimer()
    }

    /// A ball out of the basket, for the pets to fetch; an empty one just wobbles.
    private func throwFromBasket() {
        basketBounceStart = now
        guard let feet = basketFeet, let color = basket.balls.last, ballCount < Self.maxBalls else { return }
        basket.balls.removeLast()
        saveBasketBalls()
        PetPlay.shared.sendBasket()
        PetPlay.shared.throwBall(color: color, from: CGPoint(x: feet.x, y: feet.y + 26))
    }

    /// Your pet drops the ball in its mouth into the basket.
    private func tossIntoBasket(from mine: PetActor) {
        mine.carriesBall = false
        guard let id = carried, let index = balls.firstIndex(where: { $0.id == id }) else { return }
        carried = nil
        let mouth = CGPoint(x: mine.position.x + (mine.pose.facingRight ? 1 : -1) * mine.height * 0.5, y: mine.position.y + mine.height * 0.3)
        balls[index].holder = "basket"
        balls[index].toss = (mouth, now)
        placeBall(balls[index].window, at: mouth)
        balls[index].window.orderFrontRegardless()
    }

    private func stepBasket(now: CFTimeInterval) {
        if let feet = friendBasketFeet {
            let hovered = CGRect(x: feet.x - 31, y: feet.y - 2, width: 62, height: 56).contains(NSEvent.mouseLocation)
            if friendBasket.isHovered != hovered { friendBasket.isHovered = hovered }
        }
        guard let bounds = basketBounds else { return }
        let hovered = bounds.contains(NSEvent.mouseLocation)
        if basket.isHovered != hovered { basket.isHovered = hovered }
        basketWindow?.catchesClicks(hovered || isPressingBasket)
        if let start = basketBounceStart {
            let progress = (now - start) / 0.35
            let bounce = progress >= 1 ? 0 : sin(progress * .pi)
            if basket.bounce != bounce { basket.bounce = bounce }
            if progress >= 1 { basketBounceStart = nil }
        }
    }

    // MARK: Pointer

    private func mouse(_ event: PetMouseView.Event) {
        guard let mine else { return }
        noteAttention()
        switch event {
        case .down:
            isPressing = true
        case .drag:
            isPressing = true
            plan = []
            let pointer = NSEvent.mouseLocation
            if case .held(let grab) = activity {
                mine.position = CGPoint(x: pointer.x - grab.x, y: pointer.y - grab.y)
            } else {
                activity = .held(grab: CGPoint(x: pointer.x - mine.position.x, y: pointer.y - mine.position.y))
                then = nil
                mine.say(.surprise, for: 0.8, now: now)
            }
        case .up(let moved):
            if moved, case .held = activity {
                let landing = clamped(CGPoint(x: mine.position.x, y: mine.position.y - 14))
                let speed = hypot(lastHeldVelocity.dx, lastHeldVelocity.dy)
                if speed > Self.throwSpeed {
                    // Thrown: it flies off the way the pointer went, and comes down a bit lower.
                    let velocity = CGVector(dx: lastHeldVelocity.dx * 0.9, dy: lastHeldVelocity.dy * 0.9)
                    activity = .flying(velocity: velocity, ground: max(area.minY, mine.position.y - .random(in: 60...160)))
                    then = nil
                    mine.say(.surprise, for: 0.7, now: now)
                } else {
                    activity = .drop(from: mine.position, to: landing, start: now)
                    if shake >= Self.dizzyShake {
                        then = .dizzy(until: now + 4)
                    }
                }
                lastHeldPointer = nil
                lastHeldVelocity = .zero
            } else if !moved {
                clicked()
            }
            isPressing = false
        }
        updateCursor()
        startTimer()
    }

    private func clicked() {
        guard let mine else { return }
        switch activity {
        case .dazed, .dizzy, .flying:
            // Too dizzy to answer.
            mine.say(.surprise, for: 0.8, now: now)
            return
        default:
            break
        }
        plan = []
        if case .sleep = activity {
            // Woken: a start, then a stretch.
            mine.say(.surprise, for: 1, now: now)
            awakeSince = now
            activity = .stretch(until: 0)
        } else {
            mine.say(.say, for: 1.1, now: now)
            activity = .hop(start: now)
        }
        then = nil
    }

    /// A friend's pet is only petted: a heart, here only.
    private func friendMouse(_ event: PetMouseView.Event) {
        guard case .up(false) = event, let friend else { return }
        friend.say(.heart, for: 1.2, now: now)
        PetSounds.shared.play(.happy, for: friend.look, volume: 0.8)
    }

    // MARK: Loop

    private func startTimer(interval: TimeInterval = 1.0 / 30) {
        if let timer, timer.timeInterval == interval { return }
        timer?.invalidate()
        if timer == nil { lastTick = now }
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { PetWorld.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Sitting or asleep alone, it only breathes: drawn less often.
    private var isCalm: Bool {
        guard basketBounceStart == nil, !isPressingBasket else { return false }
        // Only the basket out: it just waits for the pointer.
        if mine == nil, friend == nil, balls.isEmpty { return true }
        guard friend == nil, balls.isEmpty, mine?.isHovered != true else { return false }
        switch activity {
        case .sit, .sleep, .idle, .lie: return true
        default: return false
        }
    }

    /// Set again every tick while over a pet, since the app underneath may have set its own.
    private func updateCursor() {
        var isHeld = false
        if case .held = activity { isHeld = true }
        let cursor: NSCursor?
        if mine != nil, isPressing || isHeld {
            cursor = .closedHand
        } else if isPressingBasket {
            cursor = .closedHand
        } else if mine?.isHovered == true || basket.isHovered {
            cursor = .openHand
        } else if friend?.isHovered == true {
            cursor = .pointingHand
        } else {
            cursor = nil
        }
        if let cursor {
            PointingHandCoordinator.allowCursorInBackground()
            cursor.set()
        } else if shownCursor != nil {
            NSCursor.arrow.set()
        }
        shownCursor = cursor
    }

    private func stopTimerIfIdle() {
        guard mine == nil, friend == nil, balls.isEmpty, basketWindow == nil, friendBasketWindow == nil else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Doing something of its own, which playing can interrupt.
    private var isFree: Bool {
        switch activity {
        case .arriving, .leaving, .held, .drop, .flying, .dazed, .leap: return false
        case .walk where then.map({ if case .leaving = $0 { return true } else { return false } }) ?? false: return false
        default: return true
        }
    }

    private var isFetchable: Bool {
        if case .carry = activity { return false }
        return isFree
    }

    private func tick() {
        let time = now
        let elapsed = min(time - lastTick, 0.1)
        lastTick = time
        if let mine {
            stepMine(mine, elapsed: elapsed, now: time)
        }
        if let friend {
            stepFriend(friend, elapsed: elapsed, now: time)
        }
        stepBall(now: time)
        stepBasket(now: time)
        updateCursor()
        stopTimerIfIdle()
        if timer != nil {
            startTimer(interval: isCalm ? 1.0 / 12 : 1.0 / 30)
        }
    }

    private func stepMine(_ mine: PetActor, elapsed: Double, now: CFTimeInterval) {
        var pose = mine.pose
        pose.time += elapsed
        let pointer = NSEvent.mouseLocation
        let hovered = mine.bounds.contains(pointer)
        if hovered != mine.isHovered { mine.isHovered = hovered }
        var isHeld = false
        if case .held = activity { isHeld = true }
        mine.window?.catchesClicks(hovered || isHeld)
        if hovered && !wasHovered, isFree, !isAsleep {
            mine.say(.heart, for: 1.2, now: now)
            // A dog often bounces with joy when you come over.
            if mine.look.kind == .dog, Double.random(in: 0..<1) < 0.35, !isFetching, bowl == nil {
                activity = .hop(start: now)
                plan = []
            }
        }
        if hovered {
            noteAttention()
        }
        // How it feels: checked every frame, cheaply.
        let hungry = Date().timeIntervalSince(lastFed) > Self.hungerAfter
        if hungry != isHungry { isHungry = hungry }
        let bored = !hungry && friend == nil && now - lastPlayedWith > Self.boredAfter
        if bored != isBored { isBored = bored }
        wasHovered = hovered

        var speed: CGFloat = 0
        var target: CGPoint?
        var chewing = false
        var bowlInFront: PetActor.BowlInFront?
        pose.headDip = 0
        switch activity {
        case .arriving(let from, let to, let start):
            let progress = min((now - start) / 0.75, 1)
            mine.position = arc(from: from, to: to, progress: progress, height: 40)
            pose.action = .leap
            pose.flight = progress
            pose.tilt = (progress - 0.5) * 28
            pose.facingRight = to.x >= from.x
            if progress >= 1 {
                activity = .sit(until: now + 2)
                mine.say(.say, for: 1, now: now)
            }
        case .leaving(let from, let start):
            if start == 0 {
                activity = .leaving(from: mine.position, start: now)
                break
            }
            let progress = min((now - start) / 0.5, 1)
            mine.position = arc(from: from, to: notchDoor, progress: progress, height: 24)
            mine.opacity = 1 - max(progress - 0.6, 0) / 0.4
            pose.action = .jump
            if progress >= 1 {
                gone()
                return
            }
        case .idle(let until):
            pose.action = .stand
            // Looks round at the pointer when it's near.
            if hypot(pointer.x - mine.position.x, pointer.y - mine.position.y) < 160 {
                pose.facingRight = pointer.x >= mine.position.x
            }
            if now >= until { decide(now: now) }
        case .walk(let to, let run):
            target = to
            speed = run ? 130 : 46
            pose.action = run ? .run : .walk
        case .sit(let until):
            pose.action = .sit
            lookAround(&pose, now: now)
            if now >= until { decide(now: now) }
        case .sleep(let until):
            pose.action = .sleep
            if mine.bubble != .sleep { mine.bubble = .sleep }
            mine.bubbleUntil = now + 1
            if now >= until {
                // Wakes up: a long stretch, sometimes a yawn.
                mine.bubble = nil
                awakeSince = now
                activity = .stretch(until: 0)
                plan = Bool.random() ? [{ .yawn(until: $0 + 1.4) }] : []
            }
        case .held(let grab):
            mine.position = CGPoint(x: pointer.x - grab.x, y: pointer.y - grab.y)
            pose.action = .held
            pose.spin = 0
            if pose.isDizzy || mine.isDizzy {
                pose.isDizzy = false
                mine.isDizzy = false
            }
            measureShake(pointer: pointer, elapsed: elapsed)
            pose.isSqueezed = shake >= Self.dizzyShake * 0.5
        case .flying(var velocity, let ground):
            velocity.dy -= 2200 * elapsed
            var point = CGPoint(x: mine.position.x + velocity.dx * elapsed, y: mine.position.y + velocity.dy * elapsed)
            // Bounces off the screen's sides and top.
            if point.x < area.minX || point.x > area.maxX {
                velocity.dx = -velocity.dx * 0.6
                point.x = min(max(point.x, area.minX), area.maxX)
            }
            if point.y > area.maxY {
                velocity.dy = -abs(velocity.dy) * 0.5
                point.y = area.maxY
            }
            pose.action = .jump
            pose.facingRight = velocity.dx >= 0
            pose.spin += Double(hypot(velocity.dx, velocity.dy)) * elapsed * 0.9
            if point.y <= ground, velocity.dy < 0 {
                // Down with a bump: hard enough, it lies there seeing stars.
                point.y = ground
                pose.spin = 0
                if abs(velocity.dy) > 350 || shake >= Self.dizzyShake {
                    PetSounds.shared.play(.bonk)
                    activity = .dazed(until: now + 2.5)
                    mine.isDizzy = true
                    mine.bubble = nil
                } else {
                    activity = .sit(until: now + 2)
                }
                shake = 0
            } else {
                activity = .flying(velocity: velocity, ground: ground)
            }
            mine.position = point
        case .dazed(let until):
            pose.action = .sleep
            pose.isDizzy = true
            if now >= until {
                // Gets up, still wobbly.
                activity = .dizzy(until: now + 2.5)
            }
        case .dizzy(let until):
            // Staggers a little this way and that, eyes spinning.
            pose.action = .walk
            pose.isDizzy = true
            pose.isSqueezed = false
            let wander = CGFloat(sin(now * 2.3)) * 14
            mine.position = clamped(CGPoint(x: mine.position.x + wander * elapsed, y: mine.position.y + CGFloat(cos(now * 1.7)) * 6 * elapsed))
            pose.facingRight = wander > 0
            if now >= until {
                pose.isDizzy = false
                mine.isDizzy = false
                shake = 0
                activity = .sit(until: now + 3)
            }
        case .drop(let from, let to, let start):
            let progress = min((now - start) / 0.3, 1)
            mine.position = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress * progress)
            pose.action = .jump
            if progress >= 1 {
                mine.position = clamped(to)
                pose.isSqueezed = false
                if let next = then {
                    activity = next
                    then = nil
                    if case .dizzy = next {
                        mine.isDizzy = true
                        mine.bubble = nil
                        PetSounds.shared.play(.bonk)
                    }
                } else {
                    shake = 0
                    activity = .sit(until: now + 2)
                }
            }
        case .hop(let start):
            let progress = min((now - start) / 0.45, 1)
            pose.action = progress < 1 ? .jump : .stand
            let lift = sin(progress * .pi) * 14
            mine.window?.place(feet: CGPoint(x: mine.position.x, y: mine.position.y + lift))
            mine.pose = pose
            if progress >= 1 { activity = .idle(until: now + 1.2) }
            return
        case .chase(let until):
            if let friend, friendGoingHome == nil {
                target = friend.position
                speed = 120
                pose.action = .run
                if hypot(friend.position.x - mine.position.x, friend.position.y - mine.position.y) < (mine.height + friend.height) * 0.4 {
                    PetPlay.shared.send("tag")
                    mine.say(.heart, for: 1.5, now: now)
                    activity = .sit(until: now + 3)
                    target = nil
                }
            }
            if now >= until { activity = .idle(until: now + 1) }
        case .flee(let until):
            pose.action = .run
            if let friend {
                let away = CGPoint(x: mine.position.x - friend.position.x, y: mine.position.y - friend.position.y)
                let length = max(hypot(away.x, away.y), 1)
                let wanted = clamped(CGPoint(x: mine.position.x + away.x / length * 80, y: mine.position.y + away.y / length * 80))
                // Cornered: dash sideways instead.
                target = hypot(wanted.x - mine.position.x, wanted.y - mine.position.y) < 20
                    ? clamped(CGPoint(x: mine.position.x + (away.y >= 0 ? 80 : -80), y: mine.position.y - away.x / length * 80))
                    : wanted
                speed = 125
            }
            if now >= until {
                // Its turn to chase, now and then.
                if Bool.random(), friend != nil {
                    PetPlay.shared.send("chase")
                    activity = .chase(until: now + 4)
                } else {
                    activity = .idle(until: now + 1.5)
                }
            }
        case .fetch(let id):
            guard let ball = balls.first(where: { $0.id == id }), ball.holder == nil, ball.droppedAt == nil else {
                activity = nextFetch() ?? .sit(until: now + 2)
                break
            }
            // Stops with its mouth over the ball, not its feet on it.
            let side: CGFloat = ball.to.x >= mine.position.x ? 1 : -1
            let spot = CGPoint(x: ball.to.x - side * mine.height * 0.62, y: ball.to.y)
            target = spot
            speed = 140
            pose.action = .run
            let landed = now - ball.start >= Ball.flight
            if landed, hypot(spot.x - mine.position.x, spot.y - mine.position.y) < 10 {
                pose.facingRight = side > 0
                activity = .bite(id, start: now)
                target = nil
            }
        case .bite(let id, let start):
            let progress = (now - start) / 0.55
            let smooth = { (x: Double) -> Double in
                let x = min(max(x, 0), 1)
                return x * x * (3 - 2 * x)
            }
            pose.action = .stand
            if let ball = balls.first(where: { $0.id == id }), ball.holder == nil {
                pose.facingRight = ball.to.x >= mine.position.x
            }
            // Down with its mouth open, "hap!", and back up with it.
            pose.headDip = progress < 0.45 ? smooth(progress / 0.45) : 1 - smooth((progress - 0.45) / 0.55)
            chewing = progress < 0.4
            if progress >= 0.4, carried != id {
                guard let index = balls.firstIndex(where: { $0.id == id }), balls[index].holder == nil else {
                    // Gone, or the friend's pet got it first.
                    activity = nextFetch() ?? .sit(until: now + 2)
                    break
                }
                balls[index].holder = "me"
                balls[index].window.orderOut(nil)
                carried = id
                mine.ballColor = balls[index].color
                mine.carriesBall = true
                PetPlay.shared.send("got", ["id": .string(id)])
                PetSounds.shared.play(.chomp, for: mine.look, volume: 0.8)
            }
            if progress >= 1 {
                pose.headDip = 0
                // To the basket when it's out, or else to you.
                let toward = clamped(CGPoint(x: pointer.x, y: pointer.y - 20))
                activity = .carry(to: toward, until: now + (basketFeet != nil ? 15 : 6))
            }
        case .eat:
            break
        case .lie(let until):
            pose.action = .lie
            lookAround(&pose, now: now)
            if now >= until { decide(now: now) }
        case .stretch(let until):
            if until == 0 {
                activity = .stretch(until: now + .random(in: 1.6...2.4))
            }
            pose.action = .stretch
            pose.isHappy = true
            if until > 0, now >= until { decide(now: now) }
        case .groom(let until):
            pose.action = .groom
            if now >= until { decide(now: now) }
        case .yawn(let until):
            pose.action = .sit
            pose.isYawning = true
            if now >= until {
                pose.isYawning = false
                decide(now: now)
            }
        case .crouch(let until, let toward):
            if until == 0 {
                activity = .crouch(until: now + .random(in: 0.7...1.4), toward: toward)
            }
            pose.action = .crouch
            pose.facingRight = toward.x >= mine.position.x
            if until > 0, now >= until {
                // Pounce!
                let distance = hypot(toward.x - mine.position.x, toward.y - mine.position.y)
                activity = .leap(from: mine.position, to: clamped(toward), start: now, height: 24 + distance * 0.18)
            }
        case .leap(let from, let to, let start, let height):
            let distance = hypot(to.x - from.x, to.y - from.y)
            let progress = min((now - start) / min(0.32 + Double(distance) / 700, 0.8), 1)
            mine.position = arc(from: from, to: to, progress: progress, height: height)
            pose.action = .leap
            pose.flight = progress
            pose.tilt = (progress - 0.5) * 28
            pose.facingRight = to.x >= from.x
            if progress >= 1 {
                pose.tilt = 0
                pose.flight = 0
                arrived(now: now)
            }
        case .zoom(let to, _):
            target = to
            speed = 230
            pose.action = .run
            pose.isHappy = true
        case .sniff(let to):
            target = to
            speed = 24
            pose.action = .walk
            // Nose to the ground, following a smell.
            pose.headDip = 0.62 + sin(now * 5) * 0.1
        case .carry(let to, let until):
            let basketSpot = basketSpot(for: mine)
            let goal = basketSpot ?? to
            target = goal
            speed = basketSpot != nil ? 85 : 70
            pose.action = .walk
            if now >= until || hypot(goal.x - mine.position.x, goal.y - mine.position.y) < 6 {
                if let basketFeet, basketSpot != nil, now < until {
                    pose.facingRight = basketFeet.x > mine.position.x
                    mine.pose.facingRight = pose.facingRight
                    tossIntoBasket(from: mine)
                } else {
                    dropBall(at: mine.position, facingRight: pose.facingRight)
                }
                mine.say(.heart, for: 1.5, now: now)
                PetSounds.shared.play(.happy, for: mine.look)
                // More balls out there: off again after a moment.
                if nextFetch() != nil {
                    activity = .sit(until: now + 1.2)
                } else {
                    activity = .sit(until: now + 4)
                }
                target = nil
            }
        }

        if case .eat(let until) = activity {
            if until == 0 {
                // Starts on what's left in the bowl.
                activity = .eat(until: now + Self.eatingTime * max(bowl?.model.fill ?? 1, 0.2))
            } else if let bowl {
                pose.action = .stand
                pose.facingRight = bowl.spot.x > mine.position.x
                let left = max((until - now) / Self.eatingTime, 0)
                if bowl.model.fill != left { bowl.model.fill = left }
                chewing = sin(now * 12) > 0
                // Nose down in the bowl, coming up a touch between mouthfuls.
                pose.headDip = 1.92 + sin(now * 6) * 0.08
                bowlInFront = PetActor.BowlInFront(offset: CGVector(dx: bowl.spot.x - mine.position.x, dy: bowl.spot.y - mine.position.y),
                                                   fill: left)
                if now >= nextMunch {
                    PetSounds.shared.play(.munch, for: mine.look, volume: 0.7)
                    nextMunch = now + 0.55
                }
                if now >= until {
                    fed(mine, now: now)
                }
            } else {
                activity = .sit(until: now + 2)
            }
        }

        if let target, speed > 0 {
            let dx = target.x - mine.position.x, dy = target.y - mine.position.y
            let distance = hypot(dx, dy)
            let step = speed * elapsed
            if distance <= step {
                mine.position = target
                arrived(now: now)
            } else {
                mine.position.x += dx / distance * step
                mine.position.y += dy / distance * step
                if abs(dx) > 1 { pose.facingRight = dx > 0 }
            }
        }

        // Blinks now and then; happy while the pointer is on it or with a heart up.
        if now >= nextBlink {
            pose.isBlinking = true
            if now >= nextBlink + 0.13 {
                pose.isBlinking = false
                nextBlink = now + .random(in: 2...5)
            }
        }
        pose.isHappy = hovered || mine.bubble == .heart
        let panting = mine.look.kind == .dog && (pose.action == .run || now < pantUntil)
        pose.mouthOpen = chewing || (!mine.carriesBall && (mine.bubble == .say || mine.bubble == .hungry || panting))
        if case .yawn = activity {} else { pose.isYawning = false }
        if pose.action != .leap {
            pose.tilt = 0
            pose.flight = 0
        }
        if mine.bubble != nil, mine.bubble != .sleep, now >= mine.bubbleUntil {
            mine.bubble = nil
        }
        if pose != mine.pose { mine.pose = pose }
        if bowlInFront != mine.bowlInFront { mine.bowlInFront = bowlInFront }
        mine.window?.place(feet: mine.position)
    }

    private var isAsleep: Bool {
        if case .sleep = activity { return true }
        return false
    }

    private func arrived(now: CFTimeInterval) {
        guard let mine else { return }
        if case .zoom(_, let left) = activity {
            guard left > 0 else {
                // Done: flops down, panting.
                pantUntil = now + 8
                activity = Bool.random() ? .lie(until: now + .random(in: 6...12)) : .sit(until: now + .random(in: 4...7))
                return
            }
            let next = farTarget()
            if Double.random(in: 0..<1) < 0.4 {
                // A bound on the way.
                let ahead: CGFloat = next.x >= mine.position.x ? 1 : -1
                let landing = clamped(CGPoint(x: mine.position.x + ahead * .random(in: 90...150), y: mine.position.y + .random(in: -20...20)))
                activity = .leap(from: mine.position, to: landing, start: now, height: .random(in: 26...42))
                then = .zoom(to: next, left: left - 1)
            } else {
                activity = .zoom(to: next, left: left - 1)
            }
            return
        }
        if let next = then {
            activity = next
            then = nil
        } else {
            decide(now: now)
        }
    }

    /// Resting, it looks the other way now and then.
    private func lookAround(_ pose: inout PetPose, now: CFTimeInterval) {
        guard now >= nextLook else { return }
        nextLook = now + .random(in: 2.5...7)
        if Double.random(in: 0..<1) < 0.4 {
            pose.facingRight.toggle()
        }
    }

    /// Somewhere well across the screen, for zoomies.
    private func farTarget() -> CGPoint {
        guard let mine else { return area.center }
        for _ in 0..<8 {
            let point = CGPoint(x: .random(in: area.minX...area.maxX), y: .random(in: area.minY...area.maxY))
            if hypot(point.x - mine.position.x, point.y - mine.position.y) > 220 { return point }
        }
        return CGPoint(x: .random(in: area.minX...area.maxX), y: .random(in: area.minY...area.maxY))
    }

    /// Picks what to do next.
    private func decide(now: CFTimeInterval) {
        guard let mine else { return }
        // Food first.
        if let bowl {
            activity = .walk(to: bowlSpot(bowl.spot, for: mine), run: true)
            then = .eat(until: 0)
            return
        }
        // Then balls waiting.
        if let fetch = nextFetch() {
            activity = fetch
            then = nil
            plan = []
            return
        }
        // Then whatever comes next in what it's doing, like lying down before falling asleep.
        if !plan.isEmpty {
            activity = plan.removeFirst()(now)
            then = nil
            return
        }
        // Hungry or bored: now and then it says so, comes to you and looks up.
        if now >= nextMoan, isHungry || isBored {
            nextMoan = now + (isHungry ? .random(in: 120...240) : .random(in: 180...300))
            mine.say(isHungry ? .hungry : .bored, for: 2.8, now: now)
            let pointer = NSEvent.mouseLocation
            if area.contains(pointer) {
                activity = .walk(to: clamped(CGPoint(x: pointer.x + .random(in: -40...40), y: pointer.y - 40)), run: isHungry)
                then = .sit(until: now + .random(in: 4...7))
            } else {
                activity = .sit(until: now + 5)
                then = nil
            }
            return
        }
        // Says something for no reason, now and then.
        if now >= nextChatter, Double.random(in: 0..<1) < 0.12 {
            nextChatter = now + .random(in: 120...300)
            mine.say(.say, for: 1, now: now)
        }
        let roll = Double.random(in: 0..<1)
        let awake = now - awakeSince
        if let friend, friendGoingHome == nil, roll < 0.4 {
            if friend.pose.action == .sleep {
                // Curl up beside a sleeping friend.
                activity = .walk(to: beside(friend.position), run: false)
                then = .sleep(until: now + .random(in: 15...30))
            } else if Bool.random() {
                PetPlay.shared.send("chase")
                mine.say(.say, for: 0.9, now: now)
                activity = .chase(until: now + 4)
            } else {
                activity = .walk(to: beside(friend.position), run: false)
                then = .sit(until: now + .random(in: 3...6))
            }
            return
        }
        let pointer = NSEvent.mouseLocation
        let isCat = mine.look.kind == .cat
        let pointerNear = area.contains(pointer) && hypot(pointer.x - mine.position.x, pointer.y - mine.position.y) < 300
        then = nil
        switch roll {
        case ..<(isCat ? 0.04 : 0.07) where awake > 20 && !isHungry:
            // Zoomies: a burst of mad running about, with bounds on the way.
            activity = .zoom(to: farTarget(), left: Int.random(in: 2...4))
        case ..<0.15 where pointerNear && isCat:
            // Stalks the pointer: creeps up, crouches with its rear wiggling, and pounces;
            // then, now and then, washes as if nothing happened.
            let toward = clamped(CGPoint(x: pointer.x, y: pointer.y - 24))
            let side: CGFloat = toward.x >= mine.position.x ? -1 : 1
            activity = .walk(to: clamped(CGPoint(x: toward.x + side * .random(in: 90...130), y: toward.y)), run: false)
            then = .crouch(until: 0, toward: toward)
            plan = Bool.random() ? [{ .groom(until: $0 + .random(in: 3...5)) }] : []
        case ..<0.15 where pointerNear:
            // Wants to play: runs up, bows, and bounces.
            let side: CGFloat = pointer.x >= mine.position.x ? -1 : 1
            activity = .walk(to: clamped(CGPoint(x: pointer.x + side * 70, y: pointer.y - 30)), run: true)
            then = .stretch(until: 0)
            plan = [{ .hop(start: $0) }]
        case ..<0.36:
            // A wander; a dog often with its nose down, following a smell.
            if Double.random(in: 0..<1) < (isCat ? 0.15 : 0.5) {
                let target = wanderTarget()
                activity = .sniff(to: CGPoint(x: (mine.position.x + target.x) / 2, y: (mine.position.y + target.y) / 2))
            } else {
                activity = .walk(to: wanderTarget(), run: false)
            }
        case ..<0.42:
            activity = .walk(to: wanderTarget(), run: true)
        case ..<0.49 where area.contains(pointer):
            // Comes to see the pointer.
            activity = .walk(to: clamped(CGPoint(x: pointer.x + .random(in: -30...30), y: pointer.y - 30)), run: false)
            then = .sit(until: now + .random(in: 3...6))
        case ..<0.54 where basketFeet != nil:
            // Goes to lie by its basket.
            activity = .walk(to: basketSpot(for: mine) ?? wanderTarget(), run: false)
            then = Bool.random() ? .sit(until: now + .random(in: 4...8)) : .lie(until: now + .random(in: 8...16))
        case ..<0.64:
            activity = .sit(until: now + .random(in: 4...10))
        case ..<0.73:
            // Lies down for a rest; sometimes it dozes off.
            activity = .lie(until: now + .random(in: 8...20))
            if awake > 90, Double.random(in: 0..<1) < 0.3 {
                plan = [{ .sleep(until: $0 + .random(in: 25...60)) }]
            }
        case ..<0.8:
            // A wash, or a good scratch.
            activity = .groom(until: now + (isCat ? .random(in: 3.5...7) : .random(in: 1.8...3)))
        case ..<0.84:
            activity = .stretch(until: 0)
        case ..<(awake > 120 ? 0.97 : 0.93):
            activity = .idle(until: now + .random(in: 1.5...4))
        default:
            // Getting sleepy: a yawn, lies down, and drops off.
            activity = .yawn(until: now + 1.4)
            plan = [{ .lie(until: $0 + .random(in: 3...6)) }, { .sleep(until: $0 + .random(in: 25...60)) }]
        }
    }

    private func wanderTarget() -> CGPoint {
        guard let mine else { return area.center }
        // Mostly not far, now and then across the screen.
        if Double.random(in: 0..<1) < 0.25 {
            return CGPoint(x: .random(in: area.minX...area.maxX), y: .random(in: area.minY...area.maxY))
        }
        return clamped(CGPoint(x: mine.position.x + .random(in: -260...260), y: mine.position.y + .random(in: -160...160)))
    }

    private func beside(_ point: CGPoint) -> CGPoint {
        guard let mine else { return point }
        let gap = (mine.height + (friend?.height ?? mine.height)) / 2
        return clamped(CGPoint(x: point.x + (mine.position.x < point.x ? -1 : 1) * gap, y: point.y))
    }

    private func stepFriend(_ friend: PetActor, elapsed: Double, now: CFTimeInterval) {
        friend.pose.time += elapsed
        let hovered = friend.bounds.contains(NSEvent.mouseLocation)
        if hovered != friend.isHovered { friend.isHovered = hovered }
        friend.window?.catchesClicks(hovered)
        if let target = friendTarget {
            let pull = min(elapsed * (friendGoingHome != nil ? 6 : 7), 1)
            friend.position.x += (target.x - friend.position.x) * pull
            friend.position.y += (target.y - friend.position.y) * pull
        }
        if let leaving = friendGoingHome {
            let progress = (now - leaving) / 0.7
            friend.opacity = 1 - min(max(progress - 0.4, 0) / 0.6, 1)
            if progress >= 1 {
                friend.window?.orderOut(nil)
                friend.window = nil
                self.friend = nil
                friendGoingHome = nil
                return
            }
        }
        if friend.bubble == .heart, friend.isMine == false, now >= friend.bubbleUntil, friend.bubbleUntil > 0 {
            friend.bubble = nil
            friend.bubbleUntil = 0
        }
        friend.window?.place(feet: friend.position)
    }

    private func stepBall(now: CFTimeInterval) {
        var gone: [String] = []
        var inBasket: [Int] = []
        for ball in balls {
            if let toss = ball.toss {
                // Over the rim and in.
                let progress = min((now - toss.start) / 0.4, 1)
                let rim = basketFeet.map { CGPoint(x: $0.x, y: $0.y + 20) } ?? toss.from
                placeBall(ball.window, at: arc(from: toss.from, to: rim, progress: progress, height: 18))
                if progress >= 1 {
                    gone.append(ball.id)
                    if basketFeet != nil { inBasket.append(ball.color) }
                }
            } else if ball.holder == nil, ball.droppedAt == nil {
                let progress = min((now - ball.start) / Ball.flight, 1)
                guard progress < 1 || ball.window.isVisible else { continue }
                // Up out of the notch and down, with a bounce at the end.
                var point = arc(from: ball.from, to: ball.to, progress: min(progress / 0.8, 1), height: 90)
                if progress > 0.8 {
                    point = CGPoint(x: ball.to.x, y: ball.to.y + sin((progress - 0.8) / 0.2 * .pi) * 10)
                }
                placeBall(ball.window, at: point)
            } else if let dropped = ball.droppedAt, now - dropped > 8 {
                gone.append(ball.id)
            } else if ball.droppedAt == nil, ball.holder == "friend", now - ball.start > 30 {
                gone.append(ball.id)
            }
        }
        gone.forEach(removeBall)
        if !inBasket.isEmpty {
            PetSounds.shared.play(.plop)
            basket.balls.append(contentsOf: inBasket)
            saveBasketBalls()
            PetPlay.shared.sendBasket()
            basketBounceStart = now
        }
    }

    private func dropBall(at point: CGPoint, facingRight: Bool) {
        mine?.carriesBall = false
        guard let id = carried, let index = balls.firstIndex(where: { $0.id == id }) else { return }
        carried = nil
        let spot = CGPoint(x: point.x + (facingRight ? 1 : -1) * (mine?.height ?? Self.petHeight) * 0.5, y: point.y)
        balls[index].droppedAt = now
        placeBall(balls[index].window, at: spot)
        balls[index].window.orderFrontRegardless()
    }

    private func placeBall(_ window: PetBallWindow, at point: CGPoint) {
        window.setFrameOrigin(CGPoint(x: (point.x - PetBallWindow.size / 2).rounded(), y: point.y.rounded()))
    }

    private func arc(from: CGPoint, to: CGPoint, progress: Double, height: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * progress,
                y: from.y + (to.y - from.y) * progress + sin(progress * .pi) * height)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
