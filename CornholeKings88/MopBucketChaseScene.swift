import SpriteKit
import UIKit

// MARK: - MopBucketChaseScene
//
// Chapter 3 chase: Billy Badger socks Jack and bolts down a hallway mid
// bucket-race chaos. Jack — one foot in a rolling mop bucket — rows after
// him with the mop. Side-scrolling rhythm game:
//
//   HOLD    — plant the mop; power builds (~0.6 s to full). Holding past
//             ~0.85 s drags the mop and bleeds speed.
//   RELEASE — the stroke fires; Jack surges forward.
//   GLIDE   — speed decays. Stroke again when it settles into the green
//             cadence band: stroking while still fast wastes the stroke
//             ("TOO EARLY!"), waiting too long loses the glide.
//
// Scripted rhythm-breakers along the hall (Summer Scream chaos): a limbo
// mop you must glide under (stroking inside clips you), a spray-bottle kid
// whose mist hides the meter, and a puddle strip that supercharges one
// stroke. The cadence meter fades to near-invisible after 3 well-timed
// strokes — diegetic cues (wake ripple, posture) take over.
//
// Canon ending: Jack never catches Billy. Winning = closing the gap before
// the hall runs out; the scripted finale then takes the wheel — Jack lunges,
// hits the janitor water, and slides helplessly into Becky. Losing = Billy
// reaches the far doors first.
//
// Pure story beat / picker replay — no rewards in any context.
final class MopBucketChaseScene: SKScene {

    // MARK: - Public
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    var awardsRewards: Bool = false

    // MARK: - Tunables (all speed/length values scale with scene width)
    private var maxSpeed:  CGFloat { size.width * 1.70 }
    private var optLow:    CGFloat { size.width * 0.35 }   // cadence band bottom
    private var optHigh:   CGFloat { size.width * 0.80 }   // cadence band top
    private var billyBase: CGFloat { size.width * 0.90 }
    private var hallLength: CGFloat { size.width * 17.0 }
    private var catchRadius: CGFloat { size.width * 0.35 }
    private let frictionK: CGFloat = 0.55       // glide decay rate
    private let holdFullPower: TimeInterval = 0.60
    private let holdDragStart: TimeInterval = 0.85

    // MARK: - Phase
    private enum ChasePhase { case racing, finale, done }
    private var phase: ChasePhase = .racing
    private var isGameOver = false
    private var isPausedGame = false
    private var countdownActive = true
    private var tutorialUp = false
    private var confirmingQuit = false

    // MARK: - Race state
    private var jackDist:  CGFloat = 0
    private var billyDist: CGFloat = 0
    private var jackSpeed: CGFloat = 0
    private var raceClock: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var isHolding = false
    private var holdStart: TimeInterval = 0
    private var wellTimedStrokes = 0
    private var meterFaded = false
    private var prevSpeed: CGFloat = 0
    private var billyStumbleUntil: TimeInterval = -1
    private var stumbleIndex = 0
    private var limboClipped = false
    private var sprayTriggered = false
    private var finaleImpacted = false
    private var beckyDist: CGFloat = 0

    // Hazard zones — fractions of hallLength, resolved in didMove.
    private var limboZone:  ClosedRange<CGFloat> = 0...0
    private var sprayPoint: CGFloat = 0
    private var puddleZone: ClosedRange<CGFloat> = 0...0
    private var stumblePoints: [CGFloat] = []

    // MARK: - Nodes
    private var scrollLayer: SKNode!
    private var jackNode: SKNode?
    private var bucketNode: SKNode?
    private var mopNode: SKSpriteNode?
    private var billyNode: SKNode?
    private var beckyNode: SKNode?
    private var meterNode: SKNode?
    private var powerFill: SKSpriteNode?
    private var speedNeedle: SKSpriteNode?
    private var mistOverlay: SKSpriteNode?
    private var gapLabel: SKLabelNode?
    private var messageNode: SKNode?
    private var pauseOverlayNode: SKNode?
    private var confirmPanel: SKNode?
    private var didWin = false

