import SwiftUI

struct CalendarDayCell: View {
    let day: CalendarDay
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let hasMemory: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 2 : 4) {
                Text(String(day.day))
                    .font(compact ? .caption2 : .body)
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 20 : 30)
                    .background {
                        if isSelected {
                            Circle().fill(.tint)
                        } else if isToday {
                            Circle().stroke(.tint, lineWidth: 1.5)
                        }
                    }
                Circle()
                    .fill(hasMemory ? Color.accentColor : .clear)
                    .frame(width: compact ? 3 : 5, height: compact ? 3 : 5)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Günü seçmek için dokun")
    }

    private var textColor: Color {
        if isSelected { return .white }
        if !isCurrentMonth { return .secondary }
        return .primary
    }

    private var accessibilityLabel: String {
        var result = day.rawValue
        if isToday { result += ", bugün" }
        if isSelected { result += ", seçili" }
        if hasMemory { result += ", anı var" }
        return result
    }
}
