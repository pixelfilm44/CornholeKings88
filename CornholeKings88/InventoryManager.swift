import Foundation

final class InventoryManager {
    private(set) var counts: [ItemType: Int] = [:]
    var onChanged: (() -> Void)?

    func collect(_ type: ItemType) {
        counts[type, default: 0] += 1
        onChanged?()
    }
}
