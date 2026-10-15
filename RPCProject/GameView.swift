import SwiftUI

struct GameView: View {
    @ObservedObject var viewModel: LobbyViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fanorona")
                                .font(.title)
                            Text(viewModel.roleText)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack {
                            Button("Desistir") {
                                viewModel.resignMatch()
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.gameState != .playing)

                            Button("Sair") {
                                viewModel.disconnectFromGame()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text("Turno: \(viewModel.currentTurn == .white ? "Brancas" : "Pretas")")
                    Text(viewModel.boardStatus)
                    if !viewModel.winnerText.isEmpty {
                        Text(viewModel.winnerText)
                            .font(.headline)
                    }
                }

                FanoronaBoardView(
                    board: viewModel.board,
                    selectedPosition: viewModel.selectedPosition,
                    onTapPosition: viewModel.handleBoardTap
                )
                .frame(minHeight: 360)

                if viewModel.pendingCaptureDestination != nil {
                    HStack {
                        Button("Aproximação") { viewModel.chooseCapture(.approach) }
                        Button("Afastamento") { viewModel.chooseCapture(.withdrawal) }
                        Button("Cancelar") { viewModel.cancelCaptureChoice() }
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.canEndCaptureSequence {
                    Button("Encerrar turno") { viewModel.endCaptureSequence() }
                        .buttonStyle(.bordered)
                }

                ChatView(
                    messages: viewModel.chatMessages,
                    text: $viewModel.message,
                    canSend: viewModel.canSendChatMessage,
                    onSend: viewModel.sendChatMessage
                )
            }
            .padding()
        }
    }
}

private struct FanoronaBoardView: View {
    let board: Board
    let selectedPosition: BoardPosition?
    let onTapPosition: (BoardPosition) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let inset = size * 0.08
            let usableSize = size - inset * 2
            let columnSpacing = usableSize / CGFloat(Board.columns - 1)
            let rowSpacing = usableSize / CGFloat(Board.rows - 1)

            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .overlay(
                        Rectangle()
                            .stroke(lineWidth: 1)
                    )

                Path { path in
                    for row in 0..<Board.rows {
                        let y = inset + CGFloat(row) * rowSpacing
                        path.move(to: CGPoint(x: inset, y: y))
                        path.addLine(to: CGPoint(x: inset + usableSize, y: y))
                    }

                    for column in 0..<Board.columns {
                        let x = inset + CGFloat(column) * columnSpacing
                        path.move(to: CGPoint(x: x, y: inset))
                        path.addLine(to: CGPoint(x: x, y: inset + usableSize))
                    }

                    for origin in board.positions {
                        for columnDelta in [-1, 1] {
                            let destination = BoardPosition(row: origin.row + 1, column: origin.column + columnDelta)
                            if board.isValidStep(from: origin, to: destination) {
                                path.move(to: CGPoint(
                                    x: inset + CGFloat(origin.column) * columnSpacing,
                                    y: inset + CGFloat(origin.row) * rowSpacing
                                ))
                                path.addLine(to: CGPoint(
                                    x: inset + CGFloat(destination.column) * columnSpacing,
                                    y: inset + CGFloat(destination.row) * rowSpacing
                                ))
                            }
                        }
                    }
                }
                .stroke(lineWidth: 1)

                ForEach(board.positions) { position in
                    let point = CGPoint(
                        x: inset + CGFloat(position.column) * columnSpacing,
                        y: inset + CGFloat(position.row) * rowSpacing
                    )

                    Button {
                        onTapPosition(position)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.gray.opacity(0.18))
                                .frame(width: size * 0.09, height: size * 0.09)

                            if selectedPosition == position {
                                Circle()
                                    .stroke(lineWidth: 2)
                                    .frame(width: size * 0.10, height: size * 0.10)
                            }

                            if let piece = board.piece(at: position) {
                                Circle()
                                    .fill(piece.owner == .white ? .white : .black)
                                    .overlay(
                                        Circle()
                                            .stroke(lineWidth: 1)
                                    )
                                    .frame(width: size * 0.08, height: size * 0.08)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .position(point)
                }
            }
        }
    }
}
