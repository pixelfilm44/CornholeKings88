import SpriteKit
import UIKit

// MARK: - SuburbanJoustersScene
// Backyard bicycle jousting: dirt arena, two cyclists with cornhole-board shields
// and broomstick lances. Player rides the left lane; rival descends the right lane.
// Dual-zone touch: left half pedals/slides shield, right half sweeps lance aim.
// Heart-draining: each crash costs a heart; first to drop the rival's 3 lives wins.

final class SuburbanJoustersScene: SKScene {

    // MARK: - Public contract (mirrors BeeHiveScene)
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    /// True only when launched from the world map / story mode; gates prize display.
    var awardsRewards: Bool = false
    var startingHearts: Int = 5
    private(set) var remainingHearts: Int = 5

    // MARK: - State machine
    private enum JoustState { case startScreen, jousting, crashSequence, roundOver, gameOver }
    private var state: JoustState = .startScreen

    // MARK: - Rider model
    private final class Rider {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var speed: CGFloat = 0
        var lanceAngle: CGFloat = 0
        var shieldOffset: CGFloat = 0
        var lancesLeft: Int = 3
        var lives: Int = 3
        var node: SKNode = SKNode()
        var lanceNode: SKShapeNode?
        var lanceIsBroken: Bool = false
        // tumble kinematics
        var fallVx: CGFloat = 0
        var fallVy: CGFloat = 0
        var fallAv: CGFloat = 0
        var fallAngle: CGFloat = 0
        var riderDetached: Bool = false
        var riderBodyNode: SKNode?
        var boardNode: SKNode?
        var boardVx: CGFloat = 0
        var boardVy: CGFloat = 0
        var boardAv: CGFloat = 0
        var boardAngle: CGFloat = 0
        var boardX: CGFloat = 0
        var boardY: CGFloat = 0
        var boardShadow: SKShapeNode?
        // Pedaling animation
        var legL: SKSpriteNode?
        var legR: SKSpriteNode?
        var pedalPhase: CGFloat = 0
    }

    private let player = Rider()
    private let rival  = Rider()

    // MARK: - Tuning
    private let maxSpeed: CGFloat       = 15.0
    private let pedalIncrement: CGFloat = 1.25
    private let dismountSpeed: CGFloat  = 8.5
    /// Per-frame multiplicative coast when the player isn't pedaling. ~0.985^60 ≈ 0.40,
    /// so a full second of not tapping cuts speed to ~40%.
    private let coastDecay: CGFloat     = 0.985
    /// Speed floor while still pedaling-eligible — keeps the bike from stalling fully.
    private let minCoastSpeed: CGFloat  = 1.5
    /// Player hit window scales with speed — see `currentPlayerHitRadius`. Charging
    /// hard widens the window; coasting tightens it. Rival's window is fixed.
    private let playerHitRadiusMin: CGFloat = 17.0
    private let playerHitRadiusMax: CGFloat = 28.0
    private let rivalHitRadius:  CGFloat = 22.0

    private var currentPlayerHitRadius: CGFloat {
        let span = max(0.01, maxSpeed - dismountSpeed)
        let t = max(0, min(1, (player.speed - dismountSpeed) / span))
        return playerHitRadiusMin + (playerHitRadiusMax - playerHitRadiusMin) * t
    }
    private let crossingOffset: CGFloat = 118.0
    private let lanceLen: CGFloat       = 110.0
    private let baseInwardTilt: CGFloat = 0.3

    // MARK: - Match length
    private let cornholesToWin: Int = 4
    private let maxRounds: Int      = 7
    private var playerCornholes: Int = 0
    private var rivalCornholes: Int  = 0

    private var W: CGFloat = 0
    private var H: CGFloat = 0
    private var confirmingQuit = false
    private var confirmPanel: SKNode?
    private var laneGapHalf: CGFloat = 0   // |player.x| = |rival.x|
    private var playerLaneY: CGFloat = 0
    private var rivalStartY: CGFloat = 0

    // MARK: - Background scroll
    private var bgOffset: CGFloat = 0
    private var dashesNode: SKNode!

    // MARK: - HUD
    private var hudPlayerScoreLbl: SKLabelNode?
    private var hudSpeedLbl: SKLabelNode?
    private var hudRoundLbl: SKLabelNode?
    private var heartsNode: SKNode?
    private var heartLabels: [SKLabelNode] = []
    private var leftHintLbl: SKNode?
    private var rightHintLbl: SKNode?
    private var rivalLivesLbl: SKLabelNode?
    private var reticleLine: SKShapeNode?
    private var reticleDot: SKShapeNode?

    // MARK: - Crash sequence
    private var crashFrames: Int = 0
    private let crashDuration: Int = 110
    private var splinterParent: SKNode!
    private var debrisParent:   SKNode!

    // MARK: - Round state
    private var hitCheckedThisPass: Bool = false
    private var roundResult: (playerHit: Bool, rivalHit: Bool, playerDismounted: Bool, rivalDismounted: Bool) = (false, false, false, false)
    private var roundNumber: Int = 1

    // MARK: - Pre-charge countdown
    /// > 0 means a "READY / 3 / 2 / 1 / CHARGE" windup is running; rival holds at spawn.
    /// Player can pre-set shield/lance and start pedaling during windup.
    private var countdownFrames: Int = 0
    private let countdownTotal: Int = 60 * 3        // 3 seconds at 60fps
    private var countdownLabel: SKLabelNode?

    // MARK: - Speed gate HUD pulse
    private var wasAboveDismountSpeed: Bool = false

    // MARK: - AI difficulty
    private static let fightCountKey = "joustersFightCount_v1"
    /// 0…1. Higher = tighter aim tracking, faster shield dodge, less noise, earlier commit.
    private var aiSkill: CGFloat = 0.35
    private var sessionBoost: CGFloat = 0
    /// Per-pass aim bias — the rival "picks a spot" each round that may be slightly wrong.
    /// Resampled in startRound() from a roughly bell-shaped distribution scaled by (1 - aiSkill).
    private var rivalAimBias: CGFloat = 0
    private var rivalShieldBias: CGFloat = 0

    // MARK: - Pause
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?

    // MARK: - Input tracking
    private var leftActiveTouch:  UITouch?
    private var rightActiveTouch: UITouch?
    private var leftLastX: CGFloat = 0
    private var rightLastX: CGFloat = 0

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        backgroundColor = SKColor(red: 0.573, green: 0.400, blue: 0.278, alpha: 1) // #926647

        remainingHearts = startingHearts
        view.isMultipleTouchEnabled = true

        // Persisted session difficulty bump (mirrors BeeHive's fightCount pattern).
        let fightCount = UserDefaults.standard.integer(forKey: Self.fightCountKey)
        sessionBoost = min(0.18, CGFloat(fightCount) * 0.03)

        computeLayout()
        buildArena()
        buildHUD()
        buildPlayer()
        buildRival(initialSpawn: true)
        addCrtOverlay()

