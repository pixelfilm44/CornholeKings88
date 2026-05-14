import SpriteKit
import UIKit

// MARK: - Delegate
protocol MainMenuSceneDelegate: AnyObject {
    func mainMenuSceneDidSelectBikeRace(_ scene: MainMenuScene)
}

// MARK: - Main Menu Scene
final class MainMenuScene: SKScene {

    weak var menuDelegate: MainMenuSceneDelegate?

    // MARK: - Layout (set from view bounds in didMove)
    private var W: CGFloat = 0, H: CGFloat = 0

    // MARK: - Scrolling road strip
    private var roadTile1: SKSpriteNode!
    private var roadTile2: SKSpriteNode!
    private let scrollSpeed: CGFloat = 60

    // MARK: - Buttons
    private struct MenuItem {
        let label: String, subLabel: String
        let color: SKColor, name: String
    }
    private let items: [MenuItem] = [
        MenuItem(label: "STORY MODE",     subLabel: "adventure", color: SKColor(red:0.72,green:0.28,blue:0.92,alpha:1), name: "story"),
        MenuItem(label: "BEANBAG BIKE",   subLabel: "racing",    color: SKColor(red:0.10,green:0.85,blue:0.90,alpha:1), name: "bike"),
        MenuItem(label: "CORNHOLE",       subLabel: "bag toss",  color: SKColor(red:0.95,green:0.85,blue:0.10,alpha:1), name: "cornhole"),
        MenuItem(label: "BASEBALL",       subLabel: "batting",   color: SKColor(red:0.95,green:0.45,blue:0.10,alpha:1), name: "baseball"),
        MenuItem(label: "BEEHIVE BATTLE", subLabel: "defense",   color: SKColor(red:0.95,green:0.80,blue:0.05,alpha:1), name: "beehive"),
        MenuItem(label: "EXPLORE",        subLabel: "open world",color: SKColor(red:0.40,green:0.90,blue:0.40,alpha:1), name: "explore"),
    ]
    private var buttonNodes: [SKNode] = []

    // MARK: - didMove
    override func didMove(to view: SKView) {
        // Anchor at center so (0,0) == screen center — must be set before any layout.
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Use view bounds directly; the scene was created with view.bounds.size so
        // size already equals view.bounds.size, but reading it here is the safe pattern.
        W = size.width
        H = size.height

        backgroundColor = SKColor(red: 0.08, green: 0.10, blue: 0.08, alpha: 1)

        setupBackground()
        setupTitle()
        setupMenuButtons()
        setupFooter()
    }

    // MARK: - Background road strip (decorative, faint)
    private func setupBackground() {
        let rw = W * 0.38
        let tex = makeRoadStrip(width: rw, height: H)
        let sz  = CGSize(width: rw, height: H)

        roadTile1 = SKSpriteNode(texture: tex, size: sz)
        roadTile1.position  = .zero; roadTile1.alpha = 0.30; roadTile1.zPosition = -5
        addChild(roadTile1)

        roadTile2 = SKSpriteNode(texture: tex, size: sz)
        roadTile2.position  = CGPoint(x: 0, y: H); roadTile2.alpha = 0.30; roadTile2.zPosition = -5
        addChild(roadTile2)
    }

