import AppKit
import SwiftUI

/// The Game tab's Notch Rush: the race, alone or against a friend. The road is drawn in
/// NotchRushStyle.swift; panels and buttons are Notch Drop's.
struct NotchRushView: View {
    @EnvironmentObject var layout: IslandLayout
    @ObservedObject private var rush = NotchRush.shared
    @FocusState private var hasKeys: Bool
    /// Whether the notch was pinned open before a race kept it open.
    @State private var wasPinned = false

    var body: some View {
        Group {
            if rush.phase == .menu {
                RushMenu()
            } else {
                racing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeys)
        .onKeyPress(phases: .all) { press in
            handle(press)
        }
        .onAppear {
            updatePanelStyle()
            hasKeys = true
        }
        .onDisappear {
            layout.resetPanelStyle(from: .game)
            rush.pause()
            if rush.keepsPanelOpen {
                layout.staysOpen = wasPinned
            }
        }
        .onChange(of: rush.keepsPanelOpen) { _, keeps in
            if keeps {
                wasPinned = layout.staysOpen
                layout.staysOpen = true
            } else {
                layout.staysOpen = wasPinned
            }
        }
        .onChange(of: rush.phase) {
            hasKeys = true
            updatePanelStyle()
        }
        // A click elsewhere takes the keys away: a solo race waits.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if note.object is FloatingPanel {
                rush.pause()
                rush.releaseKeys()
            }
        }
    }

    /// The notch grows taller for the road; the menu fits the usual size.
    private func updatePanelStyle() {
        if rush.phase == .menu {
            layout.resetPanelStyle(from: .game)
        } else {
            layout.setPanelStyle(.game)
        }
    }

    private var racing: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Text(NotchRush.format(rush.race.time))
                    .font(DropStyle.number(layout.wide(14, 16), weight: .bold))
                    .frame(width: 58, alignment: .leading)
                RushProgress(you: rush.race.progress, friend: rush.isDuel ? rush.opponentShownDistance / NotchRushRace.length : nil)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(rush.race.speed * 3.6))")
                        .font(DropStyle.number(layout.wide(14, 16), weight: .bold))
                    Text("km/h")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(DropStyle.muted)
                }
                .frame(width: 70, alignment: .trailing)
            }

            RushScene(race: rush.race, ghost: ghost)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DropStyle.line, lineWidth: 0.5))
                .overlay { overlay }

            HStack(spacing: 14) {
                RushBoostMeter(boost: rush.race.boost, isBoosting: rush.race.isBoosting)
                if rush.isDuel, let opponent = rush.opponent {
                    let record = rush.record(against: opponent)
                    Text("vs \(opponent.name) · \(record.wins) – \(record.losses)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(DropStyle.muted)
                } else if let best = rush.best {
                    Text("Best \(NotchRush.format(best))")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(DropStyle.muted)
                }
                Spacer(minLength: 0)
                keys
            }
        }
    }

    private var ghost: RushGhost? {
        guard rush.isDuel, let opponent = rush.opponent else { return nil }
        return RushGhost(distance: rush.opponentShownDistance, lanePosition: rush.opponentShownLane, name: opponent.name)
    }

    private var keys: some View {
        HStack(spacing: 10) {
            keycaps(["↑"], "gas")
            keycaps(["↓"], "brake")
            keycaps(["←", "→"], "steer")
            keycaps(["space"], "boost")
            keycaps(["esc"], "pause")
        }
    }

    private func keycaps(_ keys: [String], _ action: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 13)
                    .background(RoundedRectangle(cornerRadius: 3.5).fill(Color.white.opacity(0.1)))
            }
            Text(action)
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(DropStyle.muted)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch rush.phase {
        case .countdown(let count):
            Text("\(count)")
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 10)
                .id(count)
                .transition(.scale(scale: 1.4).combined(with: .opacity))
        case .paused:
            DropCard(width: 170) {
                Text("Paused").font(.system(size: 14, weight: .bold, design: .rounded))
                DropButton(title: "Resume", systemImage: "play.fill", prominent: true) { rush.resume() }
                DropButton(title: "Quit") { rush.backToMenu() }
            }
        case .waiting(let text):
            DropCard(width: 190) {
                ProgressView().controlSize(.small)
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                DropButton(title: "Cancel") { rush.backToMenu() }
            }
        case .finished(let won, let reason):
            DropCard(width: 190) {
                Image(systemName: won == true ? "trophy.fill" : won == false ? "xmark.circle.fill" : "flag.checkered")
                    .font(.system(size: 18))
                Text(won == true ? "You win" : won == false ? "You lose" : "Finished")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(reason)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(DropStyle.muted)
                    .multilineTextAlignment(.center)
                if let opponent = rush.opponent {
                    DropButton(title: "Rematch", systemImage: "bolt.fill", prominent: true) { rush.challenge(opponent) }
                } else {
                    DropButton(title: "Race Again", systemImage: "arrow.clockwise", prominent: true) { rush.startSolo() }
                }
                DropButton(title: "Menu") { rush.backToMenu() }
            }
        default:
            EmptyView()
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard rush.phase != .menu else { return .ignored }
        let key: NotchRush.Key
        switch press.key {
        case .upArrow: key = .gas
        case .downArrow: key = .brake
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .space: key = .boost
        case .escape: key = .pause
        default:
            switch press.characters.lowercased() {
            case "w": key = .gas
            case "s": key = .brake
            case "a": key = .left
            case "d": key = .right
            case "p": key = .pause
            default: return .ignored
            }
        }
        switch press.phase {
        case .down:
            rush.keyDown(key)
        case .up:
            rush.keyUp(key)
        default:
            // Held keys repeat; they count as held until let go.
            break
        }
        return .handled
    }
}

/// Picking a race: solo against the clock, a friend's challenge, or a friend to challenge.
private struct RushMenu: View {
    @EnvironmentObject var layout: IslandLayout
    @EnvironmentObject var pokeService: PokeService
    @ObservedObject private var rush = NotchRush.shared
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

                HStack(spacing: 12) {
                    RushCarIcon()
                        .frame(width: layout.wide(46, 72), height: layout.wide(46, 72))
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DropStyle.faint))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DropStyle.line, lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notch Rush")
                            .font(.system(size: layout.wide(18, 26), weight: .bold, design: .rounded))
                        Text("Take the bends and weave through night traffic.")
                            .font(.system(size: layout.wide(10, 11), design: .rounded))
                            .foregroundColor(DropStyle.muted)
                    }
                }

                HStack(spacing: 12) {
                    DropButton(title: "Race Solo", systemImage: "play.fill", prominent: true, height: layout.wide(26, 30)) { rush.startSolo() }
                        .frame(width: layout.wide(120, 140))
                    if let best = rush.best {
                        VStack(alignment: .leading, spacing: 0) {
                            DropCaption("Best")
                            Text(NotchRush.format(best)).font(DropStyle.number(14, weight: .bold))
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
                DropCaption("Race a friend")
                if pokeService.state != .ready {
                    note("Races go through Poke. Set it up in the Poke tab first.")
                } else if pokeService.friends.isEmpty {
                    note("Add a friend in the Poke tab to race them.")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 5) {
                            ForEach(pokeService.friends) { friend in
                                let record = rush.record(against: friend)
                                DropFriendRow(name: friend.name, isOnline: pokeService.isOnline(friend),
                                              wins: record.wins, losses: record.losses) {
                                    rush.challenge(friend)
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
