import AppKit
import Combine
import CoreAudio

@MainActor
final class AudioManager: ObservableObject {
    @Published private(set) var processes: [AudioProcess] = []

    private let controller = AudioProcessController()
    private var taps: [pid_t: ProcessTap] = [:]
    private var volumes: [pid_t: Float] = [:]
    private var mutedPIDs: Set<pid_t> = []

    init() {
        controller.onChange = { [weak self] processes in
            self?.handleProcessListChange(processes)
        }
        controller.start()
    }

    // MARK: - Queries

    func volume(for process: AudioProcess) -> Float {
        volumes[process.pid] ?? 1.0
    }

    func isMuted(_ process: AudioProcess) -> Bool {
        mutedPIDs.contains(process.pid)
    }

    // MARK: - Actions

    func setVolume(_ value: Float, for process: AudioProcess) {
        volumes[process.pid] = value
        if value > 0 { mutedPIDs.remove(process.pid) }
        applyTap(for: process)
        objectWillChange.send()
    }

    func toggleMute(_ process: AudioProcess) {
        if mutedPIDs.contains(process.pid) {
            mutedPIDs.remove(process.pid)
        } else {
            mutedPIDs.insert(process.pid)
        }
        applyTap(for: process)
        objectWillChange.send()
    }

    func resetAll() {
        volumes.removeAll()
        mutedPIDs.removeAll()
        for tap in taps.values { tap.deactivate() }
        taps.removeAll()
        objectWillChange.send()
    }

    // MARK: - Internals

    private func effectiveVolume(for pid: pid_t) -> Float {
        if mutedPIDs.contains(pid) { return 0 }
        return volumes[pid] ?? 1.0
    }

    private func applyTap(for process: AudioProcess) {
        let pid = process.pid
        let target = effectiveVolume(for: pid)

        // At full volume there is nothing to do — let the app play normally.
        if target >= 0.999 {
            taps[pid]?.deactivate()
            taps.removeValue(forKey: pid)
            return
        }

        if let existing = taps[pid] {
            existing.volume = target
            return
        }

        let tap = ProcessTap(process: process)
        do {
            try tap.activate()
            tap.volume = target
            taps[pid] = tap
        } catch {
            appLog("AppMixer: could not control \(process.name): \(error)")
        }
    }

    private func handleProcessListChange(_ newProcesses: [AudioProcess]) {
        processes = newProcesses

        // Tear down taps for apps that are gone.
        let livePIDs = Set(newProcesses.map(\.pid))
        for pid in taps.keys where !livePIDs.contains(pid) {
            taps[pid]?.deactivate()
            taps.removeValue(forKey: pid)
        }

        // Re-apply remembered settings to processes that (re)appeared.
        for process in newProcesses {
            let pid = process.pid
            let hasSetting = volumes[pid] != nil || mutedPIDs.contains(pid)
            if hasSetting && taps[pid] == nil {
                applyTap(for: process)
            }
        }
    }
}
