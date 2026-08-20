import Foundation

enum MasterImportError: LocalizedError {
    case unreadableEncoding
    case missingColumns(String)
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .unreadableEncoding:
            return "文字コードを判別できませんでした（UTF-8 か Shift_JIS で保存してください）"
        case .missingColumns(let detail):
            return "必要な列が見つかりません: \(detail)"
        case .emptyFile:
            return "データが 0 件でした"
        }
    }
}

/// 商品マスタ（CSV / JSON）の読み込み。
/// Excel から出した Shift_JIS CSV と、BOM 付き UTF-8 の両方を想定している。
enum MasterFileImporter {

    static func load(from url: URL) throws -> [Product] {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "json" {
            return try loadJSON(data: data)
        }
        return try loadCSV(text: try decode(data: data))
    }

    static func decode(data: Data) throws -> String {
        var body = data
        // UTF-8 BOM を落とす
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if body.count >= 3, Array(body.prefix(3)) == bom {
            body = body.dropFirst(3)
        }
        if let utf8 = String(data: body, encoding: .utf8) { return utf8 }
        let shiftJIS = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue))
        if let sjis = String(data: body, encoding: String.Encoding(rawValue: shiftJIS)) { return sjis }
        if let utf16 = String(data: body, encoding: .utf16) { return utf16 }
        throw MasterImportError.unreadableEncoding
    }

    static func loadJSON(data: Data) throws -> [Product] {
        let decoder = JSONDecoder()
        let products = try decoder.decode([Product].self, from: data)
        guard !products.isEmpty else { throw MasterImportError.emptyFile }
        return products
    }

    static func loadCSV(text: String) throws -> [Product] {
        let rows = CSVReader.parse(text)
        guard let header = rows.first else { throw MasterImportError.emptyFile }
        let index = ColumnIndex(header: header)
        guard let codeColumn = index.code, let nameColumn = index.name else {
            throw MasterImportError.missingColumns("商品コード / 商品名 (code, name)")
        }

        var products: [Product] = []
        for row in rows.dropFirst() {
            guard row.count > max(codeColumn, nameColumn) else { continue }
            let code = TextNormalizer.digitsOnly(row[codeColumn]).isEmpty
                ? row[codeColumn].trimmingCharacters(in: .whitespaces)
                : TextNormalizer.digitsOnly(row[codeColumn])
            let name = row[nameColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, !name.isEmpty else { continue }

            products.append(Product(code: code,
                                    name: name,
                                    priceTaxIncluded: index.value(.priceTaxIncluded, row).flatMap(intValue),
                                    priceBody: index.value(.priceBody, row).flatMap(intValue),
                                    netWeight: index.value(.netWeight, row),
                                    allergens: splitList(index.value(.allergens, row)),
                                    keywords: splitList(index.value(.keywords, row)),
                                    note: index.value(.note, row)))
        }
        guard !products.isEmpty else { throw MasterImportError.emptyFile }
        return products
    }

    private static func intValue(_ raw: String) -> Int? {
        Int(TextNormalizer.digitsOnly(raw))
    }

    private static func splitList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .components(separatedBy: CharacterSet(charactersIn: "/／、,，;；|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 列名（日本語 / 英語）を吸収するインデックス。
    private struct ColumnIndex {
        enum Column: CaseIterable {
            case code, name, priceTaxIncluded, priceBody, netWeight, allergens, keywords, note

            var aliases: [String] {
                switch self {
                case .code: return ["code", "jan", "jancode", "barcode", "商品コード", "コード", "バーコード", "jan コード"]
                case .name: return ["name", "productname", "商品名", "品名", "名称"]
                case .priceTaxIncluded: return ["price", "pricetaxincluded", "税込価格", "税込", "売価", "販売価格"]
                case .priceBody: return ["pricebody", "本体価格", "税抜価格", "税抜", "本体"]
                case .netWeight: return ["netweight", "weight", "内容量", "重量", "規格"]
                case .allergens: return ["allergens", "allergen", "アレルゲン", "アレルギー", "特定原材料"]
                case .keywords: return ["keywords", "keyword", "必須表記", "キーワード", "必須文言"]
                case .note: return ["note", "memo", "備考", "メモ"]
                }
            }
        }

        private var map: [Column: Int] = [:]

        init(header: [String]) {
            for (position, raw) in header.enumerated() {
                let key = TextNormalizer.normalize(raw)
                guard !key.isEmpty else { continue }
                for column in Column.allCases where map[column] == nil {
                    if column.aliases.contains(where: { TextNormalizer.normalize($0) == key }) {
                        map[column] = position
                        break
                    }
                }
            }
        }

        var code: Int? { map[.code] }
        var name: Int? { map[.name] }

        func value(_ column: Column, _ row: [String]) -> String? {
            guard let position = map[column], position < row.count else { return nil }
            let value = row[position].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }
}

/// クォート・改行入りセルに対応した最小限の CSV パーサ。
enum CSVReader {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")   // エスケープされた二重引用符
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
            case ",":
                endField()
            case "\t":
                // タブ区切りファイルもそのまま扱えるようにする
                endField()
            case "\n":
                endRow()
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