        if TutorialManager.shared.hasSeen(TutorialManager.jousters) {
            startRound()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    private func computeLayout() {
        // Coordinate system: SKScene center anchor.
        // Player: W*0.44 from left in bottom-left convention → x = (0.44-0.5)*W
        // Rival : W*0.56 from left → x = (0.56-0.5)*W
        laneGapHalf  = W * 0.06
        // Player y at H*0.25 from bottom → y = (0.25 - 0.5)*H
        playerLaneY  = -H * 0.25
        // Rival spawn off-screen above
        rivalStartY  = H * 0.5 + 100
    }

    // MARK: - Arena rendering

    private func buildArena() {
        // Grass green strips
        let grass = SKColor(red: 0.133, green: 0.769, blue: 0.369, alpha: 1) // #22C55E
        let leftGrass = SKSpriteNode(color: grass, size: CGSize(width: 16, height: H))
        leftGrass.position  = CGPoint(x: -W / 2 + 8, y: 0)
        leftGrass.zPosition = 1
        addChild(leftGrass)
        let rightGrass = SKSpriteNode(color: grass, size: CGSize(width: 16, height: H))
        rightGrass.position = CGPoint(x: W / 2 - 8, y: 0)
        rightGrass.zPosition = 1
        addChild(rightGrass)

        // Centerline + lane dashes (scrolling container)
        dashesNode = SKNode()
        dashesNode.zPosition = 2
        addChild(dashesNode)

        let dashColor = SKColor(red: 0.733, green: 0.518, blue: 0.337, alpha: 1)
        let dashH: CGFloat = 14
        let dashSpacing: CGFloat = 28
        let numDashes = Int(H / dashSpacing) + 4
        for i in 0..<numDashes {
            let dash = SKSpriteNode(color: dashColor, size: CGSize(width: 3, height: dashH))
            dash.position = CGPoint(x: 0, y: H / 2 - CGFloat(i) * dashSpacing)
            dash.name = "dash"
            dashesNode.addChild(dash)
        }
        // Lane tire-tread lines (player side and rival side)
        for laneSign: CGFloat in [-1, 1] {
            for i in 0..<numDashes {
                let tread = SKSpriteNode(color: dashColor.withAlphaComponent(0.45),
                                         size: CGSize(width: 2, height: 6))
                tread.position = CGPoint(x: laneSign * laneGapHalf,
                                         y: H / 2 - CGFloat(i) * dashSpacing - dashSpacing / 2)
                tread.name = "dash"
                dashesNode.addChild(tread)
            }
        }

        // Fence posts on grass strips
        for laneSign: CGFloat in [-1, 1] {
            for i in 0..<numDashes {
                let post = SKSpriteNode(color: SKColor(white: 0.25, alpha: 1), size: CGSize(width: 4, height: 8))
                post.position = CGPoint(x: laneSign * (W / 2 - 22),
                                        y: H / 2 - CGFloat(i) * dashSpacing)
                post.name = "fence"
                dashesNode.addChild(post)
            }
        }

        // Particle parents
        splinterParent = SKNode(); splinterParent.zPosition = 60; addChild(splinterParent)
        debrisParent   = SKNode(); debrisParent.zPosition   = 50; addChild(debrisParent)
    }

    // MARK: - HUD

    private func buildHUD() {
        let dsPrimary   = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1)
        let dsGold      = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1)
        let dsHeartRed  = SKColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1)
        let dsTimerBlue = SKColor(red: 0.353, green: 0.612, blue: 0.831, alpha: 1)

        let topInset = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let contentY  = H / 2 - topInset - topH / 2

        let bar = SKSpriteNode(color: dsPrimary, size: CGSize(width: W, height: totalTopH))
        bar.position = CGPoint(x: 0, y: H / 2 - totalTopH / 2); bar.zPosition = 500
        addChild(bar)
        let border = SKSpriteNode(color: dsGold, size: CGSize(width: W, height: 2))
        border.position = CGPoint(x: 0, y: H / 2 - totalTopH + 1); border.zPosition = 501
        addChild(border)

        // Zone A: pause
        let pause = SKSpriteNode(imageNamed: "pauseIcon")
        pause.size = CGSize(width: 22, height: 22)
        pause.position = CGPoint(x: -W / 2 + 22, y: contentY); pause.zPosition = 502; pause.name = "pauseBtn"
        addChild(pause)

        // Tutorial help button — just right of pause
        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -W / 2 + 52, y: contentY)
        help.zPosition = 502
        addChild(help)

        // Zone B center: hearts + rival lives indicator
        let totalSlots = max(1, startingHearts)
        let spacing: CGFloat = 16
        let totalW = CGFloat(totalSlots - 1) * spacing
        let hContainer = SKNode()
        hContainer.position = CGPoint(x: -totalW / 2, y: contentY + 7); hContainer.zPosition = 502
        addChild(hContainer); heartsNode = hContainer
        heartLabels.removeAll()
        for i in 0..<totalSlots {
            let h = SKLabelNode(text: "♥")
            h.fontName = "AvenirNext-Heavy"
            h.fontSize = 14
            h.fontColor = dsHeartRed
            h.verticalAlignmentMode = .center; h.horizontalAlignmentMode = .left
            h.position = CGPoint(x: CGFloat(i) * spacing, y: 0)
            hContainer.addChild(h)
            heartLabels.append(h)
        }

        let rivalLbl = makeLabel("YOU \(playerCornholes) / \(cornholesToWin)", size: 8, color: SKColor(red: 0.96, green: 0.84, blue: 0.10, alpha: 1))
        rivalLbl.position = CGPoint(x: 0, y: contentY - 7); rivalLbl.zPosition = 502
        addChild(rivalLbl); rivalLivesLbl = rivalLbl

        // Zone C: close, speed/round below
        let close = SKSpriteNode(imageNamed: "closeIcon")
        close.size = CGSize(width: 22, height: 22)
        close.position = CGPoint(x: W / 2 - 22, y: contentY); close.zPosition = 502; close.name = "closeButton"
        addChild(close)

        let speed = makeLabel("MPH 0", size: 8, color: dsTimerBlue)
        speed.horizontalAlignmentMode = .right
        speed.position = CGPoint(x: W / 2 - 52, y: contentY + 7); speed.zPosition = 502
        addChild(speed); hudSpeedLbl = speed

        let round = makeLabel("R1", size: 8, color: dsGold)
        round.horizontalAlignmentMode = .right
        round.position = CGPoint(x: W / 2 - 52, y: contentY - 7); round.zPosition = 502
        addChild(round); hudRoundLbl = round

        // Reticle (targeting aid) — invisible until first tap
        let line = SKShapeNode()
        line.lineWidth = 1.5; line.strokeColor = SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 0.85)
        line.zPosition = 80
        addChild(line); reticleLine = line

        let dot = SKShapeNode(circleOfRadius: 4)
        dot.lineWidth = 1; dot.strokeColor = SKColor.white.withAlphaComponent(0.85)
        dot.fillColor   = SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 0.65)
        dot.zPosition   = 81
        addChild(dot); reticleDot = dot

        // Bottom-of-screen control hints. Each fades out on first touch in its zone.
        leftHintLbl  = makeHintLabel(text: "TAP HERE FAST\nTO SPEED UP",
                                     at: CGPoint(x: -W * 0.22, y: -H / 2 + 28),
                                     align: .center)
        rightHintLbl = makeHintLabel(text: "DRAG TO\nAIM LANCE",
                                     at: CGPoint(x:  W * 0.22, y: -H / 2 + 28),
                                     align: .center)
    }

    private func makeHintLabel(text: String,
                               at position: CGPoint,
                               align: SKLabelHorizontalAlignmentMode) -> SKNode {
        let container = SKNode()
        container.position = position
        container.zPosition = 90
        let lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            let l = makeLabel(line, size: 9,
                              color: SKColor(red: 0.96, green: 0.84, blue: 0.10, alpha: 0.95))
            l.horizontalAlignmentMode = align
            l.verticalAlignmentMode = .center
            l.position = CGPoint(x: 0, y: CGFloat(lines.count - 1 - i) * 12)
            container.addChild(l)
        }
        container.alpha = 0
        container.run(.fadeAlpha(to: 0.95, duration: 0.4))
        // Gentle pulse so it reads as an active prompt, not chrome.
        let pulse = SKAction.sequence([
            .fadeAlpha(to: 0.55, duration: 0.7),
            .fadeAlpha(to: 0.95, duration: 0.7)
        ])
        container.run(.repeatForever(pulse), withKey: "pulse")
        addChild(container)
        return container
    }

    private func dismissHint(_ node: inout SKNode?) {
        guard let n = node else { return }
        n.removeAction(forKey: "pulse")
        n.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        node = nil
    }

    // MARK: - Countdown + speed-gate HUD

    private func showCountdownLabel(_ text: String) {
        countdownLabel?.removeFromParent()
        let l = makeLabel(text, size: 28, color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        l.position = CGPoint(x: 0, y: H * 0.10)
        l.zPosition = 900
        l.setScale(1.5)
        l.alpha = 0
        addChild(l)
        l.run(.group([
            .fadeAlpha(to: 1, duration: 0.10),
            .scale(to: 1.0, duration: 0.18),
        ]))
        countdownLabel = l
    }

    /// Maps remaining countdown frames into READY / 3 / 2 / 1 / CHARGE beats.
    private func tickCountdownLabel() {
        let remaining = countdownFrames
        let total = countdownTotal
        // Beat boundaries (counting down): READY (full→2/3), 3, 2, 1, CHARGE
        let bands: [(threshold: Int, text: String)] = [
            (total * 4 / 5, "READY?"),
            (total * 3 / 5, "3"),
            (total * 2 / 5, "2"),
            (total * 1 / 5, "1"),
            (0,             "CHARGE!"),
        ]
        let current = bands.first(where: { remaining >= $0.threshold })?.text ?? "CHARGE!"
        if countdownLabel?.text != current {
            showCountdownLabel(current)
        }
        if remaining == 0 {
            // Brief flash on CHARGE then clear.
            countdownLabel?.run(.sequence([
                .scale(to: 1.4, duration: 0.10),
                .group([.scale(to: 0.6, duration: 0.30), .fadeOut(withDuration: 0.30)]),
                .removeFromParent(),
            ]))
            countdownLabel = nil
            run(SKAction.playSoundFileNamed("round_end.wav", waitForCompletion: false))
        }
    }

    /// Colors the MPH label red below the dismount gate, green at/above, with a pulse on cross.
    private func updateSpeedGateColor() {
        let above = player.speed >= dismountSpeed
        let green = SKColor(red: 0.30, green: 0.92, blue: 0.30, alpha: 1)
        let red   = SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1)
        hudSpeedLbl?.fontColor = above ? green : red
        if above != wasAboveDismountSpeed {
            wasAboveDismountSpeed = above
            // Pulse on threshold cross so the player notices.
            hudSpeedLbl?.run(.sequence([
                .scale(to: 1.4, duration: 0.08),
                .scale(to: 1.0, duration: 0.12),
            ]))
        }
    }

    private func makeLabel(_ text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.fontSize = size; l.fontColor = color; l.text = text
        l.horizontalAlignmentMode = .center; l.verticalAlignmentMode = .center
        return l
    }

    // MARK: - Rider construction (procedural pixel art)

    /// Zeroes out all kinematic state that `updateCrash` / `updateFlyingBoard` /
    /// `tumbleRider` use to drive detached parts. Must be called before every
    /// rebuild of a rider's nodes — otherwise stale values from a prior dismount
    /// will animate the freshly-built body or board off-screen on the next pass.
    private func resetRiderRoundState(_ r: Rider) {
        r.fallVx = 0; r.fallVy = 0; r.fallAv = 0; r.fallAngle = 0
        r.boardVx = 0; r.boardVy = 0; r.boardAv = 0; r.boardAngle = 0
        r.boardX = 0; r.boardY = 0
        r.boardShadow?.removeFromParent()
        r.boardShadow = nil
        r.riderDetached = false
    }

    private func buildPlayer() {
        // Reset all per-round / per-build state so leftover values (e.g. a non-zero
        // boardVx from a previous dismount) can't carry into the next round's
        // updateFlyingBoard and yank the fresh board off-screen.
        resetRiderRoundState(player)

        let node = SKNode()
        node.zPosition = 20
        node.position = CGPoint(x: -laneGapHalf, y: playerLaneY)

        // Bike
        let bike = makeBike()
        bike.setScale(2.0)
        node.addChild(bike)

        // Rider body container
        let body = makeRiderBody(capColor: SKColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1), visorUp: true,
                                 boardBorderColor: SKColor(red: 0.18, green: 0.50, blue: 0.92, alpha: 1))
        body.zPosition = 1
        body.setScale(2.0)
        node.addChild(body)

        // Lance — pinned at the rider's right hand on the doubled body.
        // Arms are at body-local (±7, 8) at scale 2 → scene (±14, 16), and the
        // 6-wide arm sprite reaches out to x ≈ 20 — that's where the grip is.
        let lance = makeLance(ribbonColor: SKColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1))
        lance.position = CGPoint(x: 20, y: 16)
        lance.zPosition = 2
        node.addChild(lance)

        player.node = node
        player.x = node.position.x
        player.y = node.position.y
        player.riderBodyNode = body
        player.boardNode = body.childNode(withName: "board")
        player.legL = body.childNode(withName: "legL") as? SKSpriteNode
        player.legR = body.childNode(withName: "legR") as? SKSpriteNode
        player.pedalPhase = 0
        player.lanceNode = lance
        addChild(node)
    }

    private func buildRival(initialSpawn: Bool) {
        // Clear leaked tumble/board kinematics from a previous round before building anew.
        resetRiderRoundState(rival)

        rival.node.removeFromParent()
        rival.node = SKNode()
        rival.node.zPosition = 20
        rival.lanceIsBroken = false
        rival.riderDetached = false
        rival.shieldOffset = 0
        rival.lanceAngle = 0

        let bike = makeBike()
        bike.setScale(2.0)
        rival.node.addChild(bike)

        let body = makeRiderBody(capColor: SKColor(red: 0.58, green: 0.20, blue: 0.82, alpha: 1), visorUp: false,
                                 boardBorderColor: SKColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1))
        body.zPosition = 1
        body.setScale(2.0)
        // Rival faces down — flip 180°
        body.zRotation = .pi
        rival.node.addChild(body)

        // Rival's right shoulder (their right) is at -x relative to their forward (-y).
        // After 180° rotation the body's right is at world -x; pivot at (-12, +10).
        // Mirror of player: rival's right hand is at body-local (-7, 8) but
        // body is rotated π, so the hand ends up at scene (-20, -16) relative to rival.node.
        let lance = makeLance(ribbonColor: SKColor(red: 0.96, green: 0.84, blue: 0.10, alpha: 1))
        lance.position = CGPoint(x: -20, y: -16)
        lance.zPosition = 2
        rival.node.addChild(lance)

        rival.node.position = CGPoint(x: laneGapHalf, y: initialSpawn ? rivalStartY : rivalStartY)
        rival.x = rival.node.position.x
        rival.y = rival.node.position.y
        rival.riderBodyNode = body
        rival.boardNode = body.childNode(withName: "board")
        rival.legL = body.childNode(withName: "legL") as? SKSpriteNode
        rival.legR = body.childNode(withName: "legR") as? SKSpriteNode
        rival.pedalPhase = 0
        rival.lanceNode = lance
        addChild(rival.node)
    }

    private func makeBike() -> SKNode {
        let n = SKNode()
        // Frame bar (vertical, central)
        let frame = SKSpriteNode(color: SKColor(red: 0.216, green: 0.255, blue: 0.318, alpha: 1), // #374151
                                 size: CGSize(width: 3, height: 30))
        frame.position = .zero
        n.addChild(frame)
        // Wheels (thin dark strips with light rim) front/back of frame center along travel axis
        for dy: CGFloat in [-16, 16] {
            let tire = SKSpriteNode(color: SKColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
                                    size: CGSize(width: 5, height: 12))
            tire.position = CGPoint(x: 0, y: dy)
            n.addChild(tire)
            let rim = SKSpriteNode(color: SKColor(white: 0.7, alpha: 1), size: CGSize(width: 3, height: 10))
            rim.position = CGPoint(x: 0, y: dy)
            n.addChild(rim)
        }
        // Handlebars (front yoke crossbar + grips)
        let bars = SKSpriteNode(color: SKColor(red: 0.294, green: 0.337, blue: 0.388, alpha: 1), // #4B5563
                                size: CGSize(width: 18, height: 2))
        bars.position = CGPoint(x: 0, y: 14)
        n.addChild(bars)
        for gx: CGFloat in [-9, 9] {
            let grip = SKSpriteNode(color: SKColor.black, size: CGSize(width: 3, height: 3))
            grip.position = CGPoint(x: gx, y: 14)
            n.addChild(grip)
        }
        return n
    }

    private func makeRiderBody(capColor: SKColor, visorUp: Bool, boardBorderColor: SKColor) -> SKNode {
        let n = SKNode()
        // Torso (blue jersey)
        let torso = SKSpriteNode(color: SKColor(red: 0.290, green: 0.510, blue: 0.722, alpha: 1), // #4A82B8
                                 size: CGSize(width: 16, height: 14))
        torso.position = CGPoint(x: 0, y: -2)
        n.addChild(torso)
        // Legs — pump up/down each frame in updatePedaling, faster with speed.
        let pantColor = SKColor(red: 0.18, green: 0.22, blue: 0.30, alpha: 1) // dark denim
        let legL = SKSpriteNode(color: pantColor, size: CGSize(width: 3, height: 6))
        legL.name = "legL"
        legL.position = CGPoint(x: -3, y: -11)
        n.addChild(legL)
        let legR = SKSpriteNode(color: pantColor, size: CGSize(width: 3, height: 6))
        legR.name = "legR"
        legR.position = CGPoint(x: 3, y: -11)
        n.addChild(legR)
        // Arms splayed to grips
        let armL = SKSpriteNode(color: SKColor(red: 0.290, green: 0.510, blue: 0.722, alpha: 1),
                                size: CGSize(width: 6, height: 3))
        armL.position = CGPoint(x: -7, y: 8); n.addChild(armL)
        let armR = SKSpriteNode(color: SKColor(red: 0.290, green: 0.510, blue: 0.722, alpha: 1),
                                size: CGSize(width: 6, height: 3))
        armR.position = CGPoint(x: 7, y: 8); n.addChild(armR)
        // Head + cap
        let head = SKSpriteNode(color: SKColor(red: 0.92, green: 0.78, blue: 0.62, alpha: 1),
                                size: CGSize(width: 8, height: 8))
        head.position = CGPoint(x: 0, y: 8); n.addChild(head)
        let cap = SKSpriteNode(color: capColor, size: CGSize(width: 9, height: 4))
        cap.position = CGPoint(x: 0, y: 11); n.addChild(cap)
        let visor = SKSpriteNode(color: capColor, size: CGSize(width: 6, height: 2))
        visor.position = CGPoint(x: 0, y: visorUp ? 13 : 9); n.addChild(visor)

        // Chest-strapped triangular cornhole shield (board) — child name "board" for tracking
        let board = SKNode(); board.name = "board"
        board.position = CGPoint(x: 0, y: -2)
        let trip = SKShapeNode(path: makeTrianglePath(width: 32, height: 24))
        trip.fillColor = SKColor(red: 0.831, green: 0.541, blue: 0.333, alpha: 1) // #D48A55
        trip.strokeColor = boardBorderColor
        trip.lineWidth = 1.5
        board.addChild(trip)
        let hole = SKShapeNode(circleOfRadius: 4.5)
        hole.fillColor = .black; hole.strokeColor = .clear
        hole.position = CGPoint(x: 0, y: -2)
        board.addChild(hole)
        n.addChild(board)
        return n
    }

    private func makeTrianglePath(width: CGFloat, height: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: height / 2))
        p.addLine(to: CGPoint(x: -width / 2, y: -height / 2))
        p.addLine(to: CGPoint(x: width / 2, y: -height / 2))
        p.closeSubpath()
        return p
    }

    private func makeLance(ribbonColor: SKColor) -> SKShapeNode {
        // The lance node's local frame has its base at (0,0); shaft extends along +y.
        // The visual angle of the lance is applied via zRotation each frame.
        let lance = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: lanceLen))
        lance.path = path
        lance.lineWidth = 2.5
        lance.strokeColor = SKColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1) // #555555
        lance.lineCap = .square

        // Silver duct-tape tip
        let tip = SKSpriteNode(color: SKColor(red: 0.612, green: 0.639, blue: 0.686, alpha: 1), // #9CA3AF
                               size: CGSize(width: 4, height: 12))
        tip.position = CGPoint(x: 0, y: lanceLen - 4)
        lance.addChild(tip)
        // Warning ribbon
        let ribbon = SKSpriteNode(color: ribbonColor, size: CGSize(width: 5, height: 3))
        ribbon.position = CGPoint(x: 0, y: lanceLen - 10)
        lance.addChild(ribbon)
        return lance
    }

    // MARK: - Round flow

    private func startRound() {
        state = .jousting
        hitCheckedThisPass = false
        roundResult = (false, false, false, false)
        // Start with a coast so the player isn't pedaling from a dead stop while the rival closes.
        player.speed = 4.0
        player.lanceAngle = 0
        player.shieldOffset = 0
        player.lanceIsBroken = false
        // Player tilt visual
        updatePlayerLanceVisual()
        // Reset rival
        buildRival(initialSpawn: true)
        // AI difficulty: ramp by round, on top of persisted session boost.
        let roundBoost = min(0.42, CGFloat(roundNumber - 1) * 0.11)
        aiSkill = max(0.30, min(0.95, 0.35 + sessionBoost + roundBoost))
        // Initial idle pose — small random bias so the rival doesn't start dead-on.
        rival.lanceAngle   = CGFloat.random(in: -0.15...0.15)
        rival.shieldOffset = CGFloat.random(in: -6...6)
        // Per-pass aim error: averaged two uniform draws to approximate a bell.
        // At low skill this is large enough to put the lance well outside the hit radius.
        let lanceErrMag  = (1.0 - aiSkill) * 0.30 + 0.06
        let shieldErrMag = (1.0 - aiSkill) * 22.0 + 4.0
        rivalAimBias    = (CGFloat.random(in: -1...1) + CGFloat.random(in: -1...1)) * 0.5 * lanceErrMag
        rivalShieldBias = (CGFloat.random(in: -1...1) + CGFloat.random(in: -1...1)) * 0.5 * shieldErrMag

        // Per-pass miss roll — the AI sometimes commits to a guaranteed-miss aim.
        // Lance is 110 long, player hit radius 36pt; an angular bias of >=0.40 rad
        // puts the tip ~44pt off-target, outside the player's hit window.
        let missChance: CGFloat = (1.0 - aiSkill) * 0.55 + 0.12
        if CGFloat.random(in: 0...1) < missChance {
            let dir: CGFloat = Bool.random() ? 1 : -1
            rivalAimBias += dir * (0.40 + CGFloat.random(in: 0...0.20))
        }

        // Kick off the pre-charge countdown.
        countdownFrames = countdownTotal
        wasAboveDismountSpeed = false
        showCountdownLabel("READY?")
        updateRivalLanceVisual()
        hudRoundLbl?.text = "R\(roundNumber)/\(maxRounds)"
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !isPausedGame else { return }
        switch state {
        case .startScreen: break
        case .jousting:    updateJousting()
        case .crashSequence: updateCrash()
        case .roundOver, .gameOver: break
        }
    }

    private func updateJousting() {
        // Pre-charge windup: scroll the road, let the player adjust, but the rival hasn't
        // launched yet. Tap-to-pedal still works so you can be at speed when the bell rings.
        if countdownFrames > 0 {
            countdownFrames -= 1
            tickCountdownLabel()
            if leftActiveTouch == nil {
                player.speed = max(minCoastSpeed, player.speed * coastDecay)
            }
            bgOffset += player.speed
            for child in dashesNode.children where (child.name == "dash" || child.name == "fence") {
                child.position.y -= player.speed
                if child.position.y < -H / 2 - 30 { child.position.y += H + 60 }
            }
            updatePlayerLanceVisual()
            applyShieldOffset(rider: player)
            updatePedaling(player)
            updateReticle()
            hudSpeedLbl?.text = "MPH \(Int(player.speed * 3.5))"
            updateSpeedGateColor()
            return
        }

        // Coast: if the player isn't actively pedaling (no finger on the left zone),
        // the bike bleeds speed. Sustained tapping is what keeps you above the
        // dismount-speed gate.
        if leftActiveTouch == nil {
            player.speed = max(minCoastSpeed, player.speed * coastDecay)
        }

        // Scroll background
        bgOffset += player.speed
        for child in dashesNode.children where (child.name == "dash" || child.name == "fence") {
            child.position.y -= player.speed
            if child.position.y < -H / 2 - 30 {
                child.position.y += H + 60
            }
        }

        // Rival descends matched to the player's pace plus a small skill bonus. Tying
        // rival speed to player speed gives the symmetric speed gate below a fair feel:
        // if neither rider has built momentum, neither can dismount the other.
        let approachSpeed = max(player.speed * 0.9 + 1.0 + aiSkill * 0.6, 2.0)
        rival.speed = approachSpeed
        rival.y -= approachSpeed
        updateRivalAI()
        rival.node.position = CGPoint(x: rival.x, y: rival.y)
        // Apply shield + lance visuals
        applyShieldOffset(rider: rival)
        updateRivalLanceVisual()
        applyShieldOffset(rider: player)
        updatePlayerLanceVisual()
        updatePedaling(player)
        updatePedaling(rival)
        updateReticle()

        hudSpeedLbl?.text = "MPH \(Int(player.speed * 3.5))"
        updateSpeedGateColor()

        // Trigger crash check at crossing point
        if !hitCheckedThisPass && rival.y <= player.y + crossingOffset {
            hitCheckedThisPass = true
            evaluateJoust()
        }
        // If rival passes too far without crossing event (should never happen) end round
        if rival.y < player.y - 200 && state == .jousting {
            triggerCrashSequence()
        }
    }

    private func updateCrash() {
        crashFrames += 1
        // Decelerate scroll
        player.speed *= 0.96
        bgOffset += player.speed
        for child in dashesNode.children where (child.name == "dash" || child.name == "fence") {
            child.position.y -= player.speed
            if child.position.y < -H / 2 - 30 {
                child.position.y += H + 60
            }
        }

        // Tumble each detached rider
        tumbleRider(player)
        tumbleRider(rival)
        // Coast riderless bikes off-course
        if player.riderDetached { player.node.position.x -= 0.6 }
        if rival.riderDetached  { rival.node.position.x  += 0.6 }
        // Flying boards
        updateFlyingBoard(player)
        updateFlyingBoard(rival)

        if crashFrames >= crashDuration {
            endRound()
        }
    }

    // MARK: - Rival AI (target-tracking aim + dodge shield)

    /// 0 at rival spawn → 1 at crossing point. Used to time the AI's commitment.
    private func approachProgress() -> CGFloat {
        let crossingY = player.y + crossingOffset
        let span = rivalStartY - crossingY
        guard span > 0 else { return 1 }
        let t = (rivalStartY - rival.y) / span
        return max(0, min(1, t))
    }

    private func updateRivalAI() {
        let t = approachProgress()
        // Commit threshold: high-skill AI starts tracking earlier in the pass.
        let commitStart: CGFloat = 0.35 + (1.0 - aiSkill) * 0.40   // skill 0.95 → 0.37, skill 0.30 → 0.63
        let commitT = max(0, min(1, (t - commitStart) / max(0.05, 1.0 - commitStart)))

        // Noise shrinks with skill and commitment but keeps a permanent floor so the rival is never perfect.
        let lanceNoise  = (1.0 - aiSkill) * (1.0 - commitT * 0.5) * 0.30 + 0.05
        let shieldNoise = (1.0 - aiSkill) * (1.0 - commitT * 0.5) * 14.0 + 3.0

        // ── Aim: solve for the lance angle that puts the tip on the player's hole.
        let playerTargetX = player.x + player.shieldOffset
        let playerTargetY = player.y - 8
        let pivotX = rival.x - 20
        let pivotY = rival.y - 16
        let dx = playerTargetX - pivotX
        let dy = playerTargetY - pivotY
        let absAngle = atan2(dy, dx)
        // updateRivalLanceVisual: zRotation = (-π/2 - baseInwardTilt + rival.lanceAngle) - π/2
        // The tip direction in scene coords ends up as: -π/2 - baseInwardTilt + rival.lanceAngle (rotation + local +y).
        // So lanceAngle = absAngle - (-π/2 - baseInwardTilt) = absAngle + π/2 + baseInwardTilt.
        var desiredLance = absAngle + .pi / 2 + baseInwardTilt
        // Wrap to [-π, π]
        while desiredLance >  .pi { desiredLance -= 2 * .pi }
        while desiredLance < -.pi { desiredLance += 2 * .pi }
        desiredLance += rivalAimBias
        desiredLance = max(-0.6, min(0.6, desiredLance))
        desiredLance += CGFloat.random(in: -lanceNoise...lanceNoise)

        // Approach desired angle at a rate proportional to skill + commit.
        let lanceRate: CGFloat = 0.04 + aiSkill * 0.12 + commitT * 0.10
        rival.lanceAngle += (desiredLance - rival.lanceAngle) * lanceRate
        rival.lanceAngle = max(-0.6, min(0.6, rival.lanceAngle))

        // ── Dodge: slide shield AWAY from where the player's lance tip will hit the rival board's x.
        let pTip = playerLanceTip()
        let relativeTipX = pTip.x - rival.x
        // If the player's tip is currently right of the rival, push the shield left (negative offset), and vice versa.
        var desiredShield = -relativeTipX + rivalShieldBias
        desiredShield = max(-28, min(28, desiredShield))
        desiredShield += CGFloat.random(in: -shieldNoise...shieldNoise)

        // Only meaningfully dodge once committed; before commit, drift gently.
        let shieldRate: CGFloat = commitT > 0
            ? 0.04 + aiSkill * 0.18 + commitT * 0.10
            : 0.02
        let target = commitT > 0 ? desiredShield : CGFloat(0)
        rival.shieldOffset += (target - rival.shieldOffset) * shieldRate
        rival.shieldOffset = max(-28, min(28, rival.shieldOffset))
    }

    // MARK: - Hit math (per spec)

    private struct TipVec { let x: CGFloat; let y: CGFloat }

    private func playerLanceTip() -> TipVec {
        // Pivot in scene coords: player's right hand on doubled body = (player.x + 20, player.y + 16)
        let pivotX = player.x + 20
        let pivotY = player.y + 16
        // Lance base direction is +y (straight up). Inward tilt is toward +x → angle reduced from pi/2.
        let a = .pi / 2 - baseInwardTilt + player.lanceAngle
        return TipVec(x: pivotX + cos(a) * lanceLen, y: pivotY + sin(a) * lanceLen)
    }

    private func rivalLanceTip() -> TipVec {
        // Pivot: rival's right hand on doubled body. Rival faces -y so their "right" is -x.
        let pivotX = rival.x - 20
        let pivotY = rival.y - 16
        // Lance base direction is -y (down). Inward tilt is toward -x → angle decreased further.
        let a = -.pi / 2 - baseInwardTilt + rival.lanceAngle
        return TipVec(x: pivotX + cos(a) * lanceLen, y: pivotY + sin(a) * lanceLen)
    }

    private func evaluateJoust() {
        // Targets are the actual hole positions in scene coords. The hole sits at
        // body-local (0, -4) and the body is at scale 2, so it's ±8 from the
        // rider's scene-Y (negative for the player facing up, positive for the
        // rival facing down). Older code used ±3 here, which left scoring
        // visually off by ~5 px and silently relied on a wide hit radius to mask it.
        let rivalTargetX = rival.x + rival.shieldOffset
        let rivalTargetY = rival.y + 8
        let playerTargetX = player.x + player.shieldOffset
        let playerTargetY = player.y - 8

        let pTip = playerLanceTip()
        let rTip = rivalLanceTip()
        let pDist = hypot(pTip.x - rivalTargetX,  pTip.y - rivalTargetY)
        let rDist = hypot(rTip.x - playerTargetX, rTip.y - playerTargetY)

        let pHitHole = pDist < currentPlayerHitRadius
        let rHitHole = rDist < rivalHitRadius

        var pDismounted = false
        var rDismounted = false
        if pHitHole {
            if player.speed >= dismountSpeed {
                rDismounted = true
                rival.lives = max(0, rival.lives - 1)
            } else {
                // hit but bounce off (no dismount)
                showFloatingLabel("BOUNCE", at: CGPoint(x: rivalTargetX, y: rivalTargetY),
                                  color: SKColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1))
            }
        } else {
            // outside hit radius → strikes plywood, shatters player's lance
            shatterLance(rider: player, atTip: pTip, ribbonColor: SKColor(red: 0.92, green: 0.18, blue: 0.18, alpha: 1))
        }
        if rHitHole {
            // Symmetric speed gate: rival also needs momentum to dismount the player.
            // Below dismountSpeed they ring the board but bounce off without knocking the player down.
            if rival.speed >= dismountSpeed {
                pDismounted = true
            } else {
                showFloatingLabel("BOUNCE", at: CGPoint(x: playerTargetX, y: playerTargetY),
                                  color: SKColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1))
            }
        } else {
            shatterLance(rider: rival, atTip: rTip, ribbonColor: SKColor(red: 0.96, green: 0.84, blue: 0.10, alpha: 1))
        }

        roundResult = (rHitHole, pHitHole, pDismounted, rDismounted)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        screenShake(intensity: 6, duration: 0.25)

        // Freeze-frame for 0.1s then start crash sequence
        state = .crashSequence
        isPausedGame = true
        run(.sequence([
            .wait(forDuration: 0.1),
            .run { [weak self] in
                guard let self = self else { return }
                self.isPausedGame = false
                self.startCrashKinematics(playerDismounted: pDismounted, rivalDismounted: rDismounted)
            },
        ]))
    }

    private func triggerCrashSequence() {
        state = .crashSequence
        startCrashKinematics(playerDismounted: false, rivalDismounted: false)
    }

    private func startCrashKinematics(playerDismounted: Bool, rivalDismounted: Bool) {
        crashFrames = 0

        if playerDismounted {
            detachRider(player, throwingLeftward: true)
            launchBoard(rider: player, vx: -7.5, vy: -13.0)
        }
        if rivalDismounted {
            detachRider(rival, throwingLeftward: false)
            launchBoard(rider: rival, vx: 7.5, vy: -13.0)
        }
        // Heart drain — player crash costs a heart
        if playerDismounted {
            rivalCornholes += 1
            let lostIdx = remainingHearts - 1
            remainingHearts = max(0, remainingHearts - 1)
            updateHeart(lostIdx: lostIdx)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        if rivalDismounted {
            playerCornholes += 1
            rivalLivesLbl?.text = "YOU \(playerCornholes) / \(cornholesToWin)"
        }
    }

    private func detachRider(_ r: Rider, throwingLeftward: Bool) {
        guard !r.riderDetached, let body = r.riderBodyNode else { return }
        r.riderDetached = true
        // Reparent body to scene so it can fly independent of the bike node
        let world = body.parent?.convert(body.position, to: self) ?? body.position
        body.removeFromParent()
        body.position = world
        body.zPosition = 70
        body.setScale(2.0)
        addChild(body)
        r.riderBodyNode = body
        // Launch up + outward so the dismount arcs clearly above the bike before
        // gravity drags the rider down. Without an upward kick the rider just
        // sinks with the road and the toss reads as "fell through the floor."
        r.fallVx = throwingLeftward ? -5.5 : 5.5
        r.fallVy = 7.5
        r.fallAv = throwingLeftward ? -0.22 : 0.22
        r.fallAngle = body.zRotation
    }

    private func tumbleRider(_ r: Rider) {
        guard r.riderDetached, let body = r.riderBodyNode else { return }
        // Gravity dominates; only mild damping on horizontal velocity. Spin keeps
        // its initial energy longer so the tumble reads visually.
        r.fallVx *= 0.985
        r.fallVy -= 0.55                              // gravity
        r.fallAv *= 0.985
        r.fallAngle += r.fallAv
        body.position.x += r.fallVx
        // Only a fraction of road speed drags the rider — they should hang in
        // the air long enough to see the arc, not get yanked straight off-screen.
        body.position.y += r.fallVy - player.speed * 0.35
        body.zRotation = r.fallAngle
        // Dust trail
        if abs(r.fallVx) > 0.4 {
            spawnDust(at: body.position)
        }
    }

    private func launchBoard(rider r: Rider, vx: CGFloat, vy: CGFloat) {
        guard let board = r.boardNode else { return }
        let world = board.parent?.convert(board.position, to: self) ?? board.position
        board.removeFromParent()
        board.position = world
        board.zPosition = 75
        board.setScale(2.0)
        addChild(board)
        r.boardNode = board
        r.boardVx = vx; r.boardVy = vy
        r.boardAv = vx > 0 ? 0.20 : -0.20
        r.boardAngle = 0
        r.boardX = world.x; r.boardY = world.y

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 18, height: 6))
        shadow.fillColor = SKColor.black.withAlphaComponent(0.40)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: world.x, y: world.y - 18)
        shadow.zPosition = 49
        addChild(shadow)
        r.boardShadow = shadow
    }

    private func updateFlyingBoard(_ r: Rider) {
        guard let board = r.boardNode, r.boardVx != 0 || r.boardVy != 0 else { return }
        r.boardVy += 0.22 // gravity (positive y down in spec; in our coords add to downward motion)
        r.boardX += r.boardVx
        r.boardY -= r.boardVy + player.speed * 0.5  // down-screen scaling
        r.boardVx *= 0.97
        r.boardVy *= 0.97
        r.boardAngle += r.boardAv
        board.position = CGPoint(x: r.boardX, y: r.boardY)
        board.zRotation = r.boardAngle
        // Shadow scales with altitude (boardVy magnitude proxy)
        let altitude = max(0, 15 - abs(r.boardVy * 1.5))
        if let sh = r.boardShadow {
            let s = 1.0 + altitude * 0.04
            sh.setScale(s)
            sh.alpha = 0.4 - altitude * 0.018
            sh.position = CGPoint(x: r.boardX, y: r.boardY - 18 - altitude)
        }
        // Bounce when board "lands" on the rider's ground line
        if r.riderDetached, let body = r.riderBodyNode,
           r.boardY < body.position.y - 14, r.boardVy > 0 {
            r.boardVy = -r.boardVy * 0.45
            r.boardVx *= 0.6
            r.boardAv = -r.boardAv * 0.7
        }
    }

    // MARK: - Lance shatter

    private func shatterLance(rider r: Rider, atTip tip: TipVec, ribbonColor: SKColor) {
        guard !r.lanceIsBroken, let lance = r.lanceNode else { return }
        r.lanceIsBroken = true
        r.lancesLeft = max(0, r.lancesLeft - 1)

        // Replace shaft with short jagged stump
        lance.removeAllChildren()
        let stumpPath = CGMutablePath()
        stumpPath.move(to: .zero)
        // jagged zig-zag up to 32
        var y: CGFloat = 0
        var sign: CGFloat = 1
        while y < 32 {
            y += 4
            stumpPath.addLine(to: CGPoint(x: sign * 1.5, y: y))
            sign = -sign
        }
        lance.path = stumpPath

        // Flying broken tip fragment
        let frag = SKNode()
        frag.position = CGPoint(x: tip.x, y: tip.y)
        frag.zPosition = 65
        let shaft = SKSpriteNode(color: SKColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1),
                                 size: CGSize(width: 2.5, height: 30))
        frag.addChild(shaft)
        let tipSilver = SKSpriteNode(color: SKColor(red: 0.612, green: 0.639, blue: 0.686, alpha: 1),
                                     size: CGSize(width: 3, height: 8))
        tipSilver.position = CGPoint(x: 0, y: 13)
        frag.addChild(tipSilver)
        let ribbon = SKSpriteNode(color: ribbonColor, size: CGSize(width: 4, height: 3))
        ribbon.position = CGPoint(x: 0, y: 7)
        frag.addChild(ribbon)
        debrisParent.addChild(frag)

        let isPlayer = (r === player)
        let fvx = (isPlayer ? 3.5 : -3.5) + CGFloat.random(in: -1.0...1.0)
        let fvy = isPlayer ? -4.0 - player.speed : 5.0
        let av  = CGFloat.random(in: 0.12...0.20)
        frag.run(spinAndDriftAction(vx: fvx, vy: fvy, av: av, lifetime: 1.6))

        // Splinter burst
        spawnSplinters(at: CGPoint(x: tip.x, y: tip.y))
        run(SKAction.playSoundFileNamed("round_end.wav", waitForCompletion: false))
    }

    private func spinAndDriftAction(vx: CGFloat, vy: CGFloat, av: CGFloat, lifetime: TimeInterval) -> SKAction {
        var vx = vx, vy = vy
        let step = SKAction.customAction(withDuration: lifetime) { node, _ in
            vx *= 0.96
            vy *= 0.96
            node.position.x += vx
            node.position.y += vy
            node.zRotation += av
        }
        return SKAction.sequence([step, SKAction.fadeOut(withDuration: 0.2), SKAction.removeFromParent()])
    }

    // MARK: - Particles

    private func spawnSplinters(at p: CGPoint) {
        // Broomstick wood + duct tape — deliberately avoids the board's tan #D48A55 so a
        // lance-shatter burst doesn't read as a board explosion. Boards only fly on dismount.
        let colors = [
            SKColor(red: 0.42, green: 0.27, blue: 0.14, alpha: 1), // dark broomstick wood
            SKColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1), // medium wood
            SKColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 1), // weathered shaft
            SKColor(red: 0.75, green: 0.76, blue: 0.78, alpha: 1), // silver duct-tape shred
        ]
        let count = Int.random(in: 15...25)
        for _ in 0..<count {
            let s = SKSpriteNode(color: colors.randomElement()!, size: CGSize(width: 2, height: 2))
            s.position = p
            s.zPosition = 90
            splinterParent.addChild(s)
            var vx = CGFloat.random(in: -6...6)
            var vy = CGFloat.random(in: -6...6)
            let action = SKAction.customAction(withDuration: 0.45) { node, t in
                vx *= 0.92; vy *= 0.92
                node.position.x += vx
                node.position.y += vy
                node.alpha = 1.0 - t / 0.45
            }
            s.run(.sequence([action, .removeFromParent()]))
        }
    }

    private func spawnDust(at p: CGPoint) {
        let dust = SKSpriteNode(color: SKColor(red: 0.45, green: 0.32, blue: 0.21, alpha: 0.6),
                                size: CGSize(width: 3, height: 3))
        dust.position = p
        dust.zPosition = 45
        debrisParent.addChild(dust)
        dust.run(.sequence([
            .group([.fadeOut(withDuration: 0.6), .moveBy(x: 0, y: -4, duration: 0.6)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Visuals: shield + lance + reticle

    /// Pumps the rider's legs alternately up and down. The phase increment is
    /// proportional to `r.speed`, so faster tapping (player) or a faster rival
    /// approach visibly cycles the legs faster.
    private func updatePedaling(_ r: Rider) {
        guard !r.riderDetached, let legL = r.legL, let legR = r.legR else { return }
        // 0.18 rad/frame at speed=1 → at maxSpeed (15) that's ~2.7 rad/frame,
        // a fast blur of pumping that reads clearly without aliasing.
        r.pedalPhase += max(0.02, r.speed * 0.18)
        let amp: CGFloat = 2.5
        let baseY: CGFloat = -11
        legL.position.y = baseY + sin(r.pedalPhase) * amp
        legR.position.y = baseY + sin(r.pedalPhase + .pi) * amp
    }

    private func applyShieldOffset(rider r: Rider) {
        guard let board = r.boardNode, board.parent === r.riderBodyNode else { return }
        // Body is at scale 2, so dividing by 2 puts the board exactly at `shieldOffset`
        // in scene units — matching the collision target math in evaluateJoust.
        // Rival's body has zRotation = π (facing down), so its local +x is world -x;
        // negating keeps "shield slides right of rider" feeling consistent.
        let isPlayer = (r === player)
        board.position.x = (isPlayer ? r.shieldOffset : -r.shieldOffset) / 2.0
    }

    private func updatePlayerLanceVisual() {
        guard let lance = player.lanceNode else { return }
        // Lance's local +y points "out the tip"; rotate so it points along the tip vector.
        let a = .pi / 2 - baseInwardTilt + player.lanceAngle
        lance.zRotation = a - .pi / 2
    }

    private func updateRivalLanceVisual() {
        guard let lance = rival.lanceNode else { return }
        let a = -.pi / 2 - baseInwardTilt + rival.lanceAngle
        // rival.lanceNode lives inside the rival node which is rotated 0; we set absolute rotation.
        lance.zRotation = a - .pi / 2
    }

    private func updateReticle() {
        let tip = playerLanceTip()
        let targetX = rival.x + rival.shieldOffset
        let targetY = rival.y + 8     // must match evaluateJoust's rival hole Y
        let dist = hypot(tip.x - targetX, tip.y - targetY)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: player.x + 20, y: player.y + 16))
        path.addLine(to: CGPoint(x: tip.x, y: tip.y))
        reticleLine?.path = path

        let aligned = dist < currentPlayerHitRadius
        let color: SKColor = aligned
            ? SKColor(red: 0.30, green: 0.92, blue: 0.30, alpha: 0.85)
            : SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 0.85)
        reticleLine?.strokeColor = color
        reticleDot?.position = CGPoint(x: tip.x, y: tip.y)
        reticleDot?.fillColor = color.withAlphaComponent(0.65)
    }

    // MARK: - Round end / game over

    private func endRound() {
        state = .roundOver
        crashFrames = 0
        // Cleanup detached parts for next round
        if player.riderDetached, let body = player.riderBodyNode { body.removeFromParent() }
        if rival.riderDetached,  let body = rival.riderBodyNode  { body.removeFromParent() }
        if let b = player.boardNode, b.parent !== player.riderBodyNode { b.removeFromParent() }
        if let b = rival.boardNode,  b.parent !== rival.riderBodyNode  { b.removeFromParent() }
        player.boardShadow?.removeFromParent(); rival.boardShadow?.removeFromParent()

        // Check end conditions (best of 7).
        if playerCornholes >= cornholesToWin {
            triggerGameOver(playerWon: true);  return
        }
        if rivalCornholes >= cornholesToWin || remainingHearts <= 0 {
            triggerGameOver(playerWon: false); return
        }
        if roundNumber >= maxRounds {
            // Tiebreaker after 7 played rounds: more cornholes wins; exact ties favor the player.
            triggerGameOver(playerWon: playerCornholes >= rivalCornholes); return
        }
        roundNumber += 1
        showRoundSummary { [weak self] in
            self?.player.node.removeFromParent()
            self?.rival.node.removeFromParent()
            self?.buildPlayer()
            self?.startRound()
        }
    }

    /// Mid-game banner shown between rounds. Reports the outcome of the pass and
    /// the running cornhole score, then runs `continuation` to start the next round.
    private func showRoundSummary(then continuation: @escaping () -> Void) {
        let playerScored = roundResult.rivalDismounted
        let rivalScored  = roundResult.playerDismounted

        let title: String
        let titleColor: SKColor
        if playerScored && rivalScored {
            title = "DOUBLE DISMOUNT!"
            titleColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        } else if playerScored {
            title = "YOU CORNHOLED!"
            titleColor = SKColor(red: 0.30, green: 0.92, blue: 0.30, alpha: 1)
        } else if rivalScored {
            title = "RIVAL CORNHOLED!"
            titleColor = SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1)
        } else if roundResult.rivalHit || roundResult.playerHit {
            title = "BOUNCE — NO SPEED"
            titleColor = SKColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1)
        } else {
            title = "BOTH WHIFFED"
            titleColor = SKColor(white: 0.85, alpha: 1)
        }

        let panelW: CGFloat = W * 0.86
        let panelH: CGFloat = 96
        let panel = SKNode()
        panel.zPosition = 1200
        panel.alpha = 0

        let bg = SKSpriteNode(color: SKColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 0.94),
                              size: CGSize(width: panelW, height: panelH))
        panel.addChild(bg)
        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = titleColor
        border.fillColor = .clear
        border.lineWidth = 2
        panel.addChild(border)

        let titleLbl = makeLabel(title, size: 14, color: titleColor)
        titleLbl.position = CGPoint(x: 0, y: 18)
        panel.addChild(titleLbl)

        let scoreLbl = makeLabel("YOU \(playerCornholes)   —   \(rivalCornholes) RIVAL",
                                 size: 9, color: SKColor(white: 0.92, alpha: 1))
        scoreLbl.position = CGPoint(x: 0, y: -6)
        panel.addChild(scoreLbl)

        let nextRound = roundNumber + 1
        let nextLbl = makeLabel("ROUND \(nextRound) / \(maxRounds)  —  FIRST TO \(cornholesToWin)", size: 7,
                                color: SKColor(white: 0.55, alpha: 1))
        nextLbl.position = CGPoint(x: 0, y: -26)
        panel.addChild(nextLbl)

        addChild(panel)

        panel.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 1.4),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
            .run { continuation() },
        ]))
    }

    private func updateHeart(lostIdx: Int) {
        guard lostIdx >= 0, lostIdx < heartLabels.count else { return }
        let lost = heartLabels[lostIdx]
        guard lost.parent != nil else { return }
        lost.run(.sequence([
            .scale(to: 1.4, duration: 0.07),
            .group([.scale(to: 0, duration: 0.14), .fadeOut(withDuration: 0.14)]),
            .removeFromParent(),
        ]))
    }

    private func triggerGameOver(playerWon: Bool) {
        state = .gameOver
        run(SKAction.playSoundFileNamed(playerWon ? "game_win.wav" : "game_lose.wav", waitForCompletion: false))
        run(.sequence([.wait(forDuration: 0.5), .run { [weak self] in self?.showGameOverPanel(won: playerWon) }]))
    }

    private func showGameOverPanel(won: Bool) {
        let tied = playerCornholes == rivalCornholes

        // One-line reason / flavor that depends on how the match ended.
        let reason: String
        if playerCornholes >= cornholesToWin {
            reason = "FIRST TO \(cornholesToWin) — RIVAL TUMBLED"
        } else if rivalCornholes >= cornholesToWin {
            reason = "RIVAL HIT \(cornholesToWin) FIRST"
        } else if remainingHearts <= 0 {
            reason = "OUT OF HEARTS"
        } else {
            reason = "AFTER \(maxRounds) ROUNDS — MOST DISMOUNTS WINS"
        }

        // Reward: the Golden Lance on the first jousting win.
        let rewards: [GameResultModal.Reward] = (awardsRewards && won && !ProgressManager.shared.hasLance)
            ? [GameResultModal.Reward(item: .goldenLance, count: 1, text: "EARNED THE GOLDEN LANCE!")]
            : []

        let headline = tied && won ? "DRAW — YOU EDGE IT"
                                   : (won ? "VICTORY!" : "DEFEAT")
        let panel = GameResultModal.make(
            sceneSize: CGSize(width: W, height: H),
            won: won,
            title: headline,
            subtitle: "DISMOUNTS:  YOU \(playerCornholes)  -  \(rivalCornholes) RIVAL",
            detail: reason,
            rewards: rewards,
            buttons: [GameResultModal.Button(label: "REMATCH", name: "playAgainBtn", style: .primary),
                      GameResultModal.Button(label: "QUIT", name: "exitBtn", style: .danger)])
        addChild(panel)
        pauseOverlayNode = panel
    }

    private func restartGame() {
        // refill hearts on replay-after-loss
        HeartsManager.shared.refill()
        remainingHearts = HeartsManager.shared.currentHearts
        startingHearts  = remainingHearts
        // Tear down and rebuild
        pauseOverlayNode?.removeFromParent(); pauseOverlayNode = nil
        removeAllChildren()
        heartLabels.removeAll()
        rival.lives = 3
        playerCornholes = 0
        rivalCornholes  = 0
        roundNumber = 1
        bgOffset = 0
        // Reset rivers + UI
        buildArena()
        buildHUD()
        buildPlayer()
        buildRival(initialSpawn: true)
        addCrtOverlay()
        startRound()
    }

    // MARK: - Pause overlay

    private func pauseGame() {
        guard !isPausedGame, state == .jousting else { return }
        isPausedGame = true
        let overlay = SKNode(); overlay.zPosition = 1400
        let dim = SKSpriteNode(color: SKColor.black.withAlphaComponent(0.65), size: CGSize(width: W, height: H))
        overlay.addChild(dim)
        let title = makeLabel("PAUSED", size: 18, color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        title.position = CGPoint(x: 0, y: 30); overlay.addChild(title)
        let btnW: CGFloat = W * 0.6, btnH: CGFloat = 40
        let resume = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2, width: btnW, height: btnH), cornerRadius: 6)
        resume.fillColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.25)
        resume.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.9)
        resume.lineWidth = 1.5; resume.position = CGPoint(x: 0, y: -20)
        resume.name = "resumeBtn"; overlay.addChild(resume)
        let rLbl = makeLabel("RESUME", size: 11, color: SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1))
        rLbl.position = resume.position; rLbl.name = "resumeBtn"; overlay.addChild(rLbl)
        addChild(overlay)
        pauseOverlayNode = overlay
    }

    private func resumeGame() {
        isPausedGame = false
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handleTouchBegan(touch) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handleTouchMoved(touch) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handleTouchEnded(touch) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { handleTouchEnded(touch) }
    }

    private func handleTouchBegan(_ touch: UITouch) {
        let loc = touch.location(in: self)

        // Tutorial overlay — any tap advances it.
        if let overlay = TutorialOverlay.active(in: self) { overlay.advance(); return }

        // Help button
        for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        // Pause routing
        if isPausedGame {
            for n in nodes(at: loc) {
                let name = n.name ?? n.parent?.name ?? ""
                if name == "resumeBtn"     { resumeGame(); return }
                if name == "playAgainBtn"  { restartGame(); return }
                if name == "exitBtn"       { dismissScene(playerWon: playerCornholes >= cornholesToWin); return }
            }
            return
        }
        if state == .gameOver {
            for n in nodes(at: loc) {
                let name = n.name ?? n.parent?.name ?? ""
                if name == "playAgainBtn" { restartGame(); return }
                if name == "exitBtn"      { dismissScene(playerWon: playerCornholes >= cornholesToWin); return }
            }
            return
        }

        // Quit-confirm modal consumes all input until resolved.
        if confirmingQuit {
            for n in nodes(at: loc) {
                if QuitConfirmModal.isQuit(n)   { hideConfirmPanel(); dismissScene(playerWon: false); return }
                if QuitConfirmModal.isCancel(n) { hideConfirmPanel(); return }
            }
            return
        }

        // HUD chrome
        if nodes(at: loc).contains(where: { $0.name == "pauseBtn" })    { pauseGame(); return }
        if nodes(at: loc).contains(where: { $0.name == "closeButton" }) { showConfirmQuit(); return }

        // Gameplay only when jousting
        guard state == .jousting else { return }

        // Split zones at scene X = 0 (since anchor 0.5)
        if loc.x < 0 {
            // LEFT zone — pedal click + shield drag
            player.speed = min(maxSpeed, player.speed + pedalIncrement)
            if leftActiveTouch == nil {
                leftActiveTouch = touch
                leftLastX = loc.x
            }
            run(SKAction.playSoundFileNamed("pedal_click.wav", waitForCompletion: false))
            dismissHint(&leftHintLbl)
        } else {
            // RIGHT zone — lance aim drag
            if rightActiveTouch == nil {
                rightActiveTouch = touch
                rightLastX = loc.x
            }
            dismissHint(&rightHintLbl)
        }
    }

    private func handleTouchMoved(_ touch: UITouch) {
        let loc = touch.location(in: self)
        if touch === leftActiveTouch {
            let dx = loc.x - leftLastX
            leftLastX = loc.x
            player.shieldOffset = max(-28, min(28, player.shieldOffset + dx))
        } else if touch === rightActiveTouch {
            let dx = loc.x - rightLastX
            rightLastX = loc.x
            // Right swipe = lance sweeps right (player.lanceAngle increases)
            player.lanceAngle = max(-0.6, min(0.6, player.lanceAngle + dx * 0.01))
        }
    }

    private func handleTouchEnded(_ touch: UITouch) {
        if touch === leftActiveTouch  { leftActiveTouch  = nil }
        if touch === rightActiveTouch { rightActiveTouch = nil }
    }

    // MARK: - Screen shake

    private func screenShake(intensity: CGFloat, duration: TimeInterval) {
        let cam = self.camera ?? {
            let c = SKCameraNode(); c.position = .zero; self.addChild(c); self.camera = c; return c
        }()
        let steps = 6
        var actions: [SKAction] = []
        for _ in 0..<steps {
            let dx = CGFloat.random(in: -intensity...intensity)
            let dy = CGFloat.random(in: -intensity...intensity)
            actions.append(.moveTo(x: dx, duration: duration / Double(steps * 2)))
            actions.append(.moveTo(y: dy, duration: duration / Double(steps * 2)))
        }
        actions.append(.move(to: .zero, duration: 0.05))
        cam.run(.sequence(actions))
    }

    // MARK: - CRT

    private func addCrtOverlay() {
        let w = W, h = H
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(UIColor(white: 0, alpha: 0.24).cgColor)
            var y: CGFloat = 0
            while y < h { c.fill(CGRect(x: 0, y: y, width: w, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let cols = [UIColor(white: 0, alpha: 0).cgColor,
                        UIColor(white: 0, alpha: 0.16).cgColor,
                        UIColor(white: 0, alpha: 0.62).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: space, colors: cols, locations: [0, 0.55, 1.0])!
            c.drawRadialGradient(grad,
                                 startCenter: CGPoint(x: w/2, y: h/2), startRadius: 0,
                                 endCenter:   CGPoint(x: w/2, y: h/2), endRadius: max(w, h) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: w, height: h))
        overlay.position = .zero; overlay.zPosition = 3000
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Tutorial

    private func presentTutorial(autoTriggered: Bool) {
        let W = size.width
        let H = size.height
        let steps: [TutorialStep] = [
            .hint(at: CGPoint(x: -W * 0.25, y: -H * 0.15),
                  title: "LEFT SIDE: PEDAL",
                  body:  "TAP THE LEFT HALF FAST TO PEDAL — SPEED BUILDS WITH EACH TAP. DRAG LEFT OR RIGHT TO SLIDE YOUR SHIELD."),
            .hint(at: CGPoint(x: W * 0.25, y: -H * 0.15),
                  title: "RIGHT SIDE: LANCE",
                  body:  "DRAG ON THE RIGHT HALF TO SWEEP YOUR LANCE. AIM THE TIP AT THE RIVAL'S SHIELD HOLE."),
            .hint(at: CGPoint(x: 0, y: H * 0.10),
                  title: "HIT AT SPEED",
                  body:  "REACH 30+ MPH AND LINE UP YOUR LANCE TIP ON THEIR HOLE TO DISMOUNT. FIRST TO DROP 3 LIVES LOSES!"),
        ]
        if !autoTriggered { isPausedGame = true }
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self = self else { return }
            TutorialManager.shared.markSeen(TutorialManager.jousters)
            if autoTriggered {
                self.startRound()
            } else {
                self.isPausedGame = false
            }
        }
        addChild(overlay)
    }

    // MARK: - Quit Confirmation

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true
        let panel = QuitConfirmModal.make(sceneSize: size)
        addChild(panel)
        confirmPanel = panel
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        confirmPanel = nil
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        let count = UserDefaults.standard.integer(forKey: Self.fightCountKey)
        UserDefaults.standard.set(count + 1, forKey: Self.fightCountKey)
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        SceneTransition.iris(in: view, to: prev)
    }

    // MARK: - Floating label

    private func showFloatingLabel(_ text: String, at pos: CGPoint, color: SKColor) {
        let l = makeLabel(text, size: 10, color: color)
        l.position = pos; l.zPosition = 800; l.alpha = 0
        addChild(l)
        l.run(.sequence([
            .fadeIn(withDuration: 0.08),
            .moveBy(x: 0, y: 30, duration: 0.6),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
        ]))
    }
}
