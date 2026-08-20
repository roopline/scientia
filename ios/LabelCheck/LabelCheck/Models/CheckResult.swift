import Foundation
import SwiftUI

enum FieldStatus: String, Codable {
    case ok         // 一致
    case warning    // 読み取れない／要目視
    case mismatch   // 不一致（NG）

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .mismatch: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .mismatch: return .red
        }
    }
}

/// 項目ごとの照合結果。
struct FieldCheck: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 項目名（商品名 / 税込価格 …）
    var field: String
    /// マスタ側の値
    var expected: String
    /// ラベルから読み取った値（読めなければ nil）
    var found: String?
    var status: FieldStatus
    /// 補足（一致率など）
    var detail: String?
    /// この項目が NG のとき全体を NG にするか
    var isCritical: Bool
}

enum Verdict: String, Codable {
    case ok             // 全項目一致
    case warning        // 読み取れない項目あり（要目視）
    case ng             // 不一致あり＝貼り間違いの可能性
    case unknownProduct // バーコードはあるがマスタに無い
    case noBarcode      // バーコード未検出

    var title: String {
        switch self {
        case .ok: return "OK 一致"
        case .warning: return "要確認"
        case .ng: return "NG 不一致"
        case .unknownProduct: return "マスタ未登録"
        case .noBarcode: return "バーコード未検出"
        }
    }

    var tint: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .ng, .unknownProduct: return .red
        case .noBarcode: return .gray
        }
    }

    var isFinal: Bool {
        switch self {
        case .ok, .warning, .ng, .unknownProduct: return true
        case .noBarcode: return false
        }
    }
}

/// 1 回の照合結果。履歴にもそのまま保存する。
struct CheckResult: Identifiable, Codable, Hashable {
    var id = UUID()
    var timestamp: Date = Date()
    var verdict: Verdict
    var barcode: String?
    var productCode: String?
    var productName: String?
    var fields: [FieldCheck] = []
    /// OCR 全文（後から検証できるように残す）
    var rawText: String = ""

    var okCount: Int { fields.filter { $0.status == .ok }.count }
    var ngCount: Int { fields.filter { $0.status == .mismatch }.count }

    /// 音声読み上げ用の文言。
    var spokenText: String {
        switch verdict {
        case .ok:
            return "オーケー。\(productName ?? "商品")"
        case .warning:
            let f = fields.filter { $0.status == .warning }.map(\.field).joined(separator: "、")
            return "要確認。\(f.isEmpty ? "目視で確認してください" : f + "が読み取れません")"
        case .ng:
            let f = fields.filter { $0.status == .mismatch }.map(\.field).joined(separator: "、")
            return "エラー。\(f.isEmpty ? "ラベルが一致しません" : f + "が一致しません")"
        case .unknownProduct:
            return "エラー。マスタに登録されていない商品です"
        case .noBarcode:
            return "バーコードが読み取れません"
        }
    }
}
