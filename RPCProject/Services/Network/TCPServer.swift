import Foundation
import Network

final class TCPServer {
    private var listener: NWListener?
    private var connection: NWConnection?

    private var receiveBuffer = Data()
    private var isReceiving = false

    var onStateChange: ((String) -> Void)?
    var onMessageReceived: ((GameRPCCall) -> Void)?

    private let queue = DispatchQueue(label: "TCPServerQueue")
    private let port: NWEndpoint.Port

    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        guard listener == nil else {
            print("Servidor já está iniciado")
            return
        }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Servidor iniciado")
                    print("Aguardando conexão")
                    self?.onStateChange?("Servidor iniciado")
                case .failed(let error):
                    print("Erro no servidor: \(error)")
                    self?.onStateChange?("Erro no servidor")
                case .cancelled:
                    print("Servidor parado")
                    self?.onStateChange?("Servidor parado")
                case .waiting(let error):
                    print("Servidor aguardando: \(error)")
                    self?.onStateChange?("Servidor aguardando")
                default:
                    break
                }
            }

            listener.start(queue: queue)
        } catch {
            onStateChange?("Erro no servidor")
            print("Falha ao iniciar o servidor: \(error)")
        }
    }

    func stop() {
        queue.async {
            guard self.connection != nil else {
                self.close()
                return
            }

            self.send(GameRPCCall(method: .leave, player: Player(name: "HOST"))) {
                self.close()
            }
        }
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

    private func accept(_ newConnection: NWConnection) {
        if connection != nil {
            print("Servidor já possui um cliente conectado")
            newConnection.cancel()
            return
        }

        connection = newConnection
        receiveBuffer.removeAll(keepingCapacity: false)
        isReceiving = false

        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Cliente conectado")
                self?.receive()
            case .failed(let error):
                print("Erro na conexão: \(error)")
                self?.cleanupConnection()
            case .cancelled:
                print("Cliente desconectado")
                self?.cleanupConnection()
            case .waiting(let error):
                print("Servidor aguardando: \(error)")
            default:
                break
            }
        }

        newConnection.start(queue: queue)
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBufferedMessages(prefix: "Recebido do cliente")
            }

            if isComplete {
                connection.cancel()
                self.cleanupConnection()
                return
            }

            if let error {
                print("Erro na conexão: \(error)")
                self.cleanupConnection()
                return
            }

            self.receiveNextMessage(on: connection)
        }
    }

    private func processBufferedMessages(prefix: String) {
        for message in RPCParser.decodeMessages(from: &receiveBuffer) {
            onMessageReceived?(message)
            print("\(prefix): \(RPCParser.summary(for: message))")
        }
    }

    private func cleanupConnection() {
        guard let connection else { return }
        self.connection = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        isReceiving = false
        receiveBuffer.removeAll(keepingCapacity: false)
        onStateChange?("Aguardando conexão")
    }

    private func close() {
        isReceiving = false
        receiveBuffer.removeAll(keepingCapacity: false)
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }

    private func send(_ message: GameRPCCall, completion: (() -> Void)? = nil) {
        guard let connection = self.connection else {
            print("Nenhum cliente conectado")
            completion?()
            return
        }

        guard let data = RPCParser.encodeFramed(message) else {
            print("Falha ao codificar mensagem do servidor")
            completion?()
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("Erro ao enviar do servidor: \(error)")
            } else {
                print("Servidor enviou: \(RPCParser.summary(for: message))")
            }
            completion?()
        })
    }
}
