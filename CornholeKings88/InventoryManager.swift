import Foundation

final class InventoryManager {
    private static let storageKey = "inventoryCounts_v1"

    private(set) var counts: [ItemType: Int] = [:]
    var onChanged: (() -> Void)?
    /// Fired after each collect() with the type granted — lets the host show
    /// a one-time "what this does" hint at the canonical pickup moment.
    var onCollect: ((ItemType) -> Void)?

    init() { load() }

    func collect(_ type: ItemType) {
        counts[type, default: 0] += 1
        save()
        onChanged?()
        onCollect?(type)
    }

    func collect(_ type: ItemType, count: Int) {
        guard count > 0 else { return }
        counts[type, default: 0] += count
        save()
        onChanged?()
        onCollect?(type)
    }

    func consume(_ type: ItemType, count: Int = 1) {
        guard count > 0, let current = counts[type], current > 0 else { return }
        counts[type] = max(0, current - count)
        save()
        onChanged?()
    }

    // MARK: - Persistence

    private func save() {
        let raw = Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(raw, forKey: Self.storageKey)
    }

    private func load() {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: Int] else { return }
        counts = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            ItemType(rawValue: key).map { ($0, value) }
        })
    }
}
