import Foundation

/// インストアマーキング（プリンタが値段を埋め込むタイプのバーコード）の読み方。
/// 店舗ごとに桁割りが違うため設定で切り替えられるようにしている。
struct InStoreBarcodeRule: Codable, Hashable {
    /// 商品コード部の開始位置と桁数（0 始まり）
    var itemCodeStart: Int
    var itemCodeLength: Int
    /// 価格部の開始位置と桁数
    var priceStart: Int
    var priceLength: Int

    /// フラグ2桁(20〜29) + 商品コード5桁 + 価格5桁 + CD（もっとも普及した形）
    static let standard = InStoreBarcodeRule(itemCodeStart: 2, itemCodeLength: 5,
                                             priceStart: 7, priceLength: 5)
    /// フラグ2桁 + 商品コード5桁 + プライスチェックデジタル1桁 + 価格4桁 + CD
    static let withPriceCheckDigit = InStoreBarcodeRule(itemCodeStart: 2, itemCodeLength: 5,
                                                        priceStart: 8, priceLength: 4)
}

enum BarcodeUtil {

    /// EAN-13 / EAN-8 のチェックディジットを検証する。
    static func isValidEAN(_ code: String) -> Bool {
        let digits = code.compactMap { $0.wholeNumberValue }
        guard digits.count == code.count, digits.count == 13 || digits.count == 8 else { return false }
        let body = digits.dropLast()
        var sum = 0
        // 右端（チェックディジットの左隣）から 3,1,3,1... の重み
        for (offset, digit) in body.reversed().enumerated() {
            sum += digit * (offset % 2 == 0 ? 3 : 1)
        }
        let check = (10 - (sum % 10)) % 10
        return check == digits.last
    }

    /// インストアマーキング（先頭 2 桁が 02 / 20〜29）か。
    static func isInStore(_ code: String) -> Bool {
        guard code.count == 13 else { return false }
        let prefix = String(code.prefix(2))
        return prefix == "02" || (prefix.first == "2" && prefix.allSatisfy { $0.isNumber })
    }

    /// インストアバーコードから商品コードと価格を取り出す。
    static func decodeInStore(_ code: String, rule: InStoreBarcodeRule) -> (itemCode: String, price: Int?)? {
        guard isInStore(code) else { return nil }
        let chars = Array(code)
        func slice(_ start: Int, _ length: Int) -> String? {
            guard start >= 0, length > 0, start + length <= chars.count else { return nil }
            return String(chars[start..<(start + length)])
        }
        guard let itemCode = slice(rule.itemCodeStart, rule.itemCodeLength) else { return nil }
        let price = slice(rule.priceStart, rule.priceLength).flatMap { Int($0) }
        return (itemCode, price)
    }

    /// マスタ照合に使うキーの候補を、優先度順に返す。
    /// （JAN そのもの → インストアの商品コード → 先頭 0 を落とした形）
    static func lookupKeys(for payload: String, rule: InStoreBarcodeRule) -> [String] {
        let code = TextNormalizer.digitsOnly(payload)
        var keys: [String] = [code]
        if let decoded = decodeInStore(code, rule: rule) {
            keys.append(decoded.itemCode)
            if let trimmed = trimLeadingZeros(decoded.itemCode) { keys.append(trimmed) }
        }
        if let trimmed = trimLeadingZeros(code) { keys.append(trimmed) }
        var seen = Set<String>()
        return keys.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func trimLeadingZeros(_ s: String) -> String? {
        let trimmed = String(s.drop { $0 == "0" })
        return trimmed.isEmpty || trimmed == s ? nil : trimmed
    }
}
