import SwiftUI

struct ProcessingOverlay: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.4)
            Text(title)
                .font(.headline)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25))
        .transition(.opacity)
    }
}
