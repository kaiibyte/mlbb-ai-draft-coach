
import SwiftUI
import ScreenCaptureKit
import Vision
import CoreMedia
import CoreImage

final class ScreenCaptureManager: NSObject, ObservableObject {
    @MainActor @Published private(set) var isCapturing = false
    @MainActor @Published private(set) var status = "Screen capture is off"
    @MainActor @Published private(set) var framesReceived = 0
    @MainActor @Published private(set) var recognizedText: [String] = []

    private let picker = SCContentSharingPicker.shared
    private var stream: SCStream?

    private let frameQueue = DispatchQueue(
        label: "com.draftcoach.screenframes"
    )

    private var lastOCRTime = Date.distantPast
    private let ciContext = CIContext()

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
            recognizedText = []
            status = "Capturing and recognizing screen text"

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
            status = "Screen capture is off"
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

    private func recognizeText(in pixelBuffer: CVPixelBuffer) {
        let request = VNRecognizeTextRequest()

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        do {
            try VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer
            ).perform([request])

            let lines = (request.results ?? []).compactMap {
                $0.topCandidates(1).first?.string
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recognizedText = lines
                self.framesReceived += 1
            }

        } catch {
            Task { @MainActor [weak self] in
                self?.status = "Text recognition failed"
            }
        }
    }
}

// MARK: Screen sharing picker

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

// MARK: Screen stream

extension ScreenCaptureManager: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastOCRTime) >= 1.0 else {
            return
        }
        lastOCRTime = now

        recognizeText(in: pixelBuffer)
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
