import SwiftUI
import SwiftData

/// Вкладка «Задачи»: просроченные, сегодняшние и предстоящие задачи. Просрочка — одна и та же задача, а не копии.
struct TasksView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \Plant.name) private var plants: [Plant]
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            let tasks = TaskBuilder.tasks(plants: plants, types: types, provider: env.provider)
            let overdue = tasks.filter { if case .overdue = $0.status { true } else { false } }
            let today = tasks.filter { $0.status == .dueToday }
            let upcoming = tasks.filter { if case .upcoming = $0.status { true } else { false } }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Задачи").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                        Spacer()
                        NavigationLink { CalendarScreen(plant: nil) } label: {
                            Image(systemName: "calendar").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                .frame(width: 46, height: 46).background(Theme.surface, in: Circle())
                        }.accessibilityLabel("Общий календарь")
                    }
                    summary(overdue: overdue.count, today: today.count, upcoming: upcoming.count)
                    if tasks.isEmpty {
                        EmptyStateView(icon: "bell", title: "Задач пока нет",
                                       message: "Настройте расписание ухода на карточке растения, и здесь появятся сроки.")
                            .card()
                    }
                    section("Просрочено", overdue)
                    section("Сегодня", today, emptyText: overdue.isEmpty && !tasks.isEmpty ? "На сегодня срочных задач нет." : nil)
                    section("Предстоящие", upcoming)
                }
                .padding(Theme.pad)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0) }
            .errorAlert($error)
        }
    }

    private func summary(overdue: Int, today: Int, upcoming: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сводка по уходу").font(.footnote).foregroundStyle(Theme.textSecondary)
            Text(overdue > 0 ? "Есть просроченный уход: \(overdue)" : (today > 0 ? "Сегодня нужен уход: \(today)" : "Ближайшие задачи уже запланированы."))
                .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                stat(today, "Сегодня", Theme.orange, "clock")
                stat(upcoming, "Скоро", Theme.green, "calendar")
                stat(overdue, "Просрочено", Theme.danger, "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card(padding: 18)
    }

    private func stat(_ n: Int, _ title: String, _ color: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.footnote).foregroundStyle(color)
            Text("\(n)").font(.title.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func section(_ title: String, _ tasks: [CareTask], emptyText: String? = nil) -> some View {
        if !tasks.isEmpty || emptyText != nil {
            SectionTitle(title, count: tasks.count)
            if tasks.isEmpty, let emptyText {
                Text(emptyText).font(.subheadline).foregroundStyle(Theme.textSecondary).card()
            }
            ForEach(tasks) { t in
                NavigationLink(value: t.plant) {
                    TaskRowView(task: t, onError: { error = $0 })
                }.buttonStyle(.plain)
            }
        }
    }
}
