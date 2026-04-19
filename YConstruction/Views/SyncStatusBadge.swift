import SwiftUI

struct SyncStatusBadge: View {
    let lastSyncedAt: Date?
    let isOnline: Bool
    let isSyncing: Bool

    private var color: Color {
        if !isOnline { return .red }
        if isSyncing { return .yellow }
        return .green
    }

    private var label: String {
        if !isOnline { return "Offline" }
        if isSyncing { return "Syncing" }
        return "Synced"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }
}
