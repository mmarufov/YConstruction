import SwiftUI

struct ProjectEntryView: View {
    @State private var projectIdInput: String = ""
    let onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("YConstruction")
                    .font(.largeTitle.weight(.bold))
                Text("Offline-first site defect reporting")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Actual Project ID")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. duplex-demo-001", text: $projectIdInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    onSubmit(AppConfig.demoProjectId)
                } label: {
                    VStack(spacing: 6) {
                        Text("Duplex")
                            .font(.headline)
                        Text("Open the built-in demo")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .padding(.horizontal, 12)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }

                Button {
                    onSubmit(projectIdInput)
                } label: {
                    VStack(spacing: 6) {
                        Text("Project ID")
                            .font(.headline)
                        Text("Load the typed project")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 78)
                    .padding(.horizontal, 12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(projectIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}
