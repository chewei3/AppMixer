import AppKit
import Combine
import CoreAudio

@MainActor
final class AudioManager: ObservableObject {
    @Published private(set) var processes: [AudioProcess] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var volumeKeysWanted = false
    @Published private(set) var volumeKeysActive = false

    private let controller = AudioProcessController()
    private let volumeKeyMonitor = VolumeKeyMonitor()
    private let defaults = UserDefaults.standard

    private static let volumeKeyStep: Float = 1.0 / 16.0

    // Runtime taps are keyed by pid; settings are keyed by bundle ID so they
    // survive app relaunches.
    private var taps: [pid_t: ProcessTap] = [:]
    private var volumes: [String: Float] = [:]
    private var muted: Set<String> = []
    private var devices: [String: String] = [:]   // bundle ID -> output device UID

    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceListListener: AudioObjectPropertyListenerBlock?

    private enum Keys {
        static let volumes = "volumes"
        static let muted = "muted"
        static let devices = "devices"
        static let volumeKeys = "volumeKeysEnabled"
    }

    init() {
        loadSettings()
        refreshDevices()
        controller.onChange = { [weak self] processes in
            self?.handleProcessListChange(processes)
        }
        controller.start()

        // Rebuild default-routed taps when the system output device changes.
        defaultDeviceListener = AudioObjectID.system.addListener(
            kAudioHardwarePropertyDefaultOutputDevice, queue: .main
        ) { [weak self] in
            MainActor.assumeIsolated { self?.handleDefaultDeviceChanged() }
        }
        // Refresh routing when devices are plugged in or removed.
        deviceListListener = AudioObjectID.system.addListener(
            kAudioHardwarePropertyDevices, queue: .main
        ) { [weak self] in
            MainActor.assumeIsolated { self?.handleDeviceListChanged() }
        }

        // Volume keys controlling the frontmost app (opt-in, needs permission).
        volumeKeyMonitor.onVolumeKey = { [weak self] up in
            MainActor.assumeIsolated { self?.adjustFocusedAppVolume(up: up) ?? false }
        }
        volumeKeysWanted = defaults.bool(forKey: Keys.volumeKeys)
        if volumeKeysWanted {
            volumeKeysActive = volumeKeyMonitor.enable()
        }
    }

    deinit {
        if let defaultDeviceListener {
            AudioObjectID.system.removeListener(
                kAudioHardwarePropertyDefaultOutputDevice,
                queue: .main, block: defaultDeviceListener
            )
        }
        if let deviceListListener {
            AudioObjectID.system.removeListener(
                kAudioHardwarePropertyDevices,
                queue: .main, block: deviceListListener
            )
        }
    }

    // MARK: - Queries

    func volume(for process: AudioProcess) -> Float {
        volumes[process.bundleID] ?? 1.0
    }

    func isMuted(_ process: AudioProcess) -> Bool {
        muted.contains(process.bundleID)
    }

    /// The chosen output device UID, or `nil` for the system default.
    func outputDevice(for process: AudioProcess) -> String? {
        validatedDeviceUID(for: process.bundleID)
    }

    // MARK: - Actions

    func setVolume(_ value: Float, for process: AudioProcess) {
        volumes[process.bundleID] = value
        if value > 0 { muted.remove(process.bundleID) }
        saveSettings()
        applyTap(for: process)
        objectWillChange.send()
    }

    func toggleMute(_ process: AudioProcess) {
        if muted.contains(process.bundleID) {
            muted.remove(process.bundleID)
        } else {
            muted.insert(process.bundleID)
        }
        saveSettings()
        applyTap(for: process)
        objectWillChange.send()
    }

    func setOutputDevice(_ uid: String?, for process: AudioProcess) {
        if let uid {
            devices[process.bundleID] = uid
        } else {
            devices.removeValue(forKey: process.bundleID)
        }
        saveSettings()
        applyTap(for: process)
        objectWillChange.send()
    }

    func resetAll() {
        volumes.removeAll()
        muted.removeAll()
        devices.removeAll()
        saveSettings()
        for tap in taps.values { tap.deactivate() }
        taps.removeAll()
        objectWillChange.send()
    }

