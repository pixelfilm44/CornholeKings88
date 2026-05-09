import SpriteKit
import UIKit
import SwiftUI

// MARK: - Internal data containers

private final class PitchBag {
    var bx: CGFloat = 0, by: CGFloat = 0
    var vx: CGFloat = 0, vy: CGFloat = 0
    var node: SKSpriteNode = SKSpriteNode()
}

private final class HitBag {
    var bx: CGFloat = 0, by: CGFloat = 0, bz: CGFloat = 0
    var vx: CGFloat = 0, vy: CGFloat = 0, vz: CGFloat = 0
    var isUserHit:   Bool    = true
    var chargeLevel: CGFloat = 0
    var node:   SKSpriteNode = SKSpriteNode()
    var shadow: SKSpriteNode = SKSpriteNode()
}

// MARK: - Scene

/// Portrait-mode "Beanbag Baseball" mini-game.
///
/// Field layout (anchorPoint = 0.5, 0.5):
///   batY     > 0  →  Batter's box at the TOP   (~28 % above centre)
///   pitcherY < 0  →  Pitcher's mound at the BOTTOM (~28 % below centre)
///
/// Pitches travel UPWARD  (+vy).
/// Hit bags travel DOWNWARD (−vy) into the outfield past the pitcher.
///
/// A transparent SwiftUI HUD is injected onto the host SKView in didMove(to:)
/// and removed in willMove(from:) — no changes to GameScene.swift required.
final class CornholeBaseballScene: SKScene {

    // MARK: - Public API
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?

    // MARK: - HUD (SwiftUI overlay, owned by this scene)
    private let hudViewModel = BaseballHUDViewModel()
    private var hudHostingController: UIHostingController<BaseballHUDView>?

    // MARK: - Field layout
    private var batY:     CGFloat = 0   // top  (positive)
    private var pitcherY: CGFloat = 0   // bottom (negative)

    // MARK: - Game phase
    private enum GamePhase {
        case userBatting    // AI pitches from bottom, player swings at top
        case userPitching   // player pitches from bottom, AI swings at top
        case tracking       // camera follows hit bag into outfield
        case gameOver
    }

    // MARK: - Constants
    private let totalCycles    = 3
    private let pitchesPerHalf = 3
    private let gravity: CGFloat   = 0.22
    private let distScale: CGFloat = 0.55  // scene-units → display "ft"

    // MARK: - Game state
    private var phase: GamePhase = .userBatting
    private var currentCycle  = 1
    private var aiPitchCount  = 0
    private var userPitchCount = 0
    private var userDistances: [CGFloat] = []
    private var aiDistances:   [CGFloat] = []

    // Pitch bag
    private var pitchBag:       PitchBag?
    private var pitchInFlight   = false
    private var swingWindowOpen = false
    private var userHasSwung    = false

    // Hit bag
    private var hitBag:    HitBag?
    private var isTracking = false

    // AI batting
    private var aiWillHit    = false
    private var aiSwingFrame = 0
    private var aiFrameCount = 0

    // User pitching gesture
    private var pitchTouchStart: CGPoint?
    private var pitchTouchTime:  TimeInterval = 0

    // Bat charging
    private var isBatCharging        = false
    private var batChargeStartTime:  TimeInterval = 0
    private var currentChargeLevel:  CGFloat = 0

    // AI power swing
    private var aiWillPowerSwing        = false
    private var aiPowerChargeStartTime: TimeInterval = 0

    // Hit-stop (freeze world for ~5 frames on contact)
    private var hitStopEndTime: TimeInterval = 0

    // Fielder mechanics
    private var userFielderNode:    SKSpriteNode!
    private var aiFielderNode:      SKSpriteNode!
    private var userFielderPos:     CGPoint = .zero
    private var aiFielderPos:       CGPoint = .zero
    private var userFielderTarget:  CGPoint = .zero
    private var aiFielderTarget:    CGPoint = .zero
    private var aiFielderMoveDelay:   Int = 0
    private var userFielderMoveDelay: Int = 0
    private var userFielderBoost:     CGFloat = 0
    private let fielderSpeed:         CGFloat = 4.0
    private let fielderCatchRadius:   CGFloat = 30

