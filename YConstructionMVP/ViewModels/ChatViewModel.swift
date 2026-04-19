import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var lastInputSummary = ""
    @Published var latestReply = ""
    @Published var lastRuntimeText: String?
    @Published var statusText = "Ready on iPhone."
    @Published var isLoading = false
    @Published var isListening = false
    @Published var permissionMessage: String?
    @Published var modelStatusText = "Checking local model..."
    @Published var localSearchStatusText = "Checking local search..."
    @Published var modelSetupMessage: String?
    @Published var isModelReady = false
    @Published var isImportingModel = false
    @Published var isPreparingModel = false
    @Published var isCameraContextEnabled = false
    @Published var isCapturingPhoto = false
    @Published var stagedPhotoStatusText = "No site photo staged."
    @Published var backendStatusText = "Checking Supabase contract..."
    @Published var backendSyncText = "No queued captures yet."
    @Published var backendErrorMessage: String?
    @Published var pendingSyncCount = 0

    private enum CaptureTurnState {
        case idle
        case waitingForSpeech(startedAt: Date)
        case speechDetected(startedAt: Date, lastSpeechAt: Date)
        case trailingSilence(startedAt: Date, lastSpeechAt: Date, silenceBeganAt: Date)

        var hasDetectedSpeech: Bool {
            switch self {
            case .speechDetected, .trailingSilence:
                return true
            case .idle, .waitingForSpeech:
                return false
            }
        }
    }

    private enum StagedPhotoSession: Sendable {
        case awaitingIntent(createdAt: Date, transcriptSnippets: [String])
        case report(PhotoReportState)
        case query(PhotoQueryState)

        var createdAt: Date {
            switch self {
            case .awaitingIntent(let createdAt, _):
                return createdAt
            case .report(let state):
                return state.createdAt
            case .query(let state):
                return state.createdAt
            }
        }

        var transcriptHistory: [String] {
            switch self {
            case .awaitingIntent(_, let transcriptSnippets):
                return transcriptSnippets
            case .report(let state):
                return state.transcriptSnippets
            case .query(let state):
                return state.transcriptSnippets
            }
        }
    }

    private let aiService: any AIService
    private let defectSyncService: DefectSyncService
    private let localRAGService: LocalRAGService
    private let photoTurnCoordinator: PhotoTurnCoordinator
    private let synthesizer = AVSpeechSynthesizer()
    private let modelStore = LocalModelStore.shared

    private let monitorInterval: TimeInterval = 0.15
    private let retainedMessageLimit = 6
    private let speechStartThreshold: Float = 0.03
    private let speechContinueThreshold: Float = 0.018
    private let meterSmoothingFactor: Float = 0.25
    private let silenceDuration: TimeInterval = 0.85
    private let maxNoSpeechDuration: TimeInterval = 5.0
    private let maxTurnDuration: TimeInterval = 20.0
    private let minimumUtteranceDuration: TimeInterval = 0.12
    private let minimumCapturedAudioBytes: Int64 = 2_048
    private let modelDisplayName = LocalModelStore.displayName

    private let recorder = WAVRecorder()
    private var silenceTimer: Timer?
    private var capturedDuration: TimeInterval = 0
    private var smoothedLevel: Float = 0
    private var captureTurnState: CaptureTurnState = .idle
    private var cameraSnapshotProvider: (@Sendable () async -> URL?)?
    private var stagedPhotoURL: URL?
    private var stagedPhotoSession: StagedPhotoSession?
    private var cancellables: Set<AnyCancellable> = []

    init(
        aiService: any AIService,
        defectSyncService: DefectSyncService
    ) {
        self.aiService = aiService
        self.defectSyncService = defectSyncService
        let localRAGService = LocalRAGService()
        self.localRAGService = localRAGService
        self.photoTurnCoordinator = PhotoTurnCoordinator(aiService: aiService, ragService: localRAGService)
        bindSyncState()
    }

    convenience init(aiService: any AIService = MockAIService()) {
        self.init(aiService: aiService, defectSyncService: DefectSyncService())
    }

    var hasReply: Bool {
        !latestReply.isEmpty
    }

    var canUseMicrophone: Bool {
        isModelReady && !isPreparingModel && !isLoading && !isImportingModel && !isCapturingPhoto
    }

    var canCapturePhotoNow: Bool {
        isCameraContextEnabled && canCaptureSitePhoto && !isCapturingPhoto && !isListening && !isLoading && stagedPhotoURL == nil
    }

    var canCaptureSitePhoto: Bool {
        true
    }

    var hasStagedPhoto: Bool {
        stagedPhotoURL != nil
    }

    func prepare() async {
        await refreshModelAvailability()
        await defectSyncService.prepare()
        await refreshLocalSearchStatus()
        _ = await requestMicrophonePermissionIfNeeded()
        _ = await requestSpeechRecognitionPermissionIfNeeded()
    }

    func refreshModelAvailability() async {
        do {
            if let installation = try await modelStore.prepareInstalledModel() {
                await prewarmInstalledModel(installation)
            } else {
                isPreparingModel = false
                isModelReady = false
                modelStatusText = "\(modelDisplayName) is not installed on this iPhone."
                modelSetupMessage = LocalModelStore.importInstructions

                if !isListening && !isLoading {
                    statusText = "Import \(modelDisplayName) before asking a question."
                }
            }
        } catch {
            isPreparingModel = false
            isModelReady = false
            modelStatusText = "Could not verify the local model."
            modelSetupMessage = error.localizedDescription

            if !isListening && !isLoading {
                statusText = "Local model setup needs attention."
            }
        }

        await refreshLocalSearchStatus()
    }

    func importModel(from url: URL) async {
        isImportingModel = true
        modelStatusText = "Importing a local model..."
        statusText = "Installing local model..."

        defer {
            isImportingModel = false
        }

        do {
            let importedModel = try await modelStore.importKnownModel(from: url)

            switch importedModel.spec {
            case LocalModelStore.assistantModel:
                await prewarmInstalledModel(importedModel.installation)
            case LocalModelStore.embeddingModel:
                localSearchStatusText = "\(importedModel.spec.displayName) imported for local question search."
                statusText = "\(importedModel.spec.displayName) imported."
                if !isModelReady {
                    modelStatusText = "\(modelDisplayName) is still needed for answers."
                }
            default:
                statusText = "\(importedModel.spec.displayName) imported."
            }

            await refreshLocalSearchStatus()
        } catch {
            isPreparingModel = false
            modelStatusText = "Model import failed."
            modelSetupMessage = error.localizedDescription
            statusText = "Local model import failed."
        }
    }

    func setCameraSnapshotProvider(_ provider: (@Sendable () async -> URL?)?) {
        cameraSnapshotProvider = provider
    }

    func syncNow() {
        Task {
            await defectSyncService.syncNow()
            await refreshLocalSearchStatus()
        }
    }

    func captureSitePhoto() {
        guard canCapturePhotoNow else { return }

        Task {
            await stageCurrentCameraPhoto()
        }
    }

    func toggleListening() {
        guard isModelReady else {
            statusText = isPreparingModel ? "\(modelDisplayName) is still loading locally." : "Import \(modelDisplayName) first."
            return
        }

        if isListening {
            statusText = "Sending now..."
            finalizeCaptureAndSend(forceSend: true)
        } else {
            Task {
                await beginListening()
            }
        }
    }

    func replayLatestReply() {
        guard !latestReply.isEmpty else { return }
        speak(latestReply)
    }

    func clearConversation() {
        cancelListening()
        messages.removeAll()
        lastInputSummary = ""
        latestReply = ""
        lastRuntimeText = nil
        cleanupFile(at: stagedPhotoURL)
        stagedPhotoURL = nil
        stagedPhotoSession = nil
        stagedPhotoStatusText = "No site photo staged."
        statusText = isModelReady ? "Ready on iPhone." : "Import \(modelDisplayName) before asking a question."
        permissionMessage = nil
    }

    func stopListening() {
        cancelListening()
    }

    private func stageCurrentCameraPhoto() async {
        guard isCameraContextEnabled else {
            stagedPhotoStatusText = "Turn on site photo capture before taking a photo."
            return
        }

        isCapturingPhoto = true
        statusText = "Capturing site photo..."

        defer {
            isCapturingPhoto = false
            if !isListening && !isLoading && statusText == "Capturing site photo..." {
                statusText = isModelReady ? "Ready on iPhone." : "Import \(modelDisplayName) before asking a question."
            }
        }

        guard let provider = cameraSnapshotProvider, let imageURL = await provider() else {
            stagedPhotoStatusText = "Could not capture a site photo. The camera can stay optional."
            statusText = "Site photo capture failed."
            return
        }

        do {
            let persistedPhotoURL = try await defectSyncService.persistCapturedPhoto(from: imageURL)
            cleanupFile(at: stagedPhotoURL)
            stagedPhotoURL = persistedPhotoURL
            stagedPhotoSession = .awaitingIntent(createdAt: Date(), transcriptSnippets: [])
            stagedPhotoStatusText = "Photo staged locally. Ask a question about it, or describe a new issue."
            statusText = "Site photo staged."
        } catch {
            stagedPhotoStatusText = "Photo capture succeeded, but it could not be stored locally for sync."
            statusText = "Site photo storage failed."
        }

        cleanupFile(at: imageURL)
    }

    private func prewarmInstalledModel(_ installation: LocalModelInstallation) async {
        let formattedSize = ByteCountFormatter.string(fromByteCount: installation.sizeBytes, countStyle: .file)

        isPreparingModel = true
        isModelReady = false
        modelStatusText = "Prewarming \(modelDisplayName) locally (\(formattedSize))..."
        modelSetupMessage = nil
        statusText = "Loading \(modelDisplayName) on iPhone..."

        defer {
            isPreparingModel = false
        }

        do {
            _ = try await aiService.prewarm()
            isModelReady = true
            modelStatusText = "\(modelDisplayName) ready locally (\(formattedSize), prewarmed)."
            modelSetupMessage = nil

            if !isListening && !isLoading {
                statusText = "Ready on iPhone."
            }
        } catch {
            isModelReady = false
            modelStatusText = "\(modelDisplayName) failed to load locally."
            modelSetupMessage = error.localizedDescription

            if !isListening && !isLoading {
                statusText = "Local model setup needs attention."
            }
        }
    }

    private func beginListening() async {
        permissionMessage = nil

        guard await requestMicrophonePermissionIfNeeded() else {
            return
        }

        guard await requestSpeechRecognitionPermissionIfNeeded() else {
            return
        }

        do {
            try configureAudioSession()
            try recorder.start()
            capturedDuration = 0
            smoothedLevel = 0
            captureTurnState = .waitingForSpeech(startedAt: Date())
            isListening = true
            statusText = "Listening locally..."
            lastInputSummary = ""

            startSilenceMonitor()
        } catch {
            permissionMessage = error.localizedDescription
            statusText = "Could not start local audio capture."
            _ = stopCaptureSession()
        }
    }

    private func cancelListening() {
        _ = stopCaptureSession()
        statusText = "Listening canceled."
    }

    private func startSilenceMonitor() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitorCaptureState()
            }
        }
    }

    private func monitorCaptureState() {
        guard isListening else { return }

        let now = Date()
        let snapshot = recorder.snapshot()
        capturedDuration = snapshot.duration
        smoothedLevel = smoothedLevel == 0
            ? snapshot.level
            : ((meterSmoothingFactor * snapshot.level) + ((1 - meterSmoothingFactor) * smoothedLevel))

        switch captureTurnState {
        case .idle:
            captureTurnState = .waitingForSpeech(startedAt: now)

        case .waitingForSpeech(let startedAt):
            if smoothedLevel >= speechStartThreshold {
                captureTurnState = .speechDetected(startedAt: startedAt, lastSpeechAt: now)
                statusText = "Listening..."
            } else if now.timeIntervalSince(startedAt) >= maxNoSpeechDuration {
                _ = stopCaptureSession()
                statusText = "No speech detected. Try speaking closer to the phone."
            }

        case .speechDetected(let startedAt, let lastSpeechAt):
            if capturedDuration >= maxTurnDuration {
                statusText = "Sending at the turn limit..."
                finalizeCaptureAndSend(forceSend: true)
                return
            }

            if smoothedLevel >= speechContinueThreshold {
                captureTurnState = .speechDetected(startedAt: startedAt, lastSpeechAt: now)
                statusText = "Listening..."
            } else {
                captureTurnState = .trailingSilence(
                    startedAt: startedAt,
                    lastSpeechAt: lastSpeechAt,
                    silenceBeganAt: now
                )
                statusText = "Listening for a pause..."
            }

        case .trailingSilence(let startedAt, _, let silenceBeganAt):
            if capturedDuration >= maxTurnDuration {
                statusText = "Sending at the turn limit..."
                finalizeCaptureAndSend(forceSend: true)
                return
            }

            if smoothedLevel >= speechContinueThreshold {
                captureTurnState = .speechDetected(startedAt: startedAt, lastSpeechAt: now)
                statusText = "Listening..."
            } else if now.timeIntervalSince(silenceBeganAt) >= silenceDuration {
                statusText = "Sending after pause..."
                finalizeCaptureAndSend(forceSend: false)
            }
        }
    }

    private func finalizeCaptureAndSend(forceSend: Bool) {
        let detectedSpeech = captureTurnState.hasDetectedSpeech
        guard let capturedAudio = stopCaptureSession() else {
            statusText = "No audio captured."
            return
        }

        guard forceSend || detectedSpeech else {
            cleanupFile(at: capturedAudio.fileURL)
            statusText = "No speech captured."
            return
        }

        guard isUsableCapturedAudio(capturedAudio) else {
            cleanupFile(at: capturedAudio.fileURL)
            statusText = "Audio was too short. Hold for a moment longer and speak a full phrase."
            return
        }

        Task {
            await sendRecordedTurn(capturedAudio)
        }
    }

    private func sendRecordedTurn(_ capturedAudio: CapturedAudio) async {
        let durationText = String(format: "%.1f", capturedAudio.duration)
        let audioSize = ByteCountFormatter.string(fromByteCount: capturedAudio.fileSizeBytes, countStyle: .file)
        let isStagedPhotoTurn = stagedPhotoURL != nil || stagedPhotoSession != nil
        do {
            statusText = "Transcribing speech..."
            let transcription = try await transcribeCapturedAudio(capturedAudio)
            let capturedAt = Date()
            let cameraSummary = isStagedPhotoTurn
                ? "A staged site photo is attached to this voice workflow."
                : "Sent transcript only."

            lastInputSummary = """
            Captured \(durationText)s of local mic audio (\(audioSize)).
            Heard: "\(abbreviatedTranscript(transcription.text))"
            \(transcriptionSummary(transcription))
            \(cameraSummary)
            """
            appendMessage(Message(text: transcription.text, sender: .user))

            defer {
                cleanupFile(at: capturedAudio.fileURL)
                isLoading = false
            }

            if isStagedPhotoTurn {
                try await handleStagedPhotoTurn(
                    transcript: transcription,
                    capturedAt: capturedAt
                )
            } else {
                try await handleGeneralAssistantTurn(
                    transcript: transcription,
                    capturedAudio: capturedAudio
                )
            }
        } catch let error as SpeechRecognitionError {
            latestReply = ""
            lastRuntimeText = nil
            statusText = speechRecognitionStatusText(for: error)
            cleanupFile(at: capturedAudio.fileURL)
        } catch {
            lastRuntimeText = nil

            if isStagedPhotoTurn {
                let recoveryText = "I could not finish that staged-photo turn. The photo is still staged. Say whether this is a new report or a question about an existing issue."
                latestReply = recoveryText
                appendMessage(Message(text: recoveryText, sender: .assistant))
                stagedPhotoStatusText = "Photo is still staged locally."
                statusText = "Staged photo turn needs clarification."
                speak(recoveryText)
            } else {
                latestReply = error.localizedDescription
                appendMessage(Message(text: error.localizedDescription, sender: .assistant))
                statusText = "Voice turn failed."
            }

            cleanupFile(at: capturedAudio.fileURL)
        }
    }

    private func handleGeneralAssistantTurn(
        transcript: SpeechTranscriptionResult,
        capturedAudio: CapturedAudio
    ) async throws {
        isLoading = true
        statusText = "Sending to local \(modelDisplayName)..."

        let request = AIRequest(
            prompt: transcript.text,
            imagePaths: [],
            audioPaths: LocalModelStore.supportsDirectAudioInput ? [capturedAudio.fileURL.path] : [],
            maxTokens: 128
        )
        let response = try await aiService.send(
            request: request,
            conversation: messages
        )

        appendMessage(Message(text: response.text, sender: .assistant))
        latestReply = response.text
        lastRuntimeText = formatRuntimeStats(response.runtimeStats)
        statusText = response.runtimeStats?.cloudHandoff == true
            ? "Response arrived through cloud handoff."
            : "Local response ready."
        speak(response.text)
    }

    private func handleStagedPhotoTurn(
        transcript: SpeechTranscriptionResult,
        capturedAt: Date
    ) async throws {
        let currentSession = stagedPhotoSession ?? .awaitingIntent(createdAt: capturedAt, transcriptSnippets: [])

        switch currentSession {
        case .awaitingIntent(let createdAt, let transcriptSnippets):
            let history = transcriptSnippets + [transcript.text]
            let decision = await photoTurnCoordinator.classifyIntent(transcriptHistory: history)

            switch decision.intent {
            case .report:
                isLoading = true
                statusText = "Reviewing the new report..."
                stagedPhotoStatusText = "Photo staged for a new report."
                let existingState = PhotoReportState(
                    createdAt: createdAt,
                    transcriptSnippets: Array(history.dropLast()),
                    fields: PhotoReportFields(),
                    explicitlyUnknownFields: [],
                    lastBlockingFields: [],
                    repeatedFollowUpCount: 0
                )
                let outcome = try await photoTurnCoordinator.processReportTurn(
                    existingState: existingState,
                    newTranscript: transcript.text,
                    createdAt: createdAt
                )
                lastRuntimeText = formatRuntimeStats(outcome.runtimeStats)
                await applyReportTurnOutcome(outcome)

            case .query:
                isLoading = true
                statusText = "Preparing the local question search..."
                stagedPhotoStatusText = "Photo staged for a local question."
                let existingState = PhotoQueryState(
                    createdAt: createdAt,
                    transcriptSnippets: Array(history.dropLast()),
                    questionSummary: nil,
                    storey: nil,
                    space: nil,
                    orientation: nil,
                    elementType: nil,
                    timeframeHint: nil,
                    ambiguityNote: nil
                )
                let outcome = try await photoTurnCoordinator.processQueryTurn(
                    existingState: existingState,
                    newTranscript: transcript.text,
                    createdAt: createdAt
                )
                lastRuntimeText = formatRuntimeStats(outcome.runtimeStats)
                await applyQueryTurnOutcome(outcome)

            case .unclear:
                stagedPhotoSession = .awaitingIntent(createdAt: createdAt, transcriptSnippets: history)
                let assistantText = decision.assistantMessage
                appendMessage(Message(text: assistantText, sender: .assistant))
                latestReply = assistantText
                stagedPhotoStatusText = "Photo staged locally. I still need to know whether this is a new report or a question."
                statusText = "Waiting for report-versus-question clarification."
                speak(assistantText)
                lastInputSummary = "Photo staged locally. Waiting to learn whether the next workflow is a report or a question."
            }

        case .report(let state):
            if let pivotIntent = await photoTurnCoordinator.pivotIntent(
                for: transcript.text,
                currentIntent: .report
            ), pivotIntent == .query {
                isLoading = true
                statusText = "Switching to a local question search..."
                stagedPhotoStatusText = "Photo staged for a local question."
                let outcome = try await photoTurnCoordinator.processQueryTurn(
                    existingState: makeQueryPivotState(from: state),
                    newTranscript: transcript.text,
                    createdAt: state.createdAt
                )
                lastRuntimeText = formatRuntimeStats(outcome.runtimeStats)
                await applyQueryTurnOutcome(outcome)
                return
            }

            isLoading = true
            statusText = "Reviewing the new report..."
            let outcome = try await photoTurnCoordinator.processReportTurn(
                existingState: state,
                newTranscript: transcript.text,
                createdAt: state.createdAt
            )
            lastRuntimeText = formatRuntimeStats(outcome.runtimeStats)
            await applyReportTurnOutcome(outcome)

        case .query(let state):
            if let pivotIntent = await photoTurnCoordinator.pivotIntent(
                for: transcript.text,
                currentIntent: .query
            ), pivotIntent == .report {
                isLoading = true
                statusText = "Switching to a new report..."
                stagedPhotoStatusText = "Photo staged for a new report."
                let outcome = try await photoTurnCoordinator.processReportTurn(
                    existingState: makeReportPivotState(from: state),
                    newTranscript: transcript.text,
                    createdAt: state.createdAt
                )
                lastRuntimeText = formatRuntimeStats(outcome.runtimeStats)
                await applyReportTurnOutcome(outcome)
                return
            }

            isLoading = true
            statusText = "Preparing the local question search..."
            let outcome = try await photoTurnCoordinator.processQueryTurn(
                existingState: state,
                newTranscript: transcript.text,
                createdAt: state.createdAt
            )
            lastRuntimeText = formatRuntimeStats(outcome.runtimeStats)
            await applyQueryTurnOutcome(outcome)
        }
    }

    private func applyReportTurnOutcome(_ outcome: PhotoReportTurnOutcome) async {
        if outcome.readyToUpload {
            guard let stagedPhotoURL else {
                stagedPhotoSession = .report(outcome.state)
                let assistantText = "The staged photo is missing from local storage. Take the photo again and then describe the issue."
                appendMessage(Message(text: assistantText, sender: .assistant))
                latestReply = assistantText
                stagedPhotoStatusText = "The staged photo needs to be recaptured."
                statusText = "Staged photo missing."
                speak(assistantText)
                return
            }

            statusText = "Saving the report locally..."

            do {
                let syncResult = try await defectSyncService.enqueue(
                    draft: DefectSyncDraft(
                        transcriptOriginal: outcome.state.combinedTranscript,
                        transcriptEnglish: outcome.state.combinedTranscript,
                        photoLocalURL: stagedPhotoURL,
                        timestamp: outcome.state.createdAt,
                        reporter: ProjectBackendConfig.reporterID,
                        metadataOverride: outcome.state.fields.asSyncMetadata()
                    )
                )

                let assistantText: String
                if syncResult.wasUploaded && syncResult.photoUploaded {
                    assistantText = "Photo uploaded and done!"
                    statusText = "Photo uploaded and done!"
                } else {
                    assistantText = "Issue saved locally with its photo. It will upload automatically on Wi-Fi or when you tap Sync Now."
                    statusText = "Issue queued locally for Supabase."
                }

                appendMessage(Message(text: assistantText, sender: .assistant))
                latestReply = assistantText
                speak(assistantText)
                lastInputSummary = """
                Staged photo + voice note were mapped to Supabase issue fields.
                \(outcome.state.fields.compactSummaryLines().joined(separator: "\n"))
                """

                clearStagedPhotoSession(deleteLocalPhoto: false)
                await refreshLocalSearchStatus()
            } catch {
                stagedPhotoSession = .report(outcome.state)
                let assistantText = "I mapped the report, but saving it for Supabase failed. The staged photo is still here, and you can try again. \(error.localizedDescription)"
                appendMessage(Message(text: assistantText, sender: .assistant))
                latestReply = assistantText
                stagedPhotoStatusText = "Photo staged for a new report. Saving needs attention."
                statusText = "Report save failed."
                speak(assistantText)
            }
        } else {
            stagedPhotoSession = .report(outcome.state)
            stagedPhotoStatusText = "Photo staged for a new report. Answer the follow-up to finish tagging it."
            statusText = "Waiting for one more report detail before upload."
            appendMessage(Message(text: outcome.assistantMessage, sender: .assistant))
            latestReply = outcome.assistantMessage
            speak(outcome.assistantMessage)
            lastInputSummary = """
            Photo report is still being tagged locally.
            \(outcome.state.fields.compactSummaryLines().joined(separator: "\n"))
            """
        }
    }

    private func applyQueryTurnOutcome(_ outcome: PhotoQueryTurnOutcome) async {
        if outcome.readyToSearch {
            stagedPhotoSession = .query(outcome.state)
            statusText = "Searching synced reports on this iPhone..."
            do {
                let cachedRecords = await defectSyncService.cachedProjectChangesForRetrieval()
                let answerOutcome = try await photoTurnCoordinator.answerQuery(
                    state: outcome.state,
                    cachedRecords: cachedRecords
                )
                appendMessage(Message(text: answerOutcome.assistantMessage, sender: .assistant))
                latestReply = answerOutcome.assistantMessage
                lastRuntimeText = formatRuntimeStats(answerOutcome.runtimeStats)
                statusText = "Local answer ready."
                lastInputSummary = answerOutcome.summaryText
                speak(answerOutcome.assistantMessage)
                clearStagedPhotoSession(deleteLocalPhoto: true)
                await refreshLocalSearchStatus()
            } catch {
                stagedPhotoSession = .query(outcome.state)
                appendMessage(Message(text: error.localizedDescription, sender: .assistant))
                latestReply = error.localizedDescription
                statusText = "Local question search needs attention."
                lastInputSummary = "Local question search was not ready yet."
                localSearchStatusText = error.localizedDescription
                speak(error.localizedDescription)
            }
        } else {
            stagedPhotoSession = .query(outcome.state)
            stagedPhotoStatusText = "Photo staged for a local question. Answer the follow-up so I can search synced history."
            statusText = "Waiting for one more question detail."
            appendMessage(Message(text: outcome.assistantMessage, sender: .assistant))
            latestReply = outcome.assistantMessage
            speak(outcome.assistantMessage)
            lastInputSummary = """
            Local question search is gathering context from the staged photo workflow.
            \(outcome.state.compactSummaryLines().joined(separator: "\n"))
            """
        }
    }

    private func makeQueryPivotState(from reportState: PhotoReportState) -> PhotoQueryState {
        PhotoQueryState(
            createdAt: reportState.createdAt,
            transcriptSnippets: Array(reportState.transcriptSnippets.suffix(2)),
            questionSummary: nil,
            storey: PhotoReportFields.normalizedText(reportState.fields.storey),
            space: PhotoReportFields.normalizedText(reportState.fields.space),
            orientation: PhotoReportFields.normalizedOrientation(reportState.fields.orientation),
            elementType: PhotoReportFields.normalizedText(reportState.fields.elementType),
            timeframeHint: nil,
            ambiguityNote: nil
        )
    }

    private func makeReportPivotState(from queryState: PhotoQueryState) -> PhotoReportState {
        PhotoReportState(
            createdAt: queryState.createdAt,
            transcriptSnippets: Array(queryState.transcriptSnippets.suffix(2)),
            fields: PhotoReportFields(
                defectType: nil,
                severity: nil,
                storey: PhotoReportFields.normalizedText(queryState.storey),
                space: PhotoReportFields.normalizedText(queryState.space),
                orientation: PhotoReportFields.normalizedOrientation(queryState.orientation),
                elementType: PhotoReportFields.normalizedText(queryState.elementType),
                guid: nil,
                aiSafetyNotes: nil
            ),
            explicitlyUnknownFields: [],
            lastBlockingFields: [],
            repeatedFollowUpCount: 0
        )
    }

    private func clearStagedPhotoSession(deleteLocalPhoto: Bool) {
        if deleteLocalPhoto {
            cleanupFile(at: stagedPhotoURL)
        }
        stagedPhotoSession = nil
        stagedPhotoURL = nil
        stagedPhotoStatusText = "No site photo staged."
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.prefersAssistiveTechnologySettings = true

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    private func stopCaptureSession() -> CapturedAudio? {
        isListening = false

        silenceTimer?.invalidate()
        silenceTimer = nil

        let capturedAudio = recorder.stop()
        captureTurnState = .idle
        smoothedLevel = 0
        capturedDuration = 0

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore teardown errors so the user can start another turn immediately.
        }

        return capturedAudio
    }

    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard micGranted else {
            permissionMessage = "Allow Microphone access in iPhone Settings so \(modelDisplayName) can receive voice turns."
            statusText = "Microphone permission needed."
            return false
        }

        return true
    }

    private func requestSpeechRecognitionPermissionIfNeeded() async -> Bool {
        let status = await AppleSpeechTranscriber.requestAuthorization()

        switch status {
        case .authorized:
            return true
        case .denied:
            permissionMessage = "Allow Speech Recognition in iPhone Settings so recorded turns can be transcribed."
        case .restricted:
            permissionMessage = "Speech Recognition is restricted on this iPhone."
        case .notDetermined:
            permissionMessage = "Speech Recognition permission was not granted."
        @unknown default:
            permissionMessage = "Speech Recognition is unavailable right now."
        }

        statusText = "Speech recognition permission needed."
        return false
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        synthesizer.stopSpeaking(at: .immediate)

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try session.setPreferredInput(nil)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            if let availableInputs = session.availableInputs, availableInputs.isEmpty {
                throw AudioCaptureSetupError.noInputRoute
            }
        } catch let setupError as AudioCaptureSetupError {
            throw setupError
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSOSStatusErrorDomain, nsError.code == -50 {
                throw AudioCaptureSetupError.sessionConfigurationFailed(
                    "An unsupported audio parameter was requested. This build now falls back to the iPhone's default mic format."
                )
            }

            throw AudioCaptureSetupError.sessionConfigurationFailed(error.localizedDescription)
        }
    }

    private func formatRuntimeStats(_ runtimeStats: AIRuntimeStats?) -> String? {
        guard let runtimeStats else { return nil }

        var parts: [String] = []

        if let ramUsageMB = runtimeStats.ramUsageMB {
            parts.append(String(format: "RAM %.0f MB", ramUsageMB))
        }

        if let timeToFirstTokenMS = runtimeStats.timeToFirstTokenMS {
            parts.append(String(format: "first token %.2fs", timeToFirstTokenMS / 1_000))
        }

        if let totalTimeMS = runtimeStats.totalTimeMS {
            parts.append(String(format: "total %.2fs", totalTimeMS / 1_000))
        }

        if let decodeTokensPerSecond = runtimeStats.decodeTokensPerSecond {
            parts.append(String(format: "decode %.1f tok/s", decodeTokensPerSecond))
        }

        parts.append(runtimeStats.cloudHandoff ? "cloud handoff" : "local only")
        return parts.joined(separator: " • ")
    }

    private func cleanupFile(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func isUsableCapturedAudio(_ capturedAudio: CapturedAudio) -> Bool {
        capturedAudio.duration >= minimumUtteranceDuration || capturedAudio.fileSizeBytes >= minimumCapturedAudioBytes
    }

    private func speechRecognitionStatusText(for error: SpeechRecognitionError) -> String {
        switch error {
        case .unavailableRecognizer:
            return "Speech recognition is unavailable right now."
        case .noSpeechRecognized:
            return "I did not catch enough speech. Try speaking a little longer."
        }
    }

    private func transcribeCapturedAudio(_ capturedAudio: CapturedAudio) async throws -> SpeechTranscriptionResult {
        try await AppleSpeechTranscriber.transcribeFile(at: capturedAudio.fileURL)
    }

    private func abbreviatedTranscript(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 120

        guard collapsed.count > limit else {
            return collapsed
        }

        return String(collapsed.prefix(limit)) + "..."
    }

    private func transcriptionSummary(_ transcription: SpeechTranscriptionResult) -> String {
        transcription.usedOnDeviceRecognition
            ? "Transcript came from on-device Apple Speech."
            : "Transcript came from Apple Speech fallback."
    }

    private func refreshLocalSearchStatus() async {
        let cachedRecords = await defectSyncService.cachedProjectChangesForRetrieval()
        localSearchStatusText = await localRAGService.statusText(for: cachedRecords)
    }

    private func appendMessage(_ message: Message) {
        messages.append(message)

        let overflow = messages.count - retainedMessageLimit
        if overflow > 0 {
            messages.removeFirst(overflow)
        }
    }

    private func bindSyncState() {
        defectSyncService.$backendStatusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.backendStatusText = $0 }
            .store(in: &cancellables)

        defectSyncService.$syncStatusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.backendSyncText = $0 }
            .store(in: &cancellables)

        defectSyncService.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.backendErrorMessage = $0 }
            .store(in: &cancellables)

        defectSyncService.$pendingCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.pendingSyncCount = $0 }
            .store(in: &cancellables)
    }
}

