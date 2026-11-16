import Combine
import SwiftUI

/// The games in the Game tab. Each one is a tile in the tab's list; picking one opens it.
enum NotchGame: String, CaseIterable, Identifiable {
    case notchDrop
    case notchRush

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notchDrop: return "Notch Drop"
        case .notchRush: return "Notch Rush"
        }
    }

    var subtitle: String {
        "Solo · Duel"
    }

    /// The Realtime channel of one of its matches.
    func matchTopic(_ id: String) -> String {
        switch self {
        case .notchDrop: return "notch-drop:\(id)"
        case .notchRush: return "notch-rush:\(id)"
        }
    }
}

/// Which game the Game tab shows; nil shows the list.
final class GameLibrary: ObservableObject {
    static let shared = GameLibrary()

    @Published var current: NotchGame?

    private init() {}

    /// A game is on (counting down or playing): notifications wait in the Alerts tab meanwhile.
    static func updatePlaying() {
        NotificationManager.shared.setPlayingGame(NotchDrop.shared.keepsPanelOpen || NotchRush.shared.keepsPanelOpen)
    }
}

/// The Game tab: the list of games as square tiles, like the VPN tab's, or the game picked.
struct GameTabView: View {
    @ObservedObject private var library = GameLibrary.shared

    var body: some View {
        switch library.current {
        case .notchDrop:
            NotchDropView()
        case .notchRush:
            NotchRushView()
        case nil:
            GameList()
        }
    }
}

private struct GameList: View {
    @EnvironmentObject var layout: IslandLayout
    @ObservedObject private var invites = GameInvites.shared

    private var tileSize: CGFloat { layout.wide(112, 150) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize), spacing: 10, alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(NotchGame.allCases) { game in
                    GameTile(game: game, size: tileSize, badge: badge(for: game)) {
                        GameLibrary.shared.current = game
                    }
                }
                MoreGamesTile(size: tileSize)
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A friend's challenge waiting in that game.
    private func badge(for game: NotchGame) -> String? {
        invites.invite(for: game).map { "\($0.friend.name) challenges you" }
    }
}

private struct GameTile: View {
    @EnvironmentObject var layout: IslandLayout
    let game: NotchGame
    let size: CGFloat
    let badge: String?
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            art
                .frame(height: layout.wide(30, 44))
            Text(game.title)
                .font(.system(size: layout.wide(11, 15), weight: .semibold))
                .lineLimit(1)
            Text(game.subtitle)
                .font(.system(size: layout.wide(9, 11)))
                .foregroundColor(.gray)
        }
        .padding(8)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(isHovered ? 0.1 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(badge == nil ? Color.clear : Color.pink, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if badge != nil {
                Circle().fill(Color.pink).frame(width: 8, height: 8).padding(7)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: open)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .help(badge ?? "Play \(game.title)")
    }

    @ViewBuilder
    private var art: some View {
        switch game {
        case .notchDrop:
            HStack(alignment: .bottom, spacing: 2) {
                DropPiecePreview(shape: .tee, block: layout.wide(6, 9))
                    .frame(width: layout.wide(20, 30))
                DropPiecePreview(shape: .ell, block: layout.wide(6, 9))
                    .frame(width: layout.wide(20, 30))
                DropPiecePreview(shape: .ess, block: layout.wide(6, 9))
                    .frame(width: layout.wide(20, 30))
            }
        case .notchRush:
            RushCarIcon()
                .frame(width: layout.wide(64, 92), height: layout.wide(28, 40))
        }
    }
}

/// Room for the games still to come.
private struct MoreGamesTile: View {
    @EnvironmentObject var layout: IslandLayout
    let size: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: layout.wide(18, 26)))
            Text("More soon")
                .font(.system(size: layout.wide(10, 13), weight: .medium))
        }
        .foregroundColor(.gray.opacity(0.7))
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