    func setVolumeKeysEnabled(_ on: Bool) {
        volumeKeysWanted = on
        defaults.set(on, forKey: Keys.volumeKeys)
        if on {
            volumeKeysActive = volumeKeyMonitor.enable()
        } else {
            volumeKeyMonitor.disable()
            volumeKeysActive = false
        }
        objectWillChange.send()
    }

    /// Nudges the frontmost app's volume. Returns true if an app was adjusted
    /// (so the key press can be swallowed); false to fall back to system volume.
    func adjustFocusedAppVolume(up: Bool) -> Bool {
        guard let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let process = processes.first(where: { $0.bundleID == frontBundleID })
        else { return false }

        let delta = up ? Self.volumeKeyStep : -Self.volumeKeyStep
        let newValue = max(0, min(1, effectiveVolume(for: process.bundleID) + delta))
        setVolume(newValue, for: process)
        return true
    }

    // MARK: - Persistence

    private func loadSettings() {
        if let stored = defaults.dictionary(forKey: Keys.volumes) {
            volumes = stored.compactMapValues { ($0 as? NSNumber)?.floatValue }
        }
        muted = Set(defaults.stringArray(forKey: Keys.muted) ?? [])
        if let stored = defaults.dictionary(forKey: Keys.devices) {
            devices = stored.compactMapValues { $0 as? String }
        }
    }

    private func saveSettings() {
        defaults.set(volumes, forKey: Keys.volumes)
        defaults.set(Array(muted), forKey: Keys.muted)
        defaults.set(devices, forKey: Keys.devices)
    }

    // MARK: - Internals

    private func refreshDevices() {
        outputDevices = AudioDevices.outputDevices()
    }

    private func effectiveVolume(for bundleID: String) -> Float {
        if muted.contains(bundleID) { return 0 }
        return volumes[bundleID] ?? 1.0
    }

    /// Returns the stored device UID only if that device currently exists,
    /// otherwise `nil` (fall back to the default device).
    private func validatedDeviceUID(for bundleID: String) -> String? {
        guard let uid = devices[bundleID] else { return nil }
        return outputDevices.contains { $0.uid == uid } ? uid : nil
    }

    private func applyTap(for process: AudioProcess) {
        let pid = process.pid
        let target = effectiveVolume(for: process.bundleID)
        let desiredUID = validatedDeviceUID(for: process.bundleID)

        // A tap is needed when the app isn't at full volume, or when it is
        // routed to a non-default device.
        let needsTap = target < 0.999 || desiredUID != nil
        if !needsTap {
            taps[pid]?.deactivate()
            taps.removeValue(forKey: pid)
            return
        }

        // Reuse the tap if the routing target is unchanged; otherwise rebuild,
        // since an aggregate device's output device can't be changed live.
        if let existing = taps[pid] {
            if existing.outputDeviceUID == desiredUID {
                existing.volume = target
                return
            }
            existing.deactivate()
            taps.removeValue(forKey: pid)
        }

        let tap = ProcessTap(process: process, outputDeviceUID: desiredUID)
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
        refreshDevices()

        // Tear down taps for apps that are gone.
        let livePIDs = Set(newProcesses.map(\.pid))
        for pid in taps.keys where !livePIDs.contains(pid) {
            taps[pid]?.deactivate()
            taps.removeValue(forKey: pid)
        }

        // Re-apply remembered settings to processes that (re)appeared.
        for process in newProcesses {
            let hasSetting = volumes[process.bundleID] != nil
                || muted.contains(process.bundleID)
                || devices[process.bundleID] != nil
            if hasSetting && taps[process.pid] == nil {
                applyTap(for: process)
            }
        }
    }

    /// The system output device changed — rebuild every tap that follows the
    /// default device so its audio lands on the new device.
    private func handleDefaultDeviceChanged() {
        let affected = processes.filter { taps[$0.pid]?.outputDeviceUID == nil && taps[$0.pid] != nil }
        for process in affected {
            taps[process.pid]?.deactivate()
            taps.removeValue(forKey: process.pid)
            applyTap(for: process)
        }
    }

    /// A device was plugged in or removed — refresh the list and re-evaluate
    /// every app's routing (a routed device may have appeared or vanished).
    private func handleDeviceListChanged() {
        refreshDevices()
        for process in processes {
            applyTap(for: process)
        }
        objectWillChange.send()
    }
}
