import Foundation

enum AppPage: CaseIterable, Identifiable {
    case dictation
    case transcription
    case notes
    case systemAccess

    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .transcription: "Transcription"
        case .notes: "Notes"
        case .systemAccess: "System Access"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation: "waveform"
        case .transcription: "text.bubble"
        case .notes: "doc.text"
        case .systemAccess: "lock.shield"
        }
    }
}
