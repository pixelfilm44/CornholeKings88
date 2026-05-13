import SpriteKit
import UIKit

// MARK: - Game state
private enum BikeGameState { case menu, countdown, racing, gameOver, victory }

// MARK: - Entity models
private struct RacerData {
    enum Kind { case player, pink, green }
    var kind: Kind
    var distanceRemaining: CGFloat = 5.0
    var speed: CGFloat = 0
    var x: CGFloat = 0
    var xVelocity: CGFloat = 0
    var hearts: Int = 3
    var maxHearts: Int = 5
    var isInvincible: Bool = false
    var invTimer: CGFloat = 0
    var isCrashing: Bool = false
    var crashTimer: CGFloat = 0
    var isBoosting: Bool = false
    var boostTimer: CGFloat = 0
    var finished: Bool = false
    var finishRank: Int = 0
    // AI only
    var targetLaneX: CGFloat = 0
    var errorCooldown: CGFloat = 0
}

private struct CarData {
    var x: CGFloat
    var screenY: CGFloat
    var forwardSpeed: CGFloat
    var node: SKNode
    var isActive: Bool = true
}

private struct BeanBagData {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var node: SKSpriteNode
    var isActive: Bool = true
}

private struct PickupData {
    enum Kind { case heart, boost }
    var kind: Kind
    var x: CGFloat
    var screenY: CGFloat
    var node: SKNode
    var isActive: Bool = true
}

// MARK: - Main Scene
final class BikeDodgeScene: SKScene {

    // MARK: - Public
    weak var bikeDodgeDelegate: BikeDodgeSceneDelegate?
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?

    // MARK: - Layout
    private var W: CGFloat = 0, H: CGFloat = 0
    private var roadLeft:  CGFloat = 0, roadRight: CGFloat = 0
    private var roadWidth: CGFloat = 0, laneWidth: CGFloat = 0
    private var laneCenter: [CGFloat] = [0, 0, 0]
    private var playerScreenY: CGFloat = 0

    // MARK: - Speed constants
    private let baseSpeed:    CGFloat = 160
    private let maxSpeed:     CGFloat = 360
    private let boostMult:    CGFloat = 1.4
    private let accel:        CGFloat = 28
    private let steerAccel:   CGFloat = 310
    private let maxSteerVel:  CGFloat = 210
    private let distPerPx:    CGFloat = 1.0 / 11_000   // miles per scene-pt scroll
    private let distToPixScale: CGFloat = 1_500         // scene-pts per mile

    // MARK: - Game state
    private var gState:     BikeGameState = .menu
    private var lastTime:   TimeInterval  = 0
    private var elapsed:    CGFloat = 0
    private var cdValue:    Int     = 3
    private var cdTimer:    CGFloat = 0
    private var finishCount: Int    = 0

    // MARK: - Racers
    private var pr = RacerData(kind: .player)
    private var pk = RacerData(kind: .pink)
    private var gr = RacerData(kind: .green)

    // MARK: - Sprites
    private var playerSprite: SKSpriteNode!
    private var pinkSprite:   SKSpriteNode!
    private var greenSprite:  SKSpriteNode!
    private var playerBoostNode: SKNode?
    private var pinkBoostNode:   SKNode?
    private var greenBoostNode:  SKNode?

    // MARK: - Road
    private var roadBG1: SKSpriteNode!
    private var roadBG2: SKSpriteNode!

    // MARK: - Entities
    private var cars:    [CarData]     = []
    private var bags:    [BeanBagData] = []
    private var pickups: [PickupData]  = []

    // MARK: - Spawn timers
    private var carTimer:  CGFloat = 1.5,  carInterval:  CGFloat = 2.5
    private var pkTimer:   CGFloat = 4.0,  pkInterval:   CGFloat = 5.0
    private var bagTimer:  CGFloat = 2.0,  bagInterval:  CGFloat = 3.0

    // MARK: - Input
    private var steerLeft  = false
    private var steerRight = false
    private var leftTouches:  Set<UITouch> = []
    private var rightTouches: Set<UITouch> = []

    // MARK: - HUD
    private var distLabel:   SKLabelNode!
    private var timeLabel:   SKLabelNode!
    private var heartsLabel: SKLabelNode!
    private var minimapBG:   SKShapeNode!
    private var mmDots:      [SKShapeNode] = []
    private var mmBottom:    CGFloat = 0, mmHeight: CGFloat = 0

    // MARK: - Overlay
    private var overlayNode:    SKNode?
    private var countdownLabel: SKLabelNode?

