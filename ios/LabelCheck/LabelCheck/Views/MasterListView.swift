import SwiftUI
import UniformTypeIdentifiers

struct MasterListView: View {
    @EnvironmentObject private var master: ProductMasterStore
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var editing: Product?
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if master.products.isEmpty {
                    emptyState
                } else {
                    Section {
                        ForEach(filtered) { product in
                            Button { editing = product } label: { row(product) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            // 検索中でも正しい行を消せるよう、実体の index に変換する
                            let codes = offsets.map { filtered[$0].code }
                            let actual = IndexSet(master.products.indices.filter { codes.contains(master.products[$0].code) })
                            master.remove(at: actual)
                        }
                    } header: {
                        Text("\(master.products.count) 件" + (master.lastImportedAt.map { " ・ 読込 \(Self.dateFormatter.string(from: $0))" } ?? ""))
                    }
                }
            }
            .searchable(text: $searchText, prompt: "商品名 / コードで検索")
            .navigationTitle("商品マスタ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { isImporting = true } label: { Label("CSV / JSON を読み込む", systemImage: "square.and.arrow.down") }
                        Button { master.replace(with: SampleMaster.products) } label: { Label("サンプルを読み込む", systemImage: "sparkles") }
                        Divider()
                        Button(role: .destructive) { showingClearConfirm = true } label: { Label("すべて削除", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = Product(code: "", name: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: [.commaSeparatedText, .json, .plainText, .text, .data],
                          allowsMultipleSelection: false) { outcome in
                switch outcome {
                case .success(let urls):
                    if let url = urls.first { master.replace(with: url) }
                case .failure(let error):
                    master.lastError = error.localizedDescription
                }
            }
            .alert("読み込みエラー", isPresented: Binding(get: { master.lastError != nil },
                                                  set: { if !$0 { master.lastError = nil } })) {
                Button("OK", role: .cancel) { master.lastError = nil }
            } message: {
                Text(master.lastError ?? "")
            }
            .confirmationDialog("マスタをすべて削除しますか？", isPresented: $showingClearConfirm, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { master.removeAll() }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(item: $editing) { product in
                ProductEditorView(product: product) { updated in
                    master.upsert(updated)
                }
            }
        }
    }

    private var filtered: [Product] {
        guard !searchText.isEmpty else { return master.products }
        let key = TextNormalizer.normalize(searchText)
        return master.products.filter {
            TextNormalizer.normalize($0.name).contains(key) || $0.code.contains(searchText)
        }
    }

    private func row(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(product.name).font(.body.weight(.semibold))
            Text(product.code).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(product.priceSummary)
                if let weight = product.netWeight { Text(weight) }
                if !product.allergens.isEmpty {
                    Text("アレルゲン: " + product.allergens.joined(separator: "・"))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("商品マスタが空です").font(.headline)
            Text("""
            バーコード（JAN / インストア）から正しい商品を引くための一覧です。
            次の列を持つ CSV を読み込んでください（Shift_JIS / UTF-8 どちらも可）。

            商品コード, 商品名, 税込価格, 本体価格, 内容量, アレルゲン, 必須表記, 備考
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button { isImporting = true } label: {
                Label("CSV / JSON を読み込む", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            Button { master.replace(with: SampleMaster.products) } label: {
                Label("まずサンプルで試す", systemImage: "sparkles")
            }
        }
        .padding(.vertical, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

/// 1 件だけ手で追加・修正するための画面。
struct ProductEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Product
    private let onSave: (Product) -> Void

    init(product: Product, onSave: @escaping (Product) -> Void) {
        _draft = State(initialValue: product)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("識別") {
                    TextField("商品コード / JAN", text: $draft.code)
                        .keyboardType(.numberPad)
                    TextField("商品名", text: $draft.name)
                }
                Section("照合する値") {
                    numberField("税込価格", value: $draft.priceTaxIncluded)
                    numberField("本体価格", value: $draft.priceBody)
                    TextField("内容量（例: 100g）", text: Binding(get: { draft.netWeight ?? "" },
                                                            set: { draft.netWeight = $0.isEmpty ? nil : $0 }))
                    TextField("アレルゲン（/ 区切り）", text: Binding(get: { draft.allergens.joined(separator: "/") },
                                                            set: { draft.allergens = splitList($0) }))
                    TextField("必須表記（/ 区切り）", text: Binding(get: { draft.keywords.joined(separator: "/") },
                                                           set: { draft.keywords = splitList($0) }))
                }
                Section("備考") {
                    TextField("メモ", text: Binding(get: { draft.note ?? "" },
                                                 set: { draft.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
                }
            }
            .navigationTitle(draft.code.isEmpty ? "商品を追加" : "商品を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.code.isEmpty || draft.name.isEmpty)
                }
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Int?>) -> some View {
        TextField(title, text: Binding(get: { value.wrappedValue.map(String.init) ?? "" },
                                       set: { value.wrappedValue = Int(TextNormalizer.digitsOnly($0)) }))
            .keyboardType(.numberPad)
    }

    private func splitList(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: "/／、,，;；|"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// 動作確認用のサンプルマスタ。
enum SampleMaster {
    static let products: [Product] = [
        Product(code: "4901234567894", name: "黒豚ロースカツ丼", priceTaxIncluded: 598, priceBody: 553,
                netWeight: "1食", allergens: ["小麦", "卵"], keywords: ["要冷蔵"], note: "サンプル"),
        Product(code: "4901234567900", name: "牛肉コロッケ", priceTaxIncluded: 128, priceBody: 119,
                netWeight: "2個", allergens: ["小麦", "乳"], keywords: [], note: "サンプル"),
        Product(code: "4901234567917", name: "メンチカツ", priceTaxIncluded: 158, priceBody: 146,
                netWeight: "1個", allergens: ["小麦", "卵", "乳"], keywords: [], note: "サンプル"),
        Product(code: "4901234567924", name: "エビフライ", priceTaxIncluded: 298, priceBody: 276,
                netWeight: "3本", allergens: ["えび", "小麦", "卵"], keywords: [], note: "サンプル")
    ]
}
