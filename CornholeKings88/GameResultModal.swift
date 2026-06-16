import SpriteKit

/// Shared, consistently-styled victory / defeat modal used by every mini-game.
///
/// Each scene keeps its own touch routing: it supplies `Button`s with the same
/// `name`s its `touchesBegan` already dispatches on, so swapping a scene's bespoke
/// panel for `GameResultModal.make(...)` only changes the visuals, never the flow.
///
/// Rewards are passed in by the scene **only when it is in reward context** (launched
/// from the world map / story mode). Launched from the mini-game menu, the scene passes
/// an empty `rewards` array and no prize lines are drawn — matching the design rule that
/// menu play never grants a prize.
enum GameResultModal {

    // MARK: Design-system colors (Bit-Wood Brawler)
    private static let dsPrimary = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.96)
    private static let dsGold    = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)
    private static let dsWin     = SKColor(red: 0.30, green: 0.92, blue: 0.34, alpha: 1)
    private static let dsLoss    = SKColor(red: 0.90, green: 0.34, blue: 0.30, alpha: 1)
    private static let dsIron    = SKColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)

    enum ButtonStyle { case primary, danger, neutral }

    struct Button {
        let label: String
        let name: String
        var style: ButtonStyle = .neutral
    }

    /// A prize line, e.g. "+3 BOMB BAGS". Pass `count: 0` to show `text` alone
    /// (used for unlock messages like "BASEBALL UNLOCKED!").
    struct Reward {
        let item: ItemType?
        let count: Int
        let text: String?
        init(item: ItemType?, count: Int, text: String? = nil) {
            self.item = item; self.count = count; self.text = text
        }
        /// Convenience for a plain unlock line with no item swatch.
        static func unlock(_ text: String) -> Reward { Reward(item: nil, count: 0, text: text) }
    }

    /// Builds the modal node (already positioned at scene center). Caller adds it to the
    /// scene and is responsible for routing taps on the supplied button names.
    static func make(sceneSize: CGSize,
                     won: Bool,
                     title: String,
                     subtitle: String? = nil,
                     detail: String? = nil,
                     hint: (text: String, color: SKColor)? = nil,
                     rewards: [Reward] = [],
                     buttons: [Button]) -> SKNode {

        let W = sceneSize.width
        let panel = SKNode()
        panel.zPosition = 1000
        panel.name = "gameResultModal"

        let panelW = W * 0.84
        // Height grows with content so reward lines never overlap buttons.
        let rewardRows = rewards.count
        let baseH = sceneSize.height * 0.50
        let panelH = min(sceneSize.height * 0.86,
                         baseH + CGFloat(rewardRows) * (W * 0.045)
                               + CGFloat(max(0, buttons.count - 2)) * (W * 0.075))

        // Backing + double border (gold over iron) for the wood-iron look.
        let backing = SKSpriteNode(color: dsPrimary, size: CGSize(width: panelW, height: panelH))
        panel.addChild(backing)

        let ironBorder = SKShapeNode(rectOf: CGSize(width: panelW + 6, height: panelH + 6))
        ironBorder.strokeColor = dsIron; ironBorder.fillColor = .clear; ironBorder.lineWidth = 4
        panel.addChild(ironBorder)
        let goldBorder = SKShapeNode(rectOf: CGSize(width: panelW + 2, height: panelH + 2))
        goldBorder.strokeColor = dsGold; goldBorder.fillColor = .clear; goldBorder.lineWidth = 2
        panel.addChild(goldBorder)

        let fs = max(6, W * 0.050)

        // Lay content out from the top down so spacing is uniform regardless of count.
        var y = panelH * 0.5 - fs * 1.6

        // Dancing Jeff perched on top of the panel — win celebration.
        if won, let jeff = makeDancingJeff(size: max(192, W * 0.72)) {
            jeff.position = .zero
            jeff.zPosition = 0
            panel.addChild(jeff)
        }

        // Title
        let titleLbl = label(won ? title : title, size: fs * 0.85,
                             color: won ? dsWin : dsLoss)
        titleLbl.position = CGPoint(x: 0, y: y)
        panel.addChild(titleLbl)
        y -= fs * 1.5

        if let subtitle = subtitle {
            let s = label(subtitle, size: fs * 0.58, color: SKColor(white: 0.85, alpha: 1))
            s.position = CGPoint(x: 0, y: y)
            panel.addChild(s)
            y -= fs * 1.15
        }

        if let detail = detail {
            let d = label(detail, size: max(5, fs * 0.52), color: SKColor(white: 0.55, alpha: 1))
            d.position = CGPoint(x: 0, y: y)
            panel.addChild(d)
            y -= fs * 1.05
        }

        // Reward lines (gold), each with a small color swatch for the item.
        for r in rewards {
            let row = SKNode()
            let text: String
            if let custom = r.text {
                text = custom
            } else if let item = r.item {
                text = "+\(r.count) \(item.displayName)\(r.count == 1 ? "" : "S")"
            } else {
                text = ""
            }
            let lbl = label(text, size: max(6, fs * 0.56), color: dsGold)
            row.addChild(lbl)
            if let item = r.item {
                let sw = SKShapeNode(rectOf: CGSize(width: fs * 0.5, height: fs * 0.5), cornerRadius: 1)
                sw.fillColor = item.color; sw.strokeColor = dsGold; sw.lineWidth = 1
                sw.position = CGPoint(x: -lbl.frame.width / 2 - fs * 0.55, y: 0)
                row.addChild(sw)
            }
            row.position = CGPoint(x: 0, y: y)
            row.alpha = 0
            row.run(.sequence([.wait(forDuration: 0.35), .fadeIn(withDuration: 0.25)]))
            // Gentle pulse so rewards feel celebratory.
            lbl.run(.repeatForever(.sequence([.scale(to: 1.08, duration: 0.5),
                                              .scale(to: 1.0, duration: 0.5)])))
            panel.addChild(row)
            y -= fs * 1.1
        }

        if let hint = hint {
            let h = label(hint.text, size: max(5, fs * 0.50), color: hint.color)
            h.numberOfLines = 3
            h.position = CGPoint(x: 0, y: y)
            panel.addChild(h)
            y -= fs * 1.6
        }

        // Buttons, stacked from the bottom up.
        let btnH = fs * 1.8
        let btnGap = fs * 0.55
        var by = -panelH * 0.5 + btnH * 0.7 + fs * 0.5
        for b in buttons.reversed() {
            let isWide = b.style == .primary
            let btn = button(label: b.label, name: b.name, style: b.style,
                             size: CGSize(width: panelW * (isWide ? 0.66 : 0.50), height: btnH))
            btn.position = CGPoint(x: 0, y: by)
            panel.addChild(btn)
            by += btnH + btnGap
        }

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.30))
        return panel
    }

    // MARK: - Dancing Jeff

    /// 64×64 frames in a 6-column sheet (matches PlayerNode layout).
    private static let jeffSheet: SKTexture? = {
        let t = SKTexture(imageNamed: "jeff_sprite")
        t.filteringMode = .nearest
        return t.size().width > 0 ? t : nil
    }()

    private static func jeffFrame(row: Int, col: Int) -> SKTexture? {
        guard let sheet = jeffSheet else { return nil }
        let nW = 64.0 / sheet.size().width
        let nH = 64.0 / sheet.size().height
        let nX = CGFloat(col) * nW
        let nY = 1.0 - CGFloat(row + 1) * nH
        let t = SKTexture(rect: CGRect(x: nX, y: nY, width: nW, height: nH), in: sheet)
        t.filteringMode = .nearest
        return t
    }

    /// A little Jeff sprite that hops back-and-forth and swaps step frames in beat.
    private static func makeDancingJeff(size: CGFloat) -> SKNode? {
        // Row 3 = move-down (legs apart on different frames). Frames 0 & 3 read as opposite steps.
        guard let stepA = jeffFrame(row: 3, col: 0),
              let stepB = jeffFrame(row: 3, col: 3) else { return nil }

        let sprite = SKSpriteNode(texture: stepA, size: CGSize(width: size, height: size))
        sprite.texture?.filteringMode = .nearest

        // Foot-swap on the beat.
        let beat = 0.22
        let stepAnim = SKAction.repeatForever(.sequence([
            .setTexture(stepA, resize: false),
            .wait(forDuration: beat),
            .setTexture(stepB, resize: false),
            .wait(forDuration: beat),
        ]))
        sprite.run(stepAnim)

        // Side-to-side sway, flipping facing on each side for that shuffle look.
        let sway: CGFloat = size * 0.18
        let flipR = SKAction.run { [weak sprite] in sprite?.xScale =  abs(sprite?.xScale ?? 1) }
        let flipL = SKAction.run { [weak sprite] in sprite?.xScale = -abs(sprite?.xScale ?? 1) }
        let swayAnim = SKAction.repeatForever(.sequence([
            flipR,
            .moveBy(x:  sway, y: 0, duration: beat * 2),
            flipL,
            .moveBy(x: -sway, y: 0, duration: beat * 2),
        ]))
        sprite.run(swayAnim)

        // Little hop synced to the beat.
        let hop: CGFloat = size * 0.10
        let hopAnim = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y:  hop, duration: beat * 0.5),
            .moveBy(x: 0, y: -hop, duration: beat * 0.5),
        ]))
        sprite.run(hopAnim)

        // Slight tilt for extra groove.
        let tilt: CGFloat = .pi / 28
        let tiltAnim = SKAction.repeatForever(.sequence([
            .rotate(toAngle:  tilt, duration: beat * 2, shortestUnitArc: true),
            .rotate(toAngle: -tilt, duration: beat * 2, shortestUnitArc: true),
        ]))
        sprite.run(tiltAnim)

        return sprite
    }

    // MARK: - Factories

    private static func label(_ text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.text = text
        l.fontSize = size
        l.fontColor = color
        l.numberOfLines = max(1, text.components(separatedBy: "\n").count)
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .center
        return l
    }

    private static func button(label text: String, name: String, style: ButtonStyle,
                               size: CGSize) -> SKNode {
        let container = SKNode()
        container.name = name

        let bg: SKColor
        switch style {
        case .primary: bg = SKColor(red: 0.18, green: 0.45, blue: 0.18, alpha: 1)
        case .danger:  bg = SKColor(red: 0.45, green: 0.12, blue: 0.10, alpha: 1)
        case .neutral: bg = SKColor(red: 0.16, green: 0.11, blue: 0.07, alpha: 1)
        }

        let body = SKSpriteNode(color: bg, size: size)
        body.name = name
        container.addChild(body)

        let border = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        border.strokeColor = dsGold; border.fillColor = .clear; border.lineWidth = 2
        border.name = name
        container.addChild(border)

        let lbl = label(text, size: max(6, size.height * 0.36), color: .white)
        lbl.name = name
        container.addChild(lbl)
        return container
    }
}
