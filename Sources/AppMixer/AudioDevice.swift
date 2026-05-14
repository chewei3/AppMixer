import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

enum AudioDevices {
    /// Every device capable of playing audio out.
    static func outputDevices() -> [AudioDevice] {
        let deviceIDs: [AudioObjectID]
        do {
            deviceIDs = try AudioObjectID.system.readArray(kAudioHardwarePropertyDevices)
        } catch {
            appLog("AppMixer: failed to read device list: \(error)")
            return []
        }

        var result: [AudioDevice] = []
        for deviceID in deviceIDs {
            let outputStreams: [AudioObjectID] = (try? deviceID.readArray(
                kAudioDevicePropertyStreams,
                scope: kAudioObjectPropertyScopeOutput
            )) ?? []
            guard !outputStreams.isEmpty else { continue }

            guard let uid = try? deviceID.readString(kAudioDevicePropertyDeviceUID),
                  let name = try? deviceID.readString(kAudioObjectPropertyName),
                  // Skip our own private aggregate devices.
                  !name.hasPrefix("AppMixer")
            else { continue }

            result.append(AudioDevice(id: deviceID, uid: uid, name: name))
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
