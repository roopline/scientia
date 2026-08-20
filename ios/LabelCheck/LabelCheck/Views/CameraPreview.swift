import AVFoundation
import SwiftUI

/// AVCaptureVideoPreviewLayer を SwiftUI に載せるためのラッパー。
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// 検出枠を重ねるために、生成したレイヤーを呼び出し側へ渡す
    var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?
    /// タップされた位置（0...1 のデバイス座標）
    var onTapToFocus: ((CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTapToFocus
        onLayerReady?(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.onTap = onTapToFocus
    }

    final class PreviewView: UIView {
        var onTap: ((CGPoint) -> Void)?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // layerClass で指定しているため必ず成功する
            layer as! AVCaptureVideoPreviewLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(recognizer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            let point = recognizer.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
            onTap?(devicePoint)
        }
    }
}
