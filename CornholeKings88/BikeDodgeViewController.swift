import UIKit
import SpriteKit

// MARK: - Scene delegate (scene → VC communication)
protocol BikeDodgeSceneDelegate: AnyObject {
    func bikeDodgeSceneDidRequestDismiss(_ scene: BikeDodgeScene)
}

// MARK: - View Controller
final class BikeDodgeViewController: UIViewController {

    private var skView: SKView!
    var onDismiss: (() -> Void)?
    /// Called after dismiss with the race result (true = player won).
    var onDismissWithResult: ((Bool) -> Void)?
    private var bikeResult: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        skView = SKView(frame: view.bounds)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
        skView.layer.magnificationFilter = .nearest
        skView.layer.minificationFilter = .nearest
        view.addSubview(skView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MusicPlayer.shared.play(named: "RacingMusic")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        MusicPlayer.shared.play(named: "CornholeKingsTheme")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard skView.scene == nil else { return }
        let scene = BikeDodgeScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        scene.bikeDodgeDelegate = self
        scene.awardsRewards = true   // bike is reached only via story → grants the world unlock
        scene.onComplete = { [weak self] won in self?.bikeResult = won }
        skView.presentScene(scene)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // Defer iOS system gestures (home indicator, Control Center, Notification Center)
    // across the whole screen so steering touches in edge zones are delivered to the
    // scene immediately instead of being held for ~2s by the system-gesture gate.
    // First swipe in an edge dims the home indicator; second activates the system gesture.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

extension BikeDodgeViewController: BikeDodgeSceneDelegate {
    func bikeDodgeSceneDidRequestDismiss(_ scene: BikeDodgeScene) {
        let result = bikeResult
        dismiss(animated: true) { [weak self] in
            self?.onDismissWithResult?(result)
            self?.onDismiss?()
        }
    }
}
