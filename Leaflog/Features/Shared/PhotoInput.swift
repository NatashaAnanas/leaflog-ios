import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

/// Выбор фото из медиатеки или съёмка. Ошибки, отмена, отказ в доступе — без падений и без потери введённых данных.
struct PhotoSourceButton<Content: View>: View {
    var onPicked: (ProcessedImage) -> Void
    var onError: (String) -> Void
    @ViewBuilder var label: () -> Content

    @State private var item: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var busy = false
    @State private var cameraDenied = false

    var body: some View {
        Menu {
            Button { showLibrary = true } label: { Label("Из медиатеки", systemImage: "photo.on.rectangle") }
            Button { openCamera() } label: { Label("Снять фото", systemImage: "camera") }
        } label: {
            label().overlay { if busy { ProgressView() } }
        }
        .disabled(busy)
        .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images)
        .onChange(of: item) { _, new in
            guard let new else { return }
            item = nil
            Task { await load(new) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                showCamera = false
                if let data { Task { await process(data) } }
            }.ignoresSafeArea()
        }
        .alert("Нет доступа к камере", isPresented: $cameraDenied) {
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Разрешите доступ к камере для Leaflog в Настройках iOS. Остальные функции работают без камеры.")
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            onError(String(localized: "Камера недоступна на этом устройстве. Выберите фото из медиатеки."))
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: cameraDenied = true
        default: showCamera = true
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                onError(String(localized: "Не удалось получить фото.")); return
            }
            await process(data)
        } catch {
            onError(String(localized: "Не удалось загрузить фото: \(error.localizedDescription)"))
        }
    }

    private func process(_ data: Data) async {
        busy = true
        defer { busy = false }
        do {
            let processed = try await Task.detached(priority: .userInitiated) { try ImageProcessing.process(data) }.value
            onPicked(processed)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.95))
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// Асинхронная миниатюра/фото из приватного хранилища.
struct StoredImage: View {
    let id: UUID?
    var thumb = true
    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.surfaceRaised)
                Image(systemName: "leaf.fill").font(.title2).foregroundStyle(Theme.green.opacity(0.7))
            }
        }
        .task(id: id) {
            guard let id else { image = nil; return }
            image = ImageCache.shared.image(id, thumb: thumb)
            if image == nil { image = await ImageCache.shared.load(id, thumb: thumb, store: env.photos) }
        }
    }
}

/// Обложка растения или красивая заглушка.
struct PlantCover: View {
    let plant: Plant
    var size: CGFloat = 80
    var corner: CGFloat = 20
    var body: some View {
        Group {
            if let cover = plant.coverPhotoID {
                StoredImage(id: cover, thumb: size < 200)
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.surfaceRaised, Theme.green.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "leaf.fill").font(.system(size: size * 0.4)).foregroundStyle(Theme.green)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }
}