    private func makeRoadStrip(width: CGFloat, height: CGFloat) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.18, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
            c.setFillColor(UIColor(white: 0.82, alpha: 1).cgColor)
            c.fill(CGRect(x: 0,       y: 0, width: 3, height: height))
            c.fill(CGRect(x: width-3, y: 0, width: 3, height: height))
            c.setStrokeColor(UIColor(red: 0.95, green: 0.85, blue: 0.10, alpha: 1).cgColor)
            c.setLineWidth(2); c.setLineDash(phase: 0, lengths: [16, 10])
            let cx = width / 2
            c.move(to: CGPoint(x: cx, y: 0)); c.addLine(to: CGPoint(x: cx, y: height))
            c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // MARK: - Title  (plain SKLabelNodes — no SKEffectNode wrapping)
    private func setupTitle() {
        let font = "PressStart2P-Regular"

        // Main title
        let title = SKLabelNode(fontNamed: font)
        title.text      = "CORNHOLE KINGS"
        title.fontSize  = min(22, W / 14)
        title.fontColor = SKColor(red: 0.95, green: 0.82, blue: 0.10, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position  = CGPoint(x: 0, y: H/2 - 88)
        title.zPosition = 10
        title.run(.repeatForever(.sequence([
            .scale(to: 1.03, duration: 1.2),
            .scale(to: 0.97, duration: 1.2)
        ])))
        addChild(title)

        // Subtitle
        let sub = SKLabelNode(fontNamed: font)
        sub.text      = "CHOOSE YOUR GAME"
        sub.fontSize  = min(9, W / 36)
        sub.fontColor = SKColor(white: 0.60, alpha: 1)
        sub.horizontalAlignmentMode = .center
        sub.verticalAlignmentMode   = .center
        sub.position  = CGPoint(x: 0, y: H/2 - 122)
        sub.zPosition = 10
        addChild(sub)
    }

    // MARK: - Menu buttons
    private func setupMenuButtons() {
        let font    = "PressStart2P-Regular"
        let btnH:   CGFloat = min(54, H / 11)
        let btnW:   CGFloat = W * 0.82
        let spacing = btnH + 12

        // Start just below the subtitle, centered vertically in remaining space
        let topMargin: CGFloat = H/2 - 148            // just below subtitle
        let totalBtnsH = CGFloat(items.count) * spacing - 12
        let startY = topMargin - (topMargin - (-H/2 + 40) - totalBtnsH) / 2 - btnH/2

        for (i, item) in items.enumerated() {
            let container = SKNode()
            container.position  = CGPoint(x: 0, y: startY - CGFloat(i) * spacing)
            container.zPosition = 20
            container.name      = item.name

            // Pill background
            let pill = SKShapeNode(rect: CGRect(x: -btnW/2, y: -btnH/2, width: btnW, height: btnH),
                                   cornerRadius: 8)
            pill.fillColor   = SKColor(white: 0.13, alpha: 0.92)
            pill.strokeColor = item.color.withAlphaComponent(0.55)
            pill.lineWidth   = 1.5
            pill.name        = item.name
            container.addChild(pill)

            // Left accent bar
            let bar = SKShapeNode(rect: CGRect(x: -btnW/2, y: -btnH/2, width: 5, height: btnH),
                                  cornerRadius: 4)
            bar.fillColor = item.color; bar.strokeColor = .clear; bar.name = item.name
            container.addChild(bar)

            // Game name label
            let lbl = SKLabelNode(fontNamed: font)
            lbl.text = item.label; lbl.fontSize = min(12, W / 26)
            lbl.fontColor = item.color
            lbl.horizontalAlignmentMode = .left; lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: -btnW/2 + 18, y: 7); lbl.name = item.name
            container.addChild(lbl)

            // Sub-label
            let sub = SKLabelNode(fontNamed: font)
            sub.text = item.subLabel; sub.fontSize = min(7, W / 50)
            sub.fontColor = SKColor(white: 0.48, alpha: 1)
            sub.horizontalAlignmentMode = .left; sub.verticalAlignmentMode = .center
            sub.position = CGPoint(x: -btnW/2 + 18, y: -9); sub.name = item.name
            container.addChild(sub)

            // Right arrow
            let arrow = SKLabelNode(fontNamed: font)
            arrow.text = "▶"; arrow.fontSize = min(10, W / 34)
            arrow.fontColor = item.color.withAlphaComponent(0.65)
            arrow.horizontalAlignmentMode = .right; arrow.verticalAlignmentMode = .center
            arrow.position = CGPoint(x: btnW/2 - 14, y: 0); arrow.name = item.name
            container.addChild(arrow)

            addChild(container)
            buttonNodes.append(container)
        }
    }

