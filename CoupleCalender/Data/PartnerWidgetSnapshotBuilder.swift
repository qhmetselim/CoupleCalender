import Foundation
import WidgetKit

enum PartnerWidgetSnapshotBuilder {
    static let memoryLimit = 7

    static func make(
        userID: UUID,
        coupleID: UUID,
        partnerID: UUID,
        partnerDisplayName: String,
        memories: [Memory],
        reactions: [MemoryReaction],
        dayColors: [DayColor],
        reactionCatalog: [ReactionCatalogItem],
        generatedAt: Date = Date()
    ) -> PartnerWidgetSnapshot {
        let selectedMemories = memories
            .sorted { $0.calendarDay.rawValue > $1.calendarDay.rawValue }
            .prefix(memoryLimit)

        let widgetMemories = selectedMemories.map { memory in
            let reaction = reactions.first { $0.memoryID == memory.id }
            let catalogItem = reaction.flatMap { reaction in
                reactionCatalog.first {
                    $0.reactionSet == reaction.reactionSet && $0.reactionKey == reaction.reactionKey
                }
            }
            let dayColor = dayColors.first {
                $0.calendarOwnerID == partnerID && $0.calendarDay == memory.calendarDay
            }

            return PartnerWidgetMemory(
                id: memory.id,
                calendarDay: memory.calendarDay.rawValue,
                contentPreview: PartnerWidgetContentPreview.truncated(memory.content),
                reactionSet: reaction?.reactionSet,
                reactionKey: reaction?.reactionKey,
                reactionDisplayValue: catalogItem?.displayValue ?? reaction?.reactionKey,
                dayColorKey: dayColor?.colorKey
            )
        }

        return PartnerWidgetSnapshot(
            schemaVersion: PartnerWidgetSnapshot.currentSchemaVersion,
            generatedAt: generatedAt,
            userID: userID,
            coupleID: coupleID,
            partnerID: partnerID,
            partnerDisplayName: partnerDisplayName,
            memories: Array(widgetMemories)
        )
    }
}

@MainActor
enum PartnerWidgetSnapshotWriter {
    private static let store = PartnerWidgetSnapshotStore()

    static func saveIfChanged(_ snapshot: PartnerWidgetSnapshot) {
        guard store.read() != snapshot else { return }
        store.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: CoupleCalenderWidgetConfiguration.widgetKind)
    }

    static func clear() {
        guard store.read() != nil else { return }
        store.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: CoupleCalenderWidgetConfiguration.widgetKind)
    }
}
