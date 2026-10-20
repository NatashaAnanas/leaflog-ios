import SwiftUI
import SwiftData

struct NotesTab: View {
    let plant: Plant
    @State private var editing: NoteRequest?

    struct NoteRequest: Identifiable { let id = UUID(); let note: PlantNote? }

    private var notes: [PlantNote] { plant.notes.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Заметки", count: notes.count)
            Button { editing = .init(note: nil) } label: { Label("Новая заметка", systemImage: "square.and.pencil") }
                .buttonStyle(PrimaryButtonStyle())
            if notes.isEmpty {
                EmptyStateView(icon: "note.text", title: "Заметок нет",
                               message: "Записывайте всё важное: где стоит растение, как оно реагирует на свет, чем его кормили.")
            }
            ForEach(notes) { n in
                Button { editing = .init(note: n) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(n.text).font(.body).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading)
                        if n.showsDate {
                            Text(dateLine(n)).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()
                }.buttonStyle(.plain)
            }
        }
        .sheet(item: $editing) { NoteEditSheet(plant: plant, note: $0.note) }
    }

    private func dateLine(_ n: PlantNote) -> String {
        n.updatedAt.timeIntervalSince(n.createdAt) > 1
            ? "Создана \(Fmt.dateTime(n.createdAt)) · изменена \(Fmt.dateTime(n.updatedAt))"
            : "Создана \(Fmt.dateTime(n.createdAt))"
    }
}

struct NoteEditSheet: View {
    let plant: Plant
    let note: PlantNote?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var showsDate = true
    @State private var confirmDelete = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel("Текст заметки")
                }
                Section {
                    Toggle("Показывать дату", isOn: $showsDate)
                } footer: { Text("Выключите, если это постоянная памятка, а не событие.") }
                if note != nil {
                    Section { Button("Удалить заметку", role: .destructive) { confirmDelete = true } }
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle(note == nil ? "Новая заметка" : "Заметка").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .confirmationDialog("Удалить заметку?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let note { attempt($error) { try env.repository.deleteNote(note); dismiss() } }
                }
            }
            .errorAlert($error)
            .onAppear { if let note { text = note.text; showsDate = note.showsDate } }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        attempt($error) {
            if let note { try env.repository.updateNote(note, text: text, showsDate: showsDate) }
            else { try env.repository.addNote(to: plant, text: text, showsDate: showsDate) }
            dismiss()
        }
    }
}
