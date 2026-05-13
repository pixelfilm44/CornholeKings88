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

        // Pixel-perfect sizing: largest integer N (>=2) keeping ≥160x120 source pixels.
        let scale = skView.contentScaleFactor
        let pixelW = skView.bounds.width * scale
        let pixelH = skView.bounds.height * scale
        let minSourceWidth:  CGFloat = 160
        let minSourceHeight: CGFloat = 120
        let maxByWidth  = floor(pixelW / minSourceWidth)
        let maxByHeight = floor(pixelH / minSourceHeight)
        let n = max(2, min(maxByWidth, maxByHeight))
        let sceneW = floor(pixelW / n)
        let sceneH = floor(pixelH / n)
        // MainMenuScene is a full-screen UI — give it the view's actual point size so
        // didMove(to:) sees the real dimensions.  (GameScene and mini-games still use
        // the pixel-perfect sceneSize they were designed for.)
        let menu = MainMenuScene(size: skView.bounds.size)
        menu.scaleMode = .resizeFill
        menu.menuDelegate = self
        skView.presentScene(menu)
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
