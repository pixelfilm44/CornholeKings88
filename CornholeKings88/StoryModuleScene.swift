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
    private var imageFrameOverlay: SKSpriteNode!
    private var titleLabel: SKLabelNode!
    private var textLabel: SKLabelNode!
    private var textClipNode: SKCropNode!
    private var textScrollNode: SKNode!
    private var scrollUpBtn: SKNode!
    private var scrollDownBtn: SKNode!
    private var continueArrow: SKLabelNode!
    private var choiceContainer: SKNode!

    // MARK: - Layout
    private var W: CGFloat = 0
    private var H: CGFloat = 0
    private var panelW: CGFloat = 0
    private var panelH: CGFloat = 0
    private var imageAreaH: CGFloat = 0
    private var ribbonBottomY: CGFloat = 0   // scene-Y of bottom edge of the top ribbon

    // MARK: - Title (wraps up to 2 lines; shrinks to fit long titles within that budget)
    private var titleBaseFontSize: CGFloat = 0
    private var titleViewportH: CGFloat = 0

    // MARK: - Text scroll (body text can exceed the panel's fixed vertical space)
    private var textViewportH: CGFloat = 0
    private var maxTextScroll: CGFloat = 0
    private var currentTextScroll: CGFloat = 0

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
        backgroundColor = Parchment.bg

        if hasSetup {
            // Returning from a mini-game — advance to queued module
            if let id = queuedModuleID {
                queuedModuleID = nil
                transitionToModule(id: id)
            }
            return
        }
        hasSetup = true
        buildTopBar()   // sets ribbonBottomY first so buildPanel can position below it
        buildPanel()
        addCrtOverlay()
        if let m = currentModule { showModule(m) }
    }

    // MARK: - Panel construction (one-time)
    private func buildPanel() {
        panelW = W * 0.88
        // Fill the space between ribbon bottom and screen bottom (8pt gap each side)
        let availableH = ribbonBottomY + H / 2 - 16
        panelH = min(H * 0.82, availableH)
        imageAreaH = panelH * 0.40

        panelNode = SKNode()
        // Center the panel in the available space below the ribbon
        panelNode.position = CGPoint(x: 0, y: ribbonBottomY - 8 - panelH / 2)
        panelNode.zPosition = 10
        addChild(panelNode)

        // Outer panel background
        let bg = SKShapeNode(
            rect: CGRect(x: -panelW/2, y: -panelH/2, width: panelW, height: panelH),
            cornerRadius: 2)
        bg.fillColor   = Parchment.paper.withAlphaComponent(0.97)
        bg.strokeColor = Parchment.edge
        bg.lineWidth   = 2
        panelNode.addChild(bg)

        // Inner highlight border (1px inset, subtler)
        let inner = SKShapeNode(
            rect: CGRect(x: -panelW/2 + 3, y: -panelH/2 + 3, width: panelW - 6, height: panelH - 6),
            cornerRadius: 1)
        inner.fillColor   = .clear
        inner.strokeColor = Parchment.edge.withAlphaComponent(0.25)
        inner.lineWidth   = 1
        panelNode.addChild(inner)

        // Image placeholder node
        imageNode = SKSpriteNode(color: .clear, size: CGSize(width: panelW - 6, height: imageAreaH - 4))
        imageNode.position = CGPoint(x: 0, y: panelH/2 - imageAreaH/2 - 2)
        imageNode.zPosition = 1
        panelNode.addChild(imageNode)

        // Frame overlay (vignette + corner marks) drawn once, shown only over real photos —
        // the placeholder path bakes its own vignette directly into imageNode's texture.
        imageFrameOverlay = SKSpriteNode(texture: makeFrameOverlayTexture(size: imageNode.size),
                                          size: imageNode.size)
        imageFrameOverlay.position = imageNode.position
        imageFrameOverlay.zPosition = 2
        imageFrameOverlay.alpha = 0
        panelNode.addChild(imageFrameOverlay)

        // Corner rivets on image frame (matches design Scene plate style)
        let rivetRadius: CGFloat = 3.5
        let imgTop  = panelH/2 - 2
        let imgLeft = -panelW/2 + 2
        for (dx, dy) in [(imgLeft + 6, imgTop - 6),
                         (-imgLeft - 6, imgTop - 6),
                         (imgLeft + 6, imgTop - imageAreaH + 6),
                         (-imgLeft - 6, imgTop - imageAreaH + 6)] {
            addPanelRivet(at: CGPoint(x: dx, y: dy), radius: rivetRadius)
        }

        // Divider below image
        let divLine = SKShapeNode()
        let path = CGMutablePath()
        let divY = panelH/2 - imageAreaH - 2
        path.move(to: CGPoint(x: -panelW/2 + 6, y: divY))
        path.addLine(to: CGPoint(x: panelW/2 - 6, y: divY))
        divLine.path = path
        divLine.strokeColor = Parchment.edge.withAlphaComponent(0.45)
        divLine.lineWidth = 1
        panelNode.addChild(divLine)

        // Title label — sits just below divider. Wraps up to 2 lines; showModule()
        // shrinks the font further for the rare title that still doesn't fit that,
        // so a long title is never clipped or run off the panel edge.
        titleBaseFontSize = min(24, W / 13)
        let titleLineH = titleBaseFontSize * 1.3
        titleViewportH = titleLineH * 2

        titleLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        titleLabel.fontSize = titleBaseFontSize
        titleLabel.fontColor = Parchment.deep
        titleLabel.numberOfLines = 0
        titleLabel.preferredMaxLayoutWidth = panelW - 20
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode   = .top
        titleLabel.position  = CGPoint(x: -panelW/2 + 10, y: divY - 4)
        titleLabel.zPosition = 5
        panelNode.addChild(titleLabel)

        // Body text label (multi-line, anchored top-left), clipped to a fixed viewport
        // so long modules never bleed into the choice/continue controls below —
        // overflow is reached instead via the scroll arrows built below. The title
        // area above always reserves 2 lines, whether or not the current title needs it.
        let textY = divY - 4 - titleViewportH - 10
        let controlsReserve: CGFloat = 56   // clears the choice-button row / continue arrow
        let textBottomLimit = -panelH/2 + controlsReserve
        textViewportH = max(40, textY - textBottomLimit)
        let maskCenterY = textY - textViewportH / 2

        textClipNode = SKCropNode()
        textClipNode.zPosition = 5
        panelNode.addChild(textClipNode)

        let mask = SKSpriteNode(color: .white, size: CGSize(width: panelW - 6, height: textViewportH))
        mask.position = CGPoint(x: 0, y: maskCenterY)
        textClipNode.maskNode = mask

        textScrollNode = SKNode()
        textClipNode.addChild(textScrollNode)

        textLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        textLabel.fontSize = min(14, W / 17)
        textLabel.fontColor = Parchment.ink
        textLabel.numberOfLines = 0
        textLabel.preferredMaxLayoutWidth = panelW - 24
        textLabel.horizontalAlignmentMode = .left
        textLabel.verticalAlignmentMode   = .top
        textLabel.position  = CGPoint(x: -panelW/2 + 12, y: textY)
        textScrollNode.addChild(textLabel)

        // Scroll arrows — a fixed, always-in-the-same-place widget on the text area's
        // right edge. Hidden when the module's text fits; shown (and individually
        // dimmed at each end) whenever it doesn't.
        scrollUpBtn = makeScrollArrowButton(text: "▲", name: "scrollUp")
        scrollUpBtn.position = CGPoint(x: panelW/2 - 16, y: maskCenterY + 20)
        scrollUpBtn.zPosition = 6
        scrollUpBtn.alpha = 0
        panelNode.addChild(scrollUpBtn)

        scrollDownBtn = makeScrollArrowButton(text: "▼", name: "scrollDown")
        scrollDownBtn.position = CGPoint(x: panelW/2 - 16, y: maskCenterY - 20)
        scrollDownBtn.zPosition = 6
        scrollDownBtn.alpha = 0
        panelNode.addChild(scrollDownBtn)

        // Continue arrow (blinking ▼)
        continueArrow = SKLabelNode(fontNamed: "PressStart2P-Regular")
        continueArrow.text      = "▼"
        continueArrow.fontSize  = min(21, W / 15)
        continueArrow.fontColor = Parchment.amber
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

    /// Top ribbon — parchment paper + ink edge border, safe-area aware.
    /// Sets ribbonBottomY so buildPanel() can position below it.
    private func buildTopBar() {
        let dsPrimary = Parchment.paper
        let dsGold    = Parchment.edge

        let topInset  = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let topBarY   = H / 2 - totalTopH / 2
        let contentY  = H / 2 - topInset - topH / 2
        ribbonBottomY = H / 2 - totalTopH

        // Background bar (extends through notch)
        let bar = SKSpriteNode(color: dsPrimary, size: CGSize(width: W, height: totalTopH))
        bar.position  = CGPoint(x: 0, y: topBarY)
        bar.zPosition = 18
        addChild(bar)

        // 2px gold bottom border
        let border = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        border.position  = CGPoint(x: 0, y: ribbonBottomY + 1)
        border.zPosition = 19
        addChild(border)

        // Zone C (right): close icon — exits to main menu
        let closeNode = SKSpriteNode(imageNamed: "closeIcon")
        closeNode.size = CGSize(width: 22, height: 22)
        closeNode.texture?.filteringMode = .nearest
        closeNode.position  = CGPoint(x: W / 2 - 22, y: contentY)
        closeNode.name      = "backToMenu"
        closeNode.zPosition = 22
        addChild(closeNode)
    }

    private func addPanelRivet(at pos: CGPoint, radius: CGFloat) {
        let r = SKShapeNode(circleOfRadius: radius)
        r.fillColor   = Parchment.muted
        r.strokeColor = Parchment.edge
        r.lineWidth   = 0.5
        r.position    = pos
        r.zPosition   = 6
        panelNode.addChild(r)
    }

    private func makeScrollArrowButton(text: String, name: String) -> SKNode {
        let container = SKNode()
        container.name = name

        let bg = SKShapeNode(circleOfRadius: 11)
        bg.fillColor   = Parchment.surface2.withAlphaComponent(0.92)
        bg.strokeColor = Parchment.edge.withAlphaComponent(0.75)
        bg.lineWidth   = 1
        bg.name        = name
        container.addChild(bg)

        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text      = text
        lbl.fontSize  = 10
        lbl.fontColor = Parchment.amber
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode   = .center
        lbl.position  = CGPoint(x: 0, y: -1)
        lbl.name      = name
        container.addChild(lbl)

        return container
    }

    // MARK: - Text scroll
    /// Recomputes overflow and dims/hides the scroll arrows to match. Call after
    /// the body text or the scroll offset changes.
    private func updateScrollUI() {
        let contentH = textLabel.frame.height
        maxTextScroll = max(0, contentH - textViewportH)
        let hasOverflow = maxTextScroll > 1
        scrollUpBtn.alpha   = hasOverflow ? (currentTextScroll > 1 ? 1.0 : 0.35) : 0
        scrollDownBtn.alpha = hasOverflow ? (currentTextScroll < maxTextScroll - 1 ? 1.0 : 0.35) : 0
    }

    /// While the typewriter is revealing characters, keep the newest line in view —
    /// same idea as a terminal auto-scrolling to the latest output.
    private func autoScrollToBottomIfNeeded() {
        let contentH = textLabel.frame.height
        maxTextScroll = max(0, contentH - textViewportH)
        currentTextScroll = maxTextScroll
        textScrollNode.position.y = currentTextScroll
        updateScrollUI()
    }

    private func scrollText(direction: CGFloat) {
        guard maxTextScroll > 0 else { return }
        let pageStep = textViewportH * 0.85
        currentTextScroll = min(maxTextScroll, max(0, currentTextScroll + direction * pageStep))
        textScrollNode.position.y = currentTextScroll
        updateScrollUI()
    }

    // MARK: - Show module
    private func showModule(_ m: StoryModule) {
        currentModule = m
        StoryManager.shared.currentModuleID = m.id
        isTypewriterDone = false
        canAdvance       = false

        // Title — reset to base size, then shrink in whole-point steps until the
        // (already-wrapping) label's rendered height fits the reserved 2-line budget.
        titleLabel.fontSize = titleBaseFontSize
        titleLabel.text = m.title
        while titleLabel.frame.height > titleViewportH && titleLabel.fontSize > 10 {
            titleLabel.fontSize -= 1
        }

        // Image area
        if let name = m.imageName, let tex = croppedImageTexture(named: name) {
            imageNode.texture = tex
            imageNode.color = .clear
            imageNode.colorBlendFactor = 0
            imageFrameOverlay.alpha = 1
        } else {
            refreshImagePlaceholder(color: m.imageColor)
            imageFrameOverlay.alpha = 0
        }

        // Reset text / choices
        textLabel.text = ""
        choiceContainer.removeAllChildren()
        continueArrow.alpha = 0
        currentTextScroll = 0
        textScrollNode.position.y = 0
        updateScrollUI()

        fullText = m.text
        startTypewriter()
    }

    /// Aspect-fill crop of a bundled scene/portrait image to exactly match imageNode's
    /// frame, so wide reference photos never stretch or letterbox inside the panel.
    private func croppedImageTexture(named name: String) -> SKTexture? {
        guard let ui = UIImage(named: name) else { return nil }
        let base = SKTexture(image: ui)
        base.filteringMode = .linear
        let targetAspect = imageNode.size.width / imageNode.size.height
        let texSize = base.size()
        let texAspect = texSize.width / texSize.height

        var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        if texAspect > targetAspect {
            let cropW = targetAspect / texAspect
            rect = CGRect(x: (1 - cropW) / 2, y: 0, width: cropW, height: 1)
        } else if texAspect < targetAspect {
            let cropH = texAspect / targetAspect
            rect = CGRect(x: 0, y: (1 - cropH) / 2, width: 1, height: cropH)
        }
        let cropped = SKTexture(rect: rect, in: base)
        cropped.filteringMode = .linear
        return cropped
    }

    /// Static vignette + corner-mark overlay, drawn once and reused for every real photo
    /// (mirrors the framing baked into the color placeholder, minus the "[IMAGE]" label).
    private func makeFrameOverlayTexture(size sz: CGSize) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: sz, format: fmt).image { ctx in
            let c = ctx.cgContext

            c.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            let edgeW: CGFloat = 6
            c.fill(CGRect(x: 0, y: 0, width: sz.width, height: edgeW))
            c.fill(CGRect(x: 0, y: sz.height - edgeW, width: sz.width, height: edgeW))
            c.fill(CGRect(x: 0, y: 0, width: edgeW, height: sz.height))
            c.fill(CGRect(x: sz.width - edgeW, y: 0, width: edgeW, height: sz.height))

            c.setFillColor(UIColor.white.withAlphaComponent(0.30).cgColor)
            let dot: CGFloat = 3
            c.fill(CGRect(x: 2, y: 2, width: dot, height: dot))
            c.fill(CGRect(x: sz.width - dot - 2, y: 2, width: dot, height: dot))
            c.fill(CGRect(x: 2, y: sz.height - dot - 2, width: dot, height: dot))
            c.fill(CGRect(x: sz.width - dot - 2, y: sz.height - dot - 2, width: dot, height: dot))
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
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
                    self.autoScrollToBottomIfNeeded()
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
        autoScrollToBottomIfNeeded()

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
            pill.fillColor   = Parchment.surface2.withAlphaComponent(0.95)
            pill.strokeColor = Parchment.edge.withAlphaComponent(0.80)
            pill.lineWidth   = 1.5
            pill.name        = "choice_\(i)"
            container.addChild(pill)

            // Left accent bar
            let bar = SKShapeNode(
                rect: CGRect(x: -btnW/2, y: -btnH/2, width: 4, height: btnH),
                cornerRadius: 2)
            bar.fillColor   = Parchment.amber.withAlphaComponent(0.9)
            bar.strokeColor = .clear
            bar.name        = "choice_\(i)"
            container.addChild(bar)

            let lbl = SKLabelNode(fontNamed: font)
            lbl.text      = choice.label
            lbl.fontSize  = min(15, W / 20)
            lbl.fontColor = Parchment.deep
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode   = .center
            lbl.position = .zero
            lbl.name     = "choice_\(i)"
            container.addChild(lbl)

            choiceContainer.addChild(container)
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
        overlay.zPosition = 90
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        var name = ""
        for node in nodes(at: loc).sorted(by: { $0.zPosition > $1.zPosition }) {
            if let n = node.name, !n.isEmpty { name = n; break }
            if let n = node.parent?.name, !n.isEmpty { name = n; break }
            if let n = node.parent?.parent?.name, !n.isEmpty { name = n; break }
        }

        if name == "backToMenu" {
            returnToMenu()
            return
        }

        if name == "scrollUp" || name == "scrollDown" {
            // Only intercept once the text is fully revealed and actually overflows —
            // otherwise fall through so a tap there still skips/advances as normal.
            if isTypewriterDone && maxTextScroll > 0 {
                scrollText(direction: name == "scrollUp" ? -1 : 1)
                return
            }
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

        case .spawnOnMap(let config):
            // Apply next-module pointer and flags before leaving the scene.
            if let nextID = config.nextModuleID {
                StoryManager.shared.currentModuleID = nextID
            }
            StoryManager.shared.pendingWorldTrigger = config.trigger
            for flag in config.flags { StoryManager.shared.setFlag(flag) }

            let ppSize = pixelPerfectSize() ?? size
            let gs = GameScene(size: ppSize)
            if let x = config.x, let y = config.y {
                gs.storySpawnOverride = CGPoint(x: x, y: y)
            }
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
        panelNode.run(.sequence([
            .fadeOut(withDuration: 0.18),
            .run { [weak self] in self?.showModule(next) },
            .fadeIn(withDuration: 0.18)
        ]))
    }

    // MARK: - Mini-game launch
    private func launchMiniGame(_ type: StoryMiniGame) {
        let ppSize = pixelPerfectSize() ?? size

        // For SK-scene mini-games: queue the next module and let didMove handle it on return.
        let handleResult: (Bool) -> Void = { [weak self] won in
            guard let self = self else { return }
            self.queuedModuleID = won ? self.miniGameWinID : self.miniGameLoseID
        }

        switch type {

        case .cornholeVs(let opponent):
            let inv = InventoryManager()
            let s = CornholeMiniGameScene(size: ppSize)
            s.previousScene       = self
            s.scaleMode           = .resizeFill
            s.preSelectedOpponent = opponent
            s.awardsRewards       = true   // story mode grants prizes
            s.availableHoneyBags  = inv.counts[.honeyBag,  default: 0]
            s.availableBombBags   = inv.counts[.bombBag,   default: 0]
            s.availableMagicBags  = inv.counts[.magicBag,  default: 0]
            s.availableFireBags   = inv.counts[.fireBag,   default: 0]
            s.availableGoldenBags = inv.counts[.goldenBag, default: 0]
            s.onComplete = { [weak s] won in
                if let used = s?.honeyBagsUsed,  used > 0 { inv.consume(.honeyBag,  count: used) }
                if let used = s?.bombBagsUsed,   used > 0 { inv.consume(.bombBag,   count: used) }
                if let used = s?.magicBagsUsed,  used > 0 { inv.consume(.magicBag,  count: used) }
                if let used = s?.fireBagsUsed,   used > 0 { inv.consume(.fireBag,   count: used) }
                if let used = s?.goldenBagsUsed, used > 0 { inv.consume(.goldenBag, count: used) }
                if let e = s?.bombBagsEarned,  e > 0 { inv.collect(.bombBag,  count: e) }
                if let e = s?.magicBagsEarned, e > 0 { inv.collect(.magicBag, count: e) }
                if let e = s?.fireBagsEarned,  e > 0 { inv.collect(.fireBag,  count: e) }
                if let e = s?.goldenBagsEarned, e > 0 { inv.collect(.goldenBag, count: e) }
                if let e = s?.coinsEarned,     e > 0 { inv.collect(.coin,     count: e) }
                if s?.houseKeyEarned == true { inv.collect(.houseKey, count: 1) }
                handleResult(won)
            }
            push(to: s)

        case .baseballVs(let difficulty):
            let s = CornholeBaseballScene(size: ppSize)
            s.previousScene  = self
            s.scaleMode      = .resizeFill
            s.aiDifficulty   = difficulty
            s.awardsRewards  = true
            s.onComplete = { won in
                // Record baseball-defeat stats so the bat / jousters unlock progresses.
                if won {
                    if difficulty == .powerHitter { CornholeStatsManager.shared.defeatedJenBaseball = true }
                    if difficulty == .greatFielder { CornholeStatsManager.shared.defeatedTomBaseball = true }
                }
                handleResult(won)
            }
            push(to: s)

        case .beehive:
            let inv = InventoryManager()
            let s = BeeHiveScene(size: ppSize)
            s.previousScene  = self
            s.scaleMode      = .resizeFill
            s.startingHearts = 3
            s.awardsRewards  = true
            s.onComplete = { won in
                if won { inv.collect(.honeyBag, count: 3) }
                handleResult(won)
            }
            push(to: s)

        case .piranha:
            let inv = InventoryManager()
            let s = BridgePiranhaScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.awardsRewards = true
            s.availableFloatingBags = inv.counts[.floatingBag, default: 0]
            s.onComplete = { [weak s] won in
                if let used = s?.floatingBagsUsed, used > 0 { inv.consume(.floatingBag, count: used) }
                if won { UserDefaults.standard.set(true, forKey: "bridgeUnlocked_v1") }
                handleResult(won)
            }
            push(to: s)

        case .beachball:
            let inv = InventoryManager()
            let s = BeachBallCornholeScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.awardsRewards = true
            s.onComplete = { won in
                if won { inv.collect(.floatingBag, count: 8) }
                handleResult(won)
            }
            push(to: s)

        case .jousters:
            let s = SuburbanJoustersScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.awardsRewards = true
            s.startingHearts = HeartsManager.shared.currentHearts
            s.onComplete = { [weak s] won in
                if let s { HeartsManager.shared.set(s.remainingHearts) }
                if won { UserDefaults.standard.set(true, forKey: "goldenLanceEarned_v1") }
                handleResult(won)
            }
            push(to: s)

        case .horseRace:
            let s = HorseRaceCornholeScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.onComplete = { won in handleResult(won) }
            push(to: s)

        case .kickball:
            let s = KickballScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.onComplete = { won in handleResult(won) }
            push(to: s)

        case .mopChase:
            let s = MopBucketChaseScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.onComplete = { won in handleResult(won) }
            push(to: s)

        case .wellFlinger:
            let inv = InventoryManager()
            let s = WellFlingerScene(size: ppSize)
            s.previousScene = self
            s.scaleMode = .resizeFill
            s.awardsRewards = true
            s.availableBags = inv.counts[.bag, default: 0]
            s.availableFireBags = inv.counts[.fireBag, default: 0]
            s.onComplete = { [weak s] won in
                if let used = s?.bagsUsed, used > 0 {
                    inv.consume(.bag, count: min(used, inv.counts[.bag, default: 0]))
                }
                if let e = s?.fireBagsEarned, e > 0 { inv.collect(.fireBag, count: e) }
                handleResult(won)
            }
            push(to: s)

        case .bike:
            // Bike runs as a UIViewController modal; callback fires after VC dismisses.
            guard let rootVC = view?.window?.rootViewController else { return }
            let winID  = miniGameWinID
            let loseID = miniGameLoseID
            let bikeVC = BikeDodgeViewController()
            bikeVC.modalPresentationStyle = .fullScreen
            bikeVC.onDismissWithResult = { [weak self] won in
                guard let self = self else { return }
                let nextID = won ? winID : loseID
                if let id = nextID { self.transitionToModule(id: id) }
            }
            DispatchQueue.main.async { rootVC.present(bikeVC, animated: true) }
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
