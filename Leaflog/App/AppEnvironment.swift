import Foundation
import SwiftData
import SwiftUI
import Observation

/// Корневой набор зависимостей приложения.
@Observable
@MainActor
final class AppEnvironment {
    @ObservationIgnored let container: ModelContainer
    let settings: AppSettings
    let photos: PhotoStore
    let provider: DateProvider
    let repository: CareRepository
    let notifications: NotificationService
    let router = AppRouter()

    init(container: ModelContainer, settings: AppSettings = AppSettings(), photos: PhotoStore = PhotoStore(root: PhotoStore.defaultRoot),
         provider: DateProvider = .system, center: NotificationCenterProtocol = SystemNotificationCenter()) {
        self.container = container
        self.settings = settings
        self.photos = photos
        self.provider = provider
        let context = container.mainContext
        let service = NotificationService(center: center, settings: settings, context: context, provider: provider)
        self.notifications = service
        self.repository = CareRepository(context: context, provider: provider, photos: photos, notifier: service)
    }

    /// Запуск: встроенные виды ухода, чистка осиротевших файлов (только после успешной загрузки базы), сверка уведомлений.
    func bootstrap() {
        try? repository.ensureBuiltInCareTypes()
        // Если база не прочиталась, файлы не трогаем: чистка только по успешному результату.
        if let all = try? container.mainContext.fetch(FetchDescriptor<PlantPhoto>()) {
            photos.removeOrphans(keeping: Set(all.map(\.id)))
        }
        notifications.registerCategories()
        notifications.requestSync()
    }
}
