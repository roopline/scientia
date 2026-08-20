import Foundation

/// 照合の閾値やチェック対象の設定。設定画面から変更でき、UserDefaults に保存される。
struct MatchOptions: Codable, Hashable {
    /// 商品名がこの類似度以上なら「一致」とみなす（0.0...1.0）
    var nameSimilarityThreshold: Double = 0.82
    /// 商品名がここまでは落ちても「要確認」で止める（これ未満は NG）
    var nameWarningThreshold: Double = 0.60
    var checkPrice: Bool = true
    var checkNetWeight: Bool = true
    var checkAllergens: Bool = true
    var checkExpiry: Bool = false
    /// 期限が今日から何日以内なら警告するか
    var expiryWarningDays: Int = 0
    /// インストアバーコードの価格を照合に使うか
    var useInStorePrice: Bool = true
    var inStoreRule: InStoreBarcodeRule = .standard

    static let `default` = MatchOptions()
}

/// マスタとラベル読み取り結果を突き合わせて OK / NG を出す本体。
struct MatchEngine {
    var options: MatchOptions = .default

    func check(label: ParsedLabel, master: [String: Product], now: Date = Date()) -> CheckResult {
        guard let barcode = primaryBarcode(in: label) else {
            return CheckResult(verdict: .noBarcode, barcode: nil, productCode: nil,
                               productName: nil, fields: [], rawText: label.joinedText)
        }

        let keys = BarcodeUtil.lookupKeys(for: barcode.payload, rule: options.inStoreRule)
        guard let product = keys.compactMap({ master[$0] }).first else {
            return CheckResult(verdict: .unknownProduct, barcode: barcode.payload, productCode: nil,
                               productName: nil, fields: [], rawText: label.joinedText)
        }

        var fields: [FieldCheck] = []
        fields.append(nameCheck(product: product, label: label))
        if options.checkPrice, let priceField = priceCheck(product: product, label: label, barcode: barcode.payload) {
            fields.append(priceField)
        }
        if options.checkNetWeight, let weightField = netWeightCheck(product: product, label: label) {
            fields.append(weightField)
        }
        if options.checkAllergens {
            fields.append(contentsOf: allergenChecks(product: product, label: label))
        }
        fields.append(contentsOf: keywordChecks(product: product, label: label))
        if options.checkExpiry, let expiryField = expiryCheck(label: label, now: now) {
            fields.append(expiryField)
        }

        let verdict: Verdict
        if fields.contains(where: { $0.status == .mismatch && $0.isCritical }) {
            verdict = .ng
        } else if fields.contains(where: { $0.status != .ok }) {
            verdict = .warning
        } else {
            verdict = .ok
        }

        return CheckResult(verdict: verdict,
                           barcode: barcode.payload,
                           productCode: product.code,
                           productName: product.name,
                           fields: fields,
                           rawText: label.joinedText)
    }

    /// 面積がもっとも大きい（＝手前にある）バーコードを採用する。
    private func primaryBarcode(in label: ParsedLabel) -> DetectedBarcode? {
        label.barcodes.max { a, b in
            (a.boundingBox.width * a.boundingBox.height) < (b.boundingBox.width * b.boundingBox.height)
        }
    }

    // MARK: - 各項目

    private func nameCheck(product: Product, label: ParsedLabel) -> FieldCheck {
        var best = (text: "", score: 0.0)
        // 候補行ごとの比較と、全文に対する部分一致の両方を見る
        for candidate in label.nameCandidates {
            let score = max(TextNormalizer.similarity(candidate, product.name),
                            TextNormalizer.bestPartialSimilarity(candidate, product.name))
            if score > best.score { best = (candidate, score) }
        }
        let wholeTextScore = TextNormalizer.bestPartialSimilarity(label.joinedText, product.name)
        if TextNormalizer.contains(label.joinedText, product.name) {
            best = (best.score >= 0.999 ? best.text : (label.nameCandidates.first ?? product.name), 1.0)
        } else if wholeTextScore > best.score {
            best = (best.text.isEmpty ? (label.nameCandidates.first ?? "") : best.text, wholeTextScore)
        }

        let status: FieldStatus
        if best.score >= options.nameSimilarityThreshold {
            status = .ok
        } else if best.score >= options.nameWarningThreshold {
            status = .warning
        } else {
            status = .mismatch
        }

        return FieldCheck(field: "商品名",
                          expected: product.name,
                          found: best.text.isEmpty ? nil : best.text,
                          status: status,
                          detail: String(format: "一致率 %.0f%%", best.score * 100),
                          isCritical: true)
    }

