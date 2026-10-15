import Foundation
import Network

final class TCPClient {
    var onStateChange: ((String) -> Void)?
    var onMessageReceived: ((GameRPCCall) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "TCPClientQueue")
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let localPlayer: Player

    private var receiveBuffer = Data()
    private var isReceiving = false

    init(host: String, port: UInt16, player: Player) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        self.localPlayer = player
    }

    func connect() {
        guard connection == nil else {
            print("Cliente já está conectado ou conectando")
            return
        }

        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Cliente conectado")
                self?.onStateChange?("Cliente conectado")
                self?.receive()
                self?.send(GameRPCCall(method: .join, player: self?.localPlayer))
            case .failed(let error):
                print("Erro na conexão: \(error)")
                self?.cleanupConnection(status: "Erro na conexão")
            case .cancelled:
                print("Desconectado")
                self?.cleanupConnection()
            case .waiting(let error):
                print("Cliente aguardando: \(error)")
                if case .posix(.ECONNREFUSED) = error {
                    self?.cleanupConnection(status: "Erro na conexão")
                } else {
                    self?.onStateChange?("Cliente aguardando")
                }
            default:
                break
            }
        }

        print("Conectando...")
        connection.start(queue: queue)
    }

    func send(_ message: GameRPCCall) {
        queue.async { [weak self] in
            self?.send(message, completion: nil)
        }
    }

    func receive() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isReceiving, let connection = self.connection else { return }
            self.isReceiving = true
            self.receiveNextMessage(on: connection)
        }
    }

    func disconnect() {
        queue.async {
            guard self.connection != nil else {
                self.cleanupConnection()
                return
            }

            let disconnectMessage = GameRPCCall(method: .leave, player: self.localPlayer)
            self.send(disconnectMessage) {
                self.cleanupConnection()
            }
        }
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBufferedMessages()
            }

            if isComplete {
                connection.cancel()
                self.cleanupConnection()
                return
            }

            if let error {
                print("Erro na conexão: \(error)")
                self.cleanupConnection(status: "Erro na conexão")
                return
            }

            self.receiveNextMessage(on: connection)
        }
    }

    private func processBufferedMessages() {
        for message in RPCParser.decodeMessages(from: &receiveBuffer) {
            onMessageReceived?(message)
            print("Recebido do servidor: \(RPCParser.summary(for: message))")
        }
    }

    private func cleanupConnection(status: String = "Desconectado") {
        guard let connection else { return }
        self.connection = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        isReceiving = false
        receiveBuffer.removeAll(keepingCapacity: false)
        onStateChange?(status)
    }

    private func send(_ message: GameRPCCall, completion: (() -> Void)? = nil) {
        guard let connection = self.connection else {
            print("Cliente sem conexão ativa")
            completion?()
            return
        }

        guard let data = RPCParser.encodeFramed(message) else {
            print("Falha ao codificar mensagem do cliente")
            completion?()
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("Erro ao enviar do cliente: \(error)")
            } else {
                print("Cliente enviou: \(RPCParser.summary(for: message))")
            }
            completion?()
        })
    }
}
