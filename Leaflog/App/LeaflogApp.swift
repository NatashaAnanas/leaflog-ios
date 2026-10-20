import SwiftUI
import SwiftData

@main
struct LeaflogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var startup: Startup = Self.makeStartup()

    enum Startup {
        case ready(AppEnvironment)
        case failed(String)
    }

    @MainActor
    private static func makeStartup() -> Startup {
        do {
            let container = try PersistenceFactory.makeContainer()
            let env = AppEnvironment(container: container)
            AppDelegate.environment = env
            env.bootstrap()
            return .ready(env)
        } catch {
            // Хранилище не стирается и не пересоздаётся: показываем ошибку, данные остаются на диске.
            return .failed(error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .ready(let env):
                RootView()
                    .environment(env)
                    .environment(env.settings)
                    .modelContainer(env.container)
                    .tint(Theme.green)
            case .failed(let message):
                StorageErrorView(message: message)
            }
        }
    }
}

struct StorageErrorView: View {
    let message: String
    var body: some View {
        EmptyStateView(icon: "exclamationmark.triangle", title: "Не удалось открыть хранилище",
                       message: "Ваши данные не тронуты. Закройте приложение и откройте его снова. Если ошибка повторяется, не удаляйте приложение — это может стереть данные.\n\n\(message)")
            .screenBackground()
    }
}
