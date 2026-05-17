import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private let gameWorld = SKNode()
    private let cameraNode = SKCameraNode()
    private var player: PlayerNode!
    private var map: TMXMap?
    private var lastUpdateTime: TimeInterval = 0
    private var hasSetup = false  // prevents double-init when scene is re-presented after mini-game
    /// When set, the player spawns here instead of the map's Spawn layer (used by story mode).
    var storySpawnOverride: CGPoint?

    // Cornhole board interaction
    private var cornholeBoardPositions: [CGPoint] = []
    private var nearbyBoardPosition: CGPoint?
    private var interactPrompt: SKNode?

    // Baseball interaction
    private var baseballPositions: [CGPoint] = []
    private var nearbyBaseballPosition: CGPoint?

    // Tree interaction
    private var treePositions: [CGPoint] = []
    private var nearbyTreePosition: CGPoint?

    // Apple tree interaction (launches cornhole vs. Spirit)
    private var appleTreePositions: [CGPoint] = []
    private var nearbyAppleTreePosition: CGPoint?

    // Beehive interaction
    private var beehivePositions: [CGPoint] = []
    private var nearbyBeehivePosition: CGPoint?

    // Bridge stone interaction (opens beachball cornhole)
    private var bridgeStonePositions: [CGPoint] = []
    private var nearbyBridgeStonePosition: CGPoint?

    // Bridge wood interaction (opens piranha mini-game; unlocks walkable bridge)
    private var bridgeWoodPositions: [CGPoint] = []
    private var nearbyBridgeWoodPosition: CGPoint?
    private var bridgePhysicsNodes: [SKNode] = []
    private let bridgeUnlockedKey = "bridgeUnlocked_v1"

    // Chest interaction
    private var chestPositions: [CGPoint] = []
    private var nearbyChestPosition: CGPoint?
    private var openedChestKeys: Set<String> = []

    // Placed dog biscuits
    private struct PlacedBiscuit { let node: SKNode; var isClaimed: Bool }
    private var placedBiscuits: [PlacedBiscuit] = []

    // Beach ball pool interaction — matches tilesets whose name contains "pool"
    private var poolPositions: [CGPoint] = []
    private var nearbyPoolPosition: CGPoint?

    // Tutorial state
    private var hasShownDogTutorial = false

    // Enemy dogs
    private var dogs: [DogNode] = []
    private var dogSpawnTimer: TimeInterval = 0
    private var nextDogSpawnInterval: TimeInterval = 7.0
    private let maxDogs = 3

    private var isTransitioning = false
    private var menuButtonPosition: CGPoint = .zero
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var pauseBtnPosition: CGPoint = .zero
    /// Half the player sprite's size in world units. Used to clamp the player at world boundaries.
    private let playerHalfExtent: CGFloat = 24
    /// Magnification of the world. Larger = sprites/tiles appear bigger and
    /// each "screen" covers less of the map, so navigation has more squares.
    private let worldZoom: CGFloat = 2.0

    // Layout — square stage in the middle, HUD on top, controls on bottom.
    private let baseTopChromeHeight: CGFloat = 32
    /// Top safe area inset (e.g. notch / Dynamic Island), in scene units.
    private var topSafeAreaInset: CGFloat { view?.safeAreaInsets.top ?? 0 }
    /// Bottom safe area inset (home indicator).
    private var bottomSafeAreaInset: CGFloat { view?.safeAreaInsets.bottom ?? 0 }
    /// Top chrome covers the safe area + the visible HUD bar.
    private var topChromeHeight: CGFloat { baseTopChromeHeight + topSafeAreaInset }
    private var stageSize: CGFloat { size.width }
    private var bottomChromeHeight: CGFloat {
        max(120, size.height - topChromeHeight - stageSize)
    }
    /// Stage center on screen (scene units), relative to camera origin.
    private var stageCenterY: CGFloat { (bottomChromeHeight - topChromeHeight) / 2 }
    /// World-space size of one navigable square. Smaller than stageSize because
    /// the camera is zoomed in, so the same map yields more screens.
    private var stageWorldSize: CGFloat { stageSize / worldZoom }
    /// Stage-center Y offset converted to world units (camera is scaled).
    private var stageCenterYWorld: CGFloat { stageCenterY / worldZoom }

    // Chrome / HUD palette (Wood & Steel).
    private let woodColor = SKColor(red: 0.36, green: 0.20, blue: 0.10, alpha: 1.0)
    private let woodDarkColor = SKColor(red: 0.23, green: 0.12, blue: 0.04, alpha: 1.0)
    private let ironColor = SKColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    private let ironLight = SKColor(red: 0.27, green: 0.27, blue: 0.27, alpha: 1.0)
    private let amberColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1.0)
    private let crimsonColor = SKColor(red: 0.54, green: 0.13, blue: 0.13, alpha: 1.0)
    private let bronzeColor = SKColor(red: 0.48, green: 0.35, blue: 0.10, alpha: 1.0)

    // Beanbag slide control.
    private let beanbagContainer = SKNode()   // anchored at rest position
    private let beanbagNode = SKNode()        // slides within container
    private let beanbagSize: CGFloat = 70
    private let beanbagMaxOffset: CGFloat = 28
    private var beanbagHitRadius: CGFloat { beanbagSize / 2 + 20 }
    private var beanbagTouch: UITouch?

    // Haptics — fire a light "click" each time the pressed direction changes.
    private let dpadHaptics = UIImpactFeedbackGenerator(style: .light)
    private var lastDpadDirection: CGVector = .zero

    // Action buttons.
    private var btnA: SKShapeNode?
    private var btnB: SKShapeNode?
    private let actionBtnRadius: CGFloat = 26

    // HUD elements (so we can update them later).
    private var scoreLabel: SKLabelNode?
    private var levelLabel: SKLabelNode?
    private var heartsContainer: SKNode?
    private var heartLabels: [SKLabelNode] = []

    // Player health — mirrors HeartsManager.shared.currentHearts
    private var playerHearts = 5
    /// Identity-based set of dogs currently overlapping the player.
    /// Maintained via didBegin / didEnd so we know whether a damage tick should fire.
    private var dogsTouchingPlayer: Set<ObjectIdentifier> = []
    /// Seconds remaining before the next bite can deal damage.
    private var damageCooldown: TimeInterval = 0
    private let damageCooldownDuration: TimeInterval = 0.6
    private var isGameOver = false

    // Inventory
    private let inventory = InventoryManager()
    private var inventoryHUD: InventoryHUDNode?

    override func didMove(to view: SKView) {
        // physicsWorld.contactDelegate is scene-owned so must be re-set on every presentation
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        MusicPlayer.shared.play(named: "CornholeKingsTheme")

        // Keep HUD in sync with HeartsManager on every presentation (handles return from bike race)
        HeartsManager.shared.onChanged = { [weak self] in
            self?.resyncHeartsDisplay()
        }

        // Prevent re-adding nodes that already have parents when returning from the mini-game
        guard !hasSetup else {
            // Resync in case hearts changed while a modal mini-game (bike race) was up
            resyncHeartsDisplay()
            return
        }
        hasSetup = true
        playerHearts = HeartsManager.shared.currentHearts

        backgroundColor = ironColor
        setupScene()
        loadMap()
        setupPlayer()
        addCrtOverlay()
    }

    private func setupScene() {
        addChild(gameWorld)
        camera = cameraNode
        cameraNode.setScale(1.0 / worldZoom)
        addChild(cameraNode)
        setupChrome()
        setupHUD()
        setupDPad()
        setupActionButtons()
        setupInventoryHUD()
    }

    // MARK: - Chrome (top + bottom bars covering the world outside the stage)

    private func setupChrome() {
        let topBar = SKSpriteNode(color: woodColor,
                                   size: CGSize(width: size.width, height: topChromeHeight))
        topBar.position = CGPoint(x: 0, y: size.height / 2 - topChromeHeight / 2)
        topBar.zPosition = 5_000
        cameraNode.addChild(topBar)

        let bottomBar = SKSpriteNode(color: woodColor,
                                      size: CGSize(width: size.width, height: bottomChromeHeight))
        bottomBar.position = CGPoint(x: 0, y: -size.height / 2 + bottomChromeHeight / 2)
        bottomBar.zPosition = 5_000
        cameraNode.addChild(bottomBar)

        // Iron borders separating chrome from stage.
        let topBorder = SKSpriteNode(color: ironColor,
                                      size: CGSize(width: size.width, height: 2))
        topBorder.position = CGPoint(x: 0, y: size.height / 2 - topChromeHeight)
        topBorder.zPosition = 5_001
        cameraNode.addChild(topBorder)

        let bottomBorder = SKSpriteNode(color: ironColor,
                                         size: CGSize(width: size.width, height: 2))
        bottomBorder.position = CGPoint(x: 0, y: -size.height / 2 + bottomChromeHeight)
        bottomBorder.zPosition = 5_001
        cameraNode.addChild(bottomBorder)
    }

    // MARK: - HUD (hearts + score + level), anchored to camera, drawn over top chrome

    private func setupHUD() {
        // HUD content sits in the visible part of the top chrome, BELOW the
        // safe-area inset (notch / Dynamic Island).
        let hudY = size.height / 2 - topSafeAreaInset - baseTopChromeHeight / 2
        let hudPadding: CGFloat = 12

        // Hearts on the left — all 5 slots always present; filled vs. empty reflects current health.
        let hearts = SKNode()
        hearts.position = CGPoint(x: -size.width / 2 + hudPadding, y: hudY)
        hearts.zPosition = 10_001
        heartLabels.removeAll()
        let fullColor  = SKColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1.0)
        let emptyColor = SKColor(white: 0.40, alpha: 0.45)
        for i in 0..<HeartsManager.shared.maxHearts {
            let heart = SKLabelNode(text: i < playerHearts ? "♥" : "♡")
            heart.fontName = "AvenirNext-Heavy"
            heart.fontSize = 22
            heart.fontColor = i < playerHearts ? fullColor : emptyColor
            heart.verticalAlignmentMode = .center
            heart.horizontalAlignmentMode = .left
            heart.position = CGPoint(x: CGFloat(i) * 18, y: 0)
            hearts.addChild(heart)
            heartLabels.append(heart)
        }
        cameraNode.addChild(hearts)
        heartsContainer = hearts

        // Score in the center, amber engraved.
        let score = SKLabelNode(text: "00000")
        score.fontName = "Menlo-Bold"
        score.fontSize = 18
        score.fontColor = amberColor
        score.verticalAlignmentMode = .center
        score.horizontalAlignmentMode = .center
        score.position = CGPoint(x: 0, y: hudY)
        score.zPosition = 10_001
        cameraNode.addChild(score)
        scoreLabel = score

        // Level on the right (shifted left to make room for menu button).
        let lvl = SKLabelNode(text: "LVL 1")
        lvl.fontName = "Menlo"
        lvl.fontSize = 14
        lvl.fontColor = SKColor(white: 0.6, alpha: 1.0)
        lvl.verticalAlignmentMode = .center
        lvl.horizontalAlignmentMode = .right
        lvl.position = CGPoint(x: size.width / 2 - hudPadding - 32, y: hudY)
        lvl.zPosition = 10_001
        cameraNode.addChild(lvl)
        levelLabel = lvl

        // Menu / home button — top-right corner of the HUD bar.
        let menuBtn = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        menuBtn.text = "⌂"
        menuBtn.fontSize = 20
        menuBtn.fontColor = SKColor(white: 0.55, alpha: 1.0)
        menuBtn.verticalAlignmentMode   = .center
        menuBtn.horizontalAlignmentMode = .right
        menuBtn.position  = CGPoint(x: size.width / 2 - hudPadding, y: hudY)
        menuBtn.zPosition = 10_001
        menuBtn.name      = "menuButton"
        cameraNode.addChild(menuBtn)
        menuButtonPosition = menuBtn.position

        // Pause button — top-left of HUD bar, before the hearts.
        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size = CGSize(width: 20, height: 20)
        pauseBtn.position = CGPoint(x: -size.width / 2 + hudPadding + 10, y: hudY)
        pauseBtn.zPosition = 10_001
        pauseBtn.name = "pauseBtn"
        cameraNode.addChild(pauseBtn)
        pauseBtnPosition = pauseBtn.position
    }

    /// Vertical center for the controls — within the bottom chrome but above
    /// the home-indicator safe area.
    private var controlsY: CGFloat {
        let usableBottom = bottomChromeHeight - bottomSafeAreaInset
        return -size.height / 2 + bottomSafeAreaInset + usableBottom / 2
    }

    // MARK: - Beanbag slide control

    private func setupDPad() {
        let cx = -size.width / 2 + beanbagSize / 2 + 22
        let cy = controlsY
        beanbagContainer.position = CGPoint(x: cx, y: cy)
        beanbagContainer.zPosition = 10_000
        cameraNode.addChild(beanbagContainer)
        beanbagContainer.addChild(beanbagNode)

        // Shadow ring behind the beanbag.
        let shadow = SKShapeNode(circleOfRadius: beanbagSize / 2 + 4)
        shadow.fillColor = SKColor(white: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -3)
        shadow.zPosition = 0
        beanbagNode.addChild(shadow)

        // Beanbag body — fabric tan circle.
        let body = SKShapeNode(circleOfRadius: beanbagSize / 2)
        body.fillColor = SKColor(red: 0.76, green: 0.55, blue: 0.28, alpha: 1.0)
        body.strokeColor = SKColor(red: 0.40, green: 0.24, blue: 0.08, alpha: 1.0)
        body.lineWidth = 2.5
        body.zPosition = 1
        body.name = "beanbagBody"
        beanbagNode.addChild(body)

        // Stitching dots around the center seam.
        let stitchColor = SKColor(red: 0.35, green: 0.20, blue: 0.06, alpha: 0.7)
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4
            let r: CGFloat = beanbagSize / 2 - 8
            let dot = SKShapeNode(circleOfRadius: 2)
            dot.fillColor = stitchColor
            dot.strokeColor = .clear
            dot.position = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            dot.zPosition = 2
            beanbagNode.addChild(dot)
        }
        // Cross-seam lines.
        for angle in [CGFloat(0), CGFloat.pi / 2] {
            let seam = SKShapeNode()
            let path = CGMutablePath()
            let dx = cos(angle) * (beanbagSize / 2 - 6)
            let dy = sin(angle) * (beanbagSize / 2 - 6)
            path.move(to: CGPoint(x: -dx, y: -dy))
            path.addLine(to: CGPoint(x: dx, y: dy))
            seam.path = path
            seam.strokeColor = stitchColor
            seam.lineWidth = 1.5
            seam.zPosition = 2
            beanbagNode.addChild(seam)
        }

        // Direction arrows outside the beanbag body.
        let arrowColor = SKColor(red: 0.92, green: 0.82, blue: 0.55, alpha: 0.95)
        let arrowOffset = beanbagSize / 2 + 14
        let arrows: [(String, CGPoint)] = [
            ("▲", CGPoint(x: 0, y:  arrowOffset)),
            ("▼", CGPoint(x: 0, y: -arrowOffset)),
            ("◀", CGPoint(x: -arrowOffset, y: 0)),
            ("▶", CGPoint(x:  arrowOffset, y: 0))
        ]
        for (sym, pos) in arrows {
            let l = SKLabelNode(text: sym)
            l.fontName = "Menlo-Bold"
            l.fontSize = 14
            l.fontColor = arrowColor
            l.verticalAlignmentMode = .center
            l.horizontalAlignmentMode = .center
            l.position = pos
            l.zPosition = 3
            beanbagContainer.addChild(l)   // arrows stay fixed; only beanbagNode slides
        }
    }

    /// Slide the beanbag sprite toward `offset` (clamped to `beanbagMaxOffset`).
    private func slideBeanbag(to offset: CGPoint) {
        let len = sqrt(offset.x * offset.x + offset.y * offset.y)
        let clamped: CGPoint
        if len > beanbagMaxOffset {
            let scale = beanbagMaxOffset / len
            clamped = CGPoint(x: offset.x * scale, y: offset.y * scale)
        } else {
            clamped = offset
        }
        beanbagNode.position = clamped
    }

    /// Animate the beanbag back to its rest position.
    private func snapBeanbagHome() {
        beanbagNode.removeAction(forKey: "snap")
        let snap = SKAction.move(to: .zero, duration: 0.12)
        snap.timingMode = .easeOut
        beanbagNode.run(snap, withKey: "snap")
    }

    // MARK: - Action buttons (A red / B bronze)

    private func setupActionButtons() {
        let btnY = controlsY
        let aX = size.width / 2 - actionBtnRadius - 16
        let bX = aX - 2 * actionBtnRadius - 14

        let a = makeActionButton(color: crimsonColor, label: "A", labelColor: SKColor(red: 0.85, green: 0.55, blue: 0.55, alpha: 1.0))
        a.position = CGPoint(x: aX, y: btnY)
        a.name = "btn_a"
        cameraNode.addChild(a)
        btnA = a

        let b = makeActionButton(color: bronzeColor, label: "B", labelColor: SKColor(red: 0.85, green: 0.70, blue: 0.30, alpha: 1.0))
        b.position = CGPoint(x: bX, y: btnY)
        b.name = "btn_b"
        b.isHidden = true   // shown when weapons are implemented
        cameraNode.addChild(b)
        btnB = b
    }

    private func makeActionButton(color: SKColor, label: String, labelColor: SKColor) -> SKShapeNode {
        let btn = SKShapeNode(circleOfRadius: actionBtnRadius)
        btn.fillColor = color
        btn.strokeColor = ironColor
        btn.lineWidth = 2.0
        btn.zPosition = 10_000

        let l = SKLabelNode(text: label)
        l.fontName = "Menlo-Bold"
        l.fontSize = 22
        l.fontColor = labelColor
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        l.zPosition = 1
        btn.addChild(l)
        return btn
    }

    // MARK: - Inventory HUD (bottom chrome, above D-pad)

    private func setupInventoryHUD() {
        let hud = InventoryHUDNode()
        // Centre horizontally; sit midway between the control area top and the stage bottom border.
        let dpadTopY  = controlsY + beanbagSize / 2 + 14   // top of arrows
        let borderY   = -size.height / 2 + bottomChromeHeight
        hud.position  = CGPoint(x: 0, y: (dpadTopY + borderY) / 2)
        hud.zPosition = 10_000
        cameraNode.addChild(hud)
        inventoryHUD = hud

        inventory.onChanged = { [weak self] in
            guard let self else { return }
            self.inventoryHUD?.refresh(counts: self.inventory.counts)
        }

        // TODO: remove before ship — grants 3 fire bags for testing
        if inventory.counts[.fireBag, default: 0] == 0 {
            inventory.collect(.fireBag, count: 3)
        }
    }

    // MARK: - Map / player setup

    private func loadMap() {
        guard let m = TMXLoader.load(tmxName: "World1") else { return }
        map = m

        m.layerNodes["Spawns"]?.isHidden = true
        m.layerNodes["Ground"]?.zPosition = -1000
        m.layerNodes["Collisions"]?.zPosition = 0
        m.layerNodes["Interactions"]?.zPosition = 0
        m.layerNodes["ImaginationFX"]?.zPosition = 1000
        m.layerNodes["ImaginationFX"]?.isHidden = true

        gameWorld.addChild(m.mapNode)

        buildPhysics(from: m)
        extractBoardPositions(from: m)
        extractBaseballPositions(from: m)
        extractTreePositions(from: m)
        extractAppleTreePositions(from: m)
        extractBeehivePositions(from: m)
        extractPoolPositions(from: m)
        extractChestPositions(from: m)
        extractBridgeStonePositions(from: m)
        extractBridgeWoodPositions(from: m)
        cacheBridgePhysicsNodes(from: m)
        ySortStaticLayers(in: m)

        if UserDefaults.standard.bool(forKey: bridgeUnlockedKey) { unlockBridge() }
    }

    // MARK: - Cornhole Board Detection

    /// Scans every map layer for cornhole-board tiles and stores their world-space
    /// centers. The board tileset is 2×2 tiles; we record the center of each group.
    private func extractBoardPositions(from m: TMXMap) {
        cornholeBoardPositions.removeAll()

        let boardRanges = m.tilesetRanges
            .filter { $0.name.contains("cornhole") }
            .map(\.gidRange)
        guard !boardRanges.isEmpty else {
            print("🎯 No cornhole board tilesets found on the map")
            return
        }

        // Collect all cells that belong to a cornhole-board tileset
        var boardCells = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    if boardRanges.contains(where: { $0.contains(gid) }) {
                        boardCells.insert("\(r),\(c)")
                    }
                }
            }
        }

        // Find the top-left corner of each 2×2 group and record its center
        var processed = Set<String>()
        for cell in boardCells {
            guard !processed.contains(cell) else { continue }
            let parts = cell.split(separator: ",")
            guard parts.count == 2,
                  let r = Int(parts[0]), let c = Int(parts[1]) else { continue }

            let isTopLeft = boardCells.contains("\(r),\(c+1)") &&
                            boardCells.contains("\(r+1),\(c)") &&
                            boardCells.contains("\(r+1),\(c+1)")
            guard isTopLeft else { continue }

            // Average the four tile centers to find the 2×2 group center
            let tl = m.tileCenter(col: c,   row: r)
            let tr = m.tileCenter(col: c+1, row: r)
            let bl = m.tileCenter(col: c,   row: r+1)
            let center = CGPoint(x: (tl.x + tr.x) / 2, y: (tl.y + bl.y) / 2)
            cornholeBoardPositions.append(center)

            processed.insert("\(r),\(c)");   processed.insert("\(r),\(c+1)")
            processed.insert("\(r+1),\(c)"); processed.insert("\(r+1),\(c+1)")
        }
        print("🎯 Found \(cornholeBoardPositions.count) cornhole board(s) on the map")
    }

    /// Scans every map layer for baseball tiles, clusters adjacent tiles, and stores
    /// one world-space centroid per cluster. That single point is what proximity uses.
    private func extractBaseballPositions(from m: TMXMap) {
        baseballPositions.removeAll()

        let baseballRanges = m.tilesetRanges
            .filter { $0.name.contains("baseball") }
            .map(\.gidRange)
        guard !baseballRanges.isEmpty else {
            print("⚾ No baseball tilesets found on the map")
            return
        }

        // 1. Collect all tile coords that belong to a baseball tileset
        var cells: [(r: Int, c: Int)] = []
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard baseballRanges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    cells.append((r, c))
                }
            }
        }

        // 2. Group cells into clusters (flood-fill on adjacency within 3 tiles)
        var assigned = Set<String>()
        for seed in cells {
            let key = "\(seed.r),\(seed.c)"
            guard !assigned.contains(key) else { continue }
            var cluster: [(r: Int, c: Int)] = []
            var queue = [seed]
            while !queue.isEmpty {
                let cell = queue.removeFirst()
                let k = "\(cell.r),\(cell.c)"
                guard !assigned.contains(k) else { continue }
                assigned.insert(k)
                cluster.append(cell)
                for other in cells {
                    let ok = "\(other.r),\(other.c)"
                    guard !assigned.contains(ok) else { continue }
                    if abs(other.r - cell.r) <= 3 && abs(other.c - cell.c) <= 3 {
                        queue.append(other)
                    }
                }
            }
            // Centroid of the cluster
            let sumX = cluster.reduce(0.0) { $0 + m.tileCenter(col: $1.c, row: $1.r).x }
            let sumY = cluster.reduce(0.0) { $0 + m.tileCenter(col: $1.c, row: $1.r).y }
            let centroid = CGPoint(x: sumX / CGFloat(cluster.count),
                                  y: sumY / CGFloat(cluster.count))
            baseballPositions.append(centroid)
        }
        print("⚾ Found \(cells.count) baseball tile(s) → \(baseballPositions.count) object(s) at \(baseballPositions)")
    }

    /// Scans every map layer for tree tiles and stores one world-space center per tile.
    private func extractTreePositions(from m: TMXMap) {
        treePositions.removeAll()
        let treeRanges = m.tilesetRanges
            .filter { $0.name.contains("tree") && !$0.name.contains("apple") }
            .map(\.gidRange)
        guard !treeRanges.isEmpty else {
            print("🌳 No tree tilesets found on the map")
            return
        }
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard treeRanges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    treePositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        print("🌳 Found \(treePositions.count) tree(s) on the map")
    }

    /// Scans every map layer for apple_tree tiles and stores one world-space center per tile.
    private func extractAppleTreePositions(from m: TMXMap) {
        appleTreePositions.removeAll()
        let appleRanges = m.tilesetRanges
            .filter { $0.name.contains("apple") }
            .map(\.gidRange)
        guard !appleRanges.isEmpty else {
            print("🍎 No apple_tree tilesets found on the map")
            return
        }
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard appleRanges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    appleTreePositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        print("🍎 Found \(appleTreePositions.count) apple tree(s) on the map")
    }

    /// Scans every map layer for beehive tiles and stores one world-space centroid per cluster.
    private func extractBeehivePositions(from m: TMXMap) {
        beehivePositions.removeAll()
        let beeRanges = m.tilesetRanges
            .filter { $0.name.contains("bee") }
            .map(\.gidRange)
        guard !beeRanges.isEmpty else {
            print("🐝 No bee tilesets found on the map")
            return
        }
        var cells: [(r: Int, c: Int)] = []
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard beeRanges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    cells.append((r, c))
                }
            }
        }
        // Cluster adjacent tiles and record one centroid per hive
        var assigned = Set<String>()
        for seed in cells {
            let key = "\(seed.r),\(seed.c)"
            guard !assigned.contains(key) else { continue }
            var cluster: [(r: Int, c: Int)] = []
            var queue = [seed]
            while !queue.isEmpty {
                let cell = queue.removeFirst()
                let k = "\(cell.r),\(cell.c)"
                guard !assigned.contains(k) else { continue }
                assigned.insert(k)
                cluster.append(cell)
                for other in cells {
                    let ok = "\(other.r),\(other.c)"
                    guard !assigned.contains(ok) else { continue }
                    if abs(other.r - cell.r) <= 2 && abs(other.c - cell.c) <= 2 {
                        queue.append(other)
                    }
                }
            }
            let sumX = cluster.reduce(0.0) { $0 + m.tileCenter(col: $1.c, row: $1.r).x }
            let sumY = cluster.reduce(0.0) { $0 + m.tileCenter(col: $1.c, row: $1.r).y }
            beehivePositions.append(CGPoint(x: sumX / CGFloat(cluster.count),
                                            y: sumY / CGFloat(cluster.count)))
        }
        print("🐝 Found \(cells.count) beehive tile(s) → \(beehivePositions.count) hive(s)")
    }

    /// Scans for pool tiles (any tileset with "pool" in its name) for beach-ball cornhole triggers.
    private func extractPoolPositions(from m: TMXMap) {
        poolPositions.removeAll()
        let poolRanges = m.tilesetRanges
            .filter { $0.name.contains("pool") }
            .map(\.gidRange)
        guard !poolRanges.isEmpty else { return }
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard poolRanges.contains(where: { $0.contains(gid) }) else { continue }
                    poolPositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        if !poolPositions.isEmpty {
            print("🏊 Found \(poolPositions.count) pool tile(s)")
        }
    }

    /// Scans every map layer for chest tiles and stores one world-space center per tile.
    private func extractChestPositions(from m: TMXMap) {
        chestPositions.removeAll()
        let chestRanges = m.tilesetRanges
            .filter { $0.name.contains("chest") }
            .map(\.gidRange)
        guard !chestRanges.isEmpty else { return }
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard chestRanges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    chestPositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        print("📦 Found \(chestPositions.count) chest(s) on the map")
    }

    /// Scans every map layer for bridge_stone tiles and stores one world-space center per tile.
    private func extractBridgeStonePositions(from m: TMXMap) {
        bridgeStonePositions.removeAll()
        let ranges = m.tilesetRanges
            .filter { $0.name.contains("bridge_stone") }
            .map(\.gidRange)
        guard !ranges.isEmpty else { return }
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard ranges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    bridgeStonePositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        print("🌉 Found \(bridgeStonePositions.count) bridge stone(s) on the map")
    }

    private func extractBridgeWoodPositions(from m: TMXMap) {
        bridgeWoodPositions.removeAll()
        let ranges = m.tilesetRanges
            .filter { $0.name.contains("bridge_wood") }
            .map(\.gidRange)
        guard !ranges.isEmpty else { return }
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard ranges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    bridgeWoodPositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        print("🌉 Found \(bridgeWoodPositions.count) bridge wood tile(s) on the map")
    }

    /// Stores references to the water-blocking physics nodes that sit under ImaginationFX
    /// bridge tiles so they can be removed when the bridge is unlocked.
    private func cacheBridgePhysicsNodes(from m: TMXMap) {
        guard let fxGrid = m.layerGIDs["ImaginationFX"] else { return }
        var bridgeCenters = Set<String>()
        for r in 0..<m.rows {
            for c in 0..<m.cols {
                if (fxGrid[r][c] & 0x0FFF_FFFF) != 0 {
                    let pt = m.tileCenter(col: c, row: r)
                    bridgeCenters.insert("\(Int(pt.x)),\(Int(pt.y))")
                }
            }
        }
        guard !bridgeCenters.isEmpty else { return }
        bridgePhysicsNodes = m.mapNode.children.filter { node in
            guard node.physicsBody != nil else { return false }
            let key = "\(Int(node.position.x)),\(Int(node.position.y))"
            return bridgeCenters.contains(key)
        }
        print("🌉 Cached \(bridgePhysicsNodes.count) bridge physics node(s)")
    }

    /// Called every frame. Shows a single "▲A" prompt for the nearest interactable
    /// object — cornhole board, baseball zone, tree, beehive, pool, or chest — and hides it otherwise.
    private func checkBoardProximity() {
        let cornholeRadius:    CGFloat = 26
        let chestRadius:       CGFloat = 26
        let bridgeStoneRadius: CGFloat = 36
        let baseballRadius:    CGFloat = 56
        let treeRadius:        CGFloat = 20
        let appleTreeRadius:   CGFloat = 26
        let beehiveRadius:     CGFloat = 36
        let poolRadius:        CGFloat = 36
        let bridgeWoodRadius:  CGFloat = 36

        // Find the single closest object across all categories.
        var bestDist         = CGFloat.infinity
        var bestBoard:        CGPoint? = nil
        var bestChest:        CGPoint? = nil
        var bestBridgeStone:  CGPoint? = nil
        var bestBaseball:     CGPoint? = nil
        var bestTree:         CGPoint? = nil
        var bestAppleTree:    CGPoint? = nil
        var bestBeehive:      CGPoint? = nil
        var bestPool:         CGPoint? = nil
        var bestBridgeWood:   CGPoint? = nil

        for pos in cornholeBoardPositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < cornholeRadius && d < bestDist { bestDist = d; bestBoard = pos }
        }
        for pos in chestPositions where !openedChestKeys.contains("\(Int(pos.x)),\(Int(pos.y))") {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < chestRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = pos
            }
        }
        for pos in bridgeStonePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < bridgeStoneRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestBridgeStone = pos
            }
        }
        for pos in baseballPositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < baseballRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestBridgeStone = nil; bestBaseball = pos
            }
        }
        for pos in treePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < treeRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = pos
            }
        }
        for pos in appleTreePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < appleTreeRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = pos
            }
        }
        for pos in beehivePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < beehiveRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = nil; bestBeehive = pos
            }
        }
        for pos in poolPositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < poolRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                bestBeehive = nil; bestPool = pos
            }
        }
        // Only show the bridge_wood prompt if the bridge hasn't been unlocked yet.
        if !UserDefaults.standard.bool(forKey: bridgeUnlockedKey) {
            for pos in bridgeWoodPositions {
                let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
                if d < bridgeWoodRadius && d < bestDist {
                    bestDist = d; bestBoard = nil; bestChest = nil; bestBridgeStone = nil
                    bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                    bestBeehive = nil; bestPool = nil; bestBridgeWood = pos
                }
            }
        }

        nearbyBoardPosition       = bestBoard
        nearbyChestPosition       = bestChest
        nearbyBridgeStonePosition = bestBridgeStone
        nearbyBaseballPosition    = bestBaseball
        nearbyTreePosition        = bestTree
        nearbyAppleTreePosition   = bestAppleTree
        nearbyBeehivePosition     = bestBeehive
        nearbyPoolPosition        = bestPool
        nearbyBridgeWoodPosition  = bestBridgeWood

        // Auto-descend when the player walks away from the tree they climbed.
        if bestTree == nil && player.isInTree { player.descendTree() }

        // Position the single shared prompt above the nearest object, or hide it.
        let anchor: CGPoint?
        if let p = bestBoard              { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestChest         { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBridgeStone   { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBaseball      { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestTree          { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestAppleTree     { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBeehive       { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestPool          { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBridgeWood    { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else                              { anchor = nil }

        if let pos = anchor {
            if interactPrompt == nil {
                interactPrompt = makeInteractPrompt()
                map?.mapNode.addChild(interactPrompt!)
            }
            interactPrompt?.position = pos
        } else {
            interactPrompt?.removeFromParent()
            interactPrompt = nil
        }
    }

    private func makeInteractPrompt() -> SKNode {
        let node = SKNode()

        // Small dark background pill
        let bg = SKSpriteNode(color: SKColor(red: 0.08, green: 0.06, blue: 0.04, alpha: 0.88),
                              size: CGSize(width: 22, height: 9))
        bg.zPosition = 0
        node.addChild(bg)

        let label = SKLabelNode(fontNamed: "PressStart2P-Regular")
        label.text     = "▲A"
        label.fontSize = 5
        label.fontColor = SKColor(red: 0.90, green: 0.75, blue: 0.30, alpha: 1)
        label.verticalAlignmentMode   = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        node.addChild(label)

        // Gentle bob animation
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 2, duration: 0.50),
            SKAction.moveBy(x: 0, y: -2, duration: 0.50),
        ])
        node.run(SKAction.repeatForever(bob))
        node.zPosition = 5_000
        return node
    }

    // MARK: - Open Mini-Game

    private func resetBeanbagControl() {
        beanbagTouch = nil
        lastDpadDirection = .zero
        snapBeanbagHome()
    }

    // MARK: - Chest

    private func openChest() {
        guard let pos = nearbyChestPosition else { return }
        let key = "\(Int(pos.x)),\(Int(pos.y))"
        openedChestKeys.insert(key)
        nearbyChestPosition = nil
        hideChestTile(at: pos)
        // 50/50: heart refill or dog biscuit
        if Bool.random() {
            HeartsManager.shared.gain()
            showPickupText("+ HEART", at: pos)
        } else {
            inventory.collect(.dogBiscuit, count: 1)
            showPickupText("+ DOG BISCUIT", at: pos)
        }
    }

    private func hideChestTile(at worldPos: CGPoint) {
        guard let m = map else { return }
        for (_, layerNode) in m.layerNodes {
            for child in layerNode.children {
                if abs(child.position.x - worldPos.x) < 2 && abs(child.position.y - worldPos.y) < 2 {
                    child.isHidden = true
                }
            }
        }
    }

    // MARK: - Inventory Tap

    private func handleInventoryTap(_ itemType: ItemType) {
        guard !isTransitioning else { return }
        switch itemType {
        case .dogBiscuit:
            guard (inventory.counts[.dogBiscuit] ?? 0) > 0 else { return }
            placeDogBiscuit()
        default:
            break
        }
    }

    private func placeDogBiscuit() {
        inventory.consume(.dogBiscuit, count: 1)
        let biscuitNode = makeBiscuitNode()
        biscuitNode.position = player.position
        biscuitNode.zPosition = -player.position.y + 1
        map?.mapNode.addChild(biscuitNode)
        placedBiscuits.append(PlacedBiscuit(node: biscuitNode, isClaimed: false))
        showPickupText("BISCUIT PLACED!", at: player.position)
    }

    private func makeBiscuitNode() -> SKNode {
        let root = SKNode()
        // Bone shaft
        let shaft = SKSpriteNode(color: SKColor(red: 0.80, green: 0.65, blue: 0.40, alpha: 1.0),
                                 size: CGSize(width: 14, height: 5))
        root.addChild(shaft)
        // Knob ends
        for xOff: CGFloat in [-8, 8] {
            let knob = SKSpriteNode(color: SKColor(red: 0.70, green: 0.52, blue: 0.28, alpha: 1.0),
                                   size: CGSize(width: 6, height: 6))
            knob.position = CGPoint(x: xOff, y: 0)
            root.addChild(knob)
        }
        root.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 1.5, duration: 0.5),
            .moveBy(x: 0, y: -1.5, duration: 0.5),
        ])))
        return root
    }

    private func openCornholeMiniGame(preSelectedOpponent: CornholeMiniGameScene.AIOpponent? = nil) {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let mini = CornholeMiniGameScene(size: self.size)
        mini.scaleMode              = self.scaleMode
        mini.previousScene          = self
        mini.preSelectedOpponent    = preSelectedOpponent
        mini.availableHoneyBags  = inventory.counts[.honeyBag,  default: 0]
        mini.availableBombBags   = inventory.counts[.bombBag,   default: 0]
        mini.availableMagicBags  = inventory.counts[.magicBag,  default: 0]
        mini.availableFireBags   = inventory.counts[.fireBag,   default: 0]
        mini.availableGoldenBags = inventory.counts[.goldenBag, default: 0]
        mini.onComplete = { [weak self, weak mini] _ in
            if let used = mini?.honeyBagsUsed,  used > 0 { self?.inventory.consume(.honeyBag,  count: used) }
            if let used = mini?.bombBagsUsed,   used > 0 { self?.inventory.consume(.bombBag,   count: used) }
            if let used = mini?.magicBagsUsed,  used > 0 { self?.inventory.consume(.magicBag,  count: used) }
            if let used = mini?.fireBagsUsed,   used > 0 { self?.inventory.consume(.fireBag,   count: used) }
            if let used = mini?.goldenBagsUsed, used > 0 { self?.inventory.consume(.goldenBag, count: used) }
            if let earned = mini?.bombBagsEarned,  earned > 0 { self?.inventory.collect(.bombBag,  count: earned) }
            if let earned = mini?.magicBagsEarned, earned > 0 { self?.inventory.collect(.magicBag, count: earned) }
            if let earned = mini?.fireBagsEarned,  earned > 0 { self?.inventory.collect(.fireBag,  count: earned) }
            self?.isTransitioning = false
        }

        let transition = SKTransition.push(with: .up, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(mini, transition: transition)
    }

    private func openCornholeBaseball() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let baseball = CornholeBaseballScene(size: self.size)
        baseball.scaleMode    = self.scaleMode
        baseball.previousScene = self
        baseball.onComplete = { [weak self] _ in
            self?.isTransitioning = false
        }

        let transition = SKTransition.push(with: .up, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(baseball, transition: transition)
    }

    private func openBeeHiveMiniGame() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let bee = BeeHiveScene(size: self.size)
        bee.scaleMode      = self.scaleMode
        bee.previousScene  = self
        bee.startingHearts = playerHearts
        bee.onComplete = { [weak self, weak bee] playerWon in
            guard let self, let bee else { return }
            // Sync hearts — bee stings can reduce health even on a loss
            self.syncHeartsFromBeeHive(to: bee.remainingHearts)
            if playerWon {
                self.inventory.collect(.honeyBag, count: 3)
            }
            self.isTransitioning = false
        }

        let transition = SKTransition.push(with: .up, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(bee, transition: transition)
    }

    private func openBeachBallCornhole() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let beach = BeachBallCornholeScene(size: self.size)
        beach.scaleMode     = self.scaleMode
        beach.previousScene = self
        beach.onComplete = { [weak self] _ in
            self?.isTransitioning = false
        }

        let transition = SKTransition.push(with: .up, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(beach, transition: transition)
    }

    private func openBridgePiranha() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let piranha = BridgePiranhaScene(size: self.size)
        piranha.scaleMode     = self.scaleMode
        piranha.previousScene = self
        piranha.onComplete = { [weak self] won in
            guard let self else { return }
            self.isTransitioning = false
            if won { self.unlockBridge() }
        }

        let transition = SKTransition.push(with: .up, duration: 0.38)
        transition.pausesOutgoingScene = false
        view.presentScene(piranha, transition: transition)
    }

    private func unlockBridge() {
        UserDefaults.standard.set(true, forKey: bridgeUnlockedKey)
        map?.layerNodes["ImaginationFX"]?.isHidden = false
        bridgePhysicsNodes.forEach { $0.removeFromParent() }
        bridgePhysicsNodes.removeAll()
    }

    /// Walks playerHearts down to `remaining`, animating each lost heart in the HUD.
    private func syncHeartsFromBeeHive(to remaining: Int) {
        let target = max(0, remaining)
        while playerHearts > target {
            playerHearts -= 1
            updateHeartsDisplay()
        }
        HeartsManager.shared.set(playerHearts)
        if playerHearts <= 0 { triggerGameOver() }
    }

    private func buildPhysics(from m: TMXMap) {
        let collisions = m.layerGIDs["Collisions"]
        let ground = m.layerGIDs["Ground"]
        let interactions = m.layerGIDs["Interactions"]

        func isWater(_ gid: Int) -> Bool {
            // water1: 22..45, water2: 257..280, water3: 281..304 (see World1.tmx).
            (22...45).contains(gid) || (257...304).contains(gid)
        }

        for r in 0..<m.rows {
            for c in 0..<m.cols {
                let blocked = (collisions?[r][c] ?? 0) != 0
                let waterHere = isWater(ground?[r][c] ?? 0)
                // A bridge (any tile on the Interactions layer at this cell)
                // overrides the water block so the player can cross it.
                let bridgeHere = (interactions?[r][c] ?? 0) != 0
                guard blocked || (waterHere && !bridgeHere) else { continue }

                let blocker = SKNode()
                blocker.position = m.tileCenter(col: c, row: r)
                let body = SKPhysicsBody(rectangleOf: m.tileSize)
                body.isDynamic = false
                body.categoryBitMask = PlayerNode.worldBit
                body.collisionBitMask = PlayerNode.categoryBit
                body.contactTestBitMask = PlayerNode.categoryBit
                blocker.physicsBody = body
                m.mapNode.addChild(blocker)
            }
        }
    }

    private func setupPlayer() {
        player = PlayerNode()
        // Enable contact detection with collectibles
        player.physicsBody?.contactTestBitMask |= CollectibleNode.collectibleBit

        if let m = map {
            let defaultSpawn = firstSpawn(in: m) ?? CGPoint(x: m.sizeInPoints.width / 2,
                                                             y: m.sizeInPoints.height / 2)
            player.position = storySpawnOverride ?? defaultSpawn
            m.mapNode.addChild(player)
            updateCamera()
            spawnCollectibles(in: m)
        } else {
            player.position = .zero
            gameWorld.addChild(player)
        }
    }

    /// Scatter collectibles around the player's starting screen.
    /// Offsets are in world units (1 tile = 8 wu at the default worldZoom).
    private func spawnCollectibles(in m: TMXMap) {
        let origin = player.position
        let items: [(CGFloat, CGFloat, ItemType)] = [
            ( 24,   0, .coin),
            (-24,  16, .coin),
            (  0, -32, .coin),
            ( 40, -16, .bag),
            (-16,  32, .bag),
            (  8,  48, .star),
        ]
        for (dx, dy, type) in items {
            let node = CollectibleNode(type: type)
            node.position = CGPoint(x: origin.x + dx, y: origin.y + dy)
            node.zPosition = 500
            m.mapNode.addChild(node)
        }
    }

    /// Floats a short pickup label upward from a world position then fades it out.
    private func showPickupText(_ text: String, at worldPos: CGPoint) {
        let label = SKLabelNode(fontNamed: "PressStart2P-Regular")
        label.text = text
        label.fontSize = 6
        label.fontColor = SKColor(red: 0.95, green: 0.90, blue: 0.35, alpha: 1.0)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: worldPos.x, y: worldPos.y + 10)
        label.zPosition = 8_000
        map?.mapNode.addChild(label)

        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 14, duration: 0.65),
                .sequence([.wait(forDuration: 0.30), .fadeOut(withDuration: 0.35)]),
            ]),
            .removeFromParent(),
        ]))
    }

    private func firstSpawn(in m: TMXMap) -> CGPoint? {
        guard let spawns = m.layerGIDs["Spawns"] else { return nil }
        for r in 0..<m.rows {
            for c in 0..<m.cols where spawns[r][c] != 0 {
                return m.tileCenter(col: c, row: r)
            }
        }
        return nil
    }

    // MARK: - CRT Overlay
    private func addCrtOverlay() {
        let w = size.width, h = size.height
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let c = ctx.cgContext
            c.clear(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            var y: CGFloat = 0
            while y < h { c.fill(CGRect(x: 0, y: y, width: w, height: 1)); y += 3 }
            let space = CGColorSpaceCreateDeviceRGB()
            let vColors = [UIColor(white: 0, alpha: 0).cgColor,
                           UIColor(white: 0, alpha: 0.18).cgColor,
                           UIColor(white: 0, alpha: 0.70).cgColor] as CFArray
            let vGrad = CGGradient(colorsSpace: space, colors: vColors, locations: [0, 0.55, 1.0])!
            c.drawRadialGradient(vGrad,
                                 startCenter: CGPoint(x: w/2, y: h/2), startRadius: 0,
                                 endCenter:   CGPoint(x: w/2, y: h/2), endRadius: max(w, h) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: w, height: h))
        overlay.position  = .zero
        overlay.zPosition = 20000
        overlay.isUserInteractionEnabled = false
        // Add to cameraNode so it stays screen-space and isn't affected by world scroll/zoom
        cameraNode.addChild(overlay)
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
        guard !isTransitioning else { return }
        let pInCam = touch.location(in: cameraNode)

        // Pause overlay routing
        if isPausedGame {
            for n in nodes(at: touch.location(in: self)) {
                let name = n.name ?? n.parent?.name ?? ""
                if name == "resumeBtn" { resumeGame(); return }
            }
            return
        }

        // Pause button (top-left of HUD).
        let pauseHit: CGFloat = 20
        if distanceSquared(pInCam, pauseBtnPosition) < pauseHit * pauseHit {
            pauseGame(); return
        }

        // Menu button (top chrome).
        let menuHit: CGFloat = 24
        if distanceSquared(pInCam, menuButtonPosition) < menuHit * menuHit {
            returnToMainMenu()
            return
        }

        // Inventory slot taps (bottom chrome, above D-pad).
        for n in nodes(at: touch.location(in: self)) {
            let nm = n.name ?? n.parent?.name ?? ""
            if nm.hasPrefix("slot_") {
                let rawValue = String(nm.dropFirst("slot_".count))
                if let itemType = ItemType(rawValue: rawValue) {
                    handleInventoryTap(itemType)
                    return
                }
            }
        }

        // Action buttons.
        let btnHit = (actionBtnRadius + 6) * (actionBtnRadius + 6)
        if let a = btnA, distanceSquared(pInCam, a.position) < btnHit {
            if nearbyBoardPosition != nil {
                openCornholeMiniGame()
            } else if nearbyChestPosition != nil {
                openChest()
            } else if nearbyBridgeStonePosition != nil {
                openBeachBallCornhole()
            } else if nearbyAppleTreePosition != nil {
                openCornholeMiniGame(preSelectedOpponent: .spirit)
            } else if nearbyBaseballPosition != nil {
                openCornholeBaseball()
            } else if nearbyBeehivePosition != nil {
                openBeeHiveMiniGame()
            } else if nearbyPoolPosition != nil {
                openBeachBallCornhole()
            } else if nearbyBridgeWoodPosition != nil {
                openBridgePiranha()
            } else if nearbyTreePosition != nil {
                if player.isInTree { player.descendTree() } else { player.climbTree() }
            }
            return
        }
        if let b = btnB, distanceSquared(pInCam, b.position) < btnHit {
            // Hook for B action goes here.
            return
        }

        // Claim this touch as the beanbag touch if it lands near the control.
        let pInBag = CGPoint(x: pInCam.x - beanbagContainer.position.x,
                             y: pInCam.y - beanbagContainer.position.y)
        let r2 = pInBag.x * pInBag.x + pInBag.y * pInBag.y
        if beanbagTouch == nil, r2 <= beanbagHitRadius * beanbagHitRadius {
            beanbagTouch = touch
            applyBeanbagOffset(pInBag)
        }
    }

    private func handleTouchMoved(_ touch: UITouch) {
        guard touch === beanbagTouch else { return }
        let pInCam = touch.location(in: cameraNode)
        let pInBag = CGPoint(x: pInCam.x - beanbagContainer.position.x,
                             y: pInCam.y - beanbagContainer.position.y)
        applyBeanbagOffset(pInBag)
    }

    private func handleTouchEnded(_ touch: UITouch) {
        guard touch === beanbagTouch else { return }
        beanbagTouch = nil
        player?.moveDirection = .zero
        lastDpadDirection = .zero
        snapBeanbagHome()
    }

    private func applyBeanbagOffset(_ offset: CGPoint) {
        let deadzone: CGFloat = 6
        let len = sqrt(offset.x * offset.x + offset.y * offset.y)
        guard len > deadzone else {
            player?.moveDirection = .zero
            lastDpadDirection = .zero
            slideBeanbag(to: .zero)
            return
        }
        slideBeanbag(to: offset)

        let newDirection: CGVector
        if abs(offset.x) > abs(offset.y) {
            newDirection = CGVector(dx: offset.x >= 0 ? 1 : -1, dy: 0)
        } else {
            newDirection = CGVector(dx: 0, dy: offset.y >= 0 ? 1 : -1)
        }
        player?.moveDirection = newDirection
        if newDirection.dx != lastDpadDirection.dx || newDirection.dy != lastDpadDirection.dy {
            dpadHaptics.impactOccurred()
            dpadHaptics.prepare()
        }
        lastDpadDirection = newDirection
    }

    private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    // MARK: - Hint Banner

    /// Shows a transient tutorial hint in the stage area, auto-dismissed after 4 s.
    /// Lines are separated by "\n".
    private func showHintBanner(_ message: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let fs: CGFloat = max(5, size.width * 0.036)
        let lineH: CGFloat = fs + 7
        let panelW = size.width * 0.76
        let panelH = CGFloat(lines.count) * lineH + 18

        let banner = SKNode()
        banner.zPosition = 18_000

        let bg = SKSpriteNode(color: SKColor(red: 0.05, green: 0.04, blue: 0.02, alpha: 0.93),
                              size: CGSize(width: panelW, height: panelH))
        banner.addChild(bg)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 2, height: panelH + 2),
                                 cornerRadius: 4)
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 0.9)
        border.fillColor   = .clear
        border.lineWidth   = 2
        banner.addChild(border)

        for (i, line) in lines.enumerated() {
            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text                  = line
            lbl.fontSize              = fs
            lbl.fontColor             = SKColor(red: 0.92, green: 0.82, blue: 0.42, alpha: 1)
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .center
            let totalH = CGFloat(lines.count - 1) * lineH
            lbl.position  = CGPoint(x: 0, y: totalH / 2 - CGFloat(i) * lineH)
            lbl.zPosition = 1
            banner.addChild(lbl)
        }

        // Centre of the visible stage area
        banner.position = CGPoint(x: 0, y: stageCenterY + stageSize * 0.22)
        banner.alpha    = 0
        cameraNode.addChild(banner)

        HapticsManager.shared.lightImpact()
        banner.run(.sequence([
            .fadeIn(withDuration: 0.25),
            .wait(forDuration: 4.0),
            .fadeOut(withDuration: 0.50),
            .removeFromParent(),
        ]))
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        if isPausedGame { return }
        if !isTransitioning {
            player?.update(dt: dt)
            updateDogs(dt: dt)
            updateDamage(dt: dt)
            updateCamera()
            checkBoardProximity()
        }
    }

    private func ySortStaticLayers(in m: TMXMap) {
        for name in ["Collisions", "Interactions"] {
            guard let layer = m.layerNodes[name] else { continue }
            for sprite in layer.children {
                sprite.zPosition = -sprite.position.y
            }
        }
    }

    // MARK: - Camera (smooth follow; player stays centered in the square stage)

    /// Moves the camera so the player is always centered in the stage area,
    /// clamped so the stage never exposes blank world outside the map.
    private func updateCamera() {
        guard let m = map else { return }
        // Clamp player to map bounds so they can't walk off the edge of the world.
        let half = playerHalfExtent
        player.position.x = max(half, min(m.sizeInPoints.width  - half, player.position.x))
        player.position.y = max(half, min(m.sizeInPoints.height - half, player.position.y))

        let halfStage = stageWorldSize / 2
        let cx = max(halfStage, min(m.sizeInPoints.width  - halfStage, player.position.x))
        let cy = max(halfStage, min(m.sizeInPoints.height - halfStage, player.position.y))
        cameraNode.position = CGPoint(x: cx, y: cy - stageCenterYWorld)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        HapticsManager.shared.lightImpact()

        let nodeA = contact.bodyA.node
        let nodeB = contact.bodyB.node

        if let item = (nodeA as? CollectibleNode) ?? (nodeB as? CollectibleNode),
           !item.isBeingCollected {
            let worldPos = item.position
            item.collect()
            inventory.collect(item.itemType)
            showPickupText("+\(item.itemType.displayName)", at: worldPos)
            // PLACEHOLDER: add item_pickup.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("item_pickup.wav", waitForCompletion: false))
            return
        }

        let dog = (nodeA as? DogNode) ?? (nodeB as? DogNode)
        let playerInvolved = (nodeA === player) || (nodeB === player)
        if let dog, playerInvolved {
            dogsTouchingPlayer.insert(ObjectIdentifier(dog))
            // First contact deals damage immediately (subject to cooldown);
            // continued overlap is handled by updateDamage() ticking.
            if damageCooldown == 0, let p = player, !p.isInTree, !isGameOver {
                bite()
            }
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let nodeA = contact.bodyA.node
        let nodeB = contact.bodyB.node
        if let dog = (nodeA as? DogNode) ?? (nodeB as? DogNode) {
            dogsTouchingPlayer.remove(ObjectIdentifier(dog))
        }
    }

    // MARK: - Enemy Dogs

    private func updateDogs(dt: TimeInterval) {
        dogSpawnTimer += dt
        if dogSpawnTimer >= nextDogSpawnInterval && dogs.count < maxDogs {
            dogSpawnTimer = 0
            nextDogSpawnInterval = TimeInterval.random(in: 6...12)
            spawnDog()
        }
        // Attract non-distracted dogs toward any unclaimed biscuits within sniff range.
        let sniffRadius: CGFloat = 80
        for dog in dogs where !dog.isFleeing && dog.biscuitTarget == nil {
            for i in 0..<placedBiscuits.count where !placedBiscuits[i].isClaimed {
                let bpos = placedBiscuits[i].node.position
                let d = hypot(dog.position.x - bpos.x, dog.position.y - bpos.y)
                guard d < sniffRadius else { continue }
                placedBiscuits[i].isClaimed = true
                dog.biscuitTarget = bpos
                let nodeRef = placedBiscuits[i].node
                dog.onFinishedEating = { [weak self, weak nodeRef] in
                    guard let self, let node = nodeRef else { return }
                    node.run(.sequence([
                        .group([.scale(to: 1.5, duration: 0.12), .fadeOut(withDuration: 0.25)]),
                        .removeFromParent(),
                    ]))
                    self.placedBiscuits.removeAll { $0.node === node }
                }
                break
            }
        }

        for dog in dogs {
            let biting = dogsTouchingPlayer.contains(ObjectIdentifier(dog))
            dog.update(dt: dt,
                       playerPosition: player.position,
                       playerInTree: player.isInTree,
                       isBiting: biting)
        }
        dogs = dogs.filter { dog in
            if isDogOffScreen(dog) {
                dogsTouchingPlayer.remove(ObjectIdentifier(dog))
                dog.removeFromParent()
                return false
            }
            return true
        }
    }

    private func spawnDog() {
        guard let m = map else { return }
        let stage   = stageWorldSize
        let centerX = cameraNode.position.x
        let centerY = cameraNode.position.y + stageCenterYWorld
        let pad: CGFloat = 24

        let half = stage / 2
        let edge = Int.random(in: 0...3)
        let pos: CGPoint
        switch edge {
        case 0:
            pos = CGPoint(x: .random(in: centerX - half ... centerX + half),
                          y: centerY + half + pad)
        case 1:
            pos = CGPoint(x: .random(in: centerX - half ... centerX + half),
                          y: centerY - half - pad)
        case 2:
            pos = CGPoint(x: centerX - half - pad,
                          y: .random(in: centerY - half ... centerY + half))
        default:
            pos = CGPoint(x: centerX + half + pad,
                          y: .random(in: centerY - half ... centerY + half))
        }

        let dog = DogNode()
        dog.position = pos
        dogs.append(dog)
        m.mapNode.addChild(dog)

        if !hasShownDogTutorial {
            hasShownDogTutorial = true
            showHintBanner("Dodge the dogs!\nClimb a tree for safety \u{25B2}A")
        }
    }

    private func isDogOffScreen(_ dog: DogNode) -> Bool {
        let stage   = stageWorldSize
        let centerX = cameraNode.position.x
        let centerY = cameraNode.position.y + stageCenterYWorld
        let margin: CGFloat = 56
        return dog.position.x < centerX - stage/2 - margin
            || dog.position.x > centerX + stage/2 + margin
            || dog.position.y < centerY - stage/2 - margin
            || dog.position.y > centerY + stage/2 + margin
    }

    private func clearDogs() {
        dogs.forEach { $0.removeFromParent() }
        dogs.removeAll()
        dogsTouchingPlayer.removeAll()
    }

    /// Called from update() each frame: ticks the damage cooldown and, if a dog
    /// is still latched onto the player, deals another bite.
    private func updateDamage(dt: TimeInterval) {
        damageCooldown = max(0, damageCooldown - dt)
        guard !isGameOver,
              damageCooldown == 0,
              !dogsTouchingPlayer.isEmpty,
              let p = player, !p.isInTree else { return }
        bite()
    }

    /// Apply one heart of damage from a bite, then arm the cooldown.
    private func bite() {
        guard !isGameOver, let p = player, !p.isInTree, playerHearts > 0 else { return }
        damageCooldown = damageCooldownDuration
        playerHearts -= 1
        HeartsManager.shared.lose()
        updateHeartsDisplay()

        HapticsManager.shared.heavyImpact()
        // PLACEHOLDER: add dog_bite.wav to Copy Bundle Resources
        run(SKAction.playSoundFileNamed("dog_bite.wav", waitForCompletion: false))

        // After one bite every dog that's currently latched on runs away off-screen.
        fleeAllBitingDogs()

        if playerHearts <= 0 {
            triggerGameOver()
            return
        }

        // Red hit flash + brief blink so the player can read the damage.
        p.removeAction(forKey: "flash")
        p.run(.sequence([
            .colorize(with: .red, colorBlendFactor: 1.0, duration: 0.0),
            .wait(forDuration: 0.10),
            .colorize(withColorBlendFactor: 0.0, duration: 0.18),
        ]), withKey: "flash")

        p.removeAction(forKey: "blink")
        let blink = SKAction.sequence([
            .fadeAlpha(to: 0.35, duration: 0.05),
            .fadeAlpha(to: 1.0,  duration: 0.05),
        ])
        p.run(.sequence([
            .repeat(blink, count: 4),
            .run { p.alpha = 1.0 },
        ]), withKey: "blink")
    }

    /// Tell every dog currently touching the player to bolt away off-screen and
    /// remove them from the active-contact set so damage stops immediately.
    private func fleeAllBitingDogs() {
        guard let p = player else { return }
        for dog in dogs where dogsTouchingPlayer.contains(ObjectIdentifier(dog)) {
            dog.startFleeing(awayFrom: p.position)
            dogsTouchingPlayer.remove(ObjectIdentifier(dog))
        }
    }

    private func updateHeartsDisplay() {
        // After decrement, playerHearts is the index that just became empty.
        let lostIdx = playerHearts
        guard lostIdx >= 0 && lostIdx < heartLabels.count else { return }
        let lost = heartLabels[lostIdx]

        lost.removeAction(forKey: "heartLost")
        lost.run(.sequence([
            .scale(to: 1.55, duration: 0.08),
            .group([
                .scale(to: 1.0, duration: 0.18),
                .run { [weak lost] in
                    lost?.text = "♡"
                    lost?.fontColor = SKColor(white: 0.40, alpha: 0.45)
                },
            ]),
        ]), withKey: "heartLost")
    }

    /// Instantly redraws all heart slots to match HeartsManager — used when returning
    /// from the bike race or any other modal that may have changed the count off-screen.
    private func resyncHeartsDisplay() {
        playerHearts = HeartsManager.shared.currentHearts
        let fullColor  = SKColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1.0)
        let emptyColor = SKColor(white: 0.40, alpha: 0.45)
        for (i, label) in heartLabels.enumerated() {
            label.removeAllActions()
            label.setScale(1.0)
            label.alpha = 1.0
            if i < playerHearts {
                label.text = "♥"; label.fontColor = fullColor
            } else {
                label.text = "♡"; label.fontColor = emptyColor
            }
        }
    }

    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        isTransitioning = true
        clearDogs()
        player?.physicsBody?.velocity = .zero
        player?.moveDirection = .zero
        player?.removeAction(forKey: "blink")
        player?.removeAction(forKey: "flash")
        player?.alpha = 1.0

        // Darken the screen.
        let overlay = SKSpriteNode(color: SKColor(white: 0, alpha: 0.75), size: size)
        overlay.zPosition = 20_000
        overlay.alpha = 0
        cameraNode.addChild(overlay)
        overlay.run(.fadeIn(withDuration: 0.55))

        // GAME OVER label.
        let label = SKLabelNode(fontNamed: "PressStart2P-Regular")
        label.text = "GAME OVER"
        label.fontSize = 20
        label.fontColor = SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1.0)
        label.verticalAlignmentMode   = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 20_001
        label.alpha = 0
        cameraNode.addChild(label)
        label.run(.sequence([.wait(forDuration: 0.55), .fadeIn(withDuration: 0.30)]))

        // PLACEHOLDER: add game_over.wav to Copy Bundle Resources
        run(SKAction.playSoundFileNamed("game_over.wav", waitForCompletion: false))

        // Restart with a fresh scene after the player has time to read the screen.
        run(.sequence([
            .wait(forDuration: 2.8),
            .run { [weak self] in
                guard let self, let view = self.view else { return }
                HeartsManager.shared.refill()   // new run starts with full hearts
                let fresh = GameScene(size: self.size)
                fresh.scaleMode = self.scaleMode
                view.presentScene(fresh, transition: .fade(withDuration: 0.50))
            },
        ]))
    }

    // MARK: - Pause / Resume

    private func pauseGame() {
        guard !isPausedGame, !isTransitioning else { return }
        isPausedGame = true
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        lastUpdateTime = 0
        pauseOverlayNode?.removeFromParent()
        pauseOverlayNode = nil
    }

    private func showPauseOverlay() {
        let W = size.width, H = size.height
        let ov = SKNode(); ov.zPosition = 15_000
        pauseOverlayNode = ov
        cameraNode.addChild(ov)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -H / 2, width: W, height: H))
        dim.fillColor = SKColor(white: 0, alpha: 0.65); dim.strokeColor = .clear; ov.addChild(dim)

        let panelW: CGFloat = min(W - 48, 280), panelH: CGFloat = 160
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH), cornerRadius: 10)
        panel.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        panel.lineWidth   = 2; ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "PAUSED"; title.fontSize = 16
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 40); ov.addChild(title)

        let btnW = panelW - 40, btnH: CGFloat = 44
        let resumeBg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2, width: btnW, height: btnH), cornerRadius: 8)
        resumeBg.fillColor   = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.20)
        resumeBg.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        resumeBg.lineWidth   = 1.5; resumeBg.position = CGPoint(x: 0, y: -12)
        resumeBg.name = "resumeBtn"; ov.addChild(resumeBg)

        let resumeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        resumeLbl.text = "RESUME"; resumeLbl.fontSize = 11
        resumeLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        resumeLbl.horizontalAlignmentMode = .center; resumeLbl.verticalAlignmentMode = .center
        resumeLbl.position = CGPoint(x: 0, y: -1); resumeLbl.name = "resumeBtn"; resumeBg.addChild(resumeLbl)
    }

    private func returnToMainMenu() {
        guard !isTransitioning else { return }
        isTransitioning = true
        guard let view = self.view else { return }
        let menu = MainMenuScene(size: view.bounds.size)
        menu.scaleMode   = .resizeFill
        menu.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let t = SKTransition.fade(withDuration: 0.45)
        t.pausesOutgoingScene = false
        view.presentScene(menu, transition: t)
    }
}
