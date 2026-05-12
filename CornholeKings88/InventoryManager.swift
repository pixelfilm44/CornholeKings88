import Foundation

final class InventoryManager {
    private(set) var counts: [ItemType: Int] = [:]
    var onChanged: (() -> Void)?

    func collect(_ type: ItemType) {
        counts[type, default: 0] += 1
        onChanged?()
    }

    func collect(_ type: ItemType, count: Int) {
        guard count > 0 else { return }
        counts[type, default: 0] += count
        onChanged?()
    }

    func consume(_ type: ItemType, count: Int = 1) {
        guard count > 0, let current = counts[type], current > 0 else { return }
        counts[type] = max(0, current - count)
        onChanged?()
    }
}
