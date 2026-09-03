import Foundation

enum AppPage: CaseIterable, Identifiable {
    case dictation
    case transcription
    case formatting
    case meetings
    case localModels
    case systemAccess

    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .transcription: "Transcription"
        case .formatting: "Formatting"
        case .meetings: "Meetings"
        case .localModels: "Local Models"
        case .systemAccess: "System Access"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation: "waveform"
        case .transcription: "text.bubble"
        case .formatting: "textformat"
        case .meetings: "person.2.wave.2"
        case .localModels: "cpu"
        case .systemAccess: "lock.shield"
        }
    }
}
