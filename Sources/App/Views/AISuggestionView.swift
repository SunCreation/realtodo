import SwiftUI
import RealTodoKit

struct AISuggestionRow: View {
    let item: TodoWithCategories
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.todo.title)
                    .font(.body)
                if let reason = item.todo.aiReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    ForEach(item.categories) { cat in
                        Text(cat.name)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color(hex: cat.color)?.opacity(0.15) ?? Color.gray.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.green)

                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 2)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(6)
    }
}
