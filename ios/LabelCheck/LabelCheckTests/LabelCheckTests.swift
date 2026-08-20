import CoreGraphics
import XCTest
@testable import LabelCheck

final class TextNormalizerTests: XCTestCase {

    func testNormalizeAbsorbsWidthAndKanaVariants() {
        XCTAssertEqual(TextNormalizer.normalize("ﾒﾝﾁｶﾂ"), TextNormalizer.normalize("メンチカツ"))
        XCTAssertEqual(TextNormalizer.normalize("めんちかつ"), TextNormalizer.normalize("メンチカツ"))
        XCTAssertEqual(TextNormalizer.normalize("１００ｇ"), TextNormalizer.normalize("100g"))
        XCTAssertEqual(TextNormalizer.normalize("黒豚 ロースカツ丼"), TextNormalizer.normalize("黒豚ロースカツ丼"))
    }

    func testSimilarityIsHighForSmallOCRErrors() {
        let score = TextNormalizer.similarity("黒豚ロースカツ丼", "黒豚ロースカツ井")
        XCTAssertGreaterThan(score, 0.8)
    }

    func testSimilarityIsLowForDifferentProducts() {
        let score = TextNormalizer.similarity("黒豚ロースカツ丼", "エビフライ")
        XCTAssertLessThan(score, 0.4)
    }

    func testPartialSimilarityFindsNameInsideFullText() {
        let text = "消費期限 26.08.21\n黒豚ロースカツ丼\n本体 553円 税込 598円"
        XCTAssertGreaterThan(TextNormalizer.bestPartialSimilarity(text, "黒豚ロースカツ丼"), 0.95)
    }
}

final class BarcodeUtilTests: XCTestCase {

    func testEANCheckDigit() {
        XCTAssertTrue(BarcodeUtil.isValidEAN("4901234567894"))
        XCTAssertFalse(BarcodeUtil.isValidEAN("4901234567895"))
    }

    func testInStoreDecoding() {
        // フラグ 20 + 商品コード 12345 + 価格 00598 + CD 3
        let decoded = BarcodeUtil.decodeInStore("2012345005983", rule: .standard)
        XCTAssertEqual(decoded?.itemCode, "12345")
        XCTAssertEqual(decoded?.price, 598)
        XCTAssertTrue(BarcodeUtil.isValidEAN("2012345005983"))
    }

    func testInStoreDecodingWithPriceCheckDigit() {
        // フラグ 20 + 商品コード 12345 + PC 0 + 価格 0598 + CD
        let decoded = BarcodeUtil.decodeInStore("2012345005983", rule: .withPriceCheckDigit)
        XCTAssertEqual(decoded?.itemCode, "12345")
        XCTAssertEqual(decoded?.price, 598)
    }

    func testLookupKeysIncludeItemCode() {
        let keys = BarcodeUtil.lookupKeys(for: "2012345005983", rule: .standard)
        XCTAssertTrue(keys.contains("12345"))
        XCTAssertEqual(keys.first, "2012345005983")
    }
}

final class LabelParserTests: XCTestCase {

    private func line(_ text: String, height: CGFloat = 0.03) -> RecognizedLine {
        RecognizedLine(text: text,
                       confidence: 0.9,
                       boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.6, height: height))
    }

    func testPriceExtraction() {
        let label = LabelParser.parse(lines: [line("本体 553円"), line("税込 ¥598")], barcodes: [])
        XCTAssertTrue(label.prices.contains { $0.value == 553 && $0.kind == .body })
        XCTAssertTrue(label.prices.contains { $0.value == 598 && $0.kind == .taxIncluded })
    }

    func testNameCandidatePrefersLargestNonNumericLine() {
        let label = LabelParser.parse(lines: [line("税込 598円", height: 0.02),
                                              line("黒豚ロースカツ丼", height: 0.06),
                                              line("消費期限 26.08.21", height: 0.02)],
                                      barcodes: [])
        XCTAssertEqual(label.nameCandidates.first, "黒豚ロースカツ丼")
    }

    func testDateExtraction() {
        let label = LabelParser.parse(lines: [line("消費期限"), line("26.08.21")], barcodes: [])
        let expiry = label.dates.first { $0.kind == .consumeBy }
        XCTAssertEqual(expiry?.month, 8)
        XCTAssertEqual(expiry?.day, 21)
    }

    func testNetWeightExtraction() {
        let label = LabelParser.parse(lines: [line("内容量 100g")], barcodes: [])
        XCTAssertTrue(label.netWeights.contains { TextNormalizer.normalize($0) == TextNormalizer.normalize("100g") })
    }
}

final class MatchEngineTests: XCTestCase {

    private let product = Product(code: "4901234567894",
                                  name: "黒豚ロースカツ丼",
                                  priceTaxIncluded: 598,
                                  priceBody: 553,
                                  netWeight: "1食",
                                  allergens: ["小麦", "卵"])

    private var master: [String: Product] { [product.code: product] }

