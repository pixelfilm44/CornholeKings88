import SpriteKit

/// Full-screen store overlay anchored to the camera. Three item cards;
/// each card's buy button is tappable while the player has enough coins.
/// Routes purchases through the provided closures so GameScene owns the
/// inventory/manager mutations.
final class StoreModalNode: SKNode {

    struct Callbacks {
        let coinBalance: () -> Int
        let buyBeanbags: () -> Bool   // returns true on success
        let buyPowerJuice: () -> Bool
        let buyGauntlet:  () -> Bool
        let buyCannonball: () -> Bool
        let close:        () -> Void
        let gauntletOwned: () -> Bool
    }

    private let sceneSize: CGSize
    private let callbacks: Callbacks
    private var coinLabel: SKLabelNode!
    private var cards: [SKNode] = []

    init(sceneSize: CGSize, callbacks: Callbacks) {
        self.sceneSize = sceneSize
        self.callbacks = callbacks
        super.init()
        zPosition = 30_000
        // GameScene's touchesBegan routes taps into handleTap(at:) — don't
        // intercept them here, or they never bubble up to the scene.
        build()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func build() {
        let W = sceneSize.width, H = sceneSize.height

        // Dim backdrop covering the whole screen; swallows taps outside cards.
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.78),
                               size: CGSize(width: W, height: H))
        dim.zPosition = 0
        dim.name = "storeBackdrop"
        addChild(dim)

