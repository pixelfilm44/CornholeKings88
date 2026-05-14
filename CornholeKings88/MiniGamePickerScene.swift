import SpriteKit
import UIKit

final class MiniGamePickerScene: SKScene {

    var onBikeRace: (() -> Void)?

    private var W: CGFloat = 0, H: CGFloat = 0
    private var buttonSprites: [String: SKSpriteNode] = [:]

    private struct MenuItem {
        let label: String
        let subLabel: String
        let name: String
    }

    private let items: [MenuItem] = [
        MenuItem(label: "STORY MODE",     subLabel: "adventure",  name: "story"),
        MenuItem(label: "BEANBAG BIKE",   subLabel: "racing",     name: "bike"),
        MenuItem(label: "CORNHOLE",       subLabel: "bag toss",   name: "cornhole"),
        MenuItem(label: "BASEBALL",       subLabel: "batting",    name: "baseball"),
        MenuItem(label: "BEEHIVE BATTLE", subLabel: "defense",    name: "beehive"),
        MenuItem(label: "EXPLORE",        subLabel: "open world", name: "explore"),
    ]

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width
        H = size.height
        backgroundColor = SKColor(red: 0.02, green: 0.04, blue: 0.02, alpha: 1)

        setupTopBar()
        setupMenuButtons()
        setupEmbers()
        addCrtOverlay()
    }

    // MARK: - Top bar with title and back button
    private func setupTopBar() {
        let font = "PressStart2P-Regular"
        let barH: CGFloat = 26
        let barY = H / 2 - barH / 2

        // Dark strip
        let barTex = makeStripTexture(width: W, height: barH)
        let bar = SKSpriteNode(texture: barTex, size: CGSize(width: W, height: barH))
        bar.position = CGPoint(x: 0, y: barY)
        bar.zPosition = 10
        addChild(bar)

        // Title
        let title = SKLabelNode(fontNamed: font)
        title.text = "MINI GAMES"
        title.fontSize = min(10, W / 32)
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: barY)
        title.zPosition = 11
        addChild(title)

        // Back button
        let back = SKLabelNode(fontNamed: font)
        back.text = "\u{25C0} BACK"
        back.fontSize = min(7, W / 44)
        back.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
        back.horizontalAlignmentMode = .left
        back.verticalAlignmentMode = .center
        back.position = CGPoint(x: -W / 2 + 12, y: barY)
        back.zPosition = 11
        back.name = "back"
        addChild(back)
    }

    // MARK: - Menu Buttons
    private func setupMenuButtons() {
        let font = "PressStart2P-Regular"
        let barH: CGFloat = 26
        let btnW = min(W * 0.84, 300)
        let btnH: CGFloat = min(50, (H - barH - 40) / CGFloat(items.count) - 10)
        let gap: CGFloat = 10

        let topOfButtons = H / 2 - barH - 20
        let totalH = CGFloat(items.count) * btnH + CGFloat(items.count - 1) * gap
        let footerTop = -H / 2 + 30
        let zone = topOfButtons - footerTop
        let startY = topOfButtons - (zone - totalH) / 2

        var curY = startY

        for item in items {
            let tex = makeButtonTexture(size: CGSize(width: btnW, height: btnH))
            let sprite = SKSpriteNode(texture: tex, size: CGSize(width: btnW, height: btnH))
            let centerY = curY - btnH / 2
            sprite.position = CGPoint(x: 0, y: centerY)
            sprite.zPosition = 20
            sprite.name = item.name
            addChild(sprite)
            buttonSprites[item.name] = sprite

            // Rivets
            addRivet(at: CGPoint(x: -btnW / 2 + 9, y: centerY + btnH / 2 - 9))
            addRivet(at: CGPoint(x: -btnW / 2 + 9, y: centerY - btnH / 2 + 9))

            // Label
            let lbl = SKLabelNode(fontNamed: font)
            lbl.text = item.label
            lbl.fontSize = min(10, btnW / 24)
            lbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: -btnW / 2 + 22, y: centerY + 6)
            lbl.zPosition = 21
            lbl.name = item.name
            addChild(lbl)

            let sub = SKLabelNode(fontNamed: font)
            sub.text = item.subLabel
            sub.fontSize = min(6, btnW / 44)
            sub.fontColor = SKColor(white: 0.55, alpha: 1)
            sub.horizontalAlignmentMode = .left
            sub.verticalAlignmentMode = .center
            sub.position = CGPoint(x: -btnW / 2 + 22, y: centerY - 7)
            sub.zPosition = 21
            sub.name = item.name
            addChild(sub)

            // Arrow
            let arrow = SKLabelNode(fontNamed: font)
            arrow.text = "\u{25B6}"
            arrow.fontSize = min(9, btnW / 30)
            arrow.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 0.80)
            arrow.horizontalAlignmentMode = .right
            arrow.verticalAlignmentMode = .center
            arrow.position = CGPoint(x: btnW / 2 - 14, y: centerY)
            arrow.zPosition = 21
            arrow.name = item.name
            arrow.run(.repeatForever(.sequence([
                .moveBy(x: 2, y: 0, duration: 0.6),
                .moveBy(x: -2, y: 0, duration: 0.6),
            ])))
            addChild(arrow)

            curY -= btnH + gap
        }
    }

    // MARK: - Embers
    private func setupEmbers() {
        let positions: [(CGFloat, CGFloat, Double)] = [
            (0.12, 0.25, 0.0), (0.82, 0.30, 0.8),
            (0.06, 0.60, 1.6), (0.90, 0.65, 2.4),
        ]
        for (px, py, delay) in positions {
            let ember = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            ember.fillColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 0.7)
            ember.strokeColor = .clear
            ember.position = CGPoint(x: -W / 2 + px * W, y: H / 2 - py * H)
            ember.zPosition = 5
            ember.run(.repeatForever(.sequence([
                .wait(forDuration: delay),
                .group([
                    .sequence([.fadeAlpha(to: 1.0, duration: 2.0), .fadeAlpha(to: 0.25, duration: 2.0)]),
                    .sequence([.moveBy(x: 0, y: -5, duration: 2.0), .moveBy(x: 0, y: 5, duration: 2.0)]),
                ]),
            ])))
            addChild(ember)
        }
    }

    // MARK: - Texture Builders

    private func addRivet(at pos: CGPoint) {
        let r = SKShapeNode(circleOfRadius: 2.5)
        r.fillColor = SKColor(white: 0.42, alpha: 1)
        r.strokeColor = SKColor(white: 0.20, alpha: 1)
        r.lineWidth = 0.5
        r.position = pos
        r.zPosition = 21
        addChild(r)
    }

    private func makeStripTexture(width: CGFloat, height: CGFloat) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
            c.setFillColor(UIColor(red: 0.35, green: 0.20, blue: 0.05, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: height - 2, width: width, height: 2))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeButtonTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6)
            c.addPath(path.cgPath); c.clip()

            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1).cgColor,
                UIColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1).cgColor,
                UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1.0])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            // Rust accent
            c.setFillColor(UIColor(red: 0.63, green: 0.31, blue: 0.06, alpha: 0.30).cgColor)
            c.fillEllipse(in: CGRect(x: size.width * 0.62, y: size.height * 0.25, width: size.width * 0.42, height: size.height * 0.75))

            // Highlight + shadow + border
            c.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))
            c.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            c.fill(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3))
            c.setStrokeColor(UIColor(white: 0.07, alpha: 1).cgColor)
            c.setLineWidth(2)
            let border = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2), cornerRadius: 5)
            c.addPath(border.cgPath); c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // MARK: - CRT Overlay
    private func addCrtOverlay() {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: W, height: H))
            c.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            var y: CGFloat = 0
            while y < H { c.fill(CGRect(x: 0, y: y, width: W, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let vColors = [UIColor(white: 0, alpha: 0).cgColor,
                           UIColor(white: 0, alpha: 0.18).cgColor,
                           UIColor(white: 0, alpha: 0.70).cgColor] as CFArray
            let vGrad = CGGradient(colorsSpace: space, colors: vColors, locations: [0, 0.55, 1.0])!
            c.drawRadialGradient(vGrad,
                                 startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                                 endCenter:   CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: W, height: H))
        overlay.position  = .zero
        overlay.zPosition = 100
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        var name = ""
        for node in nodes(at: loc).sorted(by: { $0.zPosition > $1.zPosition }) {
            if let n = node.name, !n.isEmpty { name = n; break }
            if let n = node.parent?.name, !n.isEmpty { name = n; break }
        }
        guard !name.isEmpty else { return }

        if let sprite = buttonSprites[name] {
            sprite.run(.sequence([
                .scale(to: 0.94, duration: 0.07),
                .scale(to: 1.0, duration: 0.07),
            ]))
        }
        handleSelection(name: name)
    }

    private func handleSelection(name: String) {
        let ppSize = pixelPerfectSize() ?? size

        switch name {
        case "back":
            let s = MainMenuScene(size: size)
            s.scaleMode = .resizeFill
            let t = SKTransition.push(with: .down, duration: 0.35)
            t.pausesOutgoingScene = false
            view?.presentScene(s, transition: t)

        case "story":
            let s = StoryModuleScene(size: size)
            s.scaleMode = .resizeFill
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            s.startAtCurrentProgress()
            push(to: s)

        case "bike":
            onBikeRace?()

        case "cornhole":
            let s = CornholeMiniGameScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.availableHoneyBags = 0
            s.onComplete = { _ in }
            push(to: s)

        case "baseball":
            let s = CornholeBaseballScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.onComplete = { _ in }
            push(to: s)

        case "beehive":
            let s = BeeHiveScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.startingHearts = 3
            s.onComplete = { _ in }
            push(to: s)

        case "explore":
            let s = GameScene(size: ppSize)
            s.scaleMode = .resizeFill
            push(to: s)

        default: break
        }
    }

    private func pixelPerfectSize() -> CGSize? {
        guard let v = self.view else { return nil }
        let scale = v.contentScaleFactor
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
