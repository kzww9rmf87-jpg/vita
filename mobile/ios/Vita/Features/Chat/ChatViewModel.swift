import Foundation
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isTyping = false

    private var conversationId: String?

    func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text, contextCategories: [])
        messages.append(userMessage)
        inputText = ""
        isTyping = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { await sendToAPI(text) }
    }

    private func sendToAPI(_ text: String) async {
        defer { isTyping = false }

        do {
            let body = ChatRequestBody(
                message: text,
                conversationId: conversationId
            )
            let response: ChatResponseBody = try await APIClient.shared.post("/chat", body: body)
            conversationId = response.conversationId

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.response,
                contextCategories: response.contextCategories ?? []
            )
            messages.append(assistantMessage)
        } catch {
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "Je n'ai pas pu analyser tes données pour le moment. Réessaie dans quelques secondes.",
                contextCategories: []
            )
            messages.append(errorMessage)
        }
    }

    func clearConversation() {
        messages = []
        conversationId = nil
    }
}

// MARK: — Modèles

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()
    // Catégories générales utilisées par VITA (jamais de contenu brut)
    let contextCategories: [String]
}

enum MessageRole {
    case user, assistant
}

struct ChatRequestBody: Encodable {
    let message: String
    let conversationId: String?
}

struct ChatResponseBody: Decodable {
    let conversationId: String
    let response: String
    let tokensUsed: Int?
    let contextCategories: [String]?
}
