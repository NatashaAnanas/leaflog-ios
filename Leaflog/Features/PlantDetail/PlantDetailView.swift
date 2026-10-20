import SwiftUI
import SwiftData

enum PlantTab: String, CaseIterable, Identifiable {
    case overview, calendar, photos, notes, tips
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Обзор"
        case .calendar: "Календарь"
        case .photos: "Фото"
        case .notes: "Заметки"
        case .tips: "Советы"
        }
    }
}

struct PlantDetailView: View {
    let plant: Plant
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @State private var tab: PlantTab = .overview
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var undo: UndoInfo?

    struct UndoInfo: Identifiable { let id = UUID(); let event: CareEvent; let title: String }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tabPicker
                switch tab {
                case .overview: PlantOverviewTab(plant: plant, types: types, onLogged: showUndo)
                case .calendar:
                    CalendarScreen(plant: plant, embedded: true)
                    HistoryList(plant: plant)
                case .photos: PhotosTab(plant: plant)
                case .notes: NotesTab(plant: plant)
                case .tips: PlantTipsTab(plant: plant)
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.bottom, 40)
        }
        .screenBackground()
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Изменить", systemImage: "pencil") }
                    Button {
                        attempt($error) { try env.repository.setArchived(plant, !plant.isArchived) }
                    } label: {
                        Label(plant.isArchived ? "Восстановить из архива" : "Архивировать", systemImage: plant.isArchived ? "arrow.uturn.backward" : "archivebox")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить растение", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Действия с растением")
            }
        }
        .sheet(isPresented: $showEdit) { AddEditPlantView(plant: plant) }
        .confirmationDialog("Удалить «\(plant.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить навсегда", role: .destructive) {
                attempt($error) { try env.repository.deletePlant(plant); dismiss() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будут удалены история ухода, заметки и фотографии этого растения из приложения. Оригиналы в вашей медиатеке не затрагиваются. Действие нельзя отменить. Если растение просто больше не нужно в списке, лучше архивировать его.")
        }
        .overlay(alignment: .bottom) { undoBanner }
        .errorAlert($error)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cover = plant.coverPhotoID { StoredImage(id: cover, thumb: false) }
                    else {
                        LinearGradient(colors: [Theme.surfaceRaised, Theme.green.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(Image(systemName: "leaf.fill").font(.system(size: 64)).foregroundStyle(Theme.green))
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 240).clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name).font(.largeTitle.weight(.bold)).foregroundStyle(Theme.textPrimary)
                if !plant.species.isEmpty { Text(plant.species).font(.title3.italic()).foregroundStyle(Theme.textSecondary) }
                if plant.isArchived {
                    Label("В архиве", systemImage: "archivebox.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlantTab.allCases) { t in
                    Button { tab = t } label: {
                        Text(t.title).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                            .foregroundStyle(tab == t ? Color.white : Theme.textPrimary)
                            .background(tab == t ? Theme.greenFill : Theme.surface, in: Capsule())
                    }
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
            }
        }
    }

    private func showUndo(_ event: CareEvent, _ title: String) {
        let info = UndoInfo(event: event, title: title)
        withAnimation { undo = info }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undo?.id == info.id { withAnimation { undo = nil } }
        }
    }

    @ViewBuilder private var undoBanner: some View {
        if let undo {
            HStack {
                Label(undo.title, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Отменить") {
                    attempt($error) { try env.repository.deleteEvent(undo.event) }
                    withAnimation { self.undo = nil }
                }.font(.subheadline.weight(.bold))
            }
            .padding(14).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.separator))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Обзор

struct PlantOverviewTab: View {
    let plant: Plant
    let types: [CareType]
    var onLogged: (CareEvent, String) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var logSheet: LogSheetRequest?
    @State private var ruleEditor: CareType?
    @State private var error: String?

    struct LogSheetRequest: Identifiable { let id = UUID(); let typeID: UUID? }

