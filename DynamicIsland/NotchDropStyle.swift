import AppKit
import SwiftUI

// Notch Drop's look: the wells, the pieces and the panels around them. Only plain values go in,
// so each piece can be drawn on its own.

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
    default: return Color(white: 0.36)
    }
}

enum DropStyle {
    /// One color for the few things that stand out; buttons stay white.
    static let accent = Color(red: 1, green: 0.42, blue: 0.66)
    static let title = Color.white
    static let muted = Color.white.opacity(0.45)
    static let faint = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.09)

    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func caption(_ size: CGFloat = 8.5) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

/// A small label above a value, spaced out like the notch's other captions.
struct DropCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(DropStyle.caption())
            .tracking(1.2)
            .foregroundColor(DropStyle.muted)
            .lineLimit(1)
    }
}

/// A quiet rounded panel.
struct DropPanel<Content: View>: View {
    var padding: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DropStyle.faint))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DropStyle.line, lineWidth: 0.5))
    }
}

/// A well of blocks: the player's own, or the other player's as last sent.
struct DropWell: View {
    let cells: [UInt8]
    let ghost: Set<Int>
    /// The falling piece, whose color its shadow takes.
    let ghostShape: UInt8?
    let block: CGFloat
    /// The falling piece's blocks, which glow a little.
    var piece: Set<Int> = []
    /// Full rows going away, and how far (0…1): they light up, then shrink to their middle.
    var clearingRows: Set<Int> = []
    var clearProgress: Double = 0

    var body: some View {
        Canvas { context, size in
            let well = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10, style: .continuous)
            context.fill(well, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.02)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // A dot where the grid lines would cross: the places show without lines everywhere.
            for row in 1..<NotchDropGame.rows {
                for column in 1..<NotchDropGame.columns {
                    let dot = CGRect(x: CGFloat(column) * block - 0.6, y: CGFloat(row) * block - 0.6, width: 1.2, height: 1.2)
                    context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.08)))
                }
            }

            let ghostColor = ghostShape.map(dropColor) ?? .white
            for index in cells.indices {
                let rect = CGRect(x: CGFloat(index % NotchDropGame.columns) * block, y: CGFloat(index / NotchDropGame.columns) * block,
                                  width: block, height: block).insetBy(dx: 1.1, dy: 1.1)
                let value = cells[index]
                if clearingRows.contains(index / NotchDropGame.columns) {
                    drawClearing(in: &context, rect: rect, value: value, column: index % NotchDropGame.columns)
                } else if value != 0 {
                    drawBlock(in: &context, rect: rect, color: dropColor(value), glows: piece.contains(index))
                } else if ghost.contains(index) {
                    let path = Path(roundedRect: rect, cornerRadius: block * 0.26, style: .continuous)
                    context.fill(path, with: .color(ghostColor.opacity(0.12)))
                    context.stroke(path, with: .color(ghostColor.opacity(0.45)), lineWidth: 0.8)
                }
            }
        }
        .frame(width: block * CGFloat(NotchDropGame.columns), height: block * CGFloat(NotchDropGame.rows))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                              lineWidth: 0.75)
        )
    }

    /// A block lit from above: lighter at the top, with a thin shine along its top edge.
    private func drawBlock(in context: inout GraphicsContext, rect: CGRect, color: Color, glows: Bool) {
        let path = Path(roundedRect: rect, cornerRadius: block * 0.26, style: .continuous)
        context.drawLayer { layer in
            if glows {
                layer.addFilter(.shadow(color: color.opacity(0.55), radius: 3.5))
            }
            layer.fill(path, with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.25), color, color.mix(with: .black, by: 0.12)]),
                                                   startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
        }
        let shine = CGRect(x: rect.minX + rect.width * 0.18, y: rect.minY + 1, width: rect.width * 0.64, height: max(rect.height * 0.14, 1))
        context.fill(Path(roundedRect: shine, cornerRadius: shine.height / 2), with: .color(.white.opacity(0.45)))
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
        let path = Path(roundedRect: block, cornerRadius: block.width * 0.26, style: .continuous)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .white.opacity(0.8 * flash * scale), radius: 5))
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
            let color = dropColor(shape.rawValue)
            for cell in cells {
                let rect = CGRect(x: origin.x + CGFloat(cell.column - columns.min()!) * block,
                                  y: origin.y + CGFloat(cell.row - rows.min()!) * block, width: block, height: block).insetBy(dx: 0.8, dy: 0.8)
                context.fill(Path(roundedRect: rect, cornerRadius: block * 0.26, style: .continuous),
                             with: .linearGradient(Gradient(colors: [color.mix(with: .white, by: 0.25), color]),
                                                   startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
            }
        }
        .frame(width: block * 4, height: block * 2.3)
    }
}

