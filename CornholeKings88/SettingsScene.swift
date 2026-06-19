import SpriteKit
import UIKit

final class SettingsScene: SKScene {

    private var W: CGFloat = 0, H: CGFloat = 0
    private var ribbonBottomY: CGFloat = 0   // scene-Y of bottom edge of the top ribbon
    private var confirmLabel: SKLabelNode?

    // Throw-force slider state
    private var sliderTrack: SKSpriteNode?
    private var sliderFill: SKSpriteNode?
    private var sliderThumb: SKShapeNode?
    private var sliderValueLabel: SKLabelNode?
    private var sliderMinX: CGFloat = 0
    private var sliderMaxX: CGFloat = 0
    private var sliderTrackY: CGFloat = 0
    private var isDraggingSlider = false

    // Style constants (Bit-Wood Brawler)
    private let dsPrimary = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1) // #1a0a04
    private let dsGold    = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060
    private let dsGoldDim = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
    private let dsCream   = SKColor(red: 1.0, green: 0.89, blue: 0.69, alpha: 1)
    private let dsMuted   = SKColor(white: 0.50, alpha: 1)

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width
        H = size.height

        backgroundColor = SKColor(red: 0.02, green: 0.04, blue: 0.02, alpha: 1)

        setupTopStrip()
        setupContent()
        setupFooter()
        setupEmbers()
        addCrtOverlay()
    }

    // MARK: - Top ribbon (DS standard: #1a0a04 + 2px gold border, safe-area aware)
    private func setupTopStrip() {
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
        back.size = CGSize(width: 22, height: 22)
        back.texture?.filteringMode = .nearest
        back.position  = CGPoint(x: W / 2 - 22, y: contentY)
        back.zPosition = 12
        back.name      = "back"
        addChild(back)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "SETTINGS"
        title.fontSize = 10
        title.fontColor = dsGold
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position  = CGPoint(x: 0, y: contentY)
        title.zPosition = 12
        addChild(title)
    }

    // MARK: - Sections + cards
    private func setupContent() {
        let cardW = min(W * 0.86, 320)
        // Start a comfortable gap below the ribbon.
        var y = ribbonBottomY - 22

        // GAMEPLAY section
        y = addSectionHeader("GAMEPLAY", atTopY: y, width: cardW)
        y = addThrowForceCard(topY: y, width: cardW)
        y = addCard(label: "BASEBALL AI",
                    sub: "tune tom & jen difficulty",
                    action: "TUNE",
                    name: "tuneBaseball",
                    topY: y, width: cardW, height: 60)

        // TUTORIALS section
        y -= 14
        y = addSectionHeader("TUTORIALS", atTopY: y, width: cardW)
        y = addCard(label: "REPLAY TUTORIALS",
                    sub: "show intro again next play",
                    action: "RESET",
                    name: "resetTutorials",
                    topY: y, width: cardW, height: 60)
    }

    /// Draws a left-aligned, dim-gold section header above the cards.
    /// Returns the Y below it (top edge for the next card).
    @discardableResult
    private func addSectionHeader(_ text: String, atTopY topY: CGFloat, width: CGFloat) -> CGFloat {
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = text
        lbl.fontSize = 8
        lbl.fontColor = dsGoldDim
        lbl.horizontalAlignmentMode = .left
        lbl.verticalAlignmentMode   = .top
        lbl.position  = CGPoint(x: -width / 2, y: topY)
        lbl.zPosition = 20
        addChild(lbl)

        // Thin gold underline running the card width.
        let underY = topY - 12
        let line = SKSpriteNode(color: dsGoldDim.withAlphaComponent(0.55),
                                size: CGSize(width: width, height: 1))
        line.position  = CGPoint(x: 0, y: underY)
        line.zPosition = 20
        addChild(line)

        return underY - 12  // gap before first card
    }

    /// Generic action card — label + sub-text + right-side action word.
    /// `topY` is the top edge; returns the next available `topY` below the card.
    @discardableResult
    private func addCard(label: String, sub: String, action: String, name: String,
                         topY: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
        let center = CGPoint(x: 0, y: topY - height / 2)

        let tex = makeCardTexture(size: CGSize(width: width, height: height))
        let card = SKSpriteNode(texture: tex, size: CGSize(width: width, height: height))
        card.position  = center
        card.zPosition = 20
        card.name      = name
        addChild(card)

        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y + height / 2 - 9), radius: 2.5, z: 21)
        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y - height / 2 + 9), radius: 2.5, z: 21)

        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = label
        lbl.fontSize = min(8, width / 32)
        lbl.fontColor = dsCream
        lbl.horizontalAlignmentMode = .left
        lbl.verticalAlignmentMode   = .center
        lbl.position  = CGPoint(x: center.x - width / 2 + 22, y: center.y + height * 0.18)
        lbl.zPosition = 21
        lbl.name = name
        addChild(lbl)

        let subLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        subLbl.text = sub
        subLbl.fontSize = min(5, width / 52)
        subLbl.fontColor = dsMuted
        subLbl.horizontalAlignmentMode = .left
        subLbl.verticalAlignmentMode   = .center
        subLbl.position  = CGPoint(x: center.x - width / 2 + 22, y: center.y - height * 0.18)
        subLbl.zPosition = 21
        subLbl.name = name
        addChild(subLbl)

        let actionLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        actionLbl.text = action
        actionLbl.fontSize = min(9, width / 28)
        actionLbl.fontColor = dsGold
        actionLbl.horizontalAlignmentMode = .right
        actionLbl.verticalAlignmentMode   = .center
        actionLbl.position  = CGPoint(x: center.x + width / 2 - 22, y: center.y)
        actionLbl.zPosition = 21
        actionLbl.name = name
        addChild(actionLbl)

        if name == "resetTutorials" { confirmLabel = actionLbl }

        return center.y - height / 2 - 14
    }

    /// Throw-force slider card — wider/taller than the action cards.
    /// `topY` is the top edge; returns the next available `topY` below the card.
    @discardableResult
    private func addThrowForceCard(topY: CGFloat, width: CGFloat) -> CGFloat {
        let height: CGFloat = 96
        let center = CGPoint(x: 0, y: topY - height / 2)

        let tex = makeCardTexture(size: CGSize(width: width, height: height))
        let card = SKSpriteNode(texture: tex, size: CGSize(width: width, height: height))
        card.position  = center
        card.zPosition = 20
        card.name      = "throwForceCard"
        addChild(card)

        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y + height / 2 - 9), radius: 2.5, z: 21)
        addRivet(at: CGPoint(x: center.x - width / 2 + 9, y: center.y - height / 2 + 9), radius: 2.5, z: 21)
        addRivet(at: CGPoint(x: center.x + width / 2 - 9, y: center.y + height / 2 - 9), radius: 2.5, z: 21)
        addRivet(at: CGPoint(x: center.x + width / 2 - 9, y: center.y - height / 2 + 9), radius: 2.5, z: 21)

        // Header row: title + live value tag (EASY/NORMAL/HARD)
        let titleY = center.y + height * 0.30
        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "THROW FORCE"
        title.fontSize = min(8, width / 32)
        title.fontColor = dsCream
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode   = .center
        title.position  = CGPoint(x: center.x - width / 2 + 22, y: titleY)
        title.zPosition = 21
        addChild(title)

        let value = SKLabelNode(fontNamed: "PressStart2P-Regular")
        value.fontSize = min(9, width / 28)
        value.fontColor = dsGold
        value.horizontalAlignmentMode = .right
        value.verticalAlignmentMode   = .center
        value.position  = CGPoint(x: center.x + width / 2 - 22, y: titleY)
        value.zPosition = 21
        value.text = ThrowSensitivityManager.shared.label
        addChild(value)
        sliderValueLabel = value

        // Sub-text
        let sub = SKLabelNode(fontNamed: "PressStart2P-Regular")
        sub.text = "swipe sensitivity for throws"
        sub.fontSize = min(5, width / 52)
        sub.fontColor = dsMuted
        sub.horizontalAlignmentMode = .left
        sub.verticalAlignmentMode   = .center
        sub.position  = CGPoint(x: center.x - width / 2 + 22, y: titleY - 14)
        sub.zPosition = 21
        addChild(sub)

        // Track (dark recessed channel)
        let trackInset: CGFloat = 28
        let trackW = width - trackInset * 2
        sliderMinX = center.x - trackW / 2
        sliderMaxX = center.x + trackW / 2
        sliderTrackY = center.y - height * 0.18

        let track = SKSpriteNode(texture: makeTrackTexture(size: CGSize(width: trackW, height: 8)),
                                 size: CGSize(width: trackW, height: 8))
        track.position  = CGPoint(x: center.x, y: sliderTrackY)
        track.zPosition = 21
        track.name      = "throwSliderTrack"
        addChild(track)
        sliderTrack = track

        // Gold fill from left up to the thumb.
        let fill = SKSpriteNode(color: dsGoldDim, size: CGSize(width: 1, height: 4))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position    = CGPoint(x: sliderMinX, y: sliderTrackY)
        fill.zPosition   = 22
        addChild(fill)
        sliderFill = fill

        // Tick marks for HARD / NORMAL / EASY positions.
        for frac in [0.0, 0.5, 1.0] {
            let tick = SKSpriteNode(color: dsGoldDim.withAlphaComponent(0.8),
                                    size: CGSize(width: 2, height: 12))
            tick.position  = CGPoint(x: sliderMinX + CGFloat(frac) * trackW, y: sliderTrackY)
            tick.zPosition = 22
            addChild(tick)
        }

        // End labels
        let leftLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        leftLbl.text = "HARD"
        leftLbl.fontSize = 5
        leftLbl.fontColor = dsMuted
        leftLbl.horizontalAlignmentMode = .center
        leftLbl.verticalAlignmentMode   = .top
        leftLbl.position  = CGPoint(x: sliderMinX, y: sliderTrackY - 12)
        leftLbl.zPosition = 22
        addChild(leftLbl)

        let midLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        midLbl.text = "NORMAL"
        midLbl.fontSize = 5
        midLbl.fontColor = dsMuted
        midLbl.horizontalAlignmentMode = .center
        midLbl.verticalAlignmentMode   = .top
        midLbl.position  = CGPoint(x: center.x, y: sliderTrackY - 12)
        midLbl.zPosition = 22
        addChild(midLbl)

        let rightLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        rightLbl.text = "EASY"
        rightLbl.fontSize = 5
        rightLbl.fontColor = dsMuted
        rightLbl.horizontalAlignmentMode = .center
        rightLbl.verticalAlignmentMode   = .top
        rightLbl.position  = CGPoint(x: sliderMaxX, y: sliderTrackY - 12)
        rightLbl.zPosition = 22
        addChild(rightLbl)

        // Thumb (gold rounded square)
        let thumb = SKShapeNode(rectOf: CGSize(width: 16, height: 18), cornerRadius: 3)
        thumb.fillColor   = dsGold
        thumb.strokeColor = SKColor(white: 0.12, alpha: 1)
        thumb.lineWidth   = 1.5
        thumb.zPosition   = 24
        thumb.name        = "throwSliderThumb"
        addChild(thumb)
        sliderThumb = thumb

        positionSlider(toNormalized: ThrowSensitivityManager.shared.normalized)

        return center.y - height / 2 - 14
    }

    // MARK: - Footer
    private func setupFooter() {
        let y = -H / 2 + 18

        let copy = SKLabelNode(fontNamed: "PressStart2P-Regular")
        copy.text = "\u{00A9} 2026 CK88"
        copy.fontSize = min(5, W / 60)
        copy.fontColor = SKColor(white: 0.40, alpha: 1)
        copy.horizontalAlignmentMode = .left
        copy.verticalAlignmentMode = .center
        copy.position  = CGPoint(x: -W / 2 + 12, y: y)
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

        // Slider drag — anywhere along the track (including thumb) starts a drag.
        if isOnSliderTrack(loc) {
            isDraggingSlider = true
            updateSlider(toX: loc.x)
            return
        }

        let hit = nodes(at: loc).first(where: { $0.name != nil })
        switch hit?.name {
        case "back":
            goBack()
        case "resetTutorials":
            TutorialManager.shared.resetAll()
            flashConfirm()
        case "tuneBaseball":
            openBaseballTuning()
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDraggingSlider, let touch = touches.first else { return }
        updateSlider(toX: touch.location(in: self).x)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDraggingSlider = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isDraggingSlider = false
    }

    private func isOnSliderTrack(_ loc: CGPoint) -> Bool {
        guard sliderTrack != nil else { return false }
        // Generous vertical hit area so the player can grab the thumb easily.
        let dy = abs(loc.y - sliderTrackY)
        let withinX = loc.x >= sliderMinX - 16 && loc.x <= sliderMaxX + 16
        return dy < 22 && withinX
    }

    private func updateSlider(toX rawX: CGFloat) {
        let clamped = max(sliderMinX, min(sliderMaxX, rawX))
        let norm = (clamped - sliderMinX) / (sliderMaxX - sliderMinX)
        ThrowSensitivityManager.shared.normalized = norm
        positionSlider(toNormalized: norm)
    }

    private func positionSlider(toNormalized norm: CGFloat) {
        let x = sliderMinX + norm * (sliderMaxX - sliderMinX)
        sliderThumb?.position = CGPoint(x: x, y: sliderTrackY)
        let fillW = max(1, x - sliderMinX)
        sliderFill?.size = CGSize(width: fillW, height: 4)
        sliderValueLabel?.text = ThrowSensitivityManager.shared.label
    }

    private func openBaseballTuning() {
        let t = SKTransition.push(with: .left, duration: 0.3)
        let scene = BaseballTuningScene(size: size)
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: t)
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
        lbl.run(.sequence([
            .run { lbl.text = "DONE!"; lbl.fontColor = green },
            .wait(forDuration: 1.0),
            .run { [weak self] in
                lbl.text = "RESET"
                lbl.fontColor = self?.dsGold ?? .yellow
            },
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

    private func makeTrackTexture(size: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3)
            c.addPath(path.cgPath); c.clip()
            c.setFillColor(UIColor(white: 0.06, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))
            // Subtle top inner-shadow
            c.setFillColor(UIColor(white: 0, alpha: 0.55).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))
            c.setStrokeColor(UIColor(white: 0.16, alpha: 1).cgColor)
            c.setLineWidth(1)
            c.stroke(CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }
}
