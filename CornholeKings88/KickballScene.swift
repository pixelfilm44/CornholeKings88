import SpriteKit
import UIKit

// MARK: - KickballScene
//
// Chapter 2 dream sequence: kickball on the school pavement, bases loaded,
// bottom of the last inning — the version where Jack finally connects.
//
// Flow per pitch (3 tries, first HIT wins):
//   1. AIM  — while the ball rolls down from the pitcher, swipe left/right
//             to set the kick direction (arrow at the plate).
//   2. RUN  — tap anywhere to start Jack's run-up; a speed meter builds
//             while he churns toward the plate.
//   3. KICK — a pulsing KICK button appears; tap it as the ball crosses
//             the plate. Timing quality × run speed × aim = the kick.
// A hit must be FAIR (inside the chalk foul lines) and reach PAST the
// infield — weak contact is fielded for an out, wide kicks go foul, and
// a badly timed tap whiffs entirely.
//
// Standard mini-game contract; no rewards in any context (pure story
// beat / picker replay — `awardsRewards` exists only to satisfy hosts).
final class KickballScene: SKScene {

    // MARK: - Public
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    var awardsRewards: Bool = false

    // MARK: - Tunables
    private let maxTries = 3
    private let pitchDuration: TimeInterval = 2.3   // pitcher → plate travel time
    /// The sprint from the run-up spot to the plate takes exactly this long,
    /// with speed ramping 0→1 across it. Reaching the plate while the ball is
    /// still rolling = Jack stops dead and ALL power is lost.
    private let runSpeedRampTime: TimeInterval = 1.1
    private let perfectWindow: CGFloat = 20          // |ballY-plateY| for perfect timing
    private let baseWhiffWindow:   CGFloat = 64          // beyond this = total miss
    private let baseFoulAngle:     CGFloat = .pi * 0.24  // ±43° from straight up = fair
    private let baseHitPowerThreshold: CGFloat = 0.62    // weaker contact gets fielded

    /// This is a story beat, not a skill gate — nobody should get stuck in a
    /// dream sequence. Each failed try quietly widens the timing window,
    /// lowers the power bar, and opens up the foul lines, so the player fails
    /// once or twice for drama, then connects and feels clever on a later try.
    /// `currentTry` is 1-indexed (incremented at the start of each try), so
    /// these read the *previous* fail count.
    private var whiffWindow: CGFloat {
        switch currentTry {
        case ...1:  return baseWhiffWindow
        case 2:     return baseWhiffWindow * 1.35
        default:    return baseWhiffWindow * 1.7
        }
    }
    private var foulAngle: CGFloat {
        switch currentTry {
        case ...1:  return baseFoulAngle
        case 2:     return baseFoulAngle * 1.15
        default:    return baseFoulAngle * 1.3
        }
    }
    private var hitPowerThreshold: CGFloat {
        switch currentTry {
        case ...1:  return baseHitPowerThreshold
        case 2:     return baseHitPowerThreshold - 0.08
        default:    return baseHitPowerThreshold - 0.16
        }
    }

    // MARK: - Layout
    private var pitcherPos  = CGPoint.zero
    private var platePos    = CGPoint.zero
    private var infieldLineY: CGFloat = 0

    // MARK: - Phase
    private enum TryPhase { case idle, pitching, running, ballInFlight, resolving }
    private var phase: TryPhase = .idle
    private var currentTry = 0
    private var isGameOver = false
    private var isPausedGame = false
    private var countdownActive = true
    private var tutorialUp = false
    private var confirmingQuit = false

    // MARK: - Live-try state
    private var pitchStartTime: TimeInterval = 0
    private var runStartTime:   TimeInterval = 0
    private var currentSceneTime: TimeInterval = 0
    private var pauseTimeShift: TimeInterval = 0     // pause compensation
    private var pauseBeganAt: TimeInterval = 0
    private var aimAngle: CGFloat = 0                // radians off straight-up, +right
    private var kickVel = CGVector.zero              // ball velocity after the kick
    private var flightIsHit = false
    private var flightMessage = ""
    private var chasingFielder: SKNode?
    private var chaseTarget = CGPoint.zero

