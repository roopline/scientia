import Foundation

/// 商品マスタの保持と永続化。照合はコード（JAN / 商品コード）の辞書引きで行う。
final class ProductMasterStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var lastImportedAt: Date?
    @Published var lastError: String?

    /// 照合用インデックス。JAN のほか、インストアの商品コードでも引けるようにする。
    @Published private(set) var index: [String: Product] = [:]

    private let fileURL: URL

    init(filename: String = "product_master.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
        load()
    }

    // MARK: - 読み書き

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let stored = try? JSONDecoder().decode(StoredMaster.self, from: data)
        products = stored?.products ?? []
        lastImportedAt = stored?.importedAt
        rebuildIndex()
    }

    private func save() {
        let stored = StoredMaster(products: products, importedAt: lastImportedAt)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 更新

    /// ファイルから読み込んで置き換える。
    func replace(with url: URL) {
        do {
            let imported = try MasterFileImporter.load(from: url)
            replace(with: imported)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func replace(with newProducts: [Product]) {
        products = newProducts.sorted { $0.name < $1.name }
        lastImportedAt = Date()
        rebuildIndex()
        save()
    }

    func upsert(_ product: Product) {
        if let position = products.firstIndex(where: { $0.code == product.code }) {
            products[position] = product
        } else {
            products.append(product)
            products.sort { $0.name < $1.name }
        }
        rebuildIndex()
        save()
    }

    func remove(at offsets: IndexSet) {
        products.remove(atOffsets: offsets)
        rebuildIndex()
        save()
    }

    func removeAll() {
        products = []
        lastImportedAt = nil
        rebuildIndex()
        save()
    }

    func product(for code: String) -> Product? {
        index[code]
    }

    private func rebuildIndex() {
        var built: [String: Product] = [:]
        for product in products {
            let code = TextNormalizer.digitsOnly(product.code).isEmpty ? product.code : TextNormalizer.digitsOnly(product.code)
            built[code] = product
            // 先頭 0 を落とした形でも引けるようにしておく
            let trimmed = String(code.drop { $0 == "0" })
            if !trimmed.isEmpty, built[trimmed] == nil { built[trimmed] = product }
        }
        index = built
    }

    private struct StoredMaster: Codable {
        var products: [Product]
        var importedAt: Date?
    }
}
