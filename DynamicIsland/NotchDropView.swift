import AppKit
import SwiftUI

/// The Game tab: Notch Drop alone, or side by side with a friend in a duel.
struct NotchDropView: View {
    @EnvironmentObject var layout: IslandLayout
    @EnvironmentObject var pokeService: PokeService
    @ObservedObject private var drop = NotchDrop.shared
    @FocusState private var hasKeys: Bool
    /// Whether the notch was pinned open before a game kept it open.
    @State private var wasPinned = false

    private var block: CGFloat { IslandLayout.gameBlock(wide: layout.isWide) }

    var body: some View {
        Group {
            if drop.phase == .menu {
                DropMenu()
            } else {
                playing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeys)
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press)
        }
        .onAppear {
            layout.setPanelStyle(.game)
            hasKeys = true
        }
        .onDisappear {
            layout.resetPanelStyle(from: .game)
            drop.pause()
            if drop.keepsPanelOpen {
                layout.staysOpen = wasPinned
            }
        }
        .onChange(of: drop.keepsPanelOpen) { _, keeps in
            if keeps {
                wasPinned = layout.staysOpen
                layout.staysOpen = true
            } else {
                layout.staysOpen = wasPinned
            }
        }
        .onChange(of: drop.phase) {
            hasKeys = true
        }
        // A click elsewhere takes the keys away: a solo game waits.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if note.object is FloatingPanel {
                drop.pause()
            }
        }
    }

    private var playing: some View {
        HStack(alignment: .top, spacing: drop.isDuel ? 12 : 18) {
            sideColumn
            ownWell
                .overlay { overlay }
            if drop.isDuel {
                duelColumn
                DropWell(cells: drop.opponentCells, ghost: [], ghostShape: nil, block: block)
                    .overlay(alignment: .top) {
                        Text(drop.opponent?.name ?? "")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(.top, 4)
                    }
            } else {
                soloColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The player's well; while full rows go away, the well as it was with them, flashing and shrinking.
    @ViewBuilder
    private var ownWell: some View {
        if let clearing = drop.clearing {
            TimelineView(.animation) { context in
                let progress = min(context.date.timeIntervalSince(clearing.started) / NotchDrop.clearDuration, 1)
                DropWell(cells: clearing.cells, ghost: [], ghostShape: nil, block: block,
                         clearingRows: clearing.rows, clearProgress: progress)
                    .overlay {
                        if clearing.rows.count >= 2 {
                            Text(clearing.rows.count >= 4 ? "NOTCH DROP!" : "×\(clearing.rows.count)")
                                .font(.system(size: block * (clearing.rows.count >= 4 ? 1.3 : 1.8), weight: .black))
                                .foregroundStyle(LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: .pink.opacity(0.8), radius: 6)
                                .scaleEffect(0.7 + 0.5 * min(progress * 2, 1))
                                .opacity(progress < 0.75 ? 1 : (1 - progress) * 4)
                        }
                    }
            }
        } else {
            DropWell(cells: drop.game.visibleCells, ghost: drop.game.ghostIndexes, ghostShape: drop.game.piece?.shape.rawValue, block: block)
        }
    }

    /// The piece on hold and the next ones.
    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("HOLD")
            DropPiecePreview(shape: drop.game.held, block: block * 0.7)
                .opacity(drop.game.canHold ? 1 : 0.4)
            label("NEXT")
            ForEach(Array(drop.game.upcoming.prefix(drop.isDuel ? 2 : 3).enumerated()), id: \.offset) { _, shape in
                DropPiecePreview(shape: shape, block: block * 0.7)
            }
        }
        .frame(width: block * 4.5, alignment: .leading)
    }

    private var soloColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            stat("SCORE", "\(drop.game.score)")
            stat("ROWS", "\(drop.game.clearedRows)")
            stat("LEVEL", "\(drop.game.level)")
            stat("BEST", "\(max(drop.best, drop.game.score))")
            Spacer(minLength: 0)
            keysHelp
        }
        .frame(width: layout.wide(150, 180), alignment: .leading)
    }

    private var duelColumn: some View {
        VStack(spacing: 10) {
            Text("VS")
                .font(.system(size: layout.wide(16, 20), weight: .black))
                .foregroundColor(.pink)
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 2) {
                    label("YOU")
                    Text("\(drop.game.score)").font(.system(size: 13, weight: .bold).monospacedDigit())
                    Text("\(drop.game.clearedRows) rows").font(.system(size: 9)).foregroundColor(.gray)
                }
                VStack(spacing: 2) {
                    label((drop.opponent?.name ?? "").uppercased())
                        .lineLimit(1)
                    Text("\(drop.opponentScore)").font(.system(size: 13, weight: .bold).monospacedDigit())
                    Text("\(drop.opponentRows) rows").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
            if !drop.game.incoming.isEmpty {
                Label("\(drop.game.incoming.count) coming", systemImage: "arrow.up.square.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
            }
            if let opponent = drop.opponent {
                let record = drop.record(against: opponent)
                Text("\(record.wins) – \(record.losses)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundColor(.gray)
                    .help("Your duels with \(opponent.name): won – lost")
            }
            Spacer(minLength: 0)
            Text("Clear 2+ rows at once\nto send rows over")
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(width: layout.wide(110, 140))
    }

    @ViewBuilder
    private var overlay: some View {
        switch drop.phase {
        case .countdown(let count):
            Text("\(count)")
                .font(.system(size: block * 3, weight: .black))
                .foregroundColor(.white)
                .shadow(radius: 8)
                .id(count)
                .transition(.scale.combined(with: .opacity))
        case .paused:
            card {
                Text("Paused").font(.system(size: 13, weight: .bold))
                button("Resume", prominent: true) { drop.resume() }
                button("Quit") { drop.backToMenu() }
            }
        case .waiting(let text):
            card {
                ProgressView().controlSize(.small)
                Text(text).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center)
                button("Cancel") { drop.backToMenu() }
            }
        case .finished(let won, let reason):
            card {
                Text(won == true ? "You win!" : won == false ? "You lose" : "Game over")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(won == true ? .green : won == false ? .red : .white)
                Text(reason).font(.system(size: 10)).foregroundColor(.gray).multilineTextAlignment(.center)
                if let opponent = drop.opponent {
                    button("Rematch", prominent: true) { drop.challenge(opponent) }
                } else {
                    button("Play Again", prominent: true) { drop.startSolo() }
                }
                button("Menu") { drop.backToMenu() }
            }
        default:
            EmptyView()
        }
    }

    private var keysHelp: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("← →  move   ↓  faster")
            Text("↑ / X  turn   Z  turn back")
            Text("Space  drop   C  hold")
            Text("Esc  pause")
        }
        .font(.system(size: 9))
        .foregroundColor(.gray)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 8, content: content)
            .padding(12)
            .frame(width: block * 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
    }

    private func button(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Capsule().fill(prominent ? Color.pink : Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.gray)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label(title)
            Text(value).font(.system(size: layout.wide(15, 18), weight: .bold).monospacedDigit())
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let once = press.phase == .down
        let key: NotchDrop.Key?
        switch press.key {
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .downArrow: key = .down
        case .upArrow: key = once ? .turn : nil
        case .space: key = once ? .drop : nil
        case .escape: key = once ? .pause : nil
        default:
            switch press.characters.lowercased() {
            case "x": key = once ? .turn : nil
            case "z": key = once ? .turnBack : nil
            case "c": key = once ? .hold : nil
            case "p": key = once ? .pause : nil
            default: return .ignored
            }
        }
        guard drop.phase != .menu else { return .ignored }
        if let key {
            drop.press(key)
        }
        return .handled
    }
}

