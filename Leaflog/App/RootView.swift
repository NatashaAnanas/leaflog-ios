import SwiftUI
import SwiftData

enum RootTab: Hashable { case plants, tips, tasks, profile }

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var tab: RootTab = .plants
    @State private var plantsPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            PlantsListView(path: $plantsPath)
                .tabItem { Label("Растения", systemImage: "camera.macro") }.tag(RootTab.plants)
            TipsHomeView()
                .tabItem { Label("Советы", systemImage: "lightbulb") }.tag(RootTab.tips)
            TasksView()
                .tabItem { Label("Задачи", systemImage: "bell") }.tag(RootTab.tasks)
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person") }.tag(RootTab.profile)
        }
        .onChange(of: scenePhase) { _, phase in
            // Возврат в приложение: сверка расписаний и уведомлений из сохранённых правил.
            if phase == .active { env.notifications.requestSync() }
        }
        .onChange(of: env.router.route) { _, route in handle(route) }
        .onAppear { handle(env.router.route) }
    }

    private func handle(_ route: AppRoute?) {
        guard let route else { return }
        switch route {
        case .tasks:
            tab = .tasks
        case .plant(let id):
            if let plant = (try? context.fetch(FetchDescriptor<Plant>(predicate: #Predicate { $0.id == id })))?.first {
                tab = .plants
                plantsPath = NavigationPath()
                plantsPath.append(plant)
            } else { tab = .tasks }
        }
        env.router.route = nil
    }
}
