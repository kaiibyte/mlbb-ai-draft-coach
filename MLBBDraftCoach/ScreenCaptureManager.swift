
import SwiftUI
import ScreenCaptureKit
import CoreMedia

final class ScreenCaptureManager: NSObject, ObservableObject {

    @MainActor @Published private(set) var isCapturing = false
    @MainActor @Published private(set) var status = "Screen capture is off"
    @MainActor @Published private(set) var framesReceived = 0

    private let picker = SCContentSharingPicker.shared

    private var stream: SCStream?

    private let frameQueue = DispatchQueue(
        label: "com.draftcoach.screenframes"
    )

    @MainActor
    func startScreenCapture() {
        guard !isCapturing else { return }

        guard picker.isAvailable else {
            status = "Screen capture is unavailable"
            return
        }

        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false

        picker.defaultConfiguration = configuration
        picker.add(self)

        status = "Waiting for screen sharing permission..."
        picker.present()
    }

    @MainActor
    func stopScreenCapture() {
        Task {
            await stopStream()
        }
    }

    @MainActor
    private func startStream(using filter: SCContentFilter) async {
        await stopStream()

        let configuration = SCStreamConfiguration()
        configuration.width = 1024
        configuration.height = 576
        configuration.capturesAudio = false

        let newStream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )

        do {
            try newStream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: frameQueue
            )

            try await newStream.startCapture()

            stream = newStream
            isCapturing = true
            framesReceived = 0
            status = "Screen capture is running"

        } catch {
            stream = nil
            isCapturing = false
            status = "Capture failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func stopStream() async {
        guard let currentStream = stream else {
            isCapturing = false
            return
        }

        do {
            try await currentStream.stopCapture()
        } catch {
            status = "Stop error: \(error.localizedDescription)"
        }

        stream = nil
        isCapturing = false
        status = "Screen capture is off"
    }
}

// MARK: - Screen sharing picker

extension ScreenCaptureManager: SCContentSharingPickerObserver {

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            await self?.startStream(using: filter)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            self?.status = "Screen sharing cancelled"
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(
        _ error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.status = "Picker failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Screen stream

extension ScreenCaptureManager: SCStreamOutput, SCStreamDelegate {

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        Task { @MainActor [weak self] in
            self?.framesReceived += 1
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didStopWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            self?.stream = nil
            self?.status = "Capture stopped: \(error.localizedDescription)"
        }
    }
}
