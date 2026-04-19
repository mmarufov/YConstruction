import SwiftUI

struct ResolverPickerSheet: View {
    let candidates: [ResolvedElement]
    let transcriptEnglish: String?
    let onPick: (ElementIndex.Element) -> Void
    let onSaveAnyway: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let transcript = transcriptEnglish {
                    Section("Worker said") {
                        Text(transcript).font(.callout)
                    }
                }

                Section("Pick the closest match") {
                    ForEach(candidates, id: \.element.guid) { r in
                        Button {
                            onPick(r.element)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(r.element.orientation ?? "—") \(r.element.elementType) in \(r.element.space ?? "—")")
                                    .font(.headline)
                                HStack {
                                    Text(r.element.storey ?? "—")
                                    Spacer()
                                    Text("match: \(Int(r.confidence * 100))%")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Save anyway (no exact match)", action: onSaveAnyway)
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
            .navigationTitle("Which element?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
