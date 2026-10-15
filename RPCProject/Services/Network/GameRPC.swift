import Foundation

struct Player: Codable {
    let name: String

    init(name: String) {
        self.name = name
    }
}

enum GameState: String, Codable {
    case waiting
    case playing
    case finished
}

enum GameRPCMethod: String, Codable {
    case join = "game.join"
    case ready = "game.ready"
    case start = "game.start"
    case move = "game.move"
    case endTurn = "game.endTurn"
    case chat = "game.chat"
    case leave = "game.leave"
    case finish = "game.finish"

}

struct GameRPCCall: Codable {
    let method: GameRPCMethod
    let player: Player?
    let text: String?
    let gameState: GameState?
    let origin: BoardPosition?
    let destination: BoardPosition?
    let captureKind: CaptureKind?
    let capturedPositions: [BoardPosition]
    let boardPieces: [Piece]?
    let winner: PieceOwner?
    let gameOverReason: GameOverReason?

    init(
        method: GameRPCMethod,
        player: Player? = nil,
        text: String? = nil,
        gameState: GameState? = nil,
        origin: BoardPosition? = nil,
        destination: BoardPosition? = nil,
        captureKind: CaptureKind? = nil,
        capturedPositions: [BoardPosition] = [],
        boardPieces: [Piece]? = nil,
        winner: PieceOwner? = nil,
        gameOverReason: GameOverReason? = nil
    ) {
        self.method = method
        self.player = player
        self.text = text
        self.gameState = gameState
        self.origin = origin
        self.destination = destination
        self.captureKind = captureKind
        self.capturedPositions = capturedPositions
        self.boardPieces = boardPieces
        self.winner = winner
        self.gameOverReason = gameOverReason
    }

    enum CodingKeys: String, CodingKey {
        case player
        case text
        case gameState
        case origin
        case destination
        case captureKind
        case capturedPositions
        case boardPieces
        case winner
        case gameOverReason
    }

    private enum EnvelopeKeys: String, CodingKey {
        case jsonrpc, method, params, id
    }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: EnvelopeKeys.self)
        guard try envelope.decode(String.self, forKey: .jsonrpc) == "2.0",
              !envelope.contains(.id) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Esperada uma notificacao JSON-RPC 2.0 sem id"
            ))
        }
        method = try envelope.decode(GameRPCMethod.self, forKey: .method)
        let parameters = try envelope.superDecoder(forKey: .params)
        let container = try parameters.container(keyedBy: CodingKeys.self)
        player = try container.decodeIfPresent(Player.self, forKey: .player)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        gameState = try container.decodeIfPresent(GameState.self, forKey: .gameState)
        origin = try container.decodeIfPresent(BoardPosition.self, forKey: .origin)
        destination = try container.decodeIfPresent(BoardPosition.self, forKey: .destination)
        captureKind = try container.decodeIfPresent(CaptureKind.self, forKey: .captureKind)
        capturedPositions = try container.decodeIfPresent([BoardPosition].self, forKey: .capturedPositions) ?? []
        boardPieces = try container.decodeIfPresent([Piece].self, forKey: .boardPieces)
        winner = try container.decodeIfPresent(PieceOwner.self, forKey: .winner)
        gameOverReason = try container.decodeIfPresent(GameOverReason.self, forKey: .gameOverReason)
        guard hasRequiredParameters else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Parametros ausentes para \(method.rawValue)"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        guard hasRequiredParameters else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "Parametros obrigatorios ausentes"
            ))
        }
        var envelope = encoder.container(keyedBy: EnvelopeKeys.self)
        try envelope.encode("2.0", forKey: .jsonrpc)
        try envelope.encode(method, forKey: .method)
        let parameters = envelope.superEncoder(forKey: .params)
        var container = parameters.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(player, forKey: .player)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(gameState, forKey: .gameState)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encodeIfPresent(destination, forKey: .destination)
        try container.encodeIfPresent(captureKind, forKey: .captureKind)
        try container.encode(capturedPositions, forKey: .capturedPositions)
        try container.encodeIfPresent(boardPieces, forKey: .boardPieces)
        try container.encodeIfPresent(winner, forKey: .winner)
        try container.encodeIfPresent(gameOverReason, forKey: .gameOverReason)
    }

    private var hasRequiredParameters: Bool {
        switch method {
        case .join, .ready, .leave:
            return player != nil
        case .start:
            return gameState == .playing
        case .move:
            return origin != nil && destination != nil && boardPieces != nil
        case .endTurn:
            return true
        case .chat:
            return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .finish:
            return winner != nil && gameOverReason != nil
        }
    }
}
