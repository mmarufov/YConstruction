import SwiftUI

struct WorkerGlossaryView: View {
    let workers: [Worker]
    let counts: [String: Int]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if expanded {
                content
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .padding(.vertical, expanded ? 10 : 0)
        .fixedSize(horizontal: true, vertical: true)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.footnote.weight(.semibold))
                Text("\(workers.count)")
                    .font(.callout.weight(.semibold))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(workers) { worker in
                row(for: worker)
            }
            if workers.isEmpty {
                Text("No defects yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(for worker: Worker) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(WorkerColorPalette.color(for: worker.colorIndex))
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(worker.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(worker.department)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let count = counts[worker.name], count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        WorkerColorPalette.color(for: worker.colorIndex).opacity(0.22),
                        in: Capsule()
                    )
                    .foregroundStyle(WorkerColorPalette.color(for: worker.colorIndex))
            }
        }
    }
}
