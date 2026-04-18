import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var modelReady: Bool = false
    @Published var modelError: String?

    let ai: SiteVoiceAI
    let punchList: PunchListStore

    init(useStub: Bool = true) {
        self.punchList = PunchListStore()
        self.ai = useStub ? StubAIService() : GemmaAIService()
    }

    func bootstrap() {
        Task {
            do {
                try await ai.loadModel()
                modelReady = true
            } catch {
                modelError = error.localizedDescription
            }
        }
    }
}
