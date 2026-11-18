import AppKit
import Combine
import OSLog
import SwiftUI

/// Tabs of the expanded notch panel, modeled after NotchNook.
enum NotchTab: String, CaseIterable {
    case nook = "Nook"
    case media = "Media"
    case alerts = "Alerts"
    case poke = "Poke"
    case timer = "Timer"
    case vpn = "VPN"
    case game = "Game"
    case pet = "Pet"

    var icon: String {
        switch self {
        case .nook: return "sparkles"
        case .media: return "music.note"
        case .alerts: return "bell.fill"
        case .poke: return "hand.point.right.fill"
        case .timer: return "timer"
        case .vpn: return "lock.shield.fill"
        case .game: return "gamecontroller.fill"
        case .pet: return "pawprint.fill"
        }
    }

    /// Beside the pin and settings, right of the notch: the left side is full.
    var isBesideSettings: Bool {
        self == .vpn || self == .game || self == .pet
    }
}

/// Where the island lives (attached to the MacBook notch, or floating freely) and whether it is open.
class IslandLayout: ObservableObject {
    @Published var isPinnedToNotch: Bool {
        didSet { UserDefaults.standard.set(isPinnedToNotch, forKey: Self.pinnedKey) }
    }
    /// Open the notch when the pointer rests on it, close it when the pointer leaves.
    @Published var openOnHover: Bool {
        didSet { UserDefaults.standard.set(openOnHover, forKey: Self.openOnHoverKey) }
    }
    /// Eyes in the wings beside the notch while nothing is live (gear menu → Animations).
    @Published var showsEyes: Bool {
        didSet { UserDefaults.standard.set(showsEyes, forKey: Self.showsEyesKey) }
    }
    /// A friend's poke shakes the notch and rains emoji.
    @Published var pokeEffects: Bool {
        didSet { UserDefaults.standard.set(pokeEffects, forKey: Self.pokeEffectsKey) }
    }
    /// Which season's look the notch has (gear menu → Animations → Season): by the date, none,
    /// or one picked by hand.
    @Published var seasonSetting: SeasonSetting {
        didSet { UserDefaults.standard.set(seasonSetting.rawValue, forKey: Self.seasonKey) }
    }
    /// The season showing now. By the date it changes at midnight (see `init`).
    var season: Season? {
        seasonSetting.season(on: Date())
    }
    /// The face beside the notch: the eyes, or in a season the eyes dressed up for it (the
    /// snowman at Christmas), which show even with the eyes turned off.
    var showsFace: Bool {
        showsEyes || season != nil
    }
    private var dayObservers: [Any] = []
    /// The open notch wider and taller than usual, for more room (the arrows beside the pin).
    @Published private(set) var isWide: Bool {
        didSet { UserDefaults.standard.set(isWide, forKey: Self.wideKey) }
    }
    /// The tab's content fades out while the open notch changes size, so it isn't seen squeezing.
    @Published private(set) var isResizing = false
    /// After the notch narrows, the pointer (on the arrows) is left beside it: it stays open until
    /// the pointer comes back, or a click elsewhere.
    var holdsOpenForPointer = false
    @Published var isExpanded = false
    /// Pinned open: the open notch doesn't close when the pointer leaves it or on a click elsewhere.
    @Published var staysOpen = false
    @Published var selectedTab: NotchTab = .nook
    /// Size of the floating island as laid out by SwiftUI; the floating window follows it.
    @Published var floatingContentSize: CGSize = .zero
    /// Whether the collapsed island shows its wings (music playing / unread notifications).
    /// When idle it is exactly as wide as the physical notch, like the iPhone's Dynamic Island.
    @Published private(set) var showsWings = false
    /// Whether the collapsed island shows another app's notification below the notch.
    @Published private(set) var showsBanner = false
    /// Whether the collapsed island shows the volume or brightness level beside the notch.
    @Published private(set) var showsHUD = false
    @Published private(set) var notchSize: CGSize
    /// Goes up each time the island's monitor changes (it moved, or monitors were plugged in or
    /// out), for views placed against the screen.
    @Published private(set) var screenChanges = 0
    /// How big the open panel is: YouTube in the Media tab takes more room.
    @Published private(set) var panelStyle = PanelStyle.regular