private struct CapturedAudio {
    let fileURL: URL
    let duration: TimeInterval
    let fileSizeBytes: Int64
}

private struct AudioMeterSnapshot {
    let level: Float
    let duration: TimeInterval
}

private enum RecorderError: LocalizedError {
    case startFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            return "The iPhone could not start recording local audio."
        }
    }
}

private enum AudioCaptureSetupError: LocalizedError {
    case noInputRoute
    case sessionConfigurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputRoute:
            return "No microphone input route is available right now. Disconnect other audio devices and try again."
        case .sessionConfigurationFailed(let details):
            return "The iPhone audio session could not start for local capture. \(details)"
        }
    }
}

private struct SpeechTranscriptionResult {
    let text: String
    let usedOnDeviceRecognition: Bool
}

private enum SpeechRecognitionError: LocalizedError {
    case unavailableRecognizer
    case noSpeechRecognized

    var errorDescription: String? {
        switch self {
        case .unavailableRecognizer:
            return "Speech recognition is unavailable on this iPhone right now."
        case .noSpeechRecognized:
            return "No spoken words were recognized from the recorded turn."
        }
    }
}

private enum AppleSpeechTranscriber {
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func transcribeFile(at fileURL: URL) async throws -> SpeechTranscriptionResult {
        let locale = Locale(identifier: "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechRecognitionError.unavailableRecognizer
        }

        guard recognizer.isAvailable else {
            throw SpeechRecognitionError.unavailableRecognizer
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        let useOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = useOnDeviceRecognition

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var recognitionTask: SFSpeechRecognitionTask?

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }

                if let error {
                    didResume = true
                    recognitionTask?.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !transcript.isEmpty else {
                    didResume = true
                    recognitionTask?.cancel()
                    continuation.resume(throwing: SpeechRecognitionError.noSpeechRecognized)
                    return
                }

                didResume = true
                continuation.resume(
                    returning: SpeechTranscriptionResult(
                        text: transcript,
                        usedOnDeviceRecognition: useOnDeviceRecognition
                    )
                )
            }
        }
    }
}

