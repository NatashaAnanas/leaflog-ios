import SwiftUI

/// Маркеры дня. Выполнено — заливка, запланировано — кольцо, просрочено — треугольник:
/// различаются формой, а не только цветом.
struct DayMarkers {
    var done: [CareType] = []
    var planned: [CareType] = []
    var overdue: [CareType] = []
    var isEmpty: Bool { done.isEmpty && planned.isEmpty && overdue.isEmpty }
}

struct MonthGridView: View {
    @Binding var month: Date
    @Binding var selected: Date
    let calendar: Calendar
    let today: Date
    let markers: (Date) -> DayMarkers
    let accessibilityText: (Date) -> String

    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        var result: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count { result.append(calendar.date(byAdding: .day, value: i, to: first)) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var weekdaySymbols: [String] {
        var f = Calendar(identifier: calendar.identifier)
        f.locale = Fmt.locale
        let symbols = f.shortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Предыдущий месяц")
                Spacer()
                Text(Fmt.month(month)).font(.headline).foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Следующий месяц")
            }
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s.capitalizedFirst).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            let grid = days
            VStack(spacing: 4) {
                ForEach(0..<(grid.count / 7), id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            if let day = grid[row * 7 + col] { cell(day) } else { Color.clear.frame(maxWidth: .infinity, minHeight: 52) }
                        }
                    }
                }
            }
            Button("Сегодня") {
                withAnimation { month = monthStart(today); selected = today }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private func cell(_ day: Date) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let m = markers(day)
        return Button { selected = day } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Theme.orange : Theme.textPrimary))
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected { Circle().fill(Theme.greenFill) }
                        else if isToday { Circle().stroke(Theme.orange, lineWidth: 2) }
                    }
                markerRow(m)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(day))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func markerRow(_ m: DayMarkers) -> some View {
        let all: [(CareType, Int)] = m.overdue.map { ($0, 2) } + m.done.map { ($0, 0) } + m.planned.map { ($0, 1) }
        return HStack(spacing: 2) {
            ForEach(Array(all.prefix(4).enumerated()), id: \.offset) { _, item in
                let color = Color(hex: item.0.colorHex)
                switch item.1 {
                case 0: Circle().fill(color).frame(width: 7, height: 7)
                case 1: Circle().stroke(color, lineWidth: 1.5).frame(width: 7, height: 7)
                default: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(color)
                }
            }
            if all.count > 4 { Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textSecondary) }
        }
        .frame(height: 8)
    }

    private func monthStart(_ d: Date) -> Date {
        calendar.dateInterval(of: .month, for: d)?.start ?? d
    }

    private func shift(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: month) {
            withAnimation { month = monthStart(d) }
        }
    }
}
