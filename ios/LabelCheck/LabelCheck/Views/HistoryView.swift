import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var selected: CheckResult?
    @State private var showingClearConfirm = false
    @State private var filter: Filter = .all
    @State private var exportFile: ExportFile?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "すべて"
        case ng = "NG のみ"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                }
                Section {
                    ForEach(entries) { entry in
                        Button { selected = entry } label: { row(entry) }
                            .buttonStyle(.plain)
                    }
                    if entries.isEmpty {
                        Text("履歴はまだありません").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("判定履歴")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("表示", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        // 書き出しはタップ時に 1 回だけ行う
                        if let url = history.exportCSV() { exportFile = ExportFile(url: url) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(history.entries.isEmpty)

                    Button(role: .destructive) { showingClearConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(history.entries.isEmpty)
                }
            }
            .confirmationDialog("履歴をすべて削除しますか？", isPresented: $showingClearConfirm, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { history.removeAll() }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(item: $selected) { entry in
                HistoryDetailView(result: entry)
            }
            .sheet(item: $exportFile) { file in
                ActivityView(items: [file.url])
            }
        }
    }

    private var entries: [CheckResult] {
        switch filter {
        case .all: return history.entries
        case .ng: return history.entries.filter { $0.verdict != .ok }
        }
    }

    private var summary: some View {
        let counts = history.summary
        return HStack {
            summaryCell(title: "OK", value: counts.ok, tint: .green)
            Divider()
            summaryCell(title: "要確認", value: counts.warning, tint: .orange)
            Divider()
            summaryCell(title: "NG", value: counts.ng, tint: .red)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryCell(title: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ entry: CheckResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.verdict == .ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(entry.verdict.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.productName ?? entry.barcode ?? "不明")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(Self.formatter.string(from: entry.timestamp))・\(entry.verdict.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.ngCount > 0 {
                    Text(entry.fields.filter { $0.status != .ok }.map(\.field).joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter
    }()
}

/// 共有シートに渡す CSV。
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// UIActivityViewController の薄いラッパー。
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct HistoryDetailView: View {
    let result: CheckResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("判定") {
                    LabeledContent("結果", value: result.verdict.title)
                    LabeledContent("商品", value: result.productName ?? "—")
                    LabeledContent("コード", value: result.productCode ?? "—")
                    LabeledContent("バーコード", value: result.barcode ?? "—")
                }
                if !result.fields.isEmpty {
                    Section("項目") {
                        ForEach(result.fields) { FieldRow(field: $0) }
                    }
                }
                Section("読み取った文字（OCR 全文）") {
                    Text(result.rawText.isEmpty ? "—" : result.rawText)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("履歴の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }
}