/// Picking a game: solo, a friend's challenge, or a friend to challenge.
private struct DropMenu: View {
    @EnvironmentObject var layout: IslandLayout
    @EnvironmentObject var pokeService: PokeService
    @ObservedObject private var drop = NotchDrop.shared

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notch Drop")
                        .font(.system(size: layout.wide(22, 26), weight: .black))
                        .foregroundStyle(LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .leading, endPoint: .trailing))
                    Text("Fill rows to clear them. Don't let the well fill up.")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                Button { drop.startSolo() } label: {
                    Label("Play Solo", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 140, height: 30)
                        .background(Capsule().fill(Color.pink))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                if drop.best > 0 {
                    Text("Best: \(drop.best)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(.gray)
                }
                Spacer(minLength: 0)
                Text("← → move · ↑ turn · Space drop · C hold")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                if let invite = drop.invite {
                    inviteCard(invite)
                }
                Text("DUEL A FRIEND")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
                if pokeService.state != .ready {
                    Text("Duels go through Poke: set it up in the Poke tab first.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else if pokeService.friends.isEmpty {
                    Text("Add a friend in the Poke tab to duel them.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(pokeService.friends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                }
            }
            .frame(width: layout.wide(260, 340), alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func inviteCard(_ invite: NotchDrop.Invite) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gamecontroller.fill")
                .foregroundColor(.pink)
            Text("\(invite.friend.name) challenges you")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Decline") { drop.decline() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
                .pointingHandCursor()
            Button { drop.accept() } label: {
                Text("Play")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.green))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.pink.opacity(0.15)))
    }

    private func friendRow(_ friend: PokeService.Friend) -> some View {
        let online = pokeService.isOnline(friend)
        let record = drop.record(against: friend)
        return HStack(spacing: 8) {
            Circle()
                .fill(online ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(friend.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if record.wins + record.losses > 0 {
                Text("\(record.wins) – \(record.losses)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(.gray)
                    .help("Won – lost")
            }
            Spacer(minLength: 4)
            Button { drop.challenge(friend) } label: {
                Text("Duel")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 22)
                    .background(Capsule().fill(online ? Color.pink : Color.white.opacity(0.1)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!online)
            .pointingHandCursor()
            .help(online ? "Challenge \(friend.name)" : "\(friend.name) is offline")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
}

/// A well of blocks: the player's own, or the other player's as last sent.
struct DropWell: View {
    let cells: [UInt8]
    let ghost: Set<Int>
    /// The falling piece, whose color its shadow takes.
    let ghostShape: UInt8?
    let block: CGFloat
    /// Full rows going away, and how far (0…1): they light up, then shrink to their middle.
    var clearingRows: Set<Int> = []
    var clearProgress: Double = 0

    var body: some View {
        Canvas { context, size in
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6), with: .color(.white.opacity(0.05)))
            // A faint grid, so a piece's place is easy to see.
            var grid = Path()
            for column in 1..<NotchDropGame.columns {
                let x = CGFloat(column) * block
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<NotchDropGame.rows {
                let y = CGFloat(row) * block
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.04)), lineWidth: 0.5)

            let ghostColor = ghostShape.map(dropColor) ?? .white
            for index in cells.indices {
                let rect = CGRect(x: CGFloat(index % NotchDropGame.columns) * block, y: CGFloat(index / NotchDropGame.columns) * block,
                                  width: block, height: block).insetBy(dx: 1, dy: 1)
                let value = cells[index]
                if clearingRows.contains(index / NotchDropGame.columns) {
                    drawClearing(in: &context, rect: rect, value: value, column: index % NotchDropGame.columns)
                } else if value != 0 {
                    let color = dropColor(value)
                    context.fill(Path(roundedRect: rect, cornerRadius: block * 0.22), with: .color(color))
                    // A light top edge, like the notch's own glass.
                    let shine = CGRect(x: rect.minX + 2, y: rect.minY + 1.5, width: rect.width - 4, height: max(rect.height * 0.22, 1.5))
                    context.fill(Path(roundedRect: shine, cornerRadius: 1), with: .color(.white.opacity(0.35)))
                } else if ghost.contains(index) {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: block * 0.22),
                                   with: .color(ghostColor.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .frame(width: block * CGFloat(NotchDropGame.columns), height: block * CGFloat(NotchDropGame.rows))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12)))
    }

    /// A block of a full row: for the first part it turns white and glows, then it shrinks away,
    /// the blocks at the row's middle first, so the row closes from the middle outward.
    private func drawClearing(in context: inout GraphicsContext, rect: CGRect, value: UInt8, column: Int) {
        let flash = min(clearProgress / 0.4, 1)
        let fromMiddle = abs(Double(column) - Double(NotchDropGame.columns - 1) / 2) / (Double(NotchDropGame.columns) / 2)
        // Each block starts shrinking a little later the further it is from the middle.
        let shrinkStart = 0.35 + fromMiddle * 0.25
        let shrink = max(0, min((clearProgress - shrinkStart) / (1 - shrinkStart), 1))
        let scale = 1 - shrink
        guard scale > 0 else { return }
        let block = rect.insetBy(dx: rect.width * (1 - scale) / 2, dy: rect.height * (1 - scale) / 2)
        let path = Path(roundedRect: block, cornerRadius: block.width * 0.22)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .white.opacity(0.8 * flash * scale), radius: 4))
            layer.fill(path, with: .color(dropColor(value)))
            layer.fill(path, with: .color(.white.opacity(0.85 * flash)))
        }
    }
}

