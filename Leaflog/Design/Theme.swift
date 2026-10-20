import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }

    init(light: String, dark: String) {
        self.init(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            var v: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&v)
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Палитра Leaflog: тёмно-зелёная и тёплая светлая темы.
enum Theme {
    static let background = Color(light: "F4F2EA", dark: "121915")
    static let surface = Color(light: "FFFFFF", dark: "1D2822")
    static let surfaceRaised = Color(light: "E8EEE2", dark: "273429")
    static let textPrimary = Color(light: "17231B", dark: "F3F1EA")
    static let textSecondary = Color(light: "5B685F", dark: "A0ADA4")
    static let green = Color(light: "3F6E32", dark: "7FB069")
    static let greenFill = Color(light: "3F6E32", dark: "4A7A3D")
    static let orange = Color(light: "A85407", dark: "F4A259")
    static let danger = Color(light: "B83A24", dark: "F08A73")
    static let separator = Color(light: "D9DED3", dark: "2E3B32")

    static let cardRadius: CGFloat = 24
    static let pad: CGFloat = 20
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.greenFill
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(tint.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.green)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surfaceRaised, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Бейдж вида ухода: цвет ВСЕГДА сопровождается иконкой и подписью.
struct CareBadge: View {
    let type: CareType
    var showsTitle = true
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type.iconName).font(.caption.weight(.bold))
            if showsTitle { Text(type.name).font(.caption.weight(.semibold)) }
        }
        .foregroundStyle(Color(hex: type.colorHex))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(hex: type.colorHex).opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(type.name)
    }
}

struct CareIconCircle: View {
    let type: CareType
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: type.iconName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color(hex: type.colorHex))
            .frame(width: size, height: size)
            .background(Color(hex: type.colorHex).opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let text: String
    var count: Int?
    init(_ text: String, count: Int? = nil) { self.text = text; self.count = count }
    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
            if let count {
                Text("\(count)").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.surfaceRaised, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.green)
                .frame(width: 84, height: 84).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle()).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - Ошибки

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(String(localized: "Ошибка"), isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: { Text(message.wrappedValue ?? "") }
    }
}

@MainActor
func attempt(_ message: Binding<String?>, _ work: () throws -> Void) {
    do { try work() } catch let e { message.wrappedValue = e.localizedDescription }
}

// MARK: - Форматирование

enum Fmt {
    static let locale = Locale(identifier: "ru_RU")
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = locale; f.setLocalizedDateFormatFromTemplate(template); return f
    }
    static func shortDate(_ d: Date) -> String { formatter("d MMM").string(from: d) }
    static func fullDate(_ d: Date) -> String { formatter("d MMMM yyyy").string(from: d) }
    static func dayTitle(_ d: Date) -> String { formatter("EEEE, d MMMM").string(from: d).capitalizedFirst }
    static func time(_ d: Date) -> String { formatter("HH:mm").string(from: d) }
    static func dateTime(_ d: Date) -> String { formatter("d MMM yyyy, HH:mm").string(from: d) }
    static func month(_ d: Date) -> String { formatter("LLLL yyyy").string(from: d).capitalizedFirst }

    static func recurrence(_ r: Recurrence) -> String {
        switch r.unit {
        case .day: r.value == 1 ? "Каждый день" : "Каждые \(RuPlural.days(r.value))"
        case .week: r.value == 1 ? "Каждую неделю" : "Каждые \(RuPlural.weeks(r.value))"
        case .month: r.value == 1 ? "Каждый месяц" : "Каждые \(RuPlural.months(r.value))"
        }
    }

    static func status(_ s: TaskStatus) -> String {
        switch s {
        case .upcoming(let d): "Через \(RuPlural.days(d))"
        case .dueToday: "Сегодня"
        case .overdue(let d): "Просрочено на \(RuPlural.days(d))"
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}


/// На крупных размерах шрифта (accessibility) горизонтальная раскладка превращается в вертикальную.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 12
    var alignment: VerticalAlignment = .center
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: () -> Content
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing, content: content)
        } else {
            HStack(alignment: alignment, spacing: spacing, content: content)
        }
    }
}