    private var floorY: CGFloat { -size.height * 0.20 }
    private var jackScreenX: CGFloat { -size.width * 0.24 }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.78, green: 0.73, blue: 0.62, alpha: 1) // hallway wall

        limboZone   = (hallLength * 0.33)...(hallLength * 0.33 + size.width * 0.6)
        sprayPoint  = hallLength * 0.55
        puddleZone  = (hallLength * 0.72)...(hallLength * 0.72 + size.width * 0.8)
        stumblePoints = [hallLength * 0.22, hallLength * 0.45, hallLength * 0.68]

        billyDist = size.width * 2.0   // Billy's head start

        buildHallway()
        buildCharacters()
        setupUI()
        addCrtOverlay()

        if TutorialManager.shared.hasSeen(TutorialManager.mopChase) {
            startCountdown()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    // MARK: - Hallway (all world-anchored inside scrollLayer)

    private func buildHallway() {
        let W = size.width, H = size.height
        let layer = SKNode()
        layer.zPosition = 10
        addChild(layer)
        scrollLayer = layer

        // Floor band (static, full width — the tile dashes below scroll).
        let floor = SKSpriteNode(color: SKColor(red: 0.55, green: 0.50, blue: 0.44, alpha: 1),
                                 size: CGSize(width: W, height: H * 0.30))
        floor.position = CGPoint(x: 0, y: floorY - H * 0.15 + 4)
        floor.zPosition = 5
        addChild(floor)

        // Lockers + floor dashes along the whole hall.
        let lockerW: CGFloat = 26
        var x: CGFloat = -W
        while x < hallLength + W * 2 {
            let locker = SKSpriteNode(
                color: SKColor(hue: 0.58, saturation: 0.35,
                               brightness: 0.55 + CGFloat((Int(x / lockerW) % 3)) * 0.06,
                               alpha: 1),
                size: CGSize(width: lockerW - 2, height: H * 0.24))
            locker.position = CGPoint(x: x, y: floorY + H * 0.16)
            layer.addChild(locker)
            let vent = SKSpriteNode(color: SKColor(white: 0, alpha: 0.22),
                                    size: CGSize(width: lockerW - 10, height: 2))
            vent.position = CGPoint(x: x, y: floorY + H * 0.22)
            layer.addChild(vent)

            let dash = SKSpriteNode(color: SKColor(white: 0.30, alpha: 0.5),
                                    size: CGSize(width: 10, height: 2))
            dash.position = CGPoint(x: x, y: floorY - 6)
            layer.addChild(dash)
            x += lockerW
        }

        // Far doors at the end of the hall — Billy's escape route.
        let doors = SKSpriteNode(color: SKColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1),
                                 size: CGSize(width: 22, height: H * 0.30))
        doors.position = CGPoint(x: hallLength + W * 0.5, y: floorY + H * 0.15)
        layer.addChild(doors)
        let doorBar = SKSpriteNode(color: SKColor(red: 0.85, green: 0.72, blue: 0.30, alpha: 1),
                                   size: CGSize(width: 16, height: 4))
        doorBar.position = CGPoint(x: hallLength + W * 0.5, y: floorY + H * 0.14)
        layer.addChild(doorBar)

        // — Hazards —

        // Limbo mop: two kids holding a horizontal mop bar. Glide under it!
        let limboX = (limboZone.lowerBound + limboZone.upperBound) / 2
        for side: CGFloat in [-1, 1] {
            let kid = makeKid(shirt: SKColor(red: 0.60, green: 0.40, blue: 0.65, alpha: 1),
                              hair: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1))
            kid.position = CGPoint(x: limboX + side * (limboZone.upperBound - limboZone.lowerBound) / 2,
                                   y: floorY + 12)
            layer.addChild(kid)
        }
        let limboBar = SKSpriteNode(color: SKColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1),
                                    size: CGSize(width: limboZone.upperBound - limboZone.lowerBound, height: 4))
        limboBar.position = CGPoint(x: limboX, y: floorY + 34)
        layer.addChild(limboBar)

        // Spray-bottle kid.
        let sprayKid = makeKid(shirt: SKColor(red: 0.30, green: 0.60, blue: 0.70, alpha: 1),
                               hair: SKColor(red: 0.72, green: 0.58, blue: 0.24, alpha: 1))
        sprayKid.position = CGPoint(x: sprayPoint, y: floorY + 12)
        layer.addChild(sprayKid)
        let bottle = SKSpriteNode(color: SKColor(red: 0.30, green: 0.75, blue: 0.90, alpha: 1),
                                  size: CGSize(width: 5, height: 8))
        bottle.position = CGPoint(x: sprayPoint - 9, y: floorY + 14)
        layer.addChild(bottle)

        // Puddle strip — a stroke released inside glows super.
        let puddle = SKShapeNode(ellipseOf: CGSize(width: puddleZone.upperBound - puddleZone.lowerBound,
                                                   height: 10))
        puddle.fillColor = SKColor(red: 0.35, green: 0.60, blue: 0.90, alpha: 0.45)
        puddle.strokeColor = SKColor(red: 0.45, green: 0.70, blue: 0.95, alpha: 0.6)
        puddle.position = CGPoint(x: (puddleZone.lowerBound + puddleZone.upperBound) / 2,
                                  y: floorY - 2)
        puddle.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.7, duration: 0.6),
            .fadeAlpha(to: 0.4, duration: 0.6),
        ])))
        layer.addChild(puddle)
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
        // Jack in the rolling mop bucket, mop in hand.
        let jack = SKNode()
        jack.zPosition = 30

        let bucket = SKNode()
        let pail = SKSpriteNode(color: SKColor(red: 0.85, green: 0.75, blue: 0.20, alpha: 1),
                                size: CGSize(width: 22, height: 14))
        pail.position = CGPoint(x: 0, y: 7)
        bucket.addChild(pail)
        for wx: CGFloat in [-7, 7] {
            let wheel = SKShapeNode(circleOfRadius: 3)
            wheel.fillColor = SKColor(white: 0.2, alpha: 1)
            wheel.strokeColor = .clear
            wheel.position = CGPoint(x: wx, y: 0)
            bucket.addChild(wheel)
        }
        jack.addChild(bucket)
        bucketNode = bucket

        let body = makeKid(shirt: SKColor(red: 0.80, green: 0.24, blue: 0.16, alpha: 1),
                           hair: SKColor(red: 0.42, green: 0.28, blue: 0.12, alpha: 1))
        body.position = CGPoint(x: 0, y: 16)
        jack.addChild(body)

        let mop = SKSpriteNode(color: SKColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1),
                               size: CGSize(width: 3, height: 34))
        mop.anchorPoint = CGPoint(x: 0.5, y: 1.0)   // pivots at Jack's hands
        mop.position = CGPoint(x: 7, y: 24)
        mop.zRotation = 0.5
        let mopHead = SKSpriteNode(color: SKColor(white: 0.85, alpha: 1),
                                   size: CGSize(width: 8, height: 5))
        mopHead.position = CGPoint(x: 0, y: -34)
        mop.addChild(mopHead)
        jack.addChild(mop)
        mopNode = mop

        jack.position = CGPoint(x: jackDist, y: floorY)
        scrollLayer.addChild(jack)
        jackNode = jack

        // Billy sprints ahead.
        let billy = makeKid(shirt: SKColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1),
                            hair: SKColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1))
        billy.position = CGPoint(x: billyDist, y: floorY + 12)
        billy.zPosition = 28
        billy.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 0.12),
            .moveBy(x: 0, y: -3, duration: 0.12),
        ])))
        scrollLayer.addChild(billy)
        billyNode = billy
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
        label.text = "CATCH BILLY!"
        label.fontSize = 9
        label.fontColor = Parchment.deep
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: contentY)
        label.zPosition = 502
        addChild(label)
        gapLabel = label

        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size = CGSize(width: 22, height: 22)
        closeBtn.position = CGPoint(x: size.width / 2 - 22, y: contentY)
        closeBtn.zPosition = 502
        closeBtn.name = "closeButton"
        addChild(closeBtn)

        buildCadenceMeter()
    }

    /// Stroke-power bar + speed gauge with the green cadence band. Fades to
    /// near-invisible after 3 well-timed strokes — the wake ripple takes over.
    private func buildCadenceMeter() {
        let W = size.width, H = size.height
        let meter = SKNode()
        meter.position = CGPoint(x: -W * 0.28, y: -H * 0.38)
        meter.zPosition = 510
        addChild(meter)
        meterNode = meter

        // Vertical hold-power bar.
        let powerBG = SKSpriteNode(color: SKColor(white: 0, alpha: 0.45),
                                   size: CGSize(width: 12, height: 54))
        powerBG.position = CGPoint(x: -W * 0.10, y: 6)
        meter.addChild(powerBG)
        let fill = SKSpriteNode(color: SKColor(red: 0.30, green: 0.85, blue: 0.35, alpha: 1),
                                size: CGSize(width: 8, height: 0))
        fill.anchorPoint = CGPoint(x: 0.5, y: 0)
        fill.position = CGPoint(x: -W * 0.10, y: -21)
        meter.addChild(fill)
        powerFill = fill

        // Horizontal speed gauge with cadence band.
        let gaugeW = W * 0.42
        let gaugeBG = SKSpriteNode(color: SKColor(white: 0, alpha: 0.45),
                                   size: CGSize(width: gaugeW, height: 10))
        gaugeBG.position = CGPoint(x: gaugeW / 2 - W * 0.04, y: 0)
        meter.addChild(gaugeBG)

        let bandStart = optLow / maxSpeed * gaugeW
        let bandEnd   = optHigh / maxSpeed * gaugeW
        let band = SKSpriteNode(color: SKColor(red: 0.25, green: 0.80, blue: 0.35, alpha: 0.55),
                                size: CGSize(width: bandEnd - bandStart, height: 10))
        band.position = CGPoint(x: -W * 0.04 + (bandStart + bandEnd) / 2, y: 0)
        meter.addChild(band)

        let needle = SKSpriteNode(color: SKColor(red: 0.95, green: 0.90, blue: 0.35, alpha: 1),
                                  size: CGSize(width: 3, height: 14))
        needle.position = CGPoint(x: -W * 0.04, y: 0)
        meter.addChild(needle)
        speedNeedle = needle

        let hint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        hint.text = "STROKE IN GREEN"
        hint.fontSize = 6
        hint.fontColor = SKColor(white: 0.98, alpha: 0.85)
        hint.horizontalAlignmentMode = .left
        hint.position = CGPoint(x: -W * 0.04, y: -14)
        meter.addChild(hint)

        // Mist overlay — hidden until the spray-bottle kid gets you.
        let mist = SKSpriteNode(color: SKColor(red: 0.75, green: 0.88, blue: 0.95, alpha: 0.92),
                                size: CGSize(width: gaugeW + W * 0.14, height: 70))
        mist.position = CGPoint(x: gaugeW / 2 - W * 0.07, y: 2)
        mist.zPosition = 2
        mist.alpha = 0
        meter.addChild(mist)
        mistOverlay = mist
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
            .card(title: "THE CHASE",
                  body: "BILLY SOCKED YOU AND RAN. ONE FOOT IN THE MOP BUCKET — ROW DOWN THE HALL AND CATCH HIM BEFORE THE DOORS!"),
            .hint(at: CGPoint(x: jackScreenX, y: floorY),
                  title: "HOLD TO STROKE",
                  body: "TAP & HOLD TO PLANT THE MOP — RELEASE TO SURGE. HOLDING TOO LONG DRAGS THE MOP AND SLOWS YOU!"),
            .card(title: "FIND THE RHYTHM",
                  body: "LET THE GLIDE SETTLE INTO THE GREEN BAND, THEN STROKE AGAIN. WATCH OUT FOR HALLWAY CHAOS — GLIDE UNDER THE LIMBO MOP!"),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self else { return }
            self.tutorialUp = false
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.mopChase)
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
            beatLabel(text: "ROW!", color: green),
            .wait(forDuration: 0.5),
            .run { [weak self] in self?.countdownActive = false },
        ]))
    }

    // MARK: - Stroke mechanics

    private func beginStroke() {
        guard phase == .racing, !isHolding else { return }
        isHolding = true
        holdStart = raceClock
        // Mop rotates back to plant.
        mopNode?.removeAllActions()
        mopNode?.run(.rotate(toAngle: 0.9, duration: 0.15, shortestUnitArc: true))
    }

    private func releaseStroke() {
        guard isHolding else { return }
        isHolding = false
        guard phase == .racing else { return }

        let holdT = raceClock - holdStart
        var power = CGFloat(min(1.0, holdT / holdFullPower))
        if holdT > holdDragStart {
            power = max(0.4, 1.0 - CGFloat(holdT - holdDragStart) * 0.8)
        }

        // Cadence: stroking while still fast wastes the catch.
        let tooEarly = jackSpeed > optHigh
        let factor: CGFloat = tooEarly ? 0.55 : 1.0

        var impulse = (size.width * 0.75 + size.width * 1.05 * power) * factor
        let inPuddle = puddleZone.contains(jackDist)
        if inPuddle {
            impulse *= 1.6
            showToast("SUPER STROKE!", color: SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1))
        } else if tooEarly && power > 0.3 {
            showToast("TOO EARLY!", color: SKColor(red: 0.95, green: 0.60, blue: 0.30, alpha: 1))
        } else if power >= 0.8 && jackSpeed >= optLow && jackSpeed <= optHigh {
            wellTimedStrokes += 1
            showToast("PERFECT STROKE!", color: SKColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 1))
            if wellTimedStrokes >= 3 && !meterFaded {
                meterFaded = true
                meterNode?.run(.fadeAlpha(to: 0.22, duration: 1.0))
            }
        }

        jackSpeed = min(maxSpeed, jackSpeed + impulse)
        HapticsManager.shared.lightImpact()
        splash(at: CGPoint(x: jackDist + 10, y: floorY - 4))

        // Mop sweeps forward, then settles.
        mopNode?.removeAllActions()
        mopNode?.run(.sequence([
            .rotate(toAngle: -0.6, duration: 0.12, shortestUnitArc: true),
            .rotate(toAngle: 0.5, duration: 0.4, shortestUnitArc: true),
        ]))
    }

    private func splash(at worldPos: CGPoint) {
        for _ in 0..<4 {
            let fleck = SKSpriteNode(color: SKColor(white: 0.95, alpha: 0.8),
                                     size: CGSize(width: 3, height: 3))
            fleck.position = worldPos
            fleck.zPosition = 32
            scrollLayer.addChild(fleck)
            fleck.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -14...4),
                            y: CGFloat.random(in: 4...16), duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    /// Wake ripple — the diegetic "stroke now" cue once the meter fades.
    private func wakePulse() {
        guard let jack = jackNode else { return }
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.strokeColor = SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 0.9)
        ring.lineWidth = 2
        ring.fillColor = .clear
        ring.position = CGPoint(x: jack.position.x, y: floorY)
        ring.zPosition = 26
        scrollLayer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 2.4, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent(),
        ]))
    }

    private func showToast(_ text: String, color: SKColor) {
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = text
        lbl.fontSize = min(11, size.width / 26)
        lbl.fontColor = color
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: 0, y: size.height * 0.10)
        lbl.zPosition = 850
        lbl.alpha = 0
        addChild(lbl)
        lbl.run(.sequence([
            .fadeIn(withDuration: 0.12),
            .wait(forDuration: 0.9),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
        ]))
    }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime == 0 { dt = 0 } else { dt = min(currentTime - lastUpdateTime, 1.0 / 20.0) }
        lastUpdateTime = currentTime

        guard !isPausedGame, !tutorialUp, !countdownActive, !isGameOver else { return }
        raceClock += dt
        let fdt = CGFloat(dt)

        switch phase {
        case .racing:
            // — Jack: glide friction (+ mop drag when overholding) —
            var k = frictionK
            if isHolding {
                let holdT = raceClock - holdStart
                if holdT > holdDragStart { k += 1.2 }   // mop dragging
                powerFill?.size.height = 48 * CGFloat(min(1.0, holdT / holdFullPower))
                powerFill?.color = holdT > holdDragStart
                    ? SKColor(red: 0.90, green: 0.30, blue: 0.20, alpha: 1)
                    : SKColor(red: 0.30, green: 0.85, blue: 0.35, alpha: 1)
            } else {
                powerFill?.size.height = 0
            }
            jackSpeed *= exp(-k * fdt)
            jackDist += jackSpeed * fdt

            // Diegetic cadence cue: speed decays back into the band.
            if prevSpeed > optHigh && jackSpeed <= optHigh && !isHolding {
                wakePulse()
            }
            prevSpeed = jackSpeed

            // — Limbo mop: stroking inside the zone clips the bar —
            if !limboClipped, limboZone.contains(jackDist), isHolding {
                limboClipped = true
                jackSpeed *= 0.45
                showToast("CLIPPED THE LIMBO MOP!", color: SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
                HapticsManager.shared.errorFeedback()
            }

            // — Spray-bottle kid mists the meter —
            if !sprayTriggered, jackDist > sprayPoint - size.width * 0.3 {
                sprayTriggered = true
                mistOverlay?.run(.sequence([
                    .fadeAlpha(to: 0.92, duration: 0.2),
                    .wait(forDuration: 2.0),
                    .fadeOut(withDuration: 0.5),
                ]))
                showToast("SPRAYED!", color: SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1))
            }

            // — Billy: base run + scripted stumbles —
            var billySpeed = billyBase
            if stumbleIndex < stumblePoints.count, billyDist >= stumblePoints[stumbleIndex] {
                billyStumbleUntil = raceClock + 1.1
                stumbleIndex += 1
                billyNode?.run(.sequence([
                    .rotate(toAngle: 0.5, duration: 0.15),
                    .wait(forDuration: 0.7),
                    .rotate(toAngle: 0, duration: 0.15),
                ]))
            }
            if raceClock < billyStumbleUntil { billySpeed = size.width * 0.12 }
            billyDist += billySpeed * fdt

            // — Camera + node positions —
            layoutWorld()

            // — Speed gauge needle —
            let gaugeW = size.width * 0.42
            speedNeedle?.position.x = -size.width * 0.04 + min(1, jackSpeed / maxSpeed) * gaugeW

            // — Gap readout —
            let gap = billyDist - jackDist
            gapLabel?.text = "GAP \(max(0, Int(gap)))"
            gapLabel?.fontColor = gap < size.width
                ? SKColor(red: 0.20, green: 0.60, blue: 0.25, alpha: 1)
                : Parchment.deep

            // — Win / lose checks —
            if gap <= catchRadius {
                startFinale()
            } else if billyDist >= hallLength {
                phase = .done
                showToast("HE'S GONE!", color: SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
                billyNode?.run(.fadeOut(withDuration: 0.4))
                run(.wait(forDuration: 1.0)) { [weak self] in
                    self?.triggerGameOver(playerWon: false)
                }
            }

        case .finale:
            // Runaway slide — no friction, no control, bucket spinning.
            jackDist += maxSpeed * 1.05 * fdt
            billyDist += billyBase * 1.2 * fdt
            bucketNode?.zRotation -= fdt * 6
            layoutWorld()

            if !finaleImpacted, jackDist >= beckyDist - 16 {
                finaleImpacted = true
                crashIntoBecky()
            }

        case .done:
            layoutWorld()
        }
    }

    /// Positions every world-anchored node relative to Jack's scroll offset.
    private func layoutWorld() {
        scrollLayer.position.x = jackScreenX - jackDist
        jackNode?.position.x = jackDist
        billyNode?.position.x = billyDist
    }

    // MARK: - Finale (scripted slip into Becky)

    private func startFinale() {
        guard phase == .racing else { return }
        phase = .finale
        isHolding = false
        showToast("GOTCHA—", color: SKColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 1))

        // Janitor water right under the lunge, and Becky just past it.
        beckyDist = jackDist + size.width * 0.95
        let water = SKShapeNode(ellipseOf: CGSize(width: size.width * 0.5, height: 8))
        water.fillColor = SKColor(red: 0.35, green: 0.60, blue: 0.90, alpha: 0.55)
        water.strokeColor = .clear
        water.position = CGPoint(x: jackDist + size.width * 0.45, y: floorY - 2)
        water.zPosition = 12
        scrollLayer.addChild(water)

        let becky = makeKid(shirt: SKColor(red: 0.85, green: 0.55, blue: 0.70, alpha: 1),
                            hair: SKColor(red: 0.72, green: 0.58, blue: 0.24, alpha: 1))
        becky.position = CGPoint(x: beckyDist, y: floorY + 12)
        becky.zPosition = 28
        scrollLayer.addChild(becky)
        beckyNode = becky

        run(.wait(forDuration: 0.35)) { [weak self] in
            self?.showToast("WHOA— THE WATER!", color: SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1))
        }
    }

    private func crashIntoBecky() {
        run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        HapticsManager.shared.heavyImpact()

        // Impact stars + screen shake; Becky reels.
        if let becky = beckyNode {
            for _ in 0..<6 {
                let star = SKLabelNode(fontNamed: "PressStart2P-Regular")
                star.text = "✦"
                star.fontSize = 9
                star.fontColor = SKColor(red: 0.98, green: 0.85, blue: 0.30, alpha: 1)
                star.position = CGPoint(x: becky.position.x, y: becky.position.y + 14)
                star.zPosition = 40
                scrollLayer.addChild(star)
                star.run(.sequence([
                    .group([
                        .moveBy(x: CGFloat.random(in: -26...26),
                                y: CGFloat.random(in: 6...30), duration: 0.5),
                        .fadeOut(withDuration: 0.5),
                    ]),
                    .removeFromParent(),
                ]))
            }
            becky.run(.sequence([
                .rotate(toAngle: -0.4, duration: 0.1),
                .rotate(toAngle: 0, duration: 0.3),
            ]))
        }

        let shake = SKAction.sequence([
            .moveBy(x: 5, y: 0, duration: 0.04), .moveBy(x: -10, y: 0, duration: 0.05),
            .moveBy(x: 8, y: 0, duration: 0.05), .moveBy(x: -3, y: 0, duration: 0.04),
        ])
        scrollLayer.run(shake)

        let crash = SKLabelNode(fontNamed: "PressStart2P-Regular")
        crash.text = "CRASH!"
        crash.fontSize = min(30, size.width / 8)
        crash.fontColor = SKColor(red: 0.95, green: 0.40, blue: 0.25, alpha: 1)
        crash.zPosition = 900
        crash.setScale(0.3)
        addChild(crash)
        crash.run(.sequence([
            .scale(to: 1.0, duration: 0.15),
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))

        phase = .done
        run(.wait(forDuration: 1.5)) { [weak self] in
            self?.triggerGameOver(playerWon: true)
        }
    }

    // MARK: - Input

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
        if handleButtonTap(at: loc) { return }

        beginStroke()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let end = touch.location(in: self)

        if isGameOver || isPausedGame || confirmingQuit {
            handleButtonTap(at: end)
            if isHolding { isHolding = false }
            return
        }
        releaseStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseStroke()
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

    private func triggerGameOver(playerWon: Bool) {
        guard !isGameOver else { return }
        isGameOver = true
        didWin = playerWon
        run(SKAction.playSoundFileNamed(playerWon ? "game_win.wav" : "game_lose.wav",
                                        waitForCompletion: false))
        run(.wait(forDuration: 0.5)) { [weak self] in
            self?.showGameOverPanel(playerWon: playerWon)
        }
    }

    private func showGameOverPanel(playerWon: Bool) {
        messageNode?.removeFromParent()
        let panel = GameResultModal.make(
            sceneSize: size,
            won: playerWon,
            title: playerWon ? "CAUGHT UP... TOO FAST" : "BILLY GOT AWAY",
            subtitle: playerWon ? "RIGHT INTO BECKY" : "OUT THE FAR DOORS",
            detail: playerWon ? nil : "CLOSE THE GAP BEFORE THE HALL ENDS",
            hint: playerWon ? nil : ("FIND THE RHYTHM —\nSTROKE, GLIDE, STROKE",
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
        beckyNode?.removeFromParent()
        beckyNode = nil

        jackDist = 0
        billyDist = size.width * 2.0
        jackSpeed = 0
        prevSpeed = 0
        raceClock = 0
        isHolding = false
        wellTimedStrokes = 0
        billyStumbleUntil = -1
        stumbleIndex = 0
        limboClipped = false
        sprayTriggered = false
        finaleImpacted = false
        isGameOver = false
        didWin = false
        phase = .racing

        // Restore the (possibly faded) meter and any finale leftovers.
        if meterFaded {
            meterFaded = false
            meterNode?.alpha = 1
        }
        mistOverlay?.removeAllActions()
        mistOverlay?.alpha = 0
        bucketNode?.zRotation = 0
        billyNode?.alpha = 1
        billyNode?.zRotation = 0
        layoutWorld()
        gapLabel?.text = "CATCH BILLY!"
        startCountdown()
    }

    // MARK: - Pause

    private func pauseGame() {
        guard !isPausedGame, !isGameOver else { return }
        isPausedGame = true
        if isHolding { releaseStroke() }
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
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
        q.text = "LET BILLY GO?"; q.fontSize = 10
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