/// The piece on hold and the next ones, in one panel.
struct DropQueue: View {
    let held: NotchDropGame.Shape?
    let canHold: Bool
    let upcoming: [NotchDropGame.Shape]
    let block: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DropPanel {
                VStack(spacing: 4) {
                    DropCaption("Hold")
                    DropPiecePreview(shape: held, block: block)
                        .opacity(canHold ? 1 : 0.35)
                }
                .frame(maxWidth: .infinity)
            }
            DropPanel {
                VStack(spacing: 6) {
                    DropCaption("Next")
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { index, shape in
                        DropPiecePreview(shape: shape, block: block * (index == 0 ? 1 : 0.8))
                            .opacity(index == 0 ? 1 : 0.85)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Score, rows, level and best, beside a solo game.
struct DropSoloStats: View {
    let score: Int
    let rows: Int
    let level: Int
    let best: Int
    let wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                DropCaption("Score")
                Text("\(score)")
                    .font(DropStyle.number(wide ? 28 : 22, weight: .bold))
                    .foregroundStyle(DropStyle.title)
                    .contentTransition(.numericText(value: Double(score)))
                    .animation(.snappy(duration: 0.25), value: score)
            }
            HStack(spacing: 18) {
                stat("Rows", "\(rows)")
                stat("Best", "\(max(best, score))")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    DropCaption("Level \(level)")
                    Spacer()
                    Text("\(rows % 10)/10")
                        .font(DropStyle.number(8.5))
                        .foregroundColor(DropStyle.muted)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DropStyle.faint)
                        Capsule().fill(DropStyle.accent)
                            .frame(width: max(4, geometry.size.width * CGFloat(rows % 10) / 10))
                    }
                }
                .frame(height: 4)
                .animation(.snappy, value: rows)
            }
            Spacer(minLength: 0)
            DropKeys()
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            DropCaption(title)
            Text(value).font(DropStyle.number(wide ? 16 : 14))
        }
    }
}

/// The keys, as little keycaps.
struct DropKeys: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(["←", "→"], "move")
            row(["↑"], "turn")
            row(["↓"], "faster")
            row(["space"], "drop")
            row(["C"], "hold")
            row(["esc"], "pause")
        }
    }

    private func row(_ keys: [String], _ action: String) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 13)
                    .background(RoundedRectangle(cornerRadius: 3.5).fill(Color.white.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            Text(action)
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(DropStyle.muted)
        }
    }
}

