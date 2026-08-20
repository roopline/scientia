import AVFoundation
import SwiftUI
import UIKit

/// Vision の座標（正規化・左下原点）をプレビュー上の座標に変換するための橋渡し。
final class PreviewLayerProxy: ObservableObject {
    weak var layer: AVCaptureVideoPreviewLayer?

    func rect(for boundingBox: CGRect) -> CGRect? {
        guard let layer else { return nil }
        let metadataRect = CGRect(x: boundingBox.minX,
                                  y: 1 - boundingBox.maxY,
                                  width: boundingBox.width,
                                  height: boundingBox.height)
        let converted = layer.layerRectConverted(fromMetadataOutputRect: metadataRect)
        return converted.isNull || converted.isInfinite ? nil : converted
    }
}

struct ScanView: View {
    @EnvironmentObject private var master: ProductMasterStore
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = ScanViewModel()
    @StateObject private var proxy = PreviewLayerProxy()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: model.camera.session,
                          onLayerReady: { layer in proxy.layer = layer },
                          onTapToFocus: { point in model.camera.focus(at: point) })
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) { detectionOverlay }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomArea
            }

            if let message = cameraProblem {
                cameraProblemView(message)
            }
        }
        .statusBarHidden(false)
        .onAppear {
            model.onFinalize = { result in history.append(result) }
            model.apply(master: master.index, settings: settings)
            model.start()
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
        .onChange(of: master.index) { _, index in
            model.apply(master: index, settings: settings)
        }
        .onReceive(settings.objectWillChange) { _ in
            // 設定変更を次のフレームから反映させる
            DispatchQueue.main.async { model.apply(master: master.index, settings: settings) }
        }
    }

    // MARK: - 部品

    private var cameraProblem: String? {
        switch model.cameraStatus {
        case .denied:
            return "カメラの使用が許可されていません。設定 > LabelCheck からカメラを ON にしてください。"
        case .failed(let message):
            return message
        case .idle, .running:
            return nil
        }
    }

    private func cameraProblemView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown").font(.largeTitle)
            Text(message).multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("設定を開く", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label(model.result?.verdict.title ?? model.liveHint,
                  systemImage: model.result == nil ? "text.viewfinder" : "checkmark.seal")
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer(minLength: 0)

            Button {
                model.toggleTorch()
            } label: {
                Image(systemName: model.isTorchOn ? "bolt.fill" : "bolt.slash")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var detectionOverlay: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                ForEach(model.overlayBarcodes) { barcode in
                    if let rect = proxy.rect(for: barcode.boundingBox) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                ForEach(model.overlayLines) { line in
                    if let rect = proxy.rect(for: line.boundingBox) {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.cyan.opacity(0.55), lineWidth: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 12) {
            if master.products.isEmpty {
                masterEmptyNotice
            }
            if let result = model.result {
                ResultCard(result: result,
                           image: model.capturedImage,
                           onNext: { model.reset() },
                           onReplay: { model.replay() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                shutterButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.18), value: model.result)
    }

    private var masterEmptyNotice: some View {
        Label("商品マスタが未読込です。「商品マスタ」タブから CSV を読み込んでください。",
              systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var shutterButton: some View {
        VStack(spacing: 8) {
            Text(settings.continuousScan ? "かざすだけで自動判定します" : "ボタンを押して判定します")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Button {
                model.captureNow()
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 70, height: 70)
                    Circle().stroke(.white.opacity(0.6), lineWidth: 3).frame(width: 82, height: 82)
                    Image(systemName: "text.viewfinder")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.black)
                }
            }
            .accessibilityLabel("いま写っているラベルを判定")
        }
    }
}
