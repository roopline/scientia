import AVFoundation
import Foundation
import UIKit

/// AVCaptureSession の生成・開始・停止と、フレームの受け渡しだけを担当する。
final class CameraController: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        case running
        case denied
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isTorchOn = false

    let session = AVCaptureSession()

    /// 解析用のフレーム。videoQueue 上で呼ばれる。
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "labelcheck.camera.session")
    private let videoQueue = DispatchQueue(label: "labelcheck.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false

    // MARK: - ライフサイクル

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { self.status = .denied }
                return
            }
            self.sessionQueue.async {
                self.configureIfNeeded()
                guard !self.session.isRunning else { return }
                self.session.startRunning()
                DispatchQueue.main.async {
                    if case .failed = self.status { return }
                    self.status = .running
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.status = .idle }
        }
    }

    // MARK: - 設定

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        // 小さな文字を読むため、可能なら 1080p 以上で取り込む
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.status = .failed("カメラを初期化できませんでした") }
            return
        }
        session.addInput(input)
        device = camera

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // 端末を縦持ちした状態のフレームが届くようにする（Vision へは .up で渡せる）
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        configureFocus(camera)
        session.commitConfiguration()
    }

    private func configureFocus(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            // ラベルは近距離で読むため、近接側を優先して合焦させる
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        } catch {
            // 合焦設定に失敗しても撮影自体は続行する
        }
    }

    /// 画面タップ位置にフォーカスを合わせる（引数は 0...1 のデバイス座標）。
    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()
            } catch {
                // 無視して継続
            }
        }
    }

    func toggleTorch() {
        sessionQueue.async {
            guard let device = self.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                let turnOn = !device.isTorchActive
                device.torchMode = turnOn ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.isTorchOn = turnOn }
            } catch {
                // 無視して継続
            }
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer)
    }
}
