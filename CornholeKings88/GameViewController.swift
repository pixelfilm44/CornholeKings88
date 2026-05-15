import UIKit
import SpriteKit

class GameViewController: UIViewController {

    private var didPresentScene = false

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let skView = view as? SKView else { return }
        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true
        skView.layer.magnificationFilter = .nearest
        skView.layer.minificationFilter = .nearest
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didPresentScene, let skView = view as? SKView else { return }
        didPresentScene = true

        // Show a LoadingScene first that aggressively pre-warms every code path
        // (Metal shader variants, audio decode, fonts, haptics) that previously
        // caused a stutter on first collision. On completion, transition to the menu.
        let loading = LoadingScene(size: skView.bounds.size)
        loading.scaleMode = .resizeFill
        loading.onComplete = { [weak self, weak skView] in
            guard let self = self, let skView = skView else { return }
            let menu = MainMenuScene(size: skView.bounds.size)
            menu.scaleMode = .resizeFill
            menu.menuDelegate = self
            skView.presentScene(menu, transition: SKTransition.fade(withDuration: 0.3))
        }
        skView.presentScene(loading)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? .allButUpsideDown : .all
    }

    override var prefersStatusBarHidden: Bool { true }
}

// MARK: - MainMenuSceneDelegate
extension GameViewController: MainMenuSceneDelegate {
    func mainMenuSceneDidSelectBikeRace(_ scene: MainMenuScene) {
        let bikeVC = BikeDodgeViewController()
        bikeVC.modalPresentationStyle = .fullScreen
        present(bikeVC, animated: true)
    }
}
