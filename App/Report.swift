import SwiftUI
import UIKit

/// Builds a simple A4 PDF: summary, open tasks, tasks finished in the last 7 days.
enum ReportBuilder {
    static func make(_ tasks: [TodoItem], now: Date = Date()) -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 48
        let width = page.width - margin * 2

        let open = TaskStore.ordered(tasks, now: now).filter { !$0.done }
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let finished = tasks.filter { $0.done && ($0.completedAt ?? .distantPast) >= weekAgo }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let overdue = open.filter { DueLevel.of($0.due, now: now) == .overdue }.count

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Todo-Report-\(DueText.format(now, "yyyy-MM-dd")).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try? renderer.writePDF(to: url) { context in
            var y = margin
            context.beginPage()

            func ensure(_ height: CGFloat) {
                if y + height > page.height - margin {
                    context.beginPage()
                    y = margin
                }
            }

            func draw(_ text: String, x: CGFloat, width: CGFloat, font: UIFont, color: UIColor = .black, align: NSTextAlignment = .natural) -> CGFloat {
                let style = NSMutableParagraphStyle()
                style.alignment = align
                style.baseWritingDirection = .natural
                let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
                let bounds = string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                string.draw(with: CGRect(x: x, y: y, width: width, height: ceil(bounds.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                return ceil(bounds.height)
            }

            y += draw("Todo report", x: margin, width: width, font: .systemFont(ofSize: 26, weight: .bold), align: .left) + 4
            y += draw(DueText.format(now, "EEEE d MMMM yyyy, h:mm a"), x: margin, width: width, font: .systemFont(ofSize: 12), color: .darkGray, align: .left) + 16
            y += draw("Open: \(open.count)    Overdue: \(overdue)    Done in last 7 days: \(finished.count)", x: margin, width: width, font: .systemFont(ofSize: 13, weight: .semibold), align: .left) + 24

            func section(_ title: String, _ items: [TodoItem], detail: (TodoItem) -> (String, UIColor)) {
                ensure(40)
                y += draw(title, x: margin, width: width, font: .systemFont(ofSize: 17, weight: .bold), align: .left) + 8
                if items.isEmpty {
                    y += draw("Nothing here.", x: margin, width: width, font: .systemFont(ofSize: 13), color: .gray, align: .left) + 16
                    return
                }
                for item in items {
                    ensure(30)
                    let (info, color) = detail(item)
                    let titleHeight = draw(item.title, x: margin, width: width - 170, font: .systemFont(ofSize: 14), align: .natural)
                    _ = draw(info, x: margin + width - 160, width: 160, font: .systemFont(ofSize: 12, weight: .medium), color: color, align: .right)
                    y += max(titleHeight, 16) + 6
                    UIColor(white: 0.88, alpha: 1).setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: width, height: 0.5))
                    y += 6
                }
                y += 16
            }

            section("Open tasks", open) { item in
                guard let due = item.due else { return ("No date", .gray) }
                let level = DueLevel.of(due, now: now)
                let color: UIColor = level == .overdue || level == .urgent ? UIColor(hex: 0xB3261E) : (level == .soon ? UIColor(hex: 0x8A4B00) : .darkGray)
                return (level == .overdue ? "Overdue · \(DueText.format(due, "d MMM h:mm a"))" : DueText.format(due, "EEE d MMM, h:mm a"), color)
            }
            section("Finished in the last 7 days", finished) { item in
                ("Done \(DueText.format(item.completedAt ?? now, "EEE d MMM"))", UIColor(hex: 0x2E7D32))
            }
        }
        return url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
