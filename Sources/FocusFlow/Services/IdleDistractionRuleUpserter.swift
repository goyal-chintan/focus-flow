import Foundation

struct IdleDistractionRuleUpsertResult {
    let item: IdleDistractionItem
    let inserted: Bool
}

enum IdleDistractionRuleUpserter {
    static func upsert(
        items: inout [IdleDistractionItem],
        preferredItem: IdleDistractionItem?,
        targetKind: IdleDistractionTargetKind,
        key: String,
        displayName: String,
        severity: IdleDistractionSeverity,
        source: IdleDistractionSource,
        now: Date = Date()
    ) -> IdleDistractionRuleUpsertResult {
        let existingActiveMatch = items.last(where: {
            $0.targetKind == targetKind &&
            $0.key == key &&
            $0.status == .active
        })

        let item: IdleDistractionItem
        let inserted: Bool
        if let preferredItem {
            item = preferredItem
            inserted = false
        } else if let existingActiveMatch {
            item = existingActiveMatch
            inserted = false
        } else {
            item = IdleDistractionItem(
                key: key,
                displayName: displayName,
                targetKind: targetKind,
                severity: severity,
                source: source,
                status: .active,
                evidenceCount: 0,
                createdAt: now,
                updatedAt: now
            )
            items.append(item)
            inserted = true
        }

        item.key = key
        item.displayName = displayName
        item.targetKind = targetKind
        item.severity = severity
        item.source = source
        item.status = .active
        item.updatedAt = now

        for existing in items where existing !== item {
            guard existing.targetKind == targetKind, existing.key == key else { continue }
            if existing.status == .pending || existing.status == .active {
                existing.status = .dismissed
                existing.updatedAt = now
            }
        }

        return IdleDistractionRuleUpsertResult(item: item, inserted: inserted)
    }
}
