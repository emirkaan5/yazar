import SwiftUI

struct OverlayView: View {
    @Bindable var yazar: Yazar
    // Drives the entrance animation: the panel keeps this view alive across
    // sessions, so the blur/fade is keyed off the idle transition, not onAppear.
    @State private var visible = false

    static let panelSize = CGSize(width: 420, height: 76)

    var body: some View {
        Group {
            switch yazar.state {
            case .idle:
                EmptyView()
            case .warmingUp:
                Image(systemName: "waveform")
                    .symbolEffect(.pulse)
                    .foregroundStyle(.secondary)
            case .recording:
                recordingView
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
            case .noSpeech:
                HStack(spacing: 6) {
                    Image(systemName: "mic.slash")
                    Text("No speech")
                }
                .foregroundStyle(.white)
            case .error(let message):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.white)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 12)
        .frame(width: capsuleSize.width, height: capsuleSize.height)
        .background(backgroundColor, in: Capsule())
        // Entrance: the capsule extends vertically from a sliver to full height,
        // clipping (not squashing) the content while it grows.
        .frame(height: visible ? capsuleSize.height : 5)
        .clipShape(Capsule())
        .blur(radius: visible ? 0 : 10)
        .opacity(visible ? 1 : 0)
        // Pins the capsule to the centre of the panel so the height change
        // expands symmetrically instead of dropping from the top edge.
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .center)
        .onChange(of: yazar.state == .idle) { _, idle in
            // Animate both ways so an interrupted entrance reverses smoothly
            // rather than snapping while the panel fades out.
            withAnimation(.easeOut(duration: 0.2)) { visible = !idle }
        }
    }

    private var recordingView: some View {
        HStack(spacing: 8) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(.white)
                        .frame(width: 2, height: barHeight(at: index))
                }
            }
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(elapsed(at: context.date), format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
    }

    private var backgroundColor: Color {
        if case .error = yazar.state { return .red.opacity(0.92) }
        return .black.opacity(0.82)
    }

    private var capsuleSize: CGSize {
        if case .error = yazar.state { return CGSize(width: 400, height: 58) }
        return CGSize(width: 115, height: 30)
    }

    private func elapsed(at date: Date) -> Double {
        max(0, date.timeIntervalSince(yazar.recordingStartedAt ?? date))
    }

    private func barHeight(at index: Int) -> CGFloat {
        let shape = [0.45, 0.7, 1.0, 0.75, 0.55, 0.85, 0.4][index]
        return 3 + 12 * max(0.08, yazar.level) * shape
    }
}