    private func label(texts: [String], barcode: String?) -> ParsedLabel {
        let lines = texts.enumerated().map { index, text in
            RecognizedLine(text: text,
                           confidence: 0.9,
                           boundingBox: CGRect(x: 0.1, y: 0.9 - Double(index) * 0.1,
                                               width: 0.6, height: index == 0 ? 0.06 : 0.03))
        }
        let codes = barcode.map {
            [DetectedBarcode(payload: $0, symbology: "VNBarcodeSymbologyEAN13",
                             boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.6, height: 0.1))]
        } ?? []
        return LabelParser.parse(lines: lines, barcodes: codes)
    }

    func testMatchingLabelIsOK() {
        let engine = MatchEngine()
        let result = engine.check(label: label(texts: ["黒豚ロースカツ丼",
                                                       "本体 553円 税込 598円",
                                                       "内容量 1食",
                                                       "原材料 豚肉 小麦 卵"],
                                               barcode: "4901234567894"),
                                  master: master)
        XCTAssertEqual(result.verdict, .ok, "NG項目: \(result.fields.filter { $0.status != .ok })")
    }

    func testWrongProductNameIsNG() {
        let engine = MatchEngine()
        let result = engine.check(label: label(texts: ["エビフライ",
                                                       "本体 553円 税込 598円",
                                                       "内容量 1食",
                                                       "原材料 小麦 卵"],
                                               barcode: "4901234567894"),
                                  master: master)
        XCTAssertEqual(result.verdict, .ng)
        XCTAssertTrue(result.fields.contains { $0.field == "商品名" && $0.status == .mismatch })
    }

    func testWrongPriceIsNG() {
        let engine = MatchEngine()
        let result = engine.check(label: label(texts: ["黒豚ロースカツ丼",
                                                       "本体 460円 税込 498円",
                                                       "内容量 1食",
                                                       "原材料 小麦 卵"],
                                               barcode: "4901234567894"),
                                  master: master)
        XCTAssertEqual(result.verdict, .ng)
        XCTAssertTrue(result.fields.contains { $0.field == "価格" && $0.status == .mismatch })
    }

    func testMissingAllergenIsNG() {
        let engine = MatchEngine()
        let result = engine.check(label: label(texts: ["黒豚ロースカツ丼",
                                                       "本体 553円 税込 598円",
                                                       "内容量 1食",
                                                       "原材料 豚肉 小麦"],
                                               barcode: "4901234567894"),
                                  master: master)
        XCTAssertEqual(result.verdict, .ng)
        XCTAssertTrue(result.fields.contains { $0.field.hasPrefix("アレルゲン(卵)") && $0.status == .mismatch })
    }

    func testUnknownBarcode() {
        let engine = MatchEngine()
        let result = engine.check(label: label(texts: ["黒豚ロースカツ丼"], barcode: "4909999999996"),
                                  master: master)
        XCTAssertEqual(result.verdict, .unknownProduct)
    }

    func testNoBarcode() {
        let engine = MatchEngine()
        let result = engine.check(label: label(texts: ["黒豚ロースカツ丼"], barcode: nil), master: master)
        XCTAssertEqual(result.verdict, .noBarcode)
    }

    func testExpiredDateIsNG() {
        var engine = MatchEngine()
        engine.options.checkExpiry = true
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let result = engine.check(label: label(texts: ["黒豚ロースカツ丼",
                                                       "本体 553円 税込 598円",
                                                       "内容量 1食",
                                                       "原材料 豚肉 小麦 卵",
                                                       "消費期限 2026.08.19"],
                                               barcode: "4901234567894"),
                                  master: master,
                                  now: now)
        XCTAssertEqual(result.verdict, .ng)
        XCTAssertTrue(result.fields.contains { $0.field == "期限" && $0.status == .mismatch })
    }
}

final class MasterImportTests: XCTestCase {

    func testCSVWithJapaneseHeaders() throws {
        let csv = """
        商品コード,商品名,税込価格,本体価格,内容量,アレルゲン,必須表記,備考
        4901234567894,黒豚ロースカツ丼,598,553,1食,小麦/卵,要冷蔵,定番
        4901234567900,"牛肉コロッケ, 2個入",128,119,2個,小麦/乳,,
        """
        let products = try MasterFileImporter.loadCSV(text: csv)
        XCTAssertEqual(products.count, 2)
        let first = try XCTUnwrap(products.first { $0.code == "4901234567894" })
        XCTAssertEqual(first.name, "黒豚ロースカツ丼")
        XCTAssertEqual(first.priceTaxIncluded, 598)
        XCTAssertEqual(first.allergens, ["小麦", "卵"])
        XCTAssertEqual(first.keywords, ["要冷蔵"])
        let second = try XCTUnwrap(products.first { $0.code == "4901234567900" })
        XCTAssertEqual(second.name, "牛肉コロッケ, 2個入")
    }

    func testCSVWithEnglishHeaders() throws {
        let csv = "code,name,price\n4901234567894,Kurobuta Katsudon,598\n"
        let products = try MasterFileImporter.loadCSV(text: csv)
        XCTAssertEqual(products.first?.priceTaxIncluded, 598)
    }

    func testMissingColumnsThrows() {
        XCTAssertThrowsError(try MasterFileImporter.loadCSV(text: "foo,bar\n1,2\n"))
    }

    func testShiftJISDecoding() throws {
        let text = "商品コード,商品名\n4901234567894,黒豚ロースカツ丼\n"
        let sjisEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        let data = try XCTUnwrap(text.data(using: sjisEncoding))
        let decoded = try MasterFileImporter.decode(data: data)
        XCTAssertTrue(decoded.contains("黒豚ロースカツ丼"))
    }
}
