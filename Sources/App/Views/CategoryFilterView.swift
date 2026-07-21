import SwiftUI
import RealTodoKit

struct CategoryFilterView: View {
    let categories: [RealTodoKit.Category]
    let selectedIds: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "전체", isSelected: selectedIds.isEmpty, onTap: {
                    for id in selectedIds { onToggle(id) }
                })
                ForEach(categories) { cat in
                    filterChip(
                        label: cat.name,
                        isSelected: selectedIds.contains(cat.id),
                        color: Color(hex: cat.color) ?? .gray,
                        onTap: { onToggle(cat.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func filterChip(label: String, isSelected: Bool, color: Color = .secondary, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? color : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
