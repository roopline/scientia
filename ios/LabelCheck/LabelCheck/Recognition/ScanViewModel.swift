import AVFoundation
import Combine
import Foundation
import UIKit

/// スキャン画面の状態機械。
/// カメラのフレームをバックグラウンドで解析し、同じ判定が続けて出たら確定させる。
final class ScanViewModel: ObservableObject {

    // MARK: - 画面に出す状態

    @Published private(set) var result: CheckResult?
    @Published private(set) var capturedImage: UIImage?
    @Published private(set) var overlayLines: [RecognizedLine] = []
    @Published private(set) var overlayBarcodes: [DetectedBarcode] = []
    @Published private(set) var isFrozen = false
    @Published private(set) var liveHint: String = "ラベル全体をフレームに入れてください"

    let camera = CameraController()

    private let recognizer = VisionRecognizer()
    private let announcer = Announcer()

    // MARK: - 解析キューから触る状態（lock で保護）

    private let lock = NSLock()
    private var masterIndex: [String: Product] = [:]
    private var engine = MatchEngine()
    private var announcementSettings = Announcer.AnnouncementSettings(speechEnabled: true,
                                                                     speakOnSuccess: true,
                                                                     hapticsEnabled: true)
    private var requiredStableFrames = 2
    private var cooldown: TimeInterval = 2.5
    private var continuousScan = true

    private var isProcessing = false
    private var paused = false
    private var manualCaptureRequested = false
    private var candidateKey: String?
    private var candidateCount = 0
    private var lastFinalizedKey: String?
    private var lastFinalizedAt: Date?
    private var cancellables = Set<AnyCancellable>()

    /// 履歴への追加はビュー側（メインアクター）に任せる
    var onFinalize: ((CheckResult) -> Void)?

    var isTorchOn: Bool { camera.isTorchOn }
    var cameraStatus: CameraController.Status { camera.status }

    init() {
        camera.onFrame = { [weak self] buffer in
            self?.handle(buffer: buffer)
        }
        // CameraController は入れ子の ObservableObject なので、変更を自前で中継する
        camera.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - 外部から

    func start() {
        lock.lock(); paused = false; lock.unlock()
        camera.start()
    }

    func stop() {
        camera.stop()
        announcer.stop()
    }

    /// マスタ・設定の変更をスキャン側に反映する。
    func apply(master: [String: Product], settings: AppSettings) {
        lock.lock()
        masterIndex = master
        engine.options = settings.options
        announcementSettings = Announcer.AnnouncementSettings(speechEnabled: settings.speechEnabled,
                                                             speakOnSuccess: settings.speakOnSuccess,
                                                             hapticsEnabled: settings.hapticsEnabled)
        requiredStableFrames = max(1, settings.stabilityFrames)
        cooldown = max(0, settings.cooldownSeconds)
        continuousScan = settings.continuousScan
        lock.unlock()
    }

    /// 結果を閉じて次のラベルへ。
    func reset() {
        lock.lock()
        paused = false
        candidateKey = nil
        candidateCount = 0
        lastFinalizedKey = nil
        lastFinalizedAt = nil
        lock.unlock()

        DispatchQueue.main.async {
            self.result = nil
            self.capturedImage = nil
            self.isFrozen = false
            self.liveHint = "ラベル全体をフレームに入れてください"
        }
    }

    /// シャッターボタン。今のフレームで 1 回だけ強制的に判定する。
    func captureNow() {
        lock.lock()
        manualCaptureRequested = true
        paused = false
        lock.unlock()
    }

    func toggleTorch() { camera.toggleTorch() }

    func replay() {
        guard let result else { return }
        announcer.speak(result.spokenText)
    }

    // MARK: - フレーム解析（video queue 上）

    private func handle(buffer: CVPixelBuffer) {
        lock.lock()
        let manual = manualCaptureRequested
        if (paused && !manual) || isProcessing {
            lock.unlock()
            return
        }
        if !manual, let lastFinalizedAt, Date().timeIntervalSince(lastFinalizedAt) < cooldown {
            lock.unlock()
            return
        }
        isProcessing = true
        let index = masterIndex
        let currentEngine = engine
        let required = manual ? 1 : requiredStableFrames
        lock.unlock()

        defer {
            lock.lock()
            isProcessing = false
            lock.unlock()
        }

        let label = recognizer.recognize(pixelBuffer: buffer)
        let checked = currentEngine.check(label: label, master: index)

        DispatchQueue.main.async {
            self.overlayLines = label.lines
            self.overlayBarcodes = label.barcodes
            if self.result == nil {
                self.liveHint = self.hint(for: checked, label: label)
            }
        }

        guard checked.verdict.isFinal || manual else {
            // バーコードが外れた＝次の商品へ移ったとみなし、同一ラベル判定をリセットする
            lock.lock()
            candidateKey = nil
            candidateCount = 0
            lastFinalizedKey = nil
            lock.unlock()
            return
        }

        let key = stabilityKey(for: checked)
        lock.lock()
        if candidateKey == key {
            candidateCount += 1
        } else {
            candidateKey = key
            candidateCount = 1
        }
        let reached = candidateCount >= required
        let repeatedSameLabel = !manual && key == lastFinalizedKey
        if reached {
            candidateKey = nil
            candidateCount = 0
            manualCaptureRequested = false
            if !repeatedSameLabel {
                lastFinalizedKey = key
                lastFinalizedAt = Date()
                if !continuousScan { paused = true }
            }
        }
        let settings = announcementSettings
        let shouldFreeze = reached && !continuousScan
        lock.unlock()

        guard reached, !repeatedSameLabel else { return }

        let image = recognizer.makeImage(from: buffer)
        announcer.announce(checked, settings: settings)

        DispatchQueue.main.async {
            self.result = checked
            self.capturedImage = image
            self.isFrozen = shouldFreeze
            self.onFinalize?(checked)
        }
    }

    /// 「同じ判定が続いているか」を見るためのキー。
    /// 商品と NG 項目の組み合わせが変わったらカウントをやり直す。
    private func stabilityKey(for result: CheckResult) -> String {
        let fields = result.fields
            .filter { $0.status != .ok }
            .map { "\($0.field):\($0.status.rawValue)" }
            .sorted()
            .joined(separator: ",")
        return [result.verdict.rawValue, result.barcode ?? "-", fields].joined(separator: "|")
    }

    private func hint(for result: CheckResult, label: ParsedLabel) -> String {
        switch result.verdict {
        case .noBarcode:
            return label.lines.isEmpty
                ? "ラベルにカメラを近づけてください"
                : "バーコードが写るようにしてください"
        case .unknownProduct:
            return "マスタに無いバーコードです"
        default:
            return "判定中…"
        }
    }
}
