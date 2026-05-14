import CoreAudio
import Foundation

struct CAError: LocalizedError {
    let status: OSStatus
    let context: String
    var errorDescription: String? { "\(context) failed (OSStatus \(status))" }
}

@discardableResult
func ca(_ status: OSStatus, _ context: String) throws -> OSStatus {
    guard status == noErr else { throw CAError(status: status, context: context) }
    return status
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    private func address(_ selector: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope,
                         _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func read<T>(_ selector: AudioObjectPropertySelector,
                 as _: T.Type = T.self,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> T {
        var addr = address(selector, scope, element)
        var size = UInt32(MemoryLayout<T>.size)
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        try ca(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, ptr), "GetPropertyData(\(selector))")
        return ptr.pointee
    }

    func readArray<T>(_ selector: AudioObjectPropertySelector,
                      as _: T.Type = T.self,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                      element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> [T] {
        var addr = address(selector, scope, element)
        var dataSize: UInt32 = 0
        try ca(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &dataSize), "GetPropertyDataSize(\(selector))")
        let count = Int(dataSize) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        var size = dataSize
        return try [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            try ca(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, buffer.baseAddress!),
                   "GetPropertyData(\(selector)) array")
            initialized = count
        }
    }

    func readString(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String {
        var addr = address(selector, scope, element)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        try ca(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &value), "GetPropertyData(\(selector)) string")
        guard let value else { return "" }
        return value.takeRetainedValue() as String
    }

    func hasProperty(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var addr = address(selector, scope, element)
        return AudioObjectHasProperty(self, &addr)
    }

    func addListener(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                     queue: DispatchQueue,
                     handler: @escaping () -> Void) -> AudioObjectPropertyListenerBlock {
        var addr = address(selector, scope, element)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(self, &addr, queue, block)
        return block
    }

    func removeListener(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                        queue: DispatchQueue,
                        block: @escaping AudioObjectPropertyListenerBlock) {
        var addr = address(selector, scope, element)
        AudioObjectRemovePropertyListenerBlock(self, &addr, queue, block)
    }
}
