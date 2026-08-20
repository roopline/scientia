import Foundation

/// 設定値。UserDefaults に JSON で保存する。
final class AppSettings: ObservableObject {
    @Published var options: MatchOptions { didSet { persist() } }
    /// 判定結果を音声で読み上げる
    @Published var speechEnabled: Bool { didSet { persist() } }
    /// OK のときも読み上げる（NG のみ鳴らしたい現場向けに切替）
    @Published var speakOnSuccess: Bool { didSet { persist() } }
    /// バイブレーションで通知する
    @Published var hapticsEnabled: Bool { didSet { persist() } }
    /// 判定確定に必要な連続一致フレーム数
    @Published var stabilityFrames: Int { didSet { persist() } }
    /// 同じ商品を連続で判定しないためのクールダウン（秒）
    @Published var cooldownSeconds: Double { didSet { persist() } }
    /// 連続スキャン（かざすだけで次々判定）
    @Published var continuousScan: Bool { didSet { persist() } }

    private static let key = "app_settings_v1"

    init() {
        let stored = Self.loadStored()
        options = stored?.options ?? .default
        speechEnabled = stored?.speechEnabled ?? true
        speakOnSuccess = stored?.speakOnSuccess ?? true
        hapticsEnabled = stored?.hapticsEnabled ?? true
        stabilityFrames = stored?.stabilityFrames ?? 2
        cooldownSeconds = stored?.cooldownSeconds ?? 2.5
        continuousScan = stored?.continuousScan ?? true
    }

    private func persist() {
        let snapshot = Stored(options: options,
                              speechEnabled: speechEnabled,
                              speakOnSuccess: speakOnSuccess,
                              hapticsEnabled: hapticsEnabled,
                              stabilityFrames: stabilityFrames,
                              cooldownSeconds: cooldownSeconds,
                              continuousScan: continuousScan)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private static func loadStored() -> Stored? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    private struct Stored: Codable {
        var options: MatchOptions
        var speechEnabled: Bool
        var speakOnSuccess: Bool
        var hapticsEnabled: Bool
        var stabilityFrames: Int
        var cooldownSeconds: Double
        var continuousScan: Bool
    }
}
