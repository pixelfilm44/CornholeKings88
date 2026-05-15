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
    private weak var closeButton: UIButton?

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

        let btn = buildCloseButton()
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 66),
            btn.heightAnchor.constraint(equalToConstant: 66),
            btn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6)
        ])
        view.bringSubviewToFront(btn)
        closeButton = btn
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

    private func buildCloseButton() -> UIButton {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(named: "closeIcon"), for: .normal)
        btn.imageView?.contentMode = .scaleAspectFit
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return btn
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
        onDismiss?()
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
