import SwiftUI
import SwiftData

/// Вкладка «Советы»: сезон, справочные профили, источники.
struct TipsHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Советы").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.textPrimary).accessibilityAddTraits(.isHeader)
                    let season = settings.currentSeason(provider: env.provider)
                    Text("СЕГОДНЯ ДЛЯ ТЕБЯ").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Label(season.cardTitle, systemImage: season.icon).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        Text(TipsCatalog.general.seasonal[season] ?? "").foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card(padding: 20)
                    SeasonSettingsCard()
                    SectionTitle("Справочные профили")
                    ForEach(TipsCatalog.profiles + [TipsCatalog.general]) { p in
                        NavigationLink { ProfileDetailView(profile: p) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                    if !p.latinName.isEmpty { Text(p.latinName).font(.footnote.italic()).foregroundStyle(Theme.textSecondary) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.textSecondary)
                            }.card(padding: 14)
                        }.buttonStyle(.plain)
                    }
                    DisclaimerView()
                }
                .padding(Theme.pad)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct SeasonSettingsCard: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        @Bindable var s = settings
        VStack(alignment: .leading, spacing: 12) {
            Text("Сезон").font(.headline).foregroundStyle(Theme.textPrimary)
            Picker("Полушарие", selection: $s.hemisphere) {
                Text("Северное").tag(Hemisphere.north)
                Text("Южное").tag(Hemisphere.south)
            }.pickerStyle(.segmented)
            Picker("Сезон", selection: $s.seasonOverride) {
                Text("Автоматически (\(Season.current(for: env.provider.now(), hemisphere: settings.hemisphere, calendar: env.provider.calendar).title))").tag(Season?.none)
                ForEach(Season.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            Text("Сезон влияет только на справочные советы и не меняет ваши интервалы.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}

struct DisclaimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Как пользоваться советами", systemImage: "info.circle").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(TipsCatalog.disclaimer).font(.footnote).foregroundStyle(Theme.textSecondary)
            ForEach(TipsCatalog.sources, id: \.url) { s in
                if let url = URL(string: s.url) { Link(s.name, destination: url).font(.footnote) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct ProfileDetailView: View {
    let profile: CareProfile
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProfileContent(profile: profile, season: settings.currentSeason(provider: env.provider))
                DisclaimerView()
            }.padding(Theme.pad)
        }
        .screenBackground()
        .navigationTitle(profile.name).navigationBarTitleDisplayMode(.inline)
    }
}

struct ProfileContent: View {
    let profile: CareProfile
    let season: Season
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !profile.latinName.isEmpty { Text(profile.latinName).font(.title3.italic()).foregroundStyle(Theme.textSecondary) }
            if let s = profile.seasonal[season] {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Сейчас: \(season.title.lowercased())", systemImage: season.icon).font(.headline).foregroundStyle(Theme.green)
                    Text(s).foregroundStyle(Theme.textPrimary)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
            }
            row("sun.max", "Свет", profile.light)
            row("drop", "Полив", profile.watering)
            row("humidity", "Влажность", profile.humidity)
            row("thermometer.medium", "Температура", profile.temperature)
            row("sparkle", "Подкормка", profile.feeding)
            row("exclamationmark.shield", "Важно", profile.caution)
        }
    }
    private func row(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.green).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 14)
    }
}

/// Советы внутри карточки растения: профиль, сезон и собственные рекомендации.
struct PlantTipsTab: View {
    let plant: Plant
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings
    @State private var editingOwn = false
    @State private var choosingProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Советы по уходу")
            if let profile = TipsCatalog.profile(id: plant.referenceProfileID) {
                ProfileContent(profile: profile, season: settings.currentSeason(provider: env.provider))
            } else {
                Text("Справочный профиль не выбран. Название растения у вас произвольное, поэтому приложение не угадывает вид. Выберите профиль вручную или оставьте растение без него.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).card()
            }
            Button { choosingProfile = true } label: { Label(plant.referenceProfileID == nil ? "Выбрать справочный профиль" : "Сменить профиль", systemImage: "book") }
                .buttonStyle(SecondaryButtonStyle())

            SectionTitle("Мои рекомендации")
            VStack(alignment: .leading, spacing: 8) {
                Text(plant.ownTips.isEmpty ? "Здесь можно сохранить собственные правила ухода именно за этим растением." : plant.ownTips)
                    .foregroundStyle(plant.ownTips.isEmpty ? Theme.textSecondary : Theme.textPrimary)
            }.frame(maxWidth: .infinity, alignment: .leading).card()
            Button { editingOwn = true } label: { Label("Изменить мои рекомендации", systemImage: "square.and.pencil") }
                .buttonStyle(SecondaryButtonStyle())
            DisclaimerView()
        }
        .sheet(isPresented: $editingOwn) { OwnTipsSheet(plant: plant) }
        .sheet(isPresented: $choosingProfile) { ProfilePickerSheet(plant: plant) }
    }
}

struct OwnTipsSheet: View {
    let plant: Plant
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form { TextEditor(text: $text).frame(minHeight: 220).accessibilityLabel("Мои рекомендации") }
                .scrollContentBackground(.hidden).screenBackground()
                .navigationTitle("Мои рекомендации").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            attempt($error) { plant.ownTips = text.trimmingCharacters(in: .whitespacesAndNewlines); try env.repository.commit(sync: false); dismiss() }
                        }
                    }
                }
                .errorAlert($error)
                .onAppear { text = plant.ownTips }
        }
    }
}

struct ProfilePickerSheet: View {
    let plant: Plant
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Button { choose(nil) } label: { row("Без профиля", selected: plant.referenceProfileID == nil) }
                ForEach(TipsCatalog.profiles + [TipsCatalog.general]) { p in
                    Button { choose(p.id) } label: { row(p.name, selected: plant.referenceProfileID == p.id) }
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("Справочный профиль").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .errorAlert($error)
        }
    }
    private func row(_ t: String, selected: Bool) -> some View {
        HStack { Text(t).foregroundStyle(Theme.textPrimary); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(Theme.green) } }
    }
    private func choose(_ id: String?) {
        attempt($error) { plant.referenceProfileID = id; try env.repository.commit(sync: false); dismiss() }
    }
}
