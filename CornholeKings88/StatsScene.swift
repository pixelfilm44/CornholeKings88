import SpriteKit
import UIKit

final class StatsScene: SKScene {

    private var W: CGFloat = 0, H: CGFloat = 0
    private var resetLabel: SKLabelNode?
    private var ribbonBottomY: CGFloat = 0   // scene-Y of bottom edge of the top ribbon

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width
        H = size.height

        backgroundColor = Parchment.bg

        setupTopStrip()
        setupPlaque()
        setupStats()
        setupFooter()
        // embers removed for parchment theme
        addCrtOverlay()
    }

    // MARK: - Top ribbon (parchment paper + ink edge border, safe-area aware)
    private func setupTopStrip() {
        let dsPrimary = Parchment.paper
        let dsGold    = Parchment.edge

        let topInset  = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let topBarY   = H / 2 - totalTopH / 2
        ribbonBottomY = H / 2 - totalTopH

        // Background bar (extends through notch)
        let bar = SKSpriteNode(color: dsPrimary, size: CGSize(width: W, height: totalTopH))
        bar.position  = CGPoint(x: 0, y: topBarY)
        bar.zPosition = 10
        addChild(bar)

        // 2px gold bottom border
        let border = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        border.position  = CGPoint(x: 0, y: ribbonBottomY + 1)
        border.zPosition = 11
        addChild(border)

        // Zone C (right): close / back icon at 22×22
        let contentY = H / 2 - topInset - topH / 2
        let back = SKSpriteNode(imageNamed: "closeIcon")
        back.size             = CGSize(width: 22, height: 22)
        back.texture?.filteringMode = .nearest
        back.position  = CGPoint(x: W / 2 - 22, y: contentY)
        back.zPosition = 12
        back.name      = "back"
        addChild(back)

        // Zone B (center): scene title
        let font = "PressStart2P-Regular"
        let title = SKLabelNode(fontNamed: font)
        title.text = "STATS"
        title.fontSize = 8
        title.fontColor = Parchment.deep
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
        lbl.text = "MY STATS"
        lbl.fontSize = titleFS
        lbl.fontColor = Parchment.deep
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: 0, y: plaqueY)
        lbl.zPosition = 11
        addChild(lbl)
    }

    // MARK: - Stat cards
    private func setupStats() {
        let stats = CornholeStatsManager.shared
        let plaqueH: CGFloat = 52
        let topContentY = ribbonBottomY - 16 - plaqueH - 20

        let cardW = min(W * 0.84, 300)
        let cardH: CGFloat = 60
        let gap: CGFloat = 14

        let medals = MedalManager.shared
        let entries: [(label: String, value: String, sub: String)] = [
            ("RECORD",    "\(stats.wins) - \(stats.losses)",  "wins - losses"),
            ("CORNHOLES", "\(stats.cornholes)",               "bags in the hole"),
            ("MEDALS",    "\(medals.totalMedalScore) / \(medals.maxMedalScore)", "mastery earned"),
            ("RANK",      stats.currentRank,                  "current rank"),
        ]

        var curY = topContentY
        for entry in entries {
            let cardY = curY - cardH / 2
            drawCard(label: entry.label, value: entry.value, sub: entry.sub,
                     at: CGPoint(x: 0, y: cardY), width: cardW, height: cardH)
            curY -= cardH + gap
        }
    }

    private func drawCard(label: String, value: String, sub: String,
                          at center: CGPoint, width: CGFloat, height: CGFloat) {
        let font = "PressStart2P-Regular"

        let tex = makeCardTexture(size: CGSize(width: width, height: height))
        let card = SKSpriteNode(texture: tex, size: CGSize(width: width, height: height))
        card.position = center
        card.zPosition = 20
        addChild(card)

        // Rivets
        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y + height / 2 - 9), radius: 2.5, z: 21)
        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y - height / 2 + 9), radius: 2.5, z: 21)

        // Stat label (left side)
        let lbl = SKLabelNode(fontNamed: font)
        lbl.text = label
        lbl.fontSize = min(7, width / 36)
        lbl.fontColor = Parchment.muted
        lbl.horizontalAlignmentMode = .left
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: center.x - width / 2 + 22, y: center.y + height * 0.18)
        lbl.zPosition = 21
        addChild(lbl)

        let subLbl = SKLabelNode(fontNamed: font)
        subLbl.text = sub
        subLbl.fontSize = min(5, width / 52)
        subLbl.fontColor = Parchment.muted
        subLbl.horizontalAlignmentMode = .left
        subLbl.verticalAlignmentMode = .center
        subLbl.position = CGPoint(x: center.x - width / 2 + 22, y: center.y - height * 0.18)
        subLbl.zPosition = 21
        addChild(subLbl)

        // Value (right side)
        let valLbl = SKLabelNode(fontNamed: font)
        valLbl.text = value
        valLbl.fontSize = min(14, width / 18)
        valLbl.fontColor = Parchment.deep
        valLbl.horizontalAlignmentMode = .right
        valLbl.verticalAlignmentMode = .center
        valLbl.position = CGPoint(x: center.x + width / 2 - 22, y: center.y)
        valLbl.zPosition = 21
        addChild(valLbl)
    }

    // MARK: - Footer
    private func setupFooter() {
        let font = "PressStart2P-Regular"
        let y = -H / 2 + 18

        let copy = SKLabelNode(fontNamed: font)
        copy.text = "\u{00A9} 2026 CK88"
        copy.fontSize = min(5, W / 60)
        copy.fontColor = Parchment.muted
        copy.horizontalAlignmentMode = .left
        copy.verticalAlignmentMode = .center
        copy.position = CGPoint(x: -W / 2 + 12, y: y)
        copy.zPosition = 10
        addChild(copy)

        let reset = SKLabelNode(fontNamed: font)
        reset.text = "RESET STATS"
        reset.fontSize = min(5, W / 60)
        reset.fontColor = Parchment.muted
        reset.horizontalAlignmentMode = .right
        reset.verticalAlignmentMode = .center
        reset.position = CGPoint(x: W / 2 - 12, y: y)
        reset.zPosition = 10
        reset.name = "resetStats"
        addChild(reset)
        resetLabel = reset
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
            c.setFillColor(UIColor(white: 0, alpha: 0.10).cgColor)
            var y: CGFloat = 0
            while y < H { c.fill(CGRect(x: 0, y: y, width: W, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let vColors = [UIColor(white: 0, alpha: 0).cgColor,
                           UIColor(white: 0, alpha: 0.10).cgColor,
                           UIColor(white: 0, alpha: 0.35).cgColor] as CFArray
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
        // Use nodes(at:) so the CRT overlay (highest zPosition) doesn't shadow named nodes below it.
        let hit = nodes(at: loc).first(where: { $0.name != nil })
        switch hit?.name {
        case "back":
            goBack()
        case "resetStats":
            CornholeStatsManager.shared.reset()
            flashReset()
            refreshStats()
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

    private func flashReset() {
        guard let lbl = resetLabel else { return }
        let gold = Parchment.amber
        let dim  = Parchment.muted
        lbl.run(.sequence([
            .run { lbl.fontColor = gold },
            .wait(forDuration: 0.6),
            .run { lbl.fontColor = dim },
        ]))
    }

    private func refreshStats() {
        // Rebuild stat cards in place after reset
        let stats = CornholeStatsManager.shared
        let stripH: CGFloat = 20
        let plaqueH: CGFloat = 52
        let topContentY = H / 2 - stripH - 16 - plaqueH - 20
        let cardW = min(W * 0.84, 300)
        let cardH: CGFloat = 60
        let gap: CGFloat = 14

        let newValues = [
            "\(stats.wins) - \(stats.losses)",
            "\(stats.cornholes)",
            stats.currentRank,
        ]

        // Value labels are at right edge of each card; update them by zPosition+name
        // Simplest approach: re-present this scene
        let fresh = StatsScene(size: size)
        fresh.scaleMode = scaleMode
        view?.presentScene(fresh)
        _ = (topContentY, cardW, cardH, gap, newValues) // silence unused warning
    }

    // MARK: - Texture Builders

    private func addRivet(at pos: CGPoint, radius: CGFloat, z: CGFloat) {
        let r = SKShapeNode(circleOfRadius: radius)
        r.fillColor = Parchment.muted
        r.strokeColor = Parchment.edge
        r.lineWidth = 0.5
        r.position = pos
        r.zPosition = z
        addChild(r)
    }

    private func makeStrip(width: CGFloat, height: CGFloat) -> SKSpriteNode {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(Parchment.paper.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: width, height: height))
            c.setFillColor(Parchment.edge.cgColor)
            c.fill(CGRect(x: 0, y: height - 2, width: width, height: 2))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest
        return SKSpriteNode(texture: t, size: CGSize(width: width, height: height))
    }

    private func makePlaqueTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            c.addPath(path.cgPath); c.clip()

            // Parchment panel fill
            c.setFillColor(Parchment.paper.cgColor)
            c.fill(CGRect(origin: .zero, size: size))

            // Top highlight
            c.setFillColor(UIColor(white: 1, alpha: 0.20).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))

            // Bottom shadow
            c.setFillColor(Parchment.edge.withAlphaComponent(0.18).cgColor)
            c.fill(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3))

            // Ink edge border
            c.setStrokeColor(Parchment.edge.cgColor)
            c.setLineWidth(2)
            let border = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2), cornerRadius: 4)
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

            // Parchment surface fill
            c.setFillColor(Parchment.surface.cgColor)
            c.fill(CGRect(origin: .zero, size: size))

            // Top highlight
            c.setFillColor(UIColor(white: 1, alpha: 0.20).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))

            // Bottom shadow
            c.setFillColor(Parchment.edge.withAlphaComponent(0.18).cgColor)
            c.fill(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3))

            // Ink edge border
            c.setStrokeColor(Parchment.edge.cgColor)
            c.setLineWidth(2)
            let border = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2), cornerRadius: 5)
            c.addPath(border.cgPath); c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }
}
