import SpriteKit
import UIKit

final class MiniGamePickerScene: SKScene {

    var onBikeRace: (() -> Void)?

    private var W: CGFloat = 0, H: CGFloat = 0
    private var cardNodes: [String: SKNode] = [:]
    private var tapEnabled = false
    private var nodesCount = 45
    private weak var nodesLabel: SKLabelNode?

    private struct MenuItem {
        let label: String
        let subLabel: String
        let name: String
        let isLocked: Bool
    }

    private let items: [MenuItem] = [
        MenuItem(label: "STORY MODE",     subLabel: "adventure",  name: "story",      isLocked: false),
        MenuItem(label: "BEANBAG BIKE",   subLabel: "racing",     name: "bike",       isLocked: false),
        MenuItem(label: "CORNHOLE",       subLabel: "bag toss",   name: "cornhole",   isLocked: false),
        MenuItem(label: "BASEBALL",       subLabel: "batting",    name: "baseball",   isLocked: false),
        MenuItem(label: "BEEHIVE BATTLE", subLabel: "defense",    name: "beehive",    isLocked: false),
        MenuItem(label: "BEACH BALL",     subLabel: "pool blitz",    name: "beachball",  isLocked: false),
        MenuItem(label: "PIRANHA BRIDGE", subLabel: "bridge build",  name: "piranha",    isLocked: false),
        MenuItem(label: "EXPLORE",        subLabel: "open world",    name: "explore",    isLocked: true),
    ]

    // Palette
    private let engraveHi  = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060
    private let engrave    = SKColor(red: 0.784, green: 0.573, blue: 0.165, alpha: 1) // #c8922a
    private let engraveDim = SKColor(red: 0.416, green: 0.290, blue: 0.078, alpha: 1) // #6a4a14
    private let txtGrey    = SKColor(red: 0.722, green: 0.690, blue: 0.627, alpha: 1) // #b8b0a0
    private let lockedTxt  = SKColor(red: 0.478, green: 0.416, blue: 0.282, alpha: 1) // #7a6b48

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        backgroundColor = SKColor(red: 0.020, green: 0.012, blue: 0.008, alpha: 1) // #050302

        setupHeader()
        setupEyebrow()
        setupCards()
        setupEmbers()
        setupFooter()
        addCrtOverlay()

