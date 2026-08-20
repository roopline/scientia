import Foundation

/// OCR の行データから「商品名候補・価格・内容量・期限」を取り出す。
enum LabelParser {

    static func parse(lines: [RecognizedLine], barcodes: [DetectedBarcode]) -> ParsedLabel {
        var label = ParsedLabel()
        label.lines = lines
        label.barcodes = barcodes
        label.joinedText = lines.map(\.text).joined(separator: "\n")
        label.nameCandidates = nameCandidates(from: lines)
        label.prices = prices(from: lines)
        label.netWeights = netWeights(from: lines)
        label.dates = dates(from: lines)
        return label
    }

    // MARK: - 商品名

    /// 値付けラベルでは商品名がもっとも大きく印字されるため、
    /// 文字高さの大きい行を優先しつつ、価格や日付らしい行を除外して候補にする。
    static func nameCandidates(from lines: [RecognizedLine], limit: Int = 6) -> [String] {
        let candidates = lines
            .filter { line in
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 2 else { return false }
                if isMostlyDigits(text) { return false }
                if noiseKeywords.contains(where: { text.contains($0) }) { return false }
                return true
            }
            .sorted { $0.relativeHeight > $1.relativeHeight }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }

        var seen = Set<String>()
        var result: [String] = []
        for candidate in candidates where seen.insert(TextNormalizer.normalize(candidate)).inserted {
            result.append(candidate)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - 価格

    static func prices(from lines: [RecognizedLine]) -> [DetectedPrice] {
        var found: [DetectedPrice] = []
        let texts = lines.map { $0.text.precomposedStringWithCompatibilityMapping }
        for (index, text) in texts.enumerated() {
            let previousLine = index > 0 ? texts[index - 1] : ""
            for match in priceMatches(in: text) {
                // 「本体 553円 税込 598円」のように 1 行に複数あるので、
                // その金額の直前にある語で税込／本体を決める
                let prefix = String(text[text.startIndex..<match.start])
                var kind = priceKind(in: prefix)
                if kind == .unknown {
                    // 「税込」だけが前の行にある 2 行組みのレイアウト
                    kind = priceKind(in: previousLine)
                }
                found.append(DetectedPrice(value: match.value, kind: kind, source: text))
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert("\($0.kind.rawValue)-\($0.value)").inserted }
    }

    private static func priceMatches(in text: String) -> [(value: Int, start: String.Index)] {
        var results: [(value: Int, start: String.Index)] = []
        for pattern in pricePatterns {
            for match in matches(pattern: pattern, in: text) {
                guard let raw = group(match, 1, in: text),
                      let range = Range(match.range, in: text) else { continue }
                let cleaned = raw.replacingOccurrences(of: ",", with: "")
                guard let value = Int(cleaned), value > 0, value < 1_000_000 else { continue }
                results.append((value, range.lowerBound))
            }
        }
        return results.sorted { $0.start < $1.start }
    }

    /// 直前の文字列の中で、最後に現れた語で種別を決める。
    private static func priceKind(in prefix: String) -> DetectedPrice.Kind {
        let normalized = TextNormalizer.normalize(prefix)
        let taxIncluded = lastPosition(of: ["税込", "込価格", "税込み"], in: normalized)
        let body = lastPosition(of: ["本体", "税抜", "税別"], in: normalized)
        switch (taxIncluded, body) {
        case let (t?, b?): return t >= b ? .taxIncluded : .body
        case (_?, nil): return .taxIncluded
        case (nil, _?): return .body
        default: return .unknown
        }
    }

    private static func lastPosition(of keywords: [String], in normalizedText: String) -> Int? {
        var best: Int?
        for keyword in keywords {
            let needle = TextNormalizer.normalize(keyword)
            guard !needle.isEmpty,
                  let range = normalizedText.range(of: needle, options: .backwards) else { continue }
            let position = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
            best = max(best ?? position, position)
        }
        return best
    }

    // MARK: - 内容量

    static func netWeights(from lines: [RecognizedLine]) -> [String] {
        var results: [String] = []
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*(kg|g|ml|mL|L|入|枚|個|本|食|串|切|尾|袋|パック|人前)"
        for line in lines {
            let text = line.text.precomposedStringWithCompatibilityMapping
            for match in matches(pattern: pattern, in: text) {
                guard let amount = group(match, 1, in: text), let unit = group(match, 2, in: text) else { continue }
                results.append(amount + unit)
            }
        }
        var seen = Set<String>()
        return results.filter { seen.insert(TextNormalizer.normalize($0)).inserted }
    }

    // MARK: - 期限

    static func dates(from lines: [RecognizedLine]) -> [DetectedDate] {
        var results: [DetectedDate] = []
        let texts = lines.map { $0.text.precomposedStringWithCompatibilityMapping }
        // 「消費期限」だけの行の次の行に日付が来るレイアウトが多いので 2 行を連結して見る
        for (index, text) in texts.enumerated() {
            let context = text + " " + (index + 1 < texts.count ? texts[index + 1] : "")
            let kind = dateKind(in: context)
            for pattern in datePatterns {
                for match in matches(pattern: pattern, in: context) {
                    guard let parsed = makeDate(match: match, in: context, kind: kind) else { continue }
                    results.append(parsed)
                }
            }
        }
        var seen = Set<String>()
        return results.filter { seen.insert("\($0.kind.rawValue)-\($0.displayText)").inserted }
    }

    private static func dateKind(in context: String) -> DetectedDate.Kind {
        let normalized = TextNormalizer.normalize(context)
        if normalized.contains(TextNormalizer.normalize("消費期限")) { return .consumeBy }
        if normalized.contains(TextNormalizer.normalize("賞味期限")) { return .bestBefore }
        if normalized.contains(TextNormalizer.normalize("加工日")) || normalized.contains(TextNormalizer.normalize("製造日")) { return .packedOn }
        return .unknown
    }

    private static func makeDate(match: NSTextCheckingResult, in text: String, kind: DetectedDate.Kind) -> DetectedDate? {
        let groups = (1..<match.numberOfRanges).compactMap { group(match, $0, in: text) }
        let numbers = groups.compactMap { Int($0) }
        switch numbers.count {
        case 3:
            let (rawYear, m, d) = (numbers[0], numbers[1], numbers[2])
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            let year = rawYear < 100 ? 2000 + rawYear : rawYear
            return DetectedDate(kind: kind, year: year, month: m, day: d, source: matchedString(match, in: text))
        case 2:
            let (m, d) = (numbers[0], numbers[1])
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            return DetectedDate(kind: kind, year: nil, month: m, day: d, source: matchedString(match, in: text))
        default:
            return nil
        }
    }

    // MARK: - 正規表現ヘルパー

    private static let pricePatterns = [
        "[¥￥]\\s*([0-9][0-9,]*)",
        "([0-9][0-9,]*)\\s*円"
    ]

    private static let datePatterns = [
        "([0-9]{4})\\s*[./年-]\\s*([0-9]{1,2})\\s*[./月-]\\s*([0-9]{1,2})",
        "([0-9]{2})\\s*[./-]\\s*([0-9]{1,2})\\s*[./-]\\s*([0-9]{1,2})",
        "([0-9]{1,2})\\s*月\\s*([0-9]{1,2})\\s*日"
    ]

    private static let noiseKeywords = ["税込", "本体", "消費期限", "賞味期限", "加工日", "円", "100gあたり"]

    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        guard let created = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = created
        return created
    }

    private static func matches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = regex(pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func matchedString(_ match: NSTextCheckingResult, in text: String) -> String {
        guard let range = Range(match.range, in: text) else { return "" }
        return String(text[range])
    }

    private static func isMostlyDigits(_ text: String) -> Bool {
        let stripped = text.filter { !$0.isWhitespace }
        guard !stripped.isEmpty else { return true }
        let digits = stripped.filter { $0.isNumber || $0 == "," || $0 == "." }
        return Double(digits.count) / Double(stripped.count) > 0.6
    }
}
