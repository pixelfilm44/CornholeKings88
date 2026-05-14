import SpriteKit
import UIKit

// MARK: - Story Module Scene
// Full-screen pixel-art dialogue scene. Presents one StoryModule at a time.
// Supports typewriter text, tap-to-continue, multi-choice branching, mini-game
// launches, and map-spawn transitions.

final class StoryModuleScene: SKScene {

    // MARK: - State
    private var hasSetup = false
    private var queuedModuleID: String?         // set before launching a mini-game; read on return
    private var miniGameWinID: String?
    private var miniGameLoseID: String?
    private var currentModule: StoryModule?

    // MARK: - Panel sub-nodes (built once in buildPanel)
    private var panelNode: SKNode!
    private var imageNode: SKSpriteNode!
    private var titleLabel: SKLabelNode!
    private var textLabel: SKLabelNode!
    private var continueArrow: SKLabelNode!
    private var choiceContainer: SKNode!

    // MARK: - Layout
    private var W: CGFloat = 0
    private var H: CGFloat = 0
    private var panelW: CGFloat = 0
    private var panelH: CGFloat = 0
    private var imageAreaH: CGFloat = 0

    // MARK: - Typewriter
    private var fullText: String = ""
    private var isTypewriterDone = false
    private var canAdvance = false

    // MARK: - Audio (placeholder — wire up AVAudioPlayer here when assets are ready)
    // private var bgAudioPlayer: AVAudioPlayer?

    // MARK: - Entry
    /// Call this from MainMenuScene before presenting.
    func startAtCurrentProgress() {
        let id = StoryManager.shared.currentModuleID
        currentModule = StoryManager.shared.module(id: id)
    }

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width
        H = size.height
        backgroundColor = SKColor(red: 0.04, green: 0.04, blue: 0.14, alpha: 1)

