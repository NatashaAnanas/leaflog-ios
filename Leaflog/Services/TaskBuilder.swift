import Foundation

/// Вычисляемая задача: одна на пару «растение + вид ухода». Копии на каждый день не создаются:
/// просрочка — это тот же срок, у которого растёт счётчик дней.
struct CareTask: Identifiable {
    var id: UUID { rule.id }
    let rule: CareRule
    let plant: Plant
    let type: CareType
    let dueDay: Date
    let status: TaskStatus
    let lastPerformed: Date?
}

enum TaskBuilder {
    static func lastPerformed(of plant: Plant, typeID: UUID) -> Date? {
        CareScheduler.latest(plant.events.filter { $0.careTypeID == typeID }.map(\.date))
    }

    static func task(for rule: CareRule, types: [UUID: CareType], provider: DateProvider) -> CareTask? {
        guard let plant = rule.plant, let type = types[rule.careTypeID] else { return nil }
        let last = lastPerformed(of: plant, typeID: rule.careTypeID)
        guard let due = CareScheduler.nextDue(recurrence: rule.recurrence, anchorDate: rule.anchorDate,
                                              anchorKind: rule.anchorKind, lastPerformed: last,
                                              calendar: provider.calendar) else { return nil }
        let status = CareScheduler.status(dueDay: due, today: provider.today, calendar: provider.calendar)
        return CareTask(rule: rule, plant: plant, type: type, dueDay: due, status: status, lastPerformed: last)
    }

    /// Задачи активных растений по включённым видам ухода, отсортированные по сроку.
    static func tasks(plants: [Plant], types: [CareType], provider: DateProvider) -> [CareTask] {
        let map = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
        var result: [CareTask] = []
        for plant in plants where !plant.isArchived {
            for rule in plant.rules {
                guard let t = map[rule.careTypeID], t.isEnabled,
                      let task = task(for: rule, types: map, provider: provider) else { continue }
                result.append(task)
            }
        }
        return result.sorted {
            if $0.dueDay != $1.dueDay { return $0.dueDay < $1.dueDay }
            return $0.plant.name < $1.plant.name
        }
    }

    static func notifItems(from tasks: [CareTask]) -> [NotifItem] {
        tasks.compactMap { t in
            guard t.plant.notificationsEnabled, t.type.notificationsEnabled, t.rule.notificationsEnabled else { return nil }
            return NotifItem(ruleID: t.rule.id, plantID: t.plant.id, plantName: t.plant.name,
                             typeName: t.type.name, dueDay: t.dueDay, snoozedUntil: t.rule.snoozedUntil)
        }
    }
}
