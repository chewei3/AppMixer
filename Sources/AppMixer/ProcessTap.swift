import CoreAudio
import Foundation

/// Captures a single process's audio via a Core Audio process tap, mutes the
/// original output, and re-injects the audio through a private aggregate device
/// at an adjustable volume. Requires macOS 14.2+.
final class ProcessTap {
    let process: AudioProcess

    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let volumePtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    /// 0.0 ... 1.0 — read on the realtime audio thread.
    var volume: Float {
        get { volumePtr.pointee }
        set { volumePtr.pointee = max(0, min(1, newValue)) }
    }

    init(process: AudioProcess) {
        self.process = process
        volumePtr.pointee = 1.0
    }

    deinit {
        deactivate()
        volumePtr.deallocate()
    }

    func activate() throws {
        guard tapID == .unknown else { return }

        // 1. Describe a stereo mixdown tap of just this process, muting its
        //    normal output path while we are tapping it.
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [process.id])
        tapDescription.uuid = UUID()
        tapDescription.name = "AppMixer-\(process.pid)"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped

        var createdTap: AudioObjectID = .unknown
        try ca(AudioHardwareCreateProcessTap(tapDescription, &createdTap), "AudioHardwareCreateProcessTap")
        tapID = createdTap

        // 2. The real output device the audio should ultimately land on.
        let outputDevice: AudioObjectID = try AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice)
        let outputUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)

        // 3. Build a private aggregate device: real output + our tap.
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "AppMixer Aggregate \(process.pid)",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,
                    kAudioSubTapUIDKey as String: tapDescription.uuid.uuidString,
                ]
            ],
        ]

        var createdAggregate: AudioObjectID = .unknown
        try ca(AudioHardwareCreateAggregateDevice(description as CFDictionary, &createdAggregate),
               "AudioHardwareCreateAggregateDevice")
        aggregateID = createdAggregate

        // 4. Install a realtime IO callback that scales the tapped audio.
        let volumePtr = self.volumePtr
        var createdIOProc: AudioDeviceIOProcID?
        let ioBlock: AudioDeviceIOBlock = { _, inInputData, _, outOutputData, _ in
            ProcessTap.render(input: inInputData, output: outOutputData, gain: volumePtr.pointee)
        }
        try ca(AudioDeviceCreateIOProcIDWithBlock(&createdIOProc, aggregateID, nil, ioBlock),
               "AudioDeviceCreateIOProcIDWithBlock")
        ioProcID = createdIOProc

        try ca(AudioDeviceStart(aggregateID, createdIOProc), "AudioDeviceStart")
    }

    func deactivate() {
        if let ioProcID, aggregateID != .unknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != .unknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    /// Realtime-safe: copies tapped input into the output buffers scaled by `gain`.
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               gain: Float) {
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        let bufferCount = min(inList.count, outList.count)

        for i in 0..<bufferCount {
            let inBuffer = inList[i]
            let outBuffer = outList[i]
            guard let inData = inBuffer.mData, let outData = outBuffer.mData else { continue }

            let byteCount = min(inBuffer.mDataByteSize, outBuffer.mDataByteSize)
            if gain >= 0.999 {
                memcpy(outData, inData, Int(byteCount))
            } else if gain <= 0.001 {
                memset(outData, 0, Int(outBuffer.mDataByteSize))
                continue
            } else {
                let sampleCount = Int(byteCount) / MemoryLayout<Float32>.size
                let inSamples = inData.assumingMemoryBound(to: Float32.self)
                let outSamples = outData.assumingMemoryBound(to: Float32.self)
                for s in 0..<sampleCount {
                    outSamples[s] = inSamples[s] * gain
                }
            }
            // Silence any trailing space if the output buffer is larger.
            if outBuffer.mDataByteSize > byteCount {
                memset(outData + Int(byteCount), 0, Int(outBuffer.mDataByteSize - byteCount))
            }
        }
    }
}
