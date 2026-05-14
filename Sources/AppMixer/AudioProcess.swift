import AppKit
import CoreAudio

struct AudioProcess: Identifiable, Equatable {
    let id: AudioObjectID      // Core Audio process object ID
    let pid: pid_t
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let isPlaying: Bool

    static func == (lhs: AudioProcess, rhs: AudioProcess) -> Bool {
        lhs.id == rhs.id && lhs.isPlaying == rhs.isPlaying
    }
}

final class AudioProcessController {
    private let queue = DispatchQueue(label: "com.chewei3.appmixer.processlist")
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    var onChange: (([AudioProcess]) -> Void)?

    func start() {
        listenerBlock = AudioObjectID.system.addListener(
            kAudioHardwarePropertyProcessObjectList,
            queue: queue
        ) { [weak self] in
            self?.reload()
        }
        reload()
    }

    func stop() {
        if let listenerBlock {
            AudioObjectID.system.removeListener(
                kAudioHardwarePropertyProcessObjectList,
                queue: queue,
                block: listenerBlock
            )
        }
        listenerBlock = nil
    }

    func reload() {
        let processes = Self.currentProcesses()
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(processes)
        }
    }

    private static func currentProcesses() -> [AudioProcess] {
        let objectIDs: [AudioObjectID]
        do {
            objectIDs = try AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList)
        } catch {
            appLog("AppMixer: failed to read process list: \(error)")
            return []
        }
        appLog("AppMixer: process object count = \(objectIDs.count)")

        var result: [AudioProcess] = []
        for objectID in objectIDs {
            guard let pid: pid_t = try? objectID.read(kAudioProcessPropertyPID) else {
                appLog("AppMixer:   objectID \(objectID) — no PID")
                continue
            }

            let runningApp = NSRunningApplication(processIdentifier: pid)
            let bundleID = (try? objectID.readString(kAudioProcessPropertyBundleID)).flatMap {
                $0.isEmpty ? nil : $0
            }
            let runningOutput = (try? objectID.read(kAudioProcessPropertyIsRunningOutput)) as UInt32?
            let isPlaying = (runningOutput ?? 0) != 0

            // Only show real, user-facing apps (Dock apps) — skip daemons,
            // XPC helper services, menu bar agents, and ourselves.
            guard let app = runningApp,
                  app.activationPolicy == .regular,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let name = app.localizedName
            else { continue }

            result.append(AudioProcess(
                id: objectID,
                pid: pid,
                bundleID: bundleID,
                name: name,
                icon: app.icon,
                isPlaying: isPlaying
            ))
        }
        appLog("AppMixer: visible processes = \(result.count)")
        return result.sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
