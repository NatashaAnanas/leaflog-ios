import SwiftUI
import SwiftData

struct PlantCardView: View {
    let plant: Plant
    let tasks: [CareTask]
    let types: [CareType]
    @Environment(AppEnvironment.self) private var env
    @State private var error: String?
    @State private var tick = 0

    private var top: CareTask? { tasks.first { $0.status.isActionable } ?? tasks.first }
    private var water: CareType? { types.first { $0.builtinKey == "water" } }
    private var lastWater: Date? {
        guard let water else { return nil }
        return TaskBuilder.lastPerformed(of: plant, typeID: water.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: plant) {
                HStack(spacing: 14) {
                    PlantCover(plant: plant, size: 84)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(plant.name).font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                        if !plant.species.isEmpty {
                            Text(plant.species).font(.subheadline.italic()).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        statusLine
                        Text(lastWater.map { "Последний полив: \(Fmt.shortDate($0))" } ?? "Полив ещё не отмечался")
                            .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            if !plant.isArchived { quickAction }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .errorAlert($error)
        .sensoryFeedback(.success, trigger: tick)
    }

    @ViewBuilder private var statusLine: some View {
        if plant.isArchived {
            Label("В архиве", systemImage: "archivebox").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        } else if let t = top {
            switch t.status {
            case .overdue(let d):
                Label("\(t.type.name): просрочено \(RuPlural.days(d))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
            case .dueToday:
                Label("Сегодня: \(t.type.name.lowercased())", systemImage: t.type.iconName)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.orange)
            case .upcoming(let d):
                Label("\(t.type.name) через \(RuPlural.days(d))", systemImage: "leaf.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.green)
            }
        } else {
            Label("Расписание не задано", systemImage: "calendar.badge.plus")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var quickAction: some View {
        if let t = tasks.first(where: { $0.status.isActionable }) {
            Button { log(t.type) } label: {
                Image(systemName: "checkmark").font(.title3.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Color(hex: t.type.colorHex), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityLabel("Отметить: \(t.type.name)")
            .accessibilityHint("Сохраняет выполнение на сегодня для растения \(plant.name)")
        } else {
            Menu {
                ForEach(types.filter(\.isEnabled)) { type in
                    Button { log(type) } label: { Label(type.name, systemImage: type.iconName) }
                }
            } label: {
                Image(systemName: "plus").font(.title3.weight(.bold)).foregroundStyle(Theme.green)
                    .frame(width: 48, height: 48).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityLabel("Отметить уход")
        }
    }

    private func log(_ type: CareType) {
        attempt($error) {
            let r = try env.repository.logCare(plant: plant, typeID: type.id)
            if !r.wasDuplicate { tick += 1 }
        }
    }
}
