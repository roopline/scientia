import CoreGraphics
import Foundation

/// OCR で読み取った 1 行。
struct RecognizedLine: Identifiable, Hashable {
    let id = UUID()
    /// 認識文字列（そのまま）
    let text: String
    /// Vision の信頼度 0.0...1.0
    let confidence: Float
    /// 正規化画像座標（左下原点）
    let boundingBox: CGRect

    /// 行の高さ。商品名（＝一番大きい文字）の推定に使う。
    var relativeHeight: CGFloat { boundingBox.height }
}

/// 読み取ったバーコード。
struct DetectedBarcode: Identifiable, Hashable {
    let id = UUID()
    let payload: String
    let symbology: String
    let boundingBox: CGRect
}

/// ラベル上の価格表記。
struct DetectedPrice: Hashable {
    enum Kind: String, Hashable {
        case taxIncluded = "税込"
        case body = "本体"
        case unknown = "価格"
    }
    let value: Int
    let kind: Kind
    let source: String
}

/// ラベル上の日付表記。
struct DetectedDate: Hashable {
    enum Kind: String, Hashable {
        case consumeBy = "消費期限"
        case bestBefore = "賞味期限"
        case packedOn = "加工日"
        case unknown = "日付"
    }
    let kind: Kind
    let year: Int?
    let month: Int
    let day: Int
    let source: String

    var displayText: String {
        if let year { return String(format: "%04d.%02d.%02d", year, month, day) }
        return String(format: "%02d.%02d", month, day)
    }

    /// 西暦に解決した日付（年が 2 桁 / 省略の場合は基準日から補完）。
    func resolvedDate(reference: Date = Date(), calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.month = month
        components.day = day
        if let year {
            components.year = year < 100 ? 2000 + year : year
        } else {
            let refYear = calendar.component(.year, from: reference)
            let refMonth = calendar.component(.month, from: reference)
            // 年またぎ（12月に 1月の期限）を考慮
            components.year = (refMonth == 12 && month == 1) ? refYear + 1 : refYear
        }
        return calendar.date(from: components)
    }
}

/// 1 フレーム分の解析結果。
struct ParsedLabel {
    var lines: [RecognizedLine] = []
    var barcodes: [DetectedBarcode] = []
    var nameCandidates: [String] = []
    var prices: [DetectedPrice] = []
    var netWeights: [String] = []
    var dates: [DetectedDate] = []
    /// 全行を連結した文字列（正規化前）
    var joinedText: String = ""

    var isEmpty: Bool { lines.isEmpty && barcodes.isEmpty }
}
