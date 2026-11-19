
import SwiftUI
import ScreenCaptureKit
import CoreMedia

@MainActor
final class ScreenCaptureManager: NSObject, ObservableObject,
    SCContentSharingPickerObserver,
    SCStreamOutput,
    SCStreamDelegate {

    @Published private(set) var isCapturing = false
    @Published private(set) var status = "Screen capture is off"
    @Published private(set) var framesReceived = 0

    private let picker = SCContentSharingPicker.shared
    private var stream: SCStream?

    private let frameQueue = DispatchQueue(
        label: "com.draftcoach.screenframes"
    )

    override init() {
        super.init()
    }

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

    func stopScreenCapture() {
        Task {
            await stopStream()
        }
    }

    private func startStream(using filter: SCContentFilter) async {
        await stopStream()

        let configuration = SCStreamConfiguration()

        configuration.width = 1024
        configuration.height = 576
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: 2
        )

        configuration.queueDepth = 3
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

    // MARK: Screen sharing picker

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor in
            await startStream(using: filter)
        }
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        status = "Screen sharing cancelled"
    }

    func contentSharingPickerStartDidFailWithError(
        _ error: Error
    ) {
        status = "Picker failed: \(error.localizedDescription)"
    }

    // MARK: Screen frames

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        Task { @MainActor in
            framesReceived += 1
        }
    }

    // MARK: Stream errors

    func stream(
        _ stream: SCStream,
        didStopWithError error: Error
    ) {
        Task { @MainActor in
            isCapturing = false
            self.stream = nil
            status = "Capture stopped: \(error.localizedDescription)"
        }
    }
}