    // MARK: - Nodes
    private var gameWorldNode: SKEffectNode!
    private var cameraOffset:  SKNode!
    private var batNode:       SKSpriteNode!
    private var aiBatNode:     SKSpriteNode!
    private var strikeZone:    SKShapeNode!
    private var flashLabel:    SKLabelNode!
    private var gameOverPanel: SKNode?
    private var chargeBarBg:   SKSpriteNode!
    private var chargeBarFill: SKSpriteNode!

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        computeLayout()
        setupCameraRig()
        setupGameWorld()
        setupBatter()      // top
        setupPitcher()     // bottom
        setupChargeBar()
        setupFlashLabel()
        setupFielders()
        injectHUD(into: view)
        startUserBatting()
    }

    override func willMove(from view: SKView) {
        hudHostingController?.view.removeFromSuperview()
        hudHostingController = nil
    }

    // MARK: - SwiftUI HUD injection

    private func injectHUD(into view: SKView) {
        let hudView = BaseballHUDView(viewModel: hudViewModel)
        let hc = UIHostingController(rootView: hudView)
        hc.view.backgroundColor = .clear
        hc.view.isUserInteractionEnabled = false   // touches fall through to SKView
        hc.view.frame = view.bounds
        hc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hc.view)
        hudHostingController = hc
        pushHUD()
    }

    // MARK: - Layout

    private func computeLayout() {
        batY     =  size.height * 0.28   // Batter at TOP
        pitcherY = -size.height * 0.28   // Pitcher at BOTTOM
    }

    // MARK: - Scene construction

    private func setupCameraRig() {
        cameraOffset = SKNode()
        addChild(cameraOffset)

        gameWorldNode = SKEffectNode()
        if let f = CIFilter(name: "CIPixellate") {
            f.setValue(2.0, forKey: "inputScale")
            gameWorldNode.filter = f
            gameWorldNode.shouldEnableEffects = true
        }
        gameWorldNode.shouldRasterize = false
        cameraOffset.addChild(gameWorldNode)
    }

    private func setupGameWorld() {
        // Base field colour
        let bg = SKSpriteNode(
            color: SKColor(red: 0.13, green: 0.30, blue: 0.10, alpha: 1),
            size: CGSize(width: size.width * 3, height: size.height * 3))
        bg.zPosition = -200
        gameWorldNode.addChild(bg)

        // Dark-green horizontal mowing stripes
        let stripeH = size.height * 3 / 20
        for i in stride(from: 0, to: 20, by: 2) {
            let stripe = SKSpriteNode(
                color: SKColor(red: 0.10, green: 0.26, blue: 0.09, alpha: 0.42),
                size: CGSize(width: size.width * 3, height: stripeH))
            stripe.position = CGPoint(x: 0,
                                      y: -size.height * 1.5 + CGFloat(i) * stripeH + stripeH * 0.5)
            stripe.zPosition = -199
            gameWorldNode.addChild(stripe)
        }

        // Centre path (pitcher ↔ batter)
        let path = SKSpriteNode(
            color: SKColor(red: 0.48, green: 0.36, blue: 0.20, alpha: 0.38),
            size: CGSize(width: size.width * 0.06, height: abs(batY - pitcherY) * 2.4))
        path.position = CGPoint(x: 0, y: (batY + pitcherY) / 2)
        path.zPosition = -5
        gameWorldNode.addChild(path)

        // Distance marker lines in the outfield (below pitcher, where hit bags land)
        for i in 1...5 {
            let lineY = pitcherY - CGFloat(i) * size.height * 0.38
            let line = SKSpriteNode(
                color: SKColor(white: 0.75, alpha: 0.20),
                size: CGSize(width: size.width * 1.8, height: 1))
            line.position  = CGPoint(x: 0, y: lineY)
            line.zPosition = -4
            gameWorldNode.addChild(line)

            let ftVal = Int(CGFloat(i) * size.height * 0.38 * distScale)
            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text      = "\(ftVal)ft"
            lbl.fontSize  = 5
            lbl.fontColor = SKColor(white: 0.58, alpha: 0.48)
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode   = .center
            lbl.position  = CGPoint(x: size.width * 0.5 + 4, y: lineY)
            lbl.zPosition = -3
            gameWorldNode.addChild(lbl)
        }
    }

    private func setupBatter() {
        // Home plate (top of field)
        let plate = SKSpriteNode(
            color: SKColor(white: 0.88, alpha: 0.85),
            size: CGSize(width: 22, height: 14))
        plate.position  = CGPoint(x: 0, y: batY - 14)
        plate.zPosition = 3
        gameWorldNode.addChild(plate)

        // Batter figure (red = player)
        let batter = SKSpriteNode(
            color: SKColor(red: 0.85, green: 0.22, blue: 0.22, alpha: 1),
            size: CGSize(width: 14, height: 22))
        batter.position  = CGPoint(x: -18, y: batY + 2)
        batter.zPosition = 10
        gameWorldNode.addChild(batter)

        // Bat sprite (player — left side)
        batNode = SKSpriteNode(texture: makeBatTexture(), size: CGSize(width: 52, height: 8))
        batNode.anchorPoint = CGPoint(x: 0.08, y: 0.5)
        batNode.position    = CGPoint(x: -24, y: batY + 4)
        batNode.zPosition   = 12
        gameWorldNode.addChild(batNode)

        // AI bat sprite (right side, mirrored so barrel faces left)
        aiBatNode = SKSpriteNode(texture: makeBatTexture(), size: CGSize(width: 52, height: 8))
        aiBatNode.anchorPoint = CGPoint(x: 0.08, y: 0.5)
        aiBatNode.xScale      = -1
        aiBatNode.position    = CGPoint(x: 24, y: batY + 4)
        aiBatNode.zPosition   = 12
        aiBatNode.isHidden    = true   // hidden until AI is batting
        gameWorldNode.addChild(aiBatNode)

        // Strike-zone indicator
        strikeZone = SKShapeNode(rectOf: CGSize(width: 56, height: 24), cornerRadius: 3)
        strikeZone.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.70)
        strikeZone.fillColor   = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.06)
        strikeZone.lineWidth   = 1.5
        strikeZone.position    = CGPoint(x: 4, y: batY + 4)
        strikeZone.zPosition   = 8
        strikeZone.isHidden    = true
        gameWorldNode.addChild(strikeZone)
    }

    private func makeBatTexture() -> SKTexture {
        let w: CGFloat = 52, h: CGFloat = 8
        UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), false, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }
        // Handle (dark brown)
        ctx.setFillColor(UIColor(red: 0.32, green: 0.16, blue: 0.05, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 2, width: 16, height: 4))
        // Barrel (tan)
        ctx.setFillColor(UIColor(red: 0.72, green: 0.48, blue: 0.20, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 16, y: 0, width: 36, height: 8))
        let tex = SKTexture(image: UIGraphicsGetImageFromCurrentImageContext() ?? UIImage())
        tex.filteringMode = .nearest
        return tex
    }

    private func setupPitcher() {
        // Pitcher's mound (bottom of field)
        let mound = SKShapeNode(ellipseOf: CGSize(width: 26, height: 16))
        mound.fillColor   = SKColor(red: 0.48, green: 0.36, blue: 0.18, alpha: 0.85)
        mound.strokeColor = SKColor(red: 0.35, green: 0.25, blue: 0.10, alpha: 1)
        mound.position    = CGPoint(x: 0, y: pitcherY)
        mound.zPosition   = 5
        gameWorldNode.addChild(mound)

        // Pitcher figure (blue = AI)
        let pitcher = SKSpriteNode(
            color: SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1),
            size: CGSize(width: 14, height: 22))
        pitcher.position  = CGPoint(x: 0, y: pitcherY + 8)
        pitcher.zPosition = 10
        gameWorldNode.addChild(pitcher)
    }

    // MARK: - Fielders (outfield characters)

    private func setupFielders() {
        let startY = pitcherY - 80

        userFielderNode = makeFielderNode(color: SKColor(red: 0.85, green: 0.22, blue: 0.22, alpha: 1))
        userFielderNode.position = CGPoint(x: 26, y: startY)
        userFielderNode.zPosition = 15
        userFielderNode.isHidden = true
        gameWorldNode.addChild(userFielderNode)
        userFielderPos    = userFielderNode.position
        userFielderTarget = userFielderNode.position

        aiFielderNode = makeFielderNode(color: SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1))
        aiFielderNode.position = CGPoint(x: -26, y: startY)
        aiFielderNode.zPosition = 15
        aiFielderNode.isHidden = true
        gameWorldNode.addChild(aiFielderNode)
        aiFielderPos    = aiFielderNode.position
        aiFielderTarget = aiFielderNode.position
    }

    private func makeFielderNode(color: SKColor) -> SKSpriteNode {
        let node = SKSpriteNode(color: color, size: CGSize(width: 15, height: 15))
        return node
    }

    private func resetFielders() {
        let startY = pitcherY - 80

        userFielderPos    = CGPoint(x: 26, y: startY)
        userFielderTarget = userFielderPos
        userFielderNode.position = userFielderPos
        userFielderNode.isHidden = true

        aiFielderPos    = CGPoint(x: -26, y: startY)
        aiFielderTarget = aiFielderPos
        aiFielderNode.position = aiFielderPos
        aiFielderNode.isHidden = true
        aiFielderMoveDelay   = 0
        userFielderMoveDelay = 0
        userFielderBoost     = 0
    }

    // MARK: - Charge bar (scene-space, floats below batter)

    private func setupChargeBar() {
        let barW: CGFloat = 60
        chargeBarBg = SKSpriteNode(
            color: SKColor(white: 0.22, alpha: 0.88),
            size: CGSize(width: barW, height: 8))
        chargeBarBg.anchorPoint = CGPoint(x: 0, y: 0.5)
        chargeBarBg.position    = CGPoint(x: batNode.position.x - barW / 2,
                                          y: batNode.position.y - 28)
        chargeBarBg.zPosition   = 600
        chargeBarBg.isHidden    = true
        addChild(chargeBarBg)

        chargeBarFill = SKSpriteNode(
            color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1),
            size: CGSize(width: 2, height: 6))
        chargeBarFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        chargeBarFill.position    = CGPoint(x: 1, y: 0)
        chargeBarFill.zPosition   = 1
        chargeBarBg.addChild(chargeBarFill)
    }

    private func refreshChargeBar() {
        let maxW: CGFloat = 58
        chargeBarFill.size.width = max(2, maxW * currentChargeLevel)
        // Yellow → red as charge builds
        let g = max(CGFloat(0.12), 0.85 * (1.0 - currentChargeLevel))
        chargeBarFill.color = SKColor(red: 1.0, green: g, blue: 0.08, alpha: 1)
    }

    private func setupFlashLabel() {
        flashLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        flashLabel.fontSize  = max(7, size.width * 0.044)
        flashLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.30, alpha: 1)
        flashLabel.horizontalAlignmentMode = .center
        flashLabel.verticalAlignmentMode   = .center
        flashLabel.position  = .zero
        flashLabel.zPosition = 800
        flashLabel.alpha     = 0
        addChild(flashLabel)
    }

    // MARK: - Game flow

    private func startUserBatting() {
        phase         = .userBatting
        aiPitchCount  = 0
        userHasSwung  = false
        pitchInFlight = false
        isBatCharging = false
        currentChargeLevel = 0
        chargeBarBg.isHidden = true
        batNode.isHidden   = false
        aiBatNode.isHidden = true
        resetBatVisual()
        strikeZone.isHidden = true
        resetFielders()
        animateCamera(to: .zero, duration: 0.30)
        pushHUD()

        run(.wait(forDuration: 1.0)) { [weak self] in self?.throwAIPitch() }
    }

    private func startUserPitching() {
        phase          = .userPitching
        userPitchCount = 0
        pitchInFlight  = false
        isBatCharging  = false
        aiWillPowerSwing = false
        currentChargeLevel = 0
        chargeBarBg.isHidden = true
        batNode.isHidden   = true
        aiBatNode.isHidden = false
        resetBatVisual()
        strikeZone.isHidden = false   // always visible so player can see where to aim
        resetFielders()
        animateCamera(to: .zero, duration: 0.40)
        pushHUD()
        showCentreFlash("YOUR TURN\nTO PITCH!")
    }

    private func afterBattingHalf() {
        run(.wait(forDuration: 0.7)) { [weak self] in self?.startUserPitching() }
    }

    private func afterPitchingHalf() {
        if currentCycle < totalCycles {
            currentCycle += 1
            run(.wait(forDuration: 0.7)) { [weak self] in self?.startUserBatting() }
        } else {
            run(.wait(forDuration: 0.7)) { [weak self] in self?.showGameOver() }
        }
    }

    // MARK: - AI pitch  (bottom → top, +vy)

    private func throwAIPitch() {
        guard phase == .userBatting, aiPitchCount < pitchesPerHalf, pitchBag == nil else { return }

        aiPitchCount  += 1
        pitchInFlight  = false
        swingWindowOpen = false
        userHasSwung    = false
        isBatCharging   = false
        currentChargeLevel = 0
        chargeBarBg.isHidden = true
        resetBatVisual()
        pushHUD()

        let pitch = PitchBag()
        pitch.bx = CGFloat.random(in: -size.width * 0.08 ... size.width * 0.08)
        pitch.by = pitcherY                               // start at BOTTOM
        pitch.vy = +CGFloat.random(in: 5.0 ... 8.5)      // travel UPWARD
        pitch.vx = CGFloat.random(in: -0.15 ... 0.15)  // nearly straight

        pitch.node = makeBagNode(color: SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1), size: 22)
        pitch.node.position  = CGPoint(x: pitch.bx, y: pitch.by)
        pitch.node.zPosition = 25
        pitch.node.setScale(0.45)
        gameWorldNode.addChild(pitch.node)

        pitchBag      = pitch
        pitchInFlight = true
    }

    // MARK: - Player pitch  (swipe up from bottom half → +vy toward AI at top)

    private func launchUserPitch(start: CGPoint, end: CGPoint, elapsed: TimeInterval) {
        guard phase == .userPitching, userPitchCount < pitchesPerHalf, pitchBag == nil else { return }

        let dy = end.y - start.y                              // positive = swiped up
        // Map swipe distance → speed. Dividing elapsed by 16ms normalises to a
        // "units per frame" value; we then scale it down only lightly (/6) so
        // even gentle swipes feel brisk. Floor of 11 keeps the minimum clearly
        // faster than the AI's top speed (~8.5); ceiling of 20 prevents wild
        // physics at very high swipe velocities.
        let rawSpeed   = abs(dy) / max(CGFloat(elapsed) * 1000 / 16.67, 1)
        let pitchSpeed = min(max(rawSpeed / 6.0, 11.0), 20.0)
        let curvature  = (end.x - start.x) / 400.0  // nearly straight

        let pitch = PitchBag()
        pitch.bx = 0
        pitch.by = pitcherY                 // starts at BOTTOM
        pitch.vy = +pitchSpeed              // travels UPWARD
        pitch.vx = curvature

        pitch.node = makeBagNode(color: SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1), size: 22)
        pitch.node.position  = CGPoint(x: pitch.bx, y: pitch.by)
        pitch.node.zPosition = 25
        pitch.node.setScale(0.45)
        gameWorldNode.addChild(pitch.node)

        pitchBag      = pitch
        pitchInFlight = true

        // 35% chance AI tries a power swing
        aiWillPowerSwing = CGFloat.random(in: 0...1) < 0.35
        if aiWillPowerSwing { aiPowerChargeStartTime = CACurrentMediaTime() }

        // AI hit probability: base 65 %, drops further if power-swinging
        let preMissProb: Double = aiWillPowerSwing ? 0.55 : 0.35
        aiWillHit    = Double.random(in: 0...1) > preMissProb
        aiFrameCount = 0
        let travelFrames = max(10, Int((batY - pitcherY) / pitchSpeed))
        aiSwingFrame = max(5, travelFrames - Int.random(in: 2...7))
    }

    // MARK: - Player swing (charge level drives risk & power)

    private func userSwings(chargeLevel: CGFloat) {
        guard phase == .userBatting, swingWindowOpen, !userHasSwung else { return }
        guard let pitch = pitchBag else { return }
        userHasSwung = true

        // Faster swing when fully charged
        let swingDur = max(0.06, 0.18 - Double(chargeLevel) * 0.10)
        batNode.removeAllActions()
        batNode.run(.sequence([
            .rotate(toAngle: -.pi * 0.5, duration: swingDur),
            .rotate(toAngle: 0,           duration: swingDur * 2),
        ]))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Swinging at a pitch outside the strike zone is an automatic miss
        let szCentre = strikeZone.position
        var pitchNearZone = false
        for frame in 0...12 {
            let projX = pitch.bx + pitch.vx * CGFloat(frame)
            let projY = pitch.by + pitch.vy * CGFloat(frame)
            if abs(projX - szCentre.x) < 32 && abs(projY - szCentre.y) < 16 {
                pitchNearZone = true; break
            }
        }
        if !pitchNearZone {
            removePitchBag()
            strikeZone.strokeColor = SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8)
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.strikeZone.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.7)
            }
            spawnFloatingText("SWINGING STRIKE!", at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(red: 1, green: 0.18, blue: 0.18, alpha: 1))
            run(.wait(forDuration: 0.85)) { [weak self] in
                self?.userDistances.append(0)
                self?.checkBattingHalfDone()
            }
            return
        }

        // Risk/reward: higher charge → up to 60 % whiff chance, but 80 % power bonus on contact
        let whiffProb = chargeLevel * 0.6
        if CGFloat.random(in: 0...1) < whiffProb {
            strikeZone.strokeColor = SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8)
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.strikeZone.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.7)
            }
            spawnFloatingText("WHIFF!", at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(white: 0.65, alpha: 1))
            run(.wait(forDuration: 0.85)) { [weak self] in
                self?.userDistances.append(0)
                self?.checkBattingHalfDone()
            }
            return
        }

        // Contact quality — look-ahead over 12 frames so the player doesn't need
        // split-second timing. The bag moves ~6-8 pts/frame, so checking the next
        // 12 frames gives ~0.2 s of forgiveness for releasing early.
        // Bounds are intentionally generous (wider than the visible zone) because
        // pixel-perfect accuracy against a moving bag feels unfair.
        var quality: CGFloat = 0.0
        for frame in 0...12 {
            let projX = pitch.bx + pitch.vx * CGFloat(frame)
            let projY = pitch.by + pitch.vy * CGFloat(frame)
            let dx = abs(projX - szCentre.x)
            let dy = abs(projY - szCentre.y)
            if dx < 32 && dy < 26      { quality = 1.00; break }
            else if dx < 48 && dy < 38 { quality = max(quality, 0.60) }
        }

        removePitchBag()

        if quality > 0 {
            // Hit-stop: snap bat to contact point, freeze world ~5 frames
            batNode.removeAllActions()
            batNode.zRotation = -.pi * 0.35
            triggerHitStop()
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.batNode.run(.rotate(toAngle: 0, duration: 0.18))
            }

            let label: String
            if chargeLevel > 0.5 && quality > 0.8 { label = "CRACK!" }
            else if quality > 0.85                 { label = "CRACK!" }
            else                                   { label = "GOOD HIT!" }
            spawnFloatingText(label, at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(red: 1, green: 0.88, blue: 0.2, alpha: 1))
            launchHitBag(from: CGPoint(x: pitch.bx, y: batY + 4),
                         quality: quality, chargeLevel: chargeLevel, isUser: true)
        } else {
            strikeZone.strokeColor = SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8)
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.strikeZone.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.7)
            }
            spawnFloatingText("MISS!", at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(red: 1, green: 0.28, blue: 0.28, alpha: 1))
            run(.wait(forDuration: 0.85)) { [weak self] in
                self?.userDistances.append(0)
                self?.checkBattingHalfDone()
            }
        }
    }

    // MARK: - AI swing

    private func aiSwings(pitch: PitchBag) {
        let aiCharge: CGFloat = aiWillPowerSwing
            ? min(CGFloat(CACurrentMediaTime() - aiPowerChargeStartTime), 1.0)
            : 0
        aiWillPowerSwing = false

        // Recalculate hit chance using actual final charge (higher charge = riskier)
        let missProb = 0.35 + Double(aiCharge) * 0.45
        aiWillHit    = Double.random(in: 0...1) > missProb

        removePitchBag()

        if aiWillHit {
            aiBatNode.removeAllActions()
            aiBatNode.zRotation = .pi * 0.35
            triggerHitStop()
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.aiBatNode.run(.rotate(toAngle: 0, duration: 0.18))
            }
            let quality = CGFloat.random(in: 0.35 ... 1.0)
            launchHitBag(from: CGPoint(x: pitch.bx, y: batY),
                         quality: quality, chargeLevel: aiCharge, isUser: false)
        } else {
            let swingDur: Double = aiCharge > 0.4 ? 0.07 : 0.13
            aiBatNode.removeAllActions()
            aiBatNode.run(.sequence([
                .rotate(toAngle: .pi * 0.5, duration: swingDur),
                .rotate(toAngle: 0,          duration: swingDur * 2),
            ]))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let label = aiCharge > 0.4 ? "AI WHIFF!" : "BOT WHIFFS!"
            spawnFloatingText(label, at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(white: 0.58, alpha: 1))
            run(.wait(forDuration: 0.90)) { [weak self] in
                self?.aiDistances.append(0)
                self?.checkPitchingHalfDone()
            }
        }
    }

    // MARK: - Hit-stop

    private func triggerHitStop() {
        hitStopEndTime       = CACurrentMediaTime() + 5.0 / 60.0  // ≈5 frames at 60 fps
        gameWorldNode.speed  = 0   // pause all child SKActions (bat swing, bag movement)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Hit bag launch (always fires DOWNWARD, −vy, into outfield past pitcher)

    private func launchHitBag(from origin: CGPoint,
                               quality: CGFloat,
                               chargeLevel: CGFloat,
                               isUser: Bool) {
        let chargeMult = 1.0 + chargeLevel * 0.8          // up to 1.8× power at full charge
        let power  = quality * CGFloat.random(in: 0.88...1.12) * chargeMult
        let baseVY = size.height * 0.009 * power

        let hit = HitBag()
        hit.bx          = origin.x
        hit.by          = origin.y
        hit.bz          = 4.0
        hit.vy          = -baseVY                          // DOWNWARD into outfield
        hit.vx          = CGFloat.random(in: -baseVY * 0.28 ... baseVY * 0.28)
        hit.vz          = 10.0 * power
        hit.isUserHit   = isUser
        hit.chargeLevel = chargeLevel

        // Hit bag matches the pitcher's color: AI pitches blue, user pitches red.
        // isUser=true means user batted (AI pitched blue); isUser=false means AI batted (user pitched red).
        hit.node = makeBagNode(
            color: isUser ? SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1)
                          : SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1),
            size: 28)
        hit.node.position  = CGPoint(x: hit.bx, y: hit.by)
        hit.node.zPosition = 30
        gameWorldNode.addChild(hit.node)

        hit.shadow = SKSpriteNode(color: .black, size: CGSize(width: 28, height: 18))
        hit.shadow.alpha     = 0.35
        hit.shadow.zPosition = 6
        gameWorldNode.addChild(hit.shadow)

        hitBag     = hit
        isTracking = true
        phase      = .tracking

        if isUser {
            // AI fielder auto-moves to predicted landing, with a reaction delay and aim error
            aiFielderNode.isHidden = false
            let landing = predictLandingPoint(vx: hit.vx, vy: hit.vy, vz: hit.vz,
                                              bx: hit.bx, by: hit.by, bz: hit.bz)
            let err = CGFloat.random(in: -38...38)
            aiFielderTarget    = CGPoint(x: landing.x + err, y: landing.y + err * 0.4)
            aiFielderMoveDelay = 20
        } else {
            // User fielder auto-runs to predicted landing; tapping sprints
            userFielderNode.isHidden = false
            let landing = predictLandingPoint(vx: hit.vx, vy: hit.vy, vz: hit.vz,
                                              bx: hit.bx, by: hit.by, bz: hit.bz)
            let err = CGFloat.random(in: -30...30)
            userFielderTarget    = CGPoint(x: landing.x + err, y: landing.y + err * 0.4)
            userFielderMoveDelay = 15
            showCentreFlash("TAP TO\nSPRINT!")
        }
    }

    // MARK: - Physics update

    override func update(_ currentTime: TimeInterval) {
        // Resume world after hit-stop timer.
        // IMPORTANT: hitStopEndTime is a CACurrentMediaTime() wall-clock value,
        // so we must compare against CACurrentMediaTime(), NOT the SpriteKit
        // scene-relative `currentTime` — those two clocks are in completely
        // different ranges and mixing them causes a permanent freeze.
        let wallNow = CACurrentMediaTime()
        if wallNow < hitStopEndTime { return }
        if gameWorldNode.speed == 0 {
            gameWorldNode.speed = 1
            // Let the swing action finish naturally; don't force-reset zRotation here
        }

        // Keep charge level in sync every frame
        if isBatCharging {
            let elapsed = CACurrentMediaTime() - batChargeStartTime
            currentChargeLevel = min(CGFloat(elapsed), 1.0)
            refreshChargeBar()
            // Bat tint: golden-yellow → red as charge fills
            let g = max(CGFloat(0.12), 0.85 * (1.0 - currentChargeLevel))
            batNode.color            = SKColor(red: 1.0, green: g, blue: 0.08, alpha: 1)
            batNode.colorBlendFactor = 0.65
        }

        updatePitchBag()
        updateHitBag()
        updateFielders()
    }

    private func updateFielders() {
        // AI fielder: waits for reaction delay then moves toward predicted landing
        if !aiFielderNode.isHidden {
            if aiFielderMoveDelay > 0 {
                aiFielderMoveDelay -= 1
            } else {
                let dx = aiFielderTarget.x - aiFielderPos.x
                let dy = aiFielderTarget.y - aiFielderPos.y
                let d  = hypot(dx, dy)
                if d > 1 {
                    let step = min(fielderSpeed, d)
                    aiFielderPos.x += dx / d * step
                    aiFielderPos.y += dy / d * step
                    aiFielderNode.position = aiFielderPos
                }
            }
        }

        // User fielder: auto-runs to predicted landing; tapping adds a speed burst
        if !userFielderNode.isHidden {
            if userFielderMoveDelay > 0 {
                userFielderMoveDelay -= 1
            } else {
                let dx = userFielderTarget.x - userFielderPos.x
                let dy = userFielderTarget.y - userFielderPos.y
                let d  = hypot(dx, dy)
                if d > 1 {
                    let speed = fielderSpeed + userFielderBoost
                    let step  = min(speed, d)
                    userFielderPos.x += dx / d * step
                    userFielderPos.y += dy / d * step
                    userFielderNode.position = userFielderPos
                }
            }
            userFielderBoost = max(0, userFielderBoost - 0.18)
        }
    }

    private func predictLandingPoint(vx: CGFloat, vy: CGFloat, vz: CGFloat,
                                      bx: CGFloat, by: CGFloat, bz: CGFloat) -> CGPoint {
        var px = bx, py = by, pz = bz
        var pvx = vx, pvy = vy, pvz = vz
        for _ in 0..<600 {
            pvz -= gravity
            px += pvx; py += pvy; pz += pvz
            pvx *= 0.997; pvy *= 0.997
            if pz <= 0 { break }
        }
        return CGPoint(x: px, y: py)
    }

    private func updatePitchBag() {
        guard let pitch = pitchBag, pitchInFlight else { return }

        pitch.bx += pitch.vx
        pitch.by += pitch.vy          // positive = moves upward toward batter
        pitch.node.position = CGPoint(x: pitch.bx, y: pitch.by)

        // Perspective scale: bag grows from 0.45× (at pitcher, bottom) to 1.55× (at batter, top)
        let totalDist = batY - pitcherY           // positive span
        let traveled  = pitch.by - pitcherY       // how far up from pitcher (0 → totalDist)
        let t = max(0, min(1, traveled / totalDist))
        pitch.node.setScale(0.45 + t * 1.10)

        if phase == .userBatting {
            // Swing window: bag is within 12 % of the batter's Y
            let distToBat = batY - pitch.by   // positive while approaching, negative after passing
            if distToBat < size.height * 0.12 {
                swingWindowOpen     = true
                strikeZone.isHidden = false
            }
            // Bag overshot batter → auto-strike
            if distToBat < -size.height * 0.05 {
                swingWindowOpen     = false
                pitchInFlight       = false
                strikeZone.isHidden = true
                removePitchBag()
                if !userHasSwung {
                    spawnFloatingText("STRIKE!", at: CGPoint(x: 0, y: batY + 22),
                                      color: SKColor(red: 1, green: 0.18, blue: 0.18, alpha: 1))
                    run(.wait(forDuration: 0.85)) { [weak self] in
                        self?.userDistances.append(0)
                        self?.checkBattingHalfDone()
                    }
                }
            }

        } else if phase == .userPitching {
            aiFrameCount += 1
            let distToAI = batY - pitch.by
            let inZone   = abs(pitch.bx - strikeZone.position.x) < 29  // half-width of strike zone

            // Pitch reached batter area — check zone before letting AI swing
            if aiFrameCount >= aiSwingFrame && distToAI < size.height * 0.10 {
                pitchInFlight = false
                if inZone {
                    let p = pitch
                    userPitchCount += 1
                    pushHUD()
                    aiSwings(pitch: p)
                } else {
                    // 25% chance AI chases a ball outside the zone — always misses
                    if CGFloat.random(in: 0...1) < 0.25 {
                        userPitchCount += 1
                        pushHUD()
                        removePitchBag()
                        spawnFloatingText("BOT SWINGS WILD!", at: CGPoint(x: pitch.bx, y: batY + 22),
                                          color: SKColor(white: 0.58, alpha: 1))
                        run(.wait(forDuration: 0.90)) { [weak self] in
                            self?.aiDistances.append(0)
                            self?.checkPitchingHalfDone()
                        }
                    } else {
                        removePitchBag()
                        spawnFloatingText("BALL!", at: CGPoint(x: pitch.bx, y: batY + 22),
                                          color: SKColor(red: 1, green: 0.85, blue: 0.22, alpha: 1))
                        run(.wait(forDuration: 0.85)) { [weak self] in self?.pushHUD() }
                    }
                }
                return
            }
            // Pitch sailed past AI batter without triggering swing window
            if pitch.by > batY + size.height * 0.08 {
                pitchInFlight = false
                removePitchBag()
                if inZone {
                    // Called strike — pitch counts, AI took it
                    userPitchCount += 1
                    pushHUD()
                    spawnFloatingText("CALLED STRIKE!", at: CGPoint(x: 0, y: batY + 22),
                                      color: SKColor(red: 1, green: 0.85, blue: 0.22, alpha: 1))
                    run(.wait(forDuration: 0.85)) { [weak self] in
                        self?.aiDistances.append(0)
                        self?.checkPitchingHalfDone()
                    }
                } else {
                    spawnFloatingText("BALL!", at: CGPoint(x: 0, y: batY + 22),
                                      color: SKColor(red: 1, green: 0.85, blue: 0.22, alpha: 1))
                    run(.wait(forDuration: 0.85)) { [weak self] in self?.pushHUD() }
                }
            }
        }
    }

    private func updateHitBag() {
        guard isTracking, let hit = hitBag else { return }

        // Integrate manual physics
        hit.vz -= gravity
        hit.bx += hit.vx
        hit.by += hit.vy          // negative = downward into outfield
        hit.bz  = max(0, hit.bz + hit.vz)
        hit.vx *= 0.997
        hit.vy *= 0.997

        let visualY = hit.by + hit.bz * 0.55
        hit.node.position   = CGPoint(x: hit.bx, y: visualY)
        hit.shadow.position = CGPoint(x: hit.bx + hit.bz * 0.05, y: hit.by)

        let heightScale = 1.0 + hit.bz * 0.010
        hit.node.setScale(heightScale)
        hit.shadow.alpha   = max(0.05, 0.35 - hit.bz * 0.006)
        hit.shadow.setScale(max(0.4, 1.0 - hit.bz * 0.005))
        hit.node.zPosition = 30 + hit.bz * 0.1

        // Camera pans DOWN to follow bag into outfield
        let targetX = -hit.bx * 0.65
        let targetY = -visualY + size.height * 0.08   // push world up so bag stays on-screen
        cameraOffset.position.x += (targetX - cameraOffset.position.x) * 0.07
        cameraOffset.position.y += (targetY - cameraOffset.position.y) * 0.07

        // Landing
        if hit.bz <= 0 && hit.vz <= 0 {
            hit.bz = 0; hit.vx = 0; hit.vy = 0
            isTracking = false

            let dist  = hypot(hit.bx, hit.by - batY)
            let ftVal = Int(dist * distScale)

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showLandingEffect(at: CGPoint(x: hit.bx, y: hit.by))

            if hit.isUserHit {
                let caught = hypot(hit.bx - aiFielderPos.x, hit.by - aiFielderPos.y) < fielderCatchRadius
                if caught {
                    userDistances.append(0)
                    pushHUD()
                    spawnFloatingText("OUT!", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 0.35, green: 1.0, blue: 0.35, alpha: 1))
                } else {
                    userDistances.append(dist)
                    pushHUD()
                    spawnFloatingText("\(ftVal)FT!", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 1, green: 0.85, blue: 0.28, alpha: 1))
                }
                run(.wait(forDuration: 1.4)) { [weak self] in
                    self?.cleanupHitBag()
                    self?.resetFielders()
                    self?.animateCamera(to: .zero, duration: 0.45)
                    self?.checkBattingHalfDone()
                }
            } else {
                let caught = hypot(hit.bx - userFielderPos.x, hit.by - userFielderPos.y) < fielderCatchRadius
                if caught {
                    aiDistances.append(0)
                    pushHUD()
                    spawnFloatingText("OUT!", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 1, green: 0.38, blue: 0.38, alpha: 1))
                } else {
                    aiDistances.append(dist)
                    pushHUD()
                    spawnFloatingText("BOT \(ftVal)FT!", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1))
                }
                run(.wait(forDuration: 1.4)) { [weak self] in
                    self?.cleanupHitBag()
                    self?.resetFielders()
                    self?.animateCamera(to: .zero, duration: 0.45)
                    self?.checkPitchingHalfDone()
                }
            }
        }
    }

    // MARK: - Half-inning advancement

    private func checkBattingHalfDone() {
        if aiPitchCount >= pitchesPerHalf {
            afterBattingHalf()
        } else {
            // Restore phase so throwAIPitch()'s guard (phase == .userBatting) passes.
            // Without this, any path through .tracking (a player hit) leaves the phase
            // stuck and the next AI pitch never fires.
            phase = .userBatting
            run(.wait(forDuration: 0.55)) { [weak self] in self?.throwAIPitch() }
        }
    }

    private func checkPitchingHalfDone() {
        if userPitchCount >= pitchesPerHalf {
            afterPitchingHalf()
        } else {
            // Restore phase so the player's swipe-up gesture is accepted again.
            // Without this, any path through .tracking (an AI hit) leaves the phase
            // stuck and touchesBegan's .userPitching case never matches.
            phase = .userPitching
            pushHUD()
        }
    }

    // MARK: - Cleanup helpers

    private func removePitchBag() {
        pitchBag?.node.removeFromParent()
        pitchBag        = nil
        swingWindowOpen = false
        // Keep zone visible during user-pitching so the player can still see where to aim
        if phase != .userPitching {
            strikeZone.isHidden = true
        }
    }

    private func cleanupHitBag() {
        hitBag?.node.removeFromParent()
        hitBag?.shadow.removeFromParent()
        hitBag = nil
    }

    private func resetBatVisual() {
        batNode.removeAllActions()
        batNode.zRotation        = 0
        batNode.color            = .white
        batNode.colorBlendFactor = 0
        aiBatNode.removeAllActions()
        aiBatNode.zRotation = 0
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)
        if handleButtonTap(at: loc) { return }

        switch phase {
        case .userBatting:
            // Hold to begin charging
            if !isBatCharging && !userHasSwung {
                isBatCharging        = true
                batChargeStartTime   = CACurrentMediaTime()
                currentChargeLevel   = 0
                chargeBarBg.isHidden = false
                refreshChargeBar()
            }

        case .userPitching:
            // Only accept swipe starts from the bottom half of the scene
            if loc.y < 0 {
                pitchTouchStart = loc
                pitchTouchTime  = touch.timestamp
            }

        case .tracking:
            // Tap anywhere to sprint: each tap adds a speed burst to the user fielder
            if let hit = hitBag, !hit.isUserHit, isTracking {
                userFielderBoost = min(userFielderBoost + 2.8, 9.0)
                showTapIndicator(at: userFielderPos)
            }

        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        // Release charge → swing
        if phase == .userBatting && isBatCharging {
            isBatCharging        = false
            chargeBarBg.isHidden = true
            resetBatVisual()
            userSwings(chargeLevel: currentChargeLevel)
            return
        }

        // Release swipe → pitch (must be an upward gesture)
        if phase == .userPitching, let start = pitchTouchStart {
            let end     = touch.location(in: self)
            let elapsed = max(0.05, touch.timestamp - pitchTouchTime)
            if end.y - start.y > 20 {   // only upward swipes count
                launchUserPitch(start: start, end: end, elapsed: elapsed)
            }
            pitchTouchStart = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isBatCharging {
            isBatCharging        = false
            chargeBarBg.isHidden = true
            resetBatVisual()
        }
        pitchTouchStart = nil
    }

    @discardableResult
    private func handleButtonTap(at loc: CGPoint) -> Bool {
        for node in nodes(at: loc) {
            var n: SKNode? = node
            while let cur = n {
                switch cur.name {
                case "closeButton":   dismissScene(playerWon: false); return true
                case "playAgainBtn":  resetGame();                     return true
                case "exitBtn":       dismissScene(playerWon: userAvg >= aiAvg); return true
                default:              n = cur.parent
                }
            }
        }
        return false
    }

    // MARK: - Camera

    private func animateCamera(to offset: CGPoint, duration: TimeInterval) {
        cameraOffset.removeAction(forKey: "cam")
        cameraOffset.run(.move(to: offset, duration: duration), withKey: "cam")
    }

    // MARK: - Visual effects

    private func showLandingEffect(at pos: CGPoint) {
        let burst = SKSpriteNode(
            color: SKColor(red: 1, green: 0.88, blue: 0.25, alpha: 0.9),
            size: CGSize(width: 32, height: 32))
        burst.position  = pos
        burst.zPosition = 50
        gameWorldNode.addChild(burst)
        burst.run(.sequence([
            .group([.scale(to: 2.6, duration: 0.20), .fadeOut(withDuration: 0.28)]),
            .removeFromParent(),
        ]))
    }

    private func showTapIndicator(at pos: CGPoint) {
        let ring = SKShapeNode(ellipseOf: CGSize(width: 14, height: 14))
        ring.strokeColor = SKColor(red: 0.85, green: 0.22, blue: 0.22, alpha: 0.85)
        ring.fillColor   = .clear
        ring.lineWidth   = 1.5
        ring.position    = pos
        ring.zPosition   = 60
        gameWorldNode.addChild(ring)
        ring.run(.sequence([
            .wait(forDuration: 0.5),
            .fadeOut(withDuration: 0.2),
            .removeFromParent(),
        ]))
    }

    /// Spawns a floating world-space text label that drifts upward and fades out.
    private func spawnFloatingText(_ text: String, at worldPos: CGPoint, color: SKColor) {
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text      = text
        lbl.fontSize  = max(8, size.width * 0.050)
        lbl.fontColor = color
        lbl.position  = worldPos
        lbl.zPosition = 200
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode   = .center

        // Pixel shadow
        let shadow = SKLabelNode(fontNamed: "PressStart2P-Regular")
        shadow.text      = text
        shadow.fontSize  = lbl.fontSize
        shadow.fontColor = SKColor(white: 0, alpha: 0.75)
        shadow.position  = CGPoint(x: 2, y: -2)
        shadow.zPosition = -1
        lbl.addChild(shadow)

        gameWorldNode.addChild(lbl)
        lbl.run(.sequence([
            .group([
                .moveBy(x: 0, y: size.height * 0.07, duration: 0.90),
                .sequence([
                    .wait(forDuration: 0.48),
                    .fadeOut(withDuration: 0.42),
                ]),
            ]),
            .removeFromParent(),
        ]))
    }

    /// Brief centred overlay flash for phase transitions.
    private func showCentreFlash(_ text: String) {
        flashLabel.text     = text
        flashLabel.alpha    = 0
        flashLabel.position = .zero
        flashLabel.removeAllActions()
        flashLabel.run(.sequence([
            .fadeIn(withDuration: 0.12),
            .wait(forDuration: 1.2),
            .fadeOut(withDuration: 0.20),
        ]))
    }

    // MARK: - HUD push

    private var userAvg: CGFloat {
        userDistances.isEmpty ? 0 : userDistances.reduce(0, +) / CGFloat(userDistances.count)
    }
    private var aiAvg: CGFloat {
        aiDistances.isEmpty ? 0 : aiDistances.reduce(0, +) / CGFloat(aiDistances.count)
    }

    private func pushHUD() {
        let pitchInPhase = phase == .userBatting ? aiPitchCount : userPitchCount
        let vm = hudViewModel
        DispatchQueue.main.async {
            vm.cycle          = self.currentCycle
            vm.phaseIsbatting = (self.phase == .userBatting)
            vm.pitchCount     = pitchInPhase
            vm.playerAvgFt    = Int(self.userAvg * self.distScale)
            vm.aiAvgFt        = Int(self.aiAvg   * self.distScale)
        }
    }

    // MARK: - Game over

    private func showGameOver() {
        phase = .gameOver
        let uAvg = userAvg, aAvg = aiAvg
        let playerWon = uAvg > aAvg
        let tied      = uAvg == aAvg
        let userFt    = Int(uAvg * distScale)
        let aiFt      = Int(aAvg * distScale)

        let panel  = SKNode(); panel.zPosition = 1000
        let panelW = size.width  * 0.82
        let panelH = size.height * 0.54

        let back = SKSpriteNode(color: SKColor(red: 0.08, green: 0.06, blue: 0.04, alpha: 0.95),
                                size: CGSize(width: panelW, height: panelH))
        panel.addChild(back)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.14, alpha: 1)
        border.fillColor   = .clear; border.lineWidth = 3
        panel.addChild(border)

        let fs = max(8, size.width * 0.056)

        let titleText  = tied ? "IT'S A TIE!" : (playerWon ? "YOU WIN!" : "BOT WINS!")
        let titleColor: SKColor = tied
            ? SKColor(red: 1.0, green: 0.85, blue: 0.28, alpha: 1)
            : (playerWon ? SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1)
                         : SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))

        let title = makeLabel(titleText, size: fs * 1.1, color: titleColor)
        title.position = CGPoint(x: 0, y: panelH * 0.30); panel.addChild(title)

        let youLbl = makeLabel("YOU AVG  \(userFt)ft", size: fs * 0.75,
                               color: SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1))
        youLbl.position = CGPoint(x: 0, y: panelH * 0.10); panel.addChild(youLbl)

        let botLbl = makeLabel("BOT AVG  \(aiFt)ft", size: fs * 0.75,
                               color: SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))
        botLbl.position = CGPoint(x: 0, y: -panelH * 0.06); panel.addChild(botLbl)

        let subLbl = makeLabel("\(totalCycles) CYCLES · AVG DISTANCE", size: max(4, fs * 0.44),
                               color: SKColor(white: 0.42, alpha: 1))
        subLbl.position = CGPoint(x: 0, y: -panelH * 0.18); panel.addChild(subLbl)

        let playBtn = makeButton("PLAY AGAIN", fg: .white,
                                 bg: SKColor(red: 0.18, green: 0.44, blue: 0.18, alpha: 1),
                                 size: CGSize(width: panelW * 0.60, height: fs * 1.85))
        playBtn.position = CGPoint(x: 0, y: -panelH * 0.30); playBtn.name = "playAgainBtn"
        panel.addChild(playBtn)

        let exitBtn = makeButton("EXIT", fg: .white,
                                 bg: SKColor(red: 0.42, green: 0.10, blue: 0.10, alpha: 1),
                                 size: CGSize(width: panelW * 0.38, height: fs * 1.85))
        exitBtn.position = CGPoint(x: 0, y: -panelH * 0.44); exitBtn.name = "exitBtn"
        panel.addChild(exitBtn)

        addChild(panel)
        gameOverPanel = panel
        panel.alpha   = 0
        panel.run(.fadeIn(withDuration: 0.30))

        onComplete?(playerWon)
    }

    private func resetGame() {
        gameOverPanel?.removeFromParent()
        gameOverPanel    = nil
        currentCycle     = 1
        userDistances    = []
        aiDistances      = []
        isBatCharging    = false
        aiWillPowerSwing = false
        currentChargeLevel = 0
        chargeBarBg.isHidden = true
        resetBatVisual()
        cleanupHitBag()
        resetFielders()
        removePitchBag()
        pitchInFlight  = false
        isTracking     = false
        hitStopEndTime = 0
        gameWorldNode.speed = 1
        animateCamera(to: .zero, duration: 0.30)
        startUserBatting()
    }

    // MARK: - Shared helpers

    private func makeBagNode(color: SKColor, size: CGFloat) -> SKSpriteNode {
        // Try the project asset first; fall back to a plain coloured square
        let tex = SKTexture(imageNamed: "bag_16bit")
        tex.filteringMode = .nearest
        let node = SKSpriteNode(texture: tex, size: CGSize(width: size, height: size))
        node.color            = color
        node.colorBlendFactor = 0.65
        return node
    }

    private func makeLabel(_ text: String, size fs: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.fontSize = fs; l.fontColor = color; l.text = text
        l.verticalAlignmentMode   = .center
        l.horizontalAlignmentMode = .center
        return l
    }

    private func makeButton(_ label: String, fg: SKColor, bg: SKColor, size: CGSize) -> SKNode {
        let n    = SKNode()
        let back = SKSpriteNode(color: bg, size: size)
        back.zPosition = 0; n.addChild(back)
        let lbl  = makeLabel(label, size: max(5, size.height * 0.52), color: fg)
        lbl.zPosition = 1; n.addChild(lbl)
        return n
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        let t = SKTransition.push(with: .down, duration: 0.38)
        t.pausesOutgoingScene = false
        view.presentScene(prev, transition: t)
    }
}
