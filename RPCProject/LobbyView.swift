import SwiftUI

struct LobbyView: View {
    @StateObject private var viewModel = LobbyViewModel()

    var body: some View {
        Group {
            if viewModel.isShowingGameScreen {
                GameView(viewModel: viewModel)
            } else {
                lobbyContent
            }
        }
    }

    private var lobbyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lobby")
                        .font(.title)

                    Text(viewModel.matchStatusText)
                    Text("Papel: \(viewModel.roleText)")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Conexão")
                        .font(.headline)

                    Button(viewModel.serverButtonTitle) {
                        viewModel.toggleServer()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(viewModel.isServerButtonDisabled)

                    if !viewModel.isServerRunning {
                        TextField("Endereço do servidor", text: $viewModel.host)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(viewModel.isClientConnected || viewModel.isConnectingClient)

                        Button(viewModel.clientButtonTitle) {
                            viewModel.toggleClient()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.isClientButtonDisabled)

                        Text(viewModel.clientStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if viewModel.clientStatus == "Erro na conexão" {
                            Text("Inicie o servidor no outro aparelho e confira o endereço IP e a porta 8080.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Partida")
                        .font(.headline)

                    Text(viewModel.matchStatusDetail)
                        .foregroundStyle(.secondary)

                    Button(viewModel.readyButtonTitle) {
                        viewModel.markReady()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isReadyButtonDisabled)
                }

                ChatView(
                    messages: viewModel.chatMessages,
                    text: $viewModel.message,
                    canSend: viewModel.canSendChatMessage,
                    onSend: viewModel.sendChatMessage
                )

                Spacer(minLength: 0)
            }
            .padding()
        }
    }
}
