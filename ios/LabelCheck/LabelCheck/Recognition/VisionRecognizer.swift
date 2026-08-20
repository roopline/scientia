import CoreImage
import Foundation
import UIKit
import Vision

/// Vision でバーコードと日本語テキストを 1 フレームから読み取る。
final class VisionRecognizer {

    private let textRequest: VNRecognizeTextRequest
    private let barcodeRequest: VNDetectBarcodesRequest
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init() {
        textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        // 日本語優先。英数字（価格・コード）も拾えるよう en-US を併用する。
        textRequest.recognitionLanguages = ["ja-JP", "en-US"]
        // ラベルは固有名詞や記号が多く、言語補正が誤変換の原因になるため切る
        textRequest.usesLanguageCorrection = false
        textRequest.minimumTextHeight = 0.012

        barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.ean13, .ean8, .upce, .code128, .itf14, .i2of5, .qr, .dataMatrix]
    }

    /// 1 フレームを解析する。呼び出し側のキューで同期実行される。
    func recognize(pixelBuffer: CVPixelBuffer,
                   orientation: CGImagePropertyOrientation = .up,
                   regionOfInterest: CGRect? = nil) -> ParsedLabel {
        if let regionOfInterest {
            textRequest.regionOfInterest = regionOfInterest
            barcodeRequest.regionOfInterest = regionOfInterest
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([textRequest, barcodeRequest])
        } catch {
            return ParsedLabel()
        }

        let lines: [RecognizedLine] = (textRequest.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string,
                                  confidence: candidate.confidence,
                                  boundingBox: observation.boundingBox)
        }

        let barcodes: [DetectedBarcode] = (barcodeRequest.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            return DetectedBarcode(payload: payload,
                                   symbology: observation.symbology.rawValue,
                                   boundingBox: observation.boundingBox)
        }

        return LabelParser.parse(lines: lines, barcodes: barcodes)
    }

    /// 判定確定時のフレームを、履歴表示用の小さな画像に変換する。
    func makeImage(from pixelBuffer: CVPixelBuffer, maxDimension: CGFloat = 900) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1.0, maxDimension / max(extent.width, extent.height))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
