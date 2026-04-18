import SwiftUI

struct ReportView: View {
    let report: DefectReport
    let canSave: Bool
    var onSave: ((DefectReport) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let img = UIImage(data: report.photoData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Text(report.defectType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.title.bold())
                    Spacer()
                    SeverityBadge(severity: report.severity)
                }

                if let code = report.codeReferenceId {
                    Label(code, systemImage: "book.closed")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }

                section("Visual description") {
                    Text(report.visualDescription)
                }

                section("Inspector said") {
                    Text("\"\(report.transcript)\"")
                        .italic()
                        .foregroundStyle(.secondary)
                }

                section("Confidence") {
                    HStack {
                        ProgressView(value: report.confidence)
                        Text("\(Int(report.confidence * 100))%")
                            .font(.subheadline.monospacedDigit())
                    }
                }

                Text("Logged \(report.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(canSave ? "Review" : "Defect")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canSave, let onSave {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { onSave(report) }.bold()
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Discard", role: .destructive) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
    }
}
