import SpriteKit

// MARK: - OpponentConfig

/// Describes one selectable opponent — name, portrait asset, and a short trait line.
/// Reusable across any mini-game that needs a pre-game opponent picker.
struct OpponentConfig {
    let name: String
    let imageName: String   // PNG asset name (no extension)
    let traitText: String   // short one-liner shown under the portrait
    /// Optional pre-built texture used instead of `imageName` (for programmatic
    /// portraits like Barnum that have no asset). Falls back to `imageName` when nil.
    let textureOverride: SKTexture?

    init(name: String, imageName: String, traitText: String,
         textureOverride: SKTexture? = nil) {
        self.name = name
        self.imageName = imageName
        self.traitText = traitText
        self.textureOverride = textureOverride
    }
}

// MARK: - OpponentPickerNode

/// Full-screen overlay that lets the player choose an opponent before a mini-game starts.
/// Reusable: create with an array of OpponentConfig, add to the scene at a high zPosition,
/// then act on the `onSelected` index callback.
final class OpponentPickerNode: SKNode {

    /// Called with the 0-based index of the tapped card. The node removes itself afterward.
    var onSelected: ((Int) -> Void)?

    private let sceneSize: CGSize
    private let fontName: String

    init(opponents: [OpponentConfig],
         sceneSize: CGSize,
         fontName: String = "PressStart2P-Regular") {
        self.sceneSize = sceneSize
        self.fontName  = fontName
        super.init()
        isUserInteractionEnabled = true
        buildUI(opponents: opponents)
        alpha = 0
        run(.fadeIn(withDuration: 0.25))
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildUI(opponents: [OpponentConfig]) {
        // Dim the scene behind the panel
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.78),
                               size: CGSize(width: sceneSize.width  * 2,
                                            height: sceneSize.height * 2))
        addChild(dim)

        let panelW = sceneSize.width  * 0.84
        let panelH = sceneSize.height * (opponents.count >= 3 ? 0.80 : 0.60)
        let fs     = max(5, sceneSize.width * 0.040)

        // Panel background
        let panel = SKSpriteNode(
            color: Parchment.paper,
            size: CGSize(width: panelW, height: panelH))
        addChild(panel)

        // Ink edge border
        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = Parchment.edge
        border.fillColor   = .clear
        border.lineWidth   = 3
        addChild(border)

        // Title
        let title = makeLabel("CHOOSE OPPONENT", size: fs * 0.82,
                              color: Parchment.deep)
        title.position = CGPoint(x: 0, y: panelH * 0.44)
        addChild(title)

