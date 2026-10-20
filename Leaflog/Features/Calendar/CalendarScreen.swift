import SwiftUI
import SwiftData

/// Календарь: общий (plant == nil) или конкретного растения.
struct CalendarScreen: View {
    var plant: Plant?
    var embedded = false
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Plant.name) private var allPlants: [Plant]
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @Query(sort: \CareEvent.date, order: .reverse) private var allEvents: [CareEvent]

    @State private var month = Date()
    @State private var selected = Date()
    @State private var plantFilter: Set<UUID> = []
    @State private var typeFilter: Set<UUID> = []
    @State private var editing: CareEvent?
    @State private var addDate: Date?
    @State private var initialized = false
    @State private var error: String?

    private var cal: Calendar { env.provider.calendar }
    private var typeMap: [UUID: CareType] { Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) }) }

    private var events: [CareEvent] {
        allEvents.filter { e in
            guard let p = e.plant else { return false }
            if let plant { return p.id == plant.id }
            if p.isArchived { return false }
            if !plantFilter.isEmpty && !plantFilter.contains(p.id) { return false }
            if !typeFilter.isEmpty && !typeFilter.contains(e.careTypeID) { return false }
            return true
        }
    }

    private var tasks: [CareTask] {
        let scope = plant.map { [$0] } ?? allPlants.filter { plantFilter.isEmpty || plantFilter.contains($0.id) }
        return TaskBuilder.tasks(plants: scope, types: types, provider: env.provider)
            .filter { typeFilter.isEmpty || typeFilter.contains($0.type.id) }
    }

    var body: some View {
        let evs = events, tks = tasks
        let eventsByDay = Dictionary(grouping: evs, by: { cal.startOfDay(for: $0.date) })
        let tasksByDay = Dictionary(grouping: tks, by: { $0.dueDay })
        let content = VStack(alignment: .leading, spacing: 16) {
            if plant == nil { filterBar }
            MonthGridView(month: $month, selected: $selected, calendar: cal, today: env.provider.today,
                          markers: { markers($0, eventsByDay, tasksByDay) },
                          accessibilityText: { describe($0, eventsByDay, tasksByDay) })
            legend
            dayDetail(eventsByDay[cal.startOfDay(for: selected)] ?? [], tasksByDay[cal.startOfDay(for: selected)] ?? [])
        }
        Group {
            if embedded { content }
            else {
                ScrollView { content.padding(Theme.pad) }
                    .screenBackground()
                    .navigationTitle(plant == nil ? "Календарь" : "Календарь ухода")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $editing) { CareLogSheet(plant: $0.plant, event: $0) }
        .sheet(item: Binding(get: { addDate.map(IdentifiedDate.init) }, set: { addDate = $0?.date })) { item in
            CareLogSheet(plant: plant, initialDate: item.date)
        }
        .errorAlert($error)
        .onAppear {
            if !initialized { initialized = true; selected = env.provider.today; month = cal.dateInterval(of: .month, for: selected)?.start ?? selected }
        }
    }

    // MARK: Данные дня

    private func markers(_ day: Date, _ e: [Date: [CareEvent]], _ t: [Date: [CareTask]]) -> DayMarkers {
        let key = cal.startOfDay(for: day)
        func uniqueTypes(_ ids: [UUID]) -> [CareType] {
            var seen = Set<UUID>(); return ids.compactMap { id in seen.insert(id).inserted ? typeMap[id] : nil }
        }
        let tasks = t[key] ?? []
        return DayMarkers(done: uniqueTypes((e[key] ?? []).map(\.careTypeID)),
                          planned: uniqueTypes(tasks.filter { !isOverdue($0) }.map(\.type.id)),
                          overdue: uniqueTypes(tasks.filter(isOverdue).map(\.type.id)))
    }

    private func isOverdue(_ t: CareTask) -> Bool { if case .overdue = t.status { true } else { false } }

    private func describe(_ day: Date, _ e: [Date: [CareEvent]], _ t: [Date: [CareTask]]) -> String {
        let key = cal.startOfDay(for: day)
        var parts = [Fmt.fullDate(day)]
        let done = (e[key] ?? []).compactMap { typeMap[$0.careTypeID]?.name }
        if !done.isEmpty { parts.append("выполнено: " + done.joined(separator: ", ")) }
        let planned = (t[key] ?? []).filter { !isOverdue($0) }.map(\.type.name)
        if !planned.isEmpty { parts.append("запланировано: " + planned.joined(separator: ", ")) }
        let over = (t[key] ?? []).filter(isOverdue).map(\.type.name)
        if !over.isEmpty { parts.append("просрочено: " + over.joined(separator: ", ")) }
        return parts.joined(separator: ". ")
    }

    // MARK: Фильтры и легенда

    private var filterBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(allPlants.filter { !$0.isArchived }) { p in
                    Button { toggle(&plantFilter, p.id) } label: {
                        Label(p.name, systemImage: plantFilter.contains(p.id) ? "checkmark.circle.fill" : "circle")
                    }
                }
                if !plantFilter.isEmpty { Button("Показать все", role: .destructive) { plantFilter = [] } }
            } label: { filterChip("camera.macro", plantFilter.isEmpty ? "Все растения" : "Растения: \(plantFilter.count)", active: !plantFilter.isEmpty) }
            Menu {
                ForEach(types.filter(\.isEnabled)) { t in
                    Button { toggle(&typeFilter, t.id) } label: {
                        Label(t.name, systemImage: typeFilter.contains(t.id) ? "checkmark.circle.fill" : t.iconName)
                    }
                }
                if !typeFilter.isEmpty { Button("Показать все", role: .destructive) { typeFilter = [] } }
            } label: { filterChip("line.3.horizontal.decrease", typeFilter.isEmpty ? "Все виды ухода" : "Виды: \(typeFilter.count)", active: !typeFilter.isEmpty) }
            Spacer(minLength: 0)
        }
    }

    private func filterChip(_ icon: String, _ text: String, active: Bool) -> some View {
        Label(text, systemImage: icon).font(.subheadline.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .foregroundStyle(active ? Color.white : Theme.textPrimary)
            .background(active ? Theme.greenFill : Theme.surface, in: Capsule())
    }

    private func toggle(_ set: inout Set<UUID>, _ id: UUID) { if set.contains(id) { set.remove(id) } else { set.insert(id) } }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(AnyView(Circle().fill(Theme.textSecondary).frame(width: 8, height: 8)), "Выполнено")
            legendItem(AnyView(Circle().stroke(Theme.textSecondary, lineWidth: 1.5).frame(width: 8, height: 8)), "Запланировано")
            legendItem(AnyView(Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(Theme.danger)), "Просрочено")
        }
        .font(.caption).foregroundStyle(Theme.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Обозначения: заливка — выполнено, кольцо — запланировано, треугольник — просрочено")
    }

    private func legendItem(_ symbol: AnyView, _ text: String) -> some View {
        HStack(spacing: 5) { symbol; Text(text) }
    }

    // MARK: День

    @ViewBuilder
    private func dayDetail(_ dayEvents: [CareEvent], _ dayTasks: [CareTask]) -> some View {
        let overdueAll = tasks.filter { isOverdue($0) }
        VStack(alignment: .leading, spacing: 12) {
            Text(Fmt.dayTitle(selected)).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if !overdueAll.isEmpty && cal.isDate(selected, inSameDayAs: env.provider.today) {
                Text("Просрочено").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger)
                ForEach(overdueAll) { taskRow($0, showOverdueDays: true) }
            }
            let planned = dayTasks.filter { !isOverdue($0) }
            let late = dayTasks.filter(isOverdue).filter { _ in !cal.isDate(selected, inSameDayAs: env.provider.today) }
            if !planned.isEmpty || !late.isEmpty {
                Text("Запланировано на этот день").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                ForEach(planned + late) { taskRow($0, showOverdueDays: isOverdue($0)) }
            }
            Text("Выполнено").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            if dayEvents.isEmpty {
                Text("Нет записей об уходе за этот день.").font(.subheadline).foregroundStyle(Theme.textSecondary).card()
            } else {
                ForEach(dayEvents.sorted { $0.date > $1.date }) { eventRow($0) }
            }
            if selected <= env.provider.today || cal.isDate(selected, inSameDayAs: env.provider.today) {
                Button {
                    addDate = defaultDate(for: selected)
                } label: { Label("Внести уход за этот день", systemImage: "plus.circle.fill") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func defaultDate(for day: Date) -> Date {
        if cal.isDate(day, inSameDayAs: env.provider.now()) { return env.provider.now() }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func eventRow(_ e: CareEvent) -> some View {
        let type = typeMap[e.careTypeID]
        return Button { editing = e } label: {
            AdaptiveStack(spacing: 12) {
                if let type { CareIconCircle(type: type) }
                VStack(alignment: .leading, spacing: 3) {
                    if plant == nil, let p = e.plant { Text(p.name).font(.headline).foregroundStyle(Theme.textPrimary) }
                    HStack(spacing: 6) {
                        Text(type?.name ?? "Уход").font(plant == nil ? .subheadline : .headline).foregroundStyle(Theme.textPrimary)
                        Text("· \(Fmt.time(e.date))").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    if !e.comment.isEmpty { Text(e.comment).font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil").foregroundStyle(Theme.textSecondary)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открыть, изменить или удалить запись")
    }

    private func taskRow(_ t: CareTask, showOverdueDays: Bool) -> some View {
        AdaptiveStack(spacing: 12) {
            CareIconCircle(type: t.type)
            VStack(alignment: .leading, spacing: 3) {
                if plant == nil { Text(t.plant.name).font(.headline).foregroundStyle(Theme.textPrimary) }
                Text(t.type.name).font(plant == nil ? .subheadline : .headline).foregroundStyle(Theme.textPrimary)
                Label(Fmt.status(t.status), systemImage: showOverdueDays ? "exclamationmark.triangle.fill" : "calendar")
                    .font(.footnote.weight(.semibold)).foregroundStyle(showOverdueDays ? Theme.danger : Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if t.status.isActionable {
                Button {
                    attempt($error) { try env.repository.logCare(plant: t.plant, typeID: t.type.id) }
                } label: { Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Theme.green) }
                    .accessibilityLabel("Выполнено сейчас: \(t.type.name), \(t.plant.name)")
            }
        }
        .card(padding: 12)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(showOverdueDays ? Theme.danger.opacity(0.6) : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

struct IdentifiedDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}
