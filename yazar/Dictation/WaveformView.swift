import SwiftUI

// The recording level meter. `TimelineView(.animation)` re-runs this at the
// display refresh rate, so the bars are one `Shape` rather than seven
// `Capsule` views: each frame builds a single path instead of laying out and
// diffing seven nodes with dynamic frames.
struct WaveformView: View {
    let level: Double

    var body: some View {
        TimelineView(.animation) { context in
            WaveformShape(level: level, time: context.date.timeIntervalSinceReferenceDate)
                .fill(.white)
                // The wave itself is redrawn every frame; only the level jumps
                // (every 33ms), so smooth that step and leave the sine alone.
                .animation(.easeOut(duration: 0.09), value: level)
        }
        .frame(width: WaveformShape.size.width, height: WaveformShape.size.height)
    }
}

// Each bar rides the same sine at its own phase, so the row ripples left to
// right instead of scaling as one block. The mic level sets the amplitude and
// is the animatable data; the envelope keeps the middle bars taller than the ends.
private struct WaveformShape: Shape {
    var level: Double
    var time: TimeInterval

    private static let envelope = [0.6, 0.8, 1.0, 0.95, 0.85, 0.75, 0.6]
    private static let barWidth: CGFloat = 2
    private static let spacing: CGFloat = 2
    private static let minBarHeight: CGFloat = 3
    private static let maxBarGrowth: CGFloat = 17

    static let size = CGSize(
        width: CGFloat(envelope.count) * barWidth + CGFloat(envelope.count - 1) * spacing,
        height: minBarHeight + maxBarGrowth
    )

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, envelope) in Self.envelope.enumerated() {
            let wave = 0.5 + 0.5 * sin(time * 7 - Double(index) * 0.9)
            let height = Self.minBarHeight
                + Self.maxBarGrowth * max(0.1, level) * envelope * (0.35 + 0.65 * wave)
            let bar = CGRect(
                x: rect.minX + CGFloat(index) * (Self.barWidth + Self.spacing),
                y: rect.midY - height / 2,
                width: Self.barWidth,
                height: height
            )
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: Self.barWidth / 2, height: Self.barWidth / 2))
        }
        return path
    }
}
