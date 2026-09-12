import SwiftUI

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
        options.first(where: { $0.key == key })?.label ?? "Bilinmeyen renk"
    }
}
