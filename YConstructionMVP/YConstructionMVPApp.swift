import SwiftUI

@main
struct YConstructionMVPApp: App {
    private let aiService: any AIService = CactusAIService()
    @StateObject private var defectSyncService = DefectSyncService()

    var body: some Scene {
        WindowGroup {
            ChatView(viewModel: ChatViewModel(aiService: aiService, defectSyncService: defectSyncService))
        }
    }
}
