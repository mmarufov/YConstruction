import SwiftUI

struct DetailSheet: View {
    let defect: Defect
    let onResolve: () -> Void
    let onDismiss: () -> Void

    @ObservedObject private var workerDirectory: WorkerDirectoryService = .shared

    private var severityColor: Color {
        switch defect.severity {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }

    private var reporterWorker: Worker? {
        workerDirectory.worker(forReporter: defect.reporter)
    }

    private var reporterColor: Color {
        let index = reporterWorker?.colorIndex
            ?? WorkerColorPalette.fallbackIndex(for: defect.reporter)
        return WorkerColorPalette.color(for: index)
    }

    private var shortDefectId: String {
        String(defect.id.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(defect.defectType.capitalized)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    SeverityBadge(severity: defect.severity, color: severityColor)
                }

                if !defect.synced {
                    Label("Pending upload", systemImage: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                }

                reporterCard

                if let photoPath = defect.photoPath {
                    DefectPhotoSection(photoPath: photoPath)
                }

                if let original = defect.transcriptOriginal, !original.isEmpty {
                    LabeledSection(title: "Original transcript") {
                        Text(original).font(.callout)
                    }
                }
                if let english = defect.transcriptEnglish, !english.isEmpty {
                    LabeledSection(title: "English") {
                        Text(english).font(.callout)
                    }
                }
                if let notes = defect.aiSafetyNotes, !notes.isEmpty {
                    LabeledSection(title: "AI safety analysis") {
                        Text(notes).font(.callout)
                    }
                }

                LabeledSection(title: "AI-extracted location") {
                    VStack(alignment: .leading, spacing: 6) {
                        metadataRow(label: "Storey", value: defect.storey)
                        metadataRow(label: "Space", value: defect.space ?? "—")
                        metadataRow(label: "Orientation", value: defect.orientation ?? "—")
                        metadataRow(label: "Element type", value: defect.elementType)
                    }
                }

                metadataSection

                dimensionsSection

                Button(action: onResolve) {
                    HStack {
                        Image(systemName: defect.resolved ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                        Text(defect.resolved ? "Reopen" : "Mark resolved")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear(perform: onDismiss)
    }

    private var reporterCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(reporterColor)
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(defect.reporter)
                    .font(.callout.weight(.semibold))
                if let worker = reporterWorker {
                    Text(worker.department)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unknown department")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(defect.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(reporterColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var metadataSection: some View {
        LabeledSection(title: "Details") {
            VStack(alignment: .leading, spacing: 6) {
                metadataRow(label: "ID", value: shortDefectId)
                if !defect.guid.isEmpty {
                    metadataRow(label: "Element GUID", value: defect.guid)
                }
                metadataRow(
                    label: "Coordinates",
                    value: String(
                        format: "x %.2f · y %.2f · z %.2f",
                        defect.centroidX, defect.centroidY, defect.centroidZ
                    )
                )
                metadataRow(
                    label: "Status",
                    value: defect.resolved ? "Resolved" : "Open"
                )
                metadataRow(
                    label: "Sync",
                    value: defect.synced ? "Synced" : "Pending"
                )
            }
        }
    }

    private var dimensionsSection: some View {
        LabeledSection(title: "Bounding box") {
            VStack(alignment: .leading, spacing: 6) {
                metadataRow(
                    label: "Min",
                    value: String(
                        format: "x %.2f · y %.2f · z %.2f",
                        defect.bboxMinX, defect.bboxMinY, defect.bboxMinZ
                    )
                )
                metadataRow(
                    label: "Max",
                    value: String(
                        format: "x %.2f · y %.2f · z %.2f",
                        defect.bboxMaxX, defect.bboxMaxY, defect.bboxMaxZ
                    )
                )
                metadataRow(
                    label: "Size",
                    value: String(
                        format: "%.2f × %.2f × %.2f m",
                        defect.bboxMaxX - defect.bboxMinX,
                        defect.bboxMaxY - defect.bboxMinY,
                        defect.bboxMaxZ - defect.bboxMinZ
                    )
                )
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SeverityBadge: View {
    let severity: Severity
    let color: Color
    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct LabeledSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct DefectPhotoSection: View {
    let photoPath: String

    @State private var image: UIImage?
    @State private var showingPhoto = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { showingPhoto = true }
                    .fullScreenCover(isPresented: $showingPhoto) {
                        PhotoViewer(image: image) { showingPhoto = false }
                    }
            }
        }
        .task(id: photoPath) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let url = URL(fileURLWithPath: photoPath)
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
        guard !Task.isCancelled else { return }
        image = data.flatMap(UIImage.init(data:))
    }
}

private struct PhotoViewer: View {
    let image: UIImage
    let onDismiss: () -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
    }
}
