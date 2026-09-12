import SwiftUI
import WidgetKit

struct CoupleCalenderWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PartnerWidgetSnapshot?
}

struct CoupleCalenderWidgetProvider: TimelineProvider {
    private let snapshotStore = PartnerWidgetSnapshotStore()

    func placeholder(in context: Context) -> CoupleCalenderWidgetEntry {
        CoupleCalenderWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CoupleCalenderWidgetEntry) -> Void) {
        completion(CoupleCalenderWidgetEntry(
            date: Date(),
            snapshot: context.isPreview ? .placeholder : snapshotStore.read()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CoupleCalenderWidgetEntry>) -> Void) {
        let entry = CoupleCalenderWidgetEntry(date: Date(), snapshot: snapshotStore.read())
        let refreshDate = Calendar.current.date(byAdding: .hour, value: 4, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct CoupleCalenderWidget: Widget {
    let kind = CoupleCalenderWidgetConfiguration.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CoupleCalenderWidgetProvider()) { entry in
            PartnerWidgetView(snapshot: entry.snapshot)
                .widgetURL(entry.snapshot?.memories.first.flatMap {
                    WidgetDeepLink.url(calendarDay: $0.calendarDay, memoryID: $0.id)
                })
        }
        .configurationDisplayName("Partner anıları")
        .description("Partnerinin son anılarını gösterir.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct CoupleCalenderWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoupleCalenderWidget()
    }
}

private struct PartnerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: PartnerWidgetSnapshot?

    var body: some View {
        Group {
            if let snapshot {
                switch family {
                case .systemMedium:
                    medium(snapshot)
                case .systemLarge:
                    large(snapshot)
                default:
                    small(snapshot)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private func small(_ snapshot: PartnerWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            partnerHeader(snapshot)
            if let memory = snapshot.memories.first {
                memoryLink(memory, lineLimit: 4)
            } else {
                Text("Henüz yeni bir anı yok")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
    }

    private func medium(_ snapshot: PartnerWidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                partnerHeader(snapshot)
                if let memory = snapshot.memories.first {
                    memoryLink(memory, lineLimit: 5)
                } else {
                    Text("Henüz yeni bir anı yok")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Son günler")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(snapshot.memories.dropFirst().prefix(3))) { memory in
                    memorySummaryLink(memory)
                }
            }
            .frame(width: 110, alignment: .leading)
        }
        .padding(4)
    }

    private func large(_ snapshot: PartnerWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            partnerHeader(snapshot)
            if snapshot.memories.isEmpty {
                Text("Henüz yeni bir anı yok")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(snapshot.memories.prefix(3)) { memory in
                    memoryLink(memory, lineLimit: 3)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Partnerine bağlan")
                .font(.headline)
            Text("CoupleCalender'ı aç")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func partnerHeader(_ snapshot: PartnerWidgetSnapshot) -> some View {
        Label(snapshot.partnerDisplayName, systemImage: "heart.fill")
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func memoryLink(_ memory: PartnerWidgetMemory, lineLimit: Int) -> some View {
        if let url = WidgetDeepLink.url(calendarDay: memory.calendarDay, memoryID: memory.id) {
            Link(destination: url) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(WidgetDateFormatting.label(for: memory.calendarDay))
                            .font(.caption.weight(.semibold))
                        if let reaction = memory.reactionDisplayValue {
                            Text(reaction)
                                .font(.body)
                                .accessibilityLabel("Reaction: \(memory.reactionKey ?? reaction)")
                        }
                    }
                    Text(memory.contentPreview)
                        .font(.subheadline)
                        .lineLimit(lineLimit)
                        .privacySensitive()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(dayColor(for: memory).opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(WidgetDateFormatting.label(for: memory.calendarDay)): \(memory.contentPreview)")
        }
    }

    private func memorySummaryLink(_ memory: PartnerWidgetMemory) -> some View {
        Group {
            if let url = WidgetDeepLink.url(calendarDay: memory.calendarDay, memoryID: memory.id) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(dayColor(for: memory))
                            .frame(width: 7, height: 7)
                        Text(WidgetDateFormatting.shortLabel(for: memory.calendarDay))
                            .font(.caption)
                            .lineLimit(1)
                        if let reaction = memory.reactionDisplayValue {
                            Text(reaction)
                                .font(.caption)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayColor(for memory: PartnerWidgetMemory) -> Color {
        guard let key = memory.dayColorKey else { return .accentColor }
        return DayColorPalette.color(for: key)
    }
}

private enum WidgetDateFormatting {
    static func label(for rawValue: String) -> String {
        date(for: rawValue)?.formatted(.dateTime.day().month(.wide).year()) ?? rawValue
    }

    static func shortLabel(for rawValue: String) -> String {
        date(for: rawValue)?.formatted(.dateTime.day().month(.abbreviated)) ?? rawValue
    }

    private static func date(for rawValue: String) -> Date? {
        guard let year = Int(rawValue.prefix(4)),
              let month = Int(rawValue.dropFirst(5).prefix(2)),
              let day = Int(rawValue.dropFirst(8))
        else { return nil }

        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}

private extension PartnerWidgetSnapshot {
    static let placeholder = PartnerWidgetSnapshot(
        schemaVersion: currentSchemaVersion,
        generatedAt: Date(),
        userID: UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID(),
        coupleID: UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID(),
        partnerID: UUID(uuidString: "00000000-0000-4000-8000-000000000003") ?? UUID(),
        partnerDisplayName: "Partnerin",
        memories: [
            PartnerWidgetMemory(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000004") ?? UUID(),
                calendarDay: "2026-09-10",
                contentPreview: "Bugünün küçük anısı…",
                reactionSet: "unicode-v1",
                reactionKey: "heart",
                reactionDisplayValue: "❤️",
                dayColorKey: "rose"
            )
        ]
    )
}
