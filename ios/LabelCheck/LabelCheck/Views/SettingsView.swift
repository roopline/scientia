import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("スキャン動作") {
                    Toggle("連続スキャン（かざすだけで判定）", isOn: $settings.continuousScan)
                    Stepper(value: $settings.stabilityFrames, in: 1...5) {
                        LabeledContent("確定に必要な連続一致", value: "\(settings.stabilityFrames) 回")
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("同一ラベルの再判定まで", value: String(format: "%.1f 秒", settings.cooldownSeconds))
                        Slider(value: $settings.cooldownSeconds, in: 0...6, step: 0.5)
                    }
                }

                Section("通知") {
                    Toggle("音声で読み上げる", isOn: $settings.speechEnabled)
                    Toggle("OK のときも読み上げる", isOn: $settings.speakOnSuccess)
                        .disabled(!settings.speechEnabled)
                    Toggle("バイブレーションで知らせる", isOn: $settings.hapticsEnabled)
                }

                Section("照合する項目") {
                    Toggle("価格", isOn: $settings.options.checkPrice)
                    Toggle("内容量", isOn: $settings.options.checkNetWeight)
                    Toggle("アレルゲン表記", isOn: $settings.options.checkAllergens)
                    Toggle("期限（本日以降か）", isOn: $settings.options.checkExpiry)
                    if settings.options.checkExpiry {
                        Stepper(value: $settings.options.expiryWarningDays, in: 0...14) {
                            LabeledContent("残日数の警告", value: "\(settings.options.expiryWarningDays) 日以内")
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("一致とみなす類似度",
                                       value: String(format: "%.0f%%", settings.options.nameSimilarityThreshold * 100))
                        Slider(value: $settings.options.nameSimilarityThreshold, in: 0.5...1.0, step: 0.01)
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("要確認とする下限",
                                       value: String(format: "%.0f%%", settings.options.nameWarningThreshold * 100))
                        Slider(value: $settings.options.nameWarningThreshold, in: 0.2...0.9, step: 0.01)
                    }
                } header: {
                    Text("商品名の判定")
                } footer: {
                    Text("印字のかすれや OCR の揺れを吸収するための閾値です。誤って NG が出る場合は下げ、見逃しが心配な場合は上げてください。")
                }

                Section {
                    Toggle("バーコード内の価格を使う", isOn: $settings.options.useInStorePrice)
                    Stepper(value: $settings.options.inStoreRule.itemCodeStart, in: 0...11) {
                        LabeledContent("商品コード開始桁", value: "\(settings.options.inStoreRule.itemCodeStart + 1) 桁目")
                    }
                    Stepper(value: $settings.options.inStoreRule.itemCodeLength, in: 1...10) {
                        LabeledContent("商品コード桁数", value: "\(settings.options.inStoreRule.itemCodeLength) 桁")
                    }
                    Stepper(value: $settings.options.inStoreRule.priceStart, in: 0...11) {
                        LabeledContent("価格開始桁", value: "\(settings.options.inStoreRule.priceStart + 1) 桁目")
                    }
                    Stepper(value: $settings.options.inStoreRule.priceLength, in: 1...6) {
                        LabeledContent("価格桁数", value: "\(settings.options.inStoreRule.priceLength) 桁")
                    }
                    Button("標準 (フラグ2桁+商品5桁+価格5桁+CD) に戻す") {
                        settings.options.inStoreRule = .standard
                    }
                    Button("PC付き (フラグ2桁+商品5桁+PC+価格4桁+CD) にする") {
                        settings.options.inStoreRule = .withPriceCheckDigit
                    }
                } header: {
                    Text("インストアバーコード")
                } footer: {
                    Text("店内プリンタが発行するバーコード（先頭が 2 で始まるもの）の桁割りです。店舗の設定に合わせてください。")
                }

                Section {
                    LabeledContent("バージョン", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("設定")
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}
