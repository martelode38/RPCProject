import Foundation
internal import Combine
import UIKit

@MainActor
final class LobbyViewModel: ObservableObject {

    // MARK: - Estado da conexao e do lobby

    @Published var playerName: String = UIDevice.current.name
    @Published var host: String = "192.168.1.3"
    @Published var portText: String = "8080"
    @Published var message: String = "Olá servidor!"
    @Published var chatMessages: [ChatMessage] = []
    @Published var logs: [String] = []
    @Published var serverStatus: String = "Servidor parado"
    @Published var clientStatus: String = "Desconectado"
    @Published var connectedPlayerName: String = "Nenhum jogador"
    @Published var gameState: GameState = .waiting
    @Published var hostReady = false
    @Published var clientReady = false
    @Published var isServerRunning = false
    @Published var isClientConnected = false
    @Published var isStartingServer = false
    @Published var isStoppingServer = false
    @Published var isConnectingClient = false
    @Published var isSendingMessage = false
    @Published var isShowingGameScreen = false

    // MARK: - Estado do tabuleiro e da partida

    @Published var board = Board.initial()
    @Published var selectedPosition: BoardPosition?
    @Published private(set) var pendingCaptureDestination: BoardPosition?
    @Published private(set) var captureSequencePosition: BoardPosition?
    private var visitedCapturePositions: Set<BoardPosition> = []
    @Published var boardStatus: String = "Selecione uma peça"

    @Published var currentTurn: PieceOwner = .white
    @Published var winnerText: String = ""

    private let repository = LobbyRepository()

