import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings
    @Query private var plants: [Plant]
    @Query private var events: [CareEvent]
    @State private var editingName = false
    @State private var nameDraft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Профиль").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                    identity
                    HStack(spacing: 12) {
                        statCard("leaf.fill", "\(plants.filter { !$0.isArchived }.count)", "растения", Theme.green)
                        statCard("bell.fill", settings.notificationsEnabled ? String(format: "%02d:%02d", settings.reminderHour, settings.reminderMinute) : "Выкл.", "Напоминания", Theme.orange)
                    }
                    progress
                    VStack(spacing: 10) {
                        link("bell.badge", "Напоминания", "Время, растения, виды ухода") { NotificationSettingsView() }
                        link("paintpalette", "Виды ухода", "Свои действия, цвета, иконки") { CareTypesView() }
                        link("sun.max", "Сезон и полушарие", "Для справочных советов") { SeasonSettingsScreen() }
                        link("externaldrive", "Резервная копия", "Экспорт и импорт через «Файлы»") { BackupView() }
                        link("info.circle", "О приложении", "Хранение данных и ограничения") { AboutView() }
                    }
                }
                .padding(Theme.pad)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .alert("Ваше имя", isPresented: $editingName) {
                TextField("Имя", text: $nameDraft)
                Button("Сохранить") { settings.userName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.fill").font(.title).foregroundStyle(Theme.green)
                .frame(width: 64, height: 64).background(Theme.surfaceRaised, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.userName.isEmpty ? "Без имени" : settings.userName).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("Локальный профиль").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { nameDraft = settings.userName; editingName = true } label: {
                Image(systemName: "pencil").foregroundStyle(Theme.green).frame(width: 44, height: 44).background(Theme.surfaceRaised, in: Circle())
            }.accessibilityLabel("Изменить имя")
        }
        .card(padding: 18)
    }

    private func statCard(_ icon: String, _ value: String, _ title: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 40, height: 40).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(value).font(.system(.largeTitle, design: .rounded).weight(.semibold)).foregroundStyle(Theme.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
        .accessibilityElement(children: .combine)
    }

    private var progress: some View {
        let cal = env.provider.calendar
        let today = env.provider.today
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today
        let week = events.filter { $0.date >= weekAgo }.count
        let days = Set(events.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var cursor = days.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        while days.contains(cursor) { streak += 1; cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86_400) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Прогресс").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Label("\(RuPlural.days(streak)) подряд", systemImage: "flame.fill").font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orange).padding(.horizontal, 12).padding(.vertical, 6).background(Theme.orange.opacity(0.15), in: Capsule())
            }
            HStack {
                metric("drop.fill", "\(week)", "За неделю")
                metric("chart.bar.fill", "\(events.count)", "Всего записей")
                metric("flame.fill", "\(streak)", "Серия")
            }
            Text("Регулярный уход — лучше для растений.").font(.subheadline).foregroundStyle(Theme.textSecondary)
        }.card(padding: 18)
    }

    private func metric(_ icon: String, _ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(Theme.green)
            Text(v).font(.title.weight(.bold)).foregroundStyle(Theme.textPrimary)
            Text(t).font(.footnote).foregroundStyle(Theme.textSecondary).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private func link<D: View>(_ icon: String, _ title: String, _ sub: String, @ViewBuilder _ dest: () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(Theme.green).frame(width: 40, height: 40)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(sub).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.textSecondary)
            }.card(padding: 14)
        }.buttonStyle(.plain)
    }
}

struct SeasonSettingsScreen: View {
    var body: some View {
        ScrollView { VStack(spacing: 14) { SeasonSettingsCard(); DisclaimerView() }.padding(Theme.pad) }
            .screenBackground().navigationTitle("Сезон").navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                block("Всё хранится на устройстве", "Растения, история, фото и настройки сохраняются только на этом iPhone. Приложение не использует интернет, аккаунты и аналитику.")
                block("Удаление приложения", "Если удалить Leaflog с телефона, локальные данные могут быть удалены вместе с ним. Перед удалением или переустановкой сделайте резервную копию: Профиль → Резервная копия.")
                block("Уведомления", "Напоминания — локальные. iOS ограничивает число ожидающих уведомлений, а режимы Фокуса и настройки системы могут скрывать их. Приложение пересчитывает сроки при каждом открытии.")
                block("Подпись для установки через Xcode", "При бесплатной подписи Apple сборка работает около 7 дней, затем её нужно переустановить из Xcode поверх прежней: данные сохранятся, если не удалять приложение.")
            }.padding(Theme.pad)
        }
        .screenBackground().navigationTitle("О приложении").navigationBarTitleDisplayMode(.inline)
    }
    private func block(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(b).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
