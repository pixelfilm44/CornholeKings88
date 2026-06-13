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
    /// Set just before presenting a mini-game; on return the player is placed here (just south of the triggering tile).
    private var pendingReturnPosition: CGPoint?

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
    private let bridgeUnlockedKey    = "bridgeUnlocked_v1"
    private let baseballUnlockedKey  = "baseballUnlocked_v1"
    private let beachBallBeatenKey   = "beachBallBeaten_v1"
    private let goldenLanceKey       = "goldenLanceEarned_v1"

    // Chest interaction
    private var chestPositions: [CGPoint] = []
    private var nearbyChestPosition: CGPoint?
    private var openedChestKeys: Set<String> = []

    // Store interaction (any tile on the "Store" map layer)
    private var storePositions: [CGPoint] = []
    private var nearbyStorePosition: CGPoint?
    private var storeModal: StoreModalNode?

    // World-throw beanbag projectiles
    private var projectiles: [BeanbagProjectile] = []
    private let projectileSpeed: CGFloat = 260
    /// Roughly how far in world units a thrown bag travels before it lands.
    private let projectileRange: CGFloat = 55
    private let projectileHitRadius: CGFloat = 14
    /// Last move direction the player committed to; used to throw bags
    /// when the player is standing still (PlayerNode.currentFacing always
    /// returns *some* facing, but we want responsive aim while moving).
    private var lastFacingVector: CGVector = CGVector(dx: 0, dy: -1)

    // Placed dog biscuits
    private struct PlacedBiscuit { let node: SKNode; var isClaimed: Bool }
    private var placedBiscuits: [PlacedBiscuit] = []

    // Beach ball pool interaction — matches tilesets whose name contains "pool"
    private var poolPositions: [CGPoint] = []
    private var nearbyPoolPosition: CGPoint?

    // Fence interaction — "fences" layer; launches Suburban Jousters
    private var fencePositions: [CGPoint] = []
    private var nearbyFencePosition: CGPoint?

    // Well interaction — tileset name contains "well"; launches Well Flinger
    private var wellPositions: [CGPoint] = []
    private var nearbyWellPosition: CGPoint?

    // High-area chests — chest tiles sitting on a "mountain" layer region.
    // Gated by the Golden Lance: A-press knocks the chest down to walkable
    // ground, where it becomes a normal openable chest.
    private var highChestPositions: [CGPoint] = []
    private var nearbyHighChestPosition: CGPoint?
    /// High knockables that are really the axe pickup (keyed "<intX>,<intY>"
    /// of the high position) — they land as the axe, not as a 50/50 chest.
    private var highAxKeys: Set<String> = []
    /// Fallen-chest sprites keyed by landing position ("<intX>,<intY>"),
    /// so openChest can remove them when the chest is opened.
    private var fallenChestNodes: [String: SKSpriteNode] = [:]

    // Axe pickup — any non-zero tile on an "ax" / "axe" layer. One-time pickup; persisted via `axeEarnedKey`.
    private var axPositions: [CGPoint] = []
    private var nearbyAxPosition: CGPoint?
    private let axeEarnedKey = "axeEarned_v1"
    /// Tree positions that have already been chopped this session/across launches. Keyed
    /// as "intX,intY" (one entry per *cluster*, not per tile).
    private var choppedTreeKeys: Set<String> = []
    private let choppedTreesKey = "choppedTrees_v1"

    // Tutorial state
    private var hasShownDogTutorial = false

    // Enemy dogs
    private var dogs: [DogNode] = []
    private var dogSpawnTimer: TimeInterval = 0
    private var nextDogSpawnInterval: TimeInterval = 12.0
    private let maxDogs = 1

    // Roaming bullies (Billy's gang) — spawn after p1_tom_win
    private var bullies: [BullyNode] = []
    private var bullySpawnTimer: TimeInterval = 0
    private var nextBullySpawnInterval: TimeInterval = 12.0
    private let maxBullies = 1
    /// Seconds remaining of post-victory peace; while > 0 no bully spawns and
    /// no contact with a roaming bully triggers a match.
    private var bullyCooldownRemaining: TimeInterval = 0
    private let bullyCooldownDuration: TimeInterval = 90.0

    // Story mode bat pickup (spawned in world during the bat-search phase)
    private var storyBatNode: SKNode?
    private var storyBatPosition: CGPoint?
    private var nearbyStoryBatPosition: CGPoint?
    private let storyBatRadius: CGFloat = 28

    private var isTransitioning = false
    private var menuButtonPosition: CGPoint = .zero
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var pauseBtnPosition: CGPoint = .zero

    // Pause map — visited screen-sized cells, persisted across launches.
    private static let visitedCellsKey = "visitedMapCells_v1"
    private var mapOverlayNode: SKNode?
    private var visitedCells: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: GameScene.visitedCellsKey) ?? [])
    /// Half the player sprite's size in world units. Used to clamp the player at world boundaries.
    private let playerHalfExtent: CGFloat = 24
    /// Magnification of the world. Larger = sprites/tiles appear bigger and
    /// each "screen" covers less of the map, so navigation has more squares.
    private let worldZoom: CGFloat = 2.0

    // Layout — square stage in the middle, HUD on top, controls on bottom.
    private let baseTopChromeHeight: CGFloat = 48
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

    // Chrome / HUD palette (Bit-Wood Brawler design system).
    private let woodColor     = SKColor(red: 0.36,  green: 0.20,  blue: 0.10,  alpha: 1.0)
    private let woodDarkColor = SKColor(red: 0.23,  green: 0.12,  blue: 0.04,  alpha: 1.0)
    private let ironColor     = SKColor(red: 0.10,  green: 0.10,  blue: 0.10,  alpha: 1.0)
    private let ironLight     = SKColor(red: 0.27,  green: 0.27,  blue: 0.27,  alpha: 1.0)
    private let amberColor    = SKColor(red: 0.78,  green: 0.57,  blue: 0.16,  alpha: 1.0)
    // Design-system constants (match DESIGN.md exactly).
    private let dsPrimary     = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1.0) // #1a0a04
    private let dsGold        = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1.0) // #f0c060
    private let dsHeartRed    = SKColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1.0) // #d4441e
    private let dsIronGray    = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 0.70) // #595959
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
    private var btnBiscuit: SKShapeNode?
    private var btnAxe: SKShapeNode?
    private var btnFort: SKShapeNode?

    // Player-placed wood-log walls. Each log has a static physics body on `worldBit`
    // so both the player and enemies (dogs) collide with it. Choppable with the axe
    // for a +1 wood refund.
    private struct PlacedWoodLog {
        let node: SKNode
        let position: CGPoint
    }
    private var placedWoodLogs: [PlacedWoodLog] = []

    // Build mode — toggled by tapping the fort button. While active, logs trail
    // continuously behind the player. Wood is a permanent material: placing a log
    // does NOT consume the inventory entry, it just transforms a piece of wood
    // from the pile into a deployed fence. Chopping the log returns it to the
    // pile (no net change). Placement is gated by `availableWoodForBuilding` so a
    // player with 14 wood can place at most 14 logs at once. Logs are session-
    // only — on next launch they vanish and the wood count is unchanged, which
    // naturally restores the "full pile" the user expects.
    private var isBuilding: Bool = false
    private var lastBuildPosition: CGPoint = .zero
    private let buildSpacing: CGFloat = 10        // < log width (14) → continuous line
    private let buildBackOffset: CGFloat = 14     // log sits this far behind the player

    private var availableWoodForBuilding: Int {
        max(0, inventory.counts[.wood, default: 0] - placedWoodLogs.count)
    }
    /// Passive Golden Lance indicator in the top HUD (not an action button).
    private var lanceIndicator: SKNode?
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
            if let p = pendingReturnPosition {
                player.position = p
                player.moveDirection = .zero
                player.physicsBody?.velocity = .zero
                pendingReturnPosition = nil
            }
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
        let topBar = SKSpriteNode(color: dsPrimary,
                                   size: CGSize(width: size.width, height: topChromeHeight))
        topBar.position = CGPoint(x: 0, y: size.height / 2 - topChromeHeight / 2)
        topBar.zPosition = 5_000
        cameraNode.addChild(topBar)

        let bottomBar = SKSpriteNode(color: woodColor,
                                      size: CGSize(width: size.width, height: bottomChromeHeight))
        bottomBar.position = CGPoint(x: 0, y: -size.height / 2 + bottomChromeHeight / 2)
        bottomBar.zPosition = 5_000
        cameraNode.addChild(bottomBar)

        // 2px gold border at the bottom edge of the top chrome (design system spec).
        let topBorder = SKSpriteNode(color: dsGold,
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

    // MARK: - HUD (three-zone ribbon), anchored to camera, drawn over top chrome

    private func setupHUD() {
        // Content Y is centered in the visible 48pt band, below the Dynamic Island inset.
        let hudY = size.height / 2 - topSafeAreaInset - baseTopChromeHeight / 2
        let W = size.width

        // Zone A — pause icon (far left, 22×22).
        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size = CGSize(width: 22, height: 22)
        pauseBtn.position = CGPoint(x: -W / 2 + 22, y: hudY)
        pauseBtn.zPosition = 10_001
        pauseBtn.name = "pauseBtn"
        cameraNode.addChild(pauseBtn)
        pauseBtnPosition = pauseBtn.position

        // Zone B — hearts centered (5 slots, filled vs. empty reflects current health).
        let hearts = SKNode()
        hearts.position = CGPoint(x: 0, y: hudY)
        hearts.zPosition = 10_001
        heartLabels.removeAll()
        let maxH = HeartsManager.shared.maxHearts
        let heartSpacing: CGFloat = 20
        let heartStartX = -CGFloat(maxH - 1) * heartSpacing / 2
        for i in 0..<maxH {
            let heart = SKLabelNode(text: i < playerHearts ? "♥" : "♡")
            heart.fontName = "PressStart2P-Regular"
            heart.fontSize = 14
            heart.fontColor = i < playerHearts ? dsHeartRed : dsIronGray
            heart.verticalAlignmentMode = .center
            heart.horizontalAlignmentMode = .center
            heart.position = CGPoint(x: heartStartX + CGFloat(i) * heartSpacing, y: 0)
            hearts.addChild(heart)
            heartLabels.append(heart)
        }
        cameraNode.addChild(hearts)
        heartsContainer = hearts

        // Zone C — close/menu icon (far right, 22×22).
        let menuBtn = SKSpriteNode(imageNamed: "closeIcon")
        menuBtn.size = CGSize(width: 22, height: 22)
        menuBtn.position = CGPoint(x: W / 2 - 22, y: hudY)
        menuBtn.zPosition = 10_001
        menuBtn.name = "menuButton"
        cameraNode.addChild(menuBtn)
        menuButtonPosition = menuBtn.position

        // Golden Lance inventory indicator — sits just left of the close icon. Not tappable;
        // the lance is a passive item used automatically. Hidden until earned.
        let lanceIcon = SKNode()
        lanceIcon.position = CGPoint(x: W / 2 - 50, y: hudY)
        lanceIcon.zPosition = 10_001
        lanceIcon.isHidden = !UserDefaults.standard.bool(forKey: goldenLanceKey)
        let lanceArt = makeLanceButtonContent()
        lanceArt.setScale(0.72)
        lanceIcon.addChild(lanceArt)
        cameraNode.addChild(lanceIcon)
        lanceIndicator = lanceIcon
    }

    /// Vertical center for the controls — within the bottom chrome but above
    /// the home-indicator safe area.
    private var controlsY: CGFloat {
        let usableBottom = bottomChromeHeight - bottomSafeAreaInset
        return -size.height / 2 + bottomSafeAreaInset + usableBottom / 2
    }

    // MARK: - Beanbag slide control

    private func setupDPad() {
        let cx = -size.width / 2 + beanbagSize / 2 + 52
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

        let b = SKShapeNode(circleOfRadius: actionBtnRadius)
        b.fillColor = bronzeColor
        b.strokeColor = ironColor
        b.lineWidth = 2.0
        b.zPosition = 10_000
        b.position = CGPoint(x: bX, y: btnY)
        b.name = "btn_b"
        b.isHidden = true   // visible only while the player has bean bags
        let bagIcon = SKSpriteNode(imageNamed: "bag_16bit")
        bagIcon.texture?.filteringMode = .nearest
        let bagFit: CGFloat = actionBtnRadius * 1.4
        bagIcon.size = CGSize(width: bagFit, height: bagFit)
        bagIcon.zPosition = 1
        b.addChild(bagIcon)
        cameraNode.addChild(b)
        btnB = b

        // Dog biscuit button — fixed position left of B, visible only when player has biscuits.
        let biscuitX = bX - 2 * actionBtnRadius - 14
        let biscuit = SKShapeNode(circleOfRadius: actionBtnRadius)
        biscuit.fillColor = woodDarkColor
        biscuit.strokeColor = ironColor
        biscuit.lineWidth = 2.0
        biscuit.zPosition = 10_000
        biscuit.position = CGPoint(x: biscuitX, y: btnY)
        biscuit.name = "btn_biscuit"
        biscuit.isHidden = true
        biscuit.addChild(makeBiscuitButtonContent())

        let countBadge = SKLabelNode(text: "")
        countBadge.fontName = "Menlo-Bold"
        countBadge.fontSize = 9
        countBadge.fontColor = dsGold
        countBadge.horizontalAlignmentMode = .right
        countBadge.verticalAlignmentMode = .top
        countBadge.position = CGPoint(x: actionBtnRadius - 2, y: actionBtnRadius - 2)
        countBadge.zPosition = 2
        countBadge.name = "btn_biscuit_count"
        biscuit.addChild(countBadge)

        cameraNode.addChild(biscuit)
        btnBiscuit = biscuit

        // Axe button — permanent unlock after collecting the axe. Stacked directly
        // below the A button so it sits within easy reach of the player's thumb.
        let axeY = btnY - 2 * actionBtnRadius - 6
        let axe = SKShapeNode(circleOfRadius: actionBtnRadius)
        axe.fillColor = SKColor(red: 0.18, green: 0.14, blue: 0.06, alpha: 1.0)
        axe.strokeColor = SKColor(red: 0.85, green: 0.82, blue: 0.40, alpha: 1.0)
        axe.lineWidth = 2.0
        axe.zPosition = 10_000
        axe.position = CGPoint(x: aX, y: axeY)
        axe.name = "btn_axe"
        axe.isHidden = !UserDefaults.standard.bool(forKey: axeEarnedKey)
        axe.addChild(makeAxeButtonContent())
        cameraNode.addChild(axe)
        btnAxe = axe

        // Fort button — placed directly left of the axe button. Visible only while
        // the player is carrying wood. Each tap consumes 1 wood and drops a log
        // wall in front of the player.
        let fortX = aX - 2 * actionBtnRadius - 14
        let fort = SKShapeNode(circleOfRadius: actionBtnRadius)
        fort.fillColor = woodDarkColor
        fort.strokeColor = SKColor(red: 0.85, green: 0.82, blue: 0.40, alpha: 1.0)
        fort.lineWidth = 2.0
        fort.zPosition = 10_000
        fort.position = CGPoint(x: fortX, y: axeY)
        fort.name = "btn_fort"
        fort.isHidden = true
        fort.addChild(makeFortButtonContent())
        cameraNode.addChild(fort)
        btnFort = fort
    }

    private func makeFortButtonContent() -> SKNode {
        let root = SKNode()
        root.zPosition = 1
        let log = SKSpriteNode(color: SKColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1.0),
                               size: CGSize(width: 26, height: 10))
        root.addChild(log)
        let ringColor = SKColor(red: 0.30, green: 0.18, blue: 0.08, alpha: 1.0)
        for x: CGFloat in [-10, 10] {
            let ring = SKSpriteNode(color: ringColor, size: CGSize(width: 2, height: 10))
            ring.position = CGPoint(x: x, y: 0)
            root.addChild(ring)
        }
        let highlight = SKSpriteNode(color: SKColor(red: 0.70, green: 0.46, blue: 0.22, alpha: 1.0),
                                     size: CGSize(width: 26, height: 2))
        highlight.position = CGPoint(x: 0, y: 3)
        root.addChild(highlight)
        return root
    }

    private func makeAxeButtonContent() -> SKNode {
        let root = SKNode()
        root.zPosition = 1
        // Wooden handle: thin brown bar rotated -45°
        let handle = SKSpriteNode(color: SKColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1.0),
                                  size: CGSize(width: 26, height: 4))
        handle.zRotation = -.pi / 4
        root.addChild(handle)
        // Iron axe head: silver wedge at the top-left end
        let head = SKSpriteNode(color: SKColor(red: 0.78, green: 0.80, blue: 0.85, alpha: 1.0),
                                size: CGSize(width: 11, height: 9))
        head.position = CGPoint(x: -8, y: 8)
        root.addChild(head)
        // Darker edge stripe on the head
        let edge = SKSpriteNode(color: SKColor(red: 0.45, green: 0.48, blue: 0.55, alpha: 1.0),
                                size: CGSize(width: 2, height: 9))
        edge.position = CGPoint(x: -12, y: 8)
        root.addChild(edge)
        return root
    }

    private func makeBiscuitButtonContent() -> SKNode {
        let root = SKNode()
        root.zPosition = 1
        let shaft = SKSpriteNode(color: SKColor(red: 0.90, green: 0.75, blue: 0.50, alpha: 1.0),
                                 size: CGSize(width: 18, height: 5))
        root.addChild(shaft)
        for xOff: CGFloat in [-11, 11] {
            let knob = SKSpriteNode(color: SKColor(red: 0.80, green: 0.62, blue: 0.36, alpha: 1.0),
                                   size: CGSize(width: 7, height: 7))
            knob.position = CGPoint(x: xOff, y: 0)
            root.addChild(knob)
        }
        return root
    }

    private func makeLanceButtonContent() -> SKNode {
        let root = SKNode()
        root.zPosition = 1
        // Shaft: thin gold bar rotated 45°
        let shaft = SKSpriteNode(color: SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1.0),
                                 size: CGSize(width: 28, height: 4))
        shaft.zRotation = .pi / 4
        root.addChild(shaft)
        // Tip: small bright triangle at the top-right end
        let tip = SKSpriteNode(color: SKColor(red: 1.00, green: 0.96, blue: 0.70, alpha: 1.0),
                               size: CGSize(width: 6, height: 6))
        tip.position = CGPoint(x: 11, y: 11)
        root.addChild(tip)
        // Grip wrap: darker band near the bottom-left end
        let grip = SKSpriteNode(color: SKColor(red: 0.72, green: 0.55, blue: 0.10, alpha: 1.0),
                                size: CGSize(width: 8, height: 5))
        grip.zRotation = .pi / 4
        grip.position = CGPoint(x: -9, y: -9)
        root.addChild(grip)
        return root
    }

    private func updateBiscuitButton() {
        let count = inventory.counts[.dogBiscuit, default: 0]
        btnBiscuit?.isHidden = count == 0
        if let badge = btnBiscuit?.childNode(withName: "btn_biscuit_count") as? SKLabelNode {
            badge.text = "×\(count)"
        }
    }

    private func updateThrowButton() {
        btnB?.isHidden = inventory.counts[.bag, default: 0] == 0
    }

    private func updateFortButton() {
        btnFort?.isHidden = availableWoodForBuilding == 0
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
            self.updateBiscuitButton()
            self.updateThrowButton()
            self.updateFortButton()
            self.storeModal?.refreshCardStates()
        }
        updateBiscuitButton()
        updateThrowButton()
        updateFortButton()
        // Wood resets every round — trees respawn at scene load (see loadChoppedTrees)
        // so any wood the player chopped last session is no longer "in their pocket."
        // They have to re-chop trees this round to refill the pile.
        if let woodCount = inventory.counts[.wood], woodCount > 0 {
            inventory.consume(.wood, count: woodCount)
        }
        // Mirror permanent unlocks (Golden Lance) into the inventory pill row so the
        // player can see what they're carrying. Lance is a single-quantity item.
        if UserDefaults.standard.bool(forKey: goldenLanceKey),
           inventory.counts[.goldenLance, default: 0] == 0 {
            inventory.collect(.goldenLance, count: 1)
        }
        // Initial HUD render — without this, items collected in a prior session
        // don't appear until the next inventory change.
        inventoryHUD?.refresh(counts: inventory.counts)

        // TODO: remove before ship — grants 3 fire bags for testing
        if inventory.counts[.fireBag, default: 0] == 0 {
            inventory.collect(.fireBag, count: 3)
        }

        // Registered after the boot-time mirror/test grants above so those
        // don't fire first-pickup hints — only items earned in play do.
        inventory.onCollect = { [weak self] type in
            self?.maybeShowItemUseHint(for: type)
        }
    }

    // MARK: - Map / player setup

    private func loadMap() {
        guard let m = TMXLoader.load(tmxName: "World1") else { return }
        map = m

        m.layerNodes["Spawns"]?.isHidden = true
        // Ground must stay below all ySorted Interactions tiles.
        // ySortStaticLayers assigns zPosition = -position.y; on a 100×100 × 16px map
        // the topmost tiles reach y≈1592, so their effective z = -1592. Ground must
        // be below that worst case — use -10_000 for a map-size-independent floor.
        m.layerNodes["Ground"]?.zPosition = -10_000
        m.layerNodes["Collisions"]?.zPosition = 0
        m.layerNodes["Interactions"]?.zPosition = 0
        m.layerNodes["ImaginationFX"]?.zPosition = 1000
        m.layerNodes["ImaginationFX"]?.isHidden = true
        m.layerNodes["Baseball"]?.zPosition = 500
        m.layerNodes["Baseball"]?.isHidden = true

        gameWorld.addChild(m.mapNode)

        buildPhysics(from: m)
        extractBoardPositions(from: m)
        extractBaseballPositions(from: m)
        extractTreePositions(from: m)
        extractAppleTreePositions(from: m)
        extractBeehivePositions(from: m)
        extractPoolPositions(from: m)
        extractChestPositions(from: m)
        extractStorePositions(from: m)
        extractBridgeStonePositions(from: m)
        extractBridgeWoodPositions(from: m)
        extractFencePositions(from: m)
        extractWellPositions(from: m)
        extractAxPositions(from: m)
        loadChoppedTrees()
        hideAlreadyChoppedTrees()
        cacheBridgePhysicsNodes(from: m)
        ySortStaticLayers(in: m)

        if UserDefaults.standard.bool(forKey: bridgeUnlockedKey) { unlockBridge() }
        if CornholeStatsManager.shared.baseballUnlocked { unlockBaseball() }
        if StoryManager.shared.hasFlag(.baseballEnabled) { unlockBaseball() }
        spawnStoryBatIfNeeded()
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
            .filter { $0.name.contains("big_oak_tree") }
            .map(\.gidRange)
        guard !treeRanges.isEmpty else {
            print("🌳 No tree tilesets found on the map")
            return
        }
        guard let grid = m.layerGIDs["Interactions"] else {
            print("🌳 No Interactions layer found — tree climbing disabled")
            return
        }
        for r in 0..<m.rows {
            for c in 0..<m.cols {
                let gid = grid[r][c] & 0x0FFF_FFFF
                guard treeRanges.contains(where: { $0.contains(gid) }) else { continue }
                treePositions.append(m.tileCenter(col: c, row: r))
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
        guard let grid = m.layerGIDs["Interactions"] else {
            print("🍎 No Interactions layer found — apple tree interaction disabled")
            return
        }
        for r in 0..<m.rows {
            for c in 0..<m.cols {
                let gid = grid[r][c] & 0x0FFF_FFFF
                guard appleRanges.contains(where: { $0.contains(gid) }) else { continue }
                appleTreePositions.append(m.tileCenter(col: c, row: r))
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
        highChestPositions.removeAll()
        let chestRanges = m.tilesetRanges
            .filter { $0.name.contains("chest") }
            .map(\.gidRange)
        guard !chestRanges.isEmpty else { return }

        var seen = Set<String>()
        for (layerName, grid) in m.layerGIDs {
            // The axe pickup is drawn with a chest tile on its own "ax" layer —
            // it's handled by extractAxPositions, never as a treasure chest.
            let lname = layerName.lowercased()
            guard lname != "ax" && lname != "axe" else { continue }
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard chestRanges.contains(where: { $0.contains(gid) }) else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    let pos = m.tileCenter(col: c, row: r)
                    if isOnHighArea(row: r, col: c, in: m) {
                        highChestPositions.append(pos)
                    } else {
                        chestPositions.append(pos)
                    }
                }
            }
        }
        print("📦 Found \(chestPositions.count) ground chest(s), \(highChestPositions.count) high chest(s) on the map")
    }

    /// True when a tile cell sits inside a mountain ("high area") region.
    /// Covers both authoring styles: the object painted on the mountains layer
    /// itself (its own GID makes the cell non-zero), or on another layer over
    /// the plateau (most surrounding cells are mountain).
    private func isOnHighArea(row: Int, col: Int, in m: TMXMap) -> Bool {
        let mountainGrids: [[[Int]]] = m.layerGIDs
            .filter { $0.key.lowercased().contains("mountain") }
            .map(\.value)
        func mountainCell(_ r: Int, _ c: Int) -> Bool {
            guard r >= 0, r < m.rows, c >= 0, c < m.cols else { return false }
            for g in mountainGrids where (g[r][c] & 0x0FFF_FFFF) != 0 { return true }
            return false
        }
        if mountainCell(row, col) { return true }
        var neighbors = 0
        for dr in -1...1 {
            for dc in -1...1 where !(dr == 0 && dc == 0) {
                if mountainCell(row + dr, col + dc) { neighbors += 1 }
            }
        }
        return neighbors >= 4
    }

    /// Scans the "Store" map layer for any non-zero tile and stores one world-space
    /// center per tile. Pressing A near any of these opens the store modal.
    private func extractStorePositions(from m: TMXMap) {
        storePositions.removeAll()
        guard let grid = m.layerGIDs["Store"] else {
            print("🏪 No Store layer found on the map")
            return
        }
        for r in 0..<m.rows {
            for c in 0..<m.cols {
                let gid = grid[r][c] & 0x0FFF_FFFF
                guard gid != 0 else { continue }
                storePositions.append(m.tileCenter(col: c, row: r))
            }
        }
        print("🏪 Found \(storePositions.count) store tile(s) on the map")
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

    /// Scans the "fences" map layer for any non-zero tile and stores one world-space
    /// center per tile. Pressing A near a fence launches Suburban Jousters.
    private func extractFencePositions(from m: TMXMap) {
        fencePositions.removeAll()
        guard let grid = m.layerGIDs["fences"] else { return }
        var seen = Set<String>()
        for r in 0..<m.rows {
            for c in 0..<m.cols {
                let gid = grid[r][c] & 0x0FFF_FFFF
                guard gid != 0 else { continue }
                let key = "\(r),\(c)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                fencePositions.append(m.tileCenter(col: c, row: r))
            }
        }
        print("🏚️ Found \(fencePositions.count) fence tile(s) on the map")
    }

    private func extractWellPositions(from m: TMXMap) {
        wellPositions.removeAll()
        let ranges = m.tilesetRanges
            .filter { $0.name.contains("well") }
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
                    wellPositions.append(m.tileCenter(col: c, row: r))
                }
            }
        }
        print("🪣 Found \(wellPositions.count) well tile(s) on the map")
    }

    /// Scans any map layer whose name contains "ax" (case-insensitive) for non-zero
    /// tiles. Pressing A near one — while the axe hasn't been earned yet — picks it up.
    private func extractAxPositions(from m: TMXMap) {
        axPositions.removeAll()
        highAxKeys.removeAll()
        // Skip if the player already owns the axe — the pickup tile should disappear.
        let earned = UserDefaults.standard.bool(forKey: axeEarnedKey)
        var seen = Set<String>()
        for (layerName, grid) in m.layerGIDs {
            let lname = layerName.lowercased()
            guard lname == "ax" || lname == "axe" else { continue }
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard gid != 0 else { continue }
                    let key = "\(r),\(c)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    let pos = m.tileCenter(col: c, row: r)
                    if earned {
                        // Already collected — hide the tile permanently.
                        hideChestTile(at: pos)
                    } else if isOnHighArea(row: r, col: c, in: m) {
                        // On a high area — must be knocked down with the lance
                        // first; it lands as the axe pickup, not a chest.
                        highChestPositions.append(pos)
                        highAxKeys.insert("\(Int(pos.x)),\(Int(pos.y))")
                    } else {
                        axPositions.append(pos)
                    }
                }
            }
        }
        print("🪓 Found \(axPositions.count) axe pickup tile(s) + \(highAxKeys.count) on high areas (earned=\(earned))")
    }

    private func loadChoppedTrees() {
        // Trees respawn each round — start every scene load with no chopped trees
        // and clear any legacy persisted state so old saves don't keep tiles hidden.
        choppedTreeKeys = []
        UserDefaults.standard.removeObject(forKey: choppedTreesKey)
    }

    private func saveChoppedTrees() {
        // Intentionally no-op: chopped trees do not persist between sessions.
    }

    /// On scene load, re-hide every tree tile that the player has already chopped.
    private func hideAlreadyChoppedTrees() {
        guard !choppedTreeKeys.isEmpty, let m = map else { return }
        // Each chopped key is a single tile center — but a tree spans multiple tiles.
        // We stored the cluster center; here we re-hide every tree/apple tile within
        // a chop radius of each saved center.
        for key in choppedTreeKeys {
            let parts = key.split(separator: ",")
            guard parts.count == 2,
                  let x = Double(parts[0]), let y = Double(parts[1]) else { continue }
            hideTreeTiles(near: CGPoint(x: x, y: y), in: m)
        }
        // Drop those positions out of the climb/apple lists so the prompts don't reappear.
        treePositions.removeAll { isChopped($0) }
        appleTreePositions.removeAll { isChopped($0) }
    }

    private func isChopped(_ pos: CGPoint) -> Bool {
        // Match if any saved key is within ~one tile of this position.
        for key in choppedTreeKeys {
            let parts = key.split(separator: ",")
            guard parts.count == 2,
                  let kx = Double(parts[0]), let ky = Double(parts[1]) else { continue }
            if hypot(pos.x - CGFloat(kx), pos.y - CGFloat(ky)) < 24 { return true }
        }
        return false
    }

    /// Hides every map tile (across all layers) in the connected cluster of tree/apple
    /// tiles starting at `worldPos`. Uses a flood-fill across the 8 surrounding neighbours
    /// so multi-tile tree sprites are removed in their entirety. Also seeds the fill from
    /// every tree tile within a small radius, in case the chop point lands on a transparent
    /// edge tile and isn't directly connected to the trunk.
    /// Returns the world-space centers of every tree tile that was hidden, so the caller
    /// can scrub those exact positions from the proximity-prompt arrays.
    @discardableResult
    private func hideTreeTiles(near worldPos: CGPoint, in m: TMXMap) -> [CGPoint] {
        let treeRanges = m.tilesetRanges
            .filter { $0.name.contains("tree") || $0.name.contains("apple") }
            .map(\.gidRange)
        guard !treeRanges.isEmpty else { return [] }
        let tw = m.tileSize.width
        let th = m.tileSize.height

        func isTreeTile(_ r: Int, _ c: Int) -> Bool {
            guard r >= 0, r < m.rows, c >= 0, c < m.cols else { return false }
            for (_, grid) in m.layerGIDs {
                let gid = grid[r][c] & 0x0FFF_FFFF
                if gid != 0 && treeRanges.contains(where: { $0.contains(gid) }) { return true }
            }
            return false
        }

        // Convert worldPos to a tile coordinate (matches m.tileCenter inversion).
        let seedCol = Int(floor(worldPos.x / tw))
        let seedRow = m.rows - 1 - Int(floor(worldPos.y / th))

        // Seed with every tree tile in a 2-tile radius around the chop point — covers cases
        // where the chop center lands on an off-by-one neighbour of the trunk.
        var stack: [(r: Int, c: Int)] = []
        let seedSpan = 2
        for dr in -seedSpan...seedSpan {
            for dc in -seedSpan...seedSpan {
                let r = seedRow + dr, c = seedCol + dc
                if isTreeTile(r, c) { stack.append((r, c)) }
            }
        }
        // Fallback: if nothing nearby is a tree tile (shouldn't happen — caller already
        // verified one was), just bail.
        guard !stack.isEmpty else { return [] }

        // Flood-fill: 8-connected so diagonally-touching canopy tiles get pulled in too.
        var visited = Set<Int>()
        let cols = m.cols
        var clusterCells: [(r: Int, c: Int)] = []
        while let cell = stack.popLast() {
            let key = cell.r * cols + cell.c
            if visited.contains(key) { continue }
            visited.insert(key)
            guard isTreeTile(cell.r, cell.c) else { continue }
            clusterCells.append(cell)
            for dr in -1...1 {
                for dc in -1...1 where !(dr == 0 && dc == 0) {
                    stack.append((cell.r + dr, cell.c + dc))
                }
            }
        }

        // Hide only the sprites belonging to a tree tileset at each cluster cell. We
        // skip the Ground/Collisions/etc. tiles underneath so the existing grass keeps
        // showing through once the tree is gone.
        for (layerName, grid) in m.layerGIDs {
            guard let layerNode = m.layerNodes[layerName] else { continue }
            // Only consider cells in this layer that hold a tree-range GID. Avoids
            // hiding the matching grass/ground tile at the same world position.
            let layerTreeCenters: [CGPoint] = clusterCells.compactMap { cell in
                let gid = grid[cell.r][cell.c] & 0x0FFF_FFFF
                guard gid != 0, treeRanges.contains(where: { $0.contains(gid) }) else { return nil }
                return m.tileCenter(col: cell.c, row: cell.r)
            }
            guard !layerTreeCenters.isEmpty else { continue }
            for child in layerNode.children {
                for center in layerTreeCenters {
                    if abs(child.position.x - center.x) < tw / 2 + 1 &&
                       abs(child.position.y - center.y) < th / 2 + 1 {
                        child.isHidden = true
                        break
                    }
                }
            }
        }

        // Return every tree-tile world center in the cluster (across all layers,
        // deduplicated) so the caller can clear the matching proximity entries.
        var seenCenters = Set<String>()
        var centers: [CGPoint] = []
        for cell in clusterCells {
            let pt = m.tileCenter(col: cell.c, row: cell.r)
            let key = "\(Int(pt.x)),\(Int(pt.y))"
            if seenCenters.insert(key).inserted { centers.append(pt) }
        }
        return centers
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
        let storeRadius:       CGFloat = 28
        let bridgeStoneRadius: CGFloat = 36
        let baseballRadius:    CGFloat = 56
        let treeRadius:        CGFloat = 20
        let appleTreeRadius:   CGFloat = 26
        let beehiveRadius:     CGFloat = 36
        let poolRadius:        CGFloat = 36
        let bridgeWoodRadius:  CGFloat = 36
        let fenceRadius:       CGFloat = 36
        let wellRadius:        CGFloat = 36
        let highChestRadius:   CGFloat = 34
        let axRadius:          CGFloat = 24

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
        var bestStore:        CGPoint? = nil
        var bestFence:        CGPoint? = nil
        var bestWell:         CGPoint? = nil
        var bestHighChest:    CGPoint? = nil
        var bestAx:           CGPoint? = nil

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
        for pos in storePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < storeRadius && d < bestDist {
                bestDist = d
                bestBoard = nil; bestChest = nil; bestStore = pos
            }
        }
        for pos in bridgeStonePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < bridgeStoneRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = pos
            }
        }
        if CornholeStatsManager.shared.baseballUnlocked || StoryManager.shared.hasFlag(.baseballEnabled) {
            for pos in baseballPositions {
                let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
                if d < baseballRadius && d < bestDist {
                    bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil; bestBaseball = pos
                }
            }
        }
        for pos in treePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < treeRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = pos
            }
        }
        for pos in appleTreePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < appleTreeRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = pos
            }
        }
        for pos in beehivePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < beehiveRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = nil; bestBeehive = pos
            }
        }
        for pos in poolPositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < poolRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                bestBeehive = nil; bestPool = pos
            }
        }
        // Only show the bridge_wood prompt if the bridge hasn't been unlocked yet.
        if !UserDefaults.standard.bool(forKey: bridgeUnlockedKey) {
            for pos in bridgeWoodPositions {
                let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
                if d < bridgeWoodRadius && d < bestDist {
                    bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                    bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                    bestBeehive = nil; bestPool = nil; bestBridgeWood = pos
                }
            }
        }

        for pos in fencePositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < fenceRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                bestBeehive = nil; bestPool = nil; bestBridgeWood = nil; bestFence = pos
            }
        }

        for pos in wellPositions {
            let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
            if d < wellRadius && d < bestDist {
                bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                bestBeehive = nil; bestPool = nil; bestBridgeWood = nil; bestFence = nil; bestWell = pos
            }
        }

        // Axe pickup — only while the player hasn't earned it yet.
        if !UserDefaults.standard.bool(forKey: axeEarnedKey) {
            for pos in axPositions {
                let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
                if d < axRadius && d < bestDist {
                    bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                    bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                    bestBeehive = nil; bestPool = nil; bestBridgeWood = nil
                    bestFence = nil; bestWell = nil; bestHighChest = nil; bestAx = pos
                }
            }
        }

        // High-area chests — knockable with the lance. No lance (or no chest
        // left up there) → no prompt at all.
        if UserDefaults.standard.bool(forKey: goldenLanceKey) {
            for pos in highChestPositions {
                let d = hypot(player.position.x - pos.x, player.position.y - pos.y)
                if d < highChestRadius && d < bestDist {
                    bestDist = d; bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                    bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                    bestBeehive = nil; bestPool = nil; bestBridgeWood = nil
                    bestFence = nil; bestWell = nil; bestHighChest = pos
                }
            }
        }

        // Story bat — only active during the bat-search phase
        var bestStoryBat: CGPoint? = nil
        if let batPos = storyBatPosition {
            let d = hypot(player.position.x - batPos.x, player.position.y - batPos.y)
            if d < storyBatRadius && d < bestDist {
                bestDist = d
                bestBoard = nil; bestChest = nil; bestStore = nil; bestBridgeStone = nil
                bestBaseball = nil; bestTree = nil; bestAppleTree = nil
                bestBeehive = nil; bestPool = nil; bestBridgeWood = nil; bestFence = nil
                bestWell = nil; bestHighChest = nil; bestAx = nil
                bestStoryBat = batPos
            }
        }

        nearbyBoardPosition       = bestBoard
        nearbyChestPosition       = bestChest
        nearbyStorePosition       = bestStore
        nearbyBridgeStonePosition = bestBridgeStone
        nearbyBaseballPosition    = bestBaseball
        nearbyTreePosition        = bestTree
        nearbyAppleTreePosition   = bestAppleTree
        nearbyBeehivePosition     = bestBeehive
        nearbyPoolPosition        = bestPool
        nearbyBridgeWoodPosition  = bestBridgeWood
        nearbyFencePosition       = bestFence
        nearbyWellPosition        = bestWell
        nearbyHighChestPosition   = bestHighChest
        nearbyAxPosition          = bestAx
        nearbyStoryBatPosition    = bestStoryBat

        // Auto-descend when the player walks away from the tree they climbed.
        if bestTree == nil && player.isInTree { player.descendTree() }

        // Position the single shared prompt above the nearest object, or hide it.
        let anchor: CGPoint?
        if let p = bestBoard              { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestChest         { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestStore         { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBridgeStone   { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBaseball      { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestTree          { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestAppleTree     { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBeehive       { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestPool          { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestBridgeWood    { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestFence         { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestWell          { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestHighChest     { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestAx            { anchor = CGPoint(x: p.x, y: p.y + 22) }
        else if let p = bestStoryBat      { anchor = CGPoint(x: p.x, y: p.y + 22) }
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
        guard let pos = nearbyChestPosition, let m = map else { return }
        let key = "\(Int(pos.x)),\(Int(pos.y))"
        openedChestKeys.insert(key)
        nearbyChestPosition = nil

        // Build 6-frame animation from the horizontal sprite sheet (96×16 → 6×16×16 frames).
        let sheet = SKTexture(imageNamed: "Chest_Anim")
        sheet.filteringMode = .nearest
        let frameCount = 6
        let nW = 1.0 / CGFloat(frameCount)
        var frames: [SKTexture] = []
        for i in 0..<frameCount {
            let t = SKTexture(rect: CGRect(x: CGFloat(i) * nW, y: 0, width: nW, height: 1), in: sheet)
            t.filteringMode = .nearest
            frames.append(t)
        }

        // Overlay sprite sits exactly on the chest tile; zPosition above map content.
        let anim = SKSpriteNode(texture: frames[0], size: m.tileSize)
        anim.position = pos
        anim.zPosition = 500
        m.mapNode.addChild(anim)

        // Hide the static tile immediately so the animation replaces it.
        hideChestTile(at: pos)

        // Play through all frames once (0.08s each ≈ 0.48 s total); restore:false keeps the last frame visible.
        let play = SKAction.animate(with: frames, timePerFrame: 0.08, resize: false, restore: false)
        anim.run(play) { [weak self] in
            guard let self else { return }
            if Bool.random() {
                HeartsManager.shared.gain()
                self.showPickupText("+ HEART", at: pos)
            } else {
                self.inventory.collect(.dogBiscuit, count: 1)
                self.showPickupText("+ DOG BISCUIT", at: pos)
            }
        }

        // If this was a chest knocked down from a high area, the static tile is
        // long gone — remove the fallen sprite so the open animation replaces it.
        if let fallen = fallenChestNodes.removeValue(forKey: key) {
            fallen.removeFromParent()
        }
    }

    // MARK: - High-Area Chest (Golden Lance)

    /// Find walkable ground for a knocked-down chest, working from the ledge
    /// toward the player — who is, by definition, standing on walkable ground.
    private func chestLandingSpot(from chestPos: CGPoint) -> CGPoint {
        for t: CGFloat in [0.45, 0.60, 0.75, 0.90] {
            let p = CGPoint(x: chestPos.x + (player.position.x - chestPos.x) * t,
                            y: chestPos.y + (player.position.y - chestPos.y) * t)
            if isWalkable(p) { return p }
        }
        return player.position
    }

    /// Lance jab + chest arcs off the ledge and lands as a normal openable chest.
    private func knockChestOffHighArea() {
        guard let chestPos = nearbyHighChestPosition else { return }
        nearbyHighChestPosition = nil
        highChestPositions.removeAll { abs($0.x - chestPos.x) < 1 && abs($0.y - chestPos.y) < 1 }

        // Face the ledge and swing.
        let dir = CGVector(dx: chestPos.x - player.position.x,
                           dy: chestPos.y - player.position.y)
        player.face(toward: dir)
        player.playAttack()
        playLanceJab(toward: dir)
        HapticsManager.shared.lightImpact()

        // Chest pops off at the jab's apex and arcs down to the ground.
        let landing = chestLandingSpot(from: chestPos)
        run(.sequence([
            .wait(forDuration: 0.20),
            .run { [weak self] in self?.launchChestArc(from: chestPos, to: landing) },
        ]))
    }

    /// Quick gold lance thrust from the player toward the target — a visual
    /// flourish layered over the sprite-sheet attack animation.
    private func playLanceJab(toward dir: CGVector) {
        guard let m = map else { return }
        let len = max(1, hypot(dir.dx, dir.dy))
        let ux = dir.dx / len, uy = dir.dy / len

        let lance = SKNode()
        let shaft = SKSpriteNode(color: dsGold, size: CGSize(width: 16, height: 2.5))
        shaft.position = CGPoint(x: 8, y: 0)
        let tip = SKSpriteNode(color: SKColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1),
                               size: CGSize(width: 4, height: 4))
        tip.position = CGPoint(x: 17, y: 0)
        lance.addChild(shaft)
        lance.addChild(tip)
        lance.zRotation = atan2(uy, ux)
        lance.position = CGPoint(x: player.position.x + ux * 8,
                                 y: player.position.y + uy * 8)
        lance.zPosition = player.zPosition + 1
        m.mapNode.addChild(lance)

        let out = SKAction.moveBy(x: ux * 12, y: uy * 12, duration: 0.12)
        out.timingMode = .easeOut
        lance.run(.sequence([
            out,
            .moveBy(x: -ux * 6, y: -uy * 6, duration: 0.10),
            .fadeOut(withDuration: 0.10),
            .removeFromParent(),
        ]))
    }

    private func launchChestArc(from chestPos: CGPoint, to landing: CGPoint) {
        guard let m = map else { return }
        hideChestTile(at: chestPos)

        // Closed-chest art = frame 0 of the same sheet openChest animates.
        let sheet = SKTexture(imageNamed: "Chest_Anim")
        sheet.filteringMode = .nearest
        let closed = SKTexture(rect: CGRect(x: 0, y: 0, width: 1.0 / 6.0, height: 1), in: sheet)
        closed.filteringMode = .nearest
        let flyer = SKSpriteNode(texture: closed, size: m.tileSize)
        flyer.position = chestPos
        flyer.zPosition = 5_000   // above everything while airborne
        m.mapNode.addChild(flyer)

        let path = CGMutablePath()
        path.move(to: chestPos)
        let control = CGPoint(x: (chestPos.x + landing.x) / 2,
                              y: max(chestPos.y, landing.y) + 26)
        path.addQuadCurve(to: landing, control: control)
        let fly = SKAction.follow(path, asOffset: false, orientToPath: false, duration: 0.55)
        fly.timingMode = .easeIn
        let spin = SKAction.rotate(byAngle: chestPos.x <= landing.x ? -2 * .pi : 2 * .pi,
                                   duration: 0.55)

        flyer.run(.sequence([
            .group([fly, spin]),
            .run { [weak self] in
                guard let self else { return }
                HapticsManager.shared.mediumImpact()
                self.run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                flyer.zRotation = 0
                // Painter's-algorithm depth like map tiles: sort by tile bottom.
                flyer.zPosition = -(landing.y - m.tileSize.height / 2)
                self.fallenChestNodes["\(Int(landing.x)),\(Int(landing.y))"] = flyer
                // Grounded — A-press now collects it. Axe pickups keep their
                // identity; everything else lands as a normal 50/50 chest.
                if self.highAxKeys.remove("\(Int(chestPos.x)),\(Int(chestPos.y))") != nil {
                    self.axPositions.append(landing)
                } else {
                    self.chestPositions.append(landing)
                }
            },
            // Landing squash-and-settle.
            .scaleY(to: 0.65, duration: 0.07),
            .scaleY(to: 1.0, duration: 0.10),
        ]))
    }

    // MARK: - Axe

    private func collectAxe() {
        guard let pos = nearbyAxPosition else { return }
        // Persist + reveal the HUD button.
        UserDefaults.standard.set(true, forKey: axeEarnedKey)
        btnAxe?.isHidden = false
        // Hide the pickup tile and clear it from the active list. If it was
        // knocked down from a high area, the visual is a fallen sprite instead.
        hideChestTile(at: pos)
        if let fallen = fallenChestNodes.removeValue(forKey: "\(Int(pos.x)),\(Int(pos.y))") {
            fallen.removeFromParent()
        }
        axPositions.removeAll { abs($0.x - pos.x) < 1 && abs($0.y - pos.y) < 1 }
        nearbyAxPosition = nil
        showPickupText("+ AXE", at: pos)
    }

    /// Chops the nearest tree tile (any tree/apple tileset, not just the climbable ones).
    /// Hides every tile in the cluster, drops it from interaction lists, persists the chop,
    /// and grants +1 wood.
    private func chopNearbyTree() {
        // If the player is climbing the tree, descend first so they're not stranded mid-air.
        if player.isInTree { player.descendTree() }

        let chopRadius: CGFloat = 28

        // Placed log walls chop first — no wood refund, because placing a log
        // never consumed any wood (it just deployed a piece of the existing pile).
        // Removing it just frees up that piece for placement again elsewhere.
        if let idx = placedWoodLogs.firstIndex(where: {
            hypot($0.position.x - player.position.x, $0.position.y - player.position.y) < chopRadius
        }) {
            let log = placedWoodLogs.remove(at: idx)
            log.node.removeFromParent()
            updateFortButton()
            return
        }

        // Search every map layer for any tile from a tileset whose name contains "tree" or
        // "apple", and pick the closest one inside the chop radius.
        guard let m = map else { return }
        let treeRanges = m.tilesetRanges
            .filter { $0.name.contains("tree") || $0.name.contains("apple") }
            .map(\.gidRange)

        var bestPos: CGPoint? = nil
        var bestDist = CGFloat.infinity
        for (_, grid) in m.layerGIDs {
            for r in 0..<m.rows {
                for c in 0..<m.cols {
                    let gid = grid[r][c] & 0x0FFF_FFFF
                    guard gid != 0,
                          treeRanges.contains(where: { $0.contains(gid) }) else { continue }
                    let center = m.tileCenter(col: c, row: r)
                    let d = hypot(center.x - player.position.x, center.y - player.position.y)
                    if d < chopRadius && d < bestDist && !isChopped(center) {
                        bestDist = d
                        bestPos = center
                    }
                }
            }
        }

        guard let pos = bestPos else {
            showHintBanner("Stand next to a tree\nto chop it.")
            return
        }

        // Hide every tree tile within the cluster, then drop every tile center that
        // belonged to the cluster from the proximity arrays so the "▲A" prompt never
        // appears over the empty spot. Trees can be tall (canopy 4+ tiles above the
        // trunk), so a radius-based prune isn't enough — we use the exact cluster
        // centers reported by hideTreeTiles.
        let removedCenters = hideTreeTiles(near: pos, in: m)
        let key = "\(Int(pos.x)),\(Int(pos.y))"
        choppedTreeKeys.insert(key)
        saveChoppedTrees()
        let tw = m.tileSize.width
        let th = m.tileSize.height
        let centerEpsilon = max(tw, th) / 2 + 1
        func nearAnyRemoved(_ p: CGPoint) -> Bool {
            for c in removedCenters {
                if abs(p.x - c.x) < centerEpsilon && abs(p.y - c.y) < centerEpsilon { return true }
            }
            return false
        }
        treePositions.removeAll { nearAnyRemoved($0) }
        appleTreePositions.removeAll { nearAnyRemoved($0) }
        nearbyTreePosition = nil
        nearbyAppleTreePosition = nil

        // Reward the player.
        inventory.collect(.wood, count: 3)
        showPickupText("+ 3 WOOD", at: pos)
    }

    /// Toggles build mode. While active, the player drops a log every `buildSpacing`
    /// world units along their path until they tap again or run out of wood.
    private func toggleBuildMode() {
        if isBuilding {
            stopBuilding()
            return
        }
        guard availableWoodForBuilding > 0 else { return }
        isBuilding = true
        setFortButtonActive(true)
        // Seed the trail with one log immediately behind the player so the first
        // tap has visible feedback even before they walk.
        let target = backPositionForPlayer()
        if tryPlaceLog(at: target) {
            lastBuildPosition = target
        } else {
            lastBuildPosition = target
        }
    }

    private func stopBuilding() {
        guard isBuilding else { return }
        isBuilding = false
        setFortButtonActive(false)
    }

    /// Called from `update(_:)`. Lays logs in a continuous line connecting
    /// `lastBuildPosition` to the current point behind the player, stepping in
    /// `buildSpacing`-unit increments so adjacent logs overlap their 14-wide
    /// collision boxes into one solid wall. Stops if wood runs out.
    private func tickBuildMode() {
        guard isBuilding else { return }
        if availableWoodForBuilding <= 0 {
            stopBuilding()
            return
        }
        var cursor = lastBuildPosition
        let target = backPositionForPlayer()
        var dx = target.x - cursor.x
        var dy = target.y - cursor.y
        var dist = hypot(dx, dy)
        // Safety cap so a teleport can't spawn a runaway number of logs in one tick.
        var safety = 64
        while dist >= buildSpacing && safety > 0 {
            safety -= 1
            if availableWoodForBuilding <= 0 { stopBuilding(); break }
            let nx = dx / dist
            let ny = dy / dist
            cursor = CGPoint(x: cursor.x + nx * buildSpacing,
                             y: cursor.y + ny * buildSpacing)
            _ = tryPlaceLog(at: cursor)
            lastBuildPosition = cursor
            dx = target.x - cursor.x
            dy = target.y - cursor.y
            dist = hypot(dx, dy)
        }
    }

    private func backPositionForPlayer() -> CGPoint {
        let facing = player.currentFacingVector
        return CGPoint(x: player.position.x - facing.dx * buildBackOffset,
                       y: player.position.y - facing.dy * buildBackOffset)
    }

    /// Places one log at `target`. Wood is NOT consumed — placement is gated by
    /// `availableWoodForBuilding` (wood pile − logs currently deployed). Returns
    /// false if the spot is blocked by an existing log or tree.
    @discardableResult
    private func tryPlaceLog(at target: CGPoint) -> Bool {
        guard availableWoodForBuilding > 0, let m = map else { return false }
        // Tight log-vs-log threshold so consecutive placements in the trail fit.
        let logMinDist: CGFloat = buildSpacing * 0.85
        for log in placedWoodLogs {
            if hypot(log.position.x - target.x, log.position.y - target.y) < logMinDist {
                return false
            }
        }
        // Keep more clearance from trees so logs don't visually overlap canopies.
        let treeMinDist: CGFloat = 14
        for pos in treePositions + appleTreePositions {
            if hypot(pos.x - target.x, pos.y - target.y) < treeMinDist {
                return false
            }
        }

        let node = makeWoodLogNode()
        node.position = target
        node.zPosition = -target.y
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 14, height: 10))
        body.isDynamic = false
        body.categoryBitMask = PlayerNode.worldBit
        body.collisionBitMask = PlayerNode.categoryBit | PlayerNode.enemyBit
        body.contactTestBitMask = 0
        node.physicsBody = body
        m.mapNode.addChild(node)
        placedWoodLogs.append(PlacedWoodLog(node: node, position: target))
        updateFortButton()
        return true
    }

    /// Highlights the fort button while build mode is engaged.
    private func setFortButtonActive(_ active: Bool) {
        guard let fort = btnFort else { return }
        if active {
            fort.fillColor = SKColor(red: 0.55, green: 0.36, blue: 0.10, alpha: 1.0)
            fort.strokeColor = SKColor(red: 1.00, green: 0.92, blue: 0.45, alpha: 1.0)
            fort.lineWidth = 3.0
        } else {
            fort.fillColor = woodDarkColor
            fort.strokeColor = SKColor(red: 0.85, green: 0.82, blue: 0.40, alpha: 1.0)
            fort.lineWidth = 2.0
        }
    }

    private func makeWoodLogNode() -> SKNode {
        let root = SKNode()
        let body = SKSpriteNode(color: SKColor(red: 0.45, green: 0.28, blue: 0.14, alpha: 1.0),
                                size: CGSize(width: 14, height: 10))
        root.addChild(body)
        let ringColor = SKColor(red: 0.28, green: 0.16, blue: 0.07, alpha: 1.0)
        for x: CGFloat in [-5, 5] {
            let ring = SKSpriteNode(color: ringColor, size: CGSize(width: 2, height: 10))
            ring.position = CGPoint(x: x, y: 0)
            root.addChild(ring)
        }
        let highlight = SKSpriteNode(color: SKColor(red: 0.60, green: 0.40, blue: 0.20, alpha: 1.0),
                                     size: CGSize(width: 14, height: 2))
        highlight.position = CGPoint(x: 0, y: 3)
        root.addChild(highlight)
        return root
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

    // MARK: - Story Mode World Helpers

    /// Spawn a bat pickup node during the story bat-search phase.
    private func spawnStoryBatIfNeeded() {
        guard StoryManager.shared.pendingWorldTrigger == StoryManager.triggerBat,
              !StoryManager.shared.hasFlag(.batFound),
              let m = map else { return }
        let pos = StoryManager.batWorldPosition
        storyBatPosition = pos

        let bat = SKNode()
        // Simple bat shape: dark brown rectangle
        let shaft = SKSpriteNode(color: SKColor(red: 0.45, green: 0.25, blue: 0.10, alpha: 1),
                                 size: CGSize(width: 5, height: 24))
        let barrel = SKSpriteNode(color: SKColor(red: 0.55, green: 0.32, blue: 0.12, alpha: 1),
                                  size: CGSize(width: 10, height: 10))
        barrel.position = CGPoint(x: 0, y: 14)
        bat.addChild(shaft)
        bat.addChild(barrel)
        bat.position = pos
        bat.zPosition = 5000
        bat.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: 0.5),
            .moveBy(x: 0, y: -2, duration: 0.5)
        ])))
        m.mapNode.addChild(bat)
        storyBatNode = bat
    }

    /// Called when player presses A near the story bat pickup.
    private func collectStoryBat() {
        guard !isTransitioning else { return }
        storyBatNode?.removeFromParent()
        storyBatNode = nil
        storyBatPosition = nil
        nearbyStoryBatPosition = nil
        StoryManager.shared.pendingWorldTrigger = nil
        showPickupText("+ BAT!", at: player.position)
        run(.wait(forDuration: 0.4)) { [weak self] in
            self?.launchStoryAtCurrentModule()
        }
    }

    /// Transitions from the world map into the story module at currentModuleID.
    private func launchStoryAtCurrentModule() {
        guard let view = self.view, !isTransitioning else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero

        let ppSize = pixelPerfectSize() ?? size
        let storyScene = StoryModuleScene(size: ppSize)
        storyScene.scaleMode = .resizeFill
        storyScene.startAtCurrentProgress()

        let t = SKTransition.fade(withDuration: 0.55)
        t.pausesOutgoingScene = false
        view.presentScene(storyScene, transition: t)
    }

    private func pixelPerfectSize() -> CGSize? {
        guard let v = self.view else { return nil }
        let scale  = v.contentScaleFactor
        let pixelW = v.bounds.width  * scale
        let pixelH = v.bounds.height * scale
        let n = max(2, min(floor(pixelW / 160), floor(pixelH / 120)))
        return CGSize(width: floor(pixelW / n), height: floor(pixelH / n))
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

    /// Stash a "return here on exit" point just south of the triggering tile so the player
    /// ends up next to the challenge after the mini-game ends. Applied in `didMove(to:)`.
    private func setMiniGameReturnPosition(near tile: CGPoint) {
        let offset: CGFloat = 24
        var p = CGPoint(x: tile.x, y: tile.y - offset)
        if let m = map {
            let half: CGFloat = 6
            p.x = max(half, min(m.sizeInPoints.width  - half, p.x))
            p.y = max(half, min(m.sizeInPoints.height - half, p.y))
        }
        pendingReturnPosition = p
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
        mini.awardsRewards          = true   // world / story context grants prizes
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
            if let earned = mini?.goldenBagsEarned, earned > 0 { self?.inventory.collect(.goldenBag, count: earned) }
            if let earned = mini?.coinsEarned,     earned > 0 { self?.inventory.collect(.coin,     count: earned) }
            if CornholeStatsManager.shared.baseballUnlocked { self?.unlockBaseball() }
            self?.isTransitioning = false
        }

        SceneTransition.iris(in: view, to: mini)
    }

    private func openCornholeBaseball() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let stats = CornholeStatsManager.shared
        let baseball = CornholeBaseballScene(size: self.size)
        baseball.scaleMode     = self.scaleMode
        baseball.previousScene = self
        baseball.awardsRewards = true

        // Sequence: face Jen (powerHitter) first, then Tom (greatFielder).
        // Once both are beaten the joust gate opens.
        if !stats.defeatedJenBaseball {
            baseball.aiDifficulty = .powerHitter
            baseball.onComplete = { [weak self] won in
                if won { stats.defeatedJenBaseball = true }
                self?.isTransitioning = false
            }
        } else if !stats.defeatedTomBaseball {
            baseball.aiDifficulty = .greatFielder
            baseball.onComplete = { [weak self] won in
                if won {
                    stats.defeatedTomBaseball = true
                    self?.showHintBanner("You beat Jen & Tom\nat baseball.\nThe joust awaits!")
                }
                self?.isTransitioning = false
            }
        } else {
            baseball.onComplete = { [weak self] _ in self?.isTransitioning = false }
        }

        SceneTransition.iris(in: view, to: baseball)
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
        bee.awardsRewards  = true
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

        SceneTransition.iris(in: view, to: bee)
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
        beach.awardsRewards = true
        beach.onComplete = { [weak self] won in
            guard let self else { return }
            self.isTransitioning = false
            if won {
                // 8 floating bags every win — usable as bonus bags in Piranha Bridge.
                self.inventory.collect(.floatingBag, count: 8)
                if !UserDefaults.standard.bool(forKey: self.beachBallBeatenKey) {
                    UserDefaults.standard.set(true, forKey: self.beachBallBeatenKey)
                    self.showHintBanner("You won 8 floating\nbean bags. Use them on\nthe piranha bridge!")
                }
            }
        }

        SceneTransition.iris(in: view, to: beach)
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
        piranha.awardsRewards = true
        piranha.availableFloatingBags = inventory.counts[.floatingBag, default: 0]
        piranha.onComplete = { [weak self, weak piranha] won in
            guard let self else { return }
            if let used = piranha?.floatingBagsUsed, used > 0 {
                self.inventory.consume(.floatingBag, count: used)
            }
            self.isTransitioning = false
            if won { self.unlockBridge() }
        }

        SceneTransition.iris(in: view, to: piranha)
    }

    private func openSuburbanJousters() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        if HeartsManager.shared.currentHearts <= 0 { HeartsManager.shared.refill() }
        let joust = SuburbanJoustersScene(size: self.size)
        joust.scaleMode     = self.scaleMode
        joust.previousScene = self
        joust.awardsRewards = true
        joust.startingHearts = HeartsManager.shared.currentHearts
        joust.onComplete = { [weak self, weak joust] won in
            guard let self, let joust else { return }
            HeartsManager.shared.set(joust.remainingHearts)
            if won && !UserDefaults.standard.bool(forKey: self.goldenLanceKey) {
                UserDefaults.standard.set(true, forKey: self.goldenLanceKey)
                self.lanceIndicator?.isHidden = false
                self.inventory.collect(.goldenLance, count: 1)
                self.showHintBanner("You won the\nGolden Lance!")
            }
            self.isTransitioning = false
        }

        SceneTransition.iris(in: view, to: joust)
    }

    private func openWellFlinger() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let well = WellFlingerScene(size: self.size)
        well.scaleMode     = self.scaleMode
        well.previousScene = self
        well.awardsRewards = true
        well.availableBags = inventory.counts[.bag, default: 0]
        well.availableFireBags = inventory.counts[.fireBag, default: 0]
        well.onComplete = { [weak self, weak well] _ in
            guard let self else { return }
            if let used = well?.bagsUsed, used > 0 {
                let have = self.inventory.counts[.bag, default: 0]
                self.inventory.consume(.bag, count: min(used, have))
            }
            if let used = well?.fireBagsUsed, used > 0 {
                let have = self.inventory.counts[.fireBag, default: 0]
                self.inventory.consume(.fireBag, count: min(used, have))
            }
            if let earned = well?.fireBagsEarned, earned > 0 {
                self.inventory.collect(.fireBag, count: earned)
            }
            if let earned = well?.goldenBagsEarned, earned > 0 {
                self.inventory.collect(.goldenBag, count: earned)
            }
            self.isTransitioning = false
        }

        SceneTransition.iris(in: view, to: well)
    }

    private func unlockBridge() {
        UserDefaults.standard.set(true, forKey: bridgeUnlockedKey)
        map?.layerNodes["ImaginationFX"]?.isHidden = false
        bridgePhysicsNodes.forEach { $0.removeFromParent() }
        bridgePhysicsNodes.removeAll()
    }

    private func unlockBaseball() {
        map?.layerNodes["Baseball"]?.isHidden = false
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
        let fences = m.layerGIDs["fences"]
        let ground = m.layerGIDs["Ground"]
        let interactions = m.layerGIDs["Interactions"]
        // Mountain (high-area) cells are always walled off — the Golden Lance
        // lets the player knock chests down from them, never stand on them.
        let mountainGrids: [[[Int]]] = m.layerGIDs
            .filter { $0.key.lowercased().contains("mountain") }
            .map { $0.value }

        func isWater(_ gid: Int) -> Bool {
            // water1: 22..45, water2: 257..280, water3: 281..304 (see World1.tmx).
            (22...45).contains(gid) || (257...304).contains(gid)
        }

        func isMountain(_ r: Int, _ c: Int) -> Bool {
            for g in mountainGrids where (g[r][c] & 0x0FFF_FFFF) != 0 { return true }
            return false
        }

        for r in 0..<m.rows {
            for c in 0..<m.cols {
                let blocked = (collisions?[r][c] ?? 0) != 0
                                    || (fences?[r][c] ?? 0) != 0
                                    || isMountain(r, c)
                let waterHere = isWater(ground?[r][c] ?? 0)
                // A bridge (any tile on the Interactions layer at this cell)
                // overrides the water block so the player can cross it.
                let bridgeHere = (interactions?[r][c] ?? 0) != 0
                guard blocked || (waterHere && !bridgeHere) else { continue }

                let blocker = SKNode()
                blocker.position = m.tileCenter(col: c, row: r)
                // Body matches the painted tile exactly — alignment depends on
                // the Collisions layer being painted correctly in Tiled.
                let body = SKPhysicsBody(rectangleOf: m.tileSize)
                body.isDynamic = false
                body.categoryBitMask = PlayerNode.worldBit
                body.collisionBitMask = PlayerNode.categoryBit | PlayerNode.enemyBit
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

        // Store modal — when open, route all input to it.
        if let modal = storeModal {
            modal.handleTap(at: touch.location(in: modal))
            return
        }

        // Pause overlay routing
        if isPausedGame {
            // Map overlay sits on top of the pause panel — any tap closes it.
            if mapOverlayNode != nil { hideMapOverlay(); return }
            for n in nodes(at: touch.location(in: self)) {
                let name = n.name ?? n.parent?.name ?? ""
                if name == "resumeBtn" { resumeGame(); return }
                if name == "mapBtn" { showMapOverlay(); return }
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
        if let axe = btnAxe, !axe.isHidden, distanceSquared(pInCam, axe.position) < btnHit {
            chopNearbyTree()
            return
        }
        if let fort = btnFort, !fort.isHidden, distanceSquared(pInCam, fort.position) < btnHit {
            toggleBuildMode()
            return
        }
        if let biscuit = btnBiscuit, !biscuit.isHidden, distanceSquared(pInCam, biscuit.position) < btnHit {
            placeDogBiscuit()
            return
        }
        if let a = btnA, distanceSquared(pInCam, a.position) < btnHit {
            let trigger = StoryManager.shared.pendingWorldTrigger

            if nearbyStoryBatPosition != nil {
                collectStoryBat()
            } else if nearbyAxPosition != nil {
                collectAxe()
            } else if let p = nearbyBoardPosition {
                if trigger == StoryManager.triggerCornhole {
                    StoryManager.shared.pendingWorldTrigger = nil
                    launchStoryAtCurrentModule()
                } else {
                    setMiniGameReturnPosition(near: p)
                    openCornholeMiniGame()
                }
            } else if nearbyChestPosition != nil {
                openChest()
            } else if nearbyStorePosition != nil {
                openStore()
            } else if let p = nearbyBridgeStonePosition {
                setMiniGameReturnPosition(near: p)
                openBeachBallCornhole()
            } else if let p = nearbyAppleTreePosition {
                setMiniGameReturnPosition(near: p)
                openCornholeMiniGame(preSelectedOpponent: .spirit)
            } else if let p = nearbyBaseballPosition {
                if trigger == StoryManager.triggerBaseball || trigger == StoryManager.triggerQuestOffer {
                    StoryManager.shared.pendingWorldTrigger = nil
                    launchStoryAtCurrentModule()
                } else {
                    setMiniGameReturnPosition(near: p)
                    openCornholeBaseball()
                }
            } else if let p = nearbyBeehivePosition {
                setMiniGameReturnPosition(near: p)
                openBeeHiveMiniGame()
            } else if let p = nearbyPoolPosition {
                setMiniGameReturnPosition(near: p)
                openBeachBallCornhole()
            } else if let p = nearbyBridgeWoodPosition {
                if trigger == StoryManager.triggerBridge {
                    StoryManager.shared.pendingWorldTrigger = nil
                    launchStoryAtCurrentModule()
                } else if UserDefaults.standard.bool(forKey: beachBallBeatenKey) {
                    setMiniGameReturnPosition(near: p)
                    openBridgePiranha()
                } else {
                    showHintBanner("You need bean bags\nthat can float\nbefore coming here.")
                }
            } else if let p = nearbyFencePosition {
                if CornholeStatsManager.shared.joustersUnlocked {
                    setMiniGameReturnPosition(near: p)
                    openSuburbanJousters()
                } else if CornholeStatsManager.shared.defeatedJenBaseball {
                    showHintBanner("Beat Tom at baseball\nto unlock the joust.")
                } else {
                    showHintBanner("In order to joust\non your bike, you need\nsomething to use\nas a lance.")
                }
            } else if let p = nearbyWellPosition {
                if inventory.counts[.bag, default: 0] > 0 {
                    setMiniGameReturnPosition(near: p)
                    openWellFlinger()
                } else {
                    showHintBanner("You need bean bags\nto throw down\nthe well.")
                }
            } else if nearbyHighChestPosition != nil {
                knockChestOffHighArea()
            } else if nearbyTreePosition != nil {
                if player.isInTree { player.descendTree() } else { player.climbTree() }
            }
            return
        }
        if let b = btnB, !b.isHidden, distanceSquared(pInCam, b.position) < btnHit {
            throwBeanbag()
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
        lastFacingVector = newDirection
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

    // One-time "what this does" hints, shown the first time a special item
    // type is ever collected (HIG: the pickup is the canonical hint moment).
    // Seen types persist across launches.
    private static let itemHintsSeenKey = "itemUseHintsSeen_v1"

    /// Keep every line ≤ 20 chars — PressStart2P glyphs are square, so the
    /// hint panel fits ~21 chars per line before the font has to shrink.
    private func itemUseHint(for type: ItemType) -> String? {
        switch type {
        case .bombBag:    return "BOMB BAG: blows up\nrival bags on board!"
        case .magicBag:   return "MAGIC BAG: zaps\nrival bags it hits!"
        case .fireBag:    return "FIRE BAG: burns all\nother bags in play!"
        case .honeyBag:   return "HONEY BAG: sticks!\nNo wind, no knocks."
        case .goldenBag:  return "GOLDEN BAG: 2 pts\non board, 6 in hole!"
        case .dogBiscuit: return "DOG BISCUIT: tap its\nslot to lure dogs!"
        // floatingBag and goldenLance already get bespoke award banners.
        default:          return nil
        }
    }

    private func maybeShowItemUseHint(for type: ItemType) {
        guard let copy = itemUseHint(for: type) else { return }
        var seen = Set(UserDefaults.standard.stringArray(forKey: GameScene.itemHintsSeenKey) ?? [])
        guard seen.insert(type.rawValue).inserted else { return }
        UserDefaults.standard.set(Array(seen), forKey: GameScene.itemHintsSeenKey)
        showHintBanner(copy)
    }

    /// Shows a transient tutorial hint in the stage area, auto-dismissed after 4 s.
    /// Lines are separated by "\n". If a hint is already up, the new one waits
    /// its turn instead of stacking on top.
    private func showHintBanner(_ message: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let panelW = size.width * 0.76
        // PressStart2P glyph advance ≈ fontSize, so shrink the font to fit the
        // longest line inside the panel rather than letting the label overflow.
        let maxLen = max(1, lines.map(\.count).max() ?? 1)
        let fs: CGFloat = max(5, min(size.width * 0.036, (panelW - 16) / CGFloat(maxLen)))
        let lineH: CGFloat = fs + 7
        let panelH = CGFloat(lines.count) * lineH + 18

        let queuedAhead = cameraNode.children.filter { $0.name == "hintBanner" }.count
        let banner = SKNode()
        banner.name = "hintBanner"
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

        banner.run(.sequence([
            .wait(forDuration: Double(queuedAhead) * 4.9),
            .run { HapticsManager.shared.lightImpact() },
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
            updateBullies(dt: dt)
            updateProjectiles(dt: dt)
            updateDamage(dt: dt)
            updateCamera()
            trackVisitedCell()
            checkBoardProximity()
            tickBuildMode()
        }
    }

    private func ySortStaticLayers(in m: TMXMap) {
        // Tile-row-aware z-sort.
        //
        // Plain feet-sort works for short tiles but breaks for tall multi-tile
        // objects (trees, houses): when the player walks under a tree, the
        // canopy 4 rows above the trunk sorts by its OWN bottom (way above the
        // player's feet) and the player's head pokes through. Fix: every tile
        // from a "tall object" tileset sorts as if it were the bottom row of
        // its tileset (the trunk base). That way the canopy and trunk share
        // one anchor and the whole tree renders as a single layer relative to
        // the player.
        //
        // We detect "tall objects" by tileset name (tree/house/shed). Add more
        // keywords here as new multi-tile decorations are imported.
        //
        // We process ALL layers except the ones that carry fixed special
        // z-positions (Ground stays pinned at -10_000; Spawns, ImaginationFX,
        // and Baseball are hidden/overlay layers that must not be y-sorted).
        // This ensures every tree — climbable oaks, apple trees, and any future
        // decorative tree layer — gets the trunk-anchor sort.
        let tallKeywords = ["tree", "house", "shed"]
        let tileH = m.tileSize.height
        let skipLayers: Set<String> = ["Ground", "Spawns", "ImaginationFX", "Baseball"]

        for (name, layer) in m.layerNodes {
            guard !skipLayers.contains(name) else { continue }
            for sprite in layer.children {
                guard let s = sprite as? SKSpriteNode else { continue }
                let halfH = s.size.height / 2
                var sortY = s.position.y - halfH   // default: tile bottom

                // If this tile is part of a tall multi-row object, shift the
                // sort y down to the bottom row of its tileset.
                if let gid = s.userData?["gid"] as? Int,
                   let ts = m.tilesetRanges.first(where: { $0.gidRange.contains(gid) }),
                   tallKeywords.contains(where: { ts.name.contains($0) }),
                   ts.columns > 0, ts.rows > 1 {
                    let localID = gid - ts.gidRange.lowerBound
                    let rowInTileset = localID / ts.columns
                    let rowsBelow = (ts.rows - 1) - rowInTileset
                    sortY -= CGFloat(rowsBelow) * tileH
                }
                s.zPosition = -sortY
            }
        }
    }

    // MARK: - Store Modal

    private func openStore() {
        guard storeModal == nil, !isTransitioning else { return }
        player.moveDirection = .zero
        resetBeanbagControl()

        let callbacks = StoreModalNode.Callbacks(
            coinBalance:  { [weak self] in self?.inventory.counts[.coin, default: 0] ?? 0 },
            buyBeanbags:  { [weak self] in self?.purchaseBeanbags() ?? false },
            buyPowerJuice:{ [weak self] in self?.purchasePowerJuice() ?? false },
            buyGauntlet:  { [weak self] in self?.purchaseGauntlet() ?? false },
            close:        { [weak self] in self?.closeStore() },
            gauntletOwned:{ StoreManager.gauntletOwned }
        )
        let modal = StoreModalNode(sceneSize: size, callbacks: callbacks)
        cameraNode.addChild(modal)
        storeModal = modal
    }

    private func closeStore() {
        storeModal?.removeFromParent()
        storeModal = nil
    }

    private func purchaseBeanbags() -> Bool {
        let coins = inventory.counts[.coin, default: 0]
        guard coins >= 10 else { return false }
        inventory.consume(.coin, count: 10)
        inventory.collect(.bag, count: 5)
        return true
    }

    private func purchasePowerJuice() -> Bool {
        let coins = inventory.counts[.coin, default: 0]
        guard coins >= 10 else { return false }
        inventory.consume(.coin, count: 10)
        HeartsManager.shared.refill()
        return true
    }

    private func purchaseGauntlet() -> Bool {
        guard !StoreManager.gauntletOwned else { return false }
        let coins = inventory.counts[.coin, default: 0]
        guard coins >= 30 else { return false }
        inventory.consume(.coin, count: 30)
        StoreManager.gauntletOwned = true
        return true
    }

    // MARK: - World Beanbag Throw

    private func throwBeanbag() {
        guard !isTransitioning, !isGameOver else { return }
        guard inventory.counts[.bag, default: 0] > 0, let m = map else { return }
        inventory.consume(.bag, count: 1)

        // Prefer the directional joystick's last heading; fall back to the
        // player's sprite facing so a stationary throw still works.
        let dir: CGVector
        if lastFacingVector.dx != 0 || lastFacingVector.dy != 0 {
            dir = lastFacingVector
        } else {
            dir = player.currentFacingVector
        }
        let mag = max(hypot(dir.dx, dir.dy), 0.001)
        let unit = CGVector(dx: dir.dx / mag, dy: dir.dy / mag)
        let velocity = CGVector(dx: unit.dx * projectileSpeed,
                                 dy: unit.dy * projectileSpeed)

        let lifetime = TimeInterval(projectileRange / projectileSpeed)
        let bag = BeanbagProjectile(velocity: velocity, lifetime: lifetime)
        // Spawn just in front of the player so it doesn't self-collide with the
        // thrower's own contact body.
        bag.position = CGPoint(x: player.position.x + unit.dx * 14,
                                y: player.position.y + unit.dy * 14)
        bag.zPosition = 5_500
        m.mapNode.addChild(bag)
        projectiles.append(bag)
        HapticsManager.shared.lightImpact()
    }

    private func updateProjectiles(dt: TimeInterval) {
        guard !projectiles.isEmpty else { return }
        for bag in projectiles where !bag.isDead {
            // Landed bags stay put on the ground until they fade out — no more
            // collision checks or motion.
            if bag.hasLanded { continue }

            bag.position.x += bag.velocity.dx * CGFloat(dt)
            bag.position.y += bag.velocity.dy * CGFloat(dt)
            bag.lifeRemaining -= dt

            // Hit a dog? Any dog within radius starts fleeing and the bag pops.
            var consumed = false
            for dog in dogs where !dog.isFleeing {
                let d = hypot(dog.position.x - bag.position.x,
                              dog.position.y - bag.position.y)
                if d < projectileHitRadius {
                    dog.startFleeing(awayFrom: bag.position)
                    dogsTouchingPlayer.remove(ObjectIdentifier(dog))
                    bag.pop()
                    consumed = true
                    break
                }
            }
            if consumed { continue }

            // Hit a bully? First hit stuns, second hit makes them flee.
            for bully in bullies where !bully.isFleeingFromBag && !bully.isEngaged {
                let d = hypot(bully.position.x - bag.position.x,
                              bully.position.y - bag.position.y)
                if d < projectileHitRadius + 6 {
                    bully.takeBagHit(from: bag.position)
                    bag.pop()
                    consumed = true
                    break
                }
            }
            if consumed { continue }

            if bag.lifeRemaining <= 0 { bag.land() }
        }
        projectiles.removeAll { $0.parent == nil }
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

        let playerInvolved = (nodeA === player) || (nodeB === player)

        if let bully = (nodeA as? BullyNode) ?? (nodeB as? BullyNode),
           playerInvolved, !bully.isEngaged, !isTransitioning, !isGameOver,
           storeModal == nil, bullyCooldownRemaining <= 0 {
            engageBully(bully)
            return
        }

        let dog = (nodeA as? DogNode) ?? (nodeB as? DogNode)
        if let dog, playerInvolved {
            dogsTouchingPlayer.insert(ObjectIdentifier(dog))
            // First contact deals damage immediately (subject to cooldown);
            // continued overlap is handled by updateDamage() ticking.
            if damageCooldown == 0, storeModal == nil,
               let p = player, !p.isInTree, !isGameOver {
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
        // Freeze enemies while the store is open — the player is "inside".
        if storeModal != nil {
            for dog in dogs { dog.physicsBody?.velocity = .zero }
            return
        }
        dogSpawnTimer += dt
        if dogSpawnTimer >= nextDogSpawnInterval && dogs.count < maxDogs
            && StoryManager.shared.hasFlag(.dogsEnabled) {
            dogSpawnTimer = 0
            nextDogSpawnInterval = TimeInterval.random(in: 14...24)
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
        guard let pos = randomEdgeSpawn() else { return }

        let dog = DogNode()
        dog.position = pos
        dogs.append(dog)
        m.mapNode.addChild(dog)

        if !hasShownDogTutorial {
            hasShownDogTutorial = true
            showHintBanner("Dodge the dogs!\nClimb a tree\nfor safety \u{25B2}A")
        }
    }

    /// True if a world-space point is on a tile the player (and therefore an
    /// enemy) is allowed to occupy — i.e. not a Collisions-layer block and not
    /// open water. Mirrors the rules in `buildPhysics(from:)`.
    private func isWalkable(_ worldPos: CGPoint) -> Bool {
        guard let m = map else { return true }
        let tw = m.tileSize.width
        let th = m.tileSize.height
        let col = Int(floor(worldPos.x / tw))
        let row = m.rows - 1 - Int(floor(worldPos.y / th))
        guard col >= 0, col < m.cols, row >= 0, row < m.rows else { return false }

        // Mountain (high-area) cells are never walkable, lance or no lance.
        for (name, grid) in m.layerGIDs where name.lowercased().contains("mountain") {
            if (grid[row][col] & 0x0FFF_FFFF) != 0 { return false }
        }
        if let collisions = m.layerGIDs["Collisions"], collisions[row][col] != 0 {
            return false
        }
        if let fences = m.layerGIDs["fences"], fences[row][col] != 0 {
            return false
        }
        let groundGid = (m.layerGIDs["Ground"]?[row][col] ?? 0) & 0x0FFF_FFFF
        let isWater = (22...45).contains(groundGid) || (257...304).contains(groundGid)
        // A bridge (any tile on Interactions) overrides water — match buildPhysics.
        let hasBridge = (m.layerGIDs["Interactions"]?[row][col] ?? 0) != 0
        if isWater && !hasBridge { return false }
        return true
    }

    /// Pick a spawn position around the player's current screen that lands on a
    /// walkable tile. Returns nil if all attempts hit obstacles — the caller
    /// should just skip the spawn that frame and try again next interval.
    private func randomEdgeSpawn(maxAttempts: Int = 10) -> CGPoint? {
        let stage   = stageWorldSize
        let centerX = cameraNode.position.x
        let centerY = cameraNode.position.y + stageCenterYWorld
        let half = stage / 2
        let pad: CGFloat = 24
        for _ in 0..<maxAttempts {
            let edge = Int.random(in: 0...3)
            let pos: CGPoint
            switch edge {
            case 0: pos = CGPoint(x: .random(in: centerX - half ... centerX + half), y: centerY + half + pad)
            case 1: pos = CGPoint(x: .random(in: centerX - half ... centerX + half), y: centerY - half - pad)
            case 2: pos = CGPoint(x: centerX - half - pad, y: .random(in: centerY - half ... centerY + half))
            default: pos = CGPoint(x: centerX + half + pad, y: .random(in: centerY - half ... centerY + half))
            }
            if isWalkable(pos) { return pos }
        }
        return nil
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

    // MARK: - Roaming Bullies

    private func updateBullies(dt: TimeInterval) {
        if storeModal != nil {
            for bully in bullies { bully.physicsBody?.velocity = .zero }
            return
        }
        // Post-victory peace window — no new bullies, no engagements.
        if bullyCooldownRemaining > 0 {
            bullyCooldownRemaining -= dt
        }
        bullySpawnTimer += dt
        if bullyCooldownRemaining <= 0
           && bullySpawnTimer >= nextBullySpawnInterval && bullies.count < maxBullies {
            // TODO: re-enable story gate — `StoryManager.shared.hasFlag(.bulliesEnabled)` —
            // once bully testing is done. Currently always-on for testing.
            bullySpawnTimer = 0
            nextBullySpawnInterval = TimeInterval.random(in: 18...30)
            spawnBully()
        }

        for bully in bullies {
            bully.update(dt: dt,
                         playerPosition: player.position,
                         playerInTree: player.isInTree)
        }
        bullies = bullies.filter { bully in
            if isBullyOffScreen(bully) {
                bully.removeFromParent()
                return false
            }
            return true
        }
    }

    private func spawnBully() {
        guard let m = map else { return }
        let stage   = stageWorldSize
        let centerY = cameraNode.position.y + stageCenterYWorld
        let half    = stage / 2

        let pos: CGPoint
        if bullies.isEmpty {
            // First bully: try in front of the player, walking outward if the
            // ideal spot lands on a wall.
            let candidates: [CGPoint] = [
                CGPoint(x: player.position.x,
                         y: min(centerY + half - 24, max(centerY - half + 24, player.position.y + 80))),
                CGPoint(x: player.position.x + 60, y: player.position.y),
                CGPoint(x: player.position.x - 60, y: player.position.y),
                CGPoint(x: player.position.x, y: player.position.y - 60),
            ]
            if let walkable = candidates.first(where: { isWalkable($0) }) {
                pos = walkable
            } else if let edge = randomEdgeSpawn() {
                pos = edge
            } else {
                return
            }
        } else {
            guard let edge = randomEdgeSpawn() else { return }
            pos = edge
        }

        let bully = BullyNode()
        bully.position = pos
        bullies.append(bully)
        m.mapNode.addChild(bully)
    }

    private func isBullyOffScreen(_ bully: BullyNode) -> Bool {
        let stage   = stageWorldSize
        let centerX = cameraNode.position.x
        let centerY = cameraNode.position.y + stageCenterYWorld
        let margin: CGFloat = 80
        return bully.position.x < centerX - stage/2 - margin
            || bully.position.x > centerX + stage/2 + margin
            || bully.position.y < centerY - stage/2 - margin
            || bully.position.y > centerY + stage/2 + margin
    }

    private func clearBullies() {
        bullies.forEach { $0.removeFromParent() }
        bullies.removeAll()
    }

    /// Player ran into a roaming bully — freeze it, despawn, and launch a
    /// 7-point cornhole match. Win → +10 coins; loss → −1 heart.
    private func engageBully(_ bully: BullyNode) {
        bully.isEngaged = true
        bully.physicsBody?.velocity = .zero
        bully.removeFromParent()
        bullies.removeAll { $0 === bully }

        openBullyCornholeMatch()
    }

    private func openBullyCornholeMatch() {
        guard let view = self.view else { return }
        isTransitioning = true
        player.moveDirection = .zero
        player.physicsBody?.velocity = .zero
        resetBeanbagControl()

        let mini = CornholeMiniGameScene(size: self.size)
        mini.scaleMode              = self.scaleMode
        mini.previousScene          = self
        mini.preSelectedOpponent    = .bully
        mini.availableHoneyBags  = inventory.counts[.honeyBag,  default: 0]
        mini.availableBombBags   = inventory.counts[.bombBag,   default: 0]
        mini.availableMagicBags  = inventory.counts[.magicBag,  default: 0]
        mini.availableFireBags   = inventory.counts[.fireBag,   default: 0]
        mini.availableGoldenBags = inventory.counts[.goldenBag, default: 0]
        mini.onComplete = { [weak self, weak mini] playerWon in
            guard let self else { return }
            if let used = mini?.honeyBagsUsed,  used > 0 { self.inventory.consume(.honeyBag,  count: used) }
            if let used = mini?.bombBagsUsed,   used > 0 { self.inventory.consume(.bombBag,   count: used) }
            if let used = mini?.magicBagsUsed,  used > 0 { self.inventory.consume(.magicBag,  count: used) }
            if let used = mini?.fireBagsUsed,   used > 0 { self.inventory.consume(.fireBag,   count: used) }
            if let used = mini?.goldenBagsUsed, used > 0 { self.inventory.consume(.goldenBag, count: used) }

            if playerWon {
                self.inventory.collect(.coin, count: 10)
                self.showHintBanner("+10 COINS")
                // Beat one bully → 90-second peace before another can attack.
                self.bullyCooldownRemaining = self.bullyCooldownDuration
                self.bullySpawnTimer = 0
                self.clearBullies()
            } else {
                if self.playerHearts > 0 {
                    self.playerHearts -= 1
                    HeartsManager.shared.lose()
                    self.updateHeartsDisplay()
                    if self.playerHearts <= 0 { self.triggerGameOver() }
                }
            }
            self.isTransitioning = false
        }

        SceneTransition.iris(in: view, to: mini)
    }

    /// Called from update() each frame: ticks the damage cooldown and, if a dog
    /// is still latched onto the player, deals another bite.
    private func updateDamage(dt: TimeInterval) {
        damageCooldown = max(0, damageCooldown - dt)
        guard !isGameOver,
              storeModal == nil,
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
                    lost?.fontColor = self.dsIronGray
                },
            ]),
        ]), withKey: "heartLost")
    }

    /// Instantly redraws all heart slots to match HeartsManager — used when returning
    /// from the bike race or any other modal that may have changed the count off-screen.
    private func resyncHeartsDisplay() {
        playerHearts = HeartsManager.shared.currentHearts
        for (i, label) in heartLabels.enumerated() {
            label.removeAllActions()
            label.setScale(1.0)
            label.alpha = 1.0
            if i < playerHearts {
                label.text = "♥"; label.fontColor = dsHeartRed
            } else {
                label.text = "♡"; label.fontColor = dsIronGray
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
        hideMapOverlay()
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

        let panelW: CGFloat = min(W - 48, 280), panelH: CGFloat = 214
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH), cornerRadius: 10)
        panel.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        panel.lineWidth   = 2; ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "PAUSED"; title.fontSize = 16
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 70); ov.addChild(title)

        let btnW = panelW - 40, btnH: CGFloat = 44
        for (text, name, y) in [("RESUME", "resumeBtn", CGFloat(18)), ("MAP", "mapBtn", CGFloat(-36))] {
            let bg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2, width: btnW, height: btnH), cornerRadius: 8)
            bg.fillColor   = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.20)
            bg.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
            bg.lineWidth   = 1.5; bg.position = CGPoint(x: 0, y: y)
            bg.name = name; ov.addChild(bg)

            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text = text; lbl.fontSize = 11
            lbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
            lbl.horizontalAlignmentMode = .center; lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: 0, y: -1); lbl.name = name; bg.addChild(lbl)
        }
    }

    // MARK: - Pause Map
    //
    // The world is divided into a virtual grid of screen-sized cells
    // (stageWorldSize per side). Cells the player has walked through are
    // remembered in UserDefaults and drawn filled on the map; unvisited cells
    // stay dark. Mini-game triggers and the store only show pins once their
    // cell has been explored, so the map doubles as a discovery log.

    private func cellKey(for p: CGPoint) -> String {
        let s = stageWorldSize
        return "\(Int(floor(p.x / s))),\(Int(floor(p.y / s)))"
    }

    private func trackVisitedCell() {
        guard map != nil, let p = player else { return }
        if visitedCells.insert(cellKey(for: p.position)).inserted {
            UserDefaults.standard.set(Array(visitedCells), forKey: GameScene.visitedCellsKey)
        }
    }

    /// Collapse runs of adjacent trigger tiles (2×2 boards, fence lines) into
    /// one pin per coarse-grid bucket so the map doesn't smear.
    private func clusteredPins(_ positions: [CGPoint], bucket: CGFloat = 64) -> [CGPoint] {
        var seen = Set<String>(), out: [CGPoint] = []
        for p in positions {
            let k = "\(Int(floor(p.x / bucket))),\(Int(floor(p.y / bucket)))"
            if seen.insert(k).inserted { out.append(p) }
        }
        return out
    }

    private func showMapOverlay() {
        guard mapOverlayNode == nil, let m = map else { return }
        let W = size.width, H = size.height

        let ov = SKNode(); ov.zPosition = 16_000
        mapOverlayNode = ov
        cameraNode.addChild(ov)

        let dim = SKShapeNode(rect: CGRect(x: -W / 2, y: -H / 2, width: W, height: H))
        dim.fillColor = SKColor(white: 0, alpha: 0.88); dim.strokeColor = .clear
        ov.addChild(dim)

        // Grid geometry — one cell per navigable screen.
        let cellWorld = stageWorldSize
        let cols = max(1, Int(ceil(m.sizeInPoints.width  / cellWorld)))
        let rows = max(1, Int(ceil(m.sizeInPoints.height / cellWorld)))
        let cell = min((W - 72) / CGFloat(cols), (H - 220) / CGFloat(rows))
        let gridW = cell * CGFloat(cols), gridH = cell * CGFloat(rows)
        let scale = cell / cellWorld   // world units → map points

        let pad: CGFloat = 14, titleBand: CGFloat = 34, legendBand: CGFloat = 30
        let panelW = gridW + pad * 2
        let panelH = gridH + pad * 2 + titleBand + legendBand
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH), cornerRadius: 10)
        panel.fillColor   = dsPrimary
        panel.strokeColor = dsGold.withAlphaComponent(0.80)
        panel.lineWidth   = 2
        ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "WORLD MAP"; title.fontSize = 13
        title.fontColor = dsGold
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelH / 2 - titleBand / 2 - 6)
        ov.addChild(title)

        let gridOrigin = CGPoint(x: -gridW / 2, y: -panelH / 2 + pad + legendBand)
        let gridNode = SKNode(); ov.addChild(gridNode)
        func mapPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: gridOrigin.x + p.x * scale, y: gridOrigin.y + p.y * scale)
        }

        for r in 0..<rows {
            for c in 0..<cols {
                let rect = CGRect(x: gridOrigin.x + CGFloat(c) * cell,
                                  y: gridOrigin.y + CGFloat(r) * cell,
                                  width: cell, height: cell).insetBy(dx: 1, dy: 1)
                let tile = SKShapeNode(rect: rect)
                tile.fillColor = visitedCells.contains("\(c),\(r)")
                    ? woodColor.withAlphaComponent(0.85)
                    : SKColor(white: 0.06, alpha: 1)
                tile.strokeColor = SKColor(white: 0.22, alpha: 0.60)
                tile.lineWidth = 1
                gridNode.addChild(tile)
            }
        }

        // Pins — only in explored cells.
        let pinSide = max(3, cell * 0.16)
        let shopBlue = SKColor(red: 0.353, green: 0.612, blue: 0.831, alpha: 1.0) // #5a9cd4
        let gameTriggers = clusteredPins(
            cornholeBoardPositions + baseballPositions + appleTreePositions +
            beehivePositions + poolPositions + bridgeStonePositions +
            bridgeWoodPositions + wellPositions + fencePositions)
        for p in gameTriggers where visitedCells.contains(cellKey(for: p)) {
            let pin = SKShapeNode(rectOf: CGSize(width: pinSide, height: pinSide))
            pin.fillColor = dsGold; pin.strokeColor = .clear
            pin.position = mapPoint(p); pin.zPosition = 1
            gridNode.addChild(pin)
        }
        for p in clusteredPins(storePositions) where visitedCells.contains(cellKey(for: p)) {
            let pin = SKShapeNode(rectOf: CGSize(width: pinSide, height: pinSide))
            pin.fillColor = shopBlue; pin.strokeColor = .clear
            pin.position = mapPoint(p); pin.zPosition = 1
            gridNode.addChild(pin)
        }

        // Player marker — pulsing red dot.
        if let p = player {
            let dot = SKShapeNode(circleOfRadius: max(3.5, cell * 0.18))
            dot.fillColor = dsHeartRed
            dot.strokeColor = SKColor.white.withAlphaComponent(0.85); dot.lineWidth = 1
            dot.position = mapPoint(p.position); dot.zPosition = 2
            dot.run(.repeatForever(.sequence([
                .scale(to: 1.35, duration: 0.45),
                .scale(to: 1.00, duration: 0.45),
            ])))
            gridNode.addChild(dot)
        }

        // Legend.
        let legendY = -panelH / 2 + pad + legendBand / 2 - 6
        let legend: [(SKColor, String, Bool)] = [
            (dsHeartRed, "YOU", true), (dsGold, "GAMES", false), (shopBlue, "SHOP", false),
        ]
        let groupX: [CGFloat] = [-panelW * 0.34, -panelW * 0.06, panelW * 0.22]
        for (i, (color, text, round)) in legend.enumerated() {
            let swatch: SKShapeNode = round
                ? SKShapeNode(circleOfRadius: 3.5)
                : SKShapeNode(rectOf: CGSize(width: 7, height: 7))
            swatch.fillColor = color; swatch.strokeColor = .clear
            swatch.position = CGPoint(x: groupX[i], y: legendY)
            ov.addChild(swatch)

            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text = text; lbl.fontSize = 7
            lbl.fontColor = SKColor(white: 0.78, alpha: 1)
            lbl.horizontalAlignmentMode = .left; lbl.verticalAlignmentMode = .center
            lbl.position = CGPoint(x: groupX[i] + 8, y: legendY)
            ov.addChild(lbl)
        }

        // Close hint below the panel.
        let hint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        hint.text = "TAP TO CLOSE"; hint.fontSize = 8
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.horizontalAlignmentMode = .center; hint.verticalAlignmentMode = .center
        hint.position = CGPoint(x: 0, y: -panelH / 2 - 20)
        hint.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.7),
            .fadeAlpha(to: 1.00, duration: 0.7),
        ])))
        ov.addChild(hint)
    }

    private func hideMapOverlay() {
        mapOverlayNode?.removeFromParent()
        mapOverlayNode = nil
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
