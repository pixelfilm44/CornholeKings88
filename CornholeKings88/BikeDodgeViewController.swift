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

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20)
        closeBtn.tintColor = .white
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        closeBtn.layer.cornerRadius = 20
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.widthAnchor.constraint(equalToConstant: 40),
            closeBtn.heightAnchor.constraint(equalToConstant: 40),
            closeBtn.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        // keep close button above SpriteKit
        view.bringSubviewToFront(closeBtn)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard skView.scene == nil else { return }
        let scene = BikeDodgeScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        scene.bikeDodgeDelegate = self
        skView.presentScene(scene)
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
