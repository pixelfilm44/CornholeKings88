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

        // Pixel-perfect sizing:
        //   Pick the largest integer N (>=2) such that at least 256x192 source
        //   pixels are visible. Scene size in source pixels = device pixels / N,
        //   so each source pixel maps to exactly N device pixels with no
        //   fractional stretching.
        let scale = skView.contentScaleFactor
        let pixelW = skView.bounds.width * scale
        let pixelH = skView.bounds.height * scale
        // Lower these for MORE zoom (each source pixel becomes a larger block of
        // device pixels). Higher for LESS zoom (more world visible).
        let minSourceWidth: CGFloat = 160
        let minSourceHeight: CGFloat = 120
        let maxByWidth = floor(pixelW / minSourceWidth)
        let maxByHeight = floor(pixelH / minSourceHeight)
        let n = max(2, min(maxByWidth, maxByHeight))
        let sceneW = floor(pixelW / n)
        let sceneH = floor(pixelH / n)

        let scene = GameScene(size: CGSize(width: sceneW, height: sceneH))
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? .allButUpsideDown : .all
    }

    override var prefersStatusBarHidden: Bool { true }
}
