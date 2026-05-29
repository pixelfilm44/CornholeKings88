import SpriteKit
import UIKit

final class SettingsScene: SKScene {

    private var W: CGFloat = 0, H: CGFloat = 0
    private var ribbonBottomY: CGFloat = 0   // scene-Y of bottom edge of the top ribbon
    private var confirmLabel: SKLabelNode?

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width
        H = size.height

        backgroundColor = SKColor(red: 0.02, green: 0.04, blue: 0.02, alpha: 1)

        setupTopStrip()
        setupPlaque()
        setupOptions()
        setupFooter()
        setupEmbers()
        addCrtOverlay()
    }

    // MARK: - Top ribbon (DS standard: #1a0a04 + 2px gold border, safe-area aware)
    private func setupTopStrip() {
        let dsPrimary = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1) // #1a0a04
        let dsGold    = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060

        let topInset  = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let topBarY   = H / 2 - totalTopH / 2
        ribbonBottomY = H / 2 - totalTopH

        let bar = SKSpriteNode(color: dsPrimary, size: CGSize(width: W, height: totalTopH))
        bar.position  = CGPoint(x: 0, y: topBarY)
        bar.zPosition = 10
        addChild(bar)

        let border = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        border.position  = CGPoint(x: 0, y: ribbonBottomY + 1)
        border.zPosition = 11
        addChild(border)

        let contentY = H / 2 - topInset - topH / 2
        let back = SKSpriteNode(imageNamed: "closeIcon")
        back.size             = CGSize(width: 22, height: 22)
        back.texture?.filteringMode = .nearest
        back.position  = CGPoint(x: W / 2 - 22, y: contentY)
        back.zPosition = 12
        back.name      = "back"
        addChild(back)

        let font = "PressStart2P-Regular"
        let title = SKLabelNode(fontNamed: font)
        title.text = "SETTINGS"
        title.fontSize = 8
        title.fontColor = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position  = CGPoint(x: 0, y: contentY)
        title.zPosition = 12
        addChild(title)
    }

    // MARK: - Wooden plaque header
    private func setupPlaque() {
        let font = "PressStart2P-Regular"

        let plaqueW = min(W * 0.72, 240)
        let plaqueH: CGFloat = 52
        let plaqueY = ribbonBottomY - 16 - plaqueH / 2

        let plaque = SKSpriteNode(texture: makePlaqueTexture(size: CGSize(width: plaqueW, height: plaqueH)),
                                  size: CGSize(width: plaqueW, height: plaqueH))
        plaque.position = CGPoint(x: 0, y: plaqueY)
        plaque.zPosition = 10
        addChild(plaque)

        let rv: CGFloat = plaqueH / 2 - 6
        let rh: CGFloat = plaqueW / 2 - 6
        for (dx, dy) in [(-rh, rv), (rh, rv), (-rh, -rv), (rh, -rv)] {
            addRivet(at: CGPoint(x: dx, y: plaqueY + dy), radius: 3.5, z: 15)
        }

        let titleFS = min(13, plaqueW / 14)
        let lbl = SKLabelNode(fontNamed: font)
        lbl.text = "OPTIONS"
        lbl.fontSize = titleFS
        lbl.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: 0, y: plaqueY)
        lbl.zPosition = 11
        addChild(lbl)
    }

    // MARK: - Option cards
    private func setupOptions() {
        let plaqueH: CGFloat = 52
        let topContentY = ribbonBottomY - 16 - plaqueH - 20

        let cardW = min(W * 0.84, 300)
        let cardH: CGFloat = 60

        let cardY = topContentY - cardH / 2
        drawCard(label: "TUTORIALS",
                 sub: "show again on next play",
                 action: "RESET",
                 name: "resetTutorials",
                 at: CGPoint(x: 0, y: cardY), width: cardW, height: cardH)
    }

    private func drawCard(label: String, sub: String, action: String, name: String,
                          at center: CGPoint, width: CGFloat, height: CGFloat) {
        let font = "PressStart2P-Regular"

        let tex = makeCardTexture(size: CGSize(width: width, height: height))
        let card = SKSpriteNode(texture: tex, size: CGSize(width: width, height: height))
        card.position = center
        card.zPosition = 20
        card.name = name
        addChild(card)

        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y + height / 2 - 9), radius: 2.5, z: 21)
        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y - height / 2 + 9), radius: 2.5, z: 21)

        let lbl = SKLabelNode(fontNamed: font)
        lbl.text = label
        lbl.fontSize = min(8, width / 32)
        lbl.fontColor = SKColor(red: 1.0, green: 0.89, blue: 0.69, alpha: 1)
        lbl.horizontalAlignmentMode = .left
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: center.x - width / 2 + 22, y: center.y + height * 0.18)
        lbl.zPosition = 21
        lbl.name = name
        addChild(lbl)

        let subLbl = SKLabelNode(fontNamed: font)
        subLbl.text = sub
        subLbl.fontSize = min(5, width / 52)
        subLbl.fontColor = SKColor(white: 0.45, alpha: 1)
        subLbl.horizontalAlignmentMode = .left
        subLbl.verticalAlignmentMode = .center
        subLbl.position = CGPoint(x: center.x - width / 2 + 22, y: center.y - height * 0.18)
        subLbl.zPosition = 21
        subLbl.name = name
        addChild(subLbl)

        let actionLbl = SKLabelNode(fontNamed: font)
        actionLbl.text = action
        actionLbl.fontSize = min(9, width / 28)
        actionLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        actionLbl.horizontalAlignmentMode = .right
        actionLbl.verticalAlignmentMode = .center
        actionLbl.position = CGPoint(x: center.x + width / 2 - 22, y: center.y)
        actionLbl.zPosition = 21
        actionLbl.name = name
        addChild(actionLbl)
        confirmLabel = actionLbl
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
        let hit = nodes(at: loc).first(where: { $0.name != nil })
        switch hit?.name {
        case "back":
            goBack()
        case "resetTutorials":
            TutorialManager.shared.resetAll()
            flashConfirm()
        default:
            break
        }
    }

    private func goBack() {
        let t = SKTransition.push(with: .down, duration: 0.35)
        t.pausesOutgoingScene = false
        let menu = MainMenuScene(size: size)
        menu.scaleMode = .resizeFill
        view?.presentScene(menu, transition: t)
    }

    private func flashConfirm() {
        guard let lbl = confirmLabel else { return }
        let green = SKColor(red: 0.40, green: 0.85, blue: 0.40, alpha: 1)
        let gold  = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        lbl.run(.sequence([
            .run { lbl.text = "DONE!"; lbl.fontColor = green },
            .wait(forDuration: 1.0),
            .run { lbl.text = "RESET"; lbl.fontColor = gold },
        ]))
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

    private func makePlaqueTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            c.addPath(path.cgPath); c.clip()

            let space = CGColorSpaceCreateDeviceRGB()
            let woodColors = [
                UIColor(red: 0.48, green: 0.31, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.36, green: 0.20, blue: 0.09, alpha: 1).cgColor,
                UIColor(red: 0.24, green: 0.12, blue: 0.03, alpha: 1).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: space, colors: woodColors, locations: [0, 0.6, 1.0])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            c.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
            var x: CGFloat = 12
            while x < size.width {
                c.fill(CGRect(x: x, y: 0, width: 2, height: size.height))
                x += 14
            }

            c.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))

            c.setFillColor(UIColor(white: 0, alpha: 0.40).cgColor)
            c.fill(CGRect(x: 0, y: size.height - 5, width: size.width, height: 5))

            c.setStrokeColor(UIColor(red: 0.16, green: 0.09, blue: 0.03, alpha: 1).cgColor)
            c.setLineWidth(3)
            let border = UIBezierPath(roundedRect: CGRect(x: 1.5, y: 1.5, width: size.width - 3, height: size.height - 3), cornerRadius: 4)
            c.addPath(border.cgPath); c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func makeCardTexture(size: CGSize) -> SKTexture {
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

            c.setFillColor(UIColor(red: 0.63, green: 0.31, blue: 0.06, alpha: 0.25).cgColor)
            c.fillEllipse(in: CGRect(x: size.width * 0.62, y: size.height * 0.20, width: size.width * 0.42, height: size.height * 0.80))

            c.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
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
}