    enum PanelStyle {
        /// 640×180, or 900×280 when wide.
        case regular
        /// Taller for a YouTube video; below the tab bar it narrows to the video.
        case video
        /// Taller for Notch Drop's wells, 20 blocks deep.
        case game
    }

    /// Width of the black "wings" shown beside the physical notch while collapsed.
    static let notchWing: CGFloat = 40
    /// The volume and brightness levels take wider wings.
    static let notchHUDWing: CGFloat = 76
    static let notchExpandedWidth: CGFloat = 640
    static let notchExpandedHeight: CGFloat = 180
    static let notchWideWidth: CGFloat = 900
    static let notchWideHeight: CGFloat = 280
    /// Room around the open panel's content, below the tab bar.
    static let expandedHorizontalPadding: CGFloat = 20
    static let expandedTopPadding: CGFloat = 6
    static let expandedBottomPadding: CGFloat = 14
    /// Height of the YouTube video in the Media tab; it is 16:9, centered in the panel.
    static let videoHeight: CGFloat = 200
    /// Below the tab bar the video panel narrows to the video plus this margin on each side, so
    /// there is no black beside the video.
    static let videoBodyMargin: CGFloat = 10
    static var videoBodyWidth: CGFloat {
        (videoHeight * 16 / 9).rounded(.up) + videoBodyMargin * 2
    }
    /// The side of one block of Notch Drop's well.
    static func gameBlock(wide: Bool) -> CGFloat {
        wide ? 16 : 13
    }
    /// Opening and closing glide without overshoot.
    static let expandAnimation = Animation.spring(response: 0.4, dampingFraction: 1)

    /// How the island grows.
    var growAnimation: Animation {
        Self.expandAnimation
    }
    static let collapseAnimation = Animation.spring(response: 0.32, dampingFraction: 1)

    /// Set by the notch window: enlarges it to the given size before a growing animation starts,
    /// so the first animated frame still has the old size instead of jumping to the new one.
    var prepareToGrow: ((CGSize) -> Void)?

    private static let pinnedKey = "islandPinnedToNotch"
    private static let openOnHoverKey = "islandOpenOnHover"
    private static let showsEyesKey = "islandShowsEyes"
    private static let pokeEffectsKey = "islandPokeEffects"
    private static let wideKey = "islandWide"
    private static let seasonKey = "islandSeason"

