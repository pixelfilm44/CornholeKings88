import SpriteKit
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private let gameWorld = SKNode()
    private let cameraNode = SKCameraNode()
    private var player: PlayerNode!
    private var map: TMXMap?
    private var lastUpdateTime: TimeInterval = 0
    private var hasSetup = false  // prevents double-init when scene is re-presented after mini-game

    // Cornhole board interaction
    private var cornholeBoardPositions: [CGPoint] = []
    private var nearbyBoardPosition: CGPoint?
    private var interactPrompt: SKNode?
    // GID range for the "cornhole board" tileset (firstgid=917, 4 tiles = 2×2)
    private let cornholeBoardGIDRange = 917...920

    // Baseball interaction
    private var baseballPositions: [CGPoint] = []
    private var nearbyBaseballPosition: CGPoint?
    // GID for the baseball tileset (firstgid=921, tilecount=2)
    private let baseballGIDRange = 921...922

    // Tree interaction
    private var treePositions: [CGPoint] = []
    private var nearbyTreePosition: CGPoint?
    // GID range for tree tiles (firstgid=923, tilecount=8)
    private let treeGIDRange = 923...930

    // Tutorial state
    private var hasShownDogTutorial = false

    // Enemy dogs
    private var dogs: [DogNode] = []
    private var dogSpawnTimer: TimeInterval = 0
    private var nextDogSpawnInterval: TimeInterval = 7.0
    private let maxDogs = 3

    private var isTransitioning = false
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

    // D-pad cross.
    private let dpad = SKNode()
    private let dpadCrossArm: CGFloat = 110
    private let dpadCrossThick: CGFloat = 36
    private var dpadHitRadius: CGFloat { dpadCrossArm / 2 + 6 }

    // D-pad haptics — fire a light "click" each time the pressed direction changes,
    // mimicking the tactile detents of a physical controller.
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

    // Player health
    private var playerHearts = 3
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

        // Prevent re-adding nodes that already have parents when returning from the mini-game
        guard !hasSetup else { return }
        hasSetup = true

        backgroundColor = ironColor
        setupScene()
        loadMap()
        setupPlayer()
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

        // Hearts on the left.
        let hearts = SKNode()
        hearts.position = CGPoint(x: -size.width / 2 + hudPadding, y: hudY)
        hearts.zPosition = 10_001
        heartLabels.removeAll()
        for i in 0..<3 {
            let heart = SKLabelNode(text: "♥")
            heart.fontName = "AvenirNext-Heavy"
            heart.fontSize = 22
            heart.fontColor = SKColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1.0)
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

        // Level on the right.
        let lvl = SKLabelNode(text: "LVL 1")
        lvl.fontName = "Menlo"
        lvl.fontSize = 14
        lvl.fontColor = SKColor(white: 0.6, alpha: 1.0)
        lvl.verticalAlignmentMode = .center
        lvl.horizontalAlignmentMode = .right
        lvl.position = CGPoint(x: size.width / 2 - hudPadding, y: hudY)
        lvl.zPosition = 10_001
        cameraNode.addChild(lvl)
        levelLabel = lvl
    }

    /// Vertical center for the controls — within the bottom chrome but above
    /// the home-indicator safe area.
    private var controlsY: CGFloat {
        let usableBottom = bottomChromeHeight - bottomSafeAreaInset
        return -size.height / 2 + bottomSafeAreaInset + usableBottom / 2
    }

    // MARK: - D-pad (forged iron cross)

    private func setupDPad() {
        dpad.zPosition = 10_000
        let dpadX = -size.width / 2 + dpadCrossArm / 2 + 16
        let dpadY = controlsY
        dpad.position = CGPoint(x: dpadX, y: dpadY)
        cameraNode.addChild(dpad)

        let hBar = SKSpriteNode(color: ironLight,
                                 size: CGSize(width: dpadCrossArm, height: dpadCrossThick))
        hBar.zPosition = 0
        dpad.addChild(hBar)

        let vBar = SKSpriteNode(color: ironLight,
                                 size: CGSize(width: dpadCrossThick, height: dpadCrossArm))
        vBar.zPosition = 0
        dpad.addChild(vBar)

        // Black outline around the cross (two thin sprites per axis).
        for side in [-1, 1] {
            let topEdge = SKSpriteNode(color: ironColor,
                                        size: CGSize(width: dpadCrossArm, height: 0.5))
            topEdge.position = CGPoint(x: 0, y: CGFloat(side) * dpadCrossThick / 2)
            topEdge.zPosition = 0.5
            dpad.addChild(topEdge)

            let sideEdge = SKSpriteNode(color: ironColor,
                                         size: CGSize(width: 0.5, height: dpadCrossArm))
            sideEdge.position = CGPoint(x: CGFloat(side) * dpadCrossThick / 2, y: 0)
            sideEdge.zPosition = 0.5
            dpad.addChild(sideEdge)
        }

        // Center boss (rusty iron).
        let boss = SKShapeNode(circleOfRadius: 12)
        boss.fillColor = SKColor(red: 0.40, green: 0.22, blue: 0.08, alpha: 1.0)
        boss.strokeColor = ironColor
        boss.lineWidth = 1.0
        boss.zPosition = 1
        dpad.addChild(boss)

        // Direction arrows.
        let arrowColor = SKColor(red: 0.70, green: 0.50, blue: 0.22, alpha: 0.95)
        let arrows: [(String, CGPoint)] = [
            ("▲", CGPoint(x: 0, y: dpadCrossArm / 2 - 11)),
            ("▼", CGPoint(x: 0, y: -dpadCrossArm / 2 + 11)),
            ("◀", CGPoint(x: -dpadCrossArm / 2 + 11, y: 0)),
            ("▶", CGPoint(x: dpadCrossArm / 2 - 11, y: 0))
        ]
        for (sym, pos) in arrows {
            let l = SKLabelNode(text: sym)
            l.fontName = "Menlo-Bold"
            l.fontSize = 18
            l.fontColor = arrowColor
            l.verticalAlignmentMode = .center
            l.horizontalAlignmentMode = .center
            l.position = pos
            l.zPosition = 2
            dpad.addChild(l)
        }
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
        // Centre horizontally; sit midway between the D-pad top and the stage bottom border.
        let dpadTopY  = controlsY + dpadCrossArm / 2
        let borderY   = -size.height / 2 + bottomChromeHeight
        hud.position  = CGPoint(x: 0, y: (dpadTopY + borderY) / 2)
        hud.zPosition = 10_000
        cameraNode.addChild(hud)
        inventoryHUD = hud

        inventory.onChanged = { [weak self] in
            guard let self else { return }
            self.inventoryHUD?.refresh(counts: self.inventory.counts)
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

        gameWorld.addChild(m.mapNode)

        buildPhysics(from: m)
        extractBoardPositions(from: m)
        extractBaseballPositions(from: m)
        extractTreePositions(from: m)
        ySortStaticLayers(in: m)
    }

    // MARK: - Cornhole Board Detection

    /// Scans every map layer for cornhole-board tiles and stores their world-space
    /// centers. The board tileset is 2×2 tiles; we record the center of each group.
    private func extractBoardPositions(from m: TMXMap) {
        cornholeBoardPositions.removeAll()

        // Collect all cells that belong to the cornhole board tileset
        var boardCells = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    if cornholeBoardGIDRange.contains(gid) {
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

        // 1. Collect all tile coords that belong to the baseball tileset
        var cells: [(r: Int, c: Int)] = []
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard baseballGIDRange.contains(gid) else { continue }
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
        var seen = Set<String>()
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard treeGIDRange.contains(gid) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    treePositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        print("🌳 Found \(treePositions.count) tree(s) on the map")
    }

    /// Called every frame. Shows a single "▲A" prompt for the nearest interactable
    /// object — cornhole board, baseball zone, or tree — and hides it otherwise.
    private func checkBoardProximity() {
        let cornholeRadius: CGFloat = 26
        let baseballRadius: CGFloat = 56
        let treeRadius:     CGFloat = 20

        // Find the single closest object across all three categories.
        var bestDist = CGFloat.infinity
        var bestBoard:    CGPoint? = nil
        var bestBaseball: CGPoint? = nil
        var bestTree:     CGPoint? = nil

        for pos in cornholeBoardPositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < cornholeRadius && d < bestDist { bestDist = d; bestBoard = pos }
        }
        for pos in baseballPositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < baseballRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestBaseball = pos
            }
        }
        for pos in treePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < treeRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestBaseball = nil; bestTree = pos
            }
        }

        nearbyBoardPosition    = bestBoard
        nearbyBaseballPosition = bestBaseball
        nearbyTreePosition     = bestTree

        // Auto-descend when the player walks away from the tree they climbed.
        if bestTree == nil && player.isInTree { player.descendTree() }

        // Position the single shared prompt above the nearest object, or hide it.
        let anchor: CGPoint?
        if let p = bestBoard          { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBaseball  { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestTree      { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else                          { anchor = nil }

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

    private func openCornholeMiniGame() {
        guard let view = self.view else { return }
        isTransitioning = true   // freeze main-game input while mini-game is open
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero

        let mini = CornholeMiniGameScene(size: self.size)
        mini.scaleMode    = self.scaleMode
        mini.previousScene = self
        mini.onComplete = { [weak self] _ in
            // Re-enable input when the main scene is restored
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
            player.position = firstSpawn(in: m) ?? CGPoint(x: m.sizeInPoints.width / 2,
                                                            y: m.sizeInPoints.height / 2)
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

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouch(touches.first)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouch(touches.first)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        player?.moveDirection = .zero
        lastDpadDirection = .zero
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        player?.moveDirection = .zero
        lastDpadDirection = .zero
    }

    private func handleTouch(_ touch: UITouch?) {
        guard !isTransitioning, let touch else {
            player?.moveDirection = .zero
            return
        }
        let pInCam = touch.location(in: cameraNode)

        // Action buttons first (don't move while pressing A/B).
        let btnHit = (actionBtnRadius + 6) * (actionBtnRadius + 6)
        if let a = btnA, distanceSquared(pInCam, a.position) < btnHit {
            player?.moveDirection = .zero
            lastDpadDirection = .zero
            if nearbyBoardPosition != nil {
                openCornholeMiniGame()
            } else if nearbyBaseballPosition != nil {
                openCornholeBaseball()
            } else if nearbyTreePosition != nil {
                if player.isInTree { player.descendTree() } else { player.climbTree() }
            }
            return
        }
        if let b = btnB, distanceSquared(pInCam, b.position) < btnHit {
            player?.moveDirection = .zero
            lastDpadDirection = .zero
            // Hook for B action goes here.
            return
        }

        // D-pad direction.
        let pInDpad = CGPoint(x: pInCam.x - dpad.position.x,
                              y: pInCam.y - dpad.position.y)
        let r2 = pInDpad.x * pInDpad.x + pInDpad.y * pInDpad.y
        if r2 > dpadHitRadius * dpadHitRadius {
            player?.moveDirection = .zero
            lastDpadDirection = .zero
            return
        }
        let newDirection: CGVector
        if abs(pInDpad.x) > abs(pInDpad.y) {
            newDirection = CGVector(dx: pInDpad.x >= 0 ? 1 : -1, dy: 0)
        } else if abs(pInDpad.y) > 0 {
            newDirection = CGVector(dx: 0, dy: pInDpad.y >= 0 ? 1 : -1)
        } else {
            newDirection = .zero
        }
        player?.moveDirection = newDirection
        if newDirection != .zero,
           (newDirection.dx != lastDpadDirection.dx || newDirection.dy != lastDpadDirection.dy) {
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
        updateHeartsDisplay()

        HapticsManager.shared.heavyImpact()
        // PLACEHOLDER: add dog_bite.wav to Copy Bundle Resources
        run(SKAction.playSoundFileNamed("dog_bite.wav", waitForCompletion: false))

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

    private func updateHeartsDisplay() {
        // After decrement, playerHearts is exactly the index of the heart that
        // was just lost. Pop it, fade it out, then remove it from the HUD.
        let lostIdx = playerHearts
        guard lostIdx >= 0 && lostIdx < heartLabels.count else { return }
        let lost = heartLabels[lostIdx]
        guard lost.parent != nil else { return }   // already removed

        lost.removeAction(forKey: "heartLost")
        lost.run(.sequence([
            .scale(to: 1.55, duration: 0.08),
            .group([
                .scale(to: 0.0, duration: 0.18),
                .fadeOut(withDuration: 0.18),
            ]),
            .removeFromParent(),
        ]), withKey: "heartLost")
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
                let fresh = GameScene(size: self.size)
                fresh.scaleMode = self.scaleMode
                view.presentScene(fresh, transition: .fade(withDuration: 0.50))
            },
        ]))
    }
}