    // MARK: - Car colors
    private static let carColors: [UIColor] = [
        UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1),
        UIColor(red: 0.15, green: 0.25, blue: 0.70, alpha: 1),
        UIColor(red: 0.65, green: 0.60, blue: 0.10, alpha: 1),
        UIColor(red: 0.45, green: 0.20, blue: 0.55, alpha: 1),
        UIColor(white: 0.75, alpha: 1),
        UIColor(red: 0.20, green: 0.55, blue: 0.20, alpha: 1),
    ]

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width; H = size.height
        roadWidth = W * 0.64
        roadLeft  = -roadWidth / 2
        roadRight =  roadWidth / 2
        laneWidth = roadWidth / 3
        laneCenter = [roadLeft + laneWidth * 0.5, 0, roadRight - laneWidth * 0.5]
        playerScreenY = -H * 0.19
        backgroundColor = SKColor(red: 0.14, green: 0.40, blue: 0.10, alpha: 1)

        setupRoad()
        setupBikes()
        setupHUD()
        setupMinimap()
        showStartMenu()
    }

    // MARK: - Road
    private func setupRoad() {
        let tex = makeRoadTexture()
        let sz  = CGSize(width: roadWidth, height: H)
        roadBG1 = SKSpriteNode(texture: tex, size: sz)
        roadBG1.position  = .zero; roadBG1.zPosition = -5; addChild(roadBG1)
        roadBG2 = SKSpriteNode(texture: tex, size: sz)
        roadBG2.position  = CGPoint(x: 0, y: H); roadBG2.zPosition = -5; addChild(roadBG2)
    }

    private func makeRoadTexture() -> SKTexture {
        let iw = roadWidth, ih = H
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: iw, height: ih), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.20, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: iw, height: ih))
            c.setFillColor(UIColor(white: 0.88, alpha: 1).cgColor)
            c.fill(CGRect(x: 0,    y: 0, width: 4, height: ih))
            c.fill(CGRect(x: iw-4, y: 0, width: 4, height: ih))
            c.setStrokeColor(UIColor(red: 0.95, green: 0.85, blue: 0.10, alpha: 1).cgColor)
            c.setLineWidth(3)
            c.setLineDash(phase: 0, lengths: [20, 10])
            for lx in [iw / 3, iw * 2 / 3] {
                c.move(to: CGPoint(x: lx, y: 0)); c.addLine(to: CGPoint(x: lx, y: ih)); c.strokePath()
            }
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // MARK: - Bikes
    private func setupBikes() {
        let cyanC  = UIColor(red: 0.10, green: 0.85, blue: 0.90, alpha: 1)
        let pinkC  = UIColor(red: 0.95, green: 0.30, blue: 0.60, alpha: 1)
        let greenC = UIColor(red: 0.20, green: 0.85, blue: 0.35, alpha: 1)

        pr.x = laneCenter[1]; pr.speed = baseSpeed; pr.hearts = 3
        pk.x = laneCenter[0]; pk.speed = baseSpeed; pk.targetLaneX = laneCenter[0]
        gr.x = laneCenter[2]; gr.speed = baseSpeed; gr.targetLaneX = laneCenter[2]

        playerSprite = makeBikeSprite(color: cyanC)
        playerSprite.position  = CGPoint(x: pr.x, y: playerScreenY)
        playerSprite.zPosition = 10; addChild(playerSprite)

        pinkSprite = makeBikeSprite(color: pinkC)
        pinkSprite.position  = CGPoint(x: pk.x, y: screenYFor(pk))
        pinkSprite.zPosition = 10; addChild(pinkSprite)

        greenSprite = makeBikeSprite(color: greenC)
        greenSprite.position  = CGPoint(x: gr.x, y: screenYFor(gr))
        greenSprite.zPosition = 10; addChild(greenSprite)
    }

    private func makeBikeSprite(color: UIColor) -> SKSpriteNode {
        let bw: CGFloat = 22, bh: CGFloat = 34
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: bw, height: bh), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
            c.fill(CGRect(x: 3, y: 1, width: bw-6, height: 8))       // rear wheel
            c.setFillColor(color.cgColor)
            c.fill(CGRect(x: 4, y: 6, width: bw-8, height: bh*0.55)) // body
            c.setFillColor(UIColor(red: 0.30, green: 0.45, blue: 0.70, alpha: 0.85).cgColor)
            c.fill(CGRect(x: 6, y: bh*0.40, width: bw-12, height: bh*0.20)) // windshield
            c.setFillColor(UIColor(white: 0.90, alpha: 1).cgColor)
            c.fill(CGRect(x: 2, y: bh*0.60, width: bw-4, height: 4)) // handlebars
            c.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
            c.fill(CGRect(x: 3, y: bh-9, width: bw-6, height: 8))    // front wheel
            c.setFillColor(UIColor(white: 1.0, alpha: 0.45).cgColor)
            c.fill(CGRect(x: 7, y: bh*0.30, width: 4, height: bh*0.20)) // highlight
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return SKSpriteNode(texture: tex, size: CGSize(width: bw, height: bh))
    }

    // MARK: - HUD
    private func setupHUD() {
        let font = "PressStart2P-Regular"
        let fs: CGFloat = max(8, W * 0.028)

        // Position labels below the camera notch / Dynamic Island safe area
        let topInset = self.view?.safeAreaInsets.top ?? 0
        let hudY = H/2 - topInset - 22

        distLabel = SKLabelNode(fontNamed: font)
        distLabel.fontSize = fs; distLabel.fontColor = .white
        distLabel.horizontalAlignmentMode = .left
        distLabel.position = CGPoint(x: -W/2 + 54, y: hudY)
        distLabel.zPosition = 50; addChild(distLabel)

        timeLabel = SKLabelNode(fontNamed: font)
        timeLabel.fontSize = fs; timeLabel.fontColor = .white
        timeLabel.horizontalAlignmentMode = .center
        timeLabel.position = CGPoint(x: 0, y: hudY)
        timeLabel.zPosition = 50; addChild(timeLabel)

        heartsLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        heartsLabel.fontSize = fs + 4; heartsLabel.fontColor = .red
        heartsLabel.horizontalAlignmentMode = .right
        heartsLabel.position = CGPoint(x: W/2 - 38, y: hudY - 2)
        heartsLabel.zPosition = 50; addChild(heartsLabel)

        refreshHUD()
    }

    private func refreshHUD() {
        let m = Int(elapsed) / 60, s = Int(elapsed) % 60
        distLabel.text  = String(format: "%.2fmi", max(0, pr.distanceRemaining))
        timeLabel.text  = String(format: "%d:%02d", m, s)
        var h = ""
        for i in 0..<pr.maxHearts { h += i < pr.hearts ? "♥" : "♡" }
        heartsLabel.text = h
    }

    // MARK: - Minimap
    private func setupMinimap() {
        let barW: CGFloat = 10
        mmHeight = H * 0.68; mmBottom = -mmHeight / 2
        let barX = W/2 - 24

        minimapBG = SKShapeNode(rect: CGRect(x: barX - barW/2, y: mmBottom - 2,
                                             width: barW, height: mmHeight + 4), cornerRadius: 3)
        minimapBG.fillColor = SKColor(white: 0, alpha: 0.50)
        minimapBG.strokeColor = SKColor(white: 0.6, alpha: 0.4)
        minimapBG.lineWidth = 1; minimapBG.zPosition = 50; addChild(minimapBG)

        let dotColors: [SKColor] = [
            SKColor(red: 0.10, green: 0.85, blue: 0.90, alpha: 1),
            SKColor(red: 0.95, green: 0.30, blue: 0.60, alpha: 1),
            SKColor(red: 0.20, green: 0.85, blue: 0.35, alpha: 1),
        ]
        for (i, col) in dotColors.enumerated() {
            let dot = SKShapeNode(circleOfRadius: i == 0 ? 5 : 4)
            dot.fillColor = col; dot.zPosition = 52
            dot.strokeColor = i == 0 ? .white : .clear
            dot.lineWidth   = i == 0 ? 1.5 : 0
            dot.position    = CGPoint(x: barX, y: mmBottom)
            addChild(dot); mmDots.append(dot)
        }
    }

    private func updateMinimap() {
        let barX = W/2 - 24
        let pairs: [(RacerData, Int)] = [(pr, 0), (pk, 1), (gr, 2)]
        for (racer, i) in pairs {
            let prog = 1.0 - racer.distanceRemaining / 5.0
            mmDots[i].position = CGPoint(x: barX, y: mmBottom + prog * mmHeight)
        }
    }

    // MARK: - Start menu
    private func showStartMenu() {
        let ov = buildOverlayContainer()
        let bg = SKShapeNode(rect: CGRect(x: -W/2, y: -H/2, width: W, height: H))
        bg.fillColor = SKColor(white: 0, alpha: 0.72); bg.strokeColor = .clear; ov.addChild(bg)

        ov.addChild(label("BEANBAG BIKE",     font: "PressStart2P-Regular", size: min(20, W/17), color: .yellow,  at: CGPoint(x:0, y:90)))
        ov.addChild(label("5 MILE RACE",      font: "PressStart2P-Regular", size: min(9, W/40),  color: .white,   at: CGPoint(x:0, y:48)))
        ov.addChild(label("HOLD LEFT / RIGHT HALF TO STEER", font: "PressStart2P-Regular",
                          size: min(7, W/50), color: SKColor(white:0.7,alpha:1), at: CGPoint(x:0,y:20)))

        let start = label("▶  TAP TO START", font: "PressStart2P-Regular", size: min(13, W/26), color: .white, at: CGPoint(x:0, y:-40))
        start.name = "startBtn"
        start.run(.repeatForever(.sequence([.scale(to:1.06,duration:0.6),.scale(to:0.94,duration:0.6)])))
        ov.addChild(start)

        addChild(ov); overlayNode = ov
        gState = .menu
    }

    // MARK: - Countdown
    private func startCountdown() {
        overlayNode?.removeFromParent(); overlayNode = nil
        cdValue = 3; cdTimer = 0
        let lbl = label("3", font: "PressStart2P-Regular", size: min(60, W/5), color: .yellow, at: .zero)
        lbl.zPosition = 100; lbl.name = "cd"; addChild(lbl); countdownLabel = lbl
        gState = .countdown
    }

    private func updateCountdown(dt: CGFloat) {
        cdTimer += dt
        if cdTimer < 1.0 { return }
        cdTimer = 0; cdValue -= 1
        if cdValue <= 0 {
            countdownLabel?.removeFromParent(); countdownLabel = nil
            gState = .racing; return
        }
        countdownLabel?.text = cdValue == 1 ? "GO!" : "\(cdValue)"
        countdownLabel?.run(.sequence([.scale(to:1.4,duration:0.1),.scale(to:1.0,duration:0.3)]))
    }

    // MARK: - Update
    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(lastTime == 0 ? 0.016 : min(currentTime - lastTime, 0.033))
        lastTime = currentTime
        switch gState {
        case .menu:              return
        case .countdown:         updateCountdown(dt: dt)
        case .racing:            updateRacing(dt: dt)
        case .gameOver, .victory: return
        }
    }

    private func updateRacing(dt: CGFloat) {
        elapsed += dt
        updateSpeeds(dt: dt)
        updateRoad(dt: dt)
        updatePlayerSteering(dt: dt)
        updateAISteering(dt: dt)
        applyBumping()
        updateCarPositions(dt: dt)
        updateBagPositions(dt: dt)
        updatePickupPositions(dt: dt)
        updateInvincibility(dt: dt)
        updateCrashTimers(dt: dt)
        updateBoostTimers(dt: dt)
        spawnStep(dt: dt)
        checkCollisions()
        syncBikePositions()
        refreshHUD()
        updateMinimap()
        checkRaceEnd()
    }

    // MARK: - Speed update
    private func updateSpeeds(dt: CGFloat) {
        if !pr.isCrashing {
            let cap = pr.isBoosting ? maxSpeed * boostMult : maxSpeed
            pr.speed = min(cap, pr.speed + accel * dt)
            pr.distanceRemaining = max(0, pr.distanceRemaining - pr.speed * distPerPx * dt)
        }
        if !pk.isCrashing {
            let cap = pk.isBoosting ? maxSpeed * boostMult * 0.96 : maxSpeed * 0.96
            pk.speed = min(cap, pk.speed + accel * dt)
            pk.distanceRemaining = max(0, pk.distanceRemaining - pk.speed * distPerPx * dt)
        }
        if !gr.isCrashing {
            let cap = gr.isBoosting ? maxSpeed * boostMult * 1.01 : maxSpeed * 1.01
            gr.speed = min(cap, gr.speed + accel * dt)
            gr.distanceRemaining = max(0, gr.distanceRemaining - gr.speed * distPerPx * dt)
        }
    }

    // MARK: - Road scroll
    private func updateRoad(dt: CGFloat) {
        let s = pr.speed * dt
        roadBG1.position.y -= s; roadBG2.position.y -= s
        if roadBG1.position.y + H/2 < -H/2 { roadBG1.position.y = roadBG2.position.y + H }
        if roadBG2.position.y + H/2 < -H/2 { roadBG2.position.y = roadBG1.position.y + H }
    }

    // MARK: - Player steering
    private func updatePlayerSteering(dt: CGFloat) {
        if steerLeft  { pr.xVelocity -= steerAccel * dt }
        if steerRight { pr.xVelocity += steerAccel * dt }
        if !steerLeft && !steerRight { pr.xVelocity *= max(0, 1 - 6 * dt) }
        pr.xVelocity = pr.xVelocity.bikeClamp(-maxSteerVel...maxSteerVel)
        pr.x = (pr.x + pr.xVelocity * dt).bikeClamp(roadLeft + 10...roadRight - 10)
    }

    // MARK: - AI steering
    private func updateAISteering(dt: CGFloat) {
        updateSingleAI(racer: &pk, dt: dt)
        updateSingleAI(racer: &gr, dt: dt)
    }

    private func updateSingleAI(racer: inout RacerData, dt: CGFloat) {
        guard !racer.isCrashing else { return }
        racer.errorCooldown -= dt
        let myY = screenYFor(racer)
        var target = racer.targetLaneX

        // Dodge cars ahead
        for car in cars where car.isActive {
            let ahead = car.screenY - myY
            if ahead > 0 && ahead < 200 && abs(car.x - racer.x) < laneWidth * 0.8 {
                if racer.errorCooldown <= 0 && Float.random(in: 0...1) > 0.05 {
                    let curr = laneIndexFor(x: racer.targetLaneX)
                    let alt  = curr == 0 ? 1 : (curr == 2 ? 1 : (Bool.random() ? 0 : 2))
                    racer.targetLaneX = laneCenter[alt]
                    racer.errorCooldown = 1.5
                }
                target = racer.targetLaneX; break
            }
        }
        // Seek pickups
        for pu in pickups where pu.isActive {
            let ahead = pu.screenY - myY
            if ahead > -40 && ahead < 160 && abs(pu.x - racer.x) < laneWidth * 1.5 {
                target = pu.x; break
            }
        }

        let diff = target - racer.x
        racer.xVelocity += diff.bikeClamp(-steerAccel...steerAccel) * dt * 3
        racer.xVelocity *= max(0, 1 - 5 * dt)
        racer.xVelocity = racer.xVelocity.bikeClamp(-maxSteerVel...maxSteerVel)
        racer.x = (racer.x + racer.xVelocity * dt).bikeClamp(roadLeft + 10...roadRight - 10)
    }

    private func laneIndexFor(x: CGFloat) -> Int {
        laneCenter.enumerated().min(by: { abs($0.element - x) < abs($1.element - x) })!.offset
    }

    // MARK: - Bumping
    private func applyBumping() {
        let pyY = playerScreenY
        let pkY = screenYFor(pk)
        let grY = screenYFor(gr)

        func bump(_ r1: inout RacerData, y1: CGFloat, _ r2: inout RacerData, y2: CGFloat) {
            guard abs(y1 - y2) < 28 else { return }
            let overlap: CGFloat = 20 - abs(r1.x - r2.x)
            guard overlap > 0 else { return }
            let push = overlap / 2 + 1
            if r1.x < r2.x { r1.x -= push; r2.x += push }
            else            { r1.x += push; r2.x -= push }
            r1.x = r1.x.bikeClamp(roadLeft + 10...roadRight - 10)
            r2.x = r2.x.bikeClamp(roadLeft + 10...roadRight - 10)
            spawnSparks(at: CGPoint(x: (r1.x + r2.x) / 2, y: (y1 + y2) / 2))
        }
        bump(&pr, y1: pyY, &pk, y2: pkY)
        bump(&pr, y1: pyY, &gr, y2: grY)
        bump(&pk, y1: pkY, &gr, y2: grY)
    }

    // MARK: - Sync sprite positions
    private func syncBikePositions() {
        playerSprite.position = CGPoint(x: pr.x, y: playerScreenY)
        pinkSprite.position   = CGPoint(x: pk.x, y: screenYFor(pk))
        greenSprite.position  = CGPoint(x: gr.x, y: screenYFor(gr))
        playerSprite.zRotation = (-pr.xVelocity / maxSteerVel) * 0.20
        if let n = playerBoostNode { n.position = CGPoint(x: pr.x, y: playerScreenY - playerSprite.size.height/2 - 8) }
        if let n = pinkBoostNode   { n.position = CGPoint(x: pk.x, y: screenYFor(pk) - pinkSprite.size.height/2 - 8) }
        if let n = greenBoostNode  { n.position = CGPoint(x: gr.x, y: screenYFor(gr) - greenSprite.size.height/2 - 8) }
    }

    // MARK: - Car spawn + update
    private func spawnStep(dt: CGFloat) {
        carTimer += dt
        if carTimer >= carInterval {
            carTimer = 0; carInterval = CGFloat.random(in: 1.8...3.5); spawnCar()
        }
        pkTimer += dt
        if pkTimer >= pkInterval {
            pkTimer = 0; pkInterval = CGFloat.random(in: 3.5...7.0); spawnPickup()
        }
        bagTimer += dt
        if bagTimer >= bagInterval {
            bagTimer = 0; bagInterval = CGFloat.random(in: 2.0...3.5); spawnBeanBag()
        }
    }

    private func spawnCar() {
        let lane = Int.random(in: 0..<3); let cx = laneCenter[lane]; let spY = H/2 + 50
        for c in cars where c.isActive {
            if abs(c.x - cx) < laneWidth * 0.6 && abs(c.screenY - spY) < 80 { return }
        }
        let cidx = Int.random(in: 0..<BikeDodgeScene.carColors.count)
        let n = makeCarNode(cidx: cidx)
        n.position = CGPoint(x: cx, y: spY); n.zPosition = 9; addChild(n)
        cars.append(CarData(x: cx, screenY: spY,
                            forwardSpeed: CGFloat.random(in: 40...100), node: n))
    }

    private func updateCarPositions(dt: CGFloat) {
        for i in cars.indices {
            guard cars[i].isActive else { continue }
            cars[i].screenY -= max(0, pr.speed - cars[i].forwardSpeed) * dt
            cars[i].node.position.y = cars[i].screenY
            if cars[i].screenY < -H/2 - 80 { cars[i].node.removeFromParent(); cars[i].isActive = false }
        }
        cars.removeAll { !$0.isActive }
    }

    private func makeCarNode(cidx: Int) -> SKNode {
        let col = BikeDodgeScene.carColors[cidx]
        let cw: CGFloat = 30, ch: CGFloat = 46
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: cw, height: ch), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
            for r in [CGRect(x:0,y:3,width:6,height:10), CGRect(x:cw-6,y:3,width:6,height:10),
                      CGRect(x:0,y:ch-13,width:6,height:10), CGRect(x:cw-6,y:ch-13,width:6,height:10)] {
                c.fill(r)
            }
            c.setFillColor(col.cgColor)
            c.fill(CGRect(x: 3, y: 4, width: cw-6, height: ch-8))
            c.setFillColor(col.withAlphaComponent(0.75).cgColor)
            c.fill(CGRect(x: 5, y: ch*0.28, width: cw-10, height: ch*0.36))
            c.setFillColor(UIColor(red:0.55,green:0.75,blue:0.92,alpha:0.80).cgColor)
            c.fill(CGRect(x: 6, y: ch*0.30, width: cw-12, height: ch*0.14))
            c.fill(CGRect(x: 6, y: ch*0.52, width: cw-12, height: ch*0.10))
            c.setFillColor(UIColor(red:1.0,green:0.95,blue:0.6,alpha:1).cgColor)
            c.fill(CGRect(x:5,   y:ch-6,width:7,height:4))
            c.fill(CGRect(x:cw-12,y:ch-6,width:7,height:4))
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return SKSpriteNode(texture: tex, size: CGSize(width: cw, height: ch))
    }

    // MARK: - Bean bag
    private func spawnBeanBag() {
        let targetRacer: RacerData = Float.random(in: 0...1) < 0.70 ? pr : (Bool.random() ? pk : gr)
        let targetX: CGFloat
        let targetY: CGFloat
        if targetRacer.kind == .player {
            targetX = pr.x; targetY = playerScreenY
        } else {
            let ty = screenYFor(targetRacer); guard abs(ty) < H/2 else { return }
            targetX = targetRacer.x; targetY = ty
        }

        // Spawn from the grass just outside the road edge, ahead of the racer,
        // as though a bystander is throwing the bag onto the road.
        let aheadDist = CGFloat.random(in: H * 0.30 ... H * 0.46)
        let fromLeft = Bool.random()
        let sx: CGFloat = fromLeft
            ? roadLeft  - CGFloat.random(in: 5...22)   // just off left edge (grass)
            : roadRight + CGFloat.random(in: 5...22)   // just off right edge (grass)
        let sy = targetY + aheadDist

        // Aim toward where the racer will be, with a small lateral lead
        let lead = targetRacer.xVelocity * 0.28
        let dx = targetX + lead - sx
        let dy = targetY - sy          // always negative — bag moves downward
        let dist = max(1, sqrt(dx*dx + dy*dy))
        let spd: CGFloat = 260

        let n = SKSpriteNode(color: SKColor(red:0.15,green:0.40,blue:0.90,alpha:1),
                             size: CGSize(width:15,height:15))
        n.position = CGPoint(x: sx, y: sy); n.zPosition = 12
        n.run(.repeatForever(.rotate(byAngle: .pi * 4, duration: 0.5))); addChild(n)
        bags.append(BeanBagData(x: sx, y: sy, vx: dx/dist*spd, vy: dy/dist*spd, node: n))
    }

    private func updateBagPositions(dt: CGFloat) {
        for i in bags.indices {
            guard bags[i].isActive else { continue }
            bags[i].x += bags[i].vx * dt; bags[i].y += bags[i].vy * dt
            bags[i].node.position = CGPoint(x: bags[i].x, y: bags[i].y)
            if bags[i].x < roadLeft - 60 || bags[i].x > roadRight + 60
                || bags[i].y < -H/2 - 50 || bags[i].y > H/2 + 60 {
                bags[i].node.removeFromParent(); bags[i].isActive = false
            }
        }
        bags.removeAll { !$0.isActive }
    }

    // MARK: - Pickups
    private func spawnPickup() {
        let kind: PickupData.Kind = Float.random(in: 0...1) < 0.4 ? .heart : .boost
        let lane = Int.random(in: 0..<3); let cx = laneCenter[lane]; let spY = H/2 + 40
        for c in cars where c.isActive {
            if abs(c.x - cx) < laneWidth * 0.7 && abs(c.screenY - spY) < 60 { return }
        }
        let n = makePickupNode(kind: kind)
        n.position = CGPoint(x: cx, y: spY); n.zPosition = 8
        n.run(.repeatForever(.sequence([.scale(to:1.15,duration:0.5),.scale(to:0.90,duration:0.5)])))
        addChild(n)
        pickups.append(PickupData(kind: kind, x: cx, screenY: spY, node: n))
    }

    private func updatePickupPositions(dt: CGFloat) {
        for i in pickups.indices {
            guard pickups[i].isActive else { continue }
            pickups[i].screenY -= pr.speed * dt
            pickups[i].node.position.y = pickups[i].screenY
            if pickups[i].screenY < -H/2 - 60 { pickups[i].node.removeFromParent(); pickups[i].isActive = false }
        }
        pickups.removeAll { !$0.isActive }
    }

    private func makePickupNode(kind: PickupData.Kind) -> SKNode {
        let sz: CGFloat = 18
        let col: SKColor = kind == .heart
            ? SKColor(red:0.92,green:0.15,blue:0.15,alpha:1)
            : SKColor(red:0.20,green:0.45,blue:0.95,alpha:1)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: sz, height: sz), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(col.cgColor)
            if kind == .heart {
                let px = sz / 8
                let pts: [(Int,Int)] = [(1,0),(2,0),(5,0),(6,0),
                                        (0,1),(1,1),(2,1),(3,1),(4,1),(5,1),(6,1),(7,1),
                                        (0,2),(1,2),(2,2),(3,2),(4,2),(5,2),(6,2),(7,2),
                                        (1,3),(2,3),(3,3),(4,3),(5,3),(6,3),
                                        (2,4),(3,4),(4,4),(5,4),(3,5),(4,5),(3,6),(4,6)]
                for (px_, py_) in pts {
                    c.fill(CGRect(x:CGFloat(px_)*px,y:CGFloat(py_)*px,width:px,height:px))
                }
            } else {
                // Up-pointing arrow: tip at top, shaft extending downward
                c.move(to: CGPoint(x:sz/2,       y:2))           // tip (top)
                c.addLine(to: CGPoint(x:sz-2,    y:sz*0.55))     // right wing
                c.addLine(to: CGPoint(x:sz*0.62, y:sz*0.55))     // right inner shoulder
                c.addLine(to: CGPoint(x:sz*0.62, y:sz-2))        // right shaft end (bottom)
                c.addLine(to: CGPoint(x:sz*0.38, y:sz-2))        // left shaft end (bottom)
                c.addLine(to: CGPoint(x:sz*0.38, y:sz*0.55))     // left inner shoulder
                c.addLine(to: CGPoint(x:2,       y:sz*0.55))     // left wing
                c.closePath(); c.fillPath()
            }
        }
        let tex = SKTexture(image: img); tex.filteringMode = .nearest
        return SKSpriteNode(texture: tex, size: CGSize(width: sz, height: sz))
    }

    // MARK: - Collision detection
    private func checkCollisions() {
        checkVsCars()
        checkVsBags()
        checkVsPickups()
    }

    private func bikeRect(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x-10, y: y-16, width: 20, height: 32)
    }

    private func checkVsCars() {
        for c in cars where c.isActive {
            let cr = CGRect(x: c.x - 14, y: c.screenY - 22, width: 28, height: 44)
            if !pr.isCrashing && !pr.isInvincible && bikeRect(x:pr.x,y:playerScreenY).intersects(cr) {
                triggerCarCrash(player: true); return
            }
            let pkY = screenYFor(pk)
            if !pk.isCrashing && !pk.isInvincible && abs(pkY) < H && bikeRect(x:pk.x,y:pkY).intersects(cr) {
                triggerCarCrash(player: false, isGreen: false)
            }
            let grY = screenYFor(gr)
            if !gr.isCrashing && !gr.isInvincible && abs(grY) < H && bikeRect(x:gr.x,y:grY).intersects(cr) {
                triggerCarCrash(player: false, isGreen: true)
            }
        }
    }

    private func checkVsBags() {
        let sz: CGFloat = 14
        for i in bags.indices {
            guard bags[i].isActive else { continue }
            let br = CGRect(x:bags[i].x-sz/2, y:bags[i].y-sz/2, width:sz, height:sz)
            if !pr.isInvincible && bikeRect(x:pr.x,y:playerScreenY).intersects(br) {
                bags[i].node.removeFromParent(); bags[i].isActive = false
                damageBag(player: true); continue
            }
            let pkY = screenYFor(pk)
            if !pk.isInvincible && abs(pkY)<H && bikeRect(x:pk.x,y:pkY).intersects(br) {
                bags[i].node.removeFromParent(); bags[i].isActive = false
                damageBag(player: false, isGreen: false); continue
            }
            let grY = screenYFor(gr)
            if !gr.isInvincible && abs(grY)<H && bikeRect(x:gr.x,y:grY).intersects(br) {
                bags[i].node.removeFromParent(); bags[i].isActive = false
                damageBag(player: false, isGreen: true); continue
            }
        }
    }

    private func checkVsPickups() {
        let sz: CGFloat = 22
        for i in pickups.indices {
            guard pickups[i].isActive else { continue }
            let pr_ = CGRect(x:pickups[i].x-sz/2, y:pickups[i].screenY-sz/2, width:sz, height:sz)
            if bikeRect(x:pr.x,y:playerScreenY).intersects(pr_) {
                collectPickup(idx: i, player: true); continue
            }
            let pkY = screenYFor(pk)
            if abs(pkY)<H && bikeRect(x:pk.x,y:pkY).intersects(pr_) {
                collectPickup(idx: i, player: false); continue
            }
            let grY = screenYFor(gr)
            if abs(grY)<H && bikeRect(x:gr.x,y:grY).intersects(pr_) {
                collectPickup(idx: i, player: false); continue
            }
        }
    }

    // MARK: - Damage
    private func triggerCarCrash(player: Bool, isGreen: Bool = false) {
        if player {
            guard !pr.isCrashing && !pr.isInvincible else { return }
            playCrashAnimation(on: playerSprite)
            pr.isCrashing = true; pr.crashTimer = 2.0; pr.speed = baseSpeed
            pr.hearts = max(0, pr.hearts - 1)
            pr.isInvincible = true; pr.invTimer = 1.5
            if pr.hearts <= 0 { showGameOver() }
        } else if isGreen {
            guard !gr.isCrashing && !gr.isInvincible else { return }
            playCrashAnimation(on: greenSprite)
            gr.isCrashing = true; gr.crashTimer = 2.0; gr.speed = baseSpeed
            gr.isInvincible = true; gr.invTimer = 2.0
        } else {
            guard !pk.isCrashing && !pk.isInvincible else { return }
            playCrashAnimation(on: pinkSprite)
            pk.isCrashing = true; pk.crashTimer = 2.0; pk.speed = baseSpeed
            pk.isInvincible = true; pk.invTimer = 2.0
        }
    }

    private func playCrashAnimation(on sprite: SKSpriteNode) {
        sprite.removeAction(forKey: "crash")
        sprite.run(.sequence([
            .group([.scale(to:1.85,duration:0.22),.rotate(byAngle:.pi*2.5,duration:0.50)]),
            .group([.scale(to:1.0,duration:0.18),.rotate(toAngle:0,duration:0.18)])
        ]), withKey: "crash")
    }

    private func damageBag(player: Bool, isGreen: Bool = false) {
        let sp = player ? playerSprite! : (isGreen ? greenSprite! : pinkSprite!)
        sp.run(.sequence([.colorize(with:.white,colorBlendFactor:1.0,duration:0.05),
                          .colorize(withColorBlendFactor:0.0,duration:0.15)]))
        if player {
            guard !pr.isInvincible else { return }
            pr.hearts = max(0, pr.hearts - 1)
            pr.isInvincible = true; pr.invTimer = 1.5
            if pr.hearts <= 0 { showGameOver() }
        } else if isGreen {
            guard !gr.isInvincible else { return }
            gr.isInvincible = true; gr.invTimer = 1.5
        } else {
            guard !pk.isInvincible else { return }
            pk.isInvincible = true; pk.invTimer = 1.5
        }
    }

    private func collectPickup(idx: Int, player: Bool) {
        let pu = pickups[idx]
        pu.node.run(.sequence([.scale(to:1.5,duration:0.1),.fadeOut(withDuration:0.1),.removeFromParent()]))
        pickups[idx].isActive = false
        if player {
            switch pu.kind {
            case .heart: pr.hearts = min(pr.maxHearts, pr.hearts + 1)
            case .boost:
                pr.isBoosting = true; pr.boostTimer = 2.0
                attachBoost(to: playerSprite, store: &playerBoostNode)
            }
        } else {
            if pu.kind == .boost {
                if Bool.random() {
                    gr.isBoosting = true; gr.boostTimer = 2.0
                    attachBoost(to: greenSprite, store: &greenBoostNode)
                } else {
                    pk.isBoosting = true; pk.boostTimer = 2.0
                    attachBoost(to: pinkSprite, store: &pinkBoostNode)
                }
            }
        }
    }

    private func attachBoost(to sprite: SKSpriteNode, store: inout SKNode?) {
        store?.removeFromParent()
        let flame = SKSpriteNode(color: SKColor(red:0.25,green:0.55,blue:1.0,alpha:0.85),
                                 size: CGSize(width:10,height:18))
        flame.position  = CGPoint(x: sprite.position.x, y: sprite.position.y - sprite.size.height/2 - 8)
        flame.zPosition = 9
        flame.run(.repeatForever(.sequence([.scale(to:1.4,duration:0.08),.scale(to:0.75,duration:0.08)])))
        addChild(flame); store = flame
    }

    // MARK: - Timer helpers
    private func updateInvincibility(dt: CGFloat) {
        func tick(racer: inout RacerData, sprite: SKSpriteNode) {
            guard racer.isInvincible else { return }
            racer.invTimer -= dt
            sprite.alpha = fmod(racer.invTimer * 8, 2) < 1 ? 0.35 : 1.0
            if racer.invTimer <= 0 { racer.isInvincible = false; sprite.alpha = 1.0 }
        }
        tick(racer: &pr, sprite: playerSprite)
        tick(racer: &pk, sprite: pinkSprite)
        tick(racer: &gr, sprite: greenSprite)
    }

    private func updateCrashTimers(dt: CGFloat) {
        func tick(racer: inout RacerData) {
            guard racer.isCrashing else { return }
            racer.crashTimer -= dt
            if racer.crashTimer <= 0 { racer.isCrashing = false }
        }
        tick(racer: &pr); tick(racer: &pk); tick(racer: &gr)
    }

    private func updateBoostTimers(dt: CGFloat) {
        func tick(racer: inout RacerData, boostNode: inout SKNode?) {
            guard racer.isBoosting else { return }
            racer.boostTimer -= dt
            if racer.boostTimer <= 0 {
                racer.isBoosting = false
                boostNode?.removeFromParent(); boostNode = nil
            }
        }
        tick(racer: &pr, boostNode: &playerBoostNode)
        tick(racer: &pk, boostNode: &pinkBoostNode)
        tick(racer: &gr, boostNode: &greenBoostNode)
    }

    // MARK: - Race end
    private func checkRaceEnd() {
        func markFinish(racer: inout RacerData) {
            guard !racer.finished && racer.distanceRemaining <= 0 else { return }
            racer.finished = true; finishCount += 1; racer.finishRank = finishCount
        }
        markFinish(racer: &pr); markFinish(racer: &pk); markFinish(racer: &gr)

        if pr.finished && pr.finishRank == 1 { showVictory(); return }
        if (pk.finished && pk.finishRank == 1) || (gr.finished && gr.finishRank == 1) {
            showGameOver(aiWon: true)
        }
    }

    // MARK: - End screens
    private func showGameOver(aiWon: Bool = false) {
        guard gState == .racing else { return }
        gState = .gameOver
        let sub = aiWon ? "AN AI FINISHED FIRST" : "YOU CRASHED OUT"
        let ov = buildEndOverlay(title: "RACE OVER", subtitle: sub,
                                 titleColor: SKColor(red:0.95,green:0.25,blue:0.25,alpha:1))
        onComplete?(false); addChild(ov); overlayNode = ov
    }

    private func showVictory() {
        guard gState == .racing else { return }
        gState = .victory
        let m = Int(elapsed)/60, s = Int(elapsed)%60
        let ov = buildEndOverlay(title: "1ST PLACE!",
                                 subtitle: String(format:"TIME  %d:%02d",m,s),
                                 titleColor: SKColor(red:0.95,green:0.85,blue:0.10,alpha:1))
        onComplete?(true); addChild(ov); overlayNode = ov
    }

    private func buildEndOverlay(title: String, subtitle: String, titleColor: SKColor) -> SKNode {
        let ov = buildOverlayContainer()
        let bg = SKShapeNode(rect: CGRect(x:-W/2,y:-H/2,width:W,height:H))
        bg.fillColor = SKColor(white:0,alpha:0.75); bg.strokeColor = .clear; ov.addChild(bg)
        ov.addChild(label(title, font:"PressStart2P-Regular", size:min(22,W/16), color:titleColor, at:CGPoint(x:0,y:80)))
        ov.addChild(label(subtitle, font:"PressStart2P-Regular", size:min(9,W/38), color:.white, at:CGPoint(x:0,y:40)))

        let replay = label("▶ PLAY AGAIN", font:"PressStart2P-Regular", size:min(13,W/26), color:.white, at:CGPoint(x:0,y:-20))
        replay.name = "replayBtn"
        replay.run(.repeatForever(.sequence([.scale(to:1.05,duration:0.5),.scale(to:0.95,duration:0.5)])))
        ov.addChild(replay)

        let menuLbl = label("MAIN MENU", font:"PressStart2P-Regular", size:min(10,W/34),
                            color:SKColor(white:0.65,alpha:1), at:CGPoint(x:0,y:-58))
        menuLbl.name = "menuBtn"
        ov.addChild(menuLbl)
        return ov
    }

    private func buildOverlayContainer() -> SKNode {
        let n = SKNode(); n.zPosition = 100; return n
    }

    // MARK: - Reset
    private func resetGame() {
        cars.forEach    { $0.node.removeFromParent() }
        bags.forEach    { $0.node.removeFromParent() }
        pickups.forEach { $0.node.removeFromParent() }
        cars.removeAll(); bags.removeAll(); pickups.removeAll()
        playerBoostNode?.removeFromParent(); playerBoostNode = nil
        pinkBoostNode?.removeFromParent();   pinkBoostNode   = nil
        greenBoostNode?.removeFromParent();  greenBoostNode  = nil
        overlayNode?.removeFromParent();     overlayNode     = nil

        pr = RacerData(kind: .player); pk = RacerData(kind: .pink); gr = RacerData(kind: .green)
        pr.x = laneCenter[1]; pr.speed = baseSpeed
        pk.x = laneCenter[0]; pk.speed = baseSpeed; pk.targetLaneX = laneCenter[0]
        gr.x = laneCenter[2]; gr.speed = baseSpeed; gr.targetLaneX = laneCenter[2]

        for sp in [playerSprite, pinkSprite, greenSprite] {
            sp?.setScale(1); sp?.zRotation = 0; sp?.alpha = 1; sp?.removeAction(forKey: "crash")
        }
        elapsed = 0; finishCount = 0
        carTimer = 1.5; pkTimer = 4.0; bagTimer = 2.0
        steerLeft = false; steerRight = false
        leftTouches.removeAll(); rightTouches.removeAll()
        lastTime = 0
        startCountdown()
    }

    // MARK: - Helpers
    private func screenYFor(_ r: RacerData) -> CGFloat {
        if r.kind == .player { return playerScreenY }
        return playerScreenY + (pr.distanceRemaining - r.distanceRemaining) * distToPixScale
    }

    private func spawnSparks(at pos: CGPoint) {
        for _ in 0..<5 {
            let sp = SKSpriteNode(color: SKColor(red:1,green:0.90,blue:0.20,alpha:1), size:CGSize(width:4,height:4))
            sp.position = pos; sp.zPosition = 25; addChild(sp)
            sp.run(.sequence([.group([
                .moveBy(x:CGFloat.random(in:-70...70), y:CGFloat.random(in:-50...50), duration:0.28),
                .fadeOut(withDuration:0.28)]), .removeFromParent()]))
        }
    }

    private func label(_ text: String, font: String, size: CGFloat, color: SKColor, at pos: CGPoint) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font)
        l.text = text; l.fontSize = size; l.fontColor = color
        l.horizontalAlignmentMode = .center; l.verticalAlignmentMode = .center
        l.position = pos; return l
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let loc = t.location(in: self)
            switch gState {
            case .menu: startCountdown(); return
            case .countdown: return
            case .racing:
                if loc.x < 0 { leftTouches.insert(t); steerLeft = true }
                else          { rightTouches.insert(t); steerRight = true }
            case .gameOver, .victory:
                let n = atPoint(loc)
                let name = n.name ?? n.parent?.name ?? ""
                if name == "replayBtn" { resetGame() }
                else if name == "menuBtn" { dismissToMenu() }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        leftTouches.subtract(touches); rightTouches.subtract(touches)
        steerLeft = !leftTouches.isEmpty; steerRight = !rightTouches.isEmpty
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func dismissToMenu() {
        bikeDodgeDelegate?.bikeDodgeSceneDidRequestDismiss(self)
        onComplete?(false)
    }
}

// MARK: - Numeric clamp helper (scoped to this file)
private extension CGFloat {
    func bikeClamp(_ range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
