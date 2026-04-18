import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var showInspection = false

    var body: some View {
        NavigationStack {
            ZStack {
                if app.punchList.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checklist")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No defects logged yet.")
                            .font(.headline)
                        Text("Tap ‘New Inspection’ to begin.")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(app.punchList.items, id: \.timestamp) { item in
                            NavigationLink(value: item) {
                                DefectRow(report: item)
                            }
                        }
                        .onDelete(perform: app.punchList.remove)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Punch List")
            .navigationDestination(for: DefectReport.self) { item in
                ReportView(report: item, canSave: false)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showInspection = true
                    } label: {
                        Label("New Inspection", systemImage: "plus.circle.fill")
                    }
                    .disabled(!app.modelReady)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !app.modelReady {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Loading model…").font(.caption)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showInspection) {
                InspectionView()
            }
        }
    }
}

struct DefectRow: View {
    let report: DefectReport

    var body: some View {
        HStack(spacing: 12) {
            if let img = UIImage(data: report.photoData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(report.defectType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                    Spacer()
                    SeverityBadge(severity: report.severity)
                }
                Text(report.visualDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let code = report.codeReferenceId {
                    Text(code).font(.caption).foregroundStyle(.tint)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SeverityBadge: View {
    let severity: DefectReport.Severity

    var body: some View {
        Text(severity.rawValue.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch severity {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

extension DefectReport: Hashable {
    public static func == (lhs: DefectReport, rhs: DefectReport) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(timestamp)
    }
}
