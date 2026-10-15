import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isMine: Bool
}

struct ChatView: View {
    let messages: [ChatMessage]
    @Binding var text: String
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chat")
                .font(.headline)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { message in
                            HStack {
                                if message.isMine {
                                    Spacer(minLength: 40)
                                }

                                Text(message.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                if !message.isMine {
                                    Spacer(minLength: 40)
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180, maxHeight: 260)
                .onChange(of: messages.count) {
                    guard let lastMessage = messages.last else { return }
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }

            HStack(spacing: 8) {
                TextField("Mensagem", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canSend { onSend() } }

                Button("Enviar") {
                    onSend()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
        }
    }
}