    init() {
        isPinnedToNotch = UserDefaults.standard.object(forKey: Self.pinnedKey) as? Bool ?? true
        openOnHover = UserDefaults.standard.object(forKey: Self.openOnHoverKey) as? Bool ?? true
        showsEyes = UserDefaults.standard.object(forKey: Self.showsEyesKey) as? Bool ?? true
        pokeEffects = UserDefaults.standard.object(forKey: Self.pokeEffectsKey) as? Bool ?? true
        isWide = UserDefaults.standard.bool(forKey: Self.wideKey)
        seasonSetting = UserDefaults.standard.string(forKey: Self.seasonKey).flatMap(SeasonSetting.init) ?? .byDate
        notchSize = Self.measureNotch()
        // A new day can start a season or end one: after midnight, or waking up on a later day.
        let refresh: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
        dayObservers = [
            NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh),
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh),
        ]
    }

    var notchCollapsedSize: CGSize {
        CGSize(width: notchSize.width + (showsWings ? Self.notchWing * 2 : 0), height: notchSize.height)
    }

    /// Transparent room around the open island so a poke's shake isn't clipped.
    static let overshootMargin: CGFloat = 24

    var notchBannerSize: CGSize {
        CGSize(width: 380, height: notchSize.height + 60)
    }

    var notchHUDSize: CGSize {
        CGSize(width: notchSize.width + Self.notchHUDWing * 2, height: notchSize.height)
    }

    var notchExpandedSize: CGSize {
        size(of: panelStyle)
    }

    /// The usual width and tab bar, with room below for the video.
    private func size(of style: PanelStyle, wide: Bool? = nil) -> CGSize {
        let wide = wide ?? isWide
        // Never wider than the screen, leaving some of it on each side.
        let screenWidth = Self.notchScreen?.frame.width ?? .greatestFiniteMagnitude
        let width = wide ? min(Self.notchWideWidth, screenWidth - 160) : Self.notchExpandedWidth
        switch style {
        case .regular:
            return CGSize(width: width, height: wide ? Self.notchWideHeight : Self.notchExpandedHeight)
        case .video:
            return CGSize(width: width,
                          height: notchSize.height + Self.expandedTopPadding + Self.videoHeight + Self.expandedBottomPadding)
        case .game:
            return CGSize(width: width,
                          height: notchSize.height + Self.expandedTopPadding + Self.gameBlock(wide: wide) * CGFloat(NotchDropGame.rows) + Self.expandedBottomPadding)
        }
    }

    var notchWindowSize: CGSize {
        if isExpanded {
            return notchExpandedWindowSize
        }
        // The level shows over a banner for a moment; the window keeps room for the banner.
        let base = showsBanner ? notchBannerWindowSize : notchCollapsedSize
        guard showsHUD else { return base }
        return CGSize(width: max(base.width, notchHUDSize.width), height: max(base.height, notchHUDSize.height))
    }

    private var notchBannerWindowSize: CGSize {
        CGSize(width: notchBannerSize.width + Self.overshootMargin * 2, height: notchBannerSize.height + Self.overshootMargin)
    }

    var notchExpandedWindowSize: CGSize {
        Self.windowSize(for: notchExpandedSize)
    }

    /// The largest the open island gets, for the island view's fixed size inside the window.
    var notchLargestWindowSize: CGSize {
        let sizes = [PanelStyle.regular, .video, .game].flatMap { [size(of: $0, wide: false), size(of: $0, wide: true)] }
        return Self.windowSize(for: CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0))
    }

    private static func windowSize(for islandSize: CGSize) -> CGSize {
        CGSize(width: islandSize.width + overshootMargin * 2, height: islandSize.height + overshootMargin)
    }

    func toggleExpanded() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func expand() {
        guard !isExpanded else { return }
        AnimationMonitor.shared.begin("open \(selectedTab) \(isWide ? "wide" : "normal")")
        grow(to: notchExpandedWindowSize) {
            self.isExpanded = true
        }
    }

    func setPanelStyle(_ style: PanelStyle) {
        guard style != panelStyle else { return }
        AnimationMonitor.shared.mark("panel style \(style)")
        let size = size(of: style)
        if size.height >= notchExpandedSize.height {
            grow(to: Self.windowSize(for: size)) {
                self.panelStyle = style
            }
        } else {
            withAnimation(Self.collapseAnimation) {
                panelStyle = style
            }
        }
    }

    /// Changing size, without bounce: the content fades out, the black shape grows or shrinks,
    /// and the content fades back in at the new size.
    static let resizeAnimation = Animation.spring(response: 0.35, dampingFraction: 1)

    /// A size for the usual open notch, or for the wide one: the tabs use the room it adds.
    func wide<T>(_ normal: T, _ wide: T) -> T {
        isWide ? wide : normal
    }

    func setWide(_ wide: Bool) {
        guard wide != isWide, !isResizing else { return }
        guard isExpanded else {
            isWide = wide
            return
        }
        let size = size(of: panelStyle, wide: wide)
        AnimationMonitor.shared.begin("\(wide ? "widen" : "narrow") \(selectedTab)", duration: 1.2)
        if !wide {
            holdsOpenForPointer = true
        }
        withAnimation(.easeOut(duration: 0.1)) {
            isResizing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if wide {
                // The window grows first, so the shape has room from the first frame.
                self.prepareToGrow?(Self.windowSize(for: size))
            }
            DispatchQueue.main.async {
                AnimationMonitor.shared.mark("resize starts")
                withAnimation(Self.resizeAnimation) {
                    self.isWide = wide
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    AnimationMonitor.shared.mark("content fades in")
                    withAnimation(.easeIn(duration: 0.15)) {
                        self.isResizing = false
                    }
                }
            }
        }
    }

    /// Back to the regular panel, unless another view has set its own style in the meantime
    /// (a view's disappearing can come after the next one appears).
    func resetPanelStyle(from style: PanelStyle) {
        if panelStyle == style {
            setPanelStyle(.regular)
        }
    }

    func collapse() {
        guard isExpanded else { return }
        staysOpen = false
        holdsOpenForPointer = false
        AnimationMonitor.shared.begin("close \(selectedTab) \(isWide ? "wide" : "normal")")
        withAnimation(Self.collapseAnimation) {
            isExpanded = false
        }
    }

    func setShowsWings(_ show: Bool) {
        guard show != showsWings else { return }
        if show {
            let size = CGSize(width: notchSize.width + Self.notchWing * 2, height: notchSize.height)
            grow(to: size) {
                self.showsWings = true
            }
        } else {
            withAnimation(Self.collapseAnimation) {
                showsWings = false
            }
        }
    }

    func setShowsBanner(_ show: Bool) {
        guard show != showsBanner else { return }
        if show {
            grow(to: notchBannerWindowSize) {
                self.showsBanner = true
            }
        } else {
            withAnimation(Self.collapseAnimation) {
                showsBanner = false
            }
        }
    }

    func setShowsHUD(_ show: Bool) {
        guard show != showsHUD else { return }
        if show {
            grow(to: notchHUDSize) {
                self.showsHUD = true
            }
        } else {
            withAnimation(Self.collapseAnimation) {
                showsHUD = false
            }
        }
    }

    private func grow(to size: CGSize, _ change: @escaping () -> Void) {
        guard let prepareToGrow else {
            withAnimation(growAnimation, change)
            return
        }
        prepareToGrow(size)
        DispatchQueue.main.async {
            AnimationMonitor.shared.mark("grow starts")
            withAnimation(self.growAnimation, change)
        }
    }

    func refreshNotch() {
        notchSize = Self.measureNotch()
        screenChanges += 1
    }

    /// The monitor the pointer was last on, by its display ID, so the island follows you between
    /// monitors. Nil until the pointer first moves.
    private static var pointerScreenID: CGDirectDisplayID?

    /// The monitor the pointer was last on. Before that, or once that monitor is unplugged, the
    /// built-in display with a notch, or the main display on Macs without one.
    static var notchScreen: NSScreen? {
        if let id = pointerScreenID, let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            return screen
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Puts the island on `screen`, measuring its notch (or the virtual one); false when it's
    /// already there.
    func move(to screen: NSScreen) -> Bool {
        guard let id = screen.displayID, id != Self.notchScreen?.displayID else { return false }
        Self.pointerScreenID = id
        refreshNotch()
        return true
    }

    /// Whether an app is full screen on `screen`: one of its windows covers all of it, the menu
    /// bar's place included. Only windows' sizes are read, which needs no permission.
    static func hasFullScreenApp(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // Window bounds count from the top-left of the main display, screens from its bottom-left.
        let target = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) })
            else { return false }
            return abs(bounds.minX - target.minX) < 1 && abs(bounds.minY - target.minY) < 1
                && abs(bounds.width - target.width) < 1 && abs(bounds.height - target.height) < 1
        }
    }

    /// Without a real notch, a menu-bar-height "virtual notch" is used instead.
    private static func measureNotch() -> CGSize {
        guard let screen = notchScreen else { return CGSize(width: 185, height: 32) }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 185, height: menuBar > 0 ? menuBar : menuBarHeight(on: screen) ?? 24)
    }

    /// The height of the menu bar macOS draws on `screen`, which a second monitor's visible frame
    /// can leave out: the window server's menu bar window along that monitor's top edge.
    private static func menuBarHeight(on screen: NSScreen) -> CGFloat? {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let top = primary.frame.maxY - screen.frame.maxY
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return windows.lazy.compactMap { info -> CGFloat? in
            guard (info[kCGWindowLayer as String] as? Int) == menuLevel,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  abs(bounds.minX - screen.frame.minX) < 1, abs(bounds.minY - top) < 1,
                  abs(bounds.width - screen.frame.width) < 1, bounds.height > 0, bounds.height < 60
            else { return nil }
            return bounds.height
        }.first
    }
}

