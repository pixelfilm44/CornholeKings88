import SpriteKit
import UIKit

// MARK: - MopBucketChaseScene
//
// Chapter 3 chase: Billy Badger socks Jack and bolts down a hallway, then
// stops to wait by the far doors — smug, bouncing in place, daring Jack to
// catch up. Jack — one foot in a rolling mop bucket — rows after him with
// the mop. Overhead vertical-scrolling chase (same top-down camera as the
// bike race):
//
//   TAP     — plant-and-sweep the mop in one motion; Jack surges forward.
//             Speed decays via glide friction between taps, so tap again to
//             keep the pace up.
//   SWIPE   — left/right shifts Jack a lane to dodge hallway obstacles.
//
// The hall is a 3-lane course seeded fresh each run: kids, wet-floor signs,
// limbo mop bars (one open lane), waxed strips (never stroke on wax),
// puddles (a stroke landing inside is a SUPER STROKE), spray-bottle kids
// who mist the screen, swinging classroom doors (timed dodges), pacing hall
// monitors, and high-five kids who grant a speed burst. Billy — waiting
// stationary at the end — occasionally hurls his binder back down Jack's
// lane once Jack is close enough. Every crash costs a heart (universal
// `HeartsManager`); run out and it's over regardless of the clock. A
// side-view progress tracker under the ribbon shows Jack, Billy, and the
// far doors.
//
// The goal is simply to reach Billy before a 60-second clock runs out,
// without crashing too much. Winning triggers the scripted cinematic
// finale — slow-mo through the janitor water, spin-out, and a spectacular
// pile-up into Becky (books, papers, ricocheting bucket, gawking
// onlookers, Billy laughing his way out the doors). Running out of time or
// hearts ends the chase before the crash ever happens.
//
// Pure story beat / picker replay — no rewards in any context.
final class MopBucketChaseScene: SKScene {

    // MARK: - Public
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    var awardsRewards: Bool = false

    // MARK: - Tunables (all speed/length values scale with scene width)
    private var W: CGFloat { size.width }
    private var H: CGFloat { size.height }
    private var maxSpeed:  CGFloat { W * 1.70 }
    private var strokeImpulse: CGFloat { W * 1.15 }   // fixed speed gain per tap
    private var fastThreshold: CGFloat { W * 0.80 }   // speed-streak FX cutoff
    private var hallLength: CGFloat { W * 46.0 }
    /// Billy waits here for the whole race — close enough to the doors to
    /// read as "about to leave," far enough to leave room for the water and
    /// Becky to be placed ahead of him once the crash triggers.
    private var billyWaitDist: CGFloat { hallLength - W * 2.0 }
    /// Jack must reach this world-Y before the crash cutscene can trigger.
    private var finaleZoneStart: CGFloat { billyWaitDist - W * 0.15 }
    /// Billy's "he's had enough of waiting" exit speed — used for the
    /// crash-finale peel-off and the time's-up escape.
    private var billyFleeSpeed: CGFloat { W * 1.3 }
    private let frictionK: CGFloat = 0.55       // glide decay rate
    private let swipeThreshold: CGFloat = 30
    /// Reach Billy before this clock runs out, or he leaves without you.
    private let raceTimeLimit: TimeInterval = 60.0

    // MARK: - Lanes (overhead 3-lane hallway)
    private var hallWidth: CGFloat { W * 0.70 }
    private var laneW: CGFloat { hallWidth / 3 }
    private func laneCenterX(_ i: Int) -> CGFloat {
        -hallWidth / 2 + laneW * (CGFloat(i) + 0.5)
    }
    private var jackScreenY: CGFloat { -H * 0.22 }

    // MARK: - Phase
    private enum ChasePhase { case racing, finale, done }
    private var phase: ChasePhase = .racing
    private var isGameOver = false
    private var isPausedGame = false
    private var countdownActive = true
    private var tutorialUp = false
    private var confirmingQuit = false

    // MARK: - Obstacles
    private enum ObstacleKind { case kid, sign, limbo, puddle, wax, spray, highFive }
    private struct Obstacle {
        let kind: ObstacleKind
        let dist: CGFloat            // world-Y center (point) or start (zone)
        let length: CGFloat          // zone length; 0 for point obstacles
        let lanes: Set<Int>          // lanes that collide / react
        let node: SKNode
        var triggered = false
    }
    private var obstacles: [Obstacle] = []

    /// Classroom door that swings open into an outer lane on a sine cycle.
    private struct SwingDoor {
        let dist: CGFloat
        let lane: Int                // 0 (left wall) or 2 (right wall)
        let panel: SKSpriteNode
        let speed: CGFloat
        let phase: CGFloat
        var hit = false
    }
    private var swingDoors: [SwingDoor] = []

    /// Hall monitor pacing side-to-side across all three lanes.
    private struct HallMonitor {
        let dist: CGFloat
        let node: SKNode
        let speed: CGFloat
        let phase: CGFloat
        var hit = false
    }
    private var hallMonitors: [HallMonitor] = []

    /// Binder Billy hurls back down Jack's lane.
    private struct BillyProjectile {
        var dist: CGFloat
        let lane: Int
        let node: SKNode
        var active = true
    }
    private var projectiles: [BillyProjectile] = []
    private var nextBillyThrow: TimeInterval = 4.0

    // MARK: - Race state
    private var jackDist:  CGFloat = 0
    private var billyDist: CGFloat = 0
    private var jackSpeed: CGFloat = 0
    private var jackX: CGFloat = 0
    private var targetLane = 1
    private var raceClock: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var streakAccum: CGFloat = 0
    private var skidAccum: CGFloat = 0
    private var finaleImpacted = false
    private var finaleWaterHit = false
    private var finaleTimeScale: CGFloat = 1
    private var beckyShrieked = false
    private var beckyDist: CGFloat = 0
    private var finaleWaterDist: CGFloat = 0
    private var didWin = false
    private enum LoseReason { case timeOut, heartsGone }
    private var loseReason: LoseReason = .timeOut

    // MARK: - Input tracking
    private var strokeTouch: UITouch?
    private var swipeRefX: CGFloat = 0
    private var touchDidSteer = false

