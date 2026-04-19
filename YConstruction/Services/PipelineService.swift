import Foundation

@MainActor
final class PipelineService {
    init(viewModel: MainViewModel) {}
    func toggleRecording() async {}
    func stopRecording() async {}
    func handleCaptured(url: URL) async {}
    func cancelCamera() async {}
    func confirmPick(element: ElementIndex.Element) async {}
    func saveWithoutResolver() async {}
    func cancelResolver() async {}
}
