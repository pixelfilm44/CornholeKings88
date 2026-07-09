import SpriteKit
import UIKit

final class MiniGamePickerScene: SKScene {

    var onBikeRace: (() -> Void)?

    private var W: CGFloat = 0, H: CGFloat = 0
    private var cardNodes: [String: SKNode] = [:]
    private var tapEnabled = false
    private var nodesCount = 45
    private weak var nodesLabel: SKLabelNode?
    private var hasSetup = false
    private var ribbonBottomY: CGFloat = 0   // scene-Y of bottom edge of the top ribbon

    private struct MenuItem {
        let label: String
        let subLabel: String
        let name: String
        let isLocked: Bool
        /// nil for non-graded entries (story, explore, and Kickball — the latter is a
        /// pure forgiveness-ramp story beat that intentionally isn't graded).
        var medalGame: MiniGameKey? = nil
    }

    private let items: [MenuItem] = [
        MenuItem(label: "STORY MODE",     subLabel: "adventure",  name: "story",      isLocked: false),
        MenuItem(label: "BEANBAG BIKE",   subLabel: "racing",     name: "bike",       isLocked: false, medalGame: .bike),
        MenuItem(label: "CORNHOLE",       subLabel: "bag toss",   name: "cornhole",   isLocked: false, medalGame: .cornhole),
        MenuItem(label: "BASEBALL",       subLabel: "batting",    name: "baseball",   isLocked: false, medalGame: .baseball),
        MenuItem(label: "BEEHIVE BATTLE", subLabel: "defense",    name: "beehive",    isLocked: false, medalGame: .beehive),
        MenuItem(label: "BEACH BALL",     subLabel: "pool blitz",    name: "beachball",  isLocked: false, medalGame: .beachball),
        MenuItem(label: "PIRANHA BRIDGE", subLabel: "bridge build",  name: "piranha",    isLocked: false, medalGame: .piranha),
        MenuItem(label: "SUBURBAN JOUSTERS", subLabel: "bike joust", name: "jousters",   isLocked: false, medalGame: .jousters),
        MenuItem(label: "WELL DROPPER",   subLabel: "tilt to dodge", name: "wellflinger", isLocked: false, medalGame: .wellFlinger),
        MenuItem(label: "KICKBALL",       subLabel: "dream at bat",  name: "kickball",   isLocked: false),
        MenuItem(label: "MOP CHASE",      subLabel: "bucket rhythm", name: "mopChase",   isLocked: false, medalGame: .mopChase),
        MenuItem(label: "HORSE RACE",     subLabel: "cornhole derby", name: "horseRace",  isLocked: false, medalGame: .horseRace),
        MenuItem(label: "EXPLORE",        subLabel: "open world",    name: "explore",    isLocked: true),
    ]

    // Parchment palette
    private let paper     = SKColor(red: 0.953, green: 0.902, blue: 0.784, alpha: 1) // #f3e6c8
    private let surface   = SKColor(red: 0.925, green: 0.855, blue: 0.706, alpha: 1) // #ecdab4
    private let surface2  = SKColor(red: 0.890, green: 0.812, blue: 0.639, alpha: 1) // #e3cfa3
    private let ink       = SKColor(red: 0.290, green: 0.204, blue: 0.082, alpha: 1) // #4a3415
    private let muted     = SKColor(red: 0.604, green: 0.494, blue: 0.306, alpha: 1) // #9a7e4e
    private let amber     = SKColor(red: 0.784, green: 0.510, blue: 0.110, alpha: 1) // #c8821c
    private let deep      = SKColor(red: 0.478, green: 0.243, blue: 0.047, alpha: 1) // #7a3e0c
    private let onAmber   = SKColor(red: 0.992, green: 0.953, blue: 0.855, alpha: 1) // #fdf3da
    private let edge      = SKColor(red: 0.290, green: 0.204, blue: 0.082, alpha: 1) // #4a3415
    private let disabled  = SKColor(red: 0.847, green: 0.780, blue: 0.620, alpha: 1) // #d8c79e
    private let disInk    = SKColor(red: 0.671, green: 0.584, blue: 0.408, alpha: 1) // #ab9568
    private let dsRed     = SKColor(red: 0.765, green: 0.227, blue: 0.094, alpha: 1) // #c33a18

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        backgroundColor = SKColor(red: 0.788, green: 0.706, blue: 0.522, alpha: 1) // #c9b485