    // MARK: - Nodes
    private var scrollLayer: SKNode!
    private var floorBG1: SKSpriteNode!
    private var floorBG2: SKSpriteNode!
    private var jackNode: SKNode?
    private var bucketNode: SKNode?
    private var mopNode: SKSpriteNode?
    private var billyNode: SKNode?
    private var beckyNode: SKNode?
    private var mistOverlay: SKSpriteNode?
    private var heartSprites: [SKLabelNode] = []
    private var timeLabel: SKLabelNode?
    private var trackJack: SKNode?
    private var trackBilly: SKNode?
    private var trackWidth: CGFloat = 0
    private var messageNode: SKNode?
    private var pauseOverlayNode: SKNode?
    private var confirmPanel: SKNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = SKColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1)

        if HeartsManager.shared.currentHearts <= 0 { HeartsManager.shared.refill() }
        billyDist = billyWaitDist   // Billy runs ahead once and waits here
        jackX = laneCenterX(1)

        buildFloor()
        buildWorld()
        buildJack()
        setupUI()
        addCrtOverlay()

        if TutorialManager.shared.hasSeen(TutorialManager.mopChase) {
            startCountdown()
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    // MARK: - Floor (screen-anchored, scrolls like the bike-race road)

    private func buildFloor() {
        let tex = makeHallTexture()
        let sz = CGSize(width: W, height: H)
        floorBG1 = SKSpriteNode(texture: tex, size: sz)
        floorBG1.position = .zero; floorBG1.zPosition = -5; addChild(floorBG1)
        floorBG2 = SKSpriteNode(texture: tex, size: sz)
        floorBG2.position = CGPoint(x: 0, y: H); floorBG2.zPosition = -5; addChild(floorBG2)
    }

    /// Overhead school hallway: pale tile floor with grout lines, locker
    /// strips along both walls, dark out-of-bounds beyond them.
    private func makeHallTexture() -> SKTexture {
        let iw = W, ih = H
        let hallL = iw / 2 - hallWidth / 2
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: iw, height: ih), format: fmt).image { ctx in
            let c = ctx.cgContext
            // Out-of-bounds walls.
            c.setFillColor(UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: iw, height: ih))
            // Hall floor.
            c.setFillColor(UIColor(red: 0.72, green: 0.74, blue: 0.66, alpha: 1).cgColor)
            c.fill(CGRect(x: hallL, y: 0, width: hallWidth, height: ih))
            // Tile grout grid (must tile vertically — step divides ih exactly).
            c.setFillColor(UIColor(white: 0.45, alpha: 0.35).cgColor)
            let rows = max(8, Int(ih / 34))
            let stepY = ih / CGFloat(rows)
            var y: CGFloat = 0
            while y < ih - 1 { c.fill(CGRect(x: hallL, y: y, width: hallWidth, height: 1)); y += stepY }
            let cols = 6
            let stepX = hallWidth / CGFloat(cols)
            var x = hallL
            while x <= hallL + hallWidth { c.fill(CGRect(x: x, y: 0, width: 1, height: ih)); x += stepX }
            // Lane hint dashes on the two inner lane lines.
            c.setFillColor(UIColor(white: 0.40, alpha: 0.30).cgColor)
            for lx in [hallL + hallWidth / 3, hallL + hallWidth * 2 / 3] {
                var dy: CGFloat = 0
                while dy < ih { c.fill(CGRect(x: lx - 1, y: dy, width: 2, height: 12)); dy += stepY }
            }
            // Locker strips (viewed from above) along both walls.
            let lockerD: CGFloat = 16
            let lockerHues: [UIColor] = [
                UIColor(red: 0.30, green: 0.42, blue: 0.55, alpha: 1),
                UIColor(red: 0.26, green: 0.38, blue: 0.50, alpha: 1),
                UIColor(red: 0.34, green: 0.46, blue: 0.58, alpha: 1),
            ]
            for side in 0..<2 {
                let lx = side == 0 ? hallL - lockerD : hallL + hallWidth
                var ly: CGFloat = 0
                var idx = 0
                while ly < ih {
                    c.setFillColor(lockerHues[idx % lockerHues.count].cgColor)
                    c.fill(CGRect(x: lx, y: ly, width: lockerD, height: stepY - 2))
                    c.setFillColor(UIColor(white: 0.9, alpha: 0.5).cgColor)
                    c.fill(CGRect(x: side == 0 ? lx + lockerD - 4 : lx + 2,
                                  y: ly + stepY / 2 - 1, width: 2, height: 2))
                    ly += stepY; idx += 1
                }
            }
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    private func scrollFloor(by dy: CGFloat) {
        floorBG1.position.y -= dy; floorBG2.position.y -= dy
        if floorBG1.position.y < -H { floorBG1.position.y = floorBG2.position.y + H }
        if floorBG2.position.y < -H { floorBG2.position.y = floorBG1.position.y + H }
    }

    // MARK: - World (scrollLayer holds every world-anchored entity; world-Y = hall distance)

    private func buildWorld() {
        let layer = SKNode()
        layer.zPosition = 10
        addChild(layer)
        scrollLayer = layer

        buildDoors(in: layer)
        buildSectionLabels(in: layer)
        buildCourse(in: layer)
        buildBilly(in: layer)
        layoutWorld()
    }

    private func buildDoors(in layer: SKNode) {
        let doors = SKNode()
        let slab = SKSpriteNode(color: SKColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1),
                                size: CGSize(width: hallWidth, height: 18))
        doors.addChild(slab)
        let seam = SKSpriteNode(color: SKColor(white: 0, alpha: 0.4), size: CGSize(width: 2, height: 18))
        doors.addChild(seam)
        for sx: CGFloat in [-hallWidth * 0.25, hallWidth * 0.25] {
            let bar = SKSpriteNode(color: SKColor(red: 0.85, green: 0.72, blue: 0.30, alpha: 1),
                                   size: CGSize(width: hallWidth * 0.34, height: 4))
            bar.position = CGPoint(x: sx, y: -4)
            doors.addChild(bar)
        }
        let exit = SKLabelNode(fontNamed: "PressStart2P-Regular")
        exit.text = "EXIT"
        exit.fontSize = 7
        exit.fontColor = SKColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 0.9)
        exit.horizontalAlignmentMode = .center
        exit.position = CGPoint(x: 0, y: 14)
        doors.addChild(exit)
        doors.position = CGPoint(x: 0, y: hallLength)
        doors.zPosition = 8
        layer.addChild(doors)
    }

    private func buildSectionLabels(in layer: SKNode) {
        let sections: [(CGFloat, String)] = [
            (0.06, "GYM HALL"), (0.36, "CAFETERIA"), (0.66, "TROPHY HALL"),
            (0.90, "MAIN HALL"),
        ]
        for (frac, name) in sections {
            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text = name
            lbl.fontSize = 8
            lbl.fontColor = SKColor(white: 0.30, alpha: 0.45)
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: 0, y: hallLength * frac)
            lbl.zPosition = 6
            layer.addChild(lbl)
        }
    }

    /// Seeds the whole course: scripted major zones + random single-lane
    /// filler obstacles. Fresh layout every run/replay.
    private func buildCourse(in layer: SKNode) {
        obstacles.removeAll()
        swingDoors.removeAll()
        hallMonitors.removeAll()
        projectiles.removeAll()

        // — Scripted majors —
        var majorSpans: [ClosedRange<CGFloat>] = []
        func reserve(_ start: CGFloat, _ len: CGFloat) {
            majorSpans.append((start - W * 0.4)...(start + len + W * 0.4))
        }
        func at(_ frac: CGFloat) -> CGFloat { hallLength * frac }

        for f in [0.14, 0.44, 0.78] {
            addWaxZone(at: at(f), length: W * 0.85, in: layer); reserve(at(f), W * 0.85)
        }
        for f in [0.22, 0.52, 0.86] {
            addLimbo(at: at(f), gapLane: Bool.random() ? 0 : 2, in: layer); reserve(at(f), 0)
        }
        for f in [0.30, 0.68] {
            addSprayKid(at: at(f), in: layer); reserve(at(f), 0)
        }
        for f in [0.37, 0.60, 0.92] {
            addPuddle(at: at(f), length: W * 0.80, in: layer); reserve(at(f), W * 0.80)
        }
        for (i, f) in [0.18, 0.405, 0.63, 0.82].enumerated() {
            addSwingDoor(at: at(f), lane: i % 2 == 0 ? 0 : 2, in: layer); reserve(at(f), 0)
        }
        for f in [0.26, 0.56, 0.74] {
            addHallMonitor(at: at(f), in: layer); reserve(at(f), 0)
        }
        for (i, f) in [0.12, 0.335, 0.48, 0.665, 0.88].enumerated() {
            addHighFiveKid(at: at(f), lane: i % 2 == 0 ? 2 : 0, in: layer); reserve(at(f), 0)
        }

        // — Random fillers (kids + wet-floor signs) — stop with clearance
        // before Billy's fixed waiting spot so nothing spawns on top of him.
        var d = hallLength * 0.05
        while d < billyWaitDist - W * 0.6 {
            d += CGFloat.random(in: (W * 0.85)...(W * 1.35))
            if majorSpans.contains(where: { $0.contains(d) }) { continue }
            let lane = Int.random(in: 0...2)
            if Bool.random() {
                addKidObstacle(at: d, lane: lane, in: layer)
            } else {
                addSignObstacle(at: d, lane: lane, in: layer)
            }
        }
    }

    private func addKidObstacle(at dist: CGFloat, lane: Int, in layer: SKNode) {
        let shirts: [SKColor] = [
            SKColor(red: 0.60, green: 0.40, blue: 0.65, alpha: 1),
            SKColor(red: 0.30, green: 0.60, blue: 0.40, alpha: 1),
            SKColor(red: 0.80, green: 0.60, blue: 0.20, alpha: 1),
            SKColor(red: 0.35, green: 0.45, blue: 0.75, alpha: 1),
        ]
        let kid = makeTopKid(shirt: shirts.randomElement()!,
                             hair: SKColor(red: 0.20, green: 0.13, blue: 0.06, alpha: 1))
        kid.position = CGPoint(x: laneCenterX(lane) + CGFloat.random(in: -6...6), y: dist)
        kid.zPosition = 20
        kid.run(.repeatForever(.sequence([
            .rotate(toAngle: 0.10, duration: 0.5),
            .rotate(toAngle: -0.10, duration: 0.5),
        ])))
        layer.addChild(kid)
        obstacles.append(Obstacle(kind: .kid, dist: dist, length: 0, lanes: [lane], node: kid))
    }

    private func addSignObstacle(at dist: CGFloat, lane: Int, in layer: SKNode) {
        let sign = SKNode()
        let base = SKSpriteNode(color: SKColor(red: 0.92, green: 0.80, blue: 0.15, alpha: 1),
                                size: CGSize(width: 28, height: 32))
        sign.addChild(base)
        let stripe = SKSpriteNode(color: SKColor(red: 0.60, green: 0.15, blue: 0.10, alpha: 1),
                                  size: CGSize(width: 28, height: 6))
        stripe.position = CGPoint(x: 0, y: 6)
        sign.addChild(stripe)
        sign.position = CGPoint(x: laneCenterX(lane), y: dist)
        sign.zPosition = 20
        layer.addChild(sign)
        obstacles.append(Obstacle(kind: .sign, dist: dist, length: 0, lanes: [lane], node: sign))
    }

    /// Two kids stretch a mop bar across two adjacent lanes — steer for the gap.
    private func addLimbo(at dist: CGFloat, gapLane: Int, in layer: SKNode) {
        let lanes: Set<Int> = gapLane == 0 ? [1, 2] : [0, 1]
        let group = SKNode()
        let minLane = lanes.min()!, maxLane = lanes.max()!
        let barL = laneCenterX(minLane) - laneW * 0.35
        let barR = laneCenterX(maxLane) + laneW * 0.35
        let bar = SKSpriteNode(color: SKColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1),
                               size: CGSize(width: barR - barL, height: 8))
        bar.position = CGPoint(x: (barL + barR) / 2, y: 0)
        group.addChild(bar)
        for bx in [barL, barR] {
            let kid = makeTopKid(shirt: SKColor(red: 0.60, green: 0.40, blue: 0.65, alpha: 1),
                                 hair: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1))
            kid.position = CGPoint(x: bx, y: 0)
            group.addChild(kid)
        }
        group.position = CGPoint(x: 0, y: dist)
        group.zPosition = 21
        layer.addChild(group)
        obstacles.append(Obstacle(kind: .limbo, dist: dist, length: 0, lanes: lanes, node: group))
    }

    private func addPuddle(at dist: CGFloat, length: CGFloat, in layer: SKNode) {
        let puddle = SKShapeNode(ellipseOf: CGSize(width: hallWidth * 0.86, height: length))
        puddle.fillColor = SKColor(red: 0.35, green: 0.60, blue: 0.90, alpha: 0.40)
        puddle.strokeColor = SKColor(red: 0.45, green: 0.70, blue: 0.95, alpha: 0.55)
        puddle.position = CGPoint(x: 0, y: dist + length / 2)
        puddle.zPosition = 12
        puddle.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.85, duration: 0.6),
            .fadeAlpha(to: 0.5, duration: 0.6),
        ])))
        layer.addChild(puddle)
        obstacles.append(Obstacle(kind: .puddle, dist: dist, length: length,
                                  lanes: [0, 1, 2], node: puddle))
    }

    private func addWaxZone(at dist: CGFloat, length: CGFloat, in layer: SKNode) {
        let zone = SKNode()
        let strip = SKSpriteNode(color: SKColor(red: 0.95, green: 0.93, blue: 0.80, alpha: 0.45),
                                 size: CGSize(width: hallWidth, height: length))
        zone.addChild(strip)
        for _ in 0..<5 {
            let sheen = SKSpriteNode(color: SKColor(white: 1.0, alpha: 0.5),
                                     size: CGSize(width: CGFloat.random(in: 14...30), height: 2))
            sheen.position = CGPoint(x: CGFloat.random(in: -hallWidth * 0.4...hallWidth * 0.4),
                                     y: CGFloat.random(in: -length * 0.4...length * 0.4))
            sheen.zRotation = 0.5
            zone.addChild(sheen)
        }
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = "WAX"
        lbl.fontSize = 7
        lbl.fontColor = SKColor(red: 0.55, green: 0.45, blue: 0.15, alpha: 0.8)
        lbl.verticalAlignmentMode = .center
        zone.addChild(lbl)
        zone.position = CGPoint(x: 0, y: dist + length / 2)
        zone.zPosition = 12
        layer.addChild(zone)
        obstacles.append(Obstacle(kind: .wax, dist: dist, length: length,
                                  lanes: [0, 1, 2], node: zone))
    }

    private func addSprayKid(at dist: CGFloat, in layer: SKNode) {
        let kid = makeTopKid(shirt: SKColor(red: 0.30, green: 0.60, blue: 0.70, alpha: 1),
                             hair: SKColor(red: 0.72, green: 0.58, blue: 0.24, alpha: 1))
        let bottle = SKSpriteNode(color: SKColor(red: 0.30, green: 0.75, blue: 0.90, alpha: 1),
                                  size: CGSize(width: 4, height: 7))
        bottle.position = CGPoint(x: 8, y: 0)
        kid.addChild(bottle)
        kid.position = CGPoint(x: -hallWidth / 2 + 8, y: dist)
        kid.zPosition = 20
        layer.addChild(kid)
        obstacles.append(Obstacle(kind: .spray, dist: dist, length: 0, lanes: [], node: kid))
    }

    /// Classroom door on a wall — swings open into the outer lane on a sine
    /// cycle (driven manually in update, so it pauses cleanly).
    private func addSwingDoor(at dist: CGFloat, lane: Int, in layer: SKNode) {
        let wallX: CGFloat = lane == 0 ? -hallWidth / 2 : hallWidth / 2
        // Door frame painted on the wall.
        let frame = SKSpriteNode(color: SKColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1),
                                 size: CGSize(width: 12, height: laneW * 0.9))
        frame.position = CGPoint(x: wallX + (lane == 0 ? -6 : 6), y: dist)
        frame.zPosition = 18
        layer.addChild(frame)
        // Swinging panel — hinge (anchor) at the wall.
        let panel = SKSpriteNode(color: SKColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1),
                                 size: CGSize(width: 10, height: laneW * 0.92))
        panel.anchorPoint = CGPoint(x: 0.5, y: 0)
        panel.position = CGPoint(x: wallX, y: dist - laneW * 0.45)
        panel.zPosition = 22
        let knob = SKSpriteNode(color: SKColor(red: 0.85, green: 0.72, blue: 0.30, alpha: 1),
                                size: CGSize(width: 3, height: 3))
        knob.position = CGPoint(x: 0, y: laneW * 0.82)
        panel.addChild(knob)
        layer.addChild(panel)
        swingDoors.append(SwingDoor(dist: dist, lane: lane, panel: panel,
                                    speed: CGFloat.random(in: 1.6...2.4),
                                    phase: CGFloat.random(in: 0...(2 * .pi))))
    }

    /// Hall monitor kid pacing side-to-side across the full hall width.
    private func addHallMonitor(at dist: CGFloat, in layer: SKNode) {
        let kid = makeTopKid(shirt: SKColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1),
                             hair: SKColor(red: 0.10, green: 0.08, blue: 0.05, alpha: 1))
        // Safety sash.
        let sash = SKSpriteNode(color: SKColor(red: 0.98, green: 0.85, blue: 0.20, alpha: 1),
                                size: CGSize(width: 4, height: 14))
        sash.zRotation = 0.6
        sash.zPosition = 3
        kid.addChild(sash)
        addAuraRing(to: kid, color: SKColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 0.9))
        kid.position = CGPoint(x: 0, y: dist)
        kid.zPosition = 22
        layer.addChild(kid)
        hallMonitors.append(HallMonitor(dist: dist, node: kid,
                                        speed: CGFloat.random(in: 1.1...1.7),
                                        phase: CGFloat.random(in: 0...(2 * .pi))))
    }

    /// Friendly kid at the lockers with a hand out — hug that wall lane for
    /// a free speed burst.
    private func addHighFiveKid(at dist: CGFloat, lane: Int, in layer: SKNode) {
        let kid = makeTopKid(shirt: SKColor(red: 0.25, green: 0.70, blue: 0.55, alpha: 1),
                             hair: SKColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1))
        let wallX: CGFloat = lane == 0 ? -hallWidth / 2 + 6 : hallWidth / 2 - 6
        let armDir: CGFloat = lane == 0 ? 1 : -1
        let arm = SKSpriteNode(color: SKColor(red: 0.94, green: 0.78, blue: 0.60, alpha: 1),
                               size: CGSize(width: 10, height: 3))
        arm.position = CGPoint(x: armDir * 11, y: 0)
        arm.run(.repeatForever(.sequence([
            .moveBy(x: armDir * 2, y: 0, duration: 0.3),
            .moveBy(x: -armDir * 2, y: 0, duration: 0.3),
        ])))
        kid.addChild(arm)
        addAuraRing(to: kid, color: SKColor(red: 0.35, green: 0.90, blue: 0.55, alpha: 0.9))
        kid.position = CGPoint(x: wallX, y: dist)
        kid.zPosition = 20
        layer.addChild(kid)
        obstacles.append(Obstacle(kind: .highFive, dist: dist, length: 0, lanes: [lane], node: kid))
    }

    /// Tiny overhead pixel kid: shoulders + head + hair, viewed from above.
    /// Uniform character scale — everyone drawn via `makeTopKid` (obstacle
    /// kids, Billy, Becky, onlookers, flying Jack) reads at 2× size. Jack's
    /// bucket rig is scaled separately as a whole in `buildJack` so its body
    /// isn't scaled twice; pass `scaled: false` there.
    private let characterScale: CGFloat = 2.0

    private func makeTopKid(shirt: SKColor, hair: SKColor, scaled: Bool = true,
                            shadow: Bool = true) -> SKNode {
        let kid = SKNode()
        let ink = SKColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 1)
        let skin = SKColor(red: 0.94, green: 0.78, blue: 0.60, alpha: 1)
        // Ground shadow anchors the kid to the floor and lifts the silhouette
        // off same-value tiles.
        if shadow {
            let drop = SKShapeNode(ellipseOf: CGSize(width: 21, height: 14))
            drop.fillColor = SKColor(white: 0, alpha: 0.30)
            drop.strokeColor = .clear
            drop.position = CGPoint(x: 1, y: -2)
            drop.zPosition = -1
            kid.addChild(drop)
        }
        // Dark outline backing behind the shoulders — the 1px "sprite border".
        let outline = SKSpriteNode(color: ink, size: CGSize(width: 17, height: 12))
        outline.zPosition = -0.5
        kid.addChild(outline)
        let shoulders = SKSpriteNode(color: shirt, size: CGSize(width: 15, height: 10))
        kid.addChild(shoulders)
        // Skin-tone arm nubs at the shoulder ends sell "person from above".
        for side: CGFloat in [-1, 1] {
            let arm = SKSpriteNode(color: skin, size: CGSize(width: 3, height: 5))
            arm.position = CGPoint(x: side * 7.5, y: -2)
            arm.zPosition = 0.5
            kid.addChild(arm)
        }
        let head = SKShapeNode(circleOfRadius: 4.5)
        head.fillColor = skin
        head.strokeColor = ink
        head.lineWidth = 1.2
        head.zPosition = 1
        kid.addChild(head)
        let cap = SKShapeNode(circleOfRadius: 3.4)
        cap.fillColor = hair
        cap.strokeColor = .clear
        cap.position = CGPoint(x: 0, y: 1.2)
        cap.zPosition = 2
        kid.addChild(cap)
        // Hair shine — a light catch so heads read as round, not flat dots.
        let shine = SKSpriteNode(color: SKColor(white: 1, alpha: 0.35),
                                 size: CGSize(width: 3, height: 1.5))
        shine.position = CGPoint(x: -1.2, y: 3.0)
        shine.zPosition = 2.5
        kid.addChild(shine)
        if scaled { kid.setScale(characterScale) }
        return kid
    }

    /// Pulsing aura ring under a kid — green = friendly (high five),
    /// orange = hazard on the move (hall monitor). Reads intent at a glance.
    private func addAuraRing(to kid: SKNode, color: SKColor) {
        let ring = SKShapeNode(circleOfRadius: 13)
        ring.strokeColor = color
        ring.lineWidth = 1.5
        ring.fillColor = color.withAlphaComponent(0.10)
        ring.zPosition = -0.8
        ring.run(.repeatForever(.sequence([
            .group([.scale(to: 1.25, duration: 0.55),
                    .fadeAlpha(to: 0.30, duration: 0.55)]),
            .group([.scale(to: 1.0, duration: 0.55),
                    .fadeAlpha(to: 0.9, duration: 0.55)]),
        ])))
        kid.addChild(ring)
    }

    /// Billy stands center-lane at the far end, tapping his foot and
    /// checking over his shoulder — impatient, but not moving.
    private func buildBilly(in layer: SKNode) {
        let billy = makeTopKid(shirt: SKColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1),
                               hair: SKColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1))
        // Crossed-arms sway — reads as "waiting, not running."
        for side: CGFloat in [-1, 1] {
            let fist = SKSpriteNode(color: SKColor(red: 0.94, green: 0.78, blue: 0.60, alpha: 1),
                                    size: CGSize(width: 4, height: 4))
            fist.position = CGPoint(x: side * 5, y: 2)
            fist.run(.repeatForever(.sequence([
                .rotate(toAngle: side * 0.2, duration: 0.5),
                .rotate(toAngle: -side * 0.2, duration: 0.5),
            ])))
            billy.addChild(fist)
        }
        // Backwards red cap — Billy is the one kid you have to spot at range.
        let capBack = SKShapeNode(circleOfRadius: 3.6)
        capBack.fillColor = SKColor(red: 0.80, green: 0.16, blue: 0.12, alpha: 1)
        capBack.strokeColor = SKColor(red: 0.45, green: 0.08, blue: 0.06, alpha: 1)
        capBack.lineWidth = 1
        capBack.position = CGPoint(x: 0, y: 1.2)
        capBack.zPosition = 3
        billy.addChild(capBack)
        let brim = SKSpriteNode(color: SKColor(red: 0.60, green: 0.12, blue: 0.09, alpha: 1),
                                size: CGSize(width: 5, height: 3))
        brim.position = CGPoint(x: 0, y: -3.5)
        brim.zPosition = 3
        billy.addChild(brim)
        billy.setScale(characterScale * 1.15)   // a head taller than the other kids
        billy.position = CGPoint(x: laneCenterX(1), y: billyDist)
        billy.zPosition = 26
        billy.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 0.35),
            .moveBy(x: 0, y: -3, duration: 0.35),
        ])), withKey: "idleBounce")
        layer.addChild(billy)
        billyNode = billy
    }

    // MARK: - Jack (screen-anchored, like the bike-race player)

    private func buildJack() {
        let jack = SKNode()
        jack.zPosition = 30

        // Ground shadow under the whole rig — same read as every other kid.
        let drop = SKShapeNode(ellipseOf: CGSize(width: 32, height: 22))
        drop.fillColor = SKColor(white: 0, alpha: 0.30)
        drop.strokeColor = .clear
        drop.position = CGPoint(x: 2, y: -3)
        drop.zPosition = -1
        jack.addChild(drop)

        // Rolling mop bucket from above: gray pail ring, water inside.
        let bucket = SKNode()
        let pail = SKShapeNode(circleOfRadius: 12)
        pail.fillColor = SKColor(red: 0.78, green: 0.70, blue: 0.22, alpha: 1)
        pail.strokeColor = SKColor(red: 0.45, green: 0.40, blue: 0.12, alpha: 1)
        pail.lineWidth = 2
        bucket.addChild(pail)
        let water = SKShapeNode(circleOfRadius: 8)
        water.fillColor = SKColor(red: 0.40, green: 0.62, blue: 0.85, alpha: 0.9)
        water.strokeColor = .clear
        water.zPosition = 1
        bucket.addChild(water)
        // Caster wheels poking out — sell the "rolling" read + spin target.
        for a in stride(from: CGFloat(0), to: .pi * 2, by: .pi / 2) {
            let wheel = SKSpriteNode(color: SKColor(white: 0.2, alpha: 1),
                                     size: CGSize(width: 4, height: 4))
            wheel.position = CGPoint(x: cos(a) * 13, y: sin(a) * 13)
            bucket.addChild(wheel)
        }
        jack.addChild(bucket)
        bucketNode = bucket

        // Jack riding on top (shoulders + head), red shirt. Unscaled here —
        // the whole rig (bucket + body + mop) is scaled together below so
        // nothing gets doubled twice.
        let body = makeTopKid(shirt: SKColor(red: 0.80, green: 0.24, blue: 0.16, alpha: 1),
                              hair: SKColor(red: 0.42, green: 0.28, blue: 0.12, alpha: 1),
                              scaled: false, shadow: false)   // bucket is his ground contact
        body.zPosition = 2
        jack.addChild(body)

        // Mop — pivots at Jack's hands, sweeps like a gondolier's oar.
        let mop = SKSpriteNode(color: SKColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1),
                               size: CGSize(width: 3, height: 30))
        mop.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        mop.position = CGPoint(x: 9, y: 2)
        mop.zRotation = 0.6   // trailing behind-right (pole points down at rotation 0)
        let mopHead = SKSpriteNode(color: SKColor(white: 0.85, alpha: 1),
                                   size: CGSize(width: 8, height: 6))
        mopHead.position = CGPoint(x: 0, y: -30)
        mop.addChild(mopHead)
        mop.zPosition = 3
        jack.addChild(mop)
        mopNode = mop

        jack.position = CGPoint(x: jackX, y: jackScreenY)
        jack.setScale(characterScale)
        addChild(jack)
        jackNode = jack
    }

    // MARK: - HUD

    private func setupUI() {
        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat = 48
        let totalTopH = topH + topInset
        let topBarY = H / 2 - totalTopH / 2

        let topBar = SKSpriteNode(color: Parchment.paper,
                                  size: CGSize(width: W, height: totalTopH))
        topBar.position = CGPoint(x: 0, y: topBarY)
        topBar.zPosition = 500
        addChild(topBar)

        let topBorder = SKSpriteNode(color: Parchment.edge,
                                     size: CGSize(width: W, height: 3))
        topBorder.position = CGPoint(x: 0, y: H / 2 - topInset - topH + 1)
        topBorder.zPosition = 501
        addChild(topBorder)

        let contentY = H / 2 - topInset - topH / 2

        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size = CGSize(width: 22, height: 22)
        pauseBtn.position = CGPoint(x: -W / 2 + 22, y: contentY)
        pauseBtn.zPosition = 502
        pauseBtn.name = "pauseBtn"
        addChild(pauseBtn)

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -W / 2 + 52, y: contentY)
        help.zPosition = 502
        addChild(help)

        // Zone B — hearts row, centered.
        let heartSpacing: CGFloat = 20
        let maxHearts = HeartsManager.shared.maxHearts
        let startX = -(CGFloat(maxHearts - 1) * heartSpacing) / 2
        heartSprites.removeAll()
        for i in 0..<maxHearts {
            let h = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            h.text = "♥"
            h.fontSize = 18
            h.fontColor = Parchment.heartRed
            h.horizontalAlignmentMode = .center
            h.verticalAlignmentMode = .center
            h.position = CGPoint(x: startX + CGFloat(i) * heartSpacing, y: contentY - 1)
            h.zPosition = 502
            addChild(h)
            heartSprites.append(h)
        }
        refreshHearts()

        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size = CGSize(width: 22, height: 22)
        closeBtn.position = CGPoint(x: W / 2 - 22, y: contentY)
        closeBtn.zPosition = 502
        closeBtn.name = "closeButton"
        addChild(closeBtn)

        // Timer — right-aligned against the close button.
        let timer = SKLabelNode(fontNamed: "PressStart2P-Regular")
        timer.fontSize = 9
        timer.fontColor = Parchment.timerBlue
        timer.horizontalAlignmentMode = .right
        timer.verticalAlignmentMode = .center
        timer.position = CGPoint(x: W / 2 - 50, y: contentY)
        timer.zPosition = 502
        addChild(timer)
        timeLabel = timer

        buildProgressTracker(below: H / 2 - topInset - topH)
        buildMistOverlay()
    }

    /// Side-view strip under the ribbon: a mini hallway profile with tiny
    /// side-on Jack (in his bucket) and Billy sprites racing left→right
    /// toward the doors, so the gap is readable at a glance.
    private func buildProgressTracker(below ribbonBottomY: CGFloat) {
        let trackH: CGFloat = 26
        trackWidth = W - 64
        let container = SKNode()
        container.position = CGPoint(x: 0, y: ribbonBottomY - trackH / 2 - 8)
        container.zPosition = 505
        addChild(container)

        let bg = SKShapeNode(rect: CGRect(x: -trackWidth / 2 - 6, y: -trackH / 2,
                                          width: trackWidth + 12, height: trackH),
                             cornerRadius: 6)
        bg.fillColor = SKColor(white: 0, alpha: 0.50)
        bg.strokeColor = Parchment.edge.withAlphaComponent(0.5)
        bg.lineWidth = 1
        container.addChild(bg)

        // Floor line the minis run along.
        let floorLine = SKSpriteNode(color: SKColor(white: 0.8, alpha: 0.5),
                                     size: CGSize(width: trackWidth + 4, height: 1))
        floorLine.position = CGPoint(x: 0, y: -7)
        container.addChild(floorLine)

        // Far doors at the right end.
        let door = SKSpriteNode(color: SKColor(red: 0.55, green: 0.35, blue: 0.18, alpha: 1),
                                size: CGSize(width: 6, height: 14))
        door.position = CGPoint(x: trackWidth / 2 + 2, y: 0)
        container.addChild(door)

        // Mini side-view Jack: bucket + head.
        let jackMini = SKNode()
        let pail = SKSpriteNode(color: SKColor(red: 0.78, green: 0.70, blue: 0.22, alpha: 1),
                                size: CGSize(width: 7, height: 5))
        pail.position = CGPoint(x: 0, y: -4)
        jackMini.addChild(pail)
        let jBody = SKSpriteNode(color: SKColor(red: 0.80, green: 0.24, blue: 0.16, alpha: 1),
                                 size: CGSize(width: 4, height: 6))
        jBody.position = CGPoint(x: 0, y: 1)
        jackMini.addChild(jBody)
        let jHead = SKSpriteNode(color: SKColor(red: 0.94, green: 0.78, blue: 0.60, alpha: 1),
                                 size: CGSize(width: 4, height: 4))
        jHead.position = CGPoint(x: 0, y: 6)
        jackMini.addChild(jHead)
        container.addChild(jackMini)
        trackJack = jackMini

        // Mini side-view Billy: dark runner with a leg scissor.
        let billyMini = SKNode()
        let bBody = SKSpriteNode(color: SKColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1),
                                 size: CGSize(width: 4, height: 7))
        bBody.position = CGPoint(x: 0, y: 0)
        billyMini.addChild(bBody)
        let bHead = SKSpriteNode(color: SKColor(red: 0.94, green: 0.78, blue: 0.60, alpha: 1),
                                 size: CGSize(width: 4, height: 4))
        bHead.position = CGPoint(x: 0, y: 6)
        billyMini.addChild(bHead)
        let leg = SKSpriteNode(color: SKColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1),
                               size: CGSize(width: 2, height: 4))
        leg.position = CGPoint(x: 1, y: -5)
        leg.run(.repeatForever(.sequence([
            .moveTo(x: -2, duration: 0.12),
            .moveTo(x: 2, duration: 0.12),
        ])))
        billyMini.addChild(leg)
        container.addChild(billyMini)
        trackBilly = billyMini

        updateProgressTracker()
    }

    private func updateProgressTracker() {
        func trackX(_ dist: CGFloat) -> CGFloat {
            -trackWidth / 2 + min(1, max(0, dist / hallLength)) * trackWidth
        }
        trackJack?.position.x = trackX(jackDist)
        trackBilly?.position.x = trackX(billyDist)
    }

    /// Full-screen mist — hidden until a spray-bottle kid gets you.
    private func buildMistOverlay() {
        let mist = SKSpriteNode(color: SKColor(red: 0.75, green: 0.88, blue: 0.95, alpha: 0.55),
                                size: CGSize(width: W, height: H))
        mist.zPosition = 510
        mist.alpha = 0
        addChild(mist)
        mistOverlay = mist
    }

    private func addCrtOverlay() {
        let w = W, h = H
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
                  body: "BILLY SOCKED YOU AND RAN — NOW HE'S WAITING BY THE DOORS. ONE FOOT IN THE MOP BUCKET, ROW DOWN THE HALL AND REACH HIM!"),
            .hint(at: CGPoint(x: jackX, y: jackScreenY),
                  title: "TAP TO STROKE",
                  body: "TAP TO SWEEP THE MOP AND SURGE FORWARD. TAP AGAIN TO KEEP YOUR SPEED UP!"),
            .card(title: "SWIPE TO STEER",
                  body: "SWIPE LEFT OR RIGHT TO CHANGE LANES. DODGE KIDS, SIGNS, SWINGING DOORS, HALL MONITORS — AND BILLY'S BINDER!"),
            .card(title: "READ THE FLOOR",
                  body: "NEVER STROKE ON WAXED FLOOR — GLIDE OVER IT. A STROKE LANDING IN A PUDDLE IS A SUPER STROKE. HIGH-FIVE THE FRIENDLY KIDS FOR A BOOST!"),
            .card(title: "BEAT THE CLOCK",
                  body: "YOU HAVE 60 SECONDS! EVERY CRASH COSTS A HEART — RUN OUT OF EITHER AND BILLY LEAVES WITHOUT YOU."),
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
                lbl.fontSize = min(48, self.W / 7)
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

    /// One tap = one plant-and-sweep of the mop. Fixed impulse; no charge,
    /// no timing window. A stroke landing in a puddle is a bonus; a stroke
    /// landing on waxed floor is a penalty.
    private func stroke() {
        guard phase == .racing else { return }

        if let i = obstacles.firstIndex(where: {
            $0.kind == .wax && !$0.triggered &&
            (($0.dist)...($0.dist + $0.length)).contains(jackDist)
        }) {
            obstacles[i].triggered = true
            jackSpeed *= 0.60
            showToast("WAXED FLOOR — GLIDE!", color: SKColor(red: 0.95, green: 0.85, blue: 0.40, alpha: 1))
            HapticsManager.shared.warningFeedback()
            jackCrashWobble()
            loseHeart()
            settleMop()
            return
        }

        var impulse = strokeImpulse
        let inPuddle = obstacles.contains {
            $0.kind == .puddle && (($0.dist)...($0.dist + $0.length)).contains(jackDist)
        }
        if inPuddle {
            impulse *= 1.6
            showToast("SUPER STROKE!", color: SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1))
        }

        jackSpeed = min(maxSpeed, jackSpeed + impulse)
        HapticsManager.shared.lightImpact()
        splash(at: CGPoint(x: jackX + 24, y: jackScreenY - 20))

        // Mop plants forward, sweeps down past the bucket, settles trailing.
        mopNode?.removeAllActions()
        mopNode?.run(.sequence([
            .rotate(toAngle: 2.6, duration: 0.10, shortestUnitArc: true),
            .rotate(toAngle: 0.9, duration: 0.12, shortestUnitArc: true),
            .rotate(toAngle: 0.6, duration: 0.4, shortestUnitArc: true),
        ]))
    }

    private func settleMop() {
        mopNode?.removeAllActions()
        mopNode?.run(.rotate(toAngle: 0.6, duration: 0.25, shortestUnitArc: true))
    }

    // MARK: - Hearts

    /// Every crash costs one universal heart. Hitting zero ends the chase
    /// immediately, regardless of the clock.
    private func loseHeart() {
        guard phase == .racing else { return }
        HeartsManager.shared.lose()
        refreshHearts()
        if HeartsManager.shared.currentHearts <= 0 {
            phase = .done
            loseReason = .heartsGone
            run(.wait(forDuration: 0.3)) { [weak self] in
                self?.triggerGameOver(playerWon: false)
            }
        }
    }

    private func refreshHearts() {
        let current = HeartsManager.shared.currentHearts
        for (i, h) in heartSprites.enumerated() {
            let filled = i < current
            h.text = filled ? "♥" : "♡"
            h.fontColor = filled ? Parchment.heartRed : Parchment.disInk
        }
    }

    // MARK: - Steering

    private func steer(_ direction: Int) {
        guard phase == .racing else { return }
        let newLane = max(0, min(2, targetLane + direction))
        guard newLane != targetLane else { return }
        targetLane = newLane
        touchDidSteer = true
        HapticsManager.shared.lightImpact()
    }

    private var jackLane: Int {
        var best = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for i in 0...2 {
            let d = abs(laneCenterX(i) - jackX)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    // MARK: - FX

    private func splash(at screenPos: CGPoint) {
        for _ in 0..<4 {
            let fleck = SKSpriteNode(color: SKColor(white: 0.95, alpha: 0.8),
                                     size: CGSize(width: 3, height: 3))
            fleck.position = screenPos
            fleck.zPosition = 32
            addChild(fleck)
            fleck.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -8...8),
                            y: CGFloat.random(in: -16...(-4)), duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    /// Thin white streak flying down-screen — high-speed game feel.
    private func spawnSpeedStreak() {
        let streak = SKSpriteNode(color: SKColor(white: 1.0, alpha: 0.35),
                                  size: CGSize(width: 2, height: CGFloat.random(in: 18...30)))
        streak.position = CGPoint(x: CGFloat.random(in: -W * 0.46...W * 0.46),
                                  y: CGFloat.random(in: 0...H * 0.42))
        streak.zPosition = 40
        addChild(streak)
        streak.run(.sequence([
            .group([.moveBy(x: 0, y: -H * 0.5, duration: 0.3), .fadeOut(withDuration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    private func jackCrashWobble() {
        guard let jack = jackNode else { return }
        jack.removeAction(forKey: "wobble")
        jack.run(.sequence([
            .rotate(toAngle: 0.35, duration: 0.07),
            .rotate(toAngle: -0.30, duration: 0.10),
            .rotate(toAngle: 0.15, duration: 0.08),
            .rotate(toAngle: 0, duration: 0.10),
        ]), withKey: "wobble")
    }

    private func showToast(_ text: String, color: SKColor) {
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text = text
        lbl.fontSize = min(11, W / 26)
        lbl.fontColor = color
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: 0, y: H * 0.10)
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

    private func flashWhite(alpha: CGFloat, fade: TimeInterval) {
        let flash = SKSpriteNode(color: .white, size: CGSize(width: W, height: H))
        flash.alpha = alpha
        flash.zPosition = 890
        addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: fade), .removeFromParent()]))
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
            updateRacing(fdt)
        case .finale:
            updateFinale(fdt)
        case .done:
            break
        }
    }

    private func updateRacing(_ fdt: CGFloat) {
        // — Jack: glide friction —
        jackSpeed *= exp(-frictionK * fdt)
        jackDist += jackSpeed * fdt

        // — Lateral ease toward the target lane + lean —
        let targetX = laneCenterX(targetLane)
        let dx = targetX - jackX
        jackX += dx * min(1, 10 * fdt)
        jackNode?.zRotation = -dx * 0.004
        // Bucket casters spin with speed.
        bucketNode?.zRotation -= fdt * jackSpeed * 0.02

        // High-speed streaks — pure eye candy above a speed threshold.
        if jackSpeed > fastThreshold {
            streakAccum += fdt
            if streakAccum > 0.06 { streakAccum = 0; spawnSpeedStreak() }
        } else {
            streakAccum = 0
        }

        updateObstacles()
        updateSwingDoors()
        updateHallMonitors()
        updateProjectiles(fdt)
        updateBillyTaunt()
        scrollFloor(by: jackSpeed * fdt)
        layoutWorld()

        // — Timer + tracker —
        let remaining = max(0, raceTimeLimit - raceClock)
        let remainingSecs = Int(ceil(remaining))
        timeLabel?.text = String(format: "%d:%02d", remainingSecs / 60, remainingSecs % 60)
        timeLabel?.fontColor = remaining <= 5
            ? SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
            : Parchment.timerBlue
        updateProgressTracker()

        // — Win / lose checks — reaching the end of the hall triggers the
        // crash; running out of time before that means Billy leaves without
        // you. Hearts hitting zero (loseHeart()) ends things immediately,
        // independent of this check.
        if jackDist >= finaleZoneStart {
            startFinale()
        } else if raceClock >= raceTimeLimit {
            billyLeaves()
        }
    }

    /// Time's up — Billy shrugs and bolts through the doors without Jack.
    private func billyLeaves() {
        guard phase == .racing else { return }
        phase = .done
        loseReason = .timeOut
        showToast("TIME'S UP!", color: SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
        billyNode?.removeAction(forKey: "idleBounce")
        billyNode?.run(.sequence([
            .rotate(toAngle: 0.3, duration: 0.1),
            .rotate(toAngle: -0.2, duration: 0.1),
            .rotate(toAngle: 0, duration: 0.08),
            .group([
                .moveBy(x: 0, y: W * 2.0, duration: 0.8),
                .fadeOut(withDuration: 0.8),
            ]),
        ]))
        run(.wait(forDuration: 1.1)) { [weak self] in
            self?.triggerGameOver(playerWon: false)
        }
    }

    private func updateObstacles() {
        let lane = jackLane
        for i in obstacles.indices {
            guard !obstacles[i].triggered else { continue }
            let ob = obstacles[i]
            switch ob.kind {
            case .kid, .sign, .limbo:
                if abs(ob.dist - jackDist) < 24, ob.lanes.contains(lane) {
                    obstacles[i].triggered = true
                    crashInto(ob)
                }
            case .wax:
                break   // handled in stroke()
            case .spray:
                if jackDist > ob.dist - W * 0.3 {
                    obstacles[i].triggered = true
                    mistOverlay?.run(.sequence([
                        .fadeAlpha(to: 0.92, duration: 0.2),
                        .wait(forDuration: 2.0),
                        .fadeOut(withDuration: 0.5),
                    ]))
                    showToast("SPRAYED!", color: SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1))
                }
            case .highFive:
                if abs(ob.dist - jackDist) < 26, ob.lanes.contains(lane) {
                    obstacles[i].triggered = true
                    jackSpeed = min(maxSpeed, jackSpeed + W * 0.30)
                    showToast("HIGH FIVE!", color: SKColor(red: 0.30, green: 0.90, blue: 0.60, alpha: 1))
                    HapticsManager.shared.successFeedback()
                    // Slap star at the kid's hand.
                    let star = SKLabelNode(fontNamed: "PressStart2P-Regular")
                    star.text = "✦"
                    star.fontSize = 10
                    star.fontColor = SKColor(red: 0.98, green: 0.85, blue: 0.30, alpha: 1)
                    star.position = CGPoint(x: ob.node.position.x + (ob.lanes.contains(0) ? 14 : -14),
                                            y: ob.dist)
                    star.zPosition = 40
                    scrollLayer.addChild(star)
                    star.run(.sequence([
                        .group([.scale(to: 1.8, duration: 0.3), .fadeOut(withDuration: 0.3)]),
                        .removeFromParent(),
                    ]))
                }
            case .puddle:
                break   // handled in stroke()
            }
        }
    }

    /// Doors swing on a sine cycle driven off raceClock (pause-safe).
    private func updateSwingDoors() {
        let lane = jackLane
        for i in swingDoors.indices {
            let door = swingDoors[i]
            let openness = (sin(CGFloat(raceClock) * door.speed + door.phase) + 1) / 2
            let dir: CGFloat = door.lane == 0 ? -1 : 1
            door.panel.zRotation = dir * openness * (.pi / 2)
            if !door.hit, openness > 0.6, lane == door.lane,
               abs(door.dist - jackDist) < 26 {
                swingDoors[i].hit = true
                jackSpeed *= 0.45
                showToast("SLAMMED BY A DOOR!", color: SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
                HapticsManager.shared.errorFeedback()
                run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                jackCrashWobble()
                loseHeart()
            }
        }
    }

    /// Hall monitors pace the full width of the hall.
    private func updateHallMonitors() {
        for i in hallMonitors.indices {
            let m = hallMonitors[i]
            let x = sin(CGFloat(raceClock) * m.speed + m.phase) * (hallWidth / 2 - 16)
            m.node.position.x = x
            if !m.hit, abs(m.dist - jackDist) < 24, abs(x - jackX) < 26 {
                hallMonitors[i].hit = true
                jackSpeed *= 0.40
                showToast("\"NO ROLLING IN THE HALL!\"", color: SKColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1))
                HapticsManager.shared.errorFeedback()
                run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                jackCrashWobble()
                loseHeart()
                m.node.run(.sequence([
                    .rotate(toAngle: 0.4, duration: 0.1),
                    .rotate(toAngle: 0, duration: 0.2),
                ]))
            }
        }
    }

    /// Billy's binder flies back down the hall toward Jack.
    private func updateProjectiles(_ fdt: CGFloat) {
        for i in projectiles.indices {
            guard projectiles[i].active else { continue }
            projectiles[i].dist -= W * 0.85 * fdt
            projectiles[i].node.position.y = projectiles[i].dist
            if abs(projectiles[i].dist - jackDist) < 20, jackLane == projectiles[i].lane {
                projectiles[i].active = false
                jackSpeed *= 0.45
                showToast("BEANED BY BILLY!", color: SKColor(red: 0.95, green: 0.35, blue: 0.25, alpha: 1))
                HapticsManager.shared.errorFeedback()
                run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                jackCrashWobble()
                loseHeart()
                projectiles[i].node.run(.sequence([
                    .group([.scale(to: 1.6, duration: 0.2), .fadeOut(withDuration: 0.2)]),
                    .removeFromParent(),
                ]))
            } else if projectiles[i].dist < jackDist - H {
                projectiles[i].active = false
                projectiles[i].node.removeFromParent()
            }
        }
        projectiles.removeAll { !$0.active }
    }

    private func billyThrowsBinder() {
        let lane = jackLane
        let spawnDist = min(billyDist, jackDist + H * 0.85)
        let binder = SKSpriteNode(color: SKColor(red: 0.80, green: 0.20, blue: 0.20, alpha: 1),
                                  size: CGSize(width: 12, height: 9))
        let spine = SKSpriteNode(color: SKColor(white: 0.95, alpha: 1),
                                 size: CGSize(width: 2, height: 9))
        spine.position = CGPoint(x: -5, y: 0)
        binder.addChild(spine)
        binder.position = CGPoint(x: laneCenterX(lane), y: spawnDist)
        binder.zPosition = 28
        binder.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.4)))
        scrollLayer.addChild(binder)
        projectiles.append(BillyProjectile(dist: spawnDist, lane: lane, node: binder))
    }

    private func crashInto(_ ob: Obstacle) {
        switch ob.kind {
        case .kid:
            jackSpeed *= 0.35
            showToast("OOF! A KID!", color: SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
            shoveKid(ob.node)
        case .sign:
            jackSpeed *= 0.50
            showToast("WET FLOOR SIGN!", color: SKColor(red: 0.95, green: 0.60, blue: 0.30, alpha: 1))
            ob.node.run(.sequence([
                .group([
                    .rotate(byAngle: .pi * 2, duration: 0.4),
                    .moveBy(x: CGFloat.random(in: -30...30), y: 40, duration: 0.4),
                ]),
                .fadeOut(withDuration: 0.2),
            ]))
        case .limbo:
            jackSpeed *= 0.45
            showToast("CLIPPED THE LIMBO MOP!", color: SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1))
            ob.node.run(.sequence([
                .rotate(toAngle: 0.12, duration: 0.1),
                .rotate(toAngle: 0, duration: 0.2),
            ]))
        default:
            return
        }
        HapticsManager.shared.errorFeedback()
        run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        jackCrashWobble()
        loseHeart()
    }

    private func shoveKid(_ node: SKNode) {
        let side: CGFloat = node.position.x >= 0 ? 1 : -1
        node.run(.sequence([
            .group([
                .rotate(byAngle: .pi * 3, duration: 0.5),
                .moveBy(x: side * (hallWidth / 2 - abs(node.position.x) + 14),
                        y: CGFloat.random(in: 10...30), duration: 0.5),
            ]),
            .rotate(toAngle: 1.4, duration: 0.1),   // ends up flat against the lockers
        ]))
    }

    /// Billy doesn't move during the chase — he's already waiting at the
    /// end. The only thing he does is heckle: once Jack is close enough, he
    /// periodically hurls his binder back down Jack's current lane.
    private func updateBillyTaunt() {
        if raceClock >= nextBillyThrow, billyDist - jackDist < H * 1.6 {
            nextBillyThrow = raceClock + TimeInterval.random(in: 3.0...5.5)
            billyThrowsBinder()
        }
    }

    /// Positions the world layer so world-Y == hall distance maps onto the screen.
    /// Billy's world-Y is only touched during the finale (when he's actually
    /// fleeing) — while racing he's stationary and free to run his own idle
    /// bounce without fighting a per-frame position reset.
    private func layoutWorld() {
        scrollLayer.position.y = jackScreenY - jackDist
        jackNode?.position = CGPoint(x: jackX, y: jackScreenY)
    }

    // MARK: - Finale (scripted cinematic spin-out into Becky)

    private func startFinale() {
        guard phase == .racing else { return }
        phase = .finale
        finaleTimeScale = 1
        settleMop()
        billyNode?.removeAction(forKey: "idleBounce")

        // Big centered "GOTCHA—" beat, not a mere toast.
        let gotcha = SKLabelNode(fontNamed: "PressStart2P-Regular")
        gotcha.text = "GOTCHA—"
        gotcha.fontSize = min(26, W / 10)
        gotcha.fontColor = SKColor(red: 0.30, green: 0.90, blue: 0.40, alpha: 1)
        gotcha.horizontalAlignmentMode = .center
        gotcha.verticalAlignmentMode = .center
        gotcha.zPosition = 900
        gotcha.setScale(0.3)
        addChild(gotcha)
        gotcha.run(.sequence([
            .scale(to: 1.0, duration: 0.12),
            .wait(forDuration: 0.6),
            .fadeOut(withDuration: 0.2),
            .removeFromParent(),
        ]))

        // Janitor water right under the lunge, and Becky just past it.
        finaleWaterDist = jackDist + W * 0.45
        beckyDist = jackDist + W * 1.05
        let water = SKShapeNode(ellipseOf: CGSize(width: hallWidth * 0.8, height: W * 0.4))
        water.fillColor = SKColor(red: 0.35, green: 0.60, blue: 0.90, alpha: 0.55)
        water.strokeColor = .clear
        water.position = CGPoint(x: 0, y: finaleWaterDist + W * 0.2)
        water.zPosition = 12
        scrollLayer.addChild(water)

        // Becky strolling in the middle lane, arms full of books.
        let becky = makeTopKid(shirt: SKColor(red: 0.85, green: 0.55, blue: 0.70, alpha: 1),
                               hair: SKColor(red: 0.72, green: 0.58, blue: 0.24, alpha: 1))
        // Pigtails — Becky reads as Becky, not another obstacle kid.
        for side: CGFloat in [-1, 1] {
            let tail = SKShapeNode(circleOfRadius: 2.2)
            tail.fillColor = SKColor(red: 0.72, green: 0.58, blue: 0.24, alpha: 1)
            tail.strokeColor = SKColor(red: 0.45, green: 0.34, blue: 0.12, alpha: 1)
            tail.lineWidth = 0.8
            tail.position = CGPoint(x: side * 5.5, y: 1.8)
            tail.zPosition = 2.2
            becky.addChild(tail)
        }
        let bookColors: [SKColor] = [
            SKColor(red: 0.75, green: 0.25, blue: 0.20, alpha: 1),
            SKColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1),
            SKColor(red: 0.30, green: 0.60, blue: 0.30, alpha: 1),
            SKColor(red: 0.70, green: 0.55, blue: 0.15, alpha: 1),
        ]
        for (i, col) in bookColors.enumerated() {
            let book = SKSpriteNode(color: col, size: CGSize(width: 9, height: 6))
            book.position = CGPoint(x: 0, y: -8 - CGFloat(i))
            book.zPosition = 3
            book.name = "beckyBook"
            becky.addChild(book)
        }
        becky.position = CGPoint(x: laneCenterX(1), y: beckyDist)
        becky.zPosition = 27
        becky.run(.repeatForever(.sequence([
            .rotate(toAngle: 0.06, duration: 0.3),
            .rotate(toAngle: -0.06, duration: 0.3),
        ])), withKey: "stroll")
        scrollLayer.addChild(becky)
        beckyNode = becky
    }

    private func updateFinale(_ fdt: CGFloat) {
        // Slow-mo eases back to full speed after the water hit.
        if finaleWaterHit && finaleTimeScale < 1 {
            finaleTimeScale = min(1, finaleTimeScale + fdt * 0.7)
        }
        let sdt = fdt * finaleTimeScale

        // Runaway slide — no friction, no control.
        jackDist += maxSpeed * 1.05 * sdt
        billyDist += billyFleeSpeed * sdt
        billyNode?.position.y = billyDist
        // Jack drifts toward the center lane, where Becky waits.
        let cx = laneCenterX(1)
        jackX += (cx - jackX) * min(1, 4 * sdt)
        // Billy peels off to the side lane, out of the blast radius.
        if let billy = billyNode {
            let bx = laneCenterX(0)
            billy.position.x += (bx - billy.position.x) * min(1, 5 * sdt)
        }

        if !finaleWaterHit, jackDist >= finaleWaterDist {
            finaleWaterHit = true
            finaleTimeScale = 0.40   // slow-mo through the spin-out
            flashWhite(alpha: 0.35, fade: 0.3)
            showToast("WHOA— THE WATER!", color: SKColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1))
            HapticsManager.shared.warningFeedback()
            // Bucket spins out; Jack fishtails.
            bucketNode?.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.25)))
            jackNode?.run(.repeatForever(.sequence([
                .rotate(toAngle: 0.35, duration: 0.12),
                .rotate(toAngle: -0.35, duration: 0.12),
            ])), withKey: "fishtail")
        }

        // Skid marks trail the spin-out.
        if finaleWaterHit {
            skidAccum += fdt
            if skidAccum > 0.05 {
                skidAccum = 0
                let skid = SKSpriteNode(color: SKColor(white: 0.15, alpha: 0.35),
                                        size: CGSize(width: 3, height: 14))
                skid.position = CGPoint(x: jackX + CGFloat.random(in: -16...16), y: jackDist - 16)
                skid.zPosition = 11
                skid.zRotation = CGFloat.random(in: -0.4...0.4)
                scrollLayer.addChild(skid)
                skid.run(.sequence([.wait(forDuration: 2.5), .fadeOut(withDuration: 1.0),
                                    .removeFromParent()]))
            }
        }

        // Becky sees it coming.
        if !beckyShrieked, jackDist > beckyDist - W * 0.5 {
            beckyShrieked = true
            let eek = SKLabelNode(fontNamed: "PressStart2P-Regular")
            eek.text = "EEEK!"
            eek.fontSize = 9
            eek.fontColor = SKColor(red: 0.95, green: 0.40, blue: 0.55, alpha: 1)
            eek.position = CGPoint(x: laneCenterX(1), y: beckyDist + 18)
            eek.zPosition = 40
            scrollLayer.addChild(eek)
            eek.run(.sequence([
                .group([.moveBy(x: 0, y: 8, duration: 0.5),
                        .sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.3)])]),
                .removeFromParent(),
            ]))
            beckyNode?.run(.sequence([
                // Becky's base scale is characterScale (2×), baked in by
                // makeTopKid — these absolute targets must scale with it.
                .scale(to: 1.15 * characterScale, duration: 0.08),
                .scale(to: characterScale, duration: 0.10),
            ]))
        }

        scrollFloor(by: maxSpeed * 1.05 * sdt)
        layoutWorld()
        updateProgressTracker()

        if !finaleImpacted, jackDist >= beckyDist - 20 {
            finaleImpacted = true
            crashIntoBecky()
        }
    }

    /// The pile-up: Jack spins out of the bucket, bowls Becky flat, and lands
    /// square on top of her. Books everywhere. The bucket ricochets off the
    /// lockers. Billy stops to laugh. A crowd gathers.
    private func crashIntoBecky() {
        phase = .done
        run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        HapticsManager.shared.heavyImpact()

        let beckyX = laneCenterX(1)
        guard let becky = beckyNode else { triggerGameOver(playerWon: true); return }
        becky.removeAction(forKey: "stroll")

        // Swap screen-anchored Jack for world-anchored crash actors.
        jackNode?.isHidden = true
        let crashOrigin = CGPoint(x: jackX, y: jackDist)

        // 1 — The bucket ejects: ricochets off the lockers with a clang,
        //     bounces back into the hall, and tips over. Geometry is
        //     doubled directly (not via .setScale) since the tip-over
        //     sequence below uses absolute scaleY targets.
        let bucket = SKShapeNode(circleOfRadius: 24)
        bucket.fillColor = SKColor(red: 0.78, green: 0.70, blue: 0.22, alpha: 1)
        bucket.strokeColor = SKColor(red: 0.45, green: 0.40, blue: 0.12, alpha: 1)
        bucket.lineWidth = 2
        bucket.position = crashOrigin
        bucket.zPosition = 29
        scrollLayer.addChild(bucket)
        let wallX = hallWidth / 2 - 12
        bucket.run(.sequence([
            .group([
                .moveTo(x: wallX, duration: 0.35),
                .moveBy(x: 0, y: W * 0.30, duration: 0.35),
                .rotate(byAngle: .pi * 4, duration: 0.35),
            ]),
            .run { [weak self] in
                guard let self else { return }
                self.run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                HapticsManager.shared.mediumImpact()
                // Clang sparks off the lockers.
                for _ in 0..<4 {
                    let spark = SKSpriteNode(color: SKColor(red: 0.98, green: 0.85, blue: 0.30, alpha: 1),
                                             size: CGSize(width: 3, height: 3))
                    spark.position = CGPoint(x: wallX + 8, y: bucket.position.y)
                    spark.zPosition = 40
                    self.scrollLayer.addChild(spark)
                    spark.run(.sequence([
                        .group([.moveBy(x: CGFloat.random(in: -18...(-4)),
                                        y: CGFloat.random(in: -12...12), duration: 0.3),
                                .fadeOut(withDuration: 0.3)]),
                        .removeFromParent(),
                    ]))
                }
            },
            .group([
                .moveTo(x: laneCenterX(2) - 8, duration: 0.45),
                .moveBy(x: 0, y: W * 0.22, duration: 0.45),
                .rotate(byAngle: .pi * 2.5, duration: 0.45),
            ]),
            .scaleY(to: 0.55, duration: 0.12),   // tips onto its side
            .scaleY(to: 0.68, duration: 0.08),
            .scaleY(to: 0.60, duration: 0.06),
        ]))
        // Water sloshes out in an expanding wave.
        for (i, r) in [22, 38, 54].enumerated() {
            let wave = SKShapeNode(ellipseOf: CGSize(width: CGFloat(r) * 2, height: CGFloat(r)))
            wave.fillColor = i == 0
                ? SKColor(red: 0.40, green: 0.62, blue: 0.85, alpha: 0.5)
                : .clear
            wave.strokeColor = SKColor(red: 0.45, green: 0.70, blue: 0.95, alpha: 0.6)
            wave.lineWidth = 2
            wave.position = CGPoint(x: beckyX, y: jackDist + W * 0.20)
            wave.zPosition = 12
            wave.setScale(0.1)
            scrollLayer.addChild(wave)
            wave.run(.sequence([
                .wait(forDuration: Double(i) * 0.12),
                .group([.scale(to: 1.0, duration: 0.6),
                        i == 0 ? .fadeAlpha(to: 0.35, duration: 0.6) : .fadeOut(withDuration: 0.7)]),
            ]))
        }

        // 2 — The mop cartwheels off to the side and clatters flat.
        let mop = SKSpriteNode(color: SKColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1),
                               size: CGSize(width: 6, height: 60))
        mop.position = crashOrigin
        mop.zPosition = 31
        scrollLayer.addChild(mop)
        mop.run(.group([
            .moveBy(x: -laneW, y: W * 0.2, duration: 0.5),
            .rotate(byAngle: .pi * 3.5, duration: 0.5),
        ]))

        // 3 — Jack launches: up and over with a growing shadow, spinning,
        //     straight into Becky.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 40, height: 20))
        shadow.fillColor = SKColor(white: 0, alpha: 0.30)
        shadow.strokeColor = .clear
        shadow.position = crashOrigin
        shadow.zPosition = 13
        scrollLayer.addChild(shadow)
        shadow.run(.sequence([
            .move(to: CGPoint(x: beckyX, y: beckyDist - 4), duration: 0.45),
            .fadeOut(withDuration: 0.15),
            .removeFromParent(),
        ]))

        let flyingJack = makeTopKid(shirt: SKColor(red: 0.80, green: 0.24, blue: 0.16, alpha: 1),
                                    hair: SKColor(red: 0.42, green: 0.28, blue: 0.12, alpha: 1),
                                    shadow: false)   // the launch shadow above is his shadow
        flyingJack.position = crashOrigin
        flyingJack.zPosition = 34
        scrollLayer.addChild(flyingJack)
        flyingJack.run(.sequence([
            .group([
                .move(to: CGPoint(x: beckyX, y: beckyDist - 4), duration: 0.45),
                .rotate(byAngle: .pi * 5, duration: 0.45),
                .sequence([.scale(to: 1.6 * characterScale, duration: 0.22),
                           .scale(to: characterScale, duration: 0.23)]),
            ]),
            .run { [weak self] in self?.impactMoment(jack: flyingJack, becky: becky, beckyX: beckyX) },
        ]))
    }

    private func impactMoment(jack: SKNode, becky: SKNode, beckyX: CGFloat) {
        HapticsManager.shared.heavyImpact()
        run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        flashWhite(alpha: 0.75, fade: 0.35)

        // Shockwave ring + dust cloud at the impact point.
        let ring = SKShapeNode(circleOfRadius: 14)
        ring.strokeColor = SKColor(white: 1.0, alpha: 0.9)
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.position = CGPoint(x: beckyX, y: beckyDist)
        ring.zPosition = 42
        scrollLayer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 4.5, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent(),
        ]))
        for _ in 0..<6 {
            let dust = SKShapeNode(circleOfRadius: CGFloat.random(in: 5...9))
            dust.fillColor = SKColor(white: 0.75, alpha: 0.5)
            dust.strokeColor = .clear
            dust.position = CGPoint(x: beckyX + CGFloat.random(in: -10...10),
                                    y: beckyDist + CGFloat.random(in: -8...8))
            dust.zPosition = 33
            scrollLayer.addChild(dust)
            dust.run(.sequence([
                .group([
                    .scale(to: 2.2, duration: 0.6),
                    .moveBy(x: CGFloat.random(in: -20...20),
                            y: CGFloat.random(in: -10...20), duration: 0.6),
                    .fadeOut(withDuration: 0.6),
                ]),
                .removeFromParent(),
            ]))
        }

        // Becky goes down flat — knocked onto her back, sliding up the hall.
        becky.removeAllActions()
        becky.run(.sequence([
            .group([
                .rotate(toAngle: 1.55, duration: 0.18),
                .moveBy(x: 0, y: 16, duration: 0.18),
            ]),
            .sequence([.scale(to: 1.1 * characterScale, duration: 0.06),
                       .scale(to: characterScale, duration: 0.08)]),
        ]))

        // Books, papers, and pencils explode outward.
        for child in becky.children where child.name == "beckyBook" {
            let worldPos = becky.convert(child.position, to: scrollLayer)
            child.removeFromParent()
            child.position = worldPos
            child.zPosition = 36
            // Preserve the size it rendered at while parented to Becky's
            // (2×) scale — reparenting to scrollLayer drops that inherited
            // transform otherwise.
            child.setScale(characterScale)
            scrollLayer.addChild(child)
            child.run(.group([
                .moveBy(x: CGFloat.random(in: -60...60),
                        y: CGFloat.random(in: 10...65), duration: 0.55),
                .rotate(byAngle: CGFloat.random(in: -8...8), duration: 0.55),
            ]))
        }
        for _ in 0..<8 {
            let paper = SKSpriteNode(color: SKColor(white: 0.95, alpha: 1),
                                     size: CGSize(width: 7, height: 9))
            paper.position = CGPoint(x: beckyX, y: beckyDist + 6)
            paper.zPosition = 36
            scrollLayer.addChild(paper)
            paper.run(.group([
                .moveBy(x: CGFloat.random(in: -70...70),
                        y: CGFloat.random(in: -15...70), duration: 0.9),
                .rotate(byAngle: CGFloat.random(in: -6...6), duration: 0.9),
                .sequence([
                    .scaleX(to: 0.3, duration: 0.22), .scaleX(to: 1.0, duration: 0.22),
                    .scaleX(to: 0.3, duration: 0.22), .scaleX(to: 1.0, duration: 0.24),
                ]),   // flutter
            ]))
        }
        for _ in 0..<3 {
            let pencil = SKSpriteNode(color: SKColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1),
                                      size: CGSize(width: 2, height: 11))
            pencil.position = CGPoint(x: beckyX, y: beckyDist + 4)
            pencil.zPosition = 36
            scrollLayer.addChild(pencil)
            pencil.run(.group([
                .moveBy(x: CGFloat.random(in: -50...50),
                        y: CGFloat.random(in: 0...50), duration: 0.6),
                .rotate(byAngle: CGFloat.random(in: -10...10), duration: 0.6),
            ]))
        }

        // Impact stars ring the pile-up.
        for _ in 0..<10 {
            let star = SKLabelNode(fontNamed: "PressStart2P-Regular")
            star.text = "✦"
            star.fontSize = 9
            star.fontColor = SKColor(red: 0.98, green: 0.85, blue: 0.30, alpha: 1)
            star.position = CGPoint(x: beckyX, y: beckyDist + 8)
            star.zPosition = 40
            scrollLayer.addChild(star)
            star.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -42...42),
                            y: CGFloat.random(in: -14...44), duration: 0.5),
                    .fadeOut(withDuration: 0.5),
                ]),
                .removeFromParent(),
            ]))
        }

        // Jack bounces once and settles right on top of her, dazed.
        jack.run(.sequence([
            .group([
                .move(to: CGPoint(x: beckyX + 2, y: beckyDist + 12), duration: 0.22),
                .rotate(toAngle: 1.2, duration: 0.22, shortestUnitArc: true),
            ]),
            .moveBy(x: 0, y: 5, duration: 0.10),
            .moveBy(x: 0, y: -5, duration: 0.10),
            .run { [weak self] in
                guard let self else { return }
                // Dizzy hearts float up — it IS Becky, after all.
                for i in 0..<3 {
                    let heart = SKLabelNode(fontNamed: "PressStart2P-Regular")
                    heart.text = "♥"
                    heart.fontSize = 8
                    heart.fontColor = SKColor(red: 0.90, green: 0.35, blue: 0.50, alpha: 1)
                    heart.position = CGPoint(x: beckyX + CGFloat(i * 10 - 10), y: beckyDist + 20)
                    heart.zPosition = 40
                    heart.alpha = 0
                    self.scrollLayer.addChild(heart)
                    heart.run(.sequence([
                        .wait(forDuration: 0.3 + Double(i) * 0.25),
                        .fadeIn(withDuration: 0.15),
                        .group([.moveBy(x: 0, y: 24, duration: 1.0), .fadeOut(withDuration: 1.0)]),
                        .removeFromParent(),
                    ]))
                }
            },
        ]))

        // Two-axis screen shake — much harder hit than the wall clang.
        let shake = SKAction.sequence([
            .moveBy(x: 7, y: -5, duration: 0.04), .moveBy(x: -13, y: 9, duration: 0.05),
            .moveBy(x: 10, y: -7, duration: 0.05), .moveBy(x: -7, y: 4, duration: 0.04),
            .moveBy(x: 3, y: -1, duration: 0.04),
        ])
        scrollLayer.run(shake)

        let crash = SKLabelNode(fontNamed: "PressStart2P-Regular")
        crash.text = "CRASH!"
        crash.fontSize = min(34, W / 7)
        crash.fontColor = SKColor(red: 0.95, green: 0.40, blue: 0.25, alpha: 1)
        crash.zPosition = 900
        crash.setScale(0.3)
        addChild(crash)
        crash.run(.sequence([
            .scale(to: 1.15, duration: 0.10),
            .scale(to: 1.0, duration: 0.08),
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))

        // Billy stops at a safe distance to point and laugh, then bolts.
        if let billy = billyNode {
            let haha = SKLabelNode(fontNamed: "PressStart2P-Regular")
            haha.text = "HA HA!"
            haha.fontSize = 8
            haha.fontColor = SKColor(red: 0.95, green: 0.45, blue: 0.30, alpha: 1)
            haha.position = CGPoint(x: 0, y: 16)
            haha.alpha = 0
            billy.addChild(haha)
            billy.run(.sequence([
                .wait(forDuration: 0.6),
                .run {
                    haha.run(.fadeIn(withDuration: 0.15))
                },
                // Mocking hop.
                .repeat(.sequence([
                    .moveBy(x: 0, y: 4, duration: 0.12),
                    .moveBy(x: 0, y: -4, duration: 0.12),
                ]), count: 3),
                .wait(forDuration: 0.4),
                .run { haha.run(.fadeOut(withDuration: 0.2)) },
                .group([.moveBy(x: 0, y: H * 0.6, duration: 0.8),
                        .fadeOut(withDuration: 0.8)]),
            ]))
        }

        // Onlooker kids waddle in from the walls to gawk.
        run(.wait(forDuration: 1.1)) { [weak self] in
            guard let self else { return }
            let spots: [(from: CGFloat, to: CGPoint)] = [
                (-1, CGPoint(x: beckyX - 34, y: beckyDist + 8)),
                (1,  CGPoint(x: beckyX + 34, y: beckyDist - 6)),
                (-1, CGPoint(x: beckyX - 26, y: beckyDist - 26)),
            ]
            let shirts: [SKColor] = [
                SKColor(red: 0.35, green: 0.45, blue: 0.75, alpha: 1),
                SKColor(red: 0.80, green: 0.60, blue: 0.20, alpha: 1),
                SKColor(red: 0.30, green: 0.60, blue: 0.40, alpha: 1),
            ]
            for (i, spot) in spots.enumerated() {
                let kid = self.makeTopKid(shirt: shirts[i],
                                          hair: SKColor(red: 0.20, green: 0.13, blue: 0.06, alpha: 1))
                kid.position = CGPoint(x: spot.from * (self.hallWidth / 2 + 10),
                                       y: spot.to.y + CGFloat.random(in: -8...8))
                kid.zPosition = 24
                self.scrollLayer.addChild(kid)
                kid.run(.sequence([
                    .wait(forDuration: Double(i) * 0.2),
                    .move(to: spot.to, duration: 0.6),
                    .repeatForever(.sequence([
                        .rotate(toAngle: 0.08, duration: 0.4),
                        .rotate(toAngle: -0.08, duration: 0.4),
                    ])),
                ]))
            }
            self.showToast("OOOOH!", color: SKColor(white: 0.9, alpha: 1))
        }

        // The sheepish outro beats.
        run(.wait(forDuration: 1.8)) { [weak self] in
            self?.showToast("...HI, BECKY.", color: SKColor(red: 0.90, green: 0.55, blue: 0.65, alpha: 1))
        }
        run(.wait(forDuration: 2.9)) { [weak self] in
            self?.showToast("\"GET OFF ME, JACK!!\"", color: SKColor(red: 0.95, green: 0.40, blue: 0.35, alpha: 1))
        }
        run(.wait(forDuration: 3.8)) { [weak self] in
            self?.showToast("\"JANITOR TO THE MAIN HALL.\"", color: SKColor(white: 0.7, alpha: 1))
        }
        run(.wait(forDuration: 4.7)) { [weak self] in
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

        strokeTouch = touch
        swipeRefX = loc.x
        touchDidSteer = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = strokeTouch, touches.contains(touch) else { return }
        guard phase == .racing, !isGameOver, !isPausedGame, !confirmingQuit else { return }
        let x = touch.location(in: self).x
        let dx = x - swipeRefX
        if abs(dx) >= swipeThreshold {
            steer(dx > 0 ? 1 : -1)
            swipeRefX = x   // allows chained swipes within one touch
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let end = touch.location(in: self)

        if let st = strokeTouch, touches.contains(st) { strokeTouch = nil }

        if isGameOver || isPausedGame || confirmingQuit {
            handleButtonTap(at: end)
            return
        }
        if touchDidSteer {
            settleMop()
        } else {
            stroke()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        strokeTouch = nil
        settleMop()
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

        let title: String
        let subtitle: String
        let detail: String?
        let hint: (String, SKColor)?
        if playerWon {
            title = "MADE IT... TOO FAST"
            subtitle = "RIGHT INTO BECKY"
            detail = nil
            hint = nil
        } else if loseReason == .heartsGone {
            title = "TOO BANGED UP!"
            subtitle = "COULDN'T KEEP GOING"
            detail = "TOO MANY CRASHES COST YOU EVERY HEART"
            hint = ("SWIPE TO DODGE —\nEVERY CRASH COSTS A HEART",
                    SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1))
        } else {
            title = "TIME'S UP!"
            subtitle = "BILLY LEFT WITHOUT YOU"
            detail = "REACH HIM BEFORE THE CLOCK RUNS OUT"
            hint = ("TAP FASTER TO KEEP YOUR SPEED UP",
                    SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1))
        }

        let panel = GameResultModal.make(
            sceneSize: size,
            won: playerWon,
            title: title,
            subtitle: subtitle,
            detail: detail,
            hint: hint,
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

        // Replaying after a loss refills hearts (matches the universal
        // hearts convention used by every other heart-draining game).
        if !didWin { HeartsManager.shared.refill() }
        refreshHearts()

        // Tear down the whole world (fresh obstacle layout every run).
        scrollLayer?.removeFromParent()
        jackNode?.removeFromParent()
        beckyNode = nil
        billyNode = nil

        jackDist = 0
        billyDist = billyWaitDist
        jackSpeed = 0
        jackX = laneCenterX(1)
        targetLane = 1
        raceClock = 0
        strokeTouch = nil
        streakAccum = 0
        skidAccum = 0
        nextBillyThrow = 4.0
        finaleImpacted = false
        finaleWaterHit = false
        finaleTimeScale = 1
        beckyShrieked = false
        isGameOver = false
        didWin = false
        phase = .racing

        mistOverlay?.removeAllActions()
        mistOverlay?.alpha = 0

        buildWorld()
        buildJack()
        updateProgressTracker()
        startCountdown()
    }

    // MARK: - Pause

    private func pauseGame() {
        guard !isPausedGame, !isGameOver else { return }
        isPausedGame = true
        settleMop()
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
    }

    private func showPauseOverlay() {
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

        let panelW: CGFloat = min(W - 48, 260), panelH: CGFloat = 150
        let panel = SKNode(); panel.zPosition = 4500
        confirmPanel = panel; addChild(panel)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -H / 2,
                                           width: W, height: H))
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
