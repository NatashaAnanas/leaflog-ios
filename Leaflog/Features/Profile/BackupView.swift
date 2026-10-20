import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @State private var busy = false
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var preview: BackupPreview?
    @State private var message: String?
    @State private var error: String?

    private var service: BackupService {
        BackupService(context: context, photos: env.photos, settings: env.settings, notifier: env.notifications)
    }

    var body: some View {
        Form {
            Section {
                Button { export() } label: { Label("Экспортировать копию…", systemImage: "square.and.arrow.up") }.disabled(busy)
                Button { showImporter = true } label: { Label("Импортировать копию…", systemImage: "square.and.arrow.down") }.disabled(busy)
                if busy { HStack { ProgressView(); Text("Подождите…").foregroundStyle(Theme.textSecondary) } }
            } footer: {
                Text("В копию входят все растения, история ухода, заметки, фото, настройки и версия формата. Файл сохраняется туда, куда вы укажете в «Файлах»; приложение ничего никуда не отправляет само.")
            }
            Section("Важно") {
                Text("Удаление приложения может удалить все локальные данные. Сохраняйте копию в «Файлы» или iCloud Drive до удаления или переустановки.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                Text("Импорт заменяет текущую коллекцию. Перед заменой файл проверяется, а вы подтверждаете действие.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            if let message { Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green) } }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Резервная копия").navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { exportURL.map(IdentifiedURL.init) }, set: { _ in exportURL = nil })) { item in
            ExportPicker(url: item.url) { saved in
                if saved { message = String(localized: "Копия сохранена.") }
                try? FileManager.default.removeItem(at: item.url)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): inspect(url)
            case .failure(let e): error = e.localizedDescription
            }
        }
        .alert("Заменить текущие данные?", isPresented: Binding(get: { preview != nil }, set: { if !$0 { discard() } })) {
            Button("Заменить", role: .destructive) { apply() }
            Button("Отмена", role: .cancel) { discard() }
        } message: {
            if let p = preview {
                Text("Копия от \(Fmt.dateTime(p.manifest.exportedAt)): растений — \(p.plantCount), записей ухода — \(p.eventCount), заметок — \(p.noteCount), фото — \(p.photoCount). Все текущие растения, история, заметки и фото будут заменены. Рекомендуем сначала экспортировать текущую копию.")
            }
        }
        .errorAlert($error)
    }

    private func export() {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { exportURL = try await service.export() } catch { self.error = error.localizedDescription }
        }
    }

    private func inspect(_ url: URL) {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { preview = try await service.inspect(url: url) } catch { self.error = error.localizedDescription }
        }
    }

    private func apply() {
        guard let p = preview else { return }
        preview = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                try await service.apply(p)
                message = String(localized: "Данные восстановлены. Напоминания пересчитаны.")
            } catch {
                service.discard(p)
                self.error = error.localizedDescription
            }
        }
    }

    private func discard() {
        if let p = preview { service.discard(p) }
        preview = nil
    }
}

struct IdentifiedURL: Identifiable { let url: URL; var id: URL { url } }

struct ExportPicker: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(false) }
    }
}