        // Re-entry path (returning from a mini-game): wipe stale nodes/actions so input doesn't get
        // jammed by leftover state from the previous presentation, then rebuild from scratch.
        if hasSetup {
            removeAllActions()
            removeAllChildren()
            cardNodes.removeAll()
            nodesLabel = nil
            tapEnabled = false
        }
        hasSetup = true

        setupHeader()
        setupEyebrow()
        setupCards()
        setupFooter()
        addCrtOverlay()

        isPaused = false
        run(.sequence([.wait(forDuration: 0.5), .run { self.tapEnabled = true }]))
    }

    // MARK: - Header (parchment ribbon with dark edge border)
    private func setupHeader() {
        let font = "PressStart2P-Regular"

        let topInset  = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let topBarY   = H / 2 - totalTopH / 2
        ribbonBottomY = H / 2 - totalTopH

        let bar = SKSpriteNode(color: paper, size: CGSize(width: W, height: totalTopH))
        bar.position  = CGPoint(x: 0, y: topBarY)
        bar.zPosition = 10
        addChild(bar)

        // 3px dark edge bottom border
        let border = SKSpriteNode(color: edge, size: CGSize(width: W, height: 3))
        border.position  = CGPoint(x: 0, y: ribbonBottomY + 1)
        border.zPosition = 11
        addChild(border)

        let contentY = H / 2 - topInset - topH / 2

        // Zone A (left): back button
        let backLbl = SKLabelNode(fontNamed: font)
        backLbl.text = "◀ BACK"
        backLbl.fontSize = min(9, W / 38)
        backLbl.fontColor = deep
        backLbl.horizontalAlignmentMode = .left
        backLbl.verticalAlignmentMode   = .center
        backLbl.position  = CGPoint(x: -W / 2 + 18, y: contentY)
        backLbl.zPosition = 11
        backLbl.name      = "back"
        addChild(backLbl)

        // Zone B (center): title
        let title = SKLabelNode(fontNamed: font)
        title.text = "MINI GAMES"
        title.fontSize = min(13, W / 26)
        title.fontColor = deep
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position  = CGPoint(x: 0, y: contentY)
        title.zPosition = 11
        addChild(title)
    }

    // MARK: - Eyebrow
    private func setupEyebrow() {
        let font = "PressStart2P-Regular"
        let ey = ribbonBottomY - 22

        let lbl = SKLabelNode(fontNamed: font)
        lbl.text = "CHOOSE YOUR EVENT"
        lbl.fontSize = min(7, W / 50)
        lbl.fontColor = muted
        lbl.horizontalAlignmentMode = .left
        lbl.verticalAlignmentMode   = .center
        lbl.position = CGPoint(x: -W / 2 + 20, y: ey); lbl.zPosition = 10
        addChild(lbl)

        // Trailing line
        let lineX0: CGFloat = lbl.position.x + lbl.frame.width + 12
        let lineX1: CGFloat = W / 2 - 20
        let line = SKSpriteNode(color: surface2, size: CGSize(width: lineX1 - lineX0, height: 2))
        line.anchorPoint = CGPoint(x: 0, y: 0.5)
        line.position = CGPoint(x: lineX0, y: ey)
        line.zPosition = 10
        addChild(line)
    }

    // MARK: - Cards
    private func setupCards() {
        let font = "PressStart2P-Regular"
        let footerH: CGFloat  = 28
        let eyebrowH: CGFloat = 40
        let sidePad: CGFloat  = 20
        let gap: CGFloat      = 6
        let btnW = W - sidePad * 2
        let usableH = ribbonBottomY + H / 2 - footerH - eyebrowH - 12
        let rowH = min(42, max(30, (usableH - CGFloat(items.count - 1) * gap) / CGFloat(items.count)))

        let topY   = ribbonBottomY - eyebrowH - 4
        var curY   = topY - rowH / 2

        let iconSz: CGFloat = min(24, rowH - 6)
        let textX  = -btnW / 2 + iconSz + 16

        for (i, item) in items.enumerated() {
            let cardY = curY
            let card  = SKNode()
            card.position  = CGPoint(x: 0, y: cardY)
            card.zPosition = CGFloat(20 + i)
            card.name      = item.name
            addChild(card)
            cardNodes[item.name] = card

            // Icon (no background square)
            let iconTex = makeIconTexture(item.name, size: iconSz, locked: item.isLocked)
            let iconSp  = SKSpriteNode(texture: iconTex, size: CGSize(width: iconSz, height: iconSz))
            iconSp.position = CGPoint(x: -btnW / 2 + iconSz / 2, y: 0)
            iconSp.name = item.name
            card.addChild(iconSp)

            // Title
            let titleLbl = SKLabelNode(fontNamed: font)
            titleLbl.text = item.label
            titleLbl.fontSize = min(10, btnW / 30)
            titleLbl.fontColor = item.isLocked ? disInk : deep
            titleLbl.horizontalAlignmentMode = .left
            titleLbl.verticalAlignmentMode   = .center
            titleLbl.position  = CGPoint(x: textX, y: 6)
            titleLbl.name = item.name
            card.addChild(titleLbl)

            // Sub
            let subLbl = SKLabelNode(fontNamed: font)
            subLbl.text = item.subLabel
            subLbl.fontSize = min(5, btnW / 54)
            subLbl.fontColor = item.isLocked ? disInk : muted
            subLbl.horizontalAlignmentMode = .left
            subLbl.verticalAlignmentMode   = .center
            subLbl.position  = CGPoint(x: textX, y: -6)
            subLbl.name = item.name
            card.addChild(subLbl)

            if item.isLocked {
                let lockLbl = SKLabelNode(fontNamed: "AppleColorEmoji")
                lockLbl.text = "🔒"
                lockLbl.fontSize  = 11
                lockLbl.horizontalAlignmentMode = .right
                lockLbl.verticalAlignmentMode   = .center
                lockLbl.position  = CGPoint(x: btnW / 2, y: 0)
                lockLbl.name = item.name
                card.addChild(lockLbl)
            } else {
                let arrow = SKLabelNode(fontNamed: font)
                arrow.text = "\u{25B6}"
                arrow.fontSize = min(10, btnW / 30)
                arrow.fontColor = amber
                arrow.horizontalAlignmentMode = .right
                arrow.verticalAlignmentMode   = .center
                arrow.position  = CGPoint(x: btnW / 2, y: 0)
                arrow.name = item.name
                arrow.run(.repeatForever(.sequence([
                    .moveBy(x: 3, y: 0, duration: 0.7),
                    .moveBy(x: -3, y: 0, duration: 0.7),
                ])))
                card.addChild(arrow)
            }

            // Medal badge — best tier ever earned, tucked above the arrow/lock corner.
            if let game = item.medalGame {
                let tier = MedalManager.shared.medal(for: game)
                if tier != .none {
                    let badge = SKLabelNode(fontNamed: "AppleColorEmoji")
                    badge.text = tier.emoji
                    badge.fontSize = 9
                    badge.horizontalAlignmentMode = .right
                    badge.verticalAlignmentMode   = .center
                    badge.position = CGPoint(x: btnW / 2, y: rowH / 2 - 8)
                    badge.name = item.name
                    card.addChild(badge)
                }
            }

            // Separator line between items
            if i < items.count - 1 {
                let sep = SKSpriteNode(color: surface2, size: CGSize(width: btnW, height: 1))
                sep.position = CGPoint(x: 0, y: -rowH / 2 - gap / 2)
                sep.alpha = 0.7
                card.addChild(sep)
            }

            // Staggered entry
            card.alpha = 0
            card.position.y = cardY - 6
            let delay = Double(i) * 0.04 + 0.05
            card.run(.sequence([
                .wait(forDuration: delay),
                .group([
                    .fadeIn(withDuration: 0.28),
                    .moveBy(x: 0, y: 6, duration: 0.28),
                ]),
            ]))

            curY -= rowH + gap
        }
    }

    // MARK: - Footer
    private func setupFooter() {
        let font = "PressStart2P-Regular"
        let footerY = -H / 2 + 14

        // Top border line
        let ftBorder = SKSpriteNode(color: surface2, size: CGSize(width: W, height: 3))
        ftBorder.position = CGPoint(x: 0, y: -H / 2 + 28)
        ftBorder.zPosition = 10
        addChild(ftBorder)

        let nodesLbl = SKLabelNode(fontNamed: font)
        nodesLbl.text = "nodes:45"
        nodesLbl.fontSize  = 6
        nodesLbl.fontColor = muted
        nodesLbl.horizontalAlignmentMode = .right
        nodesLbl.verticalAlignmentMode   = .center
        nodesLbl.position  = CGPoint(x: W / 2 - 68, y: footerY)
        nodesLbl.zPosition = 10
        addChild(nodesLbl); nodesLabel = nodesLbl

        let fpsLbl = SKLabelNode(fontNamed: font)
        fpsLbl.text = "60.0 fps"
        fpsLbl.fontSize  = 6
        fpsLbl.fontColor = muted
        fpsLbl.horizontalAlignmentMode = .right
        fpsLbl.verticalAlignmentMode   = .center
        fpsLbl.position  = CGPoint(x: W / 2 - 18, y: footerY)
        fpsLbl.zPosition = 10
        addChild(fpsLbl)

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

    // swiftlint:disable function_body_length
    private func makeIconTexture(_ name: String, size: CGFloat, locked: Bool) -> SKTexture {
        let sz = CGSize(width: size, height: size)
        let strokeColor = locked
            ? UIColor(red: 0.671, green: 0.584, blue: 0.408, alpha: 0.7) // disInk
            : UIColor(red: 0.784, green: 0.510, blue: 0.110, alpha: 1)   // amber
        let fillColor = strokeColor
        let accentColor = locked
            ? UIColor(red: 0.671, green: 0.584, blue: 0.408, alpha: 0.6) // disInk
            : UIColor(red: 0.765, green: 0.227, blue: 0.094, alpha: 1)   // dsRed
        let darkColor = UIColor(red: 0.290, green: 0.204, blue: 0.082, alpha: 1) // ink

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

            case "jousters":
                // Dirt arena backdrop
                c.setFillColor(UIColor(red: 0.573, green: 0.400, blue: 0.278, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s.width, height: s.height))
                // Two bike frame bars going up the icon (lances) — silver tips, ribbons
                c.setStrokeColor(UIColor(white: 0.33, alpha: 1).cgColor)
                c.setLineWidth(2.0)
                // Player lance (lower-left → upper-right) red ribbon
                c.move(to: CGPoint(x: s.width * 0.20, y: s.height * 0.18))
                c.addLine(to: CGPoint(x: s.width * 0.78, y: s.height * 0.78))
                c.strokePath()
                // Rival lance (upper-left → lower-right) yellow ribbon
                c.move(to: CGPoint(x: s.width * 0.22, y: s.height * 0.82))
                c.addLine(to: CGPoint(x: s.width * 0.80, y: s.height * 0.22))
                c.strokePath()
                // Crossed silver tips
                c.setFillColor(UIColor(white: 0.61, alpha: 1).cgColor)
                c.fill(CGRect(x: s.width * 0.72, y: s.height * 0.72, width: 5, height: 5))
                c.fill(CGRect(x: s.width * 0.72, y: s.height * 0.20, width: 5, height: 5))
                // Red and yellow ribbon markers
                c.setFillColor(accentColor.cgColor)
                c.fill(CGRect(x: s.width * 0.45, y: s.height * 0.42, width: 4, height: 4))
                c.setFillColor(UIColor(red: 0.96, green: 0.84, blue: 0.10, alpha: 1).cgColor)
                c.fill(CGRect(x: s.width * 0.52, y: s.height * 0.55, width: 4, height: 4))

            case "wellflinger":
                // Brick well (circle) with dark interior
                c.setFillColor(UIColor(red: 0.498, green: 0.114, blue: 0.114, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: 2, y: 2, width: s.width - 4, height: s.height - 4))
                c.setFillColor(UIColor(red: 0.059, green: 0.090, blue: 0.157, alpha: 1).cgColor)
                let innerR = s.width * 0.28
                c.fillEllipse(in: CGRect(x: s.width/2 - innerR, y: s.height/2 - innerR,
                                         width: innerR*2, height: innerR*2))
                // Rim highlight
                c.setStrokeColor(UIColor(red: 0.722, green: 0.176, blue: 0.176, alpha: 1).cgColor)
                c.setLineWidth(1.5)
                c.strokeEllipse(in: CGRect(x: s.width*0.14, y: s.height*0.14,
                                            width: s.width*0.72, height: s.height*0.72))
                // Bag descending into well
                c.setFillColor(accentColor.cgColor)
                c.fill(CGRect(x: s.width*0.44, y: s.height*0.44, width: s.width*0.14, height: s.height*0.14))

            case "kickball":
                // Pavement backdrop with chalk foul lines and a big red kickball
                c.setFillColor(UIColor(red: 0.32, green: 0.31, blue: 0.33, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s.width, height: s.height))
                // Chalk foul lines from the bottom corner
                c.setStrokeColor(UIColor(white: 0.92, alpha: 0.6).cgColor)
                c.setLineWidth(1.5)
                c.move(to: CGPoint(x: s.width * 0.50, y: s.height * 0.88))
                c.addLine(to: CGPoint(x: s.width * 0.10, y: s.height * 0.12))
                c.strokePath()
                c.move(to: CGPoint(x: s.width * 0.50, y: s.height * 0.88))
                c.addLine(to: CGPoint(x: s.width * 0.90, y: s.height * 0.12))
                c.strokePath()
                // Home plate
                c.setFillColor(UIColor(white: 0.94, alpha: 0.9).cgColor)
                c.fill(CGRect(x: s.width * 0.46, y: s.height * 0.80, width: 6, height: 6))
                // The cocky red kickball
                c.setFillColor(accentColor.cgColor)
                let ballR = s.width * 0.18
                c.fillEllipse(in: CGRect(x: s.width * 0.50 - ballR, y: s.height * 0.36 - ballR,
                                         width: ballR * 2, height: ballR * 2))
                c.setStrokeColor(UIColor(red: 0.55, green: 0.10, blue: 0.08, alpha: 1).cgColor)
                c.setLineWidth(1)
                c.strokeEllipse(in: CGRect(x: s.width * 0.50 - ballR, y: s.height * 0.36 - ballR,
                                           width: ballR * 2, height: ballR * 2))

            case "mopChase":
                // Hallway with lockers, a yellow bucket, and a mop
                c.setFillColor(UIColor(red: 0.78, green: 0.73, blue: 0.62, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s.width, height: s.height))
                // Locker band across the top
                c.setFillColor(UIColor(red: 0.30, green: 0.42, blue: 0.55, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s.width, height: s.height * 0.38))
                c.setFillColor(UIColor(white: 0, alpha: 0.25).cgColor)
                for lx in stride(from: s.width * 0.12, through: s.width * 0.88, by: s.width * 0.22) {
                    c.fill(CGRect(x: lx, y: s.height * 0.08, width: 1.5, height: s.height * 0.24))
                }
                // Floor
                c.setFillColor(UIColor(red: 0.55, green: 0.50, blue: 0.44, alpha: 1).cgColor)
                c.fill(CGRect(x: 0, y: s.height * 0.72, width: s.width, height: s.height * 0.28))
                // Water trail
                c.setFillColor(UIColor(red: 0.35, green: 0.60, blue: 0.90, alpha: 0.5).cgColor)
                c.fillEllipse(in: CGRect(x: s.width * 0.08, y: s.height * 0.70,
                                         width: s.width * 0.34, height: 5))
                // Yellow bucket
                c.setFillColor(UIColor(red: 0.85, green: 0.75, blue: 0.20, alpha: 1).cgColor)
                c.fill(CGRect(x: s.width * 0.40, y: s.height * 0.54, width: s.width * 0.24, height: s.height * 0.18))
                // Wheels
                c.setFillColor(UIColor(white: 0.2, alpha: 1).cgColor)
                c.fillEllipse(in: CGRect(x: s.width * 0.42, y: s.height * 0.70, width: 5, height: 5))
                c.fillEllipse(in: CGRect(x: s.width * 0.58, y: s.height * 0.70, width: 5, height: 5))
                // Mop leaning out of the bucket
                c.setStrokeColor(UIColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1).cgColor)
                c.setLineWidth(2.5)
                c.move(to: CGPoint(x: s.width * 0.56, y: s.height * 0.58))
                c.addLine(to: CGPoint(x: s.width * 0.78, y: s.height * 0.16))
                c.strokePath()
                c.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
                c.fill(CGRect(x: s.width * 0.74, y: s.height * 0.10, width: 8, height: 6))

            case "horseRace":
                // Race lane with a tiny red horse running over it
                c.setFillColor(UIColor(red: 0.44, green: 0.30, blue: 0.16, alpha: 1).cgColor)
                c.fill(CGRect(x: 1, y: s.height * 0.38, width: s.width - 2, height: s.height * 0.30))
                // Tick marks
                c.setFillColor(UIColor(white: 1.0, alpha: 0.32).cgColor)
                for tx in stride(from: s.width * 0.10, through: s.width * 0.86, by: s.width * 0.12) {
                    c.fill(CGRect(x: tx, y: s.height * 0.40, width: 1, height: s.height * 0.26))
                }
                // Finish line
                c.setFillColor(UIColor(red: 1.0, green: 0.92, blue: 0.40, alpha: 1).cgColor)
                c.fill(CGRect(x: s.width * 0.86, y: s.height * 0.38, width: 2, height: s.height * 0.30))
                // Red horse silhouette
                c.setFillColor(accentColor.cgColor)
                c.fill(CGRect(x: s.width * 0.30, y: s.height * 0.46, width: s.width * 0.22, height: s.height * 0.10))
                c.fill(CGRect(x: s.width * 0.48, y: s.height * 0.42, width: s.width * 0.06, height: s.height * 0.10))
                c.fill(CGRect(x: s.width * 0.30, y: s.height * 0.56, width: 2, height: s.height * 0.08))
                c.fill(CGRect(x: s.width * 0.40, y: s.height * 0.56, width: 2, height: s.height * 0.08))
                c.fill(CGRect(x: s.width * 0.48, y: s.height * 0.56, width: 2, height: s.height * 0.08))
                // Bag below
                c.setFillColor(fillColor.cgColor)
                c.fill(CGRect(x: s.width * 0.10, y: s.height * 0.74, width: s.width * 0.18, height: s.height * 0.12))

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
            // Scanlines (lighter for parchment)
            c.setFillColor(UIColor(white: 0, alpha: 0.10).cgColor)
            var y: CGFloat = 0
            while y < sz.height { c.fill(CGRect(x: 0, y: y, width: sz.width, height: 1)); y += 3 }
            // Radial vignette
            let space = CGColorSpaceCreateDeviceRGB()
            let vCols = [UIColor(white: 0, alpha: 0).cgColor,
                         UIColor(white: 0, alpha: 0.10).cgColor,
                         UIColor(white: 0, alpha: 0.35).cgColor] as CFArray
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
            let bikeVC = BikeDodgeViewController()
            bikeVC.modalPresentationStyle = .fullScreen
            DispatchQueue.main.async { [weak self] in
                self?.view?.window?.rootViewController?.present(bikeVC, animated: true)
            }

        case "cornhole":
            let s = CornholeMiniGameScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            let inv = InventoryManager()
            // Menu play uses whatever special bags the player already owns, but awards none
            // (awardsRewards stays false), per the no-prize-from-menu rule.
            s.availableHoneyBags  = inv.counts[.honeyBag,  default: 0]
            s.availableBombBags   = inv.counts[.bombBag,   default: 0]
            s.availableMagicBags  = inv.counts[.magicBag,  default: 0]
            s.availableFireBags   = inv.counts[.fireBag,   default: 0]
            s.availableGoldenBags = inv.counts[.goldenBag, default: 0]
            s.availableCannonballBags = inv.counts[.cannonballBag, default: 0]
            s.onComplete = { _ in }
            push(to: s)

        case "baseball":
            let s = CornholeBaseballScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.showOpponentPicker = true
            s.onComplete = { _ in }
            push(to: s)

        case "beehive":
            let s = BeeHiveScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            if HeartsManager.shared.currentHearts <= 0 { HeartsManager.shared.refill() }
            s.startingHearts = HeartsManager.shared.currentHearts
            s.onComplete = { [weak s] _ in
                guard let s = s else { return }
                HeartsManager.shared.set(s.remainingHearts)
            }
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

        case "jousters":
            let s = SuburbanJoustersScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            if HeartsManager.shared.currentHearts <= 0 { HeartsManager.shared.refill() }
            s.startingHearts = HeartsManager.shared.currentHearts
            s.onComplete = { [weak s] _ in
                guard let s = s else { return }
                HeartsManager.shared.set(s.remainingHearts)
                // No Golden Lance award from the menu — prizes are world/story only.
            }
            push(to: s)

        case "wellflinger":
            let s = WellFlingerScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            // Free-play from the menu isn't tied to real inventory — start with
            // a generous 5 bags so there's room to learn the shaft.
            s.availableBags = 5
            s.onComplete = { _ in }
            push(to: s)

        case "kickball":
            let s = KickballScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.onComplete = { _ in }
            push(to: s)

        case "mopChase":
            let s = MopBucketChaseScene(size: ppSize)
            s.previousScene = self; s.scaleMode = .resizeFill
            s.onComplete = { _ in }
            push(to: s)

        case "horseRace":
            let s = HorseRaceCornholeScene(size: ppSize)
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
        guard let view = self.view else { return }
        SceneTransition.iris(in: view, to: scene)
    }
}