private final class WAVRecorder {
    private let preferredSampleRate: Double = 16_000

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() throws {
        cleanupCurrentFile()

        let fileURL = try temporaryAudioFileURL()
        let recorder = try makeRecorder(url: fileURL)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecorderError.startFailed
        }

        self.recorder = recorder
        self.fileURL = fileURL
    }

    func stop() -> CapturedAudio? {
        guard let recorder, let fileURL else { return nil }

        let fallbackDuration = recorder.currentTime
        recorder.stop()

        let duration = measuredDuration(for: fileURL, fallback: fallbackDuration)
        self.recorder = nil
        self.fileURL = nil

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard fileSize > 44 else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        return CapturedAudio(fileURL: fileURL, duration: duration, fileSizeBytes: fileSize)
    }

    func snapshot() -> AudioMeterSnapshot {
        guard let recorder else {
            return AudioMeterSnapshot(level: 0, duration: 0)
        }

        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        let level = averagePower.isFinite ? pow(10, averagePower / 20) : 0
        return AudioMeterSnapshot(level: level, duration: recorder.currentTime)
    }

    private func measuredDuration(for fileURL: URL, fallback: TimeInterval) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let sampleRate = audioFile.fileFormat.sampleRate
            guard sampleRate > 0 else {
                return fallback
            }
            return Double(audioFile.length) / sampleRate
        } catch {
            return fallback
        }
    }

    private func makeRecorder(url: URL) throws -> AVAudioRecorder {
        do {
            return try AVAudioRecorder(url: url, settings: settings(sampleRate: preferredSampleRate))
        } catch {
            let hardwareSampleRate = AVAudioSession.sharedInstance().sampleRate
            let fallbackSampleRate = hardwareSampleRate > 0 ? hardwareSampleRate : 48_000

            guard abs(fallbackSampleRate - preferredSampleRate) > 1 else {
                throw error
            }

            return try AVAudioRecorder(url: url, settings: settings(sampleRate: fallbackSampleRate))
        }
    }

    private func settings(sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private func temporaryAudioFileURL() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CapturedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
    }

    private func cleanupCurrentFile() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        recorder = nil
        fileURL = nil
    }
}
