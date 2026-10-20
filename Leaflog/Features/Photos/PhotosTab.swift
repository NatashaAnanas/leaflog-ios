import SwiftUI
import SwiftData

struct PhotosTab: View {
    let plant: Plant
    @Environment(AppEnvironment.self) private var env
    @State private var feedMode = false
    @State private var viewing: PlantPhoto?
    @State private var editing: PlantPhoto?
    @State private var error: String?

    private var photos: [PlantPhoto] { plant.photos.sorted { $0.takenAt > $1.takenAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Фотодневник", count: photos.count)
                Picker("Вид", selection: $feedMode) {
                    Image(systemName: "square.grid.2x2").tag(false).accessibilityLabel("Сетка")
                    Image(systemName: "rectangle.grid.1x2").tag(true).accessibilityLabel("Лента")
                }.pickerStyle(.segmented).frame(width: 110)
            }
            PhotoSourceButton { image in add(image) } onError: { error = $0 } label: {
                Label("Добавить фото", systemImage: "camera.fill").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50).background(Theme.greenFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if photos.isEmpty {
                EmptyStateView(icon: "photo.on.rectangle.angled", title: "Фотодневник пуст",
                               message: "Добавляйте фото, чтобы видеть, как растёт ваше растение. Копии хранятся только в приложении.")
            } else if feedMode {
                ForEach(photos) { p in
                    Button { viewing = p } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            StoredImage(id: p.id, thumb: false).frame(maxWidth: .infinity).frame(height: 280).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            caption(p)
                        }
                    }.buttonStyle(.plain)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(photos) { p in
                        Button { viewing = p } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                StoredImage(id: p.id).aspectRatio(1, contentMode: .fill).frame(maxWidth: .infinity).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        if plant.coverPhotoID == p.id {
                                            Image(systemName: "star.circle.fill").symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Theme.orange).font(.title3).padding(6)
                                        }
                                    }
                                Text("Снято \(Fmt.shortDate(p.takenAt))").font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Фото, снято \(Fmt.fullDate(p.takenAt))\(plant.coverPhotoID == p.id ? ", обложка" : "")")
                    }
                }
            }
        }
        .fullScreenCover(item: $viewing) { PhotoViewer(plant: plant, start: $0) }
        .sheet(item: $editing) { PhotoEditSheet(photo: $0, reviewHint: true) }
        .errorAlert($error)
    }

    private func caption(_ p: PlantPhoto) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Снято: \(Fmt.fullDate(p.takenAt))").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text("Добавлено в приложение: \(Fmt.fullDate(p.addedAt))").font(.caption).foregroundStyle(Theme.textSecondary)
            if !p.caption.isEmpty { Text(p.caption).font(.subheadline).foregroundStyle(Theme.textSecondary) }
        }
    }

    private func add(_ image: ProcessedImage) {
        attempt($error) {
            let photo = try env.repository.addPhoto(to: plant, image: image)
            // Дата снимка может быть неточной (нет метаданных) — сразу предлагаем её проверить.
            editing = photo
        }
    }
}

struct PhotoEditSheet: View {
    let photo: PlantPhoto
    var reviewHint = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var takenAt = Date()
    @State private var caption = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Дата снимка", selection: $takenAt, in: ...env.provider.now(), displayedComponents: [.date, .hourAndMinute])
                    LabeledContent("Добавлено в приложение", value: Fmt.dateTime(photo.addedAt))
                } footer: {
                    Text(reviewHint ? "Если фото старое, укажите, когда оно было сделано. Дата добавления в приложение не меняется." : "Дата добавления в приложение не меняется.")
                }
                Section("Подпись") {
                    TextField("Необязательно", text: $caption, axis: .vertical).lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("Данные фото").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        attempt($error) { try env.repository.updatePhoto(photo, takenAt: takenAt, caption: caption); dismiss() }
                    }
                }
            }
            .errorAlert($error)
            .onAppear { takenAt = photo.takenAt; caption = photo.caption }
        }
    }
}

struct PhotoViewer: View {
    let plant: Plant
    let start: PlantPhoto
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var selection: UUID = UUID()
    @State private var editing: PlantPhoto?
    @State private var confirmDelete = false
    @State private var error: String?

    private var photos: [PlantPhoto] { plant.photos.sorted { $0.takenAt > $1.takenAt } }
    private var current: PlantPhoto? { photos.first { $0.id == selection } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(photos) { p in
                        StoredImage(id: p.id, thumb: false)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(p.id)
                            .accessibilityLabel("Фото растения, снято \(Fmt.fullDate(p.takenAt))")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                if let p = current { info(p) }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let p = current {
                        Menu {
                            Button { editing = p } label: { Label("Изменить дату и подпись", systemImage: "calendar") }
                            Button {
                                attempt($error) { try env.repository.setCover(p) }
                            } label: { Label("Сделать обложкой", systemImage: "star") }
                            .disabled(plant.coverPhotoID == p.id)
                            Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить фото", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Действия с фото")
                    }
                }
            }
            .sheet(item: $editing) { PhotoEditSheet(photo: $0) }
            .confirmationDialog("Удалить фото?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { deleteCurrent() }
            } message: { Text("Копия фото будет удалена из приложения. Оригинал в медиатеке не затрагивается.") }
            .errorAlert($error)
            .onAppear { selection = start.id }
        }
    }

    private func info(_ p: PlantPhoto) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Снято: \(Fmt.fullDate(p.takenAt))").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Добавлено в приложение: \(Fmt.dateTime(p.addedAt))").font(.footnote).foregroundStyle(Theme.textSecondary)
            if !p.caption.isEmpty { Text(p.caption).font(.subheadline).foregroundStyle(Theme.textPrimary).padding(.top, 2) }
            if plant.coverPhotoID == p.id {
                Label("Обложка", systemImage: "star.fill").font(.footnote.weight(.semibold)).foregroundStyle(Theme.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.pad)
        .background(Theme.surface)
        .accessibilityElement(children: .combine)
    }

    private func deleteCurrent() {
        guard let p = current else { return }
        let idx = photos.firstIndex { $0.id == p.id } ?? 0
        let next = photos.indices.contains(idx + 1) ? photos[idx + 1].id : (idx > 0 ? photos[idx - 1].id : nil)
        attempt($error) {
            try env.repository.deletePhoto(p)
            if let next { selection = next } else { dismiss() }
        }
    }
}
