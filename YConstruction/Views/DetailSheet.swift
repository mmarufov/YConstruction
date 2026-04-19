import SwiftUI

struct DetailSheet: View {
    let defect: Defect
    let onResolve: () -> Void
    let onDismiss: () -> Void

    private var severityColor: Color {
        switch defect.severity {
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
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

                LabeledSection(title: "Location") {
                    Text("\(defect.storey) > \(defect.space ?? "—") > \(defect.orientation ?? "—") \(defect.elementType)")
                        .font(.callout)
                }

                HStack {
                    Text(defect.reporter)
                    Spacer()
                    Text(defect.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

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
