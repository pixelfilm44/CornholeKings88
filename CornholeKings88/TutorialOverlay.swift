import SpriteKit

/// A single step in a tutorial sequence.
/// - `card`: a centered modal panel with title + body text.
/// - `hint`: a panel offset from a target point on screen, with a pulsing
///   arrow pointing at the target. Use for "look at this UI element" steps.
struct TutorialStep {
    enum Kind {
        case card
        case hint(targetPoint: CGPoint)
    }
    var kind: Kind
    var title: String
    var body: String

    static func card(title: String, body: String) -> TutorialStep {
        TutorialStep(kind: .card, title: title, body: body)
    }
    static func hint(at target: CGPoint, title: String, body: String) -> TutorialStep {
        TutorialStep(kind: .hint(targetPoint: target), title: title, body: body)
    }
}

/// Full-screen tutorial overlay that walks the player through a sequence of
/// `TutorialStep`s. Tap anywhere to advance. The overlay blocks all touches
/// underneath so the host scene's input handlers don't fire while it's up.
///
/// Usage:
/// ```
/// let overlay = TutorialOverlay(steps: [...]) { /* on complete */ }
/// scene.addChild(overlay)
/// ```
final class TutorialOverlay: SKNode {

    // MARK: - Public API
    /// Closure invoked after the final step is dismissed.
    var onComplete: (() -> Void)?

