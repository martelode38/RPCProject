struct BoardPosition: Identifiable, Hashable, Codable {
    let row: Int
    let column: Int

    var id: String {
        "\(row)-\(column)"
    }
}

enum PieceOwner: String, Codable {
    case white
    case black

    var opponent: PieceOwner {
        switch self {
        case .white:
            return .black
        case .black:
            return .white
        }
    }
}

enum CaptureKind: String, Codable {
    case approach
    case withdrawal

    var title: String {
        switch self {
        case .approach:
            return "Aproximação"
        case .withdrawal:
            return "Afastamento"
        }
    }
}

enum GameOverReason: String, Codable {
    case resignation
    case noPieces
    case disconnect

    var title: String {
        switch self {
        case .resignation:
            return "Desistência"
        case .noPieces:
            return "Sem peças"
        case .disconnect:
            return "Desconexão"
        }
    }
}

struct Piece: Codable {
    let owner: PieceOwner
    let position: BoardPosition

    init(owner: PieceOwner, position: BoardPosition) {
        self.owner = owner
        self.position = position
    }
}

struct Board {
    static let rows = 5
    static let columns = 9

    let positions: [BoardPosition]
    var pieces: [BoardPosition: Piece]

    init(positions: [BoardPosition], pieces: [BoardPosition: Piece]) {
        self.positions = positions
        self.pieces = pieces
    }

    static func initial() -> Board {
        var positions: [BoardPosition] = []
        var pieces: [BoardPosition: Piece] = [:]

        for row in 0..<rows {
            for column in 0..<columns {
                let position = BoardPosition(row: row, column: column)
                positions.append(position)

                switch row {
                case 0, 1:
                    pieces[position] = Piece(owner: .white, position: position)
                case 2:
                    if column != 4 {
                        let isRightSide = column > 4
                        let owner: PieceOwner = column.isMultiple(of: 2) == isRightSide ? .black : .white
                        pieces[position] = Piece(owner: owner, position: position)
                    }
                case 3, 4:
                    pieces[position] = Piece(owner: .black, position: position)
                default:
                    break
                }
            }
        }

        return Board(positions: positions, pieces: pieces)
    }

    func piece(at position: BoardPosition) -> Piece? {
        pieces[position]
    }

    func isEmpty(at position: BoardPosition) -> Bool {
        pieces[position] == nil
    }

    func pieceCount(for owner: PieceOwner) -> Int {
        pieces.values.filter { $0.owner == owner }.count
    }

    var winner: PieceOwner? {
        if pieceCount(for: .white) == 0 {
            return .black
        }

        if pieceCount(for: .black) == 0 {
            return .white
        }

        return nil
    }

    func contains(_ position: BoardPosition) -> Bool {
        position.row >= 0
            && position.row < Self.rows
            && position.column >= 0
            && position.column < Self.columns
    }

    func isValidStep(from source: BoardPosition, to destination: BoardPosition) -> Bool {
        let rowDelta = destination.row - source.row
        let columnDelta = destination.column - source.column
        return contains(source)
            && contains(destination)
            && abs(rowDelta) <= 1
            && abs(columnDelta) <= 1
            && (rowDelta != 0 || columnDelta != 0)
            && (rowDelta == 0 || columnDelta == 0 || (source.row + source.column).isMultiple(of: 2))
    }

    func capturePositions(from source: BoardPosition, to destination: BoardPosition, kind: CaptureKind) -> [BoardPosition] {
        guard let movingPiece = piece(at: source), isEmpty(at: destination) else { return [] }

        guard isValidStep(from: source, to: destination) else { return [] }

        let rowDelta = destination.row - source.row
        let columnDelta = destination.column - source.column

        let captureRowDirection = kind == .approach ? rowDelta : -rowDelta
        let captureColumnDirection = kind == .approach ? columnDelta : -columnDelta

        let firstCapturePosition = kind == .approach ? destination : source
        var current = BoardPosition(
            row: firstCapturePosition.row + captureRowDirection,
            column: firstCapturePosition.column + captureColumnDirection
        )
        var captured: [BoardPosition] = []

        while contains(current), let piece = piece(at: current), piece.owner == movingPiece.owner.opponent {
            captured.append(current)
            current = BoardPosition(
                row: current.row + captureRowDirection,
                column: current.column + captureColumnDirection
            )
        }

        return captured
    }

    func captureOptions(from source: BoardPosition, to destination: BoardPosition) -> [CaptureKind] {
        [CaptureKind.approach, .withdrawal].filter {
            !capturePositions(from: source, to: destination, kind: $0).isEmpty
        }
    }

    func captureDestinations(from source: BoardPosition, excluding visited: Set<BoardPosition>) -> [BoardPosition] {
        positions.filter {
            !visited.contains($0) && !captureOptions(from: source, to: $0).isEmpty
        }
    }

    mutating func movePiece(from source: BoardPosition, to destination: BoardPosition) {
        guard let piece = pieces[source] else { return }
        guard pieces[destination] == nil else { return }

        pieces[source] = nil
        pieces[destination] = Piece(owner: piece.owner, position: destination)
    }

    mutating func removePieces(at positions: [BoardPosition]) {
        for position in positions {
            pieces[position] = nil
        }
    }
}
