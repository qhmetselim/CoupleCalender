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
                    .fill(reactionDisplayValue == nil && hasMemory ? Color.accentColor : .clear)
                    .frame(width: compact ? 3 : 5, height: compact ? 3 : 5)
                    .accessibilityHidden(true)
                    .overlay {
                        if let reactionDisplayValue {
                            Text(reactionDisplayValue)
                                .font(compact ? .system(size: 8) : .caption2)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 1 : 2)
            .background {
                if let dayColor {
                    RoundedRectangle(cornerRadius: compact ? 4 : 7)
                        .fill(dayColor.opacity(isSelected ? 0.18 : 0.28))
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

enum DayColorPalette {
    struct Option: Identifiable, Hashable {
        let key: String
        let label: String
        let color: Color

        var id: String { key }
    }

    static let options: [Option] = [
        Option(key: "rose", label: "Gül", color: .pink),
        Option(key: "pink", label: "Pembe", color: Color(red: 0.95, green: 0.55, blue: 0.70)),
        Option(key: "purple", label: "Mor", color: .purple),
        Option(key: "indigo", label: "İndigo", color: .indigo),
        Option(key: "blue", label: "Mavi", color: .blue),
        Option(key: "cyan", label: "Camgöbeği", color: .cyan),
        Option(key: "mint", label: "Nane", color: .mint),
        Option(key: "green", label: "Yeşil", color: .green),
        Option(key: "yellow", label: "Sarı", color: .yellow),
        Option(key: "orange", label: "Turuncu", color: .orange),
        Option(key: "red", label: "Kırmızı", color: .red),
        Option(key: "gray", label: "Gri", color: .gray)
    ]

    static func color(for key: String) -> Color {
        options.first(where: { $0.key == key })?.color ?? .gray
    }

    static func label(for key: String) -> String {
        options.first(where: { $0.key == key })?.label ?? key
    }
}
