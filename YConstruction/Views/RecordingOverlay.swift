import SwiftUI

struct RecordingOverlay: View {
    let transcript: String
    let onStop: () -> Void

    @State private var pulse: CGFloat = 1.0

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .scaleEffect(pulse)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.7).repeatForever()) {
                                pulse = 1.25
                            }
                        }
                    Text("Listening…")
                        .font(.headline)
                }

                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Describe the defect in Spanish or English…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button(action: onStop) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("Stop")
                    }
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.red, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