/// Borderless always-on-top panel that hosts the island and stays visible on every Space.
///
/// The window size is always set here, never by SwiftUI. (When SwiftUI also sized the window,
/// the two fought over it and AppKit crashed with "more Update Constraints in Window passes than
/// there are views in the window".)
/// Floating mode: the window follows the size the floating island reports. Notch mode: the window
/// grows *before* the expand animation and shrinks *after* the collapse one, so the island
/// animates smoothly and the empty area never blocks clicks on the menu bar.
class FloatingPanel: NSPanel {
    private let layout: IslandLayout
    private let container = IslandContainerView()
    private var cancellables = Set<AnyCancellable>()
    private var shrinkWorkItem: DispatchWorkItem?
    private var hoverOpenWorkItem: DispatchWorkItem?
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var mouseMonitors: [Any] = []
    private var isMouseInside = false
    /// The frame of the monitor the island is on, so most pointer moves don't look at the monitors.
    private var islandScreenFrame: NSRect?
    /// A monitor without a notch with an app full screen on it: the island would cover the top of
    /// that app, so it stays off it until the Space changes.
    private var fullScreenDisplayID: CGDirectDisplayID?
    /// Set for a second after the Space changes, while an app may still be growing to full screen.
    private var spaceCheckWorkItem: DispatchWorkItem?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicIsland", category: "Panel")

