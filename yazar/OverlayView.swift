import SwiftUI

struct OverlayView: View {
    @Bindable var yazar: Yazar
    // Drives the entrance animation: the panel keeps this view alive across
    // sessions, so the blur/fade is keyed off the idle transition, not onAppear.
    @State private var visible = false

    static let panelSize = CGSize(width: 420, height: 80)

    var body: some View {
        ZStack {
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
                    // The system spinner draws its own grey and ignores .tint, so it
                    // gets lifted toward white with a brightness filter instead.
                    ProgressView()
                        .controlSize(.small)
                        .brightness(0.4)
                case .noSpeech:
                    HStack(spacing: 6) {
                        Image(systemName: "mic.slash")
                        Text("No speech")
                    }
                    .foregroundStyle(.white)
                case .copied:
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copied to clipboard")
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
            .id(yazar.state)
            .transition(.blurReplace)
        }
        .animation(.easeInOut(duration: 0.18), value: yazar.state)
        .font(.system(size: 13, weight: .regular))
        // The capsule is always dark, so pin the content to dark appearance:
        // the transcribing spinner and the `.secondary` waveform stay light
        // even when the system is in light mode.
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        // Entrance: the capsule extends vertically from a sliver to full height,
        // clipping (not squashing) the content while it grows.
        .frame(width: capsuleSize.width, height: capsuleSize.height)
        .background(backgroundColor, in: Capsule())
        .frame(height: visible ? capsuleSize.height : 5)
        .clipShape(Capsule())
        .animation(.spring(duration: 0.4, bounce: 0.4), value: capsuleSize)
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
            TimelineView(.animation) { context in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<7, id: \.self) { index in
                        Capsule()
                            .fill(.white)
                            .frame(width: 2, height: barHeight(at: index, time: context.date.timeIntervalSinceReferenceDate))
                    }
                }
                // The wave itself is redrawn every frame; only the level jumps
                // (every 33ms), so smooth that step and leave the sine alone.
                .animation(.easeOut(duration: 0.09), value: yazar.level)
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
        switch yazar.state {
        case .error: CGSize(width: 350, height: 35)
        case .copied: CGSize(width: 185, height: 35)
        default: CGSize(width: 115, height: 35)
        }
    }

    private func elapsed(at date: Date) -> Double {
        max(0, date.timeIntervalSince(yazar.recordingStartedAt ?? date))
    }

    // Each bar rides the same sine at its own phase, so the row ripples left to
    // right instead of scaling as one block. The mic level sets the amplitude;
    // the envelope keeps the middle bars taller than the ends.
    private func barHeight(at index: Int, time: TimeInterval) -> CGFloat {
        let envelope = [0.6, 0.8, 1.0, 0.95, 0.85, 0.75, 0.6][index]
        let wave = 0.5 + 0.5 * sin(time * 7 - Double(index) * 0.9)
        return 3 + 17 * max(0.1, yazar.level) * envelope * (0.35 + 0.65 * wave)
    }
}
