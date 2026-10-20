import SwiftUI
import SwiftData

enum PlantFilter: String, CaseIterable, Identifiable {
    case all, needsCare, ok, archived
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Все"
        case .needsCare: "Требуют ухода"
        case .ok: "В порядке"
        case .archived: "Архив"
        }
    }
    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .needsCare: "drop"
        case .ok: "leaf"
        case .archived: "archivebox"
        }
    }
}

struct PlantsListView: View {
    @Binding var path: NavigationPath
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Plant.createdAt, order: .reverse) private var plants: [Plant]
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @State private var filter: PlantFilter = .all
    @State private var query = ""
    @State private var searching = false
    @State private var showAdd = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    private var tasks: [CareTask] { TaskBuilder.tasks(plants: plants, types: types, provider: env.provider) }
    private var tasksByPlant: [UUID: [CareTask]] { Dictionary(grouping: tasks, by: { $0.plant.id }) }

    private func visible(_ tasksByPlant: [UUID: [CareTask]]) -> [Plant] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return plants.filter { p in
            if filter == .archived { if !p.isArchived { return false } } else if p.isArchived { return false }
            if !q.isEmpty, !(p.name.localizedCaseInsensitiveContains(q) || p.species.localizedCaseInsensitiveContains(q)) { return false }
            let needs = tasksByPlant[p.id]?.contains { $0.status.isActionable } ?? false
            switch filter {
            case .needsCare: return needs
            case .ok: return !needs
            default: return true
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            let byPlant = tasksByPlant
            let shown = visible(byPlant)
            let actionable = tasks.filter { $0.status.isActionable }.count
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    greeting(actionable: actionable)
                    if searching { searchField }
                    if !plants.isEmpty {
                        SeasonCard()
                        SummaryCard(actionable: actionable)
                        filters
                    }
                    if plants.isEmpty {
                        EmptyStateView(icon: "camera.macro", title: "Здесь будут ваши растения",
                                       message: "Добавьте первое растение — достаточно названия. Фото и расписание можно добавить позже.",
                                       actionTitle: "Добавить первое растение") { showAdd = true }
                            .card()
                    } else if shown.isEmpty {
                        EmptyStateView(icon: filter == .archived ? "archivebox" : "magnifyingglass",
                                       title: filter == .archived ? "Архив пуст" : "Ничего не найдено",
                                       message: filter == .archived ? "Здесь появятся растения, которые вы архивируете." : "Измените запрос или фильтр.")
                    } else {
                        ForEach(shown) { plant in
                            PlantCardView(plant: plant, tasks: byPlant[plant.id] ?? [], types: types)
                        }
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Plant.self) { PlantDetailView(plant: $0) }
            .sheet(isPresented: $showAdd) { AddEditPlantView(plant: nil) { path.append($0) } }
            .errorAlert($error)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("Leaflog").font(.system(.largeTitle, design: .rounded).weight(.heavy)).foregroundStyle(Theme.green)
                Circle().fill(Theme.orange).frame(width: 9, height: 9)
            }
            .minimumScaleFactor(0.6).lineLimit(1)
            .accessibilityElement(children: .ignore).accessibilityLabel("Leaflog").accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            NavigationLink { CalendarScreen(plant: nil) } label: {
                circleIcon("calendar", fill: Theme.surface, tint: Theme.textPrimary)
            }.accessibilityLabel("Общий календарь")
            Button {
                searching.toggle()
                if searching { searchFocused = true } else { query = "" }
            } label: { circleIcon("magnifyingglass", fill: Theme.surface, tint: Theme.textPrimary) }
                .accessibilityLabel("Поиск")
            Button { showAdd = true } label: { circleIcon("plus", fill: Theme.orange, tint: .white) }
                .accessibilityLabel("Добавить растение")
        }
        .padding(.top, 8)
    }

    private func circleIcon(_ name: String, fill: Color, tint: Color) -> some View {
        Image(systemName: name).font(.title3.weight(.bold)).foregroundStyle(tint)
            .frame(width: 46, height: 46).background(fill, in: Circle())
    }

    private func greeting(actionable: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settings.userName.isEmpty ? "Привет!" : "Привет, \(settings.userName)!")
                .font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(plants.isEmpty ? "Начните с первого растения" : (actionable == 0 ? "Все растения в порядке 🌿" : "Требуют внимания: \(actionable)"))
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Поиск по названию", text: $query).focused($searchFocused).submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary) }
                    .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PlantFilter.allCases) { f in
                    Button { withAnimation(.snappy) { filter = f } } label: {
                        Label(f.title, systemImage: f.icon).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .foregroundStyle(filter == f ? Color.white : Theme.textPrimary)
                            .background(filter == f ? Theme.orange : Theme.surface, in: Capsule())
                    }
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
        }
    }
}

struct SeasonCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings
    var body: some View {
        let season = settings.currentSeason(provider: env.provider)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: season.icon).font(.title2).foregroundStyle(Theme.green)
                .frame(width: 48, height: 48).background(Theme.surfaceRaised, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(season.cardTitle).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(TipsCatalog.general.seasonal[season] ?? "").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct SummaryCard: View {
    let actionable: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: actionable == 0 ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.title2).foregroundStyle(actionable == 0 ? Theme.green : Theme.orange)
                .frame(width: 48, height: 48).background(Theme.surfaceRaised, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(actionable == 0 ? "Всё в порядке" : "Нужен уход: \(actionable)").font(.headline).foregroundStyle(Theme.textPrimary)
                Text(actionable == 0 ? "Следующий уход уже в расписании." : "Откройте вкладку «Задачи» или отметьте уход на карточке.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

extension Season {
    var icon: String {
        switch self {
        case .spring: "leaf"
        case .summer: "sun.max"
        case .autumn: "wind"
        case .winter: "snowflake"
        }
    }
    var cardTitle: String {
        switch self {
        case .spring: "Весеннее пробуждение"
        case .summer: "Летний сезон"
        case .autumn: "Осеннее замедление"
        case .winter: "Зимний покой"
        }
    }
    var title: String {
        switch self {
        case .spring: "Весна"
        case .summer: "Лето"
        case .autumn: "Осень"
        case .winter: "Зима"
        }
    }
}