    private static let floatingPositionKey = "islandFloatingTopLeft"

    var isDraggable: Bool { !layout.isPinnedToNotch }

    init(hostingView: NSHostingView<AnyView>, layout: IslandLayout) {
        self.layout = layout
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // The hosting view sits inside a plain container instead of being the content view itself:
        // as a window's content view, NSHostingView keeps setting the window's min/max size from
        // the SwiftUI content, even with empty sizingOptions.
        hostingView.sizingOptions = []
        container.addSubview(hostingView)
        contentView = container
        hostingView.frame = container.bounds

        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false

        // Hover-to-open watches the pointer with event monitors, which see it even while this
        // panel is inactive. Global: pointer over other apps' windows. Local: over this panel.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.pointerMoved()
        }) {
            mouseMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) {
            mouseMonitors.append(monitor)
        }

        // In floating mode the window resizes itself with the content; re-anchor it every time.
        NotificationCenter.default.addObserver(self, selector: #selector(reposition), name: NSWindow.didResizeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        layout.$isPinnedToNotch
            .sink { [weak self] pinned in self?.applyMode(pinnedToNotch: pinned) }
            .store(in: &cancellables)
        layout.$floatingContentSize
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.fitFloatingContent() } }
            .store(in: &cancellables)
        Publishers.CombineLatest4(layout.$isExpanded, layout.$showsWings, layout.$showsBanner, layout.$showsHUD)
            .dropFirst()
            // @Published emits before the stored value changes, so read the new state on the next pass.
            .sink { [weak self] _ in DispatchQueue.main.async { self?.notchStateChanged() } }
            .store(in: &cancellables)
        layout.$isWide
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.notchStateChanged() } }
            .store(in: &cancellables)
        layout.$panelStyle
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.notchStateChanged() } }
            .store(in: &cancellables)

        layout.prepareToGrow = { [weak self] size in
            guard let self, self.layout.isPinnedToNotch else { return }
            self.shrinkWorkItem?.cancel()
            self.setNotchSize(CGSize(width: max(self.frame.width, size.width), height: max(self.frame.height, size.height)))
        }
    }

    // Becoming key lets the first click reach SwiftUI buttons, and lets us notice clicks outside.
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        // Clicking anywhere else closes the notch island, like the real Dynamic Island.
        guard layout.isPinnedToNotch && !layout.staysOpen && layout.isExpanded else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let location = NSEvent.mouseLocation
        // Pritunl coming to the front while a VPN connects or disconnects from the notch isn't a click
        // elsewhere: with the pointer still on the panel, it stays, and closes once the pointer
        // leaves. Other apps coming forward, like one a notification or the artwork opens, close it.
        if layout.openOnHover && VPNManager.shared.mayTakeFocus && containsPointer(location) {
            log.info("Lost the focus to \(app, privacy: .public) with the pointer on the panel at \(Int(location.x)), \(Int(location.y)); staying open")
            return
        }
        log.info("Lost the focus to \(app, privacy: .public), pointer at \(Int(location.x)), \(Int(location.y)) (panel \(Int(self.frame.minX))...\(Int(self.frame.maxX)), \(Int(self.frame.minY))...\(Int(self.frame.maxY))); closing")
        layout.collapse()
    }

    /// Whether the point is on the panel, its edges included: the pointer pushed against the top of
    /// the screen sits on the panel's top edge, which `NSRect.contains` leaves out.
    private func containsPointer(_ point: NSPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    // MARK: Hover

    private func pointerMoved() {
        guard layout.isPinnedToNotch, isVisible else { return }
        let location = NSEvent.mouseLocation
        followPointer(to: location)
        guard layout.openOnHover else { return }
        let inside = layout.isExpanded ? containsPointer(location) : notchHoverRect.contains(location)
        guard inside != isMouseInside else { return }
        isMouseInside = inside
        if inside {
            pointerEntered()
        } else {
            pointerExited()
        }
    }

    private func pointerEntered() {
        hoverCloseWorkItem?.cancel()
        layout.holdsOpenForPointer = false
        // Pointing at a notification banner (to read it) shouldn't cover it with the open panel.
        guard layout.isPinnedToNotch, layout.openOnHover, !layout.isExpanded, !layout.showsBanner else { return }

        // A short delay so sweeping past the notch on the way to the menu bar doesn't open it.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.layout.isExpanded, !self.layout.showsBanner, self.notchHoverRect.contains(NSEvent.mouseLocation) else { return }
            self.layout.expand()
        }
        hoverOpenWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func pointerExited() {
        hoverOpenWorkItem?.cancel()
        guard layout.isPinnedToNotch, layout.openOnHover, layout.isExpanded, !layout.staysOpen, !layout.holdsOpenForPointer else { return }
        scheduleHoverClose()
    }

    private func scheduleHoverClose() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.layout.isExpanded, !self.layout.staysOpen else { return }
            // A menu (like the gear menu) is open and tracking the mouse: check again once it closes.
            if RunLoop.current.currentMode == .eventTracking {
                self.scheduleHoverClose()
                return
            }
            let location = NSEvent.mouseLocation
            guard !self.containsPointer(location) else { return }
            // Text being typed, like a reply to a poke, isn't lost when the pointer wanders off;
            // a click elsewhere still closes it.
            if self.isKeyWindow, let editor = self.firstResponder as? NSTextView, !editor.string.isEmpty {
                return
            }
            self.log.info("Pointer left the panel at \(Int(location.x)), \(Int(location.y)) (panel \(Int(self.frame.minX))...\(Int(self.frame.maxX)), \(Int(self.frame.minY))...\(Int(self.frame.maxY))); closing")
            self.layout.collapse()
        }
        hoverCloseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: Monitors

    /// With more than one monitor, the closed island moves to the one the pointer is on. Open, it
    /// stays put, so it can be used; it follows once it has closed and the window has shrunk back,
    /// so a closing panel isn't cut off. It stays off a monitor without a notch that has an app
    /// full screen, where it would cover the top of that app.
    private func followPointer(to location: NSPoint) {
        if let current = islandScreenFrame, Self.screenFrame(current, contains: location) { return }
        guard layout.isPinnedToNotch, !layout.isExpanded, spaceCheckWorkItem == nil, NSScreen.screens.count > 1,
              abs(frame.width - layout.notchWindowSize.width) < 1, abs(frame.height - layout.notchWindowSize.height) < 1,
              let screen = NSScreen.screens.first(where: { Self.screenFrame($0.frame, contains: location) }),
              let id = screen.displayID, id != fullScreenDisplayID
        else { return }
        if screen.safeAreaInsets.top == 0 && IslandLayout.hasFullScreenApp(on: screen) {
            fullScreenDisplayID = id
            log.info("Staying off the monitor with the pointer: an app is full screen on it")
            return
        }
        moveIsland(to: screen)
    }

    /// The pointer pushed against a monitor's top edge is on that monitor, so the top edge counts.
    private static func screenFrame(_ frame: NSRect, contains point: NSPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    private func moveIsland(to screen: NSScreen) {
        islandScreenFrame = screen.frame
        guard layout.move(to: screen) else { return }
        log.info("Moved to a monitor \(Int(screen.frame.width))×\(Int(screen.frame.height)) (\(screen.safeAreaInsets.top > 0 ? "with" : "without", privacy: .public) a notch)")
        hoverOpenWorkItem?.cancel()
        isMouseInside = false
        container.fixedContentSize = layout.notchLargestWindowSize
        setNotchSize(layout.notchWindowSize)
    }

    /// Going full screen (or leaving it) switches Spaces; once the app has finished filling the
    /// monitor, an island over a full-screen app goes back to the display with the notch.
    @objc private func spaceChanged() {
        fullScreenDisplayID = nil
        spaceCheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.spaceCheckWorkItem = nil
            self?.settle()
        }
        spaceCheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Once the island is closed and its window back to size: off a full-screen app, then to the
    /// pointer's monitor.
    private func settle() {
        guard layout.isPinnedToNotch, !layout.isExpanded else { return }
        if let screen = IslandLayout.notchScreen, screen.safeAreaInsets.top == 0,
           let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           IslandLayout.hasFullScreenApp(on: screen) {
            fullScreenDisplayID = screen.displayID
            log.info("An app went full screen on the island's monitor; back to the display with the notch")
            moveIsland(to: notched)
        }
        followPointer(to: NSEvent.mouseLocation)
    }

    /// The collapsed island on screen, slightly enlarged so the very edge of the notch counts.
    private var notchHoverRect: NSRect {
        guard let screen = IslandLayout.notchScreen else { return .zero }
        let size = layout.notchCollapsedSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
            .insetBy(dx: -4, dy: -4)
    }

    // Allow sitting on top of the menu bar, where AppKit would normally push windows down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    private func applyMode(pinnedToNotch: Bool) {
        level = pinnedToNotch ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) : .floating
        hasShadow = !pinnedToNotch
        // Dark appearance so system colors stay readable against the black notch. Menus (like
        // Settings) follow the app's appearance, not the window's, so the app goes dark too.
        appearance = pinnedToNotch ? NSAppearance(named: .darkAqua) : nil
        NSApp.appearance = appearance
        container.fixedContentSize = pinnedToNotch ? layout.notchLargestWindowSize : nil

        // @Published emits before the stored value changes, so update on the next run loop pass.
        DispatchQueue.main.async {
            if pinnedToNotch {
                self.setNotchSize(self.layout.notchWindowSize)
            } else {
                self.fitFloatingContent()
            }
        }
    }

    /// Floating mode: size the window to the island (which reports its size) and keep it in place.
    private func fitFloatingContent() {
        let size = layout.floatingContentSize
        guard !layout.isPinnedToNotch, size.width > 0, size.height > 0 else { return }
        if frame.size != size {
            setContentSize(size)
        }
        reposition()
    }

    private func notchStateChanged() {
        guard layout.isPinnedToNotch else { return }
        shrinkWorkItem?.cancel()

        let target = layout.notchWindowSize
        if target.width >= frame.width && target.height >= frame.height {
            setNotchSize(target)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.setNotchSize(self.layout.notchWindowSize)
                // The pointer may have gone to another monitor while the panel was open.
                self.settle()
            }
            shrinkWorkItem = work
            // Wait for the shrinking spring to settle before making the window smaller.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    /// Sizes the window and centers it under the top edge of the notch screen.
    private func setNotchSize(_ size: CGSize) {
        guard let screen = IslandLayout.notchScreen else { return }
        let rect = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        if rect != frame {
            let started = CACurrentMediaTime()
            setFrame(rect, display: true)
            AnimationMonitor.shared.mark("window \(Int(size.width))×\(Int(size.height)) took \(Int((CACurrentMediaTime() - started) * 1000)) ms")
        }
    }

    @objc private func screensChanged() {
        islandScreenFrame = nil
        fullScreenDisplayID = nil
        layout.refreshNotch()
        if layout.isPinnedToNotch {
            container.fixedContentSize = layout.notchLargestWindowSize
            setNotchSize(layout.notchWindowSize)
        } else {
            reposition()
        }
    }

    /// Keeps the floating island's top-left corner where the user left it.
    @objc func reposition() {
        guard !layout.isPinnedToNotch, frame.width > 0 else { return }
        let topLeft = savedFloatingTopLeft ?? defaultFloatingTopLeft
        let origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        if origin != frame.origin {
            setFrameOrigin(origin)
        }
    }

    /// Called after the user finishes dragging the floating island.
    func saveFloatingPosition() {
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: Self.floatingPositionKey)
    }

    private var savedFloatingTopLeft: NSPoint? {
        UserDefaults.standard.string(forKey: Self.floatingPositionKey).map(NSPointFromString)
    }

    private var defaultFloatingTopLeft: NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - 8)
    }
}