/// The middle of a duel: both scores, the rows on their way here, and the record between you.
struct DropDuelBoard: View {
    let yourScore: Int
    let yourRows: Int
    let friendName: String
    let friendScore: Int
    let friendRows: Int
    let incoming: Int
    let wins: Int
    let losses: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("VS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.12)))

            VStack(spacing: 8) {
                side("You", score: yourScore, rows: yourRows, leads: yourScore >= friendScore)
                side(friendName, score: friendScore, rows: friendRows, leads: friendScore > yourScore)
            }

            if incoming > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text("\(incoming) row\(incoming == 1 ? "" : "s") coming")
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                DropCaption("Record")
                Text("\(wins) – \(losses)")
                    .font(DropStyle.number(12))
                    .foregroundColor(.white.opacity(0.8))
            }
            Text("Clear 2+ rows at once to send rows over")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(DropStyle.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func side(_ name: String, score: Int, rows: Int, leads: Bool) -> some View {
        DropPanel(padding: 7) {
            VStack(spacing: 1) {
                DropCaption(name)
                Text("\(score)")
                    .font(DropStyle.number(15, weight: .bold))
                    .foregroundStyle(leads ? AnyShapeStyle(DropStyle.title) : AnyShapeStyle(Color.white.opacity(0.7)))
                Text("\(rows) rows")
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundColor(DropStyle.muted)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A red bar beside the well that rises with the rows on their way to it.
struct DropIncomingMeter: View {
    let rows: Int
    let block: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(DropStyle.faint)
            Capsule()
                .fill(Color.orange)
                .frame(height: min(CGFloat(rows) * block, block * CGFloat(NotchDropGame.rows)))
                .animation(.snappy, value: rows)
        }
        .frame(width: 3, height: block * CGFloat(NotchDropGame.rows))
    }
}

/// A message over the well: paused, waiting, or how the game ended.
struct DropCard<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding(14)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .environment(\.colorScheme, .dark)
    }
}

/// A capsule button: the main one white, the others quiet. One color, nothing more.
struct DropButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    var height: CGFloat = 26
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
                }
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(prominent ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if prominent {
                    Capsule().fill(Color.white.opacity(isHovered ? 0.88 : 1))
                } else {
                    Capsule().fill(Color.white.opacity(isHovered ? 0.16 : 0.1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // The hand, but not on a disabled one.
        .pointingHandCursor()
    }
}

/// The game's name with a few pieces stacked beside it.
struct DropHero: View {
    let wide: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DropStyle.line, lineWidth: 0.5))
                VStack(spacing: -2) {
                    DropPiecePreview(shape: .tee, block: wide ? 9 : 6)
                    HStack(spacing: -4) {
                        DropPiecePreview(shape: .ell, block: wide ? 9 : 6)
                        DropPiecePreview(shape: .ess, block: wide ? 9 : 6)
                    }
                }
            }
            .frame(width: wide ? 72 : 46, height: wide ? 72 : 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Notch Drop")
                    .font(.system(size: wide ? 26 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DropStyle.title)
                Text("Fill a row to clear it. Keep the well from filling up.")
                    .font(.system(size: wide ? 11 : 10, design: .rounded))
                    .foregroundColor(DropStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A friend to challenge: online or not, and your record together.
struct DropFriendRow: View {
    let name: String
    let isOnline: Bool
    let wins: Int
    let losses: Int
    let challenge: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 24)
                    .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)))
                Circle()
                    .fill(isOnline ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(wins + losses > 0 ? "\(wins) won · \(losses) lost" : isOnline ? "Online" : "Offline")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(DropStyle.muted)
            }
            Spacer(minLength: 4)
            DropButton(title: "Duel", systemImage: "bolt.fill", prominent: isOnline, height: 22, action: challenge)
                .frame(width: 66)
                .disabled(!isOnline)
                .opacity(isOnline ? 1 : 0.45)
                .help(isOnline ? "Challenge \(name)" : "\(name) is offline")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DropStyle.faint))
    }
}

/// A friend's challenge, waiting for an answer.
struct DropInviteCard: View {
    let name: String
    var game = "Notch Drop"
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DropStyle.accent)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(name) challenges you")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(game) duel")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(DropStyle.muted)
            }
            Spacer(minLength: 4)
            DropButton(title: "Later", height: 22, action: decline).frame(width: 52)
            DropButton(title: "Play", prominent: true, height: 22, action: accept).frame(width: 52)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}
