import Foundation
import CoreAudio
import AVFoundation

/// Captures system-wide output audio (Zoom, Teams, browser calls…) using a
/// CoreAudio process tap (macOS 14.2+). Audio-only TCC prompt
/// (NSAudioCaptureUsageDescription) — no screen-recording permission needed.
final class SystemAudioTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private(set) var format: AVAudioFormat?

    /// Called on the CoreAudio IO thread with each captured buffer.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    enum TapError: LocalizedError {
        case osStatus(String, OSStatus)
        case badFormat

        var errorDescription: String? {
            switch self {
            case .osStatus(let stage, let status): "System audio tap failed at \(stage) (\(status))."
            case .badFormat: "System audio tap returned an unusable format."
            }
        }
    }

    func start() throws {
        // Global tap on the system mix, excluding no processes.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "FOGNote System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw TapError.osStatus("create tap", status) }
        tapID = newTapID

        // Read the tap's stream format.
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &asbd)
        guard status == noErr, let tapFormat = AVAudioFormat(streamDescription: &asbd) else {
            cleanup()
            throw status == noErr ? TapError.badFormat : TapError.osStatus("read format", status)
        }
        format = tapFormat

        // Wrap the tap in a private aggregate device we can run an IO proc on.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "FOGNote Tap Device",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr else {
            cleanup()
            throw TapError.osStatus("create aggregate device", status)
        }
        aggregateID = newAggregateID

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self, let format = self.format else { return }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else { return }
            self.onBuffer?(buffer)
        }
        guard status == noErr, let ioProcID else {
            cleanup()
            throw TapError.osStatus("create IO proc", status)
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            cleanup()
            throw TapError.osStatus("start device", status)
        }
    }

    func stop() {
        cleanup()
    }

    private func cleanup() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { cleanup() }
}
