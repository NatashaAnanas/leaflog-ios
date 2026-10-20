import SwiftUI
import SwiftData
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Plant.name) private var plants: [Plant]
    @Query(sort: \CareType.sortOrder) private var types: [CareType]
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var error: String?

    private var denied: Bool { status == .denied }

    var body: some View {
        @Bindable var s = settings
        Form {
            Section {
                Toggle("Получать напоминания", isOn: Binding(get: { settings.notificationsEnabled && !denied }, set: { toggle($0) }))
                if denied {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Уведомления выключены в системе", systemImage: "bell.slash").foregroundStyle(Theme.danger)
                        Text("Приложение работает и без них. Чтобы получать напоминания, откройте Настройки iOS → Уведомления → Leaflog и разрешите их.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                        Button("Открыть настройки") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            } footer: { Text("Разрешение iOS запрашивается в момент включения.") }

            if settings.notificationsEnabled && !denied {
                Section {
                    DatePicker("Время напоминаний", selection: timeBinding, displayedComponents: .hourAndMinute)
                    Toggle("Повторять про просроченный уход", isOn: $s.repeatOverdue)
                } header: { Text("Когда") } footer: {
                    Text("Если уход не выполнен, напоминание повторится ещё несколько раз в последующие дни (через 1, 2, 3, 7 и 14 дней после срока). При каждом открытии приложения график пересчитывается заново.")
                }
                Section("Виды ухода") {
                    ForEach(types.filter(\.isEnabled)) { t in
                        Toggle(isOn: Binding(get: { t.notificationsEnabled }, set: { v in t.notificationsEnabled = v; save() })) {
                            Label(t.name, systemImage: t.iconName)
                        }
                    }
                }
                Section("Растения") {
                    ForEach(plants.filter { !$0.isArchived }) { p in
                        Toggle(p.name, isOn: Binding(get: { p.notificationsEnabled }, set: { v in p.notificationsEnabled = v; save() }))
                    }
                }
            }
            Section("Ограничения iOS") {
                Text("iOS хранит не более 64 ожидающих локальных уведомлений, поэтому задачи одного дня объединяются в одно напоминание. Фоновый запуск не гарантирован, а режимы Фокуса и настройки системы могут скрывать уведомления. Если приложение долго не открывать, дальние напоминания не будут запланированы заранее.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Напоминания").navigationBarTitleDisplayMode(.inline)
        .task { status = await env.notifications.authorizationStatus() }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { status = await env.notifications.authorizationStatus() } } }
        .onChange(of: settings.repeatOverdue) { _, _ in env.notifications.requestSync() }
        .errorAlert($error)
    }

    private var timeBinding: Binding<Date> {
        Binding {
            env.provider.calendar.date(bySettingHour: settings.reminderHour, minute: settings.reminderMinute, second: 0, of: env.provider.today) ?? Date()
        } set: { d in
            let c = env.provider.calendar.dateComponents([.hour, .minute], from: d)
            settings.reminderHour = c.hour ?? 9
            settings.reminderMinute = c.minute ?? 0
            env.notifications.requestSync()
        }
    }

    private func save() { attempt($error) { try env.repository.commit() } }

    private func toggle(_ on: Bool) {
        if on {
            Task {
                _ = await env.notifications.enableReminders()
                status = await env.notifications.authorizationStatus()
            }
        } else {
            settings.notificationsEnabled = false
            env.notifications.requestSync()
        }
    }
}
