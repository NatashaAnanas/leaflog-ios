import SwiftUI
import SwiftData

struct AddEditPlantView: View {
    let plant: Plant?
    var onCreated: ((Plant) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \CareType.sortOrder) private var types: [CareType]

    @State private var name = ""
    @State private var species = ""
    @State private var profileID: String?
    @State private var photo: ProcessedImage?
    @State private var photoTakenAt = Date()
    @State private var watering = ScheduleDraft()
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                if plant == nil {
                    Section {
                        HStack {
                            Spacer()
                            PhotoSourceButton { img in
                                photo = img
                                photoTakenAt = img.takenAt ?? Date()
                            } onError: { error = $0 } label: { photoLabel }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                Section {
                    TextField("Название (например, «Монстя»)", text: $name)
                        .accessibilityLabel("Название растения")
                    TextField("Вид или сорт (необязательно)", text: $species)
                        .accessibilityLabel("Вид или сорт")
                } footer: { Text("Достаточно названия. Название может быть любым — оно не определяет вид растения.") }

                Section {
                    Picker("Справочный профиль", selection: $profileID) {
                        Text("Не выбран").tag(String?.none)
                        ForEach(TipsCatalog.profiles) { Text($0.name).tag(Optional($0.id)) }
                        Text(TipsCatalog.general.name).tag(Optional(TipsCatalog.general.id))
                    }
                } header: { Text("Советы по уходу") } footer: {
                    Text("Профиль нужен только для справочных советов. Расписание он не меняет.")
                }

                if plant == nil, let water = types.first(where: { $0.builtinKey == "water" }) {
                    Section {
                        ScheduleFields(draft: $watering, lastPerformed: nil)
                    } header: { Label(water.name, systemImage: water.iconName) } footer: {
                        Text("Необязательно. Расписание любого ухода можно настроить позже на карточке растения.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(plant == nil ? "Новое растение" : "Изменить растение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(!canSave) }
            }
            .errorAlert($error)
            .onAppear {
                if let plant, name.isEmpty {
                    name = plant.name; species = plant.species; profileID = plant.referenceProfileID
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder private var photoLabel: some View {
        if let photo, let img = UIImage(data: photo.thumb) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill").font(.title).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Theme.orange).padding(6)
                }
                .accessibilityLabel("Фото выбрано. Нажмите, чтобы изменить")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "camera.fill").font(.title).foregroundStyle(Theme.green)
                Text("Добавить фото").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.green)
            }
            .frame(width: 140, height: 140)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .accessibilityLabel("Добавить фото растения")
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        attempt($error) {
            if let plant {
                plant.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                plant.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
                plant.referenceProfileID = profileID
                try env.repository.commit()
                dismiss()
            } else {
                let p = try env.repository.addPlant(name: name, species: species, photo: photo,
                                                    photoTakenAt: photoTakenAt, referenceProfileID: profileID)
                if watering.enabled, let water = types.first(where: { $0.builtinKey == "water" }) {
                    try env.repository.setRule(plant: p, typeID: water.id, recurrence: watering.recurrence,
                                               anchorDate: watering.anchorDate, anchorKind: watering.anchorKind,
                                               notifications: watering.notifications)
                }
                onCreated?(p)
                dismiss()
            }
        }
    }
}
