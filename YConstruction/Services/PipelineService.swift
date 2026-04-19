import Foundation
import SwiftUI

enum PipelineError: Error, LocalizedError {
    case resolverNotLoaded
    case noExtraction
    case cancelled

    var errorDescription: String? {
        switch self {
        case .resolverNotLoaded: return "Resolver index not loaded"
        case .noExtraction: return "Could not extract defect fields from the transcript"
        case .cancelled: return "Cancelled"
        }
    }
}

@MainActor
final class PipelineService {
    weak var viewModel: MainViewModel?

    private let stt: STTService
    private let gemma: GemmaService
    private let database: DatabaseService
    private let resolver: DefectResolverService
    private let bcfEmitter: BCFEmitterService
    private let store: DefectStore
    private let camera: CameraService

    private var currentReport: VoiceReport?
    private var pendingPhotoRequest: PhotoRequest?

    init(viewModel: MainViewModel,
         stt: STTService = .shared,
         gemma: GemmaService = .shared,
         database: DatabaseService = .shared) {
        self.viewModel = viewModel
        self.stt = stt
        self.gemma = gemma
        self.database = database
        self.resolver = viewModel.resolver
        self.bcfEmitter = viewModel.bcfEmitter
        self.store = viewModel.store
        self.camera = viewModel.camera
    }

    // MARK: - Record

    func toggleRecording() async {
        guard let vm = viewModel else { return }
        switch vm.recorderState {
        case .idle:
            await startRecording()
        case .listening:
            await stopRecording()
        default:
            return
        }
    }

