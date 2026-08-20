import Foundation

/// 全角/半角・ひらがな/カタカナ・記号の揺れを吸収して比較できる形にする。
enum TextNormalizer {

    /// 比較用の正規化。全角→半角、ひらがな→カタカナ、小文字化、空白・記号除去。
    static func normalize(_ input: String) -> String {
        // NFKC: 全角英数字・半角カナ・㌘ などを標準形へ
        var s = input.precomposedStringWithCompatibilityMapping
        s = s.applyingTransform(.hiraganaToKatakana, reverse: false) ?? s
        s = s.lowercased()
        s = s.replacingOccurrences(of: "\u{FF65}", with: "")   // 半角中黒の残り
        let scalars = s.unicodeScalars.filter { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
            if separators.contains(scalar) { return false }
            return true
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// 数字だけを取り出す（バーコード・価格用）。
    static func digitsOnly(_ input: String) -> String {
        let s = input.precomposedStringWithCompatibilityMapping
        return s.filter { $0.isNumber }
    }

    /// 正規化した文字列同士の類似度 0.0...1.0（レーベンシュタイン距離ベース）。
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = normalize(a)
        let y = normalize(b)
        if x.isEmpty && y.isEmpty { return 1.0 }
        if x.isEmpty || y.isEmpty { return 0.0 }
        if x == y { return 1.0 }
        let distance = levenshtein(Array(x), Array(y))
        let longest = max(x.count, y.count)
        return 1.0 - (Double(distance) / Double(longest))
    }

    /// b が a を（正規化して）含むか。
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        let n = normalize(needle)
        guard !n.isEmpty else { return false }
        return normalize(haystack).contains(n)
    }

    /// 正規化後の部分一致率。改行や余分な文字で分断された商品名にも効くよう、
    /// 「needle が haystack のどこかにどれだけ近い形で現れるか」を測る
    /// （haystack 側の前後の余りは距離に数えない）。
    static func bestPartialSimilarity(_ haystack: String, _ needle: String) -> Double {
        let h = Array(normalize(haystack))
        let n = Array(normalize(needle))
        guard !h.isEmpty, !n.isEmpty else { return 0.0 }
        let distance = infixDistance(needle: n, haystack: h)
        return max(0.0, 1.0 - (Double(distance) / Double(n.count)))
    }

    /// needle を haystack の部分列として最も安く一致させたときの編集距離。
    private static func infixDistance(needle: [Character], haystack: [Character]) -> Int {
        // 先頭行を 0 で埋めることで、haystack 側の開始位置ずれを無料にする
        var previous = [Int](repeating: 0, count: haystack.count + 1)
        var current = [Int](repeating: 0, count: haystack.count + 1)
        for i in 1...needle.count {
            current[0] = i
            for j in 1...haystack.count {
                let cost = needle[i - 1] == haystack[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1,
                                 current[j - 1] + 1,
                                 previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        // 最終行の最小値＝どこで終わってもよい
        return previous.min() ?? needle.count
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1,        // 削除
                                 current[j - 1] + 1,     // 挿入
                                 previous[j - 1] + cost) // 置換
            }
            previous = current
        }
        return previous[b.count]
    }

    private static let separators: CharacterSet = {
        var set = CharacterSet.punctuationCharacters
        set.formUnion(.symbols)
        set.insert(charactersIn: "・￥¥/()（）[]【】「」<>|_-—ー~〜*＊:：;；,、.。")
        // 「ー」は長音として意味を持つので除外対象から戻す
        set.remove(charactersIn: "ー")
        return set
    }()
}