/// The panel's content view. In notch mode the island's SwiftUI view keeps one fixed size,
/// centered at the top, and the window only shows the part of it that fits. SwiftUI then never
/// sees the window resize: when it did, the resize could land in the same pass as the opening
/// animation, and the island slid in from the left instead of growing out of the notch.
private final class IslandContainerView: NSView {
    /// Nil: the SwiftUI view fills the window (floating mode).
    var fixedContentSize: CGSize? {
        didSet { resizeSubviews(withOldSize: bounds.size) }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard let content = subviews.first else { return }
        guard let size = fixedContentSize else {
            content.frame = bounds
            return
        }
        content.frame = NSRect(x: (bounds.width - size.width) / 2, y: bounds.height - size.height, width: size.width, height: size.height)
    }
}

/// Transparent overlay that drags its window, and reports a click when the mouse didn't move.
struct WindowDragArea: NSViewRepresentable {
    var onClick: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onClick = onClick
    }

    class DragView: NSView {
        var onClick: (() -> Void)?
        private var mouseDownLocation: NSPoint?
        private var windowOriginAtMouseDown: NSPoint?
        private var didDrag = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = NSEvent.mouseLocation
            windowOriginAtMouseDown = window?.frame.origin
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let panel = window as? FloatingPanel, panel.isDraggable,
                  let start = mouseDownLocation, let origin = windowOriginAtMouseDown else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - start.x
            let dy = current.y - start.y
            if !didDrag && hypot(dx, dy) < 3 { return }
            didDrag = true
            panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            if didDrag {
                (window as? FloatingPanel)?.saveFloatingPosition()
            } else {
                onClick?()
            }
            mouseDownLocation = nil
            windowOriginAtMouseDown = nil
        }
    }
}

extension NSScreen {
    /// The display's ID, which stays the same while it's connected (unlike the NSScreen object).
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
