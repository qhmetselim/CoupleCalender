import SwiftUI

struct CalendarDayCell: View {
    let day: CalendarDay
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let hasMemory: Bool
    let dayColor: Color?
    let reactionDisplayValue: String?
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 2 : 4) {
                Text(String(day.day))
                    .font(compact ? .caption2 : .body.weight(.medium))
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 20 : 32)
                    .minimumScaleFactor(0.75)
                    .background {
                        if isSelected {
                            Circle().fill(AppDesign.accent)
                        } else if isToday {
                            Circle().stroke(AppDesign.accent, lineWidth: 1.5)
                        }
                    }
                Circle()
                    .fill(reactionDisplayValue == nil && hasMemory ? AppDesign.accent : .clear)
                    .frame(width: compact ? 3 : 5, height: compact ? 3 : 5)
                    .accessibilityHidden(true)
                    .overlay {
                        if let reactionDisplayValue {
                            Text(reactionDisplayValue)
                                .font(compact ? .system(size: 9) : .caption)
                                .minimumScaleFactor(0.6)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: compact ? 30 : 48)
            .padding(.vertical, compact ? 1 : 2)
            .background {
                if let dayColor {
                    RoundedRectangle(cornerRadius: compact ? 4 : 7)
                        .fill(dayColor.opacity(isSelected ? 0.12 : 0.22))
                }
            }
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
        if reactionDisplayValue != nil { result += ", tepki var" }
        if dayColor != nil { result += ", gün rengi var" }
        return result
    }
}
