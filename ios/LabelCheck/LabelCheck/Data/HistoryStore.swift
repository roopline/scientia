import Foundation

/// 判定履歴。作業ログとして残し、CSV で書き出せるようにする。
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [CheckResult] = []

    private let fileURL: URL
    private let limit: Int

    init(filename: String = "check_history.json", limit: Int = 2000) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
        self.limit = limit
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CheckResult].self, from: data) else { return }
        entries = decoded
    }

    func append(_ result: CheckResult) {
        entries.insert(result, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func removeAll() {
        entries = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 書き出し

    var summary: (ok: Int, warning: Int, ng: Int) {
        var ok = 0, warning = 0, ng = 0
        for entry in entries {
            switch entry.verdict {
            case .ok: ok += 1
            case .warning, .noBarcode: warning += 1
            case .ng, .unknownProduct: ng += 1
            }
        }
        return (ok, warning, ng)
    }

    /// Excel でそのまま開ける CSV（BOM 付き UTF-8）を一時ファイルに書き出す。
    func exportCSV() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var csv = "日時,判定,バーコード,商品コード,商品名,NG項目,読み取り内容\n"
        for entry in entries {
            let ngFields = entry.fields.filter { $0.status != .ok }
                .map { "\($0.field):\($0.found ?? "未読取")" }
                .joined(separator: " / ")
            let raw = entry.rawText.replacingOccurrences(of: "\n", with: " ")
            let columns = [formatter.string(from: entry.timestamp),
                           entry.verdict.title,
                           entry.barcode ?? "",
                           entry.productCode ?? "",
                           entry.productName ?? "",
                           ngFields,
                           raw]
            csv += columns.map(escape).joined(separator: ",") + "\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("label_check_history.csv")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