    private func setupFooter() {
        let font = "PressStart2P-Regular"

        let lbl = SKLabelNode(fontNamed: font)
        lbl.text      = "CORNHOLE KINGS  v1.0"
        lbl.fontSize  = min(7, W / 52)
        lbl.fontColor = SKColor(white: 0.28, alpha: 1)
        lbl.horizontalAlignmentMode = .center
        lbl.position  = CGPoint(x: 0, y: -H/2 + 22)
        lbl.zPosition = 10
        addChild(lbl)

        // Temporary reset utility — wipes story progress back to chapter 1
        let reset = SKLabelNode(fontNamed: font)
        reset.text      = "RESET STORY"
        reset.fontSize  = min(6, W / 56)
        reset.fontColor = SKColor(white: 0.24, alpha: 1)
        reset.horizontalAlignmentMode = .right
        reset.position  = CGPoint(x: W/2 - 14, y: -H/2 + 10)
        reset.zPosition = 10
        reset.name      = "resetStory"
        addChild(reset)
    }

    // MARK: - Update (scroll road strip)
    override func update(_ currentTime: TimeInterval) {
        guard roadTile1 != nil else { return }
        let dy = scrollSpeed * 0.016
        roadTile1.position.y -= dy
        roadTile2.position.y -= dy
        if roadTile1.position.y + H/2 < -H/2 { roadTile1.position.y = roadTile2.position.y + H }
        if roadTile2.position.y + H/2 < -H/2 { roadTile2.position.y = roadTile1.position.y + H }
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc    = touch.location(in: self)
        let tapped = atPoint(loc)
        let name   = tapped.name ?? tapped.parent?.name ?? ""
        guard !name.isEmpty else { return }

        // Tap feedback
        buttonNodes.first(where: { $0.name == name })?.run(
            .sequence([.scale(to: 0.94, duration: 0.07), .scale(to: 1.0, duration: 0.07)])
        )
        handleSelection(name: name)
    }

    private func handleSelection(name: String) {
        // Mini-games and GameScene need the pixel-perfect small coordinate space.
        let ppSize = pixelPerfectSize() ?? size

        switch name {
        case "story":
            let s = StoryModuleScene(size: size)
            s.scaleMode = .resizeFill
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            s.startAtCurrentProgress()
            push(to: s)

        case "resetStory":
            StoryManager.shared.reset()
            // Brief visual confirmation
            if let node = childNode(withName: "resetStory") as? SKLabelNode {
                node.run(.sequence([
                    .run { node.fontColor = SKColor(red: 0.72, green: 0.28, blue: 0.92, alpha: 1) },
                    .wait(forDuration: 0.6),
                    .run { node.fontColor = SKColor(white: 0.24, alpha: 1) }
                ]))
            }

        case "bike":
            menuDelegate?.mainMenuSceneDidSelectBikeRace(self)

        case "cornhole":
            let s = CornholeMiniGameScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.availableHoneyBags = 0; s.onComplete = { _ in }
            push(to: s)

        case "baseball":
            let s = CornholeBaseballScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.onComplete = { _ in }
            push(to: s)

        case "beehive":
            let s = BeeHiveScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.startingHearts = 3; s.onComplete = { _ in }
            push(to: s)

        case "explore":
            let s = GameScene(size: ppSize)
            s.scaleMode = .resizeFill
            push(to: s)

        default: break
        }
    }

    // MARK: - Helpers

    /// Computes the same pixel-perfect scene size that GameViewController uses,
    /// so mini-games and GameScene receive the coordinate space they expect.
    private func pixelPerfectSize() -> CGSize? {
        guard let v = self.view else { return nil }
        let scale  = v.contentScaleFactor
        let pixelW = v.bounds.width  * scale
        let pixelH = v.bounds.height * scale
        let n = max(2, min(floor(pixelW / 160), floor(pixelH / 120)))
        return CGSize(width: floor(pixelW / n), height: floor(pixelH / n))
    }

    private func push(to scene: SKScene) {
        let t = SKTransition.push(with: .up, duration: 0.35)
        t.pausesOutgoingScene = false
        view?.presentScene(scene, transition: t)
    }
}
