import AVFoundation
import CoreAudio

struct AudioInput: Identifiable, Hashable {
    let id: String
    let name: String
    let isBuiltIn: Bool

    static var available: [AudioInput] {
        devices.map {
            AudioInput(
                id: $0.uniqueID,
                name: $0.localizedName,
                isBuiltIn: $0.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn)
            )
        }
        .sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static var defaultDevice: AVCaptureDevice? {
        devices.first {
            $0.transportType == Int32(bitPattern: kAudioDeviceTransportTypeBuiltIn)
        } ?? AVCaptureDevice.default(for: .audio)
    }

    static var defaultID: String? { defaultDevice?.uniqueID }

    static func device(id: String) -> AVCaptureDevice? {
        devices.first { $0.uniqueID == id }
    }

    private static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }
}
