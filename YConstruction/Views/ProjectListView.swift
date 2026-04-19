import SwiftUI

struct ProjectListView: View {
    @StateObject private var store = ProjectsStore()
    @State private var searchText: String = ""
    @State private var showingAddSheet: Bool = false
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(filteredProjects) { project in
                        ProjectCardView(project: project) {
                            onSelect(project.id)
                        }
                    }

                    if filteredProjects.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BrandSign()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AddProjectButton {
                        showingAddSheet = true
                    }
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search projects"
            )
            .sheet(isPresented: $showingAddSheet) {
                AddProjectSheet { id, name in
                    store.add(id: id, name: name)
                }
            }
        }
    }

    private var filteredProjects: [SavedProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No matching projects")
                .font(.headline)
            Text("Try a different search, or add a new project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

// MARK: - Brand sign

private struct BrandSign: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
            Text("YConstruction")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("YConstruction")
    }
}

// MARK: - Add project glass button

private struct AddProjectButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .accessibilityLabel("Add project")
    }
}

// MARK: - Project card

private struct ProjectCardView: View {
    let project: SavedProject
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(project.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if project.isDemo {
                            DemoTag()
                        }
                    }
                    Text(project.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct DemoTag: View {
    var body: some View {
        Text("DEMO")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(.tint)
            .background(.tint.opacity(0.15), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.tint.opacity(0.35), lineWidth: 0.5)
            )
    }
}

// MARK: - Add sheet

private struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var projectId: String = ""
    @State private var displayName: String = ""
    let onAdd: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. duplex-demo-001", text: $projectId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Project ID")
                } footer: {
                    Text("The unique identifier used to fetch the project bundle.")
                }

                Section {
                    TextField("Optional display name", text: $displayName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown in the project list. Defaults to the project ID.")
                }
            }
            .navigationTitle("Add Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(projectId, displayName)
                        dismiss()
                    }
                    .disabled(trimmedId.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedId: String {
        projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ProjectListView(onSelect: { _ in })
}