        // Panel
        let panelW: CGFloat = min(W - 32, 340)
        let panelH: CGFloat = min(H - 96, 432)
        let panel = SKShapeNode(rect: CGRect(x: -panelW/2, y: -panelH/2, width: panelW, height: panelH),
                                cornerRadius: 8)
        panel.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.98)
        panel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.85)
        panel.lineWidth   = 2
        panel.zPosition   = 1
        addChild(panel)

        // Title
        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "STORE"
        title.fontSize  = 18
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.position  = CGPoint(x: 0, y: panelH/2 - 26)
        title.zPosition = 2
        addChild(title)

        // Coin balance
        let coin = SKLabelNode(fontNamed: "PressStart2P-Regular")
        coin.fontSize  = 10
        coin.fontColor = SKColor(red: 0.95, green: 0.82, blue: 0.30, alpha: 1)
        coin.position  = CGPoint(x: 0, y: panelH/2 - 46)
        coin.zPosition = 2
        addChild(coin)
        coinLabel = coin
        refreshCoinLabel()

        // Cards
        let cardW = panelW - 32
        let cardH: CGFloat = 64
        let topY = panelH/2 - 70
        let spacing: CGFloat = 8

        let bagCard = makeCard(title: "5 BEAN BAGS",
                               subtitle: "throw at enemies",
                               price: 10,
                               buttonName: "buyBags",
                               width: cardW, height: cardH)
        bagCard.position = CGPoint(x: 0, y: topY - cardH/2)
        addChild(bagCard); cards.append(bagCard)

        let juiceCard = makeCard(title: "POWER JUICE",
                                 subtitle: "refill all hearts",
                                 price: 10,
                                 buttonName: "buyJuice",
                                 width: cardW, height: cardH)
        juiceCard.position = CGPoint(x: 0, y: topY - cardH*1.5 - spacing)
        addChild(juiceCard); cards.append(juiceCard)

        let gauntletCard = makeCard(title: "GAUNTLET",
                                    subtitle: "slows cornhole aim",
                                    price: 30,
                                    buttonName: "buyGauntlet",
                                    width: cardW, height: cardH)
        gauntletCard.position = CGPoint(x: 0, y: topY - cardH*2.5 - spacing*2)
        addChild(gauntletCard); cards.append(gauntletCard)

        let cannonCard = makeCard(title: "CANNONBALL",
                                   subtitle: "sphere / punches holes",
                                   price: 20,
                                   buttonName: "buyCannonball",
                                   width: cardW, height: cardH)
        cannonCard.position = CGPoint(x: 0, y: topY - cardH*3.5 - spacing*3)
        addChild(cannonCard); cards.append(cannonCard)

        // Close button — generous tap target so the X is easy to hit.
        let closeBtn = SKShapeNode(rect: CGRect(x: -22, y: -22, width: 44, height: 44),
                                   cornerRadius: 6)
        closeBtn.fillColor   = SKColor(red: 0.20, green: 0.10, blue: 0.05, alpha: 0.9)
        closeBtn.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.85)
        closeBtn.lineWidth   = 1.5
        closeBtn.position    = CGPoint(x: panelW/2 - 24, y: panelH/2 - 24)
        closeBtn.zPosition   = 3
        closeBtn.name        = "storeClose"
        addChild(closeBtn)

        let closeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        closeLbl.text = "X"
        closeLbl.fontSize  = 14
        closeLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        closeLbl.verticalAlignmentMode   = .center
        closeLbl.horizontalAlignmentMode = .center
        closeLbl.zPosition = 1
        closeLbl.name = "storeClose"
        closeBtn.addChild(closeLbl)

        refreshCardStates()
    }

    private func makeCard(title: String,
                          subtitle: String,
                          price: Int,
                          buttonName: String,
                          width: CGFloat,
                          height: CGFloat) -> SKNode {
        let card = SKNode()
        card.zPosition = 2

        let bg = SKShapeNode(rect: CGRect(x: -width/2, y: -height/2, width: width, height: height),
                             cornerRadius: 4)
        bg.fillColor   = SKColor(red: 0.16, green: 0.09, blue: 0.05, alpha: 1)
        bg.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 0.9)
        bg.lineWidth   = 1.5
        bg.zPosition   = 0
        card.addChild(bg)

        let nameLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        nameLbl.text = title
        nameLbl.fontSize  = 10
        nameLbl.fontColor = SKColor(red: 0.95, green: 0.86, blue: 0.40, alpha: 1)
        nameLbl.horizontalAlignmentMode = .left
        nameLbl.verticalAlignmentMode   = .center
        nameLbl.position = CGPoint(x: -width/2 + 10, y: 10)
        nameLbl.zPosition = 1
        card.addChild(nameLbl)

        let subLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        subLbl.text = subtitle
        subLbl.fontSize  = 6
        subLbl.fontColor = SKColor(white: 0.78, alpha: 1)
        subLbl.horizontalAlignmentMode = .left
        subLbl.verticalAlignmentMode   = .center
        subLbl.position = CGPoint(x: -width/2 + 10, y: -8)
        subLbl.zPosition = 1
        card.addChild(subLbl)

        // Buy button on the right
        let btnW: CGFloat = 78, btnH: CGFloat = 36
        let btn = SKShapeNode(rect: CGRect(x: -btnW/2, y: -btnH/2, width: btnW, height: btnH),
                              cornerRadius: 6)
        btn.fillColor   = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.20)
        btn.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.85)
        btn.lineWidth   = 1.5
        btn.position    = CGPoint(x: width/2 - btnW/2 - 8, y: 0)
        btn.zPosition   = 1
        btn.name        = buttonName
        card.addChild(btn)

        let priceLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        priceLbl.text = "\(price)c"
        priceLbl.fontSize  = 11
        priceLbl.fontColor = SKColor(red: 0.95, green: 0.82, blue: 0.30, alpha: 1)
        priceLbl.verticalAlignmentMode   = .center
        priceLbl.horizontalAlignmentMode = .center
        priceLbl.zPosition = 2
        priceLbl.name = buttonName
        btn.addChild(priceLbl)

        return card
    }

    private func refreshCoinLabel() {
        coinLabel.text = "COINS: \(callbacks.coinBalance())"
    }

    func refreshCardStates() {
        refreshCoinLabel()
        let coins = callbacks.coinBalance()
        let gauntletOwned = callbacks.gauntletOwned()

        let items: [(String, Int, Bool)] = [
            ("buyBags",       10, true),
            ("buyJuice",      10, true),
            ("buyGauntlet",   30, !gauntletOwned),
            ("buyCannonball", 20, true),
        ]
        for (name, price, available) in items {
            guard let btn = childButton(named: name) else { continue }
            let affordable = coins >= price && available
            btn.alpha = affordable ? 1.0 : 0.4

            if name == "buyGauntlet", !available,
               let lbl = btn.children.compactMap({ $0 as? SKLabelNode }).first {
                lbl.text = "OWNED"
            }
        }
    }

    private func childButton(named name: String) -> SKShapeNode? {
        for card in cards {
            if let btn = card.childNode(withName: name) as? SKShapeNode {
                return btn
            }
        }
        return nil
    }

    /// Public hit-test from GameScene's `touchesBegan` routing.
    /// `locationInSelf` is in this node's own coordinate space.
    func handleTap(at locationInSelf: CGPoint) {
        let candidates = nodes(at: locationInSelf)
        for n in candidates {
            var cursor: SKNode? = n
            while let cur = cursor {
                switch cur.name {
                case "storeClose":
                    callbacks.close()
                    return
                case "storeBackdrop":
                    // Block taps that fall on the backdrop (no-op).
                    return
                case "buyBags":
                    if callbacks.buyBeanbags() { flash(buttonNamed: "buyBags") }
                    refreshCardStates()
                    return
                case "buyJuice":
                    if callbacks.buyPowerJuice() { flash(buttonNamed: "buyJuice") }
                    refreshCardStates()
                    return
                case "buyGauntlet":
                    if callbacks.buyGauntlet() { flash(buttonNamed: "buyGauntlet") }
                    refreshCardStates()
                    return
                case "buyCannonball":
                    if callbacks.buyCannonball() { flash(buttonNamed: "buyCannonball") }
                    refreshCardStates()
                    return
                default:
                    cursor = cur.parent
                }
            }
        }
    }

    private func flash(buttonNamed name: String) {
        guard let btn = childButton(named: name) else { return }
        btn.removeAction(forKey: "flash")
        btn.run(.sequence([
            .scale(to: 1.10, duration: 0.06),
            .scale(to: 1.00, duration: 0.10),
        ]), withKey: "flash")
    }
}
