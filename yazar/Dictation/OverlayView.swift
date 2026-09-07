import SwiftUI

struct OverlayView: View {
    @Bindable var yazar: Yazar
    @Bindable var settings: Settings
    let openSettings: (AppPage) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The hosting view survives between dictations. Keep entrance progress
    // separate from content so a new state expands from the same narrow sliver.
    @State private var visible = false

    static let panelSize = CGSize(width: 440, height: 80)
    static let capsuleAnimationDuration: TimeInterval = 0.3

    var body: some View {
        // One persistent surface for every state. Only its dimensions change;
        // the contents crossfade without replacing or blurring the pill itself.
        Capsule()
            .fill(.black.opacity(0.86))
            .frame(
                width: visible || reduceMotion ? surfaceSize.width : 5,
                height: surfaceSize.height
            )
            .overlay {
                ZStack {
                    content
                        .id(yazar.state)
                        .transition(.opacity)
                }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: yazar.state)
            }
            .clipShape(Capsule())
        .opacity(visible ? 1 : 0)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.18) : .spring(
                duration: Self.capsuleAnimationDuration, bounce: 0.25
            ),
            value: visible
        )
        .animation(
            reduceMotion ? nil : .spring(duration: Self.capsuleAnimationDuration, bounce: 0.25),
            value: surfaceSize
        )
        // Every state keeps the same height and vertical center. Only width
        // changes, so entering an error cannot nudge the pill or its contents.
        .padding(.vertical, 22.5)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .onChange(of: yazar.state == .idle) { _, idle in
            visible = !idle
        }
    }

    private var surfaceSize: CGSize {
        let width: CGFloat = switch yazar.state {
        case .retrying, .error, .recovery: DictationRecoveryView.width
        case .warmingUp, .recording: settings.showRecordingTimer ? 115 : 65
        case .noSpeech: 175
        case .copied: 210
        case .idle, .transcribing: 115
        }
        return CGSize(width: width, height: 35)
    }

    @ViewBuilder
    private var content: some View {
        switch yazar.state {
        case .idle:
            Color.clear.frame(width: 36)
        case .warmingUp:
            ProgressView().controlSize(.small).brightness(0.4).accessibilityLabel("Preparing microphone")
        case .recording:
            HStack(spacing: 8) {
                WaveformView(yazar: yazar)
                if settings.showRecordingTimer {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        Text(max(0, context.date.timeIntervalSince(yazar.recordingStartedAt ?? context.date)),
                             format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                    }
                }
            }
        case .transcribing:
            ProgressView().controlSize(.small).brightness(0.4).accessibilityLabel("Transcribing")
        case .noSpeech:
            Label("No speech detected", systemImage: "mic.slash")
        case .copied:
            Label("Copied. Paste with ⌘V", systemImage: "checkmark")
        case .retrying, .error, .recovery:
            DictationRecoveryView(yazar: yazar, settings: settings, openSettings: openSettings)
        }
    }
}
