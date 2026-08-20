import Foundation

/// 商品マスタ 1 件。CSV / JSON から読み込む「正解データ」。
struct Product: Identifiable, Codable, Hashable {
    /// JAN(EAN-13/8) または インストア  バーコードの商品コード部
    var code: String
    /// 正しい商品名（ラベルに印字されるべき名称）
    var name: String
    /// 税込価格（円）
    var priceTaxIncluded: Int?
    /// 本体価格（円）
    var priceBody: Int?
    /// 内容量表記（例: "100g" "2枚入"）
    var netWeight: String?
    /// ラベルに必ず印字されるべきアレルゲン等（例: ["小麦", "卵"]）
    var allergens: [String]
    /// ラベルに必ず含まれるべきその他のキーワード（例: ["国産", "解凍"]）
    var keywords: [String]
    /// 備考（判定には使わず、画面表示のみ）
    var note: String?

    var id: String { code }

    init(code: String,
         name: String,
         priceTaxIncluded: Int? = nil,
         priceBody: Int? = nil,
         netWeight: String? = nil,
         allergens: [String] = [],
         keywords: [String] = [],
         note: String? = nil) {
        self.code = code
        self.name = name
        self.priceTaxIncluded = priceTaxIncluded
        self.priceBody = priceBody
        self.netWeight = netWeight
        self.allergens = allergens
        self.keywords = keywords
        self.note = note
    }

    var priceSummary: String {
        switch (priceTaxIncluded, priceBody) {
        case let (taxIn?, body?): return "税込\(taxIn)円 / 本体\(body)円"
        case let (taxIn?, nil): return "税込\(taxIn)円"
        case let (nil, body?): return "本体\(body)円"
        default: return "—"
        }
    }
}