    init() {

        repository.onServerStateChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.handleServerState(status)
            }
        }

        repository.onClientStateChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.handleClientState(status)
            }
        }

        repository.onServerMessageReceived = { [weak self] message in
            DispatchQueue.main.async {
                self?.handleServerMessage(message)
            }
        }

        repository.onClientMessageReceived = { [weak self] message in
            DispatchQueue.main.async {
                self?.handleClientMessage(message)
            }
        }
    }

    private func handleServerState(_ status: String) {
        serverStatus = status
        isServerRunning = status != "Servidor parado" && status != "Erro no servidor"
        isStartingServer = false
        if status == "Aguardando conexão" || !isServerRunning {
            handleConnectionLoss()
        }
        appendLog("HOST: \(status)")
    }

    private func handleClientState(_ status: String) {
        clientStatus = status
        if status == "Cliente conectado" {
            isClientConnected = true
            isConnectingClient = false
        } else if status == "Erro na conexão" || status == "Desconectado" {
            isConnectingClient = false
            handleConnectionLoss()
        }
        appendLog("CLIENTE: \(status)")
    }

    private func handleConnectionLoss() {
        isClientConnected = false
        connectedPlayerName = "Nenhum jogador"
        hostReady = false
        clientReady = false
        if gameState == .playing {
            finishMatch()
            boardStatus = "Conexão encerrada durante a partida"
        }
    }

    // MARK: - Controle do servidor

    func startServer() {
        guard let port = UInt16(portText), port > 0 else {
            appendLog("Porta inválida")
            return
        }

        isStartingServer = true
        dismissKeyboard()
        resetMatchState()
        isShowingGameScreen = false
        repository.startServer(port: port)
        serverStatus = "Iniciando servidor..."
        appendLog("Iniciando servidor na porta \(port)")
    }

    func stopServer() {
        isStoppingServer = true
        repository.stopServer()
        serverStatus = "Servidor parado"
        isServerRunning = false
        isClientConnected = false
        connectedPlayerName = "Nenhum jogador"
        if isShowingGameScreen {
            finishMatch()
        } else {
            resetLobbyState()
        }
        appendLog("Servidor parado")
        isStoppingServer = false
    }

    func toggleServer() {
        if isServerRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    // MARK: - Controle do cliente

    func connectClient() {
        guard let port = UInt16(portText), port > 0 else {
            appendLog("Porta inválida")
            return
        }

        guard !isConnectingClient, !isClientConnected else {
            appendLog("Cliente já está conectando ou conectado")
            return
        }

        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            clientStatus = "Informe o endereço do servidor"
            return
        }
        host = address
        isConnectingClient = true
        dismissKeyboard()
        resetMatchState()
        isShowingGameScreen = false

        repository.connectClient(host: host, port: port, player: Player(name: resolvedPlayerName))
        clientStatus = "Conectando..."
        isClientConnected = false
        appendLog("Cliente conectando em \(host):\(port) como \(resolvedPlayerName)")
    }

    func disconnectClient() {
        isConnectingClient = false
        repository.disconnectClient()
        clientStatus = "Desconectado"
        isClientConnected = false
        if isShowingGameScreen {
            finishMatch()
        } else {
            resetLobbyState()
        }
        appendLog("Cliente desconectado")
    }

    func toggleClient() {
        if isClientConnected || isConnectingClient {
            disconnectClient()
        } else {
            connectClient()
        }
    }

    // MARK: - Chat

    func sendChatMessage() {
        guard canSendChatMessage else { return }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSendingMessage = true
        dismissKeyboard()
        sendToPeer(GameRPCCall(method: .chat, text: text))
        chatMessages.append(ChatMessage(text: text, isMine: true))
        message = ""
        let sender = isServerRunning ? "Servidor" : "Cliente"
        appendLog("\(sender) enviou: \(text)")
        isSendingMessage = false
    }

    // MARK: - Preparacao e inicio da partida

    func readyAsHost() {
        guard isServerRunning, isClientConnected, !hostReady, gameState != .playing else { return }
        gameState = .waiting
        hostReady = true
        sendToPeer(GameRPCCall(method: .ready, player: Player(name: resolvedPlayerName)))
        appendLog("HOST ficou pronto")
        attemptStartGame()
    }

    func readyAsClient() {
        guard !isServerRunning, isClientConnected, !clientReady, gameState != .playing else { return }
        gameState = .waiting
        clientReady = true
        sendToPeer(GameRPCCall(method: .ready, player: Player(name: resolvedPlayerName)))
        appendLog("CLIENTE ficou pronto")
    }

    func markReady() {
        if isServerRunning {
            readyAsHost()
        } else {
            readyAsClient()
        }
    }

    // MARK: - Saida, desistência e desconexao

    func disconnectFromGame() {
        if isServerRunning {
            stopServer()
        } else if isClientConnected {
            disconnectClient()
        } else {
            resetLobbyState()
        }
    }

    func resignMatch() {
        guard gameState == .playing, isShowingGameScreen else { return }

        let winner = localPieceOwner.opponent
        sendGameOver(winner: winner, reason: .resignation)
        finishMatch(winner: winner, reason: .resignation)
        appendLog("Você desistiu")
    }

    // MARK: - Interacao com o tabuleiro

    func handleBoardTap(_ position: BoardPosition) {
        guard gameState == .playing, isShowingGameScreen else { return }
        guard isLocalPlayersTurn else {
            boardStatus = "Aguarde sua vez"
            return
        }

        guard pendingCaptureDestination == nil else {
            boardStatus = "Escolha aproximação ou afastamento, ou cancele"
            return
        }

        if let origin = captureSequencePosition {
            if board.isEmpty(at: position) {
                performLocalMove(from: origin, to: position)
            } else {
                boardStatus = "Continue capturando com a mesma peça ou encerre o turno"
            }
            return
        }

        if let selectedPosition {
            if selectedPosition == position {
                self.selectedPosition = nil
                boardStatus = "Peça desmarcada"
                return
            }

            if board.isEmpty(at: position) {
                performLocalMove(from: selectedPosition, to: position)
            } else if let piece = board.piece(at: position), piece.owner == localPieceOwner {
                self.selectedPosition = position
                boardStatus = "Outra peça selecionada"
            } else {
                boardStatus = "Destino ocupado"
            }
            return
        }

        guard let piece = board.piece(at: position) else {
            boardStatus = "Selecione uma peça primeiro"
            return
        }

        guard piece.owner == localPieceOwner else {
            boardStatus = isLocalPlayersTurn ? "Selecione sua própria peça" : "Aguarde sua vez"
            return
        }

        selectedPosition = position
        boardStatus = "Peça selecionada"
    }

    func chooseCapture(_ kind: CaptureKind) {
        guard let origin = selectedPosition, let destination = pendingCaptureDestination else { return }
        performLocalMove(from: origin, to: destination, captureKind: kind)
    }

    func cancelCaptureChoice() {
        pendingCaptureDestination = nil
        boardStatus = "Selecione outro destino"
    }

    var canEndCaptureSequence: Bool {
        gameState == .playing && isLocalPlayersTurn && captureSequencePosition != nil
            && pendingCaptureDestination == nil
    }

    func endCaptureSequence() {
        guard canEndCaptureSequence else { return }
        sendToPeer(GameRPCCall(method: .endTurn))
        advanceTurn()
    }

    private func applyRemoteEndTurn() {
        guard gameState == .playing, !isLocalPlayersTurn, captureSequencePosition != nil else { return }
        advanceTurn()
    }

    private func clearCaptureSequence() {
        captureSequencePosition = nil
        visitedCapturePositions.removeAll()
    }

    private func advanceTurn() {
        clearCaptureSequence()
        selectedPosition = nil
        pendingCaptureDestination = nil
        currentTurn = currentTurn.opponent
        boardStatus = isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente"
    }

    private func updateTurnAfterMove(from origin: BoardPosition, to destination: BoardPosition, captured: Bool) {
        if captured {
            visitedCapturePositions.insert(origin)
            visitedCapturePositions.insert(destination)
            if !board.captureDestinations(from: destination, excluding: visitedCapturePositions).isEmpty {
                captureSequencePosition = destination
                selectedPosition = isLocalPlayersTurn ? destination : nil
                boardStatus = isLocalPlayersTurn
                    ? "Continue capturando com a mesma peça ou encerre o turno"
                    : "Oponente continua a sequência de capturas"
                return
            }
        }
        advanceTurn()
    }

    var matchStatusText: String {
        switch gameState {
        case .waiting:
            if !isServerRunning && !isClientConnected {
                return "Aguardando servidor e cliente"
            }
            if isServerRunning && !isClientConnected {
                return "Servidor pronto. Aguardando cliente."
            }
            if hostReady && clientReady {
                return "Aguardando início pelo servidor"
            }
            if hostReady {
                return "HOST pronto. Aguardando CLIENTE."
            }
            if clientReady {
                return "CLIENTE pronto. Aguardando HOST."
            }
            return "Conexão estabelecida. Marque Estou pronto."
        case .playing:
            return "Tela de jogo aberta"
        case .finished:
            return winnerText.isEmpty ? "Partida encerrada" : winnerText
        }
    }

    var matchStatusDetail: String {
        switch gameState {
        case .waiting:
            return "A partida começa quando os dois estiverem prontos. O servidor joga com as brancas e começa."
        case .playing:
            return "Você já está na tela do jogo."
        case .finished:
            return boardStatus
        }
    }

    var roleText: String {
        if isServerRunning {
            return "Servidor"
        }

        if isClientConnected || isConnectingClient {
            return "Cliente"
        }

        return "Escolha uma função"
    }

    var serverButtonTitle: String {
        isServerRunning ? "Parar servidor" : "Iniciar servidor"
    }

    var clientButtonTitle: String {
        if isConnectingClient { return "Cancelar conexão" }
        return isClientConnected ? "Desconectar" : "Conectar"
    }

    var readyButtonTitle: String {
        if isServerRunning && hostReady {
            return "Servidor pronto"
        }

        if isClientConnected && clientReady {
            return "Cliente pronto"
        }

        return "Estou pronto"
    }

    var isServerButtonDisabled: Bool {
        isStartingServer || isStoppingServer || isConnectingClient || (isClientConnected && !isServerRunning)
    }

    var isClientButtonDisabled: Bool {
        isStartingServer || isServerRunning || (!isClientConnected && !isConnectingClient && host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var isReadyButtonDisabled: Bool {
        guard isClientConnected, gameState != .playing else { return true }
        if isServerRunning {
            return hostReady
        }

        if isClientConnected {
            return clientReady
        }

        return true
    }

    var canSendChatMessage: Bool {
        !isSendingMessage
            && isClientConnected
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Mensagens recebidas da rede

    private func handleServerMessage(_ message: GameRPCCall) {
        switch message.method {
        case .join:
            let name = message.player?.name ?? "Jogador"
            connectedPlayerName = name
            serverStatus = "Cliente conectado"
            isClientConnected = true
            sendToPeer(GameRPCCall(method: .join, player: Player(name: resolvedPlayerName)))
            appendLog("HOST recebeu game.join de \(name)")
        case .ready:
            guard isClientConnected, gameState != .playing else { return }
            clientReady = true
            appendLog("HOST recebeu game.ready de \(message.player?.name ?? "Jogador")")
            attemptStartGame()
        case .start:
            appendLog("Inicio ignorado: somente o servidor inicia a partida")
        case .move:
            applyRemoteMove(message)
        case .endTurn:
            applyRemoteEndTurn()
        case .chat:
            appendChatFromPeer(message.text)
            appendLog("HOST recebeu: \(message.text ?? "")")
        case .leave:
            let name = message.player?.name ?? "Jogador"
            connectedPlayerName = "Nenhum jogador"
            serverStatus = "Aguardando conexão"
            isClientConnected = false
            if isShowingGameScreen {
                finishMatch(winner: .white, reason: .disconnect)
            } else {
                resetLobbyState()
            }
            appendLog("HOST recebeu disconnect de \(name)")
        case .finish:
            applyGameOver(message)
        }
    }

    private func handleClientMessage(_ message: GameRPCCall) {
        switch message.method {
        case .join:
            connectedPlayerName = message.player?.name ?? "Jogador"
            appendLog("CLIENTE recebeu game.join de \(message.player?.name ?? "Jogador")")
        case .ready:
            guard isClientConnected, gameState != .playing else { return }
            hostReady = true
            appendLog("CLIENTE recebeu game.ready de \(message.player?.name ?? "Jogador")")
        case .start:
            guard isClientConnected, clientReady, gameState != .playing else { return }
            hostReady = true
            beginMatch()
            appendLog("CLIENTE recebeu game.start")
        case .move:
            applyRemoteMove(message)
        case .endTurn:
            applyRemoteEndTurn()
        case .chat:
            appendChatFromPeer(message.text)
            appendLog("CLIENTE recebeu: \(message.text ?? "")")
        case .leave:
            appendLog("CLIENTE recebeu disconnect")
            clientStatus = "Desconectado"
            isClientConnected = false
            if isShowingGameScreen {
                finishMatch(winner: .black, reason: .disconnect)
            } else {
                resetLobbyState()
            }
        case .finish:
            applyGameOver(message)
        }
    }

    private func attemptStartGame() {
        guard isServerRunning, isClientConnected, hostReady, clientReady else { return }
        guard gameState != .playing else { return }

        beginMatch()
        sendToPeer(GameRPCCall(method: .start, gameState: .playing))
        appendLog("HOST enviou game.start")
    }

    private func beginMatch() {
        resetBoardForNewGame()
        winnerText = ""
        gameState = .playing
        isShowingGameScreen = true
    }

    // MARK: - Reset e fim de partida

    private func resetMatchState() {
        clearCaptureSequence()
        gameState = .waiting
        hostReady = false
        clientReady = false
    }

    private func resetLobbyState() {
        clearCaptureSequence()
        gameState = .waiting
        hostReady = false
        clientReady = false
        isShowingGameScreen = false
        connectedPlayerName = "Nenhum jogador"
        selectedPosition = nil
        pendingCaptureDestination = nil
        boardStatus = "Selecione uma peça"
        currentTurn = .white
        winnerText = ""
        chatMessages.removeAll()
        board = Board.initial()
    }

    private func finishMatch(winner: PieceOwner? = nil, reason: GameOverReason? = nil) {
        clearCaptureSequence()
        gameState = .finished
        hostReady = false
        clientReady = false
        isShowingGameScreen = false
        selectedPosition = nil
        pendingCaptureDestination = nil
        if let winner {
            winnerText = "Vencedor: \(displayName(for: winner))"
            boardStatus = "\(winnerText) - \(reason?.title ?? "Fim de jogo")"
        } else {
            winnerText = ""
            boardStatus = "Partida encerrada"
        }
    }

    // MARK: - Controle de turno

    private var localPieceOwner: PieceOwner {
        isServerRunning ? .white : .black
    }

    private var isLocalPlayersTurn: Bool {
        currentTurn == localPieceOwner
    }

    private func resetBoardForNewGame() {
        clearCaptureSequence()
        board = Board.initial()
        selectedPosition = nil
        pendingCaptureDestination = nil
        currentTurn = .white
        boardStatus = isLocalPlayersTurn ? "Sua vez" : "Aguardando oponente"
    }

    // MARK: - Movimento local

    private func performLocalMove(from origin: BoardPosition, to destination: BoardPosition, captureKind chosenKind: CaptureKind? = nil) {
        guard gameState == .playing, isLocalPlayersTurn,
              board.piece(at: origin)?.owner == localPieceOwner else { return }
        guard board.isValidStep(from: origin, to: destination) else {
            boardStatus = "Movimento inválido"
            return
        }

        guard board.isEmpty(at: destination) else {
            boardStatus = "Destino ocupado"
            return
        }

        let options = board.captureOptions(from: origin, to: destination)
        if let sequence = captureSequencePosition {
            guard origin == sequence, !visitedCapturePositions.contains(destination), !options.isEmpty else {
                boardStatus = "Capture com a mesma peça sem repetir posições"
                return
            }
        }
        if options.count == 2 && chosenKind == nil {
            pendingCaptureDestination = destination
            boardStatus = "Escolha como capturar"
            return
        }
        if let chosenKind, !options.contains(chosenKind) { return }
        let captureKind = chosenKind ?? options.first
        let capturedPositions = captureKind.map {
            board.capturePositions(from: origin, to: destination, kind: $0)
        } ?? []

        board.movePiece(from: origin, to: destination)
        board.removePieces(at: capturedPositions)
        selectedPosition = nil
        pendingCaptureDestination = nil

        if let winner = board.winner {
            sendMove(
                origin: origin,
                destination: destination,
                captureKind: captureKind,
                capturedPositions: capturedPositions
            )
            sendGameOver(winner: winner, reason: .noPieces)
            finishMatch(winner: winner, reason: .noPieces)
            appendMoveLog(origin: origin, destination: destination, captureKind: captureKind, capturedPositions: capturedPositions)
            return
        }

        updateTurnAfterMove(from: origin, to: destination, captured: !capturedPositions.isEmpty)
        appendMoveLog(origin: origin, destination: destination, captureKind: captureKind, capturedPositions: capturedPositions)

        sendMove(
            origin: origin,
            destination: destination,
            captureKind: captureKind,
            capturedPositions: capturedPositions
        )
    }

    private func sendMove(
        origin: BoardPosition,
        destination: BoardPosition,
        captureKind: CaptureKind?,
        capturedPositions: [BoardPosition]
    ) {
        let message = GameRPCCall(
            method: .move,
            origin: origin,
            destination: destination,
            captureKind: captureKind,
            capturedPositions: capturedPositions,
            boardPieces: Array(board.pieces.values)
        )
        sendToPeer(message)
    }

    // MARK: - Movimento recebido

    private func applyRemoteMove(_ message: GameRPCCall) {
        guard gameState == .playing, !isLocalPlayersTurn else { return }
        let capturedPositions = message.capturedPositions
        guard let origin = message.origin, let destination = message.destination else {
            appendLog("Move inválido recebido")
            return
        }

        guard board.isValidStep(from: origin, to: destination),
              board.piece(at: origin)?.owner == currentTurn,
              board.isEmpty(at: destination) else {
            appendLog("Movimento RPC inválido")
            return
        }
        if let sequence = captureSequencePosition {
            guard origin == sequence, !visitedCapturePositions.contains(destination), !capturedPositions.isEmpty else {
                appendLog("Sequência RPC inválida")
                return
            }
        }
        let options = board.captureOptions(from: origin, to: destination)
        if let kind = message.captureKind {
            guard options.contains(kind),
                  board.capturePositions(from: origin, to: destination, kind: kind) == capturedPositions else {
                appendLog("Captura RPC inválida")
                return
            }
        } else if !options.isEmpty || !capturedPositions.isEmpty {
            appendLog("Tipo de captura RPC ausente")
            return
        }

        var updatedBoard = board
        updatedBoard.movePiece(from: origin, to: destination)
        updatedBoard.removePieces(at: capturedPositions)
        guard let boardPieces = message.boardPieces,
              boardPieces.count == updatedBoard.pieces.count,
              Set(boardPieces.map(\.position)).count == boardPieces.count,
              boardPieces.allSatisfy({ updatedBoard.piece(at: $0.position)?.owner == $0.owner }) else {
            appendLog("Estado RPC diferente do resultado da jogada")
            return
        }
        board = updatedBoard
        selectedPosition = nil
        pendingCaptureDestination = nil

        if let winner = board.winner {
            finishMatch(winner: winner, reason: message.gameOverReason ?? .noPieces)
            appendLog("Fim de jogo recebido")
            return
        }

        updateTurnAfterMove(from: origin, to: destination, captured: !capturedPositions.isEmpty)
        appendLog("Movimento recebido: \(origin.row),\(origin.column) -> \(destination.row),\(destination.column)")
        if !capturedPositions.isEmpty {
            let captureKind = message.captureKind?.title.lowercased() ?? "captura"
            appendLog("Captura recebida por \(captureKind): \(capturedPositions.count)")
        }
    }

    private func appendMoveLog(
        origin: BoardPosition,
        destination: BoardPosition,
        captureKind: CaptureKind?,
        capturedPositions: [BoardPosition]
    ) {
        appendLog("Movimento local: \(origin.row),\(origin.column) -> \(destination.row),\(destination.column)")
        if !capturedPositions.isEmpty {
            let captureName = captureKind?.title.lowercased() ?? "captura"
            appendLog("Captura por \(captureName): \(capturedPositions.count)")
        }
    }

    // MARK: - Vencedor e fim comunicado

    private func sendGameOver(winner: PieceOwner, reason: GameOverReason) {
        let message = GameRPCCall(
            method: .finish,
            winner: winner,
            gameOverReason: reason
        )

        sendToPeer(message)
    }

    private func applyGameOver(_ message: GameRPCCall) {
        guard gameState == .playing,
              let winner = message.winner,
              let reason = message.gameOverReason else { return }
        switch reason {
        case .resignation:
            guard winner == localPieceOwner else { return }
        case .noPieces:
            guard board.winner == winner else { return }
        case .disconnect:
            return
        }
        finishMatch(winner: winner, reason: reason)
        appendLog("Fim recebido: \(reason.title)")
    }

    // MARK: - Utilitarios

    private func displayName(for owner: PieceOwner) -> String {
        switch owner {
        case .white:
            return "Brancas"
        case .black:
            return "Pretas"
        }
    }

    private var resolvedPlayerName: String {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? UIDevice.current.name : trimmedName
    }

    private func sendToPeer(_ message: GameRPCCall) {
        if isServerRunning {
            repository.sendFromServer(message)
        } else {
            repository.sendFromClient(message)
        }
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > 60 {
            logs.removeFirst(logs.count - 60)
        }
    }

    private func appendChatFromPeer(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        chatMessages.append(ChatMessage(text: text, isMine: false))
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