    private var enabledTypes: [CareType] { types.filter(\.isEnabled) }
    private var tasks: [CareTask] { TaskBuilder.tasks(plants: [plant], types: types, provider: env.provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            quickActions
            tasksSection
            careSection
        }
        .sheet(item: $logSheet) { CareLogSheet(plant: plant, preselectedTypeID: $0.typeID) }
        .sheet(item: $ruleEditor) { RuleEditorView(plant: plant, type: $0) }
        .errorAlert($error)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Быстрые действия")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(enabledTypes) { type in
                    Button { logNow(type) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.iconName).font(.title2).foregroundStyle(Color(hex: type.colorHex))
                            Text(type.name).font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.center).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(Color(hex: type.colorHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .accessibilityLabel("\(type.name) сейчас")
                    .contextMenu {
                        Button { logSheet = .init(typeID: type.id) } label: { Label("Внести за другую дату", systemImage: "calendar.badge.clock") }
                    }
                }
            }
            Button { logSheet = .init(typeID: nil) } label: { Label("Внести уход задним числом", systemImage: "calendar.badge.clock") }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Ближайшие задачи", count: tasks.count)
            if tasks.isEmpty {
                Text("Расписание не настроено. Включите повторение для нужного вида ухода ниже — тогда здесь появятся сроки.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).card()
            } else {
                ForEach(tasks) { t in
                    TaskRowView(task: t, showPlant: false, onError: { error = $0 }, onLogged: { onLogged($0, "\(t.type.name): отмечено") })
                }
            }
        }
    }

    private var careSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Уход и расписание")
            ForEach(enabledTypes) { type in
                let last = TaskBuilder.lastPerformed(of: plant, typeID: type.id)
                let rule = plant.rules.first { $0.careTypeID == type.id }
                Button { ruleEditor = type } label: {
                    HStack(spacing: 12) {
                        CareIconCircle(type: type)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.name).font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(last.map { "Последний раз: \(Fmt.fullDate($0))" } ?? "Ещё не было")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                            Text(rule.map { Fmt.recurrence($0.recurrence) } ?? "Без расписания — ручной учёт")
                                .font(.footnote.weight(.semibold)).foregroundStyle(rule == nil ? Theme.textSecondary : Theme.green)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.textSecondary)
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Настроить периодичность и напоминания")
            }
            Toggle(isOn: Binding(get: { plant.notificationsEnabled }, set: { v in
                plant.notificationsEnabled = v
                attempt($error) { try env.repository.commit() }
            })) {
                Label("Напоминания для этого растения", systemImage: "bell")
            }.card(padding: 14)
        }
    }

    private func logNow(_ type: CareType) {
        attempt($error) {
            let r = try env.repository.logCare(plant: plant, typeID: type.id)
            if !r.wasDuplicate { onLogged(r.event, "\(type.name): отмечено") }
        }
    }
}

// MARK: - Строка задачи

struct TaskRowView: View {
    let task: CareTask
    var showPlant = true
    var onError: (String) -> Void
    var onLogged: (CareEvent) -> Void = { _ in }
    @Environment(AppEnvironment.self) private var env

    private var tint: Color {
        switch task.status {
        case .overdue: Theme.danger
        case .dueToday: Theme.orange
        case .upcoming: Theme.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            CareIconCircle(type: task.type, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                if showPlant { Text(task.plant.name).font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(2) }
                Text(task.type.name).font(showPlant ? .subheadline : .headline).foregroundStyle(Theme.textPrimary)
                Label(Fmt.status(task.status), systemImage: icon).font(.footnote.weight(.semibold)).foregroundStyle(tint)
                Text("Срок: \(Fmt.fullDate(task.dueDay))").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if task.status.isActionable {
                Menu {
                    Button { done() } label: { Label("Выполнено сейчас", systemImage: "checkmark.circle") }
                    Button { snooze() } label: { Label("Напомнить завтра", systemImage: "bell.badge.clock") }
                } label: {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.green)
                } primaryAction: { done() }
                .accessibilityLabel("Выполнено: \(task.type.name)")
                .accessibilityHint("Двойное нажатие — отметить. Долгое — отложить напоминание")
            }
        }
        .card(padding: 12)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(isOverdue ? Theme.danger.opacity(0.6) : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var isOverdue: Bool { if case .overdue = task.status { true } else { false } }
    private var icon: String {
        switch task.status {
        case .overdue: "exclamationmark.triangle.fill"
        case .dueToday: "clock.badge.exclamationmark"
        case .upcoming: "calendar"
        }
    }

    private func done() {
        do {
            let r = try env.repository.logCare(plant: task.plant, typeID: task.type.id)
            if !r.wasDuplicate { onLogged(r.event) }
        } catch { onError(error.localizedDescription) }
    }

    /// «Отложить» меняет только время напоминания; срок и история остаются прежними.
    private func snooze() {
        let tomorrow = env.provider.calendar.date(byAdding: .day, value: 1, to: env.provider.today) ?? env.provider.today
        do { try env.repository.snooze(task.rule, until: tomorrow) } catch { onError(error.localizedDescription) }
    }
}

// MARK: - История

struct HistoryList: View {
    let plant: Plant
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @State private var editing: CareEvent?

    var body: some View {
        let map = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
        let events = plant.events.sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("История", count: events.count)
            if events.isEmpty {
                Text("Записей пока нет.").font(.subheadline).foregroundStyle(Theme.textSecondary).card()
            }
            ForEach(events) { e in
                Button { editing = e } label: {
                    HStack(spacing: 12) {
                        if let t = map[e.careTypeID] { CareIconCircle(type: t, size: 36) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(map[e.careTypeID]?.name ?? "Уход").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text(Fmt.dateTime(e.date)).font(.footnote).foregroundStyle(Theme.textSecondary)
                            if !e.comment.isEmpty { Text(e.comment).font(.footnote).foregroundStyle(Theme.textSecondary) }
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 12)
                }.buttonStyle(.plain)
            }
        }
        .sheet(item: $editing) { CareLogSheet(plant: plant, event: $0) }
    }
}
