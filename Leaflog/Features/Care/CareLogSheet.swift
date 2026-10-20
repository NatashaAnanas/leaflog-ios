import SwiftUI
import SwiftData

/// Внесение факта ухода (в том числе задним числом) и исправление существующей записи.
struct CareLogSheet: View {
    var plant: Plant?
    var preselectedTypeID: UUID?
    var initialDate: Date?
    var event: CareEvent?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @Query(sort: \Plant.name) private var allPlants: [Plant]

    @State private var selectedPlantID: UUID?
    @State private var typeID: UUID?
    @State private var date = Date()
    @State private var comment = ""
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var error: String?

    private var activePlants: [Plant] { allPlants.filter { !$0.isArchived } }
    private var selectableTypes: [CareType] { types.filter { $0.isEnabled || $0.id == event?.careTypeID } }
    private var resolvedPlant: Plant? { plant ?? event?.plant ?? activePlants.first { $0.id == selectedPlantID } }
    private var canSave: Bool { resolvedPlant != nil && typeID != nil && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                if plant == nil && event == nil {
                    Section("Растение") {
                        Picker("Растение", selection: $selectedPlantID) {
                            Text("Выберите").tag(UUID?.none)
                            ForEach(activePlants) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                Section("Что сделано") {
                    Picker("Вид ухода", selection: $typeID) {
                        ForEach(selectableTypes) { t in Label(t.name, systemImage: t.iconName).tag(Optional(t.id)) }
                    }
                    DatePicker("Когда", selection: $date, in: ...env.provider.now())
                    TextField("Комментарий (необязательно)", text: $comment, axis: .vertical).lineLimit(1...4)
                }
                if event != nil {
                    Section {
                        Button("Удалить запись", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(event == nil ? "Внести уход" : "Изменить запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(!canSave) }
            }
            .confirmationDialog("Удалить запись об уходе?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive, action: delete)
            } message: { Text("Срок следующего ухода будет пересчитан по оставшейся истории.") }
            .errorAlert($error)
            .onAppear(perform: setup)
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func setup() {
        if let event {
            typeID = event.careTypeID; date = event.date; comment = event.comment
        } else {
            typeID = preselectedTypeID ?? selectableTypes.first?.id
            date = initialDate ?? env.provider.now()
            selectedPlantID = plant?.id
        }
    }

    private func save() {
        guard canSave, let p = resolvedPlant, let typeID else { return }
        isSaving = true
        defer { isSaving = false }
        attempt($error) {
            if let event {
                event.careTypeID = typeID
                try env.repository.updateEvent(event, date: date, comment: comment)
            } else {
                try env.repository.logCare(plant: p, typeID: typeID, date: date, comment: comment)
            }
            dismiss()
        }
    }

    private func delete() {
        guard let event else { return }
        attempt($error) {
            try env.repository.deleteEvent(event)
            dismiss()
        }
    }
}

/// Настройка расписания одного вида ухода у одного растения.
struct RuleEditorView: View {
    let plant: Plant
    let type: CareType
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var draft = ScheduleDraft()
    @State private var isSaving = false
    @State private var error: String?

    private var existing: CareRule? { plant.rules.first { $0.careTypeID == type.id } }
    private var last: Date? { TaskBuilder.lastPerformed(of: plant, typeID: type.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CareIconCircle(type: type)
                        VStack(alignment: .leading) {
                            Text(type.name).font(.headline)
                            Text(plant.name).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Section {
                    ScheduleFields(draft: $draft, lastPerformed: last)
                } footer: {
                    Text("Следующий срок считается от фактической даты последнего выполнения. Без расписания уход просто фиксируется вручную.")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Расписание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(isSaving) }
            }
            .errorAlert($error)
            .onAppear {
                if let existing { draft = ScheduleDraft(rule: existing) }
                else { draft.anchorDate = env.provider.today }
            }
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        attempt($error) {
            if draft.enabled {
                try env.repository.setRule(plant: plant, typeID: type.id, recurrence: draft.recurrence,
                                           anchorDate: draft.anchorDate, anchorKind: draft.anchorKind,
                                           notifications: draft.notifications)
            } else if let existing {
                try env.repository.removeRule(existing)
            }
            dismiss()
        }
    }
}