        if hasSetup {
            // Returning from a mini-game — advance to queued module
            if let id = queuedModuleID {
                queuedModuleID = nil
                transitionToModule(id: id)
            }
            return
        }
        hasSetup = true
        buildPanel()
        buildBackButton()
        if let m = currentModule { showModule(m) }
    }

    // MARK: - Panel construction (one-time)
    private func buildPanel() {
        panelW = W * 0.88
        panelH = H * 0.82
        imageAreaH = panelH * 0.40

        panelNode = SKNode()
        panelNode.zPosition = 10
        addChild(panelNode)

        // Outer panel background
        let bg = SKShapeNode(
            rect: CGRect(x: -panelW/2, y: -panelH/2, width: panelW, height: panelH),
            cornerRadius: 2)
        bg.fillColor   = SKColor(red: 0.07, green: 0.07, blue: 0.22, alpha: 0.97)
        bg.strokeColor = SKColor(red: 0.78, green: 0.62, blue: 0.12, alpha: 1)
        bg.lineWidth   = 2
        panelNode.addChild(bg)

        // Inner highlight border (1px inset, subtler)
        let inner = SKShapeNode(
            rect: CGRect(x: -panelW/2 + 3, y: -panelH/2 + 3, width: panelW - 6, height: panelH - 6),
            cornerRadius: 1)
        inner.fillColor   = .clear
        inner.strokeColor = SKColor(red: 0.78, green: 0.62, blue: 0.12, alpha: 0.25)
        inner.lineWidth   = 1
        panelNode.addChild(inner)

        // Image placeholder node
        imageNode = SKSpriteNode(color: .clear, size: CGSize(width: panelW - 6, height: imageAreaH - 4))
        imageNode.position = CGPoint(x: 0, y: panelH/2 - imageAreaH/2 - 2)
        imageNode.zPosition = 1
        panelNode.addChild(imageNode)

        // Divider below image
        let divLine = SKShapeNode()
        let path = CGMutablePath()
        let divY = panelH/2 - imageAreaH - 2
        path.move(to: CGPoint(x: -panelW/2 + 6, y: divY))
        path.addLine(to: CGPoint(x: panelW/2 - 6, y: divY))
        divLine.path = path
        divLine.strokeColor = SKColor(red: 0.78, green: 0.62, blue: 0.12, alpha: 0.45)
        divLine.lineWidth = 1
        panelNode.addChild(divLine)

        // Title label — sits just below divider
        titleLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        titleLabel.fontSize = min(24, W / 13)
        titleLabel.fontColor = SKColor(red: 0.95, green: 0.82, blue: 0.10, alpha: 1)
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode   = .top
        titleLabel.position  = CGPoint(x: -panelW/2 + 10, y: divY - 4)
        titleLabel.zPosition = 5
        panelNode.addChild(titleLabel)

        // Body text label (multi-line, anchored top-left)
        let textY = divY - titleLabel.fontSize - 14
        textLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        textLabel.fontSize = min(18, W / 17)
        textLabel.fontColor = .white
        textLabel.numberOfLines = 0
        textLabel.preferredMaxLayoutWidth = panelW - 24
        textLabel.horizontalAlignmentMode = .left
        textLabel.verticalAlignmentMode   = .top
        textLabel.position  = CGPoint(x: -panelW/2 + 12, y: textY)
        textLabel.zPosition = 5
        panelNode.addChild(textLabel)

        // Continue arrow (blinking ▼)
        continueArrow = SKLabelNode(fontNamed: "PressStart2P-Regular")
        continueArrow.text      = "▼"
        continueArrow.fontSize  = min(21, W / 15)
        continueArrow.fontColor = SKColor(red: 0.95, green: 0.82, blue: 0.10, alpha: 1)
        continueArrow.horizontalAlignmentMode = .right
        continueArrow.verticalAlignmentMode   = .bottom
        continueArrow.position  = CGPoint(x: panelW/2 - 12, y: -panelH/2 + 20)
        continueArrow.zPosition = 5
        continueArrow.alpha     = 0
        continueArrow.run(.repeatForever(.sequence([
            .fadeIn(withDuration: 0.35),
            .wait(forDuration: 0.25),
            .fadeOut(withDuration: 0.35),
            .wait(forDuration: 0.15)
        ])))
        panelNode.addChild(continueArrow)

        // Choice button container
        choiceContainer          = SKNode()
        choiceContainer.position = CGPoint(x: 0, y: -panelH/2 + 28)
        choiceContainer.zPosition = 5
        panelNode.addChild(choiceContainer)
    }

    private func buildBackButton() {
        let font = "PressStart2P-Regular"
        let btn = SKLabelNode(fontNamed: font)
        btn.text     = "< MENU"
        btn.fontSize = min(18, W / 17)
        btn.fontColor = SKColor(white: 0.38, alpha: 1)
        btn.horizontalAlignmentMode = .left
        btn.verticalAlignmentMode   = .bottom
        btn.position  = CGPoint(x: -W/2 + 12, y: -H/2 + 10)
        btn.zPosition = 20
        btn.name      = "backToMenu"
        addChild(btn)
    }

    // MARK: - Show module
    private func showModule(_ m: StoryModule) {
        currentModule = m
        StoryManager.shared.currentModuleID = m.id
        isTypewriterDone = false
        canAdvance       = false

        // Image area
        titleLabel.text = m.title
        refreshImagePlaceholder(color: m.imageColor)

        // Reset text / choices
        textLabel.text = ""
        choiceContainer.removeAllChildren()
        continueArrow.alpha = 0

        fullText = m.text
        startTypewriter()
    }

    private func refreshImagePlaceholder(color: SKColor) {
        let sz  = imageNode.size
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: sz, format: fmt).image { ctx in
            let c = ctx.cgContext

            // Base color fill
            c.setFillColor(color.cgColor)
            c.fill(CGRect(origin: .zero, size: sz))

            // Subtle vignette edges
            c.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            let edgeW: CGFloat = 6
            c.fill(CGRect(x: 0, y: 0, width: sz.width, height: edgeW))
            c.fill(CGRect(x: 0, y: sz.height - edgeW, width: sz.width, height: edgeW))
            c.fill(CGRect(x: 0, y: 0, width: edgeW, height: sz.height))
            c.fill(CGRect(x: sz.width - edgeW, y: 0, width: edgeW, height: sz.height))

            // Pixel-art corner marks (bright)
            c.setFillColor(UIColor.white.withAlphaComponent(0.30).cgColor)
            let dot: CGFloat = 3
            c.fill(CGRect(x: 2, y: 2, width: dot, height: dot))
            c.fill(CGRect(x: sz.width - dot - 2, y: 2, width: dot, height: dot))
            c.fill(CGRect(x: 2, y: sz.height - dot - 2, width: dot, height: dot))
            c.fill(CGRect(x: sz.width - dot - 2, y: sz.height - dot - 2, width: dot, height: dot))

            // Placeholder label "[IMAGE]"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "PressStart2P-Regular", size: 7) ?? UIFont.systemFont(ofSize: 7),
                .foregroundColor: UIColor.white.withAlphaComponent(0.22)
            ]
            let str = "[IMAGE]" as NSString
            let strSz = str.size(withAttributes: attrs)
            str.draw(
                at: CGPoint(x: (sz.width - strSz.width) / 2, y: (sz.height - strSz.height) / 2),
                withAttributes: attrs)
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        imageNode.texture = tex
        imageNode.color   = .clear
        imageNode.colorBlendFactor = 0
    }

    // MARK: - Typewriter
    private func startTypewriter() {
        removeAction(forKey: "typewriter")
        let chars   = fullText
        let total   = chars.count
        guard total > 0 else { finishTypewriter(); return }

        var revealed = 0
        let action = SKAction.repeat(
            SKAction.sequence([
                SKAction.run { [weak self] in
                    guard let self = self else { return }
                    revealed += 1
                    let end = chars.index(chars.startIndex, offsetBy: min(revealed, total))
                    self.textLabel.text = String(chars[..<end])
                    if revealed >= total { self.finishTypewriter() }
                },
                SKAction.wait(forDuration: 0.045)
            ]),
            count: total
        )
        run(action, withKey: "typewriter")
    }

    private func skipTypewriter() {
        removeAction(forKey: "typewriter")
        finishTypewriter()
    }

    private func finishTypewriter() {
        guard !isTypewriterDone else { return }
        isTypewriterDone = true
        textLabel.text = fullText

        guard let m = currentModule else { return }
        if m.choices.isEmpty {
            canAdvance = true
            continueArrow.alpha = 1
        } else {
            showChoices(m.choices)
        }
    }

    // MARK: - Choice buttons
    private func showChoices(_ choices: [StoryChoice]) {
        choiceContainer.removeAllChildren()
        let font  = "PressStart2P-Regular"
        let btnH: CGFloat = min(44, H / 14)
        let btnW: CGFloat = choices.count > 1 ? panelW * 0.44 : panelW * 0.60
        let gap:  CGFloat = 10
        let totalW = CGFloat(choices.count) * btnW + CGFloat(choices.count - 1) * gap
        let startX = -totalW / 2 + btnW / 2

        for (i, choice) in choices.enumerated() {
            let container = SKNode()
            container.position = CGPoint(x: startX + CGFloat(i) * (btnW + gap), y: 0)
            container.name     = "choice_\(i)"

            let pill = SKShapeNode(
                rect: CGRect(x: -btnW/2, y: -btnH/2, width: btnW, height: btnH),
                cornerRadius: 4)
            pill.fillColor   = SKColor(white: 0.13, alpha: 0.95)
            pill.strokeColor = SKColor(red: 0.78, green: 0.62, blue: 0.12, alpha: 0.80)
            pill.lineWidth   = 1.5
            pill.name        = "choice_\(i)"
            container.addChild(pill)

            // Left accent bar
            let bar = SKShapeNode(
                rect: CGRect(x: -btnW/2, y: -btnH/2, width: 4, height: btnH),
                cornerRadius: 2)
            bar.fillColor   = SKColor(red: 0.78, green: 0.62, blue: 0.12, alpha: 0.9)
            bar.strokeColor = .clear
            bar.name        = "choice_\(i)"
            container.addChild(bar)

            let lbl = SKLabelNode(fontNamed: font)
            lbl.text      = choice.label
            lbl.fontSize  = min(15, W / 20)
            lbl.fontColor = SKColor(red: 0.95, green: 0.88, blue: 0.60, alpha: 1)
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode   = .center
            lbl.position = .zero
            lbl.name     = "choice_\(i)"
            container.addChild(lbl)

            choiceContainer.addChild(container)
        }
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc     = touch.location(in: self)
        let tapped  = atPoint(loc)
        let name    = tapped.name ?? tapped.parent?.name ?? tapped.parent?.parent?.name ?? ""

        if name == "backToMenu" {
            returnToMenu()
            return
        }

        if name.hasPrefix("choice_"), let idx = Int(name.dropFirst(7)) {
            guard let m = currentModule, idx < m.choices.count else { return }
            // Press animation
            let choiceNode = choiceContainer.childNode(withName: "choice_\(idx)")
            choiceNode?.run(.sequence([.scale(to: 0.92, duration: 0.07), .scale(to: 1.0, duration: 0.07)]))
            run(.wait(forDuration: 0.14)) { [weak self] in
                self?.handleOutcome(m.choices[idx].outcome)
            }
            return
        }

        // Tap anywhere else: skip typewriter or advance
        if !isTypewriterDone {
            skipTypewriter()
        } else if canAdvance, let m = currentModule {
            canAdvance = false
            continueArrow.alpha = 0
            handleOutcome(m.autoOutcome)
        }
    }

    // MARK: - Outcome routing
    private func handleOutcome(_ outcome: StoryOutcome) {
        switch outcome {

        case .nextModule(let id):
            transitionToModule(id: id)

        case .spawnOnMap(let x, let y):
            let ppSize = pixelPerfectSize() ?? size
            let gs = GameScene(size: ppSize)
            gs.storySpawnOverride = CGPoint(x: x, y: y)
            gs.scaleMode = .resizeFill
            let t = SKTransition.fade(withDuration: 0.60)
            t.pausesOutgoingScene = false
            view?.presentScene(gs, transition: t)

        case .miniGame(let type, let winID, let loseID):
            miniGameWinID  = winID
            miniGameLoseID = loseID
            launchMiniGame(type)

        case .returnToMenu:
            returnToMenu()
        }
    }

    private func transitionToModule(id: String) {
        guard let next = StoryManager.shared.module(id: id) else {
            returnToMenu()
            return
        }
        // Cross-fade the panel contents
        panelNode.run(.sequence([
            .fadeOut(withDuration: 0.18),
            .run { [weak self] in self?.showModule(next) },
            .fadeIn(withDuration: 0.18)
        ]))
    }

    // MARK: - Mini-game launch
    private func launchMiniGame(_ type: StoryMiniGame) {
        let ppSize = pixelPerfectSize() ?? size

        let handleResult: (Bool) -> Void = { [weak self] won in
            guard let self = self else { return }
            self.queuedModuleID = won ? self.miniGameWinID : self.miniGameLoseID
        }

        switch type {
        case .cornhole:
            let s = CornholeMiniGameScene(size: ppSize)
            s.previousScene    = self
            s.scaleMode        = .resizeFill
            s.availableHoneyBags = 0
            s.onComplete       = handleResult
            push(to: s)

        case .baseball:
            let s = CornholeBaseballScene(size: ppSize)
            s.previousScene = self
            s.scaleMode     = .resizeFill
            s.onComplete    = handleResult
            push(to: s)

        case .beehive:
            let s = BeeHiveScene(size: ppSize)
            s.previousScene  = self
            s.scaleMode      = .resizeFill
            s.startingHearts = 3
            s.onComplete     = handleResult
            push(to: s)

        case .bike:
            // Bike uses a UIViewController modal; treat it as a win for story flow
            queuedModuleID = miniGameWinID
            returnToMenu()
        }
    }

    // MARK: - Navigation helpers
    private func returnToMenu() {
        guard let view = self.view else { return }
        let menu = MainMenuScene(size: view.bounds.size)
        menu.scaleMode   = .resizeFill
        menu.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let t = SKTransition.push(with: .down, duration: 0.35)
        t.pausesOutgoingScene = false
        view.presentScene(menu, transition: t)
    }

    private func push(to scene: SKScene) {
        let t = SKTransition.push(with: .up, duration: 0.35)
        t.pausesOutgoingScene = false
        view?.presentScene(scene, transition: t)
    }

    private func pixelPerfectSize() -> CGSize? {
        guard let v = self.view else { return nil }
        let scale  = v.contentScaleFactor
        let pixelW = v.bounds.width  * scale
        let pixelH = v.bounds.height * scale
        let n = max(2, min(floor(pixelW / 160), floor(pixelH / 120)))
        return CGSize(width: floor(pixelW / n), height: floor(pixelH / n))
    }
}
