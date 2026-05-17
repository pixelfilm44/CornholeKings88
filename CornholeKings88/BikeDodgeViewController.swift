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
        skView.presentScene(scene)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}

extension BikeDodgeViewController: BikeDodgeSceneDelegate {
    func bikeDodgeSceneDidRequestDismiss(_ scene: BikeDodgeScene) {
        dismiss(animated: true)
        onDismiss?()
    }
}
