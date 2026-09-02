import Foundation

enum AppPage: CaseIterable, Identifiable {
    case dictation
    case transcription
    case systemAccess

    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .transcription: "Transcription"
        case .systemAccess: "System Access"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation: "waveform"
        case .transcription: "text.bubble"
        case .systemAccess: "lock.shield"
        }
    }
}