    // MARK: - Nodes
    private var ballNode: SKShapeNode?
    private var kickerNode: SKNode?
    private var pitcherNode: SKNode?
    private var fielders: [SKNode] = []
    private var aimArrow: SKShapeNode?
    private var speedMeterFill: SKSpriteNode?
    private var speedMeterNode: SKNode?
    private var kickButton: SKNode?
    private var triesLabel: SKLabelNode?
    private var messageNode: SKNode?
    private var pauseOverlayNode: SKNode?
    private var confirmPanel: SKNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.32, green: 0.31, blue: 0.33, alpha: 1) // hot pavement

        computeLayout()
        buildField()
        buildCharacters()
        setupUI()
        addDreamOverlay()
        addCrtOverlay()

        if TutorialManager.shared.hasSeen(TutorialManager.kickball) {
            startCountdown()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    private func computeLayout() {
        let W = size.width, H = size.height
        pitcherPos   = CGPoint(x: 0, y: H * 0.26)
        platePos     = CGPoint(x: 0, y: -H * 0.26)
        infieldLineY = H * 0.04
        _ = W
    }

    // MARK: - Field

    private func buildField() {
        let W = size.width, H = size.height

        // Chalk foul lines diverging from home plate.
        for side: CGFloat in [-1, 1] {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: platePos)
            let a = foulAngle * side
            path.addLine(to: CGPoint(x: platePos.x + sin(a) * H * 1.1,
                                     y: platePos.y + cos(a) * H * 1.1))
            line.path = path
            line.strokeColor = SKColor(white: 0.92, alpha: 0.55)
            line.lineWidth = 2
            line.zPosition = 2
            addChild(line)
        }

        // Infield arc (chalk) — a hit must carry past this line.
        let arc = SKShapeNode()
        let arcPath = CGMutablePath()
        arcPath.move(to: CGPoint(x: -W * 0.42, y: infieldLineY - 14))
        arcPath.addQuadCurve(to: CGPoint(x: W * 0.42, y: infieldLineY - 14),
                             control: CGPoint(x: 0, y: infieldLineY + 30))
        arc.path = arcPath
        arc.strokeColor = SKColor(white: 0.92, alpha: 0.40)
        arc.lineWidth = 2
        arc.zPosition = 2
        addChild(arc)

        // Home plate + bases (painted squares on the pavement).
        func base(at p: CGPoint) {
            let b = SKSpriteNode(color: SKColor(white: 0.94, alpha: 0.85),
                                 size: CGSize(width: 12, height: 12))
            b.position = p
            b.zRotation = .pi / 4
            b.zPosition = 2
            addChild(b)
        }
        base(at: platePos)
        base(at: CGPoint(x:  W * 0.30, y: -H * 0.04))  // 1st
        base(at: CGPoint(x: 0,         y: H * 0.10))   // 2nd
        base(at: CGPoint(x: -W * 0.30, y: -H * 0.04))  // 3rd

        // Pitcher's chalk circle.
        let mound = SKShapeNode(circleOfRadius: 18)
        mound.strokeColor = SKColor(white: 0.92, alpha: 0.40)
        mound.lineWidth = 2
        mound.position = pitcherPos
        mound.zPosition = 2
        addChild(mound)

        // Pavement cracks — sparse darker flecks.
        let cracks = SKNode()
        cracks.zPosition = 1
        for _ in 0..<26 {
            let fleck = SKSpriteNode(color: SKColor(white: 0.22, alpha: 0.5),
                                     size: CGSize(width: CGFloat.random(in: 3...9), height: 2))
            fleck.position = CGPoint(x: CGFloat.random(in: -W/2...W/2),
                                     y: CGFloat.random(in: -H/2...H/2))
            fleck.zRotation = CGFloat.random(in: -0.5...0.5)
            cracks.addChild(fleck)
        }
        addChild(cracks)
    }

    /// Tiny two-block pixel kid, tinted per role.
    private func makeKid(shirt: SKColor, hair: SKColor) -> SKNode {
        let kid = SKNode()
        let body = SKSpriteNode(color: shirt, size: CGSize(width: 10, height: 14))
        let head = SKSpriteNode(color: SKColor(red: 0.94, green: 0.78, blue: 0.60, alpha: 1),
                                size: CGSize(width: 9, height: 8))
        head.position = CGPoint(x: 0, y: 11)
        let hairCap = SKSpriteNode(color: hair, size: CGSize(width: 9, height: 3))
        hairCap.position = CGPoint(x: 0, y: 15)
        kid.addChild(body); kid.addChild(head); kid.addChild(hairCap)
        return kid
    }

    private func buildCharacters() {
        let W = size.width, H = size.height

        // Pitcher (top).
        let pitcher = makeKid(shirt: SKColor(red: 0.25, green: 0.42, blue: 0.68, alpha: 1),
                              hair: SKColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 1))
        pitcher.position = pitcherPos
        pitcher.zPosition = 10
        addChild(pitcher)
        pitcherNode = pitcher

        // Kicker Jack — starts a run-up length behind the plate.
        let jack = makeKid(shirt: SKColor(red: 0.80, green: 0.24, blue: 0.16, alpha: 1),
                           hair: SKColor(red: 0.42, green: 0.28, blue: 0.12, alpha: 1))
        jack.position = kickerHomePosition()
        jack.zPosition = 12
        addChild(jack)
        kickerNode = jack

        // Infield defenders.
        fielders.forEach { $0.removeFromParent() }
        fielders = []
        let spots = [CGPoint(x: -W * 0.24, y: -H * 0.02),
                     CGPoint(x: -W * 0.08, y: H * 0.06),
                     CGPoint(x:  W * 0.08, y: H * 0.06),
                     CGPoint(x:  W * 0.24, y: -H * 0.02)]
        for p in spots {
            let f = makeKid(shirt: SKColor(red: 0.30, green: 0.52, blue: 0.30, alpha: 1),
                            hair: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1))
            f.position = p
            f.zPosition = 10
            f.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 1.5, duration: 0.6),
                .moveBy(x: 0, y: -1.5, duration: 0.6),
            ])))
            addChild(f)
            fielders.append(f)
        }

        // Sideline watchers — Kim (curly brown hair) among them, per the memoir.
        let sidelineX = -W * 0.42
        for (i, hair) in [SKColor(red: 0.36, green: 0.22, blue: 0.10, alpha: 1),   // Kim
                          SKColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1),
                          SKColor(red: 0.78, green: 0.64, blue: 0.28, alpha: 1)].enumerated() {
            let kid = makeKid(shirt: SKColor(hue: CGFloat(i) * 0.28 + 0.05,
                                             saturation: 0.45, brightness: 0.62, alpha: 1),
                              hair: hair)
            kid.position = CGPoint(x: sidelineX, y: -H * 0.10 + CGFloat(i) * 34)
            kid.zPosition = 9
            kid.setScale(0.85)
            kid.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 2, duration: 0.5 + Double(i) * 0.1),
                .moveBy(x: 0, y: -2, duration: 0.5 + Double(i) * 0.1),
            ])))
            addChild(kid)
        }
    }

    private func kickerHomePosition() -> CGPoint {
        CGPoint(x: platePos.x - 26, y: platePos.y - size.height * 0.11)
    }

    // MARK: - HUD

    private func setupUI() {
        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let topBarY = size.height / 2 - totalTopH / 2

        let topBar = SKSpriteNode(color: Parchment.paper,
                                  size: CGSize(width: size.width, height: totalTopH))
        topBar.position = CGPoint(x: 0, y: topBarY)
        topBar.zPosition = 500
        addChild(topBar)

        let topBorder = SKSpriteNode(color: Parchment.edge,
                                     size: CGSize(width: size.width, height: 3))
        topBorder.position = CGPoint(x: 0, y: size.height / 2 - topInset - topH + 1)
        topBorder.zPosition = 501
        addChild(topBorder)

        let contentY = size.height / 2 - topInset - topH / 2

        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size = CGSize(width: 22, height: 22)
        pauseBtn.position = CGPoint(x: -size.width / 2 + 22, y: contentY)
        pauseBtn.zPosition = 502
        pauseBtn.name = "pauseBtn"
        addChild(pauseBtn)

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -size.width / 2 + 52, y: contentY)
        help.zPosition = 502
        addChild(help)

        let label = SKLabelNode(fontNamed: "PressStart2P-Regular")
        label.text = "TRY 1 / \(maxTries)"
        label.fontSize = 10
        label.fontColor = Parchment.deep
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: contentY)
        label.zPosition = 502
        addChild(label)
        triesLabel = label

        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size = CGSize(width: 22, height: 22)
        closeBtn.position = CGPoint(x: size.width / 2 - 22, y: contentY)
        closeBtn.zPosition = 502
        closeBtn.name = "closeButton"
        addChild(closeBtn)

        // Aim arrow at the plate — rotates with the swipe.
        let arrow = SKShapeNode()
        let ap = CGMutablePath()
        ap.move(to: .zero)
        ap.addLine(to: CGPoint(x: 0, y: 46))
        ap.move(to: CGPoint(x: -6, y: 38))
        ap.addLine(to: CGPoint(x: 0, y: 46))
        ap.addLine(to: CGPoint(x: 6, y: 38))
        arrow.path = ap
        arrow.strokeColor = SKColor(red: 0.98, green: 0.82, blue: 0.30, alpha: 0.9)
        arrow.lineWidth = 3
        arrow.position = platePos
        arrow.zPosition = 15
        addChild(arrow)
        aimArrow = arrow

        // Speed meter — left of the plate, fills while Jack runs.
        let meter = SKNode()
        meter.position = CGPoint(x: -size.width * 0.34, y: platePos.y)
        meter.zPosition = 15
        let meterBG = SKSpriteNode(color: SKColor(white: 0, alpha: 0.45),
                                   size: CGSize(width: 14, height: 84))
        meter.addChild(meterBG)
        let fill = SKSpriteNode(color: SKColor(red: 0.30, green: 0.85, blue: 0.35, alpha: 1),
                                size: CGSize(width: 10, height: 0))
        fill.anchorPoint = CGPoint(x: 0.5, y: 0)
        fill.position = CGPoint(x: 0, y: -40)
        meter.addChild(fill)
        let meterLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        meterLbl.text = "SPEED"
        meterLbl.fontSize = 6
        meterLbl.fontColor = SKColor(white: 0.95, alpha: 0.8)
        meterLbl.position = CGPoint(x: 0, y: -58)
        meter.addChild(meterLbl)
        meter.isHidden = true
        addChild(meter)
        speedMeterNode = meter
        speedMeterFill = fill

        // KICK button — bottom-right, hidden until the run starts.
        let btn = SKNode()
        btn.position = CGPoint(x: size.width / 2 - 58, y: -size.height / 2 + 92)
        btn.zPosition = 520
        btn.name = "kickBtn"
        let circle = SKShapeNode(circleOfRadius: 34)
        circle.fillColor = SKColor(red: 0.80, green: 0.24, blue: 0.16, alpha: 0.95)
        circle.strokeColor = SKColor(red: 0.98, green: 0.82, blue: 0.30, alpha: 1)
        circle.lineWidth = 3
        circle.name = "kickBtn"
        btn.addChild(circle)
        let btnLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        btnLbl.text = "KICK!"
        btnLbl.fontSize = 9
        btnLbl.fontColor = .white
        btnLbl.verticalAlignmentMode = .center
        btnLbl.name = "kickBtn"
        btn.addChild(btnLbl)
        btn.isHidden = true
        addChild(btn)
        kickButton = btn
    }

    /// Soft drifting haze + pale vignette — sells the "this is a dream" wash.
    private func addDreamOverlay() {
        let W = size.width, H = size.height
        let dream = SKNode()
        dream.zPosition = 750

        for i in 0..<3 {
            let blob = SKSpriteNode(color: SKColor(white: 1.0, alpha: 0.07),
                                    size: CGSize(width: W * 0.7, height: H * 0.28))
            blob.position = CGPoint(x: CGFloat.random(in: -W * 0.3...W * 0.3),
                                    y: -H * 0.3 + CGFloat(i) * H * 0.3)
            let drift = Double.random(in: 7...11)
            blob.run(.repeatForever(.sequence([
                .moveBy(x: 30, y: 8, duration: drift),
                .moveBy(x: -30, y: -8, duration: drift),
            ])))
            dream.addChild(blob)
        }

        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 1, alpha: 0).cgColor,
                          UIColor(white: 1, alpha: 0.02).cgColor,
                          UIColor(white: 1, alpha: 0.18).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.6, 1.0])!
            c.drawRadialGradient(grad,
                                 startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                                 endCenter: CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.70,
                                 options: [])
        }
        let vignette = SKSpriteNode(texture: SKTexture(image: img),
                                    size: CGSize(width: W, height: H))
        dream.addChild(vignette)
        dream.isUserInteractionEnabled = false
        addChild(dream)
    }

    private func addCrtOverlay() {
        let w = size.width, h = size.height
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(UIColor(white: 0, alpha: 0.10).cgColor)
            var y: CGFloat = 0
            while y < h { c.fill(CGRect(x: 0, y: y, width: w, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let vColors = [UIColor(white: 0, alpha: 0).cgColor,
                           UIColor(white: 0, alpha: 0.08).cgColor,
                           UIColor(white: 0, alpha: 0.35).cgColor] as CFArray
            let vGrad = CGGradient(colorsSpace: space, colors: vColors, locations: [0, 0.55, 1.0])!
            c.drawRadialGradient(vGrad,
                                 startCenter: CGPoint(x: w/2, y: h/2), startRadius: 0,
                                 endCenter: CGPoint(x: w/2, y: h/2), endRadius: max(w, h) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img),
                                   size: CGSize(width: w, height: h))
        overlay.zPosition = 800
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Tutorial

    private func presentTutorial(autoTriggered: Bool) {
        tutorialUp = true
        let steps: [TutorialStep] = [
            .card(title: "BASES LOADED",
                  body: "BOTTOM OF THE LAST INNING. GET A HIT IN \(maxTries) TRIES — A FAIR BALL PAST THE INFIELD."),
            .hint(at: platePos,
                  title: "AIM & RUN",
                  body: "SWIPE LEFT/RIGHT TO AIM THE ARROW. TAP TO SPRINT — POWER BUILDS AS YOU RUN, BUT REACH THE PLATE TOO SOON AND YOU STOP DEAD!"),
            .hint(at: CGPoint(x: size.width / 2 - 58, y: -size.height / 2 + 92),
                  title: "KICK ON TIME",
                  body: "TAP KICK MID-SPRINT AS THE BALL CROSSES THE PLATE. ARRIVE TOGETHER WITH THE BALL FOR A MIGHTY KICK!"),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self else { return }
            self.tutorialUp = false
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.kickball)
                self.startCountdown()
            }
        }
        addChild(overlay)
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownActive = true

        func beatLabel(text: String, color: SKColor) -> SKAction {
            .run { [weak self] in
                guard let self else { return }
                let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
                lbl.text = text
                lbl.fontSize = min(48, self.size.width / 7)
                lbl.fontColor = color
                lbl.horizontalAlignmentMode = .center
                lbl.verticalAlignmentMode = .center
                lbl.zPosition = 900
                lbl.setScale(0.4)
                self.addChild(lbl)
                lbl.run(.sequence([
                    .group([.scale(to: 1.0, duration: 0.15), .fadeIn(withDuration: 0.10)]),
                    .wait(forDuration: 0.50),
                    .group([.scale(to: 1.4, duration: 0.25), .fadeOut(withDuration: 0.25)]),
                    .removeFromParent(),
                ]))
            }
        }

        let gold = Parchment.deep
        let green = SKColor(red: 0.18, green: 0.90, blue: 0.40, alpha: 1)
        let beat: TimeInterval = 0.85
        run(.sequence([
            beatLabel(text: "3", color: gold), .wait(forDuration: beat),
            beatLabel(text: "2", color: gold), .wait(forDuration: beat),
            beatLabel(text: "1", color: gold), .wait(forDuration: beat),
            beatLabel(text: "PLAY BALL!", color: green),
            .wait(forDuration: 0.6),
            .run { [weak self] in
                guard let self else { return }
                self.countdownActive = false
                self.startTry()
            },
        ]))
    }

    // MARK: - Try lifecycle

    private func startTry() {
        guard !isGameOver else { return }
        currentTry += 1
        triesLabel?.text = "TRY \(currentTry) / \(maxTries)"
        phase = .idle
        aimAngle = 0
        aimArrow?.zRotation = 0
        aimArrow?.isHidden = false
        speedMeterNode?.isHidden = true
        speedMeterFill?.size.height = 0
        speedMeterFill?.color = SKColor(red: 0.30, green: 0.85, blue: 0.35, alpha: 1)
        kickButton?.isHidden = true
        kickButton?.removeAction(forKey: "pulse")
        kickerNode?.position = kickerHomePosition()
        kickerNode?.zRotation = 0
        hasStalled = false
        chasingFielder = nil

        // Pitcher wind-up, then release.
        pitcherNode?.run(.sequence([
            .scaleY(to: 1.15, duration: 0.30),
            .scaleY(to: 1.0, duration: 0.12),
            .run { [weak self] in self?.releasePitch() },
        ]))
    }

    private func releasePitch() {
        guard !isGameOver else { return }
        ballNode?.removeFromParent()
        let ball = SKShapeNode(circleOfRadius: 9)
        ball.fillColor = SKColor(red: 0.82, green: 0.18, blue: 0.14, alpha: 1)
        ball.strokeColor = SKColor(red: 0.55, green: 0.10, blue: 0.08, alpha: 1)
        ball.lineWidth = 1.5
        ball.position = pitcherPos
        ball.zPosition = 14
        addChild(ball)
        ballNode = ball

        pitchStartTime = currentSceneTime
        phase = .pitching
    }

    /// 0…1 pitch progress (pitcher → plate).
    private var pitchProgress: CGFloat {
        CGFloat((currentSceneTime - pitchStartTime) / pitchDuration)
    }

    /// Jack's run-speed factor 0…1: ramps up across the sprint to the plate.
    /// The moment he arrives (sprint complete) with the ball still rolling, he
    /// stops dead — momentum and power drop straight to zero.
    private var runSpeedFactor: CGFloat {
        guard phase == .running else { return 0 }
        let t = currentSceneTime - runStartTime
        guard t <= runSpeedRampTime else { return 0 }   // reached the plate — stopped
        return CGFloat(t / runSpeedRampTime)
    }

    private var hasStalled = false

    private func startRun() {
        guard phase == .pitching else { return }
        phase = .running
        runStartTime = currentSceneTime
        speedMeterNode?.isHidden = false
        kickButton?.isHidden = false

        // Jack sprints toward the plate for the full ramp time — speed peaks
        // exactly as he arrives. The update loop stalls him if he gets there
        // while the ball is still rolling.
        kickerNode?.removeAllActions()
        kickerNode?.run(.group([
            .move(to: CGPoint(x: platePos.x - 16, y: platePos.y - 4),
                  duration: runSpeedRampTime),
            .repeat(.sequence([
                .rotate(toAngle: 0.10, duration: runSpeedRampTime / 12),
                .rotate(toAngle: -0.10, duration: runSpeedRampTime / 12),
            ]), count: 6),
        ]))

        // Button pulse accelerates as the ball nears the plate (re-pulsed in update()).
        pulseKickButton(rate: 0.5)
    }

    private func pulseKickButton(rate: TimeInterval) {
        kickButton?.removeAction(forKey: "pulse")
        kickButton?.run(.repeatForever(.sequence([
            .scale(to: 1.16, duration: rate / 2),
            .scale(to: 1.0, duration: rate / 2),
        ])), withKey: "pulse")
    }

    // MARK: - Kick resolution

    private func resolveKick() {
        guard phase == .running, let ball = ballNode else { return }

        let dist = abs(ball.position.y - platePos.y)
        // Total miss — the leg swings through empty air.
        if dist > whiffWindow {
            phase = .resolving
            kickerSwing()
            failTry(message: "WHIFF!", ballRollsPast: true)
            return
        }

        let timingQ = max(0, 1 - dist / whiffWindow)             // 0…1
        let speedF = runSpeedFactor
        var power = 0.30 + 0.70 * (0.55 * timingQ + 0.45 * speedF)
        // A stalled kicker has nothing behind the kick — never enough for a hit.
        if speedF < 0.05 { power = min(power, hitPowerThreshold - 0.10) }
        // Timing error skews direction: early = pulls the kick, late = pushes it.
        let skew = (ball.position.y - platePos.y) / whiffWindow * (.pi * 0.14)
        let kickAngle = aimAngle + skew

        phase = .ballInFlight
        kickerSwing()
        kickButton?.isHidden = true
        speedMeterNode?.isHidden = true
        aimArrow?.isHidden = true
        run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        HapticsManager.shared.mediumImpact()

        let speed = power * size.height * 1.05  // points per second
        kickVel = CGVector(dx: sin(kickAngle) * speed, dy: cos(kickAngle) * speed)
        ball.position = CGPoint(x: platePos.x, y: platePos.y + 4)

        // Outcome decided now; the flight animation plays it out.
        if abs(kickAngle) > foulAngle {
            flightIsHit = false
            flightMessage = "FOUL BALL!"
            chasingFielder = nil
        } else if power < hitPowerThreshold {
            flightIsHit = false
            flightMessage = speedF < 0.05 ? "NO LEGS — EASY OUT!" : "FIELDED — OUT!"
            // Nearest defender charges the ball's projected stall point.
            let stallT: CGFloat = 0.9
            chaseTarget = CGPoint(x: platePos.x + kickVel.dx * stallT * 0.5,
                                  y: platePos.y + kickVel.dy * stallT * 0.5)
            chasingFielder = fielders.min(by: {
                hypot($0.position.x - chaseTarget.x, $0.position.y - chaseTarget.y) <
                hypot($1.position.x - chaseTarget.x, $1.position.y - chaseTarget.y)
            })
            chasingFielder?.removeAllActions()
            chasingFielder?.run(.move(to: chaseTarget, duration: 0.55))
        } else {
            flightIsHit = true
            switch power {
            case ..<0.75:  flightMessage = "PAST THE INFIELD!"
            case ..<0.88:  flightMessage = "DEEP INTO THE OUTFIELD!"
            default:       flightMessage = "OVER EVERYONE'S HEADS!"
            }
            chasingFielder = nil
        }
    }

    private func kickerSwing() {
        kickerNode?.removeAllActions()
        kickerNode?.run(.sequence([
            .rotate(byAngle: -0.5, duration: 0.06),
            .rotate(byAngle: 0.5, duration: 0.10),
        ]))
    }

    private func failTry(message: String, ballRollsPast: Bool = false) {
        phase = .resolving
        showToast(message, color: SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
        kickButton?.isHidden = true
        speedMeterNode?.isHidden = true

        if ballRollsPast, let ball = ballNode {
            ball.run(.sequence([
                .moveBy(x: 0, y: -size.height * 0.25, duration: 0.6),
                .fadeOut(withDuration: 0.2),
                .removeFromParent(),
            ]))
            ballNode = nil
        }

        run(.wait(forDuration: 1.4)) { [weak self] in self?.finishTry(won: false) }
    }

    private func finishTry(won: Bool) {
        guard !isGameOver else { return }
        ballNode?.removeFromParent()
        ballNode = nil
        // Reset any chased fielder back to formation.
        if let f = chasingFielder {
            f.run(.sequence([
                .wait(forDuration: 0.3),
                .move(to: f.position, duration: 0),  // cancel residual actions cleanly
            ]))
        }
        buildFieldersBackIfNeeded()

        if won {
            triggerGameOver(playerWon: true)
        } else if currentTry >= maxTries {
            triggerGameOver(playerWon: false)
        } else {
            run(.wait(forDuration: 0.4)) { [weak self] in self?.startTry() }
        }
    }

    private func buildFieldersBackIfNeeded() {
        guard let f = chasingFielder else { return }
        chasingFielder = nil
        f.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 1.5, duration: 0.6),
            .moveBy(x: 0, y: -1.5, duration: 0.6),
        ])))
    }

    private func showToast(_ text: String, color: SKColor) {
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = text
        lbl.fontSize = min(16, size.width / 20)
        lbl.fontColor = color
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: 0, y: size.height * 0.16)
        lbl.zPosition = 850
        lbl.alpha = 0
        addChild(lbl)
        lbl.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 1.2),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        currentSceneTime = currentTime - pauseTimeShift
        guard !isPausedGame, !tutorialUp, !countdownActive, !isGameOver else { return }

        switch phase {
        case .pitching, .running:
            guard let ball = ballNode else { break }
            let p = pitchProgress
            if p >= 1.25 {
                // Ball rolled past the plate untouched.
                let msg = phase == .running ? "TOO LATE!" : "STRIKE!"
                failTry(message: msg, ballRollsPast: true)
                break
            }
            let y = pitcherPos.y + (platePos.y - pitcherPos.y) * min(p, 1.25)
            let wobble = sin(p * .pi * 3) * 5
            ball.position = CGPoint(x: pitcherPos.x + wobble, y: y)
            ball.zRotation -= 0.15

            if phase == .running {
                let factor = runSpeedFactor
                speedMeterFill?.size.height = 80 * factor
                // Reached the plate with the ball still rolling — dead stop, zero power.
                if factor <= 0, !hasStalled {
                    hasStalled = true
                    kickerNode?.removeAllActions()
                    kickerNode?.run(.rotate(toAngle: 0.15, duration: 0.2))
                    speedMeterFill?.color = SKColor(red: 0.90, green: 0.30, blue: 0.20, alpha: 1)
                    showToast("STOPPED AT THE PLATE!", color: SKColor(red: 0.95, green: 0.60, blue: 0.30, alpha: 1))
                }
                // Pulse urgency rises as the ball approaches the plate.
                let closeness = max(0, 1 - abs(ball.position.y - platePos.y) / (size.height * 0.4))
                pulseKickButtonIfRateChanged(rate: max(0.16, 0.5 - 0.34 * Double(closeness)))
            }

        case .ballInFlight:
            guard let ball = ballNode else { break }
            let dt: CGFloat = 1.0 / 60.0
            ball.position.x += kickVel.dx * dt
            ball.position.y += kickVel.dy * dt
            kickVel.dx *= 0.985
            kickVel.dy *= 0.985
            ball.zRotation += 0.3

            let speedNow = hypot(kickVel.dx, kickVel.dy)
            let offscreen = abs(ball.position.x) > size.width / 2 + 20
                         || ball.position.y > size.height / 2 + 20
            let caught = chasingFielder != nil
                && hypot(ball.position.x - chaseTarget.x, ball.position.y - chaseTarget.y) < 16
            if speedNow < 40 || offscreen || caught {
                phase = .resolving
                let hit = flightIsHit
                showToast(flightMessage,
                          color: hit ? SKColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 1)
                                     : SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
                if caught { ball.removeFromParent(); ballNode = nil }
                run(.wait(forDuration: 1.4)) { [weak self] in self?.finishTry(won: hit) }
            }

        case .idle, .resolving:
            break
        }
    }

    private var lastPulseRate: TimeInterval = 0
    private func pulseKickButtonIfRateChanged(rate: TimeInterval) {
        guard abs(rate - lastPulseRate) > 0.06 else { return }
        lastPulseRate = rate
        pulseKickButton(rate: rate)
    }

    // MARK: - Input

    private var touchStart: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        if let overlay = TutorialOverlay.active(in: self) {
            overlay.advance(); return
        }
        for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        if isPausedGame {
            for n in nodes(at: loc) where n.name == "resumeBtn" { resumeGame(); return }
            return
        }
        if nodes(at: loc).contains(where: { $0.name == "pauseBtn" }) {
            pauseGame(); return
        }
        if confirmingQuit { handleButtonTap(at: loc); return }
        if isGameOver { handleButtonTap(at: loc); return }
        if countdownActive || tutorialUp { return }

        // KICK button — must fire on touch-down for timing feel.
        if phase == .running,
           nodes(at: loc).contains(where: { $0.name == "kickBtn" }) {
            resolveKick(); return
        }

        if handleButtonTap(at: loc) { return }
        touchStart = loc
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let end = touch.location(in: self)

        if isGameOver || isPausedGame || confirmingQuit {
            handleButtonTap(at: end)
            touchStart = nil
            return
        }
        if countdownActive || tutorialUp { touchStart = nil; return }
        guard let start = touchStart else { return }
        touchStart = nil

        let dx = end.x - start.x
        let dy = end.y - start.y

        if hypot(dx, dy) < 12 {
            // Tap: start the run while the pitch is rolling.
            if phase == .pitching { startRun() }
        } else if abs(dx) > abs(dy), phase == .pitching || phase == .running {
            // Horizontal swipe: adjust aim.
            aimAngle = max(-.pi * 0.30, min(.pi * 0.30, aimAngle + dx / size.width * 1.4))
            aimArrow?.zRotation = -aimAngle
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
    }

    @discardableResult
    private func handleButtonTap(at location: CGPoint) -> Bool {
        for node in nodes(at: location) {
            var n: SKNode? = node
            while let current = n {
                switch current.name {
                case "closeButton":
                    showConfirmQuit()
                    return true
                case "confirmQuitBtn":
                    hideConfirmPanel()
                    dismissScene(playerWon: false)
                    return true
                case "cancelQuitBtn":
                    hideConfirmPanel()
                    return true
                case "playAgainBtn":
                    resetForReplay()
                    return true
                case "exitBtn":
                    dismissScene(playerWon: didWin)
                    return true
                default:
                    n = current.parent
                }
            }
        }
        return false
    }

    // MARK: - Game over

    private var didWin = false

    private func triggerGameOver(playerWon: Bool) {
        guard !isGameOver else { return }
        isGameOver = true
        didWin = playerWon
        run(SKAction.playSoundFileNamed(playerWon ? "game_win.wav" : "game_lose.wav",
                                        waitForCompletion: false))
        run(.wait(forDuration: 0.6)) { [weak self] in
            self?.showGameOverPanel(playerWon: playerWon)
        }
    }

    private func showGameOverPanel(playerWon: Bool) {
        messageNode?.removeFromParent()
        let panel = GameResultModal.make(
            sceneSize: size,
            won: playerWon,
            title: playerWon ? "A MIGHTY KICK!" : "THREE TRIES, NO HIT",
            subtitle: playerWon ? "THE CROWD GOES WILD" : "THE BALL WINS AGAIN",
            detail: "FAIR PAST THE INFIELD = HIT",
            hint: playerWon ? nil : ("ARRIVE WITH THE BALL —\nDON'T STOP AND WAIT",
                                     SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1)),
            rewards: [],
            buttons: [GameResultModal.Button(label: "PLAY AGAIN", name: "playAgainBtn", style: .primary),
                      GameResultModal.Button(label: playerWon ? "CONTINUE" : "EXIT",
                                             name: "exitBtn", style: playerWon ? .primary : .danger)])
        addChild(panel)
        messageNode = panel
    }

    private func resetForReplay() {
        messageNode?.removeFromParent()
        messageNode = nil
        ballNode?.removeFromParent()
        ballNode = nil
        currentTry = 0
        isGameOver = false
        didWin = false
        phase = .idle
        triesLabel?.text = "TRY 1 / \(maxTries)"
        // Rebuild defenders in formation (a chaser may have wandered).
        fielders.forEach { $0.removeFromParent() }
        kickerNode?.removeFromParent()
        pitcherNode?.removeFromParent()
        buildCharacters()
        startCountdown()
    }

    // MARK: - Pause

    private func pauseGame() {
        guard !isPausedGame, !isGameOver else { return }
        isPausedGame = true
        pauseBeganAt = currentSceneTime + pauseTimeShift
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
        // Shift the game clock so the pitch doesn't teleport after a pause.
        pauseTimeShift += (currentSceneTime + pauseTimeShift) - pauseBeganAt
    }

    private func showPauseOverlay() {
        let W = size.width, H = size.height
        let ov = SKNode(); ov.zPosition = 5000
        pauseOverlayNode = ov; addChild(ov)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -H / 2, width: W, height: H))
        dim.fillColor = SKColor(white: 0, alpha: 0.65); dim.strokeColor = .clear
        ov.addChild(dim)

        let panelW: CGFloat = min(W - 48, 280), panelH: CGFloat = 160
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2,
                                             width: panelW, height: panelH),
                                cornerRadius: 10)
        panel.fillColor = Parchment.paper.withAlphaComponent(0.97)
        panel.strokeColor = Parchment.edge.withAlphaComponent(0.80)
        panel.lineWidth = 3
        ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "PAUSED"; title.fontSize = 16
        title.fontColor = Parchment.deep
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 40)
        ov.addChild(title)

        let btnW = panelW - 40, btnH: CGFloat = 44
        let resumeBg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2,
                                                width: btnW, height: btnH),
                                   cornerRadius: 8)
        resumeBg.fillColor = Parchment.deep.withAlphaComponent(0.20)
        resumeBg.strokeColor = Parchment.deep.withAlphaComponent(0.80)
        resumeBg.lineWidth = 1.5
        resumeBg.position = CGPoint(x: 0, y: -16)
        resumeBg.name = "resumeBtn"
        ov.addChild(resumeBg)

        let resumeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        resumeLbl.text = "RESUME"; resumeLbl.fontSize = 11
        resumeLbl.fontColor = Parchment.deep
        resumeLbl.horizontalAlignmentMode = .center; resumeLbl.verticalAlignmentMode = .center
        resumeLbl.position = CGPoint(x: 0, y: -1)
        resumeLbl.name = "resumeBtn"
        resumeBg.addChild(resumeLbl)
    }

    // MARK: - Quit confirm

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true

        let W = size.width
        let panelW: CGFloat = min(W - 48, 260), panelH: CGFloat = 150
        let panel = SKNode(); panel.zPosition = 4500
        confirmPanel = panel; addChild(panel)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -size.height / 2,
                                           width: W, height: size.height))
        dim.fillColor = SKColor(white: 0, alpha: 0.60); dim.strokeColor = .clear
        panel.addChild(dim)

        let body = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2,
                                            width: panelW, height: panelH),
                               cornerRadius: 8)
        body.fillColor = Parchment.paper.withAlphaComponent(0.97)
        body.strokeColor = Parchment.edge.withAlphaComponent(0.80)
        body.lineWidth = 2
        panel.addChild(body)

        let q = SKLabelNode(fontNamed: "PressStart2P-Regular")
        q.text = "WAKE UP EARLY?"; q.fontSize = 10
        q.fontColor = Parchment.deep
        q.horizontalAlignmentMode = .center; q.verticalAlignmentMode = .center
        q.position = CGPoint(x: 0, y: 32)
        panel.addChild(q)

        let bw: CGFloat = 90, bh: CGFloat = 36

        let quit = SKShapeNode(rect: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh),
                               cornerRadius: 6)
        quit.fillColor = SKColor(red: 0.65, green: 0.18, blue: 0.18, alpha: 0.95)
        quit.strokeColor = SKColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1)
        quit.lineWidth = 1.5
        quit.position = CGPoint(x: -52, y: -22)
        quit.name = "confirmQuitBtn"
        panel.addChild(quit)
        let qLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        qLbl.text = "QUIT"; qLbl.fontSize = 9; qLbl.fontColor = .white
        qLbl.horizontalAlignmentMode = .center; qLbl.verticalAlignmentMode = .center
        qLbl.name = "confirmQuitBtn"
        quit.addChild(qLbl)

        let cancel = SKShapeNode(rect: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh),
                                 cornerRadius: 6)
        cancel.fillColor = SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 0.95)
        cancel.strokeColor = Parchment.edge.withAlphaComponent(0.80)
        cancel.lineWidth = 1.5
        cancel.position = CGPoint(x: 52, y: -22)
        cancel.name = "cancelQuitBtn"
        panel.addChild(cancel)
        let cLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        cLbl.text = "STAY"; cLbl.fontSize = 9
        cLbl.fontColor = Parchment.deep
        cLbl.horizontalAlignmentMode = .center; cLbl.verticalAlignmentMode = .center
        cLbl.name = "cancelQuitBtn"
        cancel.addChild(cLbl)
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.removeFromParent()
        confirmPanel = nil
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        SceneTransition.iris(in: view, to: prev)
    }
}
