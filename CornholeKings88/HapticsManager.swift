import UIKit

final class HapticsManager {
    static let shared = HapticsManager()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private init() { impact.prepare() }
    func lightImpact() { impact.impactOccurred() }
}