    func startRecording() async {
        guard let vm = viewModel else { return }
        vm.liveTranscript = ""
        vm.recorderState = .listening
        do {
            let partials = try await stt.startStreaming()
            for await partial in partials {
                vm.liveTranscript = partial.text
            }
        } catch {
            vm.recorderState = .idle
            vm.loadError = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard let vm = viewModel else { return }
        vm.recorderState = .processing("Transcribing…")
        do {
            let final = try await stt.stopStreaming()
            await handleFinalTranscript(final)
        } catch {
            vm.recorderState = .idle
            vm.loadError = error.localizedDescription
        }
    }

    func runDemoAudioFallback(wavURL: URL, reporter: String) async {
        guard let vm = viewModel else { return }
        vm.recorderState = .processing("Transcribing demo audio…")
        do {
            let whisper = try await CactusService.shared.loadWhisper()
            let json = try cactusTranscribe(whisper, wavURL.path, nil, nil, nil, nil)
            let result = parseTranscribeJSON(json)
            await handleFinalTranscript(STTFinalResult(text: result.text, language: result.language))
        } catch {
            vm.recorderState = .idle
            vm.loadError = error.localizedDescription
        }
    }

    // MARK: - Turn 1 (audio → extract)

    private func handleFinalTranscript(_ final: STTFinalResult) async {
        guard let vm = viewModel else { return }
        vm.recorderState = .processing("Analyzing…")

        do {
            let audio = try await gemma.audioTurn(
                transcriptOriginal: final.text,
                languageHint: final.language
            )

            guard let extraction = audio.extraction else {
                vm.recorderState = .idle
                vm.loadError = "Model did not extract structured fields."
                return
            }

            var report = VoiceReport(
                transcriptOriginal: final.text,
                transcriptEnglish: audio.transcriptEnglish,
                storey: extraction.storey,
                space: extraction.space,
                elementType: extraction.elementType,
                orientation: extraction.orientation,
                defectType: extraction.defectType,
                severity: Severity(rawValue: extraction.severity.lowercased()) ?? .medium,
                aiSafetyNotes: nil,
                photoPath: nil,
                reporter: AppConfig.reporterId,
                timestamp: Date()
            )

            if let photoReq = audio.photoRequest {
                currentReport = report
                pendingPhotoRequest = photoReq
                vm.recorderState = .camera(reason: photoReq.reason)
            } else {
                report.aiSafetyNotes = nil
                _ = await finishAndInsert(report: report)
            }
        } catch {
            vm.recorderState = .idle
            vm.loadError = error.localizedDescription
        }
    }

    // MARK: - Camera flow

    func handleCaptured(url: URL) async {
        guard let vm = viewModel, var report = currentReport else {
            viewModel?.recorderState = .idle
            return
        }

        vm.recorderState = .processing("Analyzing photo…")
        report.photoPath = url.path

        do {
            let english = report.transcriptEnglish ?? report.transcriptOriginal
            let context = "Worker said: \(english). Assess the site photo."
            let vision = try await gemma.visionTurn(photoPath: url.path, context: context)

            if let analysis = vision.analysis {
                report.aiSafetyNotes = analysis.safetyNotes
                if let sev = Severity(rawValue: analysis.severityAssessment.lowercased()) {
                    report.severity = sev
                }
            }

            _ = await finishAndInsert(report: report)
        } catch {
            vm.recorderState = .idle
            vm.loadError = error.localizedDescription
        }
    }

    func cancelCamera() async {
        guard let vm = viewModel else { return }
        if var report = currentReport {
            report.photoPath = nil
            _ = await finishAndInsert(report: report)
        } else {
            vm.recorderState = .idle
        }
        pendingPhotoRequest = nil
    }

    // MARK: - Finish

    @discardableResult
    func finishAndInsert(report: VoiceReport) async -> ProcessResult? {
        guard let vm = viewModel else { return nil }

        let query = ElementQuery(
            storey: report.storey,
            space: report.space,
            elementType: report.elementType,
            orientation: report.orientation
        )

        let result = resolver.resolve(query)
        switch result {
        case .match(let resolved):
            return await insert(report: report, element: resolved.element)
        case .ambiguous(let candidates):
            vm.resolverCandidates = candidates
            vm.resolverEnglishTranscript = report.transcriptEnglish ?? report.transcriptOriginal
            vm.showingResolverPicker = true
            vm.recorderState = .idle
            currentReport = report
            return nil
        case .notFound:
            vm.resolverCandidates = []
            vm.resolverEnglishTranscript = report.transcriptEnglish ?? report.transcriptOriginal
            vm.showingResolverPicker = true
            vm.recorderState = .idle
            currentReport = report
            return nil
        }
    }

    // MARK: - Picker handlers

    func confirmPick(element: ElementIndex.Element) async {
        guard let report = currentReport else { return }
        _ = await insert(report: report, element: element)
        currentReport = nil
    }

    func saveWithoutResolver() async {
        guard var report = currentReport else { return }
        report.aiSafetyNotes = (report.aiSafetyNotes ?? "") + "\n(No matching element found in model.)"
        _ = await insertUnresolved(report: report)
        currentReport = nil
    }

    func cancelResolver() async {
        currentReport = nil
        viewModel?.recorderState = .idle
    }

    // MARK: - Insertion

    private func insert(report: VoiceReport, element: ElementIndex.Element) async -> ProcessResult? {
        guard let vm = viewModel else { return nil }
        let defectId = UUID().uuidString
        var defect = Defect(
            id: defectId,
            projectId: store.projectId,
            guid: element.guid,
            storey: element.storey ?? report.storey,
            space: element.space ?? report.space,
            elementType: element.elementType,
            orientation: element.orientation ?? report.orientation,
            centroidX: element.centroid[0],
            centroidY: element.centroid[1],
            centroidZ: element.centroid[2],
            bboxMinX: element.bbox[0][0],
            bboxMinY: element.bbox[0][1],
            bboxMinZ: element.bbox[0][2],
            bboxMaxX: element.bbox[1][0],
            bboxMaxY: element.bbox[1][1],
            bboxMaxZ: element.bbox[1][2],
            transcriptOriginal: report.transcriptOriginal,
            transcriptEnglish: report.transcriptEnglish,
            photoPath: report.photoPath,
            photoUrl: nil,
            defectType: report.defectType,
            severity: report.severity,
            aiSafetyNotes: report.aiSafetyNotes,
            reporter: report.reporter,
            timestamp: report.timestamp,
            bcfPath: nil,
            resolved: false,
            synced: false
        )

        do {
            try store.add(defect)

            let bcfUrl = try bcfEmitter.emit(from: defect)
            defect.bcfPath = bcfUrl.path
            try database.update(defect)
            store.refresh()

            vm.recorderState = .idle
            vm.selectedDefect = defect

            return ProcessResult(
                defectId: defect.id,
                resolvedGuid: defect.guid,
                centroid: SIMD3(defect.centroidX, defect.centroidY, defect.centroidZ),
                bboxMin: SIMD3(defect.bboxMinX, defect.bboxMinY, defect.bboxMinZ),
                bboxMax: SIMD3(defect.bboxMaxX, defect.bboxMaxY, defect.bboxMaxZ),
                storey: defect.storey,
                bcfPath: bcfUrl
            )
        } catch {
            vm.recorderState = .idle
            vm.loadError = error.localizedDescription
            return nil
        }
    }

    private func insertUnresolved(report: VoiceReport) async -> ProcessResult? {
        guard let vm = viewModel else { return nil }
        let defectId = UUID().uuidString
        var defect = Defect(
            id: defectId,
            projectId: store.projectId,
            guid: "",
            storey: report.storey,
            space: report.space,
            elementType: report.elementType,
            orientation: report.orientation,
            centroidX: 0, centroidY: 0, centroidZ: 0,
            bboxMinX: 0, bboxMinY: 0, bboxMinZ: 0,
            bboxMaxX: 0, bboxMaxY: 0, bboxMaxZ: 0,
            transcriptOriginal: report.transcriptOriginal,
            transcriptEnglish: report.transcriptEnglish,
            photoPath: report.photoPath,
            photoUrl: nil,
            defectType: report.defectType,
            severity: report.severity,
            aiSafetyNotes: report.aiSafetyNotes,
            reporter: report.reporter,
            timestamp: report.timestamp,
            bcfPath: nil,
            resolved: false,
            synced: false
        )
        do {
            try store.add(defect)
            let bcfUrl = try bcfEmitter.emit(from: defect)
            defect.bcfPath = bcfUrl.path
            try database.update(defect)
            store.refresh()
            vm.recorderState = .idle
            vm.selectedDefect = defect
            return ProcessResult(
                defectId: defect.id,
                resolvedGuid: nil,
                centroid: nil,
                bboxMin: nil,
                bboxMax: nil,
                storey: defect.storey,
                bcfPath: bcfUrl
            )
        } catch {
            vm.recorderState = .idle
            vm.loadError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Helpers

    private func parseTranscribeJSON(_ json: String) -> (text: String, language: String?) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ("", nil)
        }
        return ((obj["text"] as? String) ?? "", obj["language"] as? String)
    }
}
