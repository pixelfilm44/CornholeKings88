import SpriteKit
import UIKit

// MARK: - Delegate
protocol MainMenuSceneDelegate: AnyObject {
    func mainMenuSceneDidSelectBikeRace(_ scene: MainMenuScene)
}

// MARK: - Main Menu Scene
final class MainMenuScene: SKScene {

    weak var menuDelegate: MainMenuSceneDelegate?

    private var W: CGFloat = 0, H: CGFloat = 0

    private struct MenuItem {
        let label: String
        let subLabel: String
        let name: String
        let isPrimary: Bool
    }

    private let items: [MenuItem] = [
        MenuItem(label: "PLAY",       subLabel: "adventure",   name: "story",     isPrimary: true),
        MenuItem(label: "MINI GAMES", subLabel: "pick a game", name: "minigames", isPrimary: false),
        MenuItem(label: "STATS",      subLabel: "records",     name: "stats",     isPrimary: false),
        MenuItem(label: "SETTINGS",   subLabel: "options",     name: "settings",  isPrimary: false),
    ]

    private var buttonSprites: [String: SKSpriteNode] = [:]

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width
        H = size.height

        backgroundColor = SKColor(red: 0.02, green: 0.04, blue: 0.02, alpha: 1)

        setupTopStrip()
        setupCrest()   // calls setupMenuButtons(crestBottom:) internally
        setupEmbers()
        setupFooter()
    }

    // MARK: - Top strip
    private func setupTopStrip() {
        let font = "PressStart2P-Regular"
        let stripH: CGFloat = 20
        let stripY = H / 2 - stripH / 2

        let bg = SKSpriteNode(texture: makeTopStripTexture(width: W, height: stripH),
                              size: CGSize(width: W, height: stripH))
        bg.position = CGPoint(x: 0, y: stripY)
        bg.zPosition = 10
        addChild(bg)

        let ver = SKLabelNode(fontNamed: font)
        ver.text = "v1.0.0  OFFLINE"
        ver.fontSize = min(5, W / 58)
        ver.fontColor = SKColor(white: 0.53, alpha: 1)
        ver.horizontalAlignmentMode = .left
        ver.verticalAlignmentMode = .center
        ver.position = CGPoint(x: -W / 2 + 10, y: stripY)
        ver.zPosition = 11
        addChild(ver)

        let coin = SKLabelNode(fontNamed: font)
        coin.text = "\u{25C6} 1,247"
        coin.fontSize = min(5, W / 58)
        coin.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
        coin.horizontalAlignmentMode = .right
        coin.verticalAlignmentMode = .center
        coin.position = CGPoint(x: W / 2 - 10, y: stripY)
        coin.zPosition = 11
        addChild(coin)
    }

    // MARK: - Crest
    private func setupCrest() {
        let font = "PressStart2P-Regular"
        let stripH: CGFloat = 20

        // Lay out crest as a block from stripBottom downward
        let stripBottom = H / 2 - stripH
        let emblemSize: CGFloat = 40
        let plaqueW = min(W * 0.72, 240)
        let plaqueH: CGFloat = 74
        let padding: CGFloat = 8

        let crestTop = stripBottom - 20
        let emblemCY = crestTop - emblemSize / 2
        let plaqueCY = emblemCY - emblemSize / 2 - padding - plaqueH / 2

        // Emblem
        let emblemTex = makeEmblemTexture(size: CGSize(width: emblemSize, height: emblemSize))
        let emblem = SKSpriteNode(texture: emblemTex, size: CGSize(width: emblemSize, height: emblemSize))
        emblem.position = CGPoint(x: 0, y: emblemCY)
        emblem.zPosition = 10
        addChild(emblem)

        // Wooden plaque
        let plaque = SKSpriteNode(texture: makePlaqueTexture(size: CGSize(width: plaqueW, height: plaqueH)),
                                  size: CGSize(width: plaqueW, height: plaqueH))
        plaque.position = CGPoint(x: 0, y: plaqueCY)
        plaque.zPosition = 10
        addChild(plaque)

        // Rivet dots
        let rv: CGFloat = plaqueH / 2 - 6
        let rh: CGFloat = plaqueW / 2 - 6
        for (dx, dy) in [(-rh, rv), (rh, rv), (-rh, -rv), (rh, -rv)] {
            addRivet(at: CGPoint(x: dx, y: plaqueCY + dy), radius: 3.5, z: 15)
        }

        // "CORNHOLE" top line
        let titleFS = min(18, plaqueW / 12)
        let titleColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)

        let line1 = SKLabelNode(fontNamed: font)
        line1.text = "CORNHOLE"
        line1.fontSize = titleFS
        line1.fontColor = titleColor
        line1.horizontalAlignmentMode = .center
        line1.verticalAlignmentMode = .center
        line1.position = CGPoint(x: 0, y: plaqueCY + titleFS * 0.55)
        line1.zPosition = 11
        addChild(line1)

        let line2 = SKLabelNode(fontNamed: font)
        line2.text = "KINGS"
        line2.fontSize = titleFS
        line2.fontColor = titleColor
        line2.horizontalAlignmentMode = .center
        line2.verticalAlignmentMode = .center
        line2.position = CGPoint(x: 0, y: plaqueCY - titleFS * 0.55)
        line2.zPosition = 11
        addChild(line2)

        // Store bottom of crest for button layout
        let crestBottom = plaqueCY - plaqueH / 2
        setupMenuButtons(crestBottom: crestBottom)
    }

    // MARK: - Menu Buttons
    // Called from setupCrest so we have crestBottom
    private func setupMenuButtons(crestBottom: CGFloat) {
        let font = "PressStart2P-Regular"
        let btnW = min(W * 0.84, 300)
        let primaryH: CGFloat = 56
        let normalH: CGFloat = 46
        let gap: CGFloat = 10
        let footerTop = -H / 2 + 40

        let totalBtnsH = primaryH + CGFloat(items.count - 1) * (normalH + gap)
        let zone = crestBottom - 16
        let availableH = zone - footerTop
        let startY = zone - (availableH - totalBtnsH) / 2

        var curY = startY

        for item in items {
            let btnH = item.isPrimary ? primaryH : normalH

            let tex = makeButtonTexture(size: CGSize(width: btnW, height: btnH), isPrimary: item.isPrimary)
            let sprite = SKSpriteNode(texture: tex, size: CGSize(width: btnW, height: btnH))
            let centerY = curY - btnH / 2
            sprite.position = CGPoint(x: 0, y: centerY)
            sprite.zPosition = 20
            sprite.name = item.name
            addChild(sprite)
            buttonSprites[item.name] = sprite

            // Left-side rivets
            addRivet(at: CGPoint(x: -btnW / 2 + 9, y: centerY + btnH / 2 - 9), radius: 2.5, z: 21)
            addRivet(at: CGPoint(x: -btnW / 2 + 9, y: centerY - btnH / 2 + 9), radius: 2.5, z: 21)

            // Label
            let titleColor: SKColor = item.isPrimary
                ? SKColor(red: 1.0, green: 0.89, blue: 0.69, alpha: 1)
                : SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
            let titleFS: CGFloat = item.isPrimary ? min(14, btnW / 18) : min(11, btnW / 23)

            let lbl = SKLabelNode(fontNamed: font)
            lbl.text = item.label
            lbl.fontSize = titleFS
            lbl.fontColor = titleColor
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: -btnW / 2 + 22, y: centerY + (item.isPrimary ? 9 : 7))
            lbl.zPosition = 21
            lbl.name = item.name
            addChild(lbl)

            let sub = SKLabelNode(fontNamed: font)
            sub.text = item.subLabel
            sub.fontSize = min(6, btnW / 44)
            sub.fontColor = item.isPrimary
                ? SKColor(red: 0.84, green: 0.63, blue: 0.38, alpha: 1)
                : SKColor(white: 0.67, alpha: 1)
            sub.horizontalAlignmentMode = .left
            sub.verticalAlignmentMode = .center
            sub.position = CGPoint(x: -btnW / 2 + 22, y: centerY - (item.isPrimary ? 9 : 7))
            sub.zPosition = 21
            sub.name = item.name
            addChild(sub)

            // Arrow (animated)
            let arrow = SKLabelNode(fontNamed: font)
            arrow.text = "\u{25B6}"
            arrow.fontSize = min(10, btnW / 28)
            arrow.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 0.85)
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

    // MARK: - Ember particles
    private func setupEmbers() {
        let positions: [(CGFloat, CGFloat, Double)] = [
            (0.18, 0.18, 0.0), (0.78, 0.24, 0.6), (0.08, 0.46, 1.2),
            (0.88, 0.52, 1.8), (0.18, 0.72, 2.4), (0.72, 0.78, 3.0),
        ]
        for (px, py, delay) in positions {
            let ember = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            ember.fillColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 0.8)
            ember.strokeColor = .clear
            ember.position = CGPoint(x: -W / 2 + px * W, y: H / 2 - py * H)
            ember.zPosition = 5
            ember.run(.repeatForever(.sequence([
                .wait(forDuration: delay),
                .group([
                    .sequence([.fadeAlpha(to: 1.0, duration: 2.0), .fadeAlpha(to: 0.3, duration: 2.0)]),
                    .sequence([.moveBy(x: 0, y: -5, duration: 2.0), .moveBy(x: 0, y: 5, duration: 2.0)]),
                ]),
            ])))
            addChild(ember)
        }
    }

    // MARK: - Footer
    private func setupFooter() {
        let font = "PressStart2P-Regular"
        let y = -H / 2 + 18

        let copy = SKLabelNode(fontNamed: font)
        copy.text = "\u{00A9} 2026 CK88"
        copy.fontSize = min(5, W / 60)
        copy.fontColor = SKColor(white: 0.40, alpha: 1)
        copy.horizontalAlignmentMode = .left
        copy.verticalAlignmentMode = .center
        copy.position = CGPoint(x: -W / 2 + 12, y: y)
        copy.zPosition = 10
        addChild(copy)

        let press = SKLabelNode(fontNamed: font)
        press.text = "PRESS START"
        press.fontSize = min(6, W / 52)
        press.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
        press.horizontalAlignmentMode = .center
        press.verticalAlignmentMode = .center
        press.position = CGPoint(x: 0, y: y)
        press.zPosition = 10
        press.run(.repeatForever(.sequence([
            .fadeIn(withDuration: 0),
            .wait(forDuration: 0.7),
            .fadeAlpha(to: 0.3, duration: 0),
            .wait(forDuration: 0.7),
        ])))
        addChild(press)

        let lr = SKLabelNode(fontNamed: font)
        lr.text = "L1 \u{25C6} R1"
        lr.fontSize = min(5, W / 60)
        lr.fontColor = SKColor(white: 0.40, alpha: 1)
        lr.horizontalAlignmentMode = .right
        lr.verticalAlignmentMode = .center
        lr.position = CGPoint(x: W / 2 - 12, y: y)
        lr.zPosition = 10
        addChild(lr)

        let reset = SKLabelNode(fontNamed: font)
        reset.text = "RESET STORY"
        reset.fontSize = min(5, W / 60)
        reset.fontColor = SKColor(white: 0.20, alpha: 1)
        reset.horizontalAlignmentMode = .right
        reset.verticalAlignmentMode = .center
        reset.position = CGPoint(x: W / 2 - 12, y: y + 14)
        reset.zPosition = 10
        reset.name = "resetStory"
        addChild(reset)
    }

    // MARK: - Texture Builders

    private func addRivet(at pos: CGPoint, radius: CGFloat, z: CGFloat) {
        let r = SKShapeNode(circleOfRadius: radius)
        r.fillColor = SKColor(white: 0.42, alpha: 1)
        r.strokeColor = SKColor(white: 0.20, alpha: 1)
        r.lineWidth = 0.5
        r.position = pos
        r.zPosition = z
        addChild(r)
    }

    private func makeTopStripTexture(width: CGFloat, height: CGFloat) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Bottom accent line in wood color
            c.setFillColor(UIColor(red: 0.35, green: 0.20, blue: 0.05, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: height - 2, width: width, height: 2))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeEmblemTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let cx = size.width / 2, cy = size.height / 2

            // Blue bag (rotate 30°)
            c.saveGState()
            c.translateBy(x: cx, y: cy)
            c.rotate(by: .pi / 6)
            c.setFillColor(UIColor(red: 0.29, green: 0.56, blue: 0.86, alpha: 1).cgColor)
            c.setStrokeColor(UIColor(red: 0.06, green: 0.16, blue: 0.33, alpha: 1).cgColor)
            c.setLineWidth(1)
            let bag1 = UIBezierPath(roundedRect: CGRect(x: -12, y: -3, width: 24, height: 6), cornerRadius: 1)
            c.addPath(bag1.cgPath); c.drawPath(using: .fillStroke)
            c.restoreGState()

            // Red bag (rotate -30°)
            c.saveGState()
            c.translateBy(x: cx, y: cy)
            c.rotate(by: -.pi / 6)
            c.setFillColor(UIColor(red: 0.78, green: 0.13, blue: 0.10, alpha: 1).cgColor)
            c.setStrokeColor(UIColor(red: 0.23, green: 0.04, blue: 0.02, alpha: 1).cgColor)
            c.setLineWidth(1)
            let bag2 = UIBezierPath(roundedRect: CGRect(x: -12, y: -3, width: 24, height: 6), cornerRadius: 1)
            c.addPath(bag2.cgPath); c.drawPath(using: .fillStroke)
            c.restoreGState()

            // Center gold dot
            c.setFillColor(UIColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1).cgColor)
            c.setStrokeColor(UIColor(red: 0.35, green: 0.23, blue: 0.03, alpha: 1).cgColor)
            c.setLineWidth(0.5)
            c.addEllipse(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
            c.drawPath(using: .fillStroke)
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makePlaqueTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            c.addPath(path.cgPath); c.clip()

            // Wood gradient
            let space = CGColorSpaceCreateDeviceRGB()
            let woodColors = [
                UIColor(red: 0.48, green: 0.31, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.36, green: 0.20, blue: 0.09, alpha: 1).cgColor,
                UIColor(red: 0.24, green: 0.12, blue: 0.03, alpha: 1).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: space, colors: woodColors, locations: [0, 0.6, 1.0])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            // Wood grain lines
            c.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
            var x: CGFloat = 12
            while x < size.width {
                c.fill(CGRect(x: x, y: 0, width: 2, height: size.height))
                x += 14
            }

            // Top highlight
            c.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))

            // Bottom shadow
            c.setFillColor(UIColor(white: 0, alpha: 0.40).cgColor)
            c.fill(CGRect(x: 0, y: size.height - 5, width: size.width, height: 5))

            // Border
            c.setStrokeColor(UIColor(red: 0.16, green: 0.09, blue: 0.03, alpha: 1).cgColor)
            c.setLineWidth(3)
            let border = UIBezierPath(roundedRect: CGRect(x: 1.5, y: 1.5, width: size.width - 3, height: size.height - 3), cornerRadius: 4)
            c.addPath(border.cgPath); c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeButtonTexture(size: CGSize, isPrimary: Bool) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6)
            c.addPath(path.cgPath); c.clip()

            let space = CGColorSpaceCreateDeviceRGB()
            if isPrimary {
                // Warm wood/brown
                let colors = [
                    UIColor(red: 0.48, green: 0.23, blue: 0.09, alpha: 1).cgColor,
                    UIColor(red: 0.35, green: 0.16, blue: 0.06, alpha: 1).cgColor,
                    UIColor(red: 0.23, green: 0.10, blue: 0.03, alpha: 1).cgColor,
                ] as CFArray
                let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1.0])!
                c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                // Warm glow accent
                c.setFillColor(UIColor(red: 0.78, green: 0.55, blue: 0.16, alpha: 0.20).cgColor)
                c.fillEllipse(in: CGRect(x: size.width * 0.55, y: size.height * 0.25, width: size.width * 0.5, height: size.height * 0.9))
            } else {
                // Iron
                let colors = [
                    UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1).cgColor,
                    UIColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1).cgColor,
                    UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor,
                ] as CFArray
                let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1.0])!
                c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                // Rust spots
                c.setFillColor(UIColor(red: 0.63, green: 0.31, blue: 0.06, alpha: 0.35).cgColor)
                c.fillEllipse(in: CGRect(x: size.width * 0.62, y: size.height * 0.30, width: size.width * 0.42, height: size.height * 0.75))
                c.setFillColor(UIColor(red: 0.55, green: 0.24, blue: 0.04, alpha: 0.28).cgColor)
                c.fillEllipse(in: CGRect(x: -size.width * 0.05, y: size.height * 0.45, width: size.width * 0.28, height: size.height * 0.65))
            }

            // Top highlight
            c.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))

            // Bottom shadow
            c.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            c.fill(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3))

            // Border
            c.setStrokeColor(UIColor(white: 0.07, alpha: 1).cgColor)
            c.setLineWidth(2)
            let border = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2), cornerRadius: 5)
            c.addPath(border.cgPath); c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        let tapped = atPoint(loc)
        let name = tapped.name ?? tapped.parent?.name ?? ""
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
        switch name {
        case "story":
            let s = StoryModuleScene(size: size)
            s.scaleMode = .resizeFill
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            s.startAtCurrentProgress()
            push(to: s)

        case "minigames":
            let s = MiniGamePickerScene(size: size)
            s.scaleMode = .resizeFill
            s.onBikeRace = { [weak self] in
                guard let self = self else { return }
                self.menuDelegate?.mainMenuSceneDidSelectBikeRace(self)
            }
            push(to: s)

        case "stats":
            let s = StatsScene(size: size)
            s.scaleMode = .resizeFill
            push(to: s)

        case "settings":
            showComingSoon()

        case "resetStory":
            StoryManager.shared.reset()
            if let lbl = childNode(withName: "resetStory") as? SKLabelNode {
                let gold = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
                let dim  = SKColor(white: 0.20, alpha: 1)
                lbl.run(.sequence([
                    .run { lbl.fontColor = gold },
                    .wait(forDuration: 0.6),
                    .run { lbl.fontColor = dim },
                ]))
            }

        default: break
        }
    }

    private func showComingSoon() {
        let font = "PressStart2P-Regular"
        let lbl = SKLabelNode(fontNamed: font)
        lbl.text = "COMING SOON"
        lbl.fontSize = min(10, W / 30)
        lbl.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: 0, y: 0)
        lbl.zPosition = 50
        addChild(lbl)
        lbl.run(.sequence([
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    // MARK: - Helpers
    private func push(to scene: SKScene) {
        let t = SKTransition.push(with: .up, duration: 0.35)
        t.pausesOutgoingScene = false
        view?.presentScene(scene, transition: t)
    }
}
