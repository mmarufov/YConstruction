import SwiftUI

struct SyncStatusBadge: View {
    let pendingCount: Int
    let lastSyncedAt: Date?
    let isOnline: Bool

    private var color: Color {
        if !isOnline { return .red }
        if pendingCount > 0 { return .yellow }
        return .green
    }

    private var label: String {
        if pendingCount > 0 { return "\(pendingCount) pending upload" }
        if !isOnline { return "Offline" }
        return "All synced"
    }

    private var subtitle: String? {
        guard let last = lastSyncedAt else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: last, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