        run(.sequence([.wait(forDuration: 0.5), .run { self.tapEnabled = true }]))
    }

    // MARK: - Header (height 52)
    private func setupHeader() {
        let font = "PressStart2P-Regular"
        let hH: CGFloat = 52
        let hCenterY = H / 2 - hH / 2

        // Dark iron-wood panel with gold bottom rule
        let panelImg = renderImage(CGSize(width: W, height: hH)) { c, sz in
            c.setFillColor(UIColor(red: 0.063, green: 0.027, blue: 0.012, alpha: 0.97).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: sz.width, height: sz.height))
            // Gold rule at bottom (in image coords y=0 is bottom in SpriteKit, but image coords differ —
            // fill the last row which will appear at the scene-space bottom of the sprite)
            c.setFillColor(UIColor(red: 0.784, green: 0.573, blue: 0.165, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: sz.height - 1, width: sz.width, height: 1))
            // Subtle glow below rule
            c.setFillColor(UIColor(red: 0.784, green: 0.573, blue: 0.165, alpha: 0.18).cgColor)
            c.fill(CGRect(x: 0, y: sz.height - 3, width: sz.width, height: 2))
        }
        let panel = SKSpriteNode(texture: SKTexture(image: panelImg), size: CGSize(width: W, height: hH))
        panel.position = CGPoint(x: 0, y: hCenterY); panel.zPosition = 10
        addChild(panel)

        let title = SKLabelNode(fontNamed: font)
        title.text = "MINI  GAMES"
        title.fontSize = min(14, W / 26)
        title.fontColor = engraveHi
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position  = CGPoint(x: 0, y: hCenterY); title.zPosition = 11
        addChild(title)

        let closeSize: CGFloat = min(30, W / 13)
        let back = SKSpriteNode(imageNamed: "closeIcon")
        back.size = CGSize(width: closeSize, height: closeSize)
        back.texture?.filteringMode = .nearest
        back.position  = CGPoint(x: -W / 2 + closeSize / 2 + 10, y: hCenterY)
        back.zPosition = 11; back.name = "back"
        addChild(back)
    }

    // MARK: - Eyebrow
    private func setupEyebrow() {
        let font = "PressStart2P-Regular"
        let headerBottomY = H / 2 - 52
        let ey = headerBottomY - 22

        let lbl = SKLabelNode(fontNamed: font)
        lbl.text = "CHOOSE YOUR EVENT"
        lbl.fontSize = min(7, W / 50)
        lbl.fontColor = engraveDim
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode   = .center
        lbl.position = CGPoint(x: 0, y: ey); lbl.zPosition = 10
        addChild(lbl)

        // Flanking gradient lines
        let textHalfW: CGFloat = min(90, W * 0.22)
        for sign: CGFloat in [-1, 1] {
            let x0 = sign * (textHalfW + 8)
            let x1 = sign * (textHalfW + 52)
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x0, y: ey))
            path.addLine(to: CGPoint(x: x1, y: ey))
            line.path = path
            line.strokeColor = SKColor(red: 0.416, green: 0.290, blue: 0.078, alpha: 0.6)
            line.lineWidth = 1; line.zPosition = 10
            addChild(line)
        }
    }

    // MARK: - Cards
    private func setupCards() {
        let font = "PressStart2P-Regular"
        let headerH: CGFloat  = 52
        let footerH: CGFloat  = 28
        let eyebrowH: CGFloat = 40
        let sidePad: CGFloat  = 18
        let gap: CGFloat      = 14
        let btnW = W - sidePad * 2
        let usableH = H - headerH - footerH - eyebrowH - 12
        let btnH = min(76, max(54, (usableH - CGFloat(items.count - 1) * gap) / CGFloat(items.count)))

        let topY   = H / 2 - headerH - eyebrowH - 4
        var curY   = topY - btnH / 2

        for (i, item) in items.enumerated() {
            let cardY = curY
            let card  = SKNode()
            card.position  = CGPoint(x: 0, y: cardY)
            card.zPosition = CGFloat(20 + i)
            card.name      = item.name
            addChild(card)
            cardNodes[item.name] = card

            // Drop shadow strip
            let shadow = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.85),
                                      size: CGSize(width: btnW - 4, height: 5))
            shadow.position = CGPoint(x: 1, y: -btnH / 2 - 3)
            card.addChild(shadow)

            // Card background (iron plate)
            let bgTex = makeCardTexture(CGSize(width: btnW, height: btnH), locked: item.isLocked)
            let bg    = SKSpriteNode(texture: bgTex, size: CGSize(width: btnW, height: btnH))
            bg.position = .zero; bg.name = item.name
            card.addChild(bg)

            // Rivets — top-left and bottom-left
            for dySign: CGFloat in [1, -1] {
                let rv = makeRivetNode()
                rv.position = CGPoint(x: -btnW / 2 + 9, y: dySign * (btnH / 2 - 9))
                card.addChild(rv)
            }

            // Icon
            let iconSz: CGFloat = 28
            let iconTex = makeIconTexture(item.name, size: iconSz, locked: item.isLocked)
            let iconSp  = SKSpriteNode(texture: iconTex, size: CGSize(width: iconSz, height: iconSz))
            iconSp.position = CGPoint(x: -btnW / 2 + 36, y: 1)
            iconSp.name = item.name
            card.addChild(iconSp)

            // Title
            let titleLbl = SKLabelNode(fontNamed: font)
            titleLbl.text = item.label
            titleLbl.fontSize = min(11, btnW / 26)
            titleLbl.fontColor = item.isLocked ? lockedTxt : engraveHi
            titleLbl.horizontalAlignmentMode = .left
            titleLbl.verticalAlignmentMode   = .center
            titleLbl.position  = CGPoint(x: -btnW / 2 + 68, y: 7)
            titleLbl.zPosition = 1; titleLbl.name = item.name
            card.addChild(titleLbl)

            // Sub
            let subLbl = SKLabelNode(fontNamed: font)
            subLbl.text = item.subLabel
            subLbl.fontSize = min(6, btnW / 50)
            subLbl.fontColor = txtGrey.withAlphaComponent(item.isLocked ? 0.5 : 1.0)
            subLbl.horizontalAlignmentMode = .left
            subLbl.verticalAlignmentMode   = .center
            subLbl.position  = CGPoint(x: -btnW / 2 + 68, y: -9)
            subLbl.zPosition = 1; subLbl.name = item.name
            card.addChild(subLbl)

            if item.isLocked {
                // Lock emoji
                let lockLbl = SKLabelNode(fontNamed: "AppleColorEmoji")
                lockLbl.text = "🔒"
                lockLbl.fontSize  = 14
                lockLbl.horizontalAlignmentMode = .right
                lockLbl.verticalAlignmentMode   = .center
                lockLbl.position  = CGPoint(x: btnW / 2 - 14, y: 0)
                lockLbl.zPosition = 1; lockLbl.name = item.name
                card.addChild(lockLbl)
            } else {
                // Arrow with bob animation
                let arrow = SKLabelNode(fontNamed: font)
                arrow.text = "\u{25B6}"
                arrow.fontSize = min(12, btnW / 28)
                arrow.fontColor = engraveHi
                arrow.horizontalAlignmentMode = .right
                arrow.verticalAlignmentMode   = .center
                arrow.position  = CGPoint(x: btnW / 2 - 16, y: 0)
                arrow.zPosition = 1; arrow.name = item.name
                arrow.run(.repeatForever(.sequence([
                    .moveBy(x: 3, y: 0, duration: 0.7),
                    .moveBy(x: -3, y: 0, duration: 0.7),
                ])))
                card.addChild(arrow)
            }

            // Staggered entry: fade + slide up
            card.alpha = 0
            card.position.y = cardY - 8
            let delay = Double(i) * 0.07 + 0.05
            card.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .fadeIn(withDuration: 0.35),
                    .moveBy(x: 0, y: 8, duration: 0.35),
                ]),
            ]))

            curY -= btnH + gap
        }
    }

    // MARK: - Embers
    private func setupEmbers() {
        let positions: [(CGFloat, CGFloat, Double)] = [
            (0.10, 0.22, 0.0), (0.82, 0.28, 0.8),
            (0.06, 0.55, 1.4), (0.90, 0.62, 2.0),
            (0.18, 0.80, 2.6),
        ]
        for (px, py, delay) in positions {
            let e = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            e.fillColor   = SKColor(red: 0.784, green: 0.573, blue: 0.165, alpha: 0.7)
            e.strokeColor = .clear
            e.position    = CGPoint(x: -W / 2 + px * W, y: H / 2 - py * H)
            e.zPosition   = 5; e.alpha = 0
            e.run(.repeatForever(.sequence([
                .wait(forDuration: delay),
                .group([
                    .sequence([.fadeAlpha(to: 0.9, duration: 2.0), .fadeAlpha(to: 0.0, duration: 2.0)]),
                    .sequence([.moveBy(x: 0, y: -8, duration: 2.0), .moveBy(x: 0, y: 8, duration: 2.0)]),
                ]),
            ])))
            addChild(e)
        }
    }

    // MARK: - Footer
    private func setupFooter() {
        let font = "PressStart2P-Regular"
        let footerY = -H / 2 + 14

        let nodesLbl = SKLabelNode(fontNamed: font)
        nodesLbl.text = "nodes:45"
        nodesLbl.fontSize  = 6
        nodesLbl.fontColor = SKColor(white: 0.4, alpha: 0.45)
        nodesLbl.horizontalAlignmentMode = .right
        nodesLbl.verticalAlignmentMode   = .center
        nodesLbl.position  = CGPoint(x: W / 2 - 68, y: footerY)
        nodesLbl.zPosition = 10
        addChild(nodesLbl); nodesLabel = nodesLbl

        let fpsLbl = SKLabelNode(fontNamed: font)
        fpsLbl.text = "60.0 fps"
        fpsLbl.fontSize  = 6
        fpsLbl.fontColor = SKColor(white: 0.4, alpha: 0.45)
        fpsLbl.horizontalAlignmentMode = .right
        fpsLbl.verticalAlignmentMode   = .center
        fpsLbl.position  = CGPoint(x: W / 2 - 18, y: footerY)
        fpsLbl.zPosition = 10
        addChild(fpsLbl)

        // Wandering nodes counter
        nodesLbl.run(.repeatForever(.sequence([
            .wait(forDuration: 0.7),
            .run { [weak self] in
                guard let self else { return }
                self.nodesCount = max(38, min(62, self.nodesCount + (Bool.random() ? -1 : 1)))
                self.nodesLabel?.text = "nodes:\(self.nodesCount)"
            },
        ])))
    }

    // MARK: - Texture builders

    private func renderImage(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            draw(ctx.cgContext, size)
        }
    }

    private func makeRivetNode() -> SKShapeNode {
        let r = SKShapeNode(circleOfRadius: 2.5)
        r.fillColor   = SKColor(white: 0.42, alpha: 1)
        r.strokeColor = SKColor(white: 0.20, alpha: 1)
        r.lineWidth   = 0.5; r.zPosition = 2
        return r
    }

    private func makeCardTexture(_ size: CGSize, locked: Bool) -> SKTexture {
        let img = renderImage(size) { c, sz in
            let roundedPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 7)
            c.addPath(roundedPath.cgPath); c.clip()

            // Iron gradient: #5a5a5a → #383838 → #1f1f1f
            let space = CGColorSpaceCreateDeviceRGB()
            let ironCols = [
                UIColor(red: 0.353, green: 0.353, blue: 0.353, alpha: 1).cgColor,
                UIColor(red: 0.220, green: 0.220, blue: 0.220, alpha: 1).cgColor,
                UIColor(red: 0.122, green: 0.122, blue: 0.122, alpha: 1).cgColor,
            ] as CFArray
            if let grad = CGGradient(colorsSpace: space, colors: ironCols, locations: [0, 0.5, 1.0]) {
                c.drawLinearGradient(grad,
                    start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: sz.height), options: [])
            }

            // Rust blob ellipses (right side)
            let alpha: CGFloat = locked ? 0.28 : 1.0
            c.setFillColor(UIColor(red: 0.416, green: 0.220, blue: 0.071, alpha: 0.55 * alpha).cgColor)
            c.fillEllipse(in: CGRect(x: sz.width * 0.60, y: sz.height * 0.18,
                                     width: sz.width * 0.60, height: sz.height * 0.84))
            c.setFillColor(UIColor(red: 0.549, green: 0.235, blue: 0.039, alpha: 0.30 * alpha).cgColor)
            c.fillEllipse(in: CGRect(x: sz.width * 0.50, y: sz.height * 0.32,
                                     width: sz.width * 0.46, height: sz.height * 0.56))

            // Machined horizontal grooves (every 4 px, 50% opacity)
            c.setFillColor(UIColor(white: 0, alpha: 0.18 * 0.5).cgColor)
            var gy: CGFloat = 3
            while gy < sz.height { c.fill(CGRect(x: 0, y: gy, width: sz.width, height: 1)); gy += 4 }

            // Top specular
            c.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: sz.width, height: 1))

            // Bottom shadow
            c.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            c.fill(CGRect(x: 0, y: sz.height - 3, width: sz.width, height: 3))

            // Border
            c.setStrokeColor(UIColor(white: 0.07, alpha: 1).cgColor)
            c.setLineWidth(2)
            let borderPath = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: sz.width - 2, height: sz.height - 2), cornerRadius: 6)
            c.addPath(borderPath.cgPath); c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // swiftlint:disable function_body_length
    private func makeIconTexture(_ name: String, size: CGFloat, locked: Bool) -> SKTexture {
        let sz = CGSize(width: size, height: size)
        let strokeColor = locked
            ? UIColor(red: 0.478, green: 0.416, blue: 0.282, alpha: 0.7)
            : UIColor(red: 0.784, green: 0.573, blue: 0.165, alpha: 1)
        let fillColor = strokeColor
        let accentColor = locked
            ? UIColor(red: 0.40, green: 0.30, blue: 0.20, alpha: 0.6)
            : UIColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1)
        let darkColor = UIColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1)

        let img = renderImage(sz) { c, s in
            c.setLineWidth(1.5)

            switch name {

            case "story":
                // Scroll / parchment body
                c.setFillColor(fillColor.cgColor)
                c.fill(CGRect(x: 3, y: 2, width: s.width - 6, height: s.height - 4))
                c.setStrokeColor(darkColor.cgColor)
                for lineY: CGFloat in [s.height * 0.34, s.height * 0.52, s.height * 0.69] {
                    c.move(to: CGPoint(x: 6, y: lineY))
                    c.addLine(to: CGPoint(x: s.width - 6, y: lineY))
                    c.strokePath()
                }

            case "bike":
                // Rear wheel
                c.setStrokeColor(strokeColor.cgColor)
                c.strokeEllipse(in: CGRect(x: 1, y: s.height * 0.44, width: s.width * 0.40, height: s.height * 0.46))
                // Front wheel
                c.strokeEllipse(in: CGRect(x: s.width * 0.59, y: s.height * 0.44, width: s.width * 0.40, height: s.height * 0.46))
                // Top tube
                let w1x = s.width * 0.21, w2x = s.width * 0.79, wy = s.height * 0.67
                c.move(to: CGPoint(x: w1x, y: wy)); c.addLine(to: CGPoint(x: w2x, y: wy)); c.strokePath()
                // Seat post
                let mx = s.width / 2
                c.move(to: CGPoint(x: mx, y: wy)); c.addLine(to: CGPoint(x: mx, y: s.height * 0.28)); c.strokePath()
                // Beanbag rider
                c.setFillColor(accentColor.cgColor)
                c.fill(CGRect(x: mx - 5, y: s.height * 0.08, width: 10, height: 8))

            case "cornhole":
                // Board
                c.setFillColor(UIColor(red: 0.478, green: 0.306, blue: 0.176, alpha: 1).cgColor)
                let trapPath = CGMutablePath()
                trapPath.move(to: CGPoint(x: 2,             y: s.height - 2))
                trapPath.addLine(to: CGPoint(x: s.width - 2, y: s.height - 2))
                trapPath.addLine(to: CGPoint(x: s.width - 6, y: s.height * 0.22))
                trapPath.addLine(to: CGPoint(x: 6,           y: s.height * 0.22))
                trapPath.closeSubpath()
                c.addPath(trapPath); c.fillPath()
                c.setStrokeColor(darkColor.cgColor); c.addPath(trapPath); c.strokePath()
                // Hole
                c.setFillColor(darkColor.cgColor)
                c.fillEllipse(in: CGRect(x: s.width / 2 - 4, y: s.height * 0.34, width: 8, height: 8))
                // Beanbag corner
                c.saveGState()
                c.setFillColor(accentColor.cgColor)
                let bx = s.width * 0.66, by2 = s.height * 0.73
                c.translateBy(x: bx, y: by2); c.rotate(by: -.pi * 0.15)
                c.fill(CGRect(x: -5, y: -3, width: 9, height: 6))
                c.restoreGState()

            case "baseball":
                // Bat (rotated rect)
                c.saveGState()
                c.setFillColor(fillColor.cgColor)
                c.translateBy(x: s.width * 0.28, y: s.height * 0.62)
                c.rotate(by: .pi * 0.32)
                c.fill(CGRect(x: -2, y: -s.height * 0.50, width: 4, height: s.height * 0.50))
                c.restoreGState()
                // Ball
                c.setFillColor(UIColor(red: 0.941, green: 0.910, blue: 0.831, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: s.width * 0.52, y: s.height * 0.12,
                                         width: s.width * 0.44, height: s.height * 0.44))
                // Stitch arc
                c.setStrokeColor(accentColor.cgColor); c.setLineWidth(1.0)
                c.move(to: CGPoint(x: s.width * 0.57, y: s.height * 0.27))
                c.addCurve(to:      CGPoint(x: s.width * 0.90, y: s.height * 0.27),
                           control1: CGPoint(x: s.width * 0.68, y: s.height * 0.17),
                           control2: CGPoint(x: s.width * 0.78, y: s.height * 0.17))
                c.strokePath()

            case "beehive":
                let cx = s.width / 2, cy = s.height / 2
                // Outer hexagon
                c.setFillColor(fillColor.cgColor)
                let hex = makeHexPath(center: CGPoint(x: cx, y: cy), radius: s.width * 0.44)
                c.addPath(hex); c.fillPath()
                c.setStrokeColor(darkColor.cgColor); c.setLineWidth(1.2); c.addPath(hex); c.strokePath()
                // Inner hexagon
                c.setFillColor(UIColor(red: 0.478, green: 0.306, blue: 0.176, alpha: 1).cgColor)
                let hex2 = makeHexPath(center: CGPoint(x: cx, y: cy), radius: s.width * 0.22)
                c.addPath(hex2); c.fillPath()
                c.setStrokeColor(darkColor.cgColor); c.setLineWidth(0.8); c.addPath(hex2); c.strokePath()
                // Bee body
                c.setFillColor(darkColor.cgColor)
                c.fillEllipse(in: CGRect(x: s.width * 0.62, y: s.height * 0.13, width: 5, height: 5))
                c.setFillColor(fillColor.cgColor)
                c.fillEllipse(in: CGRect(x: s.width * 0.73, y: s.height * 0.07, width: 3, height: 3))

            case "beachball":
                // Pool water background square
                c.setFillColor(UIColor(red: 0.04, green: 0.22, blue: 0.46, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s.width, height: s.height))
                // Beach ball — striped circle
                let bbcx = s.width / 2, bbcy = s.height / 2, bbr = s.width * 0.40
                let bbSlice = (2.0 * CGFloat.pi) / 6.0
                let bbColors: [UIColor] = [
                    UIColor(red: 0.92, green: 0.15, blue: 0.15, alpha: 1),
                    UIColor(red: 0.95, green: 0.84, blue: 0.08, alpha: 1),
                    UIColor(red: 0.08, green: 0.38, blue: 0.92, alpha: 1),
                    UIColor(red: 0.12, green: 0.70, blue: 0.22, alpha: 1),
                    UIColor(red: 0.94, green: 0.94, blue: 0.92, alpha: 1),
                    accentColor,
                ]
                for (si, bbc) in bbColors.enumerated() {
                    c.setFillColor(bbc.cgColor)
                    let startA2 = CGFloat(si) * bbSlice - .pi / 2
                    let bbPath = CGMutablePath()
                    bbPath.move(to: CGPoint(x: bbcx, y: bbcy))
                    bbPath.addArc(center: CGPoint(x: bbcx, y: bbcy), radius: bbr,
                                  startAngle: startA2, endAngle: startA2 + bbSlice, clockwise: false)
                    bbPath.closeSubpath()
                    c.addPath(bbPath); c.fillPath()
                }
                c.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: bbcx - 2, y: bbcy - 2, width: 4, height: 4))
                // Wave ripple underneath
                c.setStrokeColor(UIColor(red: 0.40, green: 0.78, blue: 1.0, alpha: 0.55).cgColor)
                c.setLineWidth(1.0)
                let wy2 = s.height * 0.76
                c.move(to: CGPoint(x: s.width * 0.14, y: wy2))
                c.addCurve(to: CGPoint(x: s.width * 0.86, y: wy2),
                           control1: CGPoint(x: s.width * 0.35, y: wy2 - 4),
                           control2: CGPoint(x: s.width * 0.65, y: wy2 + 4))
                c.strokePath()

            case "piranha":
                // River (blue rect)
                c.setFillColor(UIColor(red: 0.04, green: 0.16, blue: 0.40, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: s.height * 0.30, width: s.width, height: s.height * 0.40))
                // Bridge bags (two small squares crossing the river)
                c.setFillColor(accentColor.cgColor)
                for bx2: CGFloat in [s.width * 0.28, s.width * 0.52, s.width * 0.76] {
                    c.fill(CGRect(x: bx2 - 4, y: s.height * 0.41, width: 8, height: 8))
                }
                // Piranha fin
                c.setFillColor(fillColor.cgColor)
                let fPath = CGMutablePath()
                fPath.move(to:    CGPoint(x: s.width * 0.70, y: s.height * 0.32))
                fPath.addLine(to: CGPoint(x: s.width * 0.76, y: s.height * 0.18))
                fPath.addLine(to: CGPoint(x: s.width * 0.82, y: s.height * 0.32))
                fPath.closeSubpath()
                c.addPath(fPath); c.fillPath()

            case "explore":
                // Compass circle
                c.setStrokeColor(strokeColor.cgColor); c.setLineWidth(1.5)
                c.strokeEllipse(in: CGRect(x: 2, y: 2, width: s.width - 4, height: s.height - 4))
                // Diamond needle
                c.setFillColor(fillColor.cgColor)
                let cx2 = s.width / 2, cy2 = s.height / 2
                let needle = CGMutablePath()
                needle.move(to:    CGPoint(x: cx2,     y: cy2 - s.height * 0.36))
                needle.addLine(to: CGPoint(x: cx2 + 4, y: cy2))
                needle.addLine(to: CGPoint(x: cx2,     y: cy2 + s.height * 0.36))
                needle.addLine(to: CGPoint(x: cx2 - 4, y: cy2))
                needle.closeSubpath()
                c.addPath(needle); c.fillPath()
                c.setFillColor(darkColor.cgColor)
                c.fillEllipse(in: CGRect(x: cx2 - 2, y: cy2 - 2, width: 4, height: 4))

            default: break
            }
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }
    // swiftlint:enable function_body_length

    private func makeHexPath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath(); return path
    }

    // MARK: - CRT overlay
    private func addCrtOverlay() {
        let img = renderImage(CGSize(width: W, height: H)) { c, sz in
            c.clear(CGRect(x: 0, y: 0, width: sz.width, height: sz.height))
            // Scanlines
            c.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
            var y: CGFloat = 0
            while y < sz.height { c.fill(CGRect(x: 0, y: y, width: sz.width, height: 1)); y += 3 }
            // Radial vignette
            let space = CGColorSpaceCreateDeviceRGB()
            let vCols = [UIColor(white: 0, alpha: 0).cgColor,
                         UIColor(white: 0, alpha: 0.18).cgColor,
                         UIColor(white: 0, alpha: 0.65).cgColor] as CFArray
            if let vGrad = CGGradient(colorsSpace: space, colors: vCols, locations: [0, 0.55, 1.0]) {
                c.drawRadialGradient(vGrad,
                    startCenter: CGPoint(x: sz.width/2, y: sz.height/2), startRadius: 0,
                    endCenter:   CGPoint(x: sz.width/2, y: sz.height/2), endRadius: max(sz.width, sz.height) * 0.72,
                    options: [])
            }
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: W, height: H))
        overlay.position = .zero; overlay.zPosition = 100
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tapEnabled, let touch = touches.first else { return }
        let loc = touch.location(in: self)

        var name = ""
        for node in nodes(at: loc).sorted(by: { $0.zPosition > $1.zPosition }) {
            if let n = node.name, !n.isEmpty { name = n; break }
        }
        guard !name.isEmpty else { return }

        let isLocked = items.first(where: { $0.name == name })?.isLocked ?? false
        if let card = cardNodes[name] {
            if isLocked {
                card.run(.sequence([
                    .moveBy(x: -3, y: 0, duration: 0.05),
                    .moveBy(x:  6, y: 0, duration: 0.06),
                    .moveBy(x: -3, y: 0, duration: 0.05),
                ]))
                return
            }
            card.run(.sequence([.scale(to: 0.95, duration: 0.07), .scale(to: 1.0, duration: 0.07)]))
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
            s.previousScene = self; s.scaleMode = .resizeFill
            s.availableHoneyBags = 0; s.availableBombBags = 0; s.availableMagicBags = 0; s.onComplete = { _ in }
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

        case "beachball":
            let s = BeachBallCornholeScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.onComplete = { _ in }
            push(to: s)

        case "piranha":
            let s = BridgePiranhaScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.onComplete = { _ in }
            push(to: s)

        case "explore":
            break // locked

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