/// A piece on its own, for the one on hold and the next ones.
struct DropPiecePreview: View {
    let shape: NotchDropGame.Shape?
    let block: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let shape else { return }
            let cells = shape.cells(turns: 0)
            let rows = cells.map(\.row), columns = cells.map(\.column)
            let width = CGFloat(columns.max()! - columns.min()! + 1) * block
            let height = CGFloat(rows.max()! - rows.min()! + 1) * block
            let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
            for cell in cells {
                let rect = CGRect(x: origin.x + CGFloat(cell.column - columns.min()!) * block,
                                  y: origin.y + CGFloat(cell.row - rows.min()!) * block, width: block, height: block).insetBy(dx: 0.75, dy: 0.75)
                context.fill(Path(roundedRect: rect, cornerRadius: block * 0.22), with: .color(dropColor(shape.rawValue)))
            }
        }
        .frame(width: block * 4, height: block * 2.4)
    }
}

/// Notch Drop's own colors, bright against the black notch.
func dropColor(_ value: UInt8) -> Color {
    switch value {
    case 1: return Color(red: 0.98, green: 0.45, blue: 0.69)
    case 2: return Color(red: 0.35, green: 0.90, blue: 0.70)
    case 3: return Color(red: 0.40, green: 0.70, blue: 1.00)
    case 4: return Color(red: 0.72, green: 0.56, blue: 1.00)
    case 5: return Color(red: 1.00, green: 0.66, blue: 0.40)
    case 6: return Color(red: 0.78, green: 0.93, blue: 0.36)
    case 7: return Color(red: 1.00, green: 0.45, blue: 0.45)
    default: return Color(white: 0.42)
    }
}
