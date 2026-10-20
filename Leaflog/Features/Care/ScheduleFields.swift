import SwiftUI

/// Черновик расписания (правила повторения) для формы.
struct ScheduleDraft: Equatable {
    var enabled = false
    var value = 7
    var unit: IntervalUnit = .day
    var anchorKind: AnchorKind = .firstDue
    var anchorDate = Date()
    var notifications = true

    var recurrence: Recurrence { Recurrence(value: value, unit: unit) }

    init() {}
    init(rule: CareRule) {
        enabled = true
        value = rule.intervalValue
        unit = rule.recurrence.unit
        anchorKind = rule.anchorKind
        anchorDate = rule.anchorDate ?? Date()
        notifications = rule.notificationsEnabled
    }
}

extension IntervalUnit {
    var title: String {
        switch self {
        case .day: "дни"
        case .week: "недели"
        case .month: "месяцы"
        }
    }
}

struct ScheduleFields: View {
    @Binding var draft: ScheduleDraft
    var lastPerformed: Date?
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Toggle("Повторять по расписанию", isOn: $draft.enabled.animation())
        if draft.enabled {
            Stepper(value: $draft.value, in: 1...365) {
                Text(Fmt.recurrence(draft.recurrence))
            }
            .accessibilityValue(Fmt.recurrence(draft.recurrence))
            Picker("Единица", selection: $draft.unit) {
                ForEach(IntervalUnit.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if let lastPerformed {
                LabeledContent("Последнее выполнение", value: Fmt.fullDate(lastPerformed))
            } else {
                Picker("Отсчёт", selection: $draft.anchorKind) {
                    Text("Первая задача").tag(AnchorKind.firstDue)
                    Text("Последний раз делали").tag(AnchorKind.lastCare)
                }
                .pickerStyle(.segmented)
                if draft.anchorKind == .firstDue {
                    DatePicker("Дата первой задачи", selection: $draft.anchorDate, displayedComponents: .date)
                } else {
                    DatePicker("Дата последнего ухода", selection: $draft.anchorDate, in: ...env.provider.now(), displayedComponents: .date)
                }
            }
            LabeledContent("Следующий срок") {
                if let due = nextDue {
                    Text(Fmt.fullDate(due)).foregroundStyle(Theme.green)
                } else { Text("—") }
            }
            Toggle("Напоминать", isOn: $draft.notifications)
        }
    }

    var nextDue: Date? {
        CareScheduler.nextDue(recurrence: draft.enabled ? draft.recurrence : nil, anchorDate: draft.anchorDate,
                              anchorKind: draft.anchorKind, lastPerformed: lastPerformed, calendar: env.provider.calendar)
    }
}
