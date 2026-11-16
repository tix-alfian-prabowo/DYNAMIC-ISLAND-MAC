import AppKit
import SwiftUI

/// The Game tab: Notch Drop alone, or side by side with a friend in a duel. Its parts are drawn in
/// NotchDropStyle.swift.
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
            updatePanelStyle()
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
            updatePanelStyle()
        }
        // A click elsewhere takes the keys away: a solo game waits.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if note.object is FloatingPanel {
                drop.pause()
            }
        }
    }

    /// The notch grows taller only for the wells; the menu fits the usual size.
    private func updatePanelStyle() {
        if drop.phase == .menu {
            layout.resetPanelStyle(from: .game)
        } else {
            layout.setPanelStyle(.game)
        }
    }

    private var playing: some View {
        HStack(alignment: .top, spacing: drop.isDuel ? 14 : 20) {
            DropQueue(held: drop.game.held, canHold: drop.game.canHold,
                      upcoming: Array(drop.game.upcoming.prefix(drop.isDuel ? 2 : 3)), block: block * 0.62)
                .frame(width: block * 4.6)
            HStack(spacing: 4) {
                if drop.isDuel {
                    DropIncomingMeter(rows: drop.game.incoming.count, block: block)
                }
                ownWell
                    .overlay { overlay }
            }
            if drop.isDuel, let opponent = drop.opponent {
                let record = drop.record(against: opponent)
                DropDuelBoard(yourScore: drop.game.score, yourRows: drop.game.clearedRows,
                              friendName: opponent.name, friendScore: drop.opponentScore, friendRows: drop.opponentRows,
                              incoming: drop.game.incoming.count, wins: record.wins, losses: record.losses)
                    .frame(width: layout.wide(118, 140))
                DropWell(cells: drop.opponentCells, ghost: [], ghostShape: nil, block: block)
                    .opacity(0.92)
                    .overlay(alignment: .top) {
                        Text(opponent.name)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .environment(\.colorScheme, .dark)
                            .padding(.top, 6)
                    }
            } else {
                DropSoloStats(score: drop.game.score, rows: drop.game.clearedRows, level: drop.game.level,
                              best: drop.best, wide: layout.isWide)
                    .frame(width: layout.wide(130, 160), alignment: .leading)
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
                            Text(clearing.rows.count >= 4 ? "NOTCH DROP" : "×\(clearing.rows.count)")
                                .font(.system(size: block * (clearing.rows.count >= 4 ? 1.25 : 1.9), weight: .heavy, design: .rounded))
                                .foregroundStyle(DropStyle.accent)
                                .shadow(color: .black.opacity(0.6), radius: 6)
                                .scaleEffect(0.75 + 0.4 * min(progress * 2, 1))
                                .opacity(progress < 0.75 ? 1 : (1 - progress) * 4)
                        }
                    }
            }
        } else {
            let game = drop.game
            DropWell(cells: game.visibleCells, ghost: game.ghostIndexes, ghostShape: game.piece?.shape.rawValue, block: block,
                     piece: Set(game.piece?.cells.filter { $0.row >= 0 }.map { $0.row * NotchDropGame.columns + $0.column } ?? []))
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch drop.phase {
        case .countdown(let count):
            Text("\(count)")
                .font(.system(size: block * 3.4, weight: .heavy, design: .rounded))
                .foregroundStyle(DropStyle.title)
                .shadow(color: .black.opacity(0.6), radius: 10)
                .id(count)
                .transition(.scale(scale: 1.4).combined(with: .opacity))
        case .paused:
            DropCard(width: block * 9.4) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(DropStyle.accent)
                Text("Paused").font(.system(size: 14, weight: .bold, design: .rounded))
                DropButton(title: "Resume", systemImage: "play.fill", prominent: true) { drop.resume() }
                DropButton(title: "Quit") { drop.backToMenu() }
            }
        case .waiting(let text):
            DropCard(width: block * 9.4) {
                ProgressView().controlSize(.small)
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                DropButton(title: "Cancel") { drop.backToMenu() }
            }
        case .finished(let won, let reason):
            DropCard(width: block * 9.4) {
                Image(systemName: won == true ? "trophy.fill" : won == false ? "xmark.circle.fill" : "flag.checkered")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                Text(won == true ? "You win" : won == false ? "You lose" : "Game over")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(reason)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(DropStyle.muted)
                    .multilineTextAlignment(.center)
                if let opponent = drop.opponent {
                    DropButton(title: "Rematch", systemImage: "bolt.fill", prominent: true) { drop.challenge(opponent) }
                } else {
                    DropButton(title: "Play Again", systemImage: "arrow.clockwise", prominent: true) { drop.startSolo() }
                }
                DropButton(title: "Menu") { drop.backToMenu() }
            }
        default:
            EmptyView()
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
    @ObservedObject private var invites = GameInvites.shared

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: layout.wide(10, 16)) {
                Button { GameLibrary.shared.current = nil } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        Text("Games")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DropStyle.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Back to the games")

                DropHero(wide: layout.isWide)

                HStack(spacing: 12) {
                    DropButton(title: "Play Solo", systemImage: "play.fill", prominent: true, height: layout.wide(26, 30)) { drop.startSolo() }
                        .frame(width: layout.wide(120, 140))
                    if drop.best > 0 {
                        VStack(alignment: .leading, spacing: 0) {
                            DropCaption("Best")
                            Text("\(drop.best)").font(DropStyle.number(14, weight: .bold))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                if let invite = invites.invite {
                    DropInviteCard(name: invite.friend.name, game: invite.game.title,
                                   accept: { invites.accept() }, decline: { invites.decline() })
                }
                DropCaption("Duel a friend")
                if pokeService.state != .ready {
                    note("Duels go through Poke. Set it up in the Poke tab first.")
                } else if pokeService.friends.isEmpty {
                    note("Add a friend in the Poke tab to duel them.")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 5) {
                            ForEach(pokeService.friends) { friend in
                                let record = drop.record(against: friend)
                                DropFriendRow(name: friend.name, isOnline: pokeService.isOnline(friend),
                                              wins: record.wins, losses: record.losses) {
                                    drop.challenge(friend)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: layout.wide(270, 340), alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(DropStyle.muted)
    }
}
