import Foundation

/// Notch Drop, the Game tab's falling-block puzzle: pieces of four blocks fall into a well 10
/// wide and 20 deep; a full row clears. Clearing two or more rows at once in a duel sends rows
/// with one gap to the other player's well. Only the rules live here, with no timing: the
/// controller says when a piece falls a row, and the same seed gives both players the same pieces.
nonisolated struct NotchDropGame: Equatable, Sendable {
    static let columns = 10
    static let rows = 20
    /// A cell of a row sent by the other player.
    static let garbage: UInt8 = 8

    enum Shape: UInt8, CaseIterable, Sendable {
        case bar = 1, square, tee, ess, zed, jay, ell

        /// The blocks in its box (row, column), before turning.
        fileprivate var blocks: [(Int, Int)] {
            switch self {
            case .bar: return [(1, 0), (1, 1), (1, 2), (1, 3)]
            case .square: return [(0, 0), (0, 1), (1, 0), (1, 1)]
            case .tee: return [(0, 1), (1, 0), (1, 1), (1, 2)]
            case .ess: return [(0, 1), (0, 2), (1, 0), (1, 1)]
            case .zed: return [(0, 0), (0, 1), (1, 1), (1, 2)]
            case .jay: return [(0, 0), (1, 0), (1, 1), (1, 2)]
            case .ell: return [(0, 2), (1, 0), (1, 1), (1, 2)]
            }
        }

        /// The box it turns in.
        fileprivate var boxSize: Int {
            switch self {
            case .bar: return 4
            case .square: return 2
            default: return 3
            }
        }

        /// The blocks after `turns` quarter turns clockwise.
        func cells(turns: Int) -> [(row: Int, column: Int)] {
            let size = boxSize
            return blocks.map { block in
                var (row, column) = block
                for _ in 0..<((turns % 4 + 4) % 4) {
                    (row, column) = (column, size - 1 - row)
                }
                return (row, column)
            }
        }
    }

    struct Piece: Equatable, Sendable {
        var shape: Shape
        var turns = 0
        /// The top-left of its box; above the well while negative.
        var row: Int
        var column: Int

        var cells: [(row: Int, column: Int)] {
            shape.cells(turns: turns).map { (row + $0.row, column + $0.column) }
        }
    }

    /// What a piece coming to rest did.
    struct Landing: Equatable, Sendable {
        var clearedRows = 0
        /// The full rows (top first) and the well as it was with them, for showing them go.
        var fullRows: [Int] = []
        var cellsBeforeClearing: [UInt8] = []
        /// Rows sent to the other player, after the ones on their way here were cancelled.
        var sentRows = 0
    }

    /// Rows, top first, of `columns` cells: 0 is empty, otherwise a shape's raw value or `garbage`.
    private(set) var board: [[UInt8]] = Array(repeating: Array(repeating: 0, count: columns), count: rows)
    private(set) var piece: Piece?
    private(set) var held: Shape?
    /// A piece can be put on hold once until the next one comes to rest.
    private(set) var canHold = true
    private(set) var upcoming: [Shape] = []
    private(set) var score = 0
    private(set) var clearedRows = 0
    private(set) var isOver = false
    /// Rows sent by the other player, by where their gap is, added below once a piece comes to rest.
    private(set) var incoming: [Int] = []

    private var pieces: DropRandom
    private var gaps: DropRandom

    var level: Int { min(clearedRows / 10 + 1, 20) }

    /// Seconds per row the piece falls on its own: faster each level.
    var fallInterval: TimeInterval {
        let level = Double(self.level - 1)
        return max(pow(0.8 - level * 0.007, level), 0.03)
    }

    /// `seed` picks the pieces (shared by both players in a duel); `gapSeed` where the gaps of
    /// rows sent to the other player are.
    init(seed: UInt64, gapSeed: UInt64 = .random(in: 1...UInt64.max)) {
        pieces = DropRandom(seed: seed)
        gaps = DropRandom(seed: gapSeed)
        refillUpcoming()
        spawn()
    }

    // MARK: Moves

    @discardableResult
    mutating func move(by columns: Int) -> Bool {
        guard var moved = piece, !isOver else { return false }
        moved.column += columns
        guard fits(moved) else { return false }
        piece = moved
        return true
    }

    /// Turns the piece a quarter clockwise (or counterclockwise), nudged aside or up when it
    /// would hit a wall or blocks.
    @discardableResult
    mutating func turn(clockwise: Bool = true) -> Bool {
        guard let current = piece, !isOver, current.shape != .square else { return false }
        var turned = current
        turned.turns = (current.turns + (clockwise ? 1 : 3)) % 4
        for (columns, rows) in [(0, 0), (-1, 0), (1, 0), (0, -1), (-2, 0), (2, 0), (-1, -1), (1, -1)] {
            var nudged = turned
            nudged.column += columns
            nudged.row += rows
            if fits(nudged) {
                piece = nudged
                return true
            }
        }
        return false
    }

    /// One row down; false once it's resting on something.
    @discardableResult
    mutating func fall() -> Bool {
        guard var moved = piece, !isOver else { return false }
        moved.row += 1
        guard fits(moved) else { return false }
        piece = moved
        return true
    }

    /// One row down at the player's push, for a point.
    @discardableResult
    mutating func softDrop() -> Bool {
        guard fall() else { return false }
        score += 1
        return true
    }

    /// Straight down and resting, two points a row.
    mutating func hardDrop() -> Landing {
        guard piece != nil, !isOver else { return Landing() }
        var rows = 0
        while fall() { rows += 1 }
        score += rows * 2
        return land()
    }

    var isResting: Bool {
        guard var below = piece else { return false }
        below.row += 1
        return !fits(below)
    }

    /// Where the piece would come to rest, shown as its shadow.
    var ghost: Piece? {
        guard var ghost = piece else { return nil }
        while true {
            var below = ghost
            below.row += 1
            guard fits(below) else { return ghost }
            ghost = below
        }
    }

    /// Swaps the piece with the one on hold (or the next one, the first time).
    mutating func hold() {
        guard let current = piece, canHold, !isOver else { return }
        canHold = false
        if let held {
            self.held = current.shape
            spawn(held)
        } else {
            held = current.shape
            spawn()
        }
    }

    /// Puts the piece where it is: full rows clear, rows sent by the other player come in below,
    /// and the next piece starts at the top.
    @discardableResult
    mutating func land() -> Landing {
        guard let piece, !isOver else { return Landing() }
        var landing = Landing()
        for cell in piece.cells {
            // A piece resting partly above the well ends the game.
            guard cell.row >= 0 else {
                isOver = true
                self.piece = nil
                return landing
            }
            board[cell.row][cell.column] = piece.shape.rawValue
        }
        self.piece = nil

        let full = board.indices.filter { row in board[row].allSatisfy { $0 != 0 } }
        landing.clearedRows = full.count
        if !full.isEmpty {
            landing.fullRows = full
            landing.cellsBeforeClearing = Array(board.joined())
            board.removeAll { row in row.allSatisfy { $0 != 0 } }
            board.insert(contentsOf: Array(repeating: Array(repeating: 0, count: Self.columns), count: full.count), at: 0)
            clearedRows += full.count
            score += [0, 100, 300, 500, 800][min(full.count, 4)] * level
        }

        // Rows cleared cancel rows on their way here first; what's left goes to the other player.
        var attack = [0, 0, 1, 2, 4][min(full.count, 4)]
        let cancelled = min(attack, incoming.count)
        incoming.removeFirst(cancelled)
        attack -= cancelled
        landing.sentRows = attack

        if full.isEmpty {
            for gap in incoming {
                addGarbageRow(gap: gap)
                if isOver { return landing }
            }
            incoming = []
        }
        canHold = true
        spawn()
        return landing
    }

    // MARK: Duel

    /// Rows sent by the other player; they come in once the next piece rests without clearing.
    mutating func receive(rows: Int, gap: Int) {
        guard !isOver, rows > 0 else { return }
        incoming += Array(repeating: min(max(gap, 0), Self.columns - 1), count: rows)
    }

    /// Where the gap goes in rows this player sends.
    mutating func nextGap() -> Int {
        Int(gaps.next() % UInt64(Self.columns))
    }

    /// The well row by row, top first, with the falling piece in it.
    var visibleCells: [UInt8] {
        var cells = Array(board.joined())
        if let piece {
            for cell in piece.cells where cell.row >= 0 {
                cells[cell.row * Self.columns + cell.column] = piece.shape.rawValue
            }
        }
        return cells
    }

    /// Where the piece would rest, as indexes into `visibleCells`.
    var ghostIndexes: Set<Int> {
        guard let ghost else { return [] }
        return Set(ghost.cells.filter { $0.row >= 0 }.map { $0.row * Self.columns + $0.column })
    }

    /// The well as the other player sees it: 200 digits, the piece falling included.
    var snapshot: String {
        String(visibleCells.map { Character(String($0)) })
    }

    static func cells(fromSnapshot text: String) -> [UInt8]? {
        let cells = text.compactMap { $0.wholeNumberValue }.map { UInt8($0) }
        guard cells.count == columns * rows, cells.allSatisfy({ $0 <= garbage }) else { return nil }
        return cells
    }

    // MARK: Private

    private func fits(_ piece: Piece) -> Bool {
        piece.cells.allSatisfy { cell in
            cell.column >= 0 && cell.column < Self.columns && cell.row < Self.rows
                && (cell.row < 0 || board[cell.row][cell.column] == 0)
        }
    }

    /// The next piece at the top, centered; the game is over when there's no room for it.
    private mutating func spawn(_ shape: Shape? = nil) {
        let shape = shape ?? upcoming.removeFirst()
        refillUpcoming()
        let start = Piece(shape: shape, row: shape == .bar ? -1 : 0, column: (Self.columns - shape.boxSize) / 2)
        if fits(start) {
            piece = start
        } else {
            piece = nil
            isOver = true
        }
    }

    /// Pieces come in shuffled sets of all seven, so none is long missing.
    private mutating func refillUpcoming() {
        while upcoming.count < 7 {
            var set = Shape.allCases
            for index in stride(from: set.count - 1, to: 0, by: -1) {
                set.swapAt(index, Int(pieces.next() % UInt64(index + 1)))
            }
            upcoming += set
        }
    }

    private mutating func addGarbageRow(gap: Int) {
        // Pushing a block out of the top ends the game.
        if board[0].contains(where: { $0 != 0 }) {
            isOver = true
            return
        }
        board.removeFirst()
        var row = Array(repeating: Self.garbage, count: Self.columns)
        row[gap] = 0
        board.append(row)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.board == rhs.board && lhs.piece == rhs.piece && lhs.held == rhs.held && lhs.canHold == rhs.canHold
            && lhs.upcoming.prefix(3) == rhs.upcoming.prefix(3) && lhs.score == rhs.score
            && lhs.clearedRows == rhs.clearedRows && lhs.isOver == rhs.isOver && lhs.incoming == rhs.incoming
    }
}

/// SplitMix64: the same seed gives the same numbers on every Mac.
private nonisolated struct DropRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