    // MARK: - Styling (centralized — change here to restyle all tutorials)
    private static let panelFill   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.96)
    private static let panelStroke = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.55)
    private static let titleColor: SKColor = .yellow
    private static let bodyColor   = SKColor(white: 0.92, alpha: 1)
    private static let promptColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
    private static let counterColor = SKColor(white: 0.55, alpha: 1)
    private static let backdropAlpha: CGFloat = 0.78
    private static let titleFont = "PressStart2P-Regular"
    private static let bodyFont  = "PressStart2P-Regular"

    // MARK: - State
    private let steps: [TutorialStep]
    private var index: Int = 0
    private let sceneW: CGFloat
    private let sceneH: CGFloat
    private var currentPanel: SKNode?

    /// - Parameters:
    ///   - steps: Ordered list of cards/hints to show.
    ///   - sceneSize: Size of the host scene (for panel layout).
    ///   - onComplete: Fired after the final step is dismissed.
    init(steps: [TutorialStep], sceneSize: CGSize, onComplete: @escaping () -> Void) {
        self.steps = steps
        self.sceneW = sceneSize.width
        self.sceneH = sceneSize.height
        self.onComplete = onComplete
        super.init()
        self.zPosition = 1000
        addBackdrop()
        showStep(0)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Host-routed input
    /// Returns the active overlay in the scene, if any. Host scenes should
    /// call this in `touchesBegan` and route taps to `advance()` so the
    /// scene's own input handling stays disabled while a tutorial is up.
    static func active(in scene: SKScene) -> TutorialOverlay? {
        scene.children.first(where: { $0 is TutorialOverlay }) as? TutorialOverlay
    }

    /// Advances to the next step (or finishes if on the last step).
    /// Idempotent if the overlay has already finished.
    func advance() {
        guard onComplete != nil || index < steps.count else { return }
        index += 1
        showStep(index)
    }

    // MARK: - Backdrop
    private func addBackdrop() {
        let bg = SKShapeNode(rect: CGRect(x: -sceneW/2, y: -sceneH/2,
                                          width: sceneW, height: sceneH))
        bg.fillColor   = SKColor(white: 0, alpha: TutorialOverlay.backdropAlpha)
        bg.strokeColor = .clear
        bg.zPosition   = 0
        addChild(bg)
    }

    // MARK: - Step rendering
    private func showStep(_ i: Int) {
        currentPanel?.removeFromParent()
        guard i < steps.count else { finish(); return }
        let step = steps[i]

        let isLast = (i == steps.count - 1)
        let prompt = isLast ? "▶  TAP TO START" : "▶  TAP TO CONTINUE"
        let counter = "\(i + 1) / \(steps.count)"

        let panel: SKNode
        switch step.kind {
        case .card:
            panel = makePanel(title: step.title, body: step.body,
                              prompt: prompt, counter: counter,
                              showArrowFrom: nil)
            panel.position = .zero
        case .hint(let target):
            panel = makePanel(title: step.title, body: step.body,
                              prompt: prompt, counter: counter,
                              showArrowFrom: target)
            panel.position = panelPosition(for: target)
        }
        addChild(panel)
        currentPanel = panel

        // Subtle pop-in
        panel.setScale(0.92); panel.alpha = 0
        panel.run(.group([
            .fadeIn(withDuration: 0.18),
            .scale(to: 1.0, duration: 0.22),
        ]))
    }

    private func finish() {
        let cb = onComplete; onComplete = nil
        run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent(),
                       .run { cb?() }]))
    }

    // MARK: - Panel construction
    private func makePanel(title: String, body: String,
                           prompt: String, counter: String,
                           showArrowFrom target: CGPoint?) -> SKNode {
        let container = SKNode()
        container.zPosition = 5

        let panelW: CGFloat = min(sceneW - 40, 320)
        let bodyFontSize: CGFloat = min(9, panelW / 36)
        let titleFontSize: CGFloat = min(14, panelW / 22)
        let bodyLines = wrap(body, lineCharLimit: charLimit(forPanelWidth: panelW,
                                                            fontSize: bodyFontSize))
        let lineHeight = bodyFontSize * 1.6
        let bodyBlockH = lineHeight * CGFloat(bodyLines.count)
        let panelH: CGFloat = 28 + titleFontSize + 14 + bodyBlockH + 22 + bodyFontSize + 18

        let panel = SKShapeNode(rect: CGRect(x: -panelW/2, y: -panelH/2,
                                             width: panelW, height: panelH),
                                cornerRadius: 4)
        panel.fillColor   = TutorialOverlay.panelFill
        panel.strokeColor = TutorialOverlay.panelStroke
        panel.lineWidth   = 2
        container.addChild(panel)

        // Step counter — top-right inside the panel
        let counterLbl = SKLabelNode(fontNamed: TutorialOverlay.bodyFont)
        counterLbl.text = counter
        counterLbl.fontSize = bodyFontSize - 1
        counterLbl.fontColor = TutorialOverlay.counterColor
        counterLbl.horizontalAlignmentMode = .right
        counterLbl.verticalAlignmentMode   = .top
        counterLbl.position = CGPoint(x: panelW/2 - 10, y: panelH/2 - 10)
        container.addChild(counterLbl)

        // Title
        let titleLbl = SKLabelNode(fontNamed: TutorialOverlay.titleFont)
        titleLbl.text = title
        titleLbl.fontSize = titleFontSize
        titleLbl.fontColor = TutorialOverlay.titleColor
        titleLbl.horizontalAlignmentMode = .center
        titleLbl.verticalAlignmentMode   = .top
        titleLbl.position = CGPoint(x: 0, y: panelH/2 - 22)
        container.addChild(titleLbl)

        // Body — wrapped lines
        var y = titleLbl.position.y - titleFontSize - 14
        for line in bodyLines {
            let lbl = SKLabelNode(fontNamed: TutorialOverlay.bodyFont)
            lbl.text = line
            lbl.fontSize = bodyFontSize
            lbl.fontColor = TutorialOverlay.bodyColor
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode   = .top
            lbl.position = CGPoint(x: 0, y: y)
            container.addChild(lbl)
            y -= lineHeight
        }

        // Continue prompt — pulses at the bottom
        let promptLbl = SKLabelNode(fontNamed: TutorialOverlay.bodyFont)
        promptLbl.text = prompt
        promptLbl.fontSize = bodyFontSize
        promptLbl.fontColor = TutorialOverlay.promptColor
        promptLbl.horizontalAlignmentMode = .center
        promptLbl.verticalAlignmentMode   = .bottom
        promptLbl.position = CGPoint(x: 0, y: -panelH/2 + 14)
        promptLbl.run(.repeatForever(.sequence([
            .scale(to: 1.08, duration: 0.55),
            .scale(to: 0.94, duration: 0.55),
        ])))
        container.addChild(promptLbl)

        // Optional pointer arrow at target (in scene coordinates — added as a
        // sibling of the panel rather than a child so its position isn't
        // affected by panel offset).
        if let target {
            let arrow = makePointerArrow(at: target, towardPanelCenter: panelPosition(for: target))
            arrow.zPosition = 6
            // Add to self so it stays in scene-space, not panel-space.
            // The caller adds the panel to `self`; we return a wrapper that
            // groups both so they animate together.
            let wrap = SKNode()
            wrap.zPosition = 5
            wrap.addChild(arrow)
            wrap.addChild(container)
            return wrap
        }

        return container
    }

    // MARK: - Pointer arrow
    private func makePointerArrow(at scenePoint: CGPoint,
                                  towardPanelCenter panelCenter: CGPoint) -> SKNode {
        // Arrow is a small filled triangle pointing from the panel toward the
        // target. We rotate based on the angle from panel to target.
        let dx = scenePoint.x - panelCenter.x
        let dy = scenePoint.y - panelCenter.y
        let angle = atan2(dy, dx)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 14, y: 0))
        path.addLine(to: CGPoint(x: -10, y: 8))
        path.addLine(to: CGPoint(x: -6, y: 0))
        path.addLine(to: CGPoint(x: -10, y: -8))
        path.closeSubpath()

        let arrow = SKShapeNode(path: path)
        arrow.fillColor   = TutorialOverlay.promptColor
        arrow.strokeColor = .black
        arrow.lineWidth   = 1
        arrow.position    = scenePoint
        arrow.zRotation   = angle
        arrow.run(.repeatForever(.sequence([
            .scale(to: 1.25, duration: 0.45),
            .scale(to: 0.85, duration: 0.45),
        ])))
        return arrow
    }

    // MARK: - Panel placement around a target
    /// Computes a panel center position that keeps the panel on-screen and
    /// off the target. Default: place the panel on the opposite half of the
    /// scene (above if target is below center, below if target is above).
    private func panelPosition(for target: CGPoint) -> CGPoint {
        let offset: CGFloat = sceneH * 0.22
        let y = target.y >= 0 ? -offset : offset
        return CGPoint(x: 0, y: y)
    }

    // MARK: - Text wrapping
    private func charLimit(forPanelWidth w: CGFloat, fontSize fs: CGFloat) -> Int {
        // PressStart2P glyphs are square-ish; ~1.0× fontSize wide per char.
        // Use a small safety margin so words don't kiss the panel edge.
        let usable = w - 28
        return max(8, Int(usable / (fs * 1.05)))
    }

    private func wrap(_ text: String, lineCharLimit limit: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let w = String(word)
            if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= limit {
                current += " " + w
            } else {
                lines.append(current); current = w
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

}

// MARK: - HUD help button
/// Reusable `?` button. Each mini-game's HUD adds one at a corner; the host
/// scene's `touchesBegan` checks for the node name `TutorialHelpButton.name`
/// and presents the tutorial when tapped.
enum TutorialHelpButton {
    static let name = "tutorialHelpBtn"

    /// Builds a circular `?` button. Add to your HUD and position it in a
    /// free corner (top-left works well; top-right usually holds a close
    /// button). The returned node's name is set so taps can be routed.
    static func make(radius: CGFloat = 14) -> SKNode {
        let container = SKNode()
        container.name = name
        container.zPosition = 60

        let bg = SKShapeNode(circleOfRadius: radius)
        bg.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.96)
        bg.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.6)
        bg.lineWidth   = 1.5
        bg.name        = name
        container.addChild(bg)

        let q = SKLabelNode(fontNamed: "PressStart2P-Regular")
        q.text = "?"
        q.fontSize = radius * 1.1
        q.fontColor = .yellow
        q.horizontalAlignmentMode = .center
        q.verticalAlignmentMode   = .center
        q.position = CGPoint(x: 0, y: -1)
        q.name = name
        container.addChild(q)

        return container
    }

    /// Returns true if `node` (or any of its ancestors) has the help button
    /// name. Use this from `touchesBegan` to detect taps reliably across
    /// SKShapeNode vs SKLabelNode children.
    static func wasTapped(_ node: SKNode) -> Bool {
        var n: SKNode? = node
        while let cur = n {
            if cur.name == name { return true }
            n = cur.parent
        }
        return false
    }
}

