import SwiftUI
import UIKit

enum AppDesign {
    static let accent = DayColorPalette.appAccent
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let fieldBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 20
    static let smallCornerRadius: CGFloat = 14
    static let pagePadding: CGFloat = 20
}

struct AppCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = AppDesign.cornerRadius

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppDesign.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
}

extension View {
    func appCard(padding: CGFloat = 16, cornerRadius: CGFloat = AppDesign.cornerRadius) -> some View {
        modifier(AppCardModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func appInputField() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(AppDesign.fieldBackground, in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(AppDesign.accent.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(minHeight: 46)
            .padding(.horizontal, 14)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct AppStatusMessage: View {
    let text: String
    let isError: Bool

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(isError ? .red : AppDesign.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((isError ? Color.red : AppDesign.accent).opacity(0.10), in: RoundedRectangle(cornerRadius: AppDesign.smallCornerRadius, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

struct AppSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum AppHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
