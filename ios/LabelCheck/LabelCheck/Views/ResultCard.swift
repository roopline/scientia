import SwiftUI
import UIKit

/// 判定結果のカード。作業者が一瞬で OK / NG を判断できるよう、色と大きさを最優先にしている。
struct ResultCard: View {
    let result: CheckResult
    var image: UIImage?
    var onNext: () -> Void
    var onReplay: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if !result.fields.isEmpty {
                Divider()
                fieldList
            }
            Divider()
            footer
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(result.verdict.tint.opacity(0.9), lineWidth: 3)
        )
        .shadow(radius: 12, y: 4)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(result.verdict.tint, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.verdict.title)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(result.verdict.tint)
                Text(result.productName ?? (result.barcode.map { "バーコード \($0)" } ?? "商品不明"))
                    .font(.headline)
                    .lineLimit(2)
                if let code = result.productCode {
                    Text(code).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
    }

    private var fieldList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(result.fields) { field in
                    FieldRow(field: field)
                    if field.id != result.fields.last?.id { Divider() }
                }
            }
        }
        .frame(maxHeight: 210)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onReplay) {
                Label("もう一度読み上げ", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)

            Button(action: onNext) {
                Label("次のラベルへ", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(result.verdict.tint)
        }
        .padding(10)
    }

    private var iconName: String {
        switch result.verdict {
        case .ok: return "checkmark"
        case .warning: return "exclamationmark"
        case .ng, .unknownProduct: return "xmark"
        case .noBarcode: return "barcode.viewfinder"
        }
    }
}

struct FieldRow: View {
    let field: FieldCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: field.status.symbol)
                .foregroundStyle(field.status.tint)
                .font(.body.weight(.semibold))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.field).font(.subheadline.weight(.semibold))
                HStack(alignment: .top, spacing: 6) {
                    Text("マスタ: \(field.expected)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if field.status != .ok {
                        Text("ラベル: \(field.found ?? "未読取")")
                            .font(.caption)
                            .foregroundStyle(field.status.tint)
                    }
                }
                if let detail = field.detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
