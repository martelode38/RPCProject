import Foundation

enum RPCParser {

    static func encode(_ message: GameRPCCall) -> Data? {
        try? JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) -> GameRPCCall? {
        try? JSONDecoder().decode(GameRPCCall.self, from: data)
    }

    static func encodeFramed(_ message: GameRPCCall) -> Data? {
        guard let data = encode(message) else { return nil }
        var framed = Data(data)
        framed.append(0x0A)
        return framed
    }

    static func decodeMessages(from buffer: inout Data) -> [GameRPCCall] {
        var messages: [GameRPCCall] = []

        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let messageData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)

            if let message = decode(messageData) {
                messages.append(message)
            }
        }

        return messages
    }

    static func summary(for message: GameRPCCall) -> String {
        switch message.method {
        case .join:
            let name = message.player?.name ?? "?"
            return "game.join \(name)"
        case .ready:
            let name = message.player?.name ?? "?"
            return "game.ready \(name)"
        case .start:
            return "game.start"
        case .move:
            let origin = message.origin.map { "\($0.row),\($0.column)" } ?? "?"
            let destination = message.destination.map { "\($0.row),\($0.column)" } ?? "?"
            let capture = message.captureKind?.title ?? "sem captura"
            return "game.move \(origin) \(destination) \(capture) x\(message.capturedPositions.count)"
        case .endTurn:
            return "game.endTurn"
        case .chat:
            return "game.chat \(message.text ?? "")"
        case .leave:
            let name = message.player?.name ?? "?"
            return "game.leave \(name)"
        case .finish:
            let winner = message.winner?.rawValue ?? "?"
            let reason = message.gameOverReason?.title ?? "Fim"
            return "game.finish \(winner) \(reason)"
        }
    }
}
