import SpriteKit

/// Bit-Wood tuning screen for the two named baseball opponents (Tom & Jen).
/// Reached from `SettingsScene` via the "BASEBALL AI" card. Each character has
/// four −/+ steppers (hit %, power, pitch speed, run speed) backed by
/// `BaseballAISettings`. Changes persist immediately.
final class BaseballTuningScene: SKScene {

    // Bit-Wood Brawler palette
    private let dsPrimary = SKColor(red: 0x1a/255.0, green: 0x0a/255.0, blue: 0x04/255.0, alpha: 1)
    private let dsGold    = SKColor(red: 0xf0/255.0, green: 0xc0/255.0, blue: 0x60/255.0, alpha: 1)
    private let dsIron    = SKColor(red: 0x59/255.0, green: 0x59/255.0, blue: 0x59/255.0, alpha: 1)

    private let settings = BaseballAISettings.shared

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.02, green: 0.04, blue: 0.02, alpha: 1)
        buildUI()
    }

    private func buildUI() {
        removeAllChildren()
        let W = size.width, H = size.height

        // ===== Top ribbon =====
        let topInset  = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let ribbonBottomY = H / 2 - totalTopH

        let bar = SKSpriteNode(color: dsPrimary, size: CGSize(width: W, height: totalTopH))
        bar.position = CGPoint(x: 0, y: H / 2 - totalTopH / 2)
        bar.zPosition = 10
        addChild(bar)

        let border = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        border.position = CGPoint(x: 0, y: ribbonBottomY + 1)
        border.zPosition = 11
        addChild(border)

        let contentY = H / 2 - topInset - topH / 2

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "BASEBALL AI"
        title.fontSize = 8
        title.fontColor = dsGold
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: contentY)
        title.zPosition = 12
        addChild(title)

        let back = SKLabelNode(fontNamed: "PressStart2P-Regular")
        back.text = "BACK"
        back.fontSize = 8
        back.fontColor = dsGold
        back.verticalAlignmentMode = .center
        back.horizontalAlignmentMode = .right
        back.name = "back"
        back.position = CGPoint(x: W / 2 - 16, y: contentY)
        back.zPosition = 12
        addChild(back)

        // ===== Column headers (TOM | JEN) =====
        let tomX = -W * 0.20
        let jenX =  W * 0.24
        let labelX = -W / 2 + 14
        let headerY = ribbonBottomY - 40

        for (c, x) in [(BaseballAISettings.Character.tom, tomX), (.jen, jenX)] {
            let h = SKLabelNode(fontNamed: "PressStart2P-Regular")
            h.text = c.displayName
            h.fontSize = min(13, W / 24)
            h.fontColor = dsGold
            h.verticalAlignmentMode = .center
            h.horizontalAlignmentMode = .center
            h.position = CGPoint(x: x, y: headerY)
            addChild(h)
        }

        // ===== Stat rows =====
        let stats = BaseballAISettings.Stat.allCases
        let rowGap = min(H * 0.11, 62)
        let firstRowY = headerY - rowGap

        for (i, stat) in stats.enumerated() {
            let y = firstRowY - CGFloat(i) * rowGap

            let rowLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
            rowLabel.text = stat.label
            rowLabel.fontSize = min(9, W / 34)
            rowLabel.fontColor = .white
            rowLabel.verticalAlignmentMode = .center
            rowLabel.horizontalAlignmentMode = .left
            rowLabel.position = CGPoint(x: labelX, y: y)
            addChild(rowLabel)

            addStepper(character: .tom, stat: stat, centerX: tomX, y: y)
            addStepper(character: .jen, stat: stat, centerX: jenX, y: y)
        }

        // ===== Footer =====
        let footerY = firstRowY - CGFloat(stats.count) * rowGap - rowGap * 0.4

        let resetBtn = makeWideButton(label: "RESET DEFAULTS", name: "resetBaseball",
                                      size: CGSize(width: min(W - 60, 260), height: 32))
        resetBtn.position = CGPoint(x: 0, y: max(footerY, -H / 2 + 70))
        addChild(resetBtn)

        let hint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        hint.text = "100% = DEFAULT DIFFICULTY"
        hint.fontSize = min(7, W / 44)
        hint.fontColor = SKColor(white: 0.45, alpha: 1)
        hint.verticalAlignmentMode = .center
        hint.horizontalAlignmentMode = .center
        hint.position = CGPoint(x: 0, y: -H / 2 + 34)
        addChild(hint)
    }

    // MARK: - Stepper widget

    private func addStepper(character: BaseballAISettings.Character,
                            stat: BaseballAISettings.Stat,
                            centerX: CGFloat, y: CGFloat) {
        let minus = makeMiniButton(symbol: "-",
                                   name: "tune_\(character.rawValue)_\(stat.rawValue)_minus")
        minus.position = CGPoint(x: centerX - 38, y: y)
        addChild(minus)

        let val = SKLabelNode(fontNamed: "PressStart2P-Regular")
        val.text = "\(settings.percent(character, stat))%"
        val.fontSize = min(10, size.width / 30)
        val.fontColor = dsGold
        val.verticalAlignmentMode = .center
        val.horizontalAlignmentMode = .center
        val.name = "val_\(character.rawValue)_\(stat.rawValue)"
        val.position = CGPoint(x: centerX, y: y)
        addChild(val)

        let plus = makeMiniButton(symbol: "+",
                                  name: "tune_\(character.rawValue)_\(stat.rawValue)_plus")
        plus.position = CGPoint(x: centerX + 38, y: y)
        addChild(plus)
    }

    private func makeMiniButton(symbol: String, name: String) -> SKNode {
        let container = SKNode()
        container.name = name
        let bg = SKSpriteNode(color: dsGold, size: CGSize(width: 26, height: 26))
        bg.name = name
        bg.zPosition = 1
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = symbol
        lbl.fontSize = 14
        lbl.fontColor = dsPrimary
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        lbl.name = name
        lbl.zPosition = 2
        container.addChild(bg)
        container.addChild(lbl)
        return container
    }

    private func makeWideButton(label: String, name: String, size: CGSize) -> SKNode {
        let container = SKNode()
        container.name = name
        let bg = SKSpriteNode(color: dsIron, size: size)
        bg.name = name
        bg.zPosition = 1
        let bd = SKSpriteNode(color: dsGold, size: CGSize(width: size.width, height: 2))
        bd.position = CGPoint(x: 0, y: size.height / 2 - 1)
        bd.zPosition = 2
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = label
        lbl.fontSize = min(10, size.width / 18)
        lbl.fontColor = dsGold
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        lbl.name = name
        lbl.zPosition = 3
        container.addChild(bg)
        container.addChild(bd)
        container.addChild(lbl)
        return container
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        for node in nodes(at: loc) {
            guard let name = node.name else { continue }
            if name == "back" { goBack(); return }
            if name == "resetBaseball" { resetAll(); return }
            if name.hasPrefix("tune_") { handleStepper(name); return }
        }
    }

    /// Parses "tune_<character>_<stat>_<dir>" and applies the change.
    private func handleStepper(_ name: String) {
        let parts = name.split(separator: "_")
        guard parts.count == 4,
              let character = BaseballAISettings.Character(rawValue: String(parts[1])),
              let stat = BaseballAISettings.Stat(rawValue: String(parts[2]))
        else { return }

        let delta = parts[3] == "plus" ? settings.step : -settings.step
        let newPct = settings.adjust(character, stat, by: delta)
        updateValueLabel(character, stat, percent: newPct)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func resetAll() {
        settings.reset()
        for c in BaseballAISettings.Character.allCases {
            for s in BaseballAISettings.Stat.allCases {
                updateValueLabel(c, s, percent: settings.percent(c, s))
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateValueLabel(_ c: BaseballAISettings.Character,
                                  _ s: BaseballAISettings.Stat, percent: Int) {
        let label = childNode(withName: "val_\(c.rawValue)_\(s.rawValue)") as? SKLabelNode
        label?.text = "\(percent)%"
    }

    private func goBack() {
        let scene = SettingsScene(size: size)
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: SKTransition.push(with: .right, duration: 0.3))
    }
}