        if opponents.count >= 6 {
            // 3 regular on top, 3 boss below. The first three configs are the regular
            // opponents (Tom, Jenny, Barnum); the last three are bosses (Billy, Spirit,
            // CathyX), laid out in matching columns.
            let cardW   = panelW * 0.30
            let cardH   = panelH * 0.32
            let topY    = panelH * 0.15
            let bottomY = -panelH * 0.25
            let colXs:  [CGFloat] = [-panelW * 0.32, 0, panelW * 0.32]
            for i in 0..<3 {
                let card = buildCard(config: opponents[i], index: i, w: cardW, h: cardH, fs: fs * 0.9, isBoss: false)
                card.position = CGPoint(x: colXs[i], y: topY)
                addChild(card)
            }
            for i in 3..<6 {
                let card = buildCard(config: opponents[i], index: i, w: cardW, h: cardH, fs: fs * 0.9, isBoss: true)
                card.position = CGPoint(x: colXs[i - 3], y: bottomY)
                addChild(card)
            }
        } else if opponents.count >= 5 {
            // 3 regular on top, 2 boss centered below. The first three configs are the
            // regular opponents (Tom, Jenny, Barnum); the last two are bosses.
            let cardW   = panelW * 0.30
            let cardH   = panelH * 0.32
            let topY    = panelH * 0.15
            let bottomY = -panelH * 0.25
            let topXs:  [CGFloat] = [-panelW * 0.32, 0, panelW * 0.32]
            for i in 0..<3 {
                let card = buildCard(config: opponents[i], index: i, w: cardW, h: cardH, fs: fs * 0.9, isBoss: false)
                card.position = CGPoint(x: topXs[i], y: topY)
                addChild(card)
            }
            let bossW = panelW * 0.36
            let bossXs: [CGFloat] = [-panelW * 0.21, panelW * 0.21]
            for i in 3..<5 {
                let card = buildCard(config: opponents[i], index: i, w: bossW, h: cardH * 1.06, fs: fs, isBoss: true)
                card.position = CGPoint(x: bossXs[i - 3], y: bottomY)
                addChild(card)
            }
        } else if opponents.count >= 4 {
            // 2×2 grid: top row = regular opponents, bottom row = boss opponents
            let cardW   = panelW * 0.42
            let cardH   = panelH * 0.34
            let xOffset = panelW * 0.26
            let topY    = panelH * 0.13
            let bottomY = -panelH * 0.24

            for i in 0..<2 {
                let x = i == 0 ? -xOffset : xOffset
                let card = buildCard(config: opponents[i], index: i, w: cardW, h: cardH, fs: fs, isBoss: false)
                card.position = CGPoint(x: x, y: topY)
                addChild(card)
            }
            for i in 2..<4 {
                let x = i == 2 ? -xOffset : xOffset
                let card = buildCard(config: opponents[i], index: i, w: cardW, h: cardH, fs: fs, isBoss: true)
                card.position = CGPoint(x: x, y: bottomY)
                addChild(card)
            }
        } else if opponents.count == 3 {
            // 2+1 layout: first two side-by-side on top row, third centered on bottom row
            let cardW   = panelW * 0.42
            let cardH   = panelH * 0.35
            let xOffset = panelW * 0.26
            let topY    = panelH * 0.12
            let bottomY = -panelH * 0.26

            for i in 0..<2 {
                let x = i == 0 ? -xOffset : xOffset
                let card = buildCard(config: opponents[i], index: i, w: cardW, h: cardH, fs: fs, isBoss: false)
                card.position = CGPoint(x: x, y: topY)
                addChild(card)
            }
            let bossCard = buildCard(config: opponents[2], index: 2,
                                     w: cardW * 1.10, h: cardH * 1.18, fs: fs, isBoss: true)
            bossCard.position = CGPoint(x: 0, y: bottomY)
            addChild(bossCard)
        } else {
            // Original two-card side-by-side layout
            let cardW   = panelW * 0.42
            let cardH   = panelH * 0.66
            let xOffset = panelW * 0.26

            for (i, config) in opponents.enumerated() {
                let x = i == 0 ? -xOffset : xOffset
                let card = buildCard(config: config, index: i, w: cardW, h: cardH, fs: fs, isBoss: false)
                card.position = CGPoint(x: x, y: -panelH * 0.06)
                addChild(card)
            }
        }
    }

    private func buildCard(config: OpponentConfig, index: Int,
                           w: CGFloat, h: CGFloat, fs: CGFloat, isBoss: Bool) -> SKNode {
        let tag = "card_\(index)"
        let card = SKNode()

        let bgColor = Parchment.surface
        let borderColor = isBoss
            ? Parchment.red
            : Parchment.edge

        // Card background
        let bg = SKSpriteNode(color: bgColor, size: CGSize(width: w, height: h))
        bg.name = tag
        card.addChild(bg)

        // Card border
        let border = SKShapeNode(rectOf: CGSize(width: w + 2, height: h + 2))
        border.strokeColor = borderColor
        border.fillColor   = .clear
        border.lineWidth   = isBoss ? 3 : 2
        border.name = tag
        card.addChild(border)

        // Boss badge
        if isBoss {
            let badge = makeLabel("★ BOSS ★", size: max(4, fs * 0.50),
                                  color: Parchment.red)
            badge.position = CGPoint(x: 0, y: h * 0.42)
            badge.name = tag
            card.addChild(badge)
        }

        // Portrait image
        let tex = config.textureOverride ?? SKTexture(imageNamed: config.imageName)
        tex.filteringMode = .nearest
        let pSize    = min(w * 0.72, h * (isBoss ? 0.44 : 0.52))
        let portrait = SKSpriteNode(texture: tex, size: CGSize(width: pSize, height: pSize))
        portrait.position = CGPoint(x: 0, y: h * (isBoss ? 0.06 : 0.10))
        portrait.name = tag
        card.addChild(portrait)

        // Opponent name
        let nameLabel = makeLabel(config.name, size: fs * 0.74, color: Parchment.deep)
        nameLabel.position = CGPoint(x: 0, y: -h * (isBoss ? 0.28 : 0.23))
        nameLabel.name = tag
        card.addChild(nameLabel)

        // Trait description
        let traitLabel = makeLabel(config.traitText, size: max(4, fs * 0.52),
                                   color: Parchment.muted)
        traitLabel.position = CGPoint(x: 0, y: -h * (isBoss ? 0.40 : 0.36))
        traitLabel.name = tag
        card.addChild(traitLabel)

        return card
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        for node in nodes(at: loc) {
            guard let name = node.name, name.hasPrefix("card_"),
                  let index = Int(name.dropFirst(5)) else { continue }
            commitSelection(index)
            return
        }
    }

    private func commitSelection(_ index: Int) {
        isUserInteractionEnabled = false
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.14),
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.run { [weak self] in
                self?.onSelected?(index)
                self?.removeFromParent()
            },
        ]))
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: fontName)
        l.fontSize = size
        l.fontColor = color
        l.text = text
        l.verticalAlignmentMode   = .center
        l.horizontalAlignmentMode = .center
        return l
    }
}
