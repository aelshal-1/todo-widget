import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Theme {
    static let background = Color(light: 0xFBFAF7, dark: 0x1C1C1E)
    static let field = Color(light: 0xF1EFEA, dark: 0x2C2C2E)
    static let primary = Color(light: 0x17171C, dark: 0xF2F2F5)
    static let secondary = Color(light: 0x5F5E66, dark: 0xA1A0A8)
    static let accent = Color(light: 0x2D5BE3, dark: 0x5B82F0)
    static let ring = Color(light: 0x8E8B84, dark: 0x7C7B80)
}

/// How close a due date is. Drives the chip color and the row tint.
enum DueLevel {
    case none, later, soon, urgent, overdue

    static func of(_ due: Date?, now: Date = Date()) -> DueLevel {
        guard let due else { return .none }
        let s = due.timeIntervalSince(now)
        if s < 0 { return .overdue }
        if s <= 2 * 3600 { return .urgent }
        if s <= 24 * 3600 { return .soon }
        return .later
    }

    var foreground: Color {
        switch self {
        case .none, .later: return Color(light: 0x4A4A52, dark: 0xC9C8CE)
        case .soon: return Color(light: 0x8A4B00, dark: 0xFFC266)
        case .urgent: return Color(light: 0xB3261E, dark: 0xFF8A80)
        case .overdue: return .white
        }
    }

    var background: Color {
        switch self {
        case .none: return .clear
        case .later: return Color(light: 0xEEEDEA, dark: 0x3A3A3F)
        case .soon: return Color(light: 0xFFF0D6, dark: 0x4A3410)
        case .urgent: return Color(light: 0xFCE8E6, dark: 0x4D1E1B)
        case .overdue: return Color(light: 0xB3261E, dark: 0xD93A30)
        }
    }

    var rowTint: Color {
        switch self {
        case .urgent, .overdue: return Color(light: 0xFFF4F3, dark: 0x2E1716)
        default: return .clear
        }
    }

    var isHot: Bool { self == .urgent || self == .overdue }
}

enum DueText {
    static func label(_ due: Date, now: Date = Date()) -> String {
        if due < now { return "Overdue" }
        let cal = Calendar.current
        let time = timeString(due)
        if cal.isDateInToday(due) { return time }
        if cal.isDateInTomorrow(due) { return "Tomorrow \(time)" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day, days < 7 {
            return "\(format(due, "EEE")) \(time)"
        }
        return format(due, "d MMM")
    }

    static func timeString(_ date: Date) -> String {
        let minute = Calendar.current.component(.minute, from: date)
        return format(date, minute == 0 ? "h a" : "h:mm a")
    }

    static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

struct DueChip: View {
    let due: Date
    let now: Date

    var body: some View {
        let level = DueLevel.of(due, now: now)
        Text(DueText.label(due, now: now))
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(level.foreground)
            .background(RoundedRectangle(cornerRadius: 8).fill(level.background))
    }
}

struct CheckCircle: View {
    let done: Bool
    let hot: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(done ? Theme.accent : (hot ? DueLevel.urgent.foreground : Theme.ring), lineWidth: 2)
                .background(Circle().fill(done ? Theme.accent : Color.clear))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}