    private func priceCheck(product: Product, label: ParsedLabel, barcode: String) -> FieldCheck? {
        guard product.priceTaxIncluded != nil || product.priceBody != nil else { return nil }

        var found = label.prices
        // インストアバーコードに価格が埋め込まれている場合はそれも候補に加える
        if options.useInStorePrice,
           let decoded = BarcodeUtil.decodeInStore(TextNormalizer.digitsOnly(barcode), rule: options.inStoreRule),
           let price = decoded.price, price > 0 {
            found.append(DetectedPrice(value: price, kind: .unknown, source: "バーコード"))
        }

        let expected = product.priceSummary
        guard !found.isEmpty else {
            return FieldCheck(field: "価格", expected: expected, found: nil, status: .warning,
                              detail: "価格を読み取れませんでした", isCritical: true)
        }

        let taxIncludedMatch = product.priceTaxIncluded.map { expectedValue in
            found.contains { $0.value == expectedValue && $0.kind != .body }
        } ?? true
        let bodyMatch = product.priceBody.map { expectedValue in
            found.contains { $0.value == expectedValue && $0.kind != .taxIncluded }
        } ?? true

        let foundText = found.map { "\($0.kind.rawValue)\($0.value)円" }.joined(separator: " / ")
        if taxIncludedMatch && bodyMatch {
            return FieldCheck(field: "価格", expected: expected, found: foundText, status: .ok,
                              detail: nil, isCritical: true)
        }
        // 種別（税込/本体）が読めていないだけで金額自体は載っている場合は要確認に落とす
        let anyValueMatches = [product.priceTaxIncluded, product.priceBody]
            .compactMap { $0 }
            .contains { value in found.contains { $0.value == value } }
        return FieldCheck(field: "価格",
                          expected: expected,
                          found: foundText,
                          status: anyValueMatches ? .warning : .mismatch,
                          detail: anyValueMatches ? "税込/本体の区別が読み取れません" : "金額が一致しません",
                          isCritical: true)
    }

    private func netWeightCheck(product: Product, label: ParsedLabel) -> FieldCheck? {
        guard let expected = product.netWeight, !expected.isEmpty else { return nil }
        let matched = label.netWeights.first { TextNormalizer.normalize($0) == TextNormalizer.normalize(expected) }
            ?? (TextNormalizer.contains(label.joinedText, expected) ? expected : nil)
        if let matched {
            return FieldCheck(field: "内容量", expected: expected, found: matched, status: .ok,
                              detail: nil, isCritical: false)
        }
        let foundText = label.netWeights.joined(separator: " / ")
        return FieldCheck(field: "内容量",
                          expected: expected,
                          found: foundText.isEmpty ? nil : foundText,
                          status: foundText.isEmpty ? .warning : .mismatch,
                          detail: foundText.isEmpty ? "内容量を読み取れませんでした" : nil,
                          isCritical: false)
    }

    private func allergenChecks(product: Product, label: ParsedLabel) -> [FieldCheck] {
        product.allergens.map { allergen in
            let present = TextNormalizer.contains(label.joinedText, allergen)
            return FieldCheck(field: "アレルゲン(\(allergen))",
                              expected: allergen,
                              found: present ? allergen : nil,
                              status: present ? .ok : .mismatch,
                              detail: present ? nil : "ラベルに印字されていません",
                              isCritical: true)
        }
    }

    private func keywordChecks(product: Product, label: ParsedLabel) -> [FieldCheck] {
        product.keywords.map { keyword in
            let present = TextNormalizer.contains(label.joinedText, keyword)
            return FieldCheck(field: "必須表記(\(keyword))",
                              expected: keyword,
                              found: present ? keyword : nil,
                              status: present ? .ok : .mismatch,
                              detail: present ? nil : "ラベルに印字されていません",
                              isCritical: true)
        }
    }

    private func expiryCheck(label: ParsedLabel, now: Date) -> FieldCheck? {
        let expiryDates = label.dates.filter { $0.kind == .consumeBy || $0.kind == .bestBefore || $0.kind == .unknown }
        guard let nearest = expiryDates.compactMap({ date -> (DetectedDate, Date)? in
            guard let resolved = date.resolvedDate(reference: now) else { return nil }
            return (date, resolved)
        }).min(by: { $0.1 < $1.1 }) else {
            return FieldCheck(field: "期限", expected: "本日以降", found: nil, status: .warning,
                              detail: "期限を読み取れませんでした", isCritical: false)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: nearest.1)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0

        if days < 0 {
            return FieldCheck(field: "期限", expected: "本日以降", found: nearest.0.displayText,
                              status: .mismatch, detail: "期限切れです", isCritical: true)
        }
        if days <= options.expiryWarningDays {
            return FieldCheck(field: "期限", expected: "本日以降", found: nearest.0.displayText,
                              status: .warning, detail: "残り \(days) 日", isCritical: false)
        }
        return FieldCheck(field: "期限", expected: "本日以降", found: nearest.0.displayText,
                          status: .ok, detail: "残り \(days) 日", isCritical: false)
    }
}
