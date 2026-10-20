import SwiftUI
import SwiftData

struct CareTypesView: View {
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @Environment(AppEnvironment.self) private var env
    @State private var editing: TypeRequest?
    @State private var error: String?

    struct TypeRequest: Identifiable { let id = UUID(); let type: CareType? }

    var body: some View {
        List {
            Section {
                ForEach(types) { t in
                    HStack(spacing: 12) {
                        CareIconCircle(type: t)
                        Button { editing = .init(type: t) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).foregroundStyle(Theme.textPrimary)
                                Text(t.builtinKey == nil ? "Свой вид ухода" : "Предустановленный").font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        Toggle("Включён", isOn: Binding(get: { t.isEnabled }, set: { v in
                            attempt($error) { try env.repository.setCareType(t, enabled: v) }
                        })).labelsHidden()
                    }
                }
            } footer: {
                Text("Вид ухода нельзя удалить: история сохраняет его название, цвет и иконку. Отключённый вид скрывается из новых действий и расписаний.")
            }
            Section { Button { editing = .init(type: nil) } label: { Label("Добавить свой вид ухода", systemImage: "plus.circle.fill") } }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Виды ухода").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { CareTypeEditSheet(type: $0.type) }
        .errorAlert($error)
    }
}

struct CareTypeEditSheet: View {
    let type: CareType?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var name = ""
    @State private var colorHex = "8E6CEF"
    @State private var icon = "leaf.fill"
    @State private var error: String?

    static let colors = ["8E6CEF", "26A69A", "E0A100", "B5651D", "2F80ED", "D6456B", "43A047", "F57C00", "607D8B", "8D6E63"]
    static let icons = ["drop.fill", "humidity.fill", "sparkle", "leaf.fill", "scissors", "sun.max.fill", "thermometer.medium", "wind",
                        "arrow.triangle.2.circlepath", "shower.fill", "bubbles.and.sparkles", "ant.fill", "camera.macro", "flame.fill",
                        "moon.fill", "cloud.rain.fill", "hand.raised.fill", "wrench.and.screwdriver.fill", "trash.fill", "heart.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") { TextField("Например, «Обрезка»", text: $name) }
                Section("Цвет") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(Self.colors, id: \.self) { c in
                            Button { colorHex = c } label: {
                                Circle().fill(Color(hex: c)).frame(width: 36, height: 36)
                                    .overlay { if colorHex == c { Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white) } }
                            }.buttonStyle(.plain).accessibilityLabel("Цвет \(c)").accessibilityAddTraits(colorHex == c ? .isSelected : [])
                        }
                    }
                }
                Section("Иконка") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(Self.icons, id: \.self) { i in
                            Button { icon = i } label: {
                                Image(systemName: i).font(.title3).foregroundStyle(icon == i ? Color(hex: colorHex) : Theme.textSecondary)
                                    .frame(width: 40, height: 40)
                                    .background(icon == i ? Color(hex: colorHex).opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }.buttonStyle(.plain).accessibilityLabel(i).accessibilityAddTraits(icon == i ? .isSelected : [])
                        }
                    }
                }
                Section("Предпросмотр") {
                    HStack { Image(systemName: icon).foregroundStyle(Color(hex: colorHex)); Text(name.isEmpty ? "Название" : name) }
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle(type == nil ? "Новый вид ухода" : "Изменить вид ухода").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert($error)
            .onAppear { if let type { name = type.name; colorHex = type.colorHex; icon = type.iconName } }
        }
    }

    private func save() {
        attempt($error) {
            if let type {
                type.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                type.colorHex = colorHex
                type.iconName = icon
                try env.repository.commit()
            } else {
                try env.repository.addCareType(name: name, colorHex: colorHex, icon: icon)
            }
            dismiss()
        }
    }
}
