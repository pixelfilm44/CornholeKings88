import UIKit

final class HapticsManager {
    static let shared = HapticsManager()

    private let lightGen  = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGen  = UIImpactFeedbackGenerator(style: .heavy)
    private let notifGen  = UINotificationFeedbackGenerator()

    private init() {
        lightGen.prepare()
        heavyGen.prepare()
    }

    func lightImpact()      { lightGen.impactOccurred();  lightGen.prepare() }
    func mediumImpact()     { mediumGen.impactOccurred(); mediumGen.prepare() }
    func heavyImpact()      { heavyGen.impactOccurred();  heavyGen.prepare() }
    func successFeedback()  { notifGen.notificationOccurred(.success) }
    func errorFeedback()    { notifGen.notificationOccurred(.error) }
    func warningFeedback()  { notifGen.notificationOccurred(.warning) }
}
