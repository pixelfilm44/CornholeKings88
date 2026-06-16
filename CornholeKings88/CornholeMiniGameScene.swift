import SpriteKit
import UIKit

// MARK: - CornholeMiniGameScene
// 16-bit style cornhole mini-game, self-contained. Present this scene when the
// player steps up to a board and taps A. Bags are drawn programmatically;
// replace bag_16bit.png / board_16bit.png in the bundle when sprites are ready.

final class CornholeMiniGameScene: SKScene {

    // MARK: - Public
    var previousScene: SKScene?
    var onComplete: ((Bool) -> Void)?
    /// True only when launched from the world map / story mode. The mini-game menu leaves
    /// this false so no prize lines are shown and no items are awarded.
    var awardsRewards: Bool = false
    /// Coins earned this match (awarded on a Billy win); read by GameScene after onComplete.
    private(set) var coinsEarned: Int = 0
    private var closeUIButton: UIButton? = nil  // unused; SK close button replaces UIKit
    /// Honey bags from inventory injected by GameScene before presenting.
    var availableHoneyBags: Int = 0
    /// How many honey bags the player actually used this match (consumed from inventory).
    private(set) var honeyBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a honey bag on the next throw.
    private var honeyBagSelected = false
    /// Bomb bags from inventory injected by GameScene before presenting.
    var availableBombBags: Int = 0
    /// How many bomb bags the player actually used this match (consumed from inventory).
    private(set) var bombBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a bomb bag on the next throw.
    private var bombBagSelected = false
    /// Bomb bags earned this match (awarded on Billy win); read by GameScene after onComplete.
    private(set) var bombBagsEarned: Int = 0
    /// Magic bags from inventory injected by GameScene before presenting.
    var availableMagicBags: Int = 0
    /// How many magic bags the player actually used this match (consumed from inventory).
    private(set) var magicBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a magic bag on the next throw.
    private var magicBagSelected = false
    /// Magic bags earned this match (awarded on Tree Spirit win); read by GameScene after onComplete.
    private(set) var magicBagsEarned: Int = 0
    /// Fire bags from inventory injected by GameScene before presenting.
    var availableFireBags: Int = 0
    /// How many fire bags the player actually used this match (consumed from inventory).
    private(set) var fireBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a fire bag on the next throw.
    private var fireBagSelected = false
    /// Fire bags earned this match; read by GameScene after onComplete.
    private(set) var fireBagsEarned: Int = 0
    /// Golden bags from inventory injected by GameScene before presenting.
    var availableGoldenBags: Int = 0
    /// How many golden bags the player actually used this match (consumed from inventory).
    private(set) var goldenBagsUsed: Int = 0
    /// Whether the player has opted in to throwing a golden bag on the next throw.
    private var goldenBagSelected = false
    /// Golden bags earned this match (awarded mid-game on a 4x cornhole streak); read by host after onComplete.
    private(set) var goldenBagsEarned: Int = 0

    // MARK: - Types

    enum BagOwner { case player, ai }

    private enum State { case playerTurn, aiTurn, resolving, gameOver }

    // Per-bag physics/visual state kept off the node graph to avoid SpriteKit
    // overhead. Positions are in scene coordinate units (source pixels).
    private final class MiniGameBag {
        var bx, by, bz: CGFloat   // physics world position; bz = height above surface
        var vx, vy, vz: CGFloat   // velocities (per-frame units)
        var rot: CGFloat = 0
        var rotV: CGFloat = 0
        var owner: BagOwner
        var isGrounded = false
        var hasScored = false                // landed in hole
        var hasAppliedGroundScale = false    // prevents double-shrink on re-collision
        var hasLanded = false               // first touchdown — for haptic trigger
        var baseScale: CGFloat = 1.0        // 0.75 for off-board bags; multiplied by height scale
        /// Honey bags (won from BeeHive Battle) stick to the board — immune to wind and bag collisions.
        var isHoney = false
        /// Bomb bags destroy opponent bags on the board or in the hole on landing.
        var isBomb = false
        /// Prevents the bomb explosion from firing more than once.
        var hasBombed = false
        /// Magic bags destroy the specific opponent bag they physically collide with on the board;
        /// scoring in the hole destroys all opponent bags already in the hole this round.
        var isMagic = false
        /// Fire bags burn all board bags when they land (thrower keeps 1 pt); burn all hole bags when scored.
        var isFire = false
        /// Prevents the fire effect from triggering more than once per bag.
        var hasTriggeredFire = false
        /// Golden bags score 2 pts on board and 6 pts in hole. Fully immune to all magic bag effects.
        var isGolden = false
        /// Bags marked destroyed are removed from scoring but kept in activeBags until the round ends.
        var isDestroyed = false
        /// Set when an off-board bag drops into Barnum's chasm — it falls into the dark and
        /// is removed from collisions/scoring. Prevents the plummet animation re-triggering.
        var isFallingInChasm = false
        /// Set while a cave-match bat has snatched the bag and is carrying it to a drop point.
        /// While true, physics and deform are skipped — the bat action drives position.
        var isCarriedByBat = false

        // MARK: Soft-bag deformation (Tier 1/2 — pure visual, volume-preserving)
        /// Signed deform driven by a damped spring. >0 = flattened (wide + short, like a
        /// beanbag slapping the board); <0 = stretched (tall + narrow, e.g. leaning into a
        /// throw). Folded into the bag's non-uniform scale each frame in `updateBagDeform`.
        /// Never affects bx/by/bz or scoring.
        var deform: CGFloat = 0
        /// Spring velocity for `deform` — carries the overshoot that produces the jiggle/settle.
        var deformV: CGFloat = 0

        // MARK: Tier 3 — directional mesh-warp drape
        /// Displacement vector in the bag's **local texture frame** (normalized units),
        /// driven by a damped spring back to zero. Kicked toward the impact direction so
        /// the bag's leading edge visibly flops/drapes that way over the board or another
        /// bag. Folded into an `SKWarpGeometryGrid` each frame in `updateBagDeform`.
        var warpX: CGFloat = 0
        var warpY: CGFloat = 0
        var warpVX: CGFloat = 0
        var warpVY: CGFloat = 0

        let node: SKSpriteNode
        let shadow: SKSpriteNode

        init(owner: BagOwner, startX: CGFloat, startY: CGFloat,
             isHoney: Bool = false, isBomb: Bool = false, isMagic: Bool = false,
             isFire: Bool = false, isGolden: Bool = false) {
            self.owner    = owner
            self.bx = startX; self.by = startY; self.bz = 3
            self.vx = 0; self.vy = 0; self.vz = 0
            self.isHoney  = isHoney
            self.isBomb   = isBomb
            self.isMagic  = isMagic
            self.isFire   = isFire
            self.isGolden = isGolden

            let goldenColor = SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
            let playerColor: SKColor
            if isGolden {
                playerColor = goldenColor
            } else if isBomb {
                playerColor = SKColor(red: 0.08, green: 0.06, blue: 0.06, alpha: 1)
            } else if isMagic {
                // Fluorescent green — pops against the spirit's night scene
                playerColor = SKColor(red: 0.30, green: 1.00, blue: 0.10, alpha: 1)
            } else if isFire {
                playerColor = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)
            } else if isHoney {
                playerColor = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)
            } else {
                playerColor = SKColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
            }
            let aiColor: SKColor
            if isGolden {
                aiColor = goldenColor
            } else if isBomb {
                aiColor = SKColor(red: 0.12, green: 0.04, blue: 0.18, alpha: 1)
            } else if isMagic {
                // Fluorescent green — matches the player magic bag look
                aiColor = SKColor(red: 0.30, green: 1.00, blue: 0.10, alpha: 1)
            } else if isFire {
                aiColor = SKColor(red: 0.90, green: 0.22, blue: 0.02, alpha: 1)
            } else {
                aiColor = SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1)
            }

            let bagTex = SKTexture(imageNamed: "bag_16bit")
            bagTex.filteringMode = .nearest
            node = SKSpriteNode(texture: bagTex, size: CGSize(width: 50, height: 50))
            node.color            = owner == .player ? playerColor : aiColor
            node.colorBlendFactor = (isBomb || isMagic || isFire || isGolden) ? 0.88 : 0.65
            node.zPosition        = 20
            // Tier 3: smooth out the 3×3 drape warp into a curved bend rather than
            // flat facets. Costs nothing until a warpGeometry is actually attached.
            node.subdivisionLevels = 2

            // Skull marker on bomb bags
            if isBomb {
                let skull = SKLabelNode(text: "☠")
                skull.fontSize                = 14
                skull.verticalAlignmentMode   = .center
                skull.horizontalAlignmentMode = .center
                skull.position  = .zero
                skull.zPosition = 1
                node.addChild(skull)
            }
            // Sparkle marker on magic bags
            if isMagic {
                // Render above the storm dark overlay (z=95) and rain particles (z=102)
                // so the fluorescent green stays bright against the night scene.
                node.zPosition = 110
                let sparkle = SKLabelNode(text: "✦")
                sparkle.fontSize                = 14
                sparkle.fontColor               = SKColor(red: 0.90, green: 1.0, blue: 0.70, alpha: 1)
                sparkle.verticalAlignmentMode   = .center
                sparkle.horizontalAlignmentMode = .center
                sparkle.position  = .zero
                sparkle.zPosition = 1
                node.addChild(sparkle)
                // Gentle pulse so magic bags are obvious in flight
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.65, duration: 0.35),
                    SKAction.fadeAlpha(to: 1.00, duration: 0.35),
                ])))
            }
            // Flame marker on fire bags
            if isFire {
                let flame = SKLabelNode(text: "🔥")
                flame.fontSize                = 13
                flame.verticalAlignmentMode   = .center
                flame.horizontalAlignmentMode = .center
                flame.position  = .zero
                flame.zPosition = 1
                node.addChild(flame)
                // Flicker so fire bags are obvious in flight
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.70, duration: 0.18),
                    SKAction.fadeAlpha(to: 1.00, duration: 0.18),
                ])))
            }
            // Star marker on golden bags
            if isGolden {
                let star = SKLabelNode(text: "★")
                star.fontSize                = 15
                star.fontColor               = SKColor(white: 1.0, alpha: 0.90)
                star.verticalAlignmentMode   = .center
                star.horizontalAlignmentMode = .center
                star.position  = .zero
                star.zPosition = 1
                node.addChild(star)
                // Shimmer pulse so golden bags stand out clearly
                node.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.colorize(with: SKColor(red: 1.0, green: 1.0, blue: 0.6, alpha: 1),
                                      colorBlendFactor: 0.50, duration: 0.30),
                    SKAction.colorize(withColorBlendFactor: 0.88, duration: 0.30),
                ])))
            }

            shadow = SKSpriteNode(color: .black,
                                  size: CGSize(width: 50, height: 35))
            shadow.alpha = 0.35
            shadow.zPosition = 6

            // Seed initial position so the node doesn't flash at the gameWorld origin
            // (mid-screen) for one frame before updateBagPhysics positions it.
            node.position   = CGPoint(x: bx, y: by + bz * 0.50)
            shadow.position = CGPoint(x: bx, y: by)
        }

        required init?(coder: NSCoder) { fatalError() }

        var isMoving: Bool { bz > 0.15 || abs(vx) > 0.012 || abs(vy) > 0.012 }
    }

    // MARK: - Layout (computed in didMove)
    private var boardY: CGFloat = 0
    private var throwLineY: CGFloat = 0
    private var boardHalfW: CGFloat = 0
    private var boardHalfH: CGFloat = 0
    private var holeCenter = CGPoint.zero
    private var holeRadius: CGFloat = 0
    private var targetRange: CGFloat = 0
    private var targetSpeed: CGFloat = 0
    private var powerScale: CGFloat = 0
    private var crowY:      CGFloat = 0
    /// Long-distance variant — scales board, hole, bag visuals, gopher, and crow.
    /// 1.0 = standard distance; 0.5 = long-distance (used vs. Billy).
    private var distanceScale: CGFloat = 1.0
    private var boardContainerNode: SKNode?
    private var throwLineNode: SKSpriteNode?
    private var worldBackground: SKSpriteNode?
    private var sunGlowNode: SKSpriteNode?
    private var grassContainerNode: SKNode?

    // MARK: - Physics constants
    private let gravityPerFrame: CGFloat = 0.50
    private let vzInitial:       CGFloat = 15.0

    // MARK: - Game state
    private var gameState: State = .playerTurn
    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var activeBags: [MiniGameBag] = []
    private var playerBagsThrown = 0
    private var aiBagsThrown     = 0
    private let bagsPerPlayer    = 4
    private var winScore         = 11
    private var playerScore      = 0
    private var aiScore          = 0
    private var lastThrower: BagOwner = .ai
    private var hasCalculatedScore = false
    /// Consecutive player cornholes in the current match (resets on a player throw that misses).
    private var playerCornholeStreak = 0

    // Fire bag round state — reset each round
    private var boardOnFire = false   // board burns subsequent bags that land on it
    private var holeFire    = false   // subsequent cornholes this round are destroyed
    private var fireBoardOverlay: SKSpriteNode?

    // Moving throw-target oscillation
    private var targetX: CGFloat = 0
    private var targetMovingRight = true

    // Wind (dx only for 2D feel)
    private var wind = CGVector.zero

    // Rain scenario — rolled once per game; -1 = no rain
    private var rainActive      = false
    private var rainStartRound  = -1      // round when rain begins (1-indexed)
    private var rainEndRound    = Int.max // first round without rain (Int.max = whole game)
    private var roundNumber     = 0
    private var rainParticleNode: SKNode?
    private var boardRainOverlay: SKSpriteNode?

    // Thunderstorm scenario — mutually exclusive with rain; rolled once per game
    private var stormActive      = false
    private var stormStartRound  = -1
    private var stormEndRound    = Int.max
    private var stormDarkOverlay: SKSpriteNode?
    private var stormParticleNode: SKNode?
    private var stormFlashOverlay: SKSpriteNode?
    private var stormAudioNode:   SKAudioNode?

    // Tom's fart ability — 50% chance per round; green fog + faster/wobbling indicator
    private var tomFartActive    = false
    private var tomFartOverlay:  SKNode?
    private var fartBaseSpeed:   CGFloat = 0  // saved targetSpeed before doubling
    private var fartWobbleTimer: CGFloat = 0

    // Gopher — only one alive at a time; chases the throw-line bag and steals it
    private var activeGopher: GopherNode?
    private let gopherSpawnChance: Double = 0.15   // 15% per turn
    // Pre-committed AI start position so the gopher can race toward it.
    // Set when the AI's turn begins; consumed by aiThrow().
    private var pendingAIStartX: CGFloat = 0

    // Crow — occasionally flies through the bag-flight corridor below the board
    private var crowNode: SKNode?
    private var crowFlyingRight = true

    // Dragon — Barnum's cavern only. Rises from the chasm and breathes flame across
    // the bag-flight corridor, igniting any airborne bag into a fire bag.
    private var dragonNode: SKNode?

    // Cave bat — when the dragon isn't out, a bat occasionally swoops in, snatches a
    // thrown bag mid-air, and drops it on the board (mostly) or in the hole. The
    // original thrower still scores the bag.
    private var batNode: SKNode?

    // Opponent selection
    enum AIOpponent { case tom, jenny, billy, spirit, bully, barnum, cathy }
    /// Set before presenting to skip the picker and start with a specific opponent.
    var preSelectedOpponent: AIOpponent? = nil
    private var selectedOpponent: AIOpponent = .tom
    private var opponentPortrait: SKSpriteNode?
    private var playerPortrait: SKSpriteNode?
    private var opponentName: String {
        switch selectedOpponent {
        case .tom:    return "TOM"
        case .jenny:  return "JENNY"
        case .billy:  return "BILLY"
        case .spirit: return "SPIRIT"
        case .bully:  return "BULLY"
        case .barnum: return "BARNUM"
        case .cathy:  return "CATHYX"
        }
    }

    // CathyX — inverted scoring match: you only score by landing ON the board, and a
    // bag that drops in the hole is a 3-point penalty (floored at zero). Set by
    // applyCathySettings(); read by calculateRoundScore() and the cornhole-streak guard.
    private var isCathyMatch = false

    // Barnum — "good but not great". Fixed aim noise (lower = tighter). Tom/Jenny
    // sit around 2.5; Billy adapts down toward 1.4. Barnum lands in between.
    private var barnumNoiseFactor: CGFloat = 1.9
    // Cave-match flag: dark cavern scenery, no gophers, a dragon that ignites bags.
    private var isCaveMatch = false
    private var caveDragonScheduled = false
    // Chasm Y-band (world coords). An off-board bag landing between these falls into the dark.
    private var caveChasmTopY: CGFloat = 0
    private var caveChasmBottomY: CGFloat = 0

    // Billy the Bully — adaptive difficulty state
    private var billyNoiseFactor: CGFloat  = 2.5  // lower = harder; adapts each round
    private var billyBombBagsRemaining: Int = 0   // bomb bags Billy can throw this match

    // Input
    private var touchStart: CGPoint?
    private var aimingLine: SKShapeNode?

    // Quit-confirm state (tutorial state is owned by TutorialOverlay itself)
    private var confirmingQuit   = false
    private var confirmPanel:  SKNode?

    // MARK: - Node references
    private var gameWorldNode: SKEffectNode!
    private var turnIndicator: SKSpriteNode?
    private var playerScoreLabel: SKLabelNode?
    private var aiScoreLabel:     SKLabelNode?
    private var windLabel:        SKLabelNode?
    private var messageNode: SKNode?
    private var satchelButton: SKNode?
    private var satchelPanel: SKNode?
    private var satchelOpen = false

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        preloadAssets()
        computeLayout()
        setupGameWorld()
        setupBoard()
        setupUI()
        // Picker → tutorial → startRound
        showOpponentPicker()
    }

    override func willMove(from view: SKView) { }

    private func preloadAssets() {
        // Force textures into GPU memory so the first bag throw doesn't stutter
        let textures = ["bag_16bit", "board_16bit"].map { name -> SKTexture in
            let t = SKTexture(imageNamed: name)
            t.filteringMode = .nearest
            return t
        }
        SKTexture.preload(textures) { }

        // Warm up AVAudioEngine (shared with playSoundFileNamed) by playing each
        // sound once at volume 0. Guard against missing files — SKAudioNode crashes
        // hard on a missing file while playSoundFileNamed silently no-ops.
        let sounds = ["hit.mp3",      "hole_score.wav", "round_end.wav",
                      "rain_start.wav", "gopher_pop.wav", "gopher_steal.wav",
                      "game_win.wav",  "game_lose.wav",  "storm.mp3",
                      "cornhole.wav", "quack.wav",
                      "dragon_roar.wav",   // Barnum's dragon — asset optional; skipped if absent
                      "fart.wav"]   // Tom's toot — asset optional; skipped if absent
        sounds.forEach { warmUpSound($0) }
    }

    private func warmUpSound(_ filename: String) {
        let base = (filename as NSString).deletingPathExtension
        let ext  = (filename as NSString).pathExtension
        guard Bundle.main.url(forResource: base, withExtension: ext) != nil else { return }
        let audio = SKAudioNode(fileNamed: filename)
        audio.autoplayLooped = false
        audio.isPositional   = false
        addChild(audio)
        audio.run(SKAction.sequence([
            SKAction.changeVolume(to: 0, duration: 0),
            SKAction.play(),
            SKAction.wait(forDuration: 0.05),
            SKAction.run { [weak audio] in audio?.removeFromParent() },
        ]))
    }

    // MARK: - Layout

    private func computeLayout() {
        // Push the board further up the screen as distanceScale shrinks, selling the
        // longer-distance illusion. At 1.0 → boardY = 0.18; at 0.5 → boardY = 0.30.
        boardY       = size.height * (0.18 + (1.0 - distanceScale) * 0.24)
        throwLineY   = -size.height * 0.30
        boardHalfW   = size.width * 0.2625 * distanceScale  // 25% narrower than before, scaled for distance variant
        boardHalfH   = boardHalfW * 1.20
        holeCenter   = CGPoint(x: 0, y: boardY + boardHalfH * 0.30)
        holeRadius   = boardHalfW * 0.25
        targetRange  = boardHalfW * 1.30
        targetSpeed  = size.width * 0.70   // source pixels per second
        // Gauntlet (purchased from the world Store) slows the throw-line oscillation
        // so the player can time their swipe more easily.
        if StoreManager.gauntletOwned {
            targetSpeed *= 0.55
        }
        fartBaseSpeed = targetSpeed

        // powerScale chosen so a 38% screen-height swipe lands near the hole
        let distToHole   = abs(holeCenter.y - throwLineY)
        let flightFrames = 2.0 * vzInitial / gravityPerFrame  // ≈ 100 frames
        let idealSwipe   = size.height * 0.38
        powerScale = distToHole / (flightFrames * idealSwipe)

        // Crow intercept corridor: 60% of the way from throw line to board's lower edge
        crowY = throwLineY + (boardY - boardHalfH - throwLineY) * 0.60
    }

    // MARK: - Scene Setup

    private func setupGameWorld() {
        // SKEffectNode applies the CIPixellate filter — gives the 16-bit chunky-pixel look.
        // Scale 2 = each source pixel rendered as a 2×2 block (subtler than 8-bit at 4).
        gameWorldNode = SKEffectNode()
        if let filter = CIFilter(name: "CIPixellate") {
            filter.setValue(2.0, forKey: "inputScale")
            gameWorldNode.filter = filter
            gameWorldNode.shouldEnableEffects = true
        }
        gameWorldNode.shouldRasterize = false
        addChild(gameWorldNode)

        // Grass background — slightly brightened for outdoor daylight feel
        let bg = SKSpriteNode(color: SKColor(red: 0.18, green: 0.38, blue: 0.13, alpha: 1),
                              size: CGSize(width: size.width * 2, height: size.height * 2))
        bg.zPosition = -200
        gameWorldNode.addChild(bg)
        worldBackground = bg

        // Warm sunlight wash — subtle yellow-gold tint. Added to scene (not gameWorldNode)
        // to avoid SKEffectNode render-bounds expansion.
        let sunGlow = SKSpriteNode(color: SKColor(red: 1.0, green: 0.92, blue: 0.42, alpha: 0.11),
                                   size: CGSize(width: size.width * 2, height: size.height * 2))
        sunGlow.zPosition = 60   // above gameplay, below chrome (500)
        addChild(sunGlow)
        sunGlowNode = sunGlow

        let grass = SKNode()
        grass.zPosition = -199
        gameWorldNode.addChild(grass)
        grassContainerNode = grass
        addGrassPattern(into: grass)

        // Throw line
        let throwLine = SKSpriteNode(
            color: SKColor(white: 1.0, alpha: 0.55),
            size: CGSize(width: boardHalfW * 1.2, height: 1))
        throwLine.position = CGPoint(x: 0, y: throwLineY)
        throwLine.zPosition = -1
        gameWorldNode.addChild(throwLine)
        throwLineNode = throwLine
    }

    // Scatter random darker/lighter 4×4 grass tufts for texture
    private func addGrassPattern(into container: SKNode) {
        let tileSize: CGFloat = 4
        let palette: [SKColor] = [
            SKColor(red: 0.10, green: 0.25, blue: 0.08, alpha: 1),
            SKColor(red: 0.18, green: 0.38, blue: 0.14, alpha: 1),
            SKColor(red: 0.09, green: 0.22, blue: 0.07, alpha: 1),
        ]
        var x = -size.width
        while x < size.width {
            var y = -size.height
            while y < size.height {
                if Int.random(in: 0..<5) == 0 {
                    let tuft = SKSpriteNode(color: palette.randomElement()!,
                                           size: CGSize(width: tileSize, height: tileSize))
                    tuft.position = CGPoint(x: x + tileSize / 2, y: y + tileSize / 2)
                    container.addChild(tuft)
                }
                y += tileSize
            }
            x += tileSize
        }
    }

    /// Swaps the outdoor grass field for a dark cavern: black ground, a deep chasm
    /// the bag flies over, jagged rock edges, and stalactites hanging from above.
    /// Called from `applyBarnumSettings()` after layout settles.
    private func applyCaveScenery() {
        // Dim the daylight glow and darken the ground to near-black cave rock.
        sunGlowNode?.removeFromParent()
        worldBackground?.color = SKColor(red: 0.05, green: 0.04, blue: 0.06, alpha: 1)
        grassContainerNode?.removeFromParent()
        grassContainerNode = nil

        // Speckle the cave floor with a few faint rock highlights for texture.
        let speckle = SKNode()
        speckle.zPosition = -199
        let palette: [SKColor] = [
            SKColor(red: 0.10, green: 0.09, blue: 0.12, alpha: 1),
            SKColor(red: 0.07, green: 0.06, blue: 0.09, alpha: 1),
            SKColor(red: 0.13, green: 0.11, blue: 0.15, alpha: 1),
        ]
        var x = -size.width
        while x < size.width {
            var y = -size.height
            while y < size.height {
                if Int.random(in: 0..<6) == 0 {
                    let rock = SKSpriteNode(color: palette.randomElement()!,
                                            size: CGSize(width: 4, height: 4))
                    rock.position = CGPoint(x: x + 2, y: y + 2)
                    speckle.addChild(rock)
                }
                y += 4
            }
            x += 4
        }
        gameWorldNode.addChild(speckle)

        // The chasm: a wide black void between the throw line and the board's front
        // edge — the gap the player flings the bag across. Pitch black with a faint
        // blue rim so it reads as bottomless depth.
        let chasmTop    = boardY - boardHalfH - 6
        let chasmBottom = throwLineY + 18
        caveChasmTopY    = chasmTop
        caveChasmBottomY = chasmBottom
        let chasmH = max(20, chasmTop - chasmBottom)
        let chasmW = size.width * 1.05
        let chasm = SKSpriteNode(color: .black,
                                 size: CGSize(width: chasmW, height: chasmH))
        chasm.position  = CGPoint(x: 0, y: (chasmTop + chasmBottom) / 2)
        chasm.zPosition = -150
        gameWorldNode.addChild(chasm)

        // Jagged rock lip along the near and far edges of the chasm.
        addRockLip(atY: chasmTop,    pointingDown: false, width: chasmW)
        addRockLip(atY: chasmBottom, pointingDown: true,  width: chasmW)

        // Stalactites hanging from the cave ceiling (just below the top HUD).
        let ceilingY = size.height * 0.42
        var sx = -size.width * 0.5
        while sx < size.width * 0.5 {
            let h = CGFloat.random(in: 16...40)
            let w = CGFloat.random(in: 8...16)
            let stal = makeTriangle(width: w, height: h,
                                    color: SKColor(red: 0.12, green: 0.10, blue: 0.14, alpha: 1),
                                    pointingDown: true)
            stal.position  = CGPoint(x: sx + CGFloat.random(in: 0...30), y: ceilingY)
            stal.zPosition = -140
            gameWorldNode.addChild(stal)
            sx += CGFloat.random(in: 40...80)
        }
    }

    /// A row of small jagged triangles forming a rocky chasm edge.
    private func addRockLip(atY y: CGFloat, pointingDown: Bool, width: CGFloat) {
        let lip = SKNode()
        lip.position  = CGPoint(x: 0, y: y)
        lip.zPosition = -145
        var x = -width / 2
        while x < width / 2 {
            let w = CGFloat.random(in: 10...22)
            let h = CGFloat.random(in: 6...14)
            let tri = makeTriangle(width: w, height: h,
                                   color: SKColor(red: 0.09, green: 0.08, blue: 0.10, alpha: 1),
                                   pointingDown: pointingDown)
            tri.position = CGPoint(x: x + w / 2, y: 0)
            lip.addChild(tri)
            x += w
        }
        gameWorldNode.addChild(lip)
    }

    /// Builds a flat-shaded triangle sprite (stalactite / rock tooth).
    private func makeTriangle(width: CGFloat, height: CGFloat,
                              color: SKColor, pointingDown: Bool) -> SKShapeNode {
        let path = CGMutablePath()
        if pointingDown {
            path.move(to: CGPoint(x: -width / 2, y: 0))
            path.addLine(to: CGPoint(x: width / 2, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -height))
        } else {
            path.move(to: CGPoint(x: -width / 2, y: 0))
            path.addLine(to: CGPoint(x: width / 2, y: 0))
            path.addLine(to: CGPoint(x: 0, y: height))
        }
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor   = color
        node.strokeColor = SKColor(white: 0.0, alpha: 0.0)
        node.lineWidth   = 0
        return node
    }

    private func setupBoard() {
        let boardContainer = SKNode()
        boardContainer.position = CGPoint(x: 0, y: boardY)
        boardContainer.zPosition = 5
        boardContainer.setScale(0.90)   // visual-only shrink; hit zone uses unscaled values
        gameWorldNode.addChild(boardContainer)
        boardContainerNode = boardContainer

        let bw = boardHalfW * 2
        let bh = boardHalfH * 2

        // Drop shadow (offset so it reads as depth)
        let shadowNode = SKSpriteNode(color: .black,
                                      size: CGSize(width: bw + 4, height: bh + 4))
        shadowNode.alpha = 0.45
        shadowNode.position = CGPoint(x: 4, y: -5)
        shadowNode.zPosition = -1
        boardContainer.addChild(shadowNode)

        // Board surface — use the 16-bit sprite asset
        let boardTex = SKTexture(imageNamed: "board_16bit")
        boardTex.filteringMode = .nearest
        let surface = SKSpriteNode(texture: boardTex, size: CGSize(width: bw, height: bh))
        surface.zPosition = 0
        boardContainer.addChild(surface)

        // Hole — dark circle positioned in the upper third of the board
        let holeRelY = holeCenter.y - boardY
        let holeTex = makePixelCircleTexture(
            radius:      holeRadius,
            fill:        UIColor(red: 0.06, green: 0.04, blue: 0.02, alpha: 1),
            border:      UIColor(red: 0.25, green: 0.13, blue: 0.04, alpha: 1),
            pixelSize:   3)
        let hole = SKSpriteNode(texture: holeTex,
                                size: CGSize(width: holeRadius * 2, height: holeRadius * 2))
        hole.position  = CGPoint(x: 0, y: holeRelY)
        hole.zPosition = 2
        boardContainer.addChild(hole)
    }

    /// Rasterises a circle as a grid of square pixels so it looks 16-bit rather
    /// than smooth. pixelSize controls the coarseness (3 = chunky, 1 = no effect).
    private func makePixelCircleTexture(radius: CGFloat,
                                        fill: UIColor,
                                        border: UIColor,
                                        pixelSize: Int) -> SKTexture {
        let ps    = CGFloat(pixelSize)
        let cells = Int(ceil(radius * 2 / ps)) + 2   // grid cells across diameter
        let imgPx = cells * pixelSize                 // total image size in points
        let size  = CGSize(width: CGFloat(imgPx), height: CGFloat(imgPx))
        let cx    = CGFloat(cells) / 2.0
        let cy    = CGFloat(cells) / 2.0
        let r     = radius / ps   // radius in grid-cell units

        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }

        for row in 0..<cells {
            for col in 0..<cells {
                // Distance from cell centre to circle centre (in grid units)
                let dx   = CGFloat(col) + 0.5 - cx
                let dy   = CGFloat(row) + 0.5 - cy
                let dist = sqrt(dx * dx + dy * dy)

                let rect = CGRect(x: CGFloat(col) * ps, y: CGFloat(row) * ps,
                                  width: ps, height: ps)
                if dist <= r - 0.7 {
                    ctx.setFillColor(fill.cgColor)
                    ctx.fill(rect)
                } else if dist <= r + 0.3 {
                    ctx.setFillColor(border.cgColor)
                    ctx.fill(rect)
                }
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let tex   = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }

    /// Draws Barnum's portrait from scratch — a pixel-art circus showman with a black
    /// top hat (red band), big curled mustache, and a red bowtie. No asset required.
    static func makeBarnumPortraitTexture() -> SKTexture {
        // 16×16 legend grid.
        let rows = [
            "......HHHH......",
            "......HHHH......",
            "......HHHH......",
            "......RRRR......",
            "....HHHHHHHH....",
            ".....SSSSSS.....",
            ".....SSSSSS.....",
            "....SSSSSSSS....",
            "....SEESSEES....",
            "....SSSSSSSS....",
            "...MMSSSSSSMM...",
            "...MMMMMMMMMM...",
            "......SSSS......",
            "......SSSS......",
            "....RRRRRRRR....",
            "...RRRRRRRRRR...",
        ]
        let colors: [Character: UIColor] = [
            "H": UIColor(red: 0.08, green: 0.07, blue: 0.09, alpha: 1),
            "R": UIColor(red: 0.80, green: 0.16, blue: 0.12, alpha: 1),
            "S": UIColor(red: 0.93, green: 0.76, blue: 0.55, alpha: 1),
            "E": UIColor(red: 0.10, green: 0.08, blue: 0.12, alpha: 1),
            "M": UIColor(red: 0.30, green: 0.18, blue: 0.08, alpha: 1),
        ]
        let cells = 16
        let ps: CGFloat = 3
        let dim = CGFloat(cells) * ps
        UIGraphicsBeginImageContextWithOptions(CGSize(width: dim, height: dim), false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }
        for (row, line) in rows.enumerated() {
            for (col, ch) in line.enumerated() {
                guard let c = colors[ch] else { continue }
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: CGFloat(col) * ps, y: CGFloat(row) * ps, width: ps, height: ps))
            }
        }
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }

    /// Shared helper: paint a square pixel grid (`cells × cells`) from a row-string
    /// legend and a character→color map, return as a `.nearest` SKTexture.
    private static func pixelPortrait(rows: [String],
                                      colors: [Character: UIColor],
                                      cells: Int = 16,
                                      ps: CGFloat = 3) -> SKTexture {
        let dim = CGFloat(cells) * ps
        UIGraphicsBeginImageContextWithOptions(CGSize(width: dim, height: dim), false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }
        for (row, line) in rows.enumerated() {
            for (col, ch) in line.enumerated() {
                guard let c = colors[ch] else { continue }
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: CGFloat(col) * ps, y: CGFloat(row) * ps,
                                width: ps, height: ps))
            }
        }
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let tex = SKTexture(image: image)
        tex.filteringMode = .nearest
        return tex
    }

    /// Tom: short orange hair, peachy skin, blue/white striped tee, blue eyes.
    static func makeTomPortraitTexture() -> SKTexture {
        let rows = [
            "................",
            "....HHHHHHHH....",
            "...HHHHHHHHHH...",
            "..HHHHHHHHHHHH..",
            "..HHSSSSSSSSHH..",
            "..HSSSSSSSSSSH..",
            "..HSSEESSSEESH..",
            "..HSSSSSSSSSSH..",
            "...SSSSMMSSSS...",
            "....SSSSSSSS....",
            ".....SSSSSS.....",
            "...BBBWWWWBBB...",
            "..BWWBBBBBBWWB..",
            "..WBBWWWWWWBBW..",
            "..BWWBBBBBBWWB..",
            "..BB........BB..",
        ]
        let colors: [Character: UIColor] = [
            "H": UIColor(red: 0.85, green: 0.45, blue: 0.18, alpha: 1), // orange hair
            "S": UIColor(red: 0.97, green: 0.80, blue: 0.62, alpha: 1), // peach skin
            "E": UIColor(red: 0.16, green: 0.32, blue: 0.62, alpha: 1), // blue eyes
            "M": UIColor(red: 0.55, green: 0.22, blue: 0.18, alpha: 1), // mouth
            "B": UIColor(red: 0.20, green: 0.42, blue: 0.78, alpha: 1), // shirt blue
            "W": UIColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1), // shirt white
        ]
        return pixelPortrait(rows: rows, colors: colors)
    }

    /// Jenny: long dark wavy hair, tan skin, brown eyes, red top.
    static func makeJennyPortraitTexture() -> SKTexture {
        let rows = [
            "....HHHHHHHH....",
            "...HHHHHHHHHH...",
            "..HHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHSSSSSSSSHHH.",
            ".HHSSSSSSSSSSHH.",
            ".HHSSEESSSEESHH.",
            ".HHSSSSSSSSSSHH.",
            ".HHSSSSMMMMSSHH.",
            ".HHHSSSSSSSSHHH.",
            ".HHHHSSSSSSHHHH.",
            ".HHHHHHHHHHHHHH.",
            "..RRRRRRRRRRRR..",
            ".RRRRRRRRRRRRRR.",
            ".RRR........RRR.",
            ".RR..........RR.",
        ]
        let colors: [Character: UIColor] = [
            "H": UIColor(red: 0.18, green: 0.10, blue: 0.08, alpha: 1), // dark hair
            "S": UIColor(red: 0.86, green: 0.62, blue: 0.46, alpha: 1), // tan skin
            "E": UIColor(red: 0.10, green: 0.06, blue: 0.05, alpha: 1), // dark eyes
            "M": UIColor(red: 0.55, green: 0.18, blue: 0.16, alpha: 1), // smile
            "R": UIColor(red: 0.78, green: 0.22, blue: 0.22, alpha: 1), // red top
        ]
        return pixelPortrait(rows: rows, colors: colors)
    }

    /// CathyX: long platinum hair, fair skin, sly green eyes and a sideways smirk,
    /// violet top. The trickster who punishes you for sinking the hole.
    static func makeCathyPortraitTexture() -> SKTexture {
        let rows = [
            "...HHHHHHHHHH...",
            "..HHHHHHHHHHHH..",
            ".HHHHHHHHHHHHHH.",
            ".HHHSSSSSSSSHHH.",
            ".HHSSSSSSSSSSHH.",
            ".HHSSEESSSEESHH.",
            ".HHSSGGSSSGGSHH.",
            ".HHSSSSSSSSSSHH.",
            ".HHSSSSSSSMMSHH.",
            ".HHHSSSSMMSSHHH.",
            ".HHHHSSSSSSHHHH.",
            "..HHHHHHHHHHHH..",
            "..VVVVVVVVVVVV..",
            ".VVVVVVVVVVVVVV.",
            ".VVV........VVV.",
            ".VV..........VV.",
        ]
        let colors: [Character: UIColor] = [
            "H": UIColor(red: 0.93, green: 0.86, blue: 0.58, alpha: 1), // platinum hair
            "S": UIColor(red: 0.95, green: 0.80, blue: 0.68, alpha: 1), // fair skin
            "E": UIColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1), // eye outline
            "G": UIColor(red: 0.22, green: 0.62, blue: 0.34, alpha: 1), // sly green eyes
            "M": UIColor(red: 0.58, green: 0.18, blue: 0.30, alpha: 1), // sideways smirk
            "V": UIColor(red: 0.42, green: 0.20, blue: 0.55, alpha: 1), // violet top
        ]
        return pixelPortrait(rows: rows, colors: colors)
    }

    /// Billy the Bully: messy spiky black hair, pale skin, angry brow, dark shirt.
    static func makeBillyPortraitTexture() -> SKTexture {
        let rows = [
            "..H...HH..HH..H.",
            ".HHH.HHHHHHHH.HH",
            ".HHHHHHHHHHHHHH.",
            "HHHHHHHHHHHHHHHH",
            ".HHHSSSSSSSSHHH.",
            "..HSSSSSSSSSSH..",
            "..SSAASSSSAASS..",
            "..SSEESSSSEESS..", // angry eyes
            "..SSSSSSSSSSSS..",
            "..SSSSMMMMSSSS..",
            "...SSSSSSSSSS...",
            "....SSSSSSSS....",
            "...KKKKKKKKKK...",
            "..KKRRRRRRRRKK..",
            "..KRRRRRRRRRRK..",
            "..KK........KK..",
        ]
        let colors: [Character: UIColor] = [
            "H": UIColor(red: 0.10, green: 0.07, blue: 0.08, alpha: 1), // black hair
            "S": UIColor(red: 0.92, green: 0.78, blue: 0.66, alpha: 1), // pale skin
            "A": UIColor(red: 0.55, green: 0.18, blue: 0.14, alpha: 1), // red angry brow
            "E": UIColor(red: 0.08, green: 0.05, blue: 0.05, alpha: 1), // dark eyes
            "M": UIColor(red: 0.40, green: 0.10, blue: 0.10, alpha: 1), // snarl
            "K": UIColor(red: 0.12, green: 0.08, blue: 0.08, alpha: 1), // dark shirt
            "R": UIColor(red: 0.62, green: 0.16, blue: 0.16, alpha: 1), // red accent
        ]
        return pixelPortrait(rows: rows, colors: colors)
    }

    /// Generic street bully (world-roaming attackers): buzz cut, eye scar,
    /// weathered tan skin, snarl, sleeveless dirty-white muscle tee.
    static func makeBullyPortraitTexture() -> SKTexture {
        let rows = [
            "................",
            "....HHHHHHHH....",
            "...HHHHHHHHHH...",
            "..HHHHHHHHHHHH..",
            "..HHSSSSSSSSHH..",
            "..HSSSSSSSSSSH..",
            "..HSSEESCSEESH..",
            "..HSSSSSCSSSSH..",
            "...SSSSSSSSSS...",
            "....SSSMMMSSSS..",
            "....SSSSSSSS....",
            ".....SSSSSS.....",
            "...TT.TTTT.TT...",
            "..TTTTTTTTTTTT..",
            "..TTTRRRRRRTTT..",
            "..TT........TT..",
        ]
        let colors: [Character: UIColor] = [
            "H": UIColor(red: 0.16, green: 0.10, blue: 0.06, alpha: 1), // dark buzz cut
            "S": UIColor(red: 0.84, green: 0.62, blue: 0.46, alpha: 1), // tan/weathered skin
            "E": UIColor(red: 0.08, green: 0.05, blue: 0.05, alpha: 1), // hard eyes
            "C": UIColor(red: 0.62, green: 0.18, blue: 0.16, alpha: 1), // red scar
            "M": UIColor(red: 0.42, green: 0.12, blue: 0.10, alpha: 1), // snarl
            "T": UIColor(red: 0.86, green: 0.82, blue: 0.74, alpha: 1), // dirty white tee
            "R": UIColor(red: 0.62, green: 0.20, blue: 0.16, alpha: 1), // tee scuff
        ]
        return pixelPortrait(rows: rows, colors: colors)
    }

    /// Jeff (player): brown sweep hair, peach skin, brown eyes, blue hoodie + yellow tee.
    static func makeJeffPortraitTexture() -> SKTexture {
        let rows = [
            "................",
            "....HHHHHHHH....",
            "...HHHHHHHHHH...",
            "..HHHHHHHHHHHH..",
            "..HHSSSSSSSSHH..",
            "..HSSSSSSSSSSH..",
            "..HSSEESSSEESH..",
            "..HSSSSSSSSSSH..",
            "...SSSSNNSSSS...",
            "....SSSSSSSS....",
            "....SSSMMSSSS...",
            ".....SSYYSS.....",
            "...BBBBYYBBBB...",
            "..BBBBBYYBBBBB..",
            "..BBBB....BBBB..",
            "..BBB......BBB..",
        ]
        let colors: [Character: UIColor] = [
            "H": UIColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1), // brown hair
            "S": UIColor(red: 0.95, green: 0.78, blue: 0.62, alpha: 1), // peach skin
            "E": UIColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 1), // brown eyes
            "N": UIColor(red: 0.82, green: 0.62, blue: 0.48, alpha: 1), // nose shadow
            "M": UIColor(red: 0.55, green: 0.22, blue: 0.18, alpha: 1), // smile
            "B": UIColor(red: 0.24, green: 0.46, blue: 0.74, alpha: 1), // hoodie blue
            "Y": UIColor(red: 0.96, green: 0.82, blue: 0.20, alpha: 1), // tee yellow
        ]
        return pixelPortrait(rows: rows, colors: colors)
    }

    /// Tree Spirit: leafy crown, bark-textured face, glowing yellow eyes.
    static func makeSpiritPortraitTexture() -> SKTexture {
        let rows = [
            "....LL..LL.LL...",
            "...LLLLLLLLLLL..",
            "..LLGGLLGGGLLLL.",
            ".LLGGGGGGGGGGLL.",
            ".LBBBBBBBBBBBBL.",
            ".BBBBBBBBBBBBBB.",
            ".BBYYBBBBBBYYBB.",
            ".BYWYBBBBBBYWYB.", // bright pupils
            ".BBYYBBBBBBYYBB.",
            ".BBBBBBKKBBBBBB.", // nose / wood knot
            ".BBBBMMOOMMBBBB.",
            ".BBBMMMMMMMMBBB.", // jagged mouth
            ".BBBBBBBBBBBBBB.",
            "..KKBBBBBBBBKK..",
            "..KKKKKKKKKKKK..",
            "...KK......KK...",
        ]
        let colors: [Character: UIColor] = [
            "L": UIColor(red: 0.14, green: 0.32, blue: 0.18, alpha: 1), // dark leaves
            "G": UIColor(red: 0.32, green: 0.56, blue: 0.28, alpha: 1), // light leaves
            "B": UIColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1), // bark
            "K": UIColor(red: 0.20, green: 0.12, blue: 0.06, alpha: 1), // dark bark
            "Y": UIColor(red: 0.98, green: 0.82, blue: 0.20, alpha: 1), // glow ring
            "W": UIColor(red: 1.00, green: 0.98, blue: 0.70, alpha: 1), // bright pupil
            "M": UIColor(red: 0.10, green: 0.06, blue: 0.04, alpha: 1), // mouth dark
            "O": UIColor(red: 0.85, green: 0.40, blue: 0.10, alpha: 1), // inner mouth ember
        ]
        return pixelPortrait(rows: rows, colors: colors)
    }

    // MARK: - UI

    private func setupUI() {
        // Bit-Wood Brawler design-system colors
        let dsPrimary  = SKColor(red: 0.102, green: 0.039, blue: 0.016, alpha: 1) // #1a0a04
        let dsGold     = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // #f0c060
        let dsIronGray = SKColor(red: 0.349, green: 0.349, blue: 0.349, alpha: 1) // #595959

        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let topH: CGFloat    = 48
        let bottomH: CGFloat = max(40, size.height * 0.08)
        // Panel sits immediately below the safe-area inset (Dynamic Island / notch)
        let panelTopY = size.height / 2 - topInset
        let topBarY   = panelTopY - topH / 2
        let botBarY   = -size.height / 2 + bottomH / 2

        // ── Top HUD ribbon ────────────────────────────────────────────────
        // Extend the background up through the safe-area inset so the notch stays dark
        let totalTopH = topH + topInset
        let topBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: size.width, height: totalTopH))
        topBar.position  = CGPoint(x: 0, y: size.height / 2 - totalTopH / 2)
        topBar.zPosition = 500
        addChild(topBar)

        // 2px gold bottom border at the bottom edge of the visible 48pt ribbon
        let topBorder = SKSpriteNode(color: dsGold,
                                     size: CGSize(width: size.width, height: 2))
        topBorder.position  = CGPoint(x: 0, y: topBarY - topH / 2)
        topBorder.zPosition = 501
        addChild(topBorder)

        // Zone A (left): pause icon
        let pauseBtn = SKSpriteNode(imageNamed: "pauseIcon")
        pauseBtn.size     = CGSize(width: 22, height: 22)
        pauseBtn.position = CGPoint(x: -size.width / 2 + 22, y: topBarY)
        pauseBtn.zPosition = 502
        pauseBtn.name     = "pauseBtn"
        addChild(pauseBtn)

        // Tutorial help button just right of pause
        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -size.width / 2 + 52, y: topBarY)
        addChild(help)

        // Zone B (center): combined score label
        let scoreLabel = makeLabel(text: "YOU: 0 | OPP: 0", size: 9, color: dsGold)
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.position  = CGPoint(x: 0, y: topBarY)
        scoreLabel.zPosition = 502
        addChild(scoreLabel)
        playerScoreLabel = scoreLabel

        // Zone C (right): SK close button using closeIcon image
        let closeBtn = SKSpriteNode(imageNamed: "closeIcon")
        closeBtn.size      = CGSize(width: 22, height: 22)
        closeBtn.position  = CGPoint(x: size.width / 2 - 22, y: topBarY)
        closeBtn.zPosition = 502
        closeBtn.name      = "closeButton"
        addChild(closeBtn)

        // Iron bolts — corners of the visible 48pt ribbon
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: topBarY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: topBarY + topH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: topBarY - topH / 2 + 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: topBarY - topH / 2 + 5), color: dsIronGray)

        // ── Bottom bar ────────────────────────────────────────────────────
        let botBar = SKSpriteNode(color: dsPrimary,
                                  size: CGSize(width: size.width, height: bottomH))
        botBar.position  = CGPoint(x: 0, y: botBarY)
        botBar.zPosition = 500
        addChild(botBar)

        // 2px gold top border
        let botBorder = SKSpriteNode(color: dsGold,
                                     size: CGSize(width: size.width, height: 2))
        botBorder.position  = CGPoint(x: 0, y: botBarY + bottomH / 2)
        botBorder.zPosition = 501
        addChild(botBorder)

        // Weather / wind — centered, gold
        let wLabel = makeLabel(text: "CALM", size: 9, color: dsGold)
        wLabel.horizontalAlignmentMode = .center
        wLabel.position  = CGPoint(x: 0, y: botBarY)
        wLabel.zPosition = 502
        addChild(wLabel)
        windLabel = wLabel

        // Round bag counters — opponent count beside opponent portrait (left side),
        // player count beside Jeff portrait (right side). Portraits are placed in
        // addPlayerPortrait() / addOpponentPortrait() at x = ±(W/2 - 28).
        let rndALabel = makeLabel(text: "", size: 9,
                                  color: SKColor(red: 0.40, green: 0.60, blue: 0.90, alpha: 1))
        rndALabel.horizontalAlignmentMode = .left
        rndALabel.position  = CGPoint(x: -size.width / 2 + 56, y: botBarY)
        rndALabel.zPosition = 502
        rndALabel.name = "rndAILabel"
        addChild(rndALabel)

        let rndPLabel = makeLabel(text: "", size: 9,
                                  color: SKColor(red: 0.90, green: 0.42, blue: 0.42, alpha: 1))
        rndPLabel.horizontalAlignmentMode = .right
        rndPLabel.position  = CGPoint(x: size.width / 2 - 56, y: botBarY)
        rndPLabel.zPosition = 502
        rndPLabel.name = "rndPlayerLabel"
        addChild(rndPLabel)

        addPlayerPortrait()

        // Iron bolts — bottom corners
        addIronBolt(at: CGPoint(x: -size.width / 2 + 5, y: botBarY + bottomH / 2 - 5), color: dsIronGray)
        addIronBolt(at: CGPoint(x:  size.width / 2 - 5, y: botBarY + bottomH / 2 - 5), color: dsIronGray)

        // ── Turn indicator ─────────────────────────────────────────────────
        let indTex = SKTexture(imageNamed: "bag_16bit")
        indTex.filteringMode = .nearest
        let indicator = SKSpriteNode(texture: indTex, size: CGSize(width: 50, height: 50))
        indicator.color            = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
        indicator.colorBlendFactor = 0.65
        indicator.position  = CGPoint(x: 0, y: throwLineY)
        indicator.zPosition = 30
        gameWorldNode.addChild(indicator)
        turnIndicator = indicator

        indicator.run(SKAction.repeatForever(.sequence([
            .scale(to: 1.18, duration: 0.55),
            .scale(to: 1.00, duration: 0.55),
        ])))

        setupSatchelButton()
        addCrtOverlay()
    }

    private func addIronBolt(at pt: CGPoint, color: SKColor) {
        let bolt = SKSpriteNode(color: color, size: CGSize(width: 4, height: 4))
        bolt.position  = pt
        bolt.zPosition = 503
        addChild(bolt)
    }

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
        overlay.zPosition = 800
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    private func makeLabel(text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.fontSize = size
        l.fontColor = color
        l.text = text
        l.verticalAlignmentMode = .center
        return l
    }

    private func makeButton(label: String, fg: SKColor, bg: SKColor, size: CGSize) -> SKNode {
        let n = SKNode()
        let backing = SKSpriteNode(color: bg, size: size)
        backing.zPosition = 0
        n.addChild(backing)
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.fontSize = 10
        lbl.fontColor = fg
        lbl.text = label
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        lbl.zPosition = 1
        n.addChild(lbl)
        return n
    }

    // MARK: - Satchel

    /// Returns the special bag types the player currently has available for cornhole.
    private var satchelItems: [(type: ItemType, count: Int)] {
        [(type: .honeyBag,  count: availableHoneyBags),
         (type: .bombBag,   count: availableBombBags),
         (type: .magicBag,  count: availableMagicBags),
         (type: .fireBag,   count: availableFireBags),
         (type: .goldenBag, count: availableGoldenBags)]
            .filter { $0.count > 0 }
    }

    private func isItemSelected(_ type: ItemType) -> Bool {
        switch type {
        case .honeyBag:  return honeyBagSelected
        case .bombBag:   return bombBagSelected
        case .magicBag:  return magicBagSelected
        case .fireBag:   return fireBagSelected
        case .goldenBag: return goldenBagSelected
        default:         return false
        }
    }

    /// Pixel-art satchel icon button in the lower-right corner above the bottom chrome.
    /// Visible whenever the player carries at least one special bag.
    private func setupSatchelButton() {
        let bottomH: CGFloat = max(40, size.height * 0.08)
        let iconW: CGFloat = 38, iconH: CGFloat = 36

        let btn = SKNode()
        btn.name      = "satchelButton"
        btn.position  = CGPoint(x: size.width / 2 - iconW / 2 - 8,
                                y: -size.height / 2 + bottomH + iconH / 2 + 6)
        btn.zPosition = 600

        // Pouch body
        let body = SKSpriteNode(color: SKColor(red: 0.28, green: 0.15, blue: 0.05, alpha: 0.95),
                                size: CGSize(width: iconW, height: iconH))
        body.zPosition = 0
        btn.addChild(body)

        // Flap (upper portion, slightly lighter)
        let flap = SKSpriteNode(color: SKColor(red: 0.44, green: 0.25, blue: 0.08, alpha: 1.0),
                                size: CGSize(width: iconW, height: iconH * 0.38))
        flap.position = CGPoint(x: 0, y: iconH * 0.31)
        flap.zPosition = 1
        btn.addChild(flap)

        // Clasp — gold square centred on the flap
        let clasp = SKSpriteNode(color: SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1.0),
                                 size: CGSize(width: 8, height: 6))
        clasp.position = CGPoint(x: 0, y: iconH * 0.31)
        clasp.zPosition = 2
        btn.addChild(clasp)

        // Item-count badge at the bottom of the body
        let countTotal = satchelItems.reduce(0) { $0 + $1.count }
        let badge = SKLabelNode(fontNamed: "PressStart2P-Regular")
        badge.name                   = "satchelCountBadge"
        badge.fontSize               = 7
        badge.fontColor              = SKColor(white: 0.90, alpha: 1)
        badge.text                   = "×\(countTotal)"
        badge.verticalAlignmentMode  = .center
        badge.horizontalAlignmentMode = .center
        badge.position               = CGPoint(x: 0, y: -iconH * 0.28)
        badge.zPosition              = 3
        btn.addChild(badge)

        // Selected-item indicator dot (hidden until something is armed)
        let dot = SKSpriteNode(color: .clear, size: CGSize(width: 8, height: 8))
        dot.name      = "satchelSelectedDot"
        dot.position  = CGPoint(x: iconW / 2 - 5, y: -iconH / 2 + 5)
        dot.zPosition = 4
        btn.addChild(dot)

        btn.isHidden = satchelItems.isEmpty
        addChild(btn)
        satchelButton = btn
    }

    /// Syncs the satchel button appearance with current selection / count state.
    private func updateSatchelButton() {
        guard let btn = satchelButton else { return }

        if satchelItems.isEmpty {
            honeyBagSelected  = false
            bombBagSelected   = false
            magicBagSelected  = false
            fireBagSelected   = false
            goldenBagSelected = false
            closeSatchelPanel()
            btn.isHidden = true
            return
        }
        btn.isHidden = false

        // Update count badge
        let countTotal = satchelItems.reduce(0) { $0 + $1.count }
        (btn.childNode(withName: "satchelCountBadge") as? SKLabelNode)?.text = "×\(countTotal)"

        // Selected indicator dot: coloured when something is armed, clear otherwise
        let dot = btn.childNode(withName: "satchelSelectedDot") as? SKSpriteNode
        if honeyBagSelected {
            dot?.color = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1.0)  // amber
        } else if bombBagSelected {
            dot?.color = SKColor(red: 0.90, green: 0.20, blue: 0.10, alpha: 1.0)  // red
        } else if magicBagSelected {
            dot?.color = SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1.0)  // green
        } else if fireBagSelected {
            dot?.color = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1.0)  // orange-red
        } else if goldenBagSelected {
            dot?.color = SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1.0)  // bright gold
        } else {
            dot?.color = .clear
        }
    }

    /// Opens a panel anchored to the right side; slides up from below and stays open
    /// until the user taps the X button. Tapping a bag arms it as the active bag type.
    private func openSatchelPanel() {
        closeSatchelPanel()
        guard !satchelItems.isEmpty else { return }
        satchelOpen = true

        let rowH: CGFloat    = 44
        let panelW: CGFloat  = min(size.width * 0.52, 190)
        let titleH: CGFloat  = 32
        let padding: CGFloat = 10
        let panelH           = titleH + rowH * CGFloat(satchelItems.count) + padding * 2

        // Anchor just above the satchel button in the bottom-right corner.
        let bottomH: CGFloat = max(40, size.height * 0.08)
        let iconH:   CGFloat = 36
        let btnTopY  = -size.height / 2 + bottomH + iconH + 6   // top edge of satchel button
        let finalY   = btnTopY + 6 + panelH / 2                 // panel sits 6 pt above button
        let startY   = finalY - 12                              // rises 12 pt on open
        let panelX   = size.width / 2 - panelW / 2 - 8         // right-aligned

        let panel = SKNode()
        panel.name      = "satchelPanel"
        panel.position  = CGPoint(x: panelX, y: startY)
        panel.zPosition = 650
        addChild(panel)
        satchelPanel = panel

        // Dark backing — named so stray taps on it are swallowed
        let bg = SKSpriteNode(color: SKColor(red: 0.06, green: 0.03, blue: 0.01, alpha: 0.97),
                              size: CGSize(width: panelW, height: panelH))
        bg.name      = "satchelPanelBg"
        bg.zPosition = 0
        panel.addChild(bg)

        // Gold border
        let border = SKShapeNode(rectOf: CGSize(width: panelW + 2, height: panelH + 2),
                                 cornerRadius: 3)
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 2
        border.zPosition   = 1
        panel.addChild(border)

        let fs = max(7, size.width * 0.038)
        let titleY = panelH / 2 - padding - titleH / 2

        // Title label (left-of-centre to leave room for X)
        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.fontSize                = fs * 0.68
        title.fontColor               = SKColor(red: 0.95, green: 0.75, blue: 0.38, alpha: 1)
        title.text                    = "BAGS"
        title.verticalAlignmentMode   = .center
        title.horizontalAlignmentMode = .left
        title.position  = CGPoint(x: -panelW / 2 + 10, y: titleY)
        title.zPosition = 2
        panel.addChild(title)

        // X close button — top-right of title bar
        let xBtn = SKNode()
        xBtn.name      = "satchelCloseBtn"
        xBtn.position  = CGPoint(x: panelW / 2 - 16, y: titleY)
        xBtn.zPosition = 3
        panel.addChild(xBtn)

        let xBg = SKSpriteNode(color: SKColor(red: 0.28, green: 0.08, blue: 0.04, alpha: 0.85),
                               size: CGSize(width: 22, height: 22))
        xBg.zPosition = 0
        xBtn.addChild(xBg)

        let xPath = CGMutablePath()
        let xi: CGFloat = 5
        xPath.move(to: CGPoint(x: -xi, y: -xi)); xPath.addLine(to: CGPoint(x: xi, y:  xi))
        xPath.move(to: CGPoint(x:  xi, y: -xi)); xPath.addLine(to: CGPoint(x: -xi, y: xi))
        let xShape = SKShapeNode(path: xPath)
        xShape.strokeColor = SKColor(red: 0.95, green: 0.35, blue: 0.25, alpha: 1)
        xShape.lineWidth   = 2
        xShape.lineCap     = .round
        xShape.zPosition   = 1
        xBtn.addChild(xShape)

        // Divider below title
        let divider = SKSpriteNode(color: SKColor(red: 0.50, green: 0.35, blue: 0.15, alpha: 0.55),
                                   size: CGSize(width: panelW - 12, height: 1))
        divider.position  = CGPoint(x: 0, y: panelH / 2 - padding - titleH)
        divider.zPosition = 2
        panel.addChild(divider)

        // One row per item
        let rowsTop = panelH / 2 - padding - titleH - rowH / 2
        for (idx, item) in satchelItems.enumerated() {
            let rowY = rowsTop - rowH * CGFloat(idx)
            let row  = SKNode()
            row.name      = "satchelItem_\(item.type.rawValue)"
            row.position  = CGPoint(x: 0, y: rowY)
            row.zPosition = 2
            panel.addChild(row)

            let isSelected = isItemSelected(item.type)
            let selColor: SKColor
            let checkColor: SKColor
            switch item.type {
            case .bombBag:
                selColor   = SKColor(red: 0.28, green: 0.04, blue: 0.04, alpha: 0.90)
                checkColor = SKColor(red: 0.90, green: 0.20, blue: 0.10, alpha: 1)
            case .magicBag:
                selColor   = SKColor(red: 0.04, green: 0.28, blue: 0.10, alpha: 0.90)
                checkColor = SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1)
            case .fireBag:
                selColor   = SKColor(red: 0.28, green: 0.06, blue: 0.01, alpha: 0.90)
                checkColor = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)
            default:
                selColor   = SKColor(red: 0.28, green: 0.18, blue: 0.04, alpha: 0.90)
                checkColor = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)
            }
            let rowBg = SKSpriteNode(
                color: isSelected ? selColor : SKColor(white: 1, alpha: 0.04),
                size: CGSize(width: panelW - 8, height: rowH - 6))
            rowBg.name      = "satchelRowBg_\(item.type.rawValue)"
            rowBg.zPosition = 0
            row.addChild(rowBg)

            // Selection circle
            let check = SKShapeNode(circleOfRadius: 6)
            check.name        = "satchelCheck_\(item.type.rawValue)"
            check.strokeColor = isSelected ? checkColor : SKColor(white: 0.45, alpha: 1)
            check.fillColor   = isSelected ? checkColor.withAlphaComponent(0.30) : .clear
            check.lineWidth   = 1.5
            check.position    = CGPoint(x: -panelW / 2 + 16, y: 0)
            check.zPosition   = 1
            row.addChild(check)

            // Coloured bag icon
            let icon = SKSpriteNode(color: item.type.color, size: CGSize(width: 11, height: 11))
            icon.position  = CGPoint(x: -panelW / 2 + 34, y: 0)
            icon.zPosition = 1
            row.addChild(icon)

            // Name + count
            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.name                    = "satchelLbl_\(item.type.rawValue)"
            lbl.fontSize                = fs * 0.60
            lbl.fontColor               = isSelected ? SKColor(white: 1.0, alpha: 1) : SKColor(white: 0.80, alpha: 1)
            lbl.text                    = "\(item.type.displayName) ×\(item.count)"
            lbl.verticalAlignmentMode   = .center
            lbl.horizontalAlignmentMode = .left
            lbl.position                = CGPoint(x: -panelW / 2 + 48, y: 0)
            lbl.zPosition               = 1
            row.addChild(lbl)
        }

        // Pop up from just below its resting position
        panel.alpha = 0
        let rise = SKAction.move(to: CGPoint(x: panelX, y: finalY), duration: 0.15)
        rise.timingMode = .easeOut
        panel.run(SKAction.group([.fadeIn(withDuration: 0.15), rise]))
    }

    /// Fades the panel out with a short drop then removes it.
    private func closeSatchelPanel() {
        satchelOpen = false

        if let panel = satchelPanel {
            satchelPanel = nil
            let drop = SKAction.moveBy(x: 0, y: -8, duration: 0.12)
            drop.timingMode = .easeIn
            panel.run(SKAction.sequence([
                SKAction.group([drop, .fadeOut(withDuration: 0.12)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Updates row visuals and counts in-place to reflect the current selection and inventory state.
    private func refreshSatchelPanelRows() {
        guard let panel = satchelPanel else { return }
        let allItems: [(type: ItemType, count: Int)] = [
            (.honeyBag,  availableHoneyBags),
            (.bombBag,   availableBombBags),
            (.magicBag,  availableMagicBags),
            (.fireBag,   availableFireBags),
            (.goldenBag, availableGoldenBags),
        ]
        for item in allItems {
            let isSelected = isItemSelected(item.type)
            let key = item.type.rawValue
            let checkColor: SKColor
            let selBg: SKColor
            switch item.type {
            case .bombBag:
                checkColor = SKColor(red: 0.90, green: 0.20, blue: 0.10, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.04, blue: 0.04, alpha: 0.90)
            case .magicBag:
                checkColor = SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1)
                selBg      = SKColor(red: 0.04, green: 0.28, blue: 0.10, alpha: 0.90)
            case .fireBag:
                checkColor = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.06, blue: 0.01, alpha: 0.90)
            case .goldenBag:
                checkColor = SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.22, blue: 0.01, alpha: 0.90)
            default:
                checkColor = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)
                selBg      = SKColor(red: 0.28, green: 0.18, blue: 0.04, alpha: 0.90)
            }

            if let rowBg = panel.childNode(withName: "//satchelRowBg_\(key)") as? SKSpriteNode {
                rowBg.color = isSelected ? selBg : SKColor(white: 1, alpha: 0.04)
            }
            if let check = panel.childNode(withName: "//satchelCheck_\(key)") as? SKShapeNode {
                check.strokeColor = isSelected ? checkColor : SKColor(white: 0.45, alpha: 1)
                check.fillColor   = isSelected ? checkColor.withAlphaComponent(0.30) : .clear
            }
            if let lbl = panel.childNode(withName: "//satchelLbl_\(key)") as? SKLabelNode {
                lbl.fontColor = isSelected ? SKColor(white: 1.0, alpha: 1) : SKColor(white: 0.80, alpha: 1)
                lbl.text = "\(item.type.displayName) ×\(item.count)"
            }
        }
    }

    /// Arms or disarms a special bag type. Count decrements immediately on arm; refunds on disarm.
    /// Only one type can be armed at a time — arming a new type disarms the previous one.
    private func selectSatchelItem(_ type: ItemType) {
        switch type {
        case .honeyBag:
            if honeyBagSelected {
                honeyBagSelected = false
                availableHoneyBags += 1
            } else if availableHoneyBags > 0 {
                if bombBagSelected   { bombBagSelected   = false; availableBombBags   += 1 }
                if magicBagSelected  { magicBagSelected  = false; availableMagicBags  += 1 }
                if fireBagSelected   { fireBagSelected   = false; availableFireBags   += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                honeyBagSelected = true
                availableHoneyBags -= 1
            }
        case .bombBag:
            if bombBagSelected {
                bombBagSelected = false
                availableBombBags += 1
            } else if availableBombBags > 0 {
                if honeyBagSelected  { honeyBagSelected  = false; availableHoneyBags  += 1 }
                if magicBagSelected  { magicBagSelected  = false; availableMagicBags  += 1 }
                if fireBagSelected   { fireBagSelected   = false; availableFireBags   += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                bombBagSelected = true
                availableBombBags -= 1
            }
        case .magicBag:
            if magicBagSelected {
                magicBagSelected = false
                availableMagicBags += 1
            } else if availableMagicBags > 0 {
                if honeyBagSelected  { honeyBagSelected  = false; availableHoneyBags  += 1 }
                if bombBagSelected   { bombBagSelected   = false; availableBombBags   += 1 }
                if fireBagSelected   { fireBagSelected   = false; availableFireBags   += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                magicBagSelected = true
                availableMagicBags -= 1
            }
        case .fireBag:
            if fireBagSelected {
                fireBagSelected = false
                availableFireBags += 1
            } else if availableFireBags > 0 {
                if honeyBagSelected  { honeyBagSelected  = false; availableHoneyBags  += 1 }
                if bombBagSelected   { bombBagSelected   = false; availableBombBags   += 1 }
                if magicBagSelected  { magicBagSelected  = false; availableMagicBags  += 1 }
                if goldenBagSelected { goldenBagSelected = false; availableGoldenBags += 1 }
                fireBagSelected = true
                availableFireBags -= 1
            }
        case .goldenBag:
            if goldenBagSelected {
                goldenBagSelected = false
                availableGoldenBags += 1
            } else if availableGoldenBags > 0 {
                if honeyBagSelected { honeyBagSelected = false; availableHoneyBags += 1 }
                if bombBagSelected  { bombBagSelected  = false; availableBombBags  += 1 }
                if magicBagSelected { magicBagSelected = false; availableMagicBags += 1 }
                if fireBagSelected  { fireBagSelected  = false; availableFireBags  += 1 }
                goldenBagSelected = true
                availableGoldenBags -= 1
            }
        default:
            break
        }
        updateSatchelButton()
        updateTurnIndicator()
        refreshSatchelPanelRows()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toggleHoneyBagSelection() {
        honeyBagSelected.toggle()
        updateSatchelButton()
        updateTurnIndicator()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Game Flow

    private func startRound() {
        roundNumber += 1

        // Tom's fart — deactivate any lingering effect first, then re-roll
        if tomFartActive { deactivateTomFart() }
        if selectedOpponent == .tom && Bool.random() { activateTomFart() }

        // Toggle rain on/off for this round
        let shouldRain = rainStartRound >= 0 && roundNumber >= rainStartRound && roundNumber < rainEndRound
        if shouldRain && !rainActive  { activateRain() }
        if !shouldRain && rainActive  { deactivateRain() }

        // Toggle storm on/off for this round
        let shouldStorm = stormStartRound >= 0 && roundNumber >= stormStartRound && roundNumber < stormEndRound
        if shouldStorm && !stormActive  { activateStorm() }
        if !shouldStorm && stormActive  { deactivateStorm() }

        // Storm brings stronger, more consistent wind
        if stormActive {
            let dir: CGFloat = Bool.random() ? 1 : -1
            wind = CGVector(dx: CGFloat.random(in: 3.5...5.5) * dir, dy: 0)
        } else {
            wind = CGVector(dx: CGFloat.random(in: -2.0...2.0), dy: 0)
        }
        updateWindLabel()

        playerBagsThrown    = 0
        aiBagsThrown        = 0
        hasCalculatedScore  = false
        honeyBagSelected    = false
        bombBagSelected     = false
        magicBagSelected    = false
        fireBagSelected     = false
        boardOnFire         = false
        holeFire            = false
        fireBoardOverlay?.removeFromParent()
        fireBoardOverlay    = nil
        gameWorldNode.childNode(withName: "fireBoardLabel")?.removeFromParent()
        gameWorldNode.childNode(withName: "fireBoardEmitter")?.removeFromParent()
        updateSatchelButton()
        refreshSatchelPanelRows()

        for bag in activeBags {
            bag.node.removeFromParent()
            bag.shadow.removeFromParent()
        }
        activeBags.removeAll()

        clearGopher()

        crowNode?.removeFromParent()
        crowNode = nil
        removeAction(forKey: "crowSchedule")

        removeAction(forKey: "dragonSchedule")
        removeAction(forKey: "dragonFlameScan")
        dragonNode?.removeFromParent()
        dragonNode = nil

        batNode?.removeAllActions()
        batNode?.removeFromParent()
        batNode = nil

        messageNode?.removeFromParent()
        messageNode = nil

        gameState = .playerTurn
        lastThrower = .ai
        targetX = 0
        turnIndicator?.isHidden = false

        updateScoreLabels()
        updateTurnIndicator()
        updateRoundLabels()

        // First throw of the round is the player's — give the gopher a chance.
        maybeStartGopher(for: .player)
        if isCaveMatch {
            scheduleDragon()        // no crows underground — a dragon stalks the chasm instead
        } else {
            scheduleCrow()
        }
    }

    private var allBagsThrown: Bool {
        playerBagsThrown >= bagsPerPlayer && aiBagsThrown >= bagsPerPlayer
    }

    private func handleTurnEnd() {
        guard gameState == .resolving else { return }

        // Reset the cornhole streak if the player's most recent throw missed the hole.
        if lastThrower == .player {
            let lastPlayerBag = activeBags.last(where: { $0.owner == .player })
            if lastPlayerBag?.hasScored != true {
                playerCornholeStreak = 0
            }
        }

        if allBagsThrown {
            calculateRoundScore()
        } else if lastThrower == .player {
            gameState = .aiTurn
            // Pre-commit AI start X so the gopher has a fixed target to chase.
            pendingAIStartX = CGFloat.random(in: -targetRange * 0.55...targetRange * 0.55)
            updateTurnIndicator()
            turnIndicator?.position.x = pendingAIStartX

            maybeStartGopher(for: .ai)
            // Give the gopher a longer wind-up so it has a real chance to win the race.
            let delay: TimeInterval = activeGopher == nil
                ? 0.50
                : TimeInterval.random(in: 1.0...1.8)
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in self?.aiThrow() },
            ]), withKey: "pendingAIThrow")
        } else {
            gameState = .playerTurn
            targetX = 0
            turnIndicator?.position.x = 0
            turnIndicator?.isHidden = false
            updateTurnIndicator()

            maybeStartGopher(for: .player)
        }
    }

    private func calculateRoundScore() {
        guard !hasCalculatedScore else { return }
        hasCalculatedScore = true

        if isCathyMatch { calculateCathyRoundScore(); return }

        var roundPlayer = 0
        var roundAI     = 0

        for bag in activeBags {
            guard !bag.isDestroyed else { continue }
            let isInHole  = bag.hasScored
            let isOnBoard = !isInHole && checkIsOnBoard(bag)
            let pts: Int
            if isInHole        { pts = bag.isGolden ? 6 : 3 }
            else if isOnBoard  { pts = bag.isGolden ? 2 : 1 }
            else               { pts = 0 }
            if bag.owner == .player { roundPlayer += pts }
            else                    { roundAI     += pts }
        }

        let net = roundPlayer - roundAI
        if net > 0 { playerScore += net }
        else if net < 0 { aiScore += abs(net) }

        // Billy adapts: tighten on player round wins, ease slightly on AI wins
        if selectedOpponent == .billy {
            if net > 0 {
                billyNoiseFactor = max(1.4, billyNoiseFactor - 0.12)
            } else if net < 0 {
                billyNoiseFactor = min(3.8, billyNoiseFactor + 0.15)
            }
        }

        updateScoreLabels()

        // Tree Spirit: once the player takes the lead, the storm calms but the
        // moonlit night tint stays. Disarm stormStartRound so it can't re-trigger.
        if selectedOpponent == .spirit && stormActive && playerScore > aiScore {
            stormStartRound = -1
            deactivateStorm(keepNightTint: true)
        }

        concludeRound { [weak self] in
            guard let self else { return }
            self.showRoundResultMessage(roundPlayer: roundPlayer, roundAI: roundAI)
        }
    }

    /// CathyX inverted scoring. A bag in the hole **nullifies the thrower's board
    /// points for the round** — so an opponent who lands 2 on the board AND sinks one
    /// can't cancel out your 4 board bags; her board contribution this round becomes 0
    /// and you get the full +4. Round-only effect, no cumulative penalty. Board points
    /// then settle by cancellation as normal. Symmetric: applies to both player and
    /// CathyX.
    private func calculateCathyRoundScore() {
        var playerBoard = 0, aiBoard = 0
        var playerSank  = false, aiSank = false

        for bag in activeBags {
            guard !bag.isDestroyed else { continue }
            if bag.hasScored {                       // dropped in the hole
                if bag.owner == .player { playerSank = true } else { aiSank = true }
            } else if checkIsOnBoard(bag) {          // rests on the board → normal points
                let pts = bag.isGolden ? 2 : 1
                if bag.owner == .player { playerBoard += pts } else { aiBoard += pts }
            }
        }

        // Hole-in nullifies that thrower's board points for the round.
        if playerSank { playerBoard = 0 }
        if aiSank     { aiBoard     = 0 }

        // Board points cancel out, using the post-nullification values.
        let boardNet = playerBoard - aiBoard
        if boardNet > 0      { playerScore += boardNet }
        else if boardNet < 0 { aiScore     += abs(boardNet) }

        updateScoreLabels()

        concludeRound { [weak self] in
            guard let self else { return }
            self.showCathyRoundResultMessage(boardNet: boardNet,
                                             playerSank: playerSank,
                                             aiSank: aiSank)
        }
    }

    /// Shared round-end tail: tear down on a win, otherwise play the round-end beat,
    /// show the supplied banner, and schedule the next round.
    private func concludeRound(showBanner: @escaping () -> Void) {
        if playerScore >= winScore || aiScore >= winScore {
            gameState = .gameOver
            removeAction(forKey: "crowSchedule")
            crowNode?.removeFromParent()
            crowNode = nil
            removeAction(forKey: "dragonSchedule")
            removeAction(forKey: "dragonFlameScan")
            dragonNode?.removeAction(forKey: "dragonAct")
            dragonNode?.removeFromParent()
            dragonNode = nil
            batNode?.removeAllActions()
            batNode?.removeFromParent()
            batNode = nil
            // PLACEHOLDER: add game_win.wav / game_lose.wav to Copy Bundle Resources
            let resultSound = playerScore > aiScore ? "game_win.wav" : "game_lose.wav"
            run(SKAction.playSoundFileNamed(resultSound, waitForCompletion: false))
            run(SKAction.wait(forDuration: 0.6)) { [weak self] in
                guard let s = self else { return }
                s.showGameOverPanel(playerWon: s.playerScore > s.aiScore)
            }
        } else {
            // PLACEHOLDER: add round_end.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("round_end.wav", waitForCompletion: false))
            showBanner()
            run(SKAction.wait(forDuration: 2.4)) { [weak self] in self?.startRound() }
        }
    }

    // MARK: - Physics update

    override func update(_ currentTime: TimeInterval) {
        guard !isPausedGame else { return }
        let dt: CGFloat = 1.0 / 60.0

        if gameState == .playerTurn {
            updateTargetOscillation(dt: dt)
        }

        var anyMoving = false
        for bag in activeBags {
            if !bag.isGrounded || bag.isMoving {
                updateBagPhysics(bag, dt: dt)
            }
            // Soft-bag deformation spring runs every frame — even for a grounded,
            // stationary bag — so its landing jiggle keeps settling after the bag
            // stops moving. Pure visual; does not touch position or scoring.
            updateBagDeform(bag, dt: dt)
            if bag.isMoving { anyMoving = true }
        }

        resolveBagCollisions()

        // Re-check movement after collisions may have woken grounded bags
        for bag in activeBags where bag.isMoving { anyMoving = true }

        updateGopher(dt: dt)
        checkCrowCollisions()

        updateRoundLabels()

        if gameState == .resolving && !anyMoving {
            handleTurnEnd()
        }
    }

    // Elastic bag-to-bag collision — bags knock each other around on the board
    // and on the ground, and a well-aimed bag can push another into the hole.
    private func resolveBagCollisions() {
        let bagRadius: CGFloat = 22           // collision half-size (slightly under visual half)
        let minDist:   CGFloat = bagRadius * 2
        let restitution: CGFloat = 0.68       // bounciness: 0 = dead stop, 1 = fully elastic

        for i in 0..<activeBags.count {
            for j in (i + 1)..<activeBags.count {
                let a = activeBags[i]
                let b = activeBags[j]

                guard !a.hasScored && !b.hasScored else { continue }
                guard !a.isDestroyed && !b.isDestroyed else { continue }

                // Bags that fell off the board are locked in place — skip
                guard !a.hasAppliedGroundScale && !b.hasAppliedGroundScale else { continue }

                // Bat-carried bags are action-driven; physics has no say while in the bat's claws.
                guard !a.isCarriedByBat && !b.isCarriedByBat else { continue }

                // Honey bags are sticky — they don't move when other bags hit them
                guard !a.isHoney && !b.isHoney else { continue }

                // Ignore if one bag is flying well above the other
                guard abs(a.bz - b.bz) < bagRadius else { continue }

                let dx = b.bx - a.bx
                let dy = b.by - a.by
                let distSq = dx * dx + dy * dy
                guard distSq < minDist * minDist, distSq > 0.01 else { continue }

                let dist = sqrt(distSq)
                let nx = dx / dist   // collision normal
                let ny = dy / dist

                // Only resolve if the bags are approaching each other
                let dvx = b.vx - a.vx
                let dvy = b.vy - a.vy
                let relVel = dvx * nx + dvy * ny
                guard relVel < 0 else { continue }

                // Magic bag hits opponent bag — destroy the opponent bag, magic bag continues.
                // Golden bags are fully immune to magic bag effects.
                let aMagicVsB = a.isMagic && b.owner != a.owner && !b.isGolden
                let bMagicVsA = b.isMagic && a.owner != b.owner && !a.isGolden
                if aMagicVsB || bMagicVsA {
                    if aMagicVsB { destroyBag(b); showMagicPoof(at: CGPoint(x: b.bx, y: b.by)) }
                    if bMagicVsA { destroyBag(a); showMagicPoof(at: CGPoint(x: a.bx, y: a.by)) }
                    continue
                }

                // Equal-mass impulse
                let impulse = -(1.0 + restitution) * relVel * 0.5
                a.vx -= impulse * nx;  a.vy -= impulse * ny
                b.vx += impulse * nx;  b.vy += impulse * ny

                // Soft-bag squish on contact, scaled by impact strength (pure visual).
                // `max` so a harder existing deform isn't softened; zeroing deformV lets
                // the spring recoil into a jiggle.
                let dKick = min(0.60, abs(impulse) * 0.09)
                a.deform = max(a.deform, dKick); a.deformV = 0
                b.deform = max(b.deform, dKick); b.deformV = 0

                // Tier 3: each bag drapes away along the collision normal.
                kickWarp(a, worldDX: -nx, worldDY: -ny, strength: abs(impulse) * 0.05)
                kickWarp(b, worldDX:  nx, worldDY:  ny, strength: abs(impulse) * 0.05)

                // Un-ground board bags so they slide freely after impact
                a.isGrounded = false
                b.isGrounded = false

                // Positional correction — push apart so they no longer overlap
                let correction = (minDist - dist) * 0.5
                a.bx -= nx * correction;  a.by -= ny * correction
                b.bx += nx * correction;  b.by += ny * correction
            }
        }
    }

    private func updateTargetOscillation(dt: CGFloat) {
        let step = targetSpeed * dt
        if targetMovingRight {
            targetX += step
            if targetX >= targetRange { targetX = targetRange; targetMovingRight = false }
        } else {
            targetX -= step
            if targetX <= -targetRange { targetX = -targetRange; targetMovingRight = true }
        }
        // During a fart round, add a jitter wobble so the indicator shakes unpredictably.
        var displayX = targetX
        if tomFartActive {
            fartWobbleTimer += dt
            displayX += sin(fartWobbleTimer * 14.0) * targetRange * 0.08
                      + CGFloat.random(in: -targetRange * 0.04...targetRange * 0.04)
        }
        turnIndicator?.position.x = displayX
    }

    private func updateBagPhysics(_ bag: MiniGameBag, dt: CGFloat) {
        // Carried by the cave bat — the action drives position, physics is paused.
        if bag.isCarriedByBat { return }
        // Airborne wind push — honey bags are immune (they're sticky)
        if bag.bz > 0, !bag.isHoney {
            bag.vx += wind.dx * dt * 0.07
        }

        // Integrate
        bag.vz -= gravityPerFrame
        bag.bx += bag.vx
        bag.by += bag.vy
        bag.bz += bag.vz

        bag.rot += bag.rotV
        bag.node.zRotation = bag.rot

        if bag.bz <= 0 {
            bag.bz = 0
            if checkIsOnBoard(bag) {
                // Haptic on first board touchdown
                if !bag.hasLanded {
                    bag.hasLanded = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
                }

                // Soft-bag slap: flatten proportional to the downward impact speed, then
                // let the spring pull it back (overshoot = jiggle). `bag.vz` here is still
                // the incoming velocity, before the bounce/stick logic below zeroes it.
                // `> 0.5` gates out the per-frame re-entry while a bag merely slides (vz≈0).
                if abs(bag.vz) > 0.5 {
                    bag.deform  = min(0.65, abs(bag.vz) * 0.03)
                    bag.deformV = 0
                    // Tier 3: drape in the direction it's sliding as it slaps down.
                    kickWarp(bag, worldDX: bag.vx, worldDY: bag.vy, strength: abs(bag.vz) * 0.02)
                }

                // Non-fire bags landing on a burning board are immediately destroyed
                if boardOnFire && !bag.isFire && !bag.isDestroyed {
                    destroyBag(bag)
                }

                if bag.isHoney {
                    // Honey bags stick on contact — no bounce, no slide, rain-immune
                    bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
                    bag.isGrounded = true
                } else {
                    // Small bounce then slide — rain makes the surface very slippery.
                    // Long-distance variant: friction (1-f) is tripled (half-slide × 1.5×).
                    let baseFriction: CGFloat = rainActive ? 0.968 : 0.92
                    let boardFriction: CGFloat = distanceScale < 1.0
                        ? 1.0 - (1.0 - baseFriction) * 3.0
                        : baseFriction
                    if abs(bag.vz) > 0.5 {
                        bag.vz = abs(bag.vz) * 0.18
                    } else {
                        bag.vz = 0
                        bag.isGrounded = true
                    }
                    bag.vx *= boardFriction
                    bag.vy *= boardFriction
                    bag.rotV *= rainActive ? 0.88 : 0.65
                }

                // Hole detection.
                // In the long-distance variant the hole radius is half-size, so a bag
                // sliding with moderate per-frame velocity can step *over* the hole
                // between frames without its center ever falling inside. Augment the
                // endpoint check with a segment-vs-circle sweep across the bag's
                // current-frame motion, gated by speed: genuinely fast bags still skip,
                // but "moving quickly" bags drop in.
                let dist = hypot(bag.bx - holeCenter.x, bag.by - holeCenter.y)
                var captured = dist <= holeRadius
                if !captured && distanceScale < 1.0 {
                    let speed = hypot(bag.vx, bag.vy)
                    let fastSkipSpeed: CGFloat = 7.0   // above this the bag still slides over
                    if speed < fastSkipSpeed {
                        // Segment from previous frame to current vs. hole circle.
                        let px = bag.bx - bag.vx
                        let py = bag.by - bag.vy
                        let dx = bag.vx, dy = bag.vy
                        let fx = px - holeCenter.x, fy = py - holeCenter.y
                        let a = dx*dx + dy*dy
                        let b = 2 * (fx*dx + fy*dy)
                        let c = fx*fx + fy*fy - holeRadius*holeRadius
                        let disc = b*b - 4*a*c
                        if a > 0.0001 && disc >= 0 {
                            let s = sqrt(disc)
                            let t1 = (-b - s) / (2 * a)
                            let t2 = (-b + s) / (2 * a)
                            if (t1 >= 0 && t1 <= 1) || (t2 >= 0 && t2 <= 1) || (t1 <= 0 && t2 >= 1) {
                                captured = true
                                // Snap into the hole so the sink animation looks centered.
                                bag.bx = holeCenter.x
                                bag.by = holeCenter.y
                            }
                        }
                    }
                }
                if captured && !bag.hasScored {
                    bag.hasScored  = true
                    CornholeStatsManager.shared.recordCornhole()
                    // In a CathyX match a hole-in is a penalty, not an achievement — no
                    // celebratory streak banner or fire-bag rewards for sinking it.
                    if bag.owner == .player && !isCathyMatch { handlePlayerCornholeStreak() }
                    bag.isGrounded = true
                    bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    // PLACEHOLDER: add hole_score.wav to Copy Bundle Resources
                    run(SKAction.playSoundFileNamed("hole_score.wav", waitForCompletion: false))
                    run(SKAction.playSoundFileNamed("cornhole.wav", waitForCompletion: false))
                    showHoleEffect(at: CGPoint(x: bag.bx, y: bag.by))
                    let sink = SKAction.sequence([
                        SKAction.group([
                            SKAction.scale(to: 0.3, duration: 0.20),
                            SKAction.fadeOut(withDuration: 0.20),
                        ]),
                        SKAction.hide(),
                    ])
                    bag.node.run(sink)
                    bag.shadow.run(SKAction.fadeOut(withDuration: 0.15))
                    // Bomb in hole: destroy opponent bags already scored in the hole
                    if bag.isBomb && !bag.hasBombed {
                        bag.hasBombed = true
                        triggerBombHole(by: bag.owner)
                    }
                    // Magic bag in hole: destroy opponent bags already scored in the hole
                    if bag.isMagic {
                        triggerMagicHole(by: bag.owner)
                    }
                    // Fire bag in hole: burn all other cornholes this round (3 pts kept by thrower)
                    if bag.isFire && !bag.hasTriggeredFire {
                        bag.hasTriggeredFire = true
                        triggerFireHole(by: bag.owner)
                    }
                    // Non-fire bag scoring in a hole-fire round is destroyed immediately
                    if holeFire && !bag.isFire && !bag.isDestroyed {
                        destroyBag(bag)
                    }
                } else if bag.isBomb && !bag.hasBombed && bag.isGrounded && checkIsOnBoard(bag) {
                    // Bomb rests on board surface: destroy opponent bags on the board
                    bag.hasBombed = true
                    triggerBombBoard(at: CGPoint(x: bag.bx, y: bag.by), by: bag.owner)
                } else if bag.isFire && !bag.hasTriggeredFire && bag.isGrounded && checkIsOnBoard(bag) {
                    // Fire bag rests on board: burn all other board bags this round
                    bag.hasTriggeredFire = true
                    triggerFireBoard(at: CGPoint(x: bag.bx, y: bag.by), by: bag.owner)
                }
            } else if isCaveMatch && bag.by <= caveChasmTopY && bag.by >= caveChasmBottomY {
                // Missed into Barnum's chasm — the bag plummets into the darkness (0 pts).
                fallIntoChasm(bag)
                return
            } else {
                // Lands off-board — stop dead and shrink to show depth vs. board level
                bag.isGrounded = true
                bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
                if !bag.hasAppliedGroundScale {
                    bag.hasAppliedGroundScale = true
                    // Tier 3: this bag is now action-owned (updateBagDeform skips it), so
                    // drop any active drape warp before it would freeze mid-flop.
                    bag.warpX = 0; bag.warpY = 0; bag.warpVX = 0; bag.warpVY = 0
                    bag.node.warpGeometry = nil
                    // Long-distance variant: bags resting on the ground render at a final
                    // on-screen scale of 0.45 (baseScale × distanceScale).
                    let groundScale: CGFloat = distanceScale < 1.0 ? 0.45 / distanceScale : 0.75
                    bag.baseScale = groundScale
                    // node/shadow setScale calls below are baseScale-only; updateBagVisuals will
                    // re-multiply by distanceScale on the next frame.
                    bag.node.run(SKAction.scale(to: groundScale * distanceScale, duration: 0.12))
                    bag.shadow.run(SKAction.scale(to: groundScale * distanceScale, duration: 0.12))
                }
            }
        }

        // Friction stop on board surface — rain raises the stop threshold so bags
        // slide until nearly stationary rather than snapping to a halt.
        let stopThreshold: CGFloat = rainActive ? 0.012 : 0.04
        if bag.isGrounded && abs(bag.vx) < stopThreshold && abs(bag.vy) < stopThreshold {
            bag.vx = 0; bag.vy = 0
        }

        // Render: visual Y elevated by z for arc perspective effect
        let visualY = bag.by + bag.bz * 0.50
        bag.node.position   = CGPoint(x: bag.bx, y: visualY)
        bag.shadow.position = CGPoint(x: bag.bx + bag.bz * 0.08, y: bag.by)

        // Node scale (including height perspective + soft-bag deform) is applied in
        // updateBagDeform, which runs every frame for live bags.
        bag.shadow.alpha   = max(0.08, 0.35 - bag.bz * 0.005)
        bag.shadow.setScale(max(0.5, 1.0 - bag.bz * 0.005) * distanceScale)

        // Depth sort: bags closer to camera (lower on screen) appear in front
        bag.node.zPosition = 20 + bag.bz * 0.1 - bag.by * 0.02
    }

    /// Ticks the soft-bag deformation spring and writes the bag's non-uniform scale.
    /// Pure visual: never touches bx/by/bz or scoring. Runs every frame for live bags;
    /// scored / destroyed / off-board bags keep the scale set by their own SKActions
    /// (sink, poof, off-board shrink), so we return early and leave them alone.
    private func updateBagDeform(_ bag: MiniGameBag, dt: CGFloat) {
        guard !bag.hasScored, !bag.isDestroyed, !bag.hasAppliedGroundScale else { return }
        if bag.isCarriedByBat { return }

        // Tier 2: while airborne and moving, hold a gentle tall-and-narrow stretch
        // (deform < 0) that reads as the bag leaning into its arc; it relaxes to 0 as
        // the bag slows and lands, where the landing slap (deform > 0) takes over.
        let speed = hypot(bag.vx, bag.vy)
        let flightTarget: CGFloat = bag.bz > 1 ? -min(0.26, speed * 0.028) : 0

        // Damped spring pulls `deform` toward its rest target. Underdamped (lower damping =
        // more overshoot/wobble before it settles). Stable at dt = 1/60.
        let stiffness: CGFloat = 240
        let damping:   CGFloat = 13
        bag.deformV += (-stiffness * (bag.deform - flightTarget) - damping * bag.deformV) * dt
        bag.deform  += bag.deformV * dt
        bag.deform   = max(-0.75, min(0.75, bag.deform))

        // Volume-preserving non-uniform scale layered on top of the height/base scale.
        // Applied in the bag's local frame (a square beanbag has no strong axis, so the
        // approximation reads naturally); true world-axis drape would need a mesh warp.
        let heightScale = 1.0 + bag.bz * 0.012
        let base = bag.baseScale * heightScale * distanceScale
        bag.node.xScale = base * (1 + bag.deform)
        bag.node.yScale = base * (1 - bag.deform * 0.88)

        // Tier 3: spring the directional warp vector back to rest. While it's meaningfully
        // displaced, rebuild the bag's mesh-warp grid so the leading edge drapes; once it
        // settles, drop the warp entirely so the sprite renders crisp (and no warp pass).
        let wStiff: CGFloat = 180
        let wDamp:  CGFloat = 10
        bag.warpVX += (-wStiff * bag.warpX - wDamp * bag.warpVX) * dt
        bag.warpVY += (-wStiff * bag.warpY - wDamp * bag.warpVY) * dt
        bag.warpX  += bag.warpVX * dt
        bag.warpY  += bag.warpVY * dt
        if abs(bag.warpX) > 0.004 || abs(bag.warpY) > 0.004 {
            bag.node.warpGeometry = makeDrapeGrid(warpX: bag.warpX, warpY: bag.warpY)
        } else if bag.node.warpGeometry != nil {
            bag.warpX = 0; bag.warpY = 0; bag.warpVX = 0; bag.warpVY = 0
            bag.node.warpGeometry = nil
        }
    }

    /// Kicks a bag's mesh-warp drape toward a world-space impact direction. Converts the
    /// world direction into the bag's local texture frame (undoing the sprite's spin) so
    /// the flop points the correct way regardless of how the bag is rotated. Sets the warp
    /// directly (not its velocity) for an instant drape that the spring then relaxes.
    private func kickWarp(_ bag: MiniGameBag, worldDX: CGFloat, worldDY: CGFloat, strength: CGFloat) {
        let mag = hypot(worldDX, worldDY)
        guard mag > 1e-4, strength > 0.001 else { return }
        let ux = worldDX / mag, uy = worldDY / mag
        let cosR = cos(bag.rot), sinR = sin(bag.rot)
        let lx =  ux * cosR + uy * sinR     // world → bag-local
        let ly = -ux * sinR + uy * cosR
        let s = min(0.34, strength)
        bag.warpX = lx * s;  bag.warpY = ly * s
        bag.warpVX = 0;      bag.warpVY = 0
    }

    /// Builds a 3×3 (`2×2` cell) warp grid in which the edge facing the warp direction
    /// drapes furthest while the trailing edge stays put — an asymmetric, organic flop.
    private func makeDrapeGrid(warpX: CGFloat, warpY: CGFloat) -> SKWarpGeometryGrid {
        let cols = 2, rows = 2
        let mag = hypot(warpX, warpY)
        let inv: CGFloat = mag > 1e-4 ? 1 / mag : 0
        let dx = warpX * inv, dy = warpY * inv      // unit warp direction
        var src: [SIMD2<Float>] = []; src.reserveCapacity(9)
        var dst: [SIMD2<Float>] = []; dst.reserveCapacity(9)
        for r in 0...rows {
            for c in 0...cols {
                let u = CGFloat(c) / CGFloat(cols)
                let v = CGFloat(r) / CGFloat(rows)
                src.append(SIMD2<Float>(Float(u), Float(v)))
                // How far this vertex sits toward the leading edge (0 at back/center).
                let lead = max(0, (u - 0.5) * dx + (v - 0.5) * dy)
                let k = 0.5 + lead * 2.2        // slight whole-bag lean + asymmetric drape
                let ex = min(1.6, max(-0.6, u + warpX * k))
                let ey = min(1.6, max(-0.6, v + warpY * k))
                dst.append(SIMD2<Float>(Float(ex), Float(ey)))
            }
        }
        return SKWarpGeometryGrid(columns: cols, rows: rows,
                                  sourcePositions: src, destinationPositions: dst)
    }

    private func checkIsOnBoard(_ bag: MiniGameBag) -> Bool {
        // Use 95% of board dimensions to match the visually scaled boardContainer
        abs(bag.bx) <= boardHalfW * 0.95 &&
        bag.by >= boardY - boardHalfH * 0.95 &&
        bag.by <= boardY + boardHalfH * 0.95
    }

    // MARK: - Bomb Bag

    /// Bomb lands on board surface: destroys all opponent bags resting on the board.
    private func triggerBombBoard(at pos: CGPoint, by owner: BagOwner) {
        let opponent: BagOwner = owner == .player ? .ai : .player
        var destroyed = 0
        for bag in activeBags where bag.owner == opponent && !bag.isDestroyed
                                  && bag.isGrounded && !bag.hasScored && checkIsOnBoard(bag) {
            destroyBag(bag)
            destroyed += 1
        }
        showBombExplosion(at: pos, label: destroyed > 0 ? "BOOM! \(destroyed) BAG\(destroyed == 1 ? "" : "S") GONE!" : "BOOM!")
    }

    /// Bomb scores in hole: destroys all opponent bags already scored in the hole.
    private func triggerBombHole(by owner: BagOwner) {
        let opponent: BagOwner = owner == .player ? .ai : .player
        var destroyed = 0
        for bag in activeBags where bag.owner == opponent && !bag.isDestroyed && bag.hasScored {
            destroyBag(bag)
            destroyed += 1
        }
        showBombExplosion(at: CGPoint(x: holeCenter.x, y: holeCenter.y),
                          label: destroyed > 0 ? "BOOM! \(destroyed) HOLE BAG\(destroyed == 1 ? "" : "S") GONE!" : "BOOM!")
    }

    private func destroyBag(_ bag: MiniGameBag) {
        bag.isDestroyed = true
        bag.vx = 0; bag.vy = 0; bag.vz = 0
        let pop = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 0.1, duration: 0.22),
                SKAction.fadeOut(withDuration: 0.22),
            ]),
            SKAction.removeFromParent(),
        ])
        bag.node.run(pop)
        bag.shadow.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.15),
            SKAction.removeFromParent(),
        ]))
    }

    private func showBombExplosion(at pos: CGPoint, label: String) {
        // Pixel particle burst
        let container = SKNode()
        container.position  = pos
        container.zPosition = 300
        addChild(container)

        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.40, blue: 0.10, alpha: 1),
            SKColor(red: 1.0, green: 0.80, blue: 0.10, alpha: 1),
            SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
        ]
        for _ in 0..<10 {
            let p = SKSpriteNode(color: colors.randomElement()!,
                                 size: CGSize(width: 5, height: 5))
            p.position = .zero
            container.addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 35...80)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * speed, y: sin(angle) * speed, duration: 0.38),
                    SKAction.fadeOut(withDuration: 0.38),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.45),
            SKAction.removeFromParent(),
        ]))

        // BOOM label
        let boom = makeLabel(text: label,
                             size: max(6, size.width * 0.048),
                             color: SKColor(red: 1.0, green: 0.35, blue: 0.10, alpha: 1))
        boom.position  = CGPoint(x: pos.x, y: pos.y + 22)
        boom.zPosition = 800
        boom.alpha     = 0
        boom.setScale(0.6)
        addChild(boom)
        boom.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.16),
                SKAction.fadeIn(withDuration: 0.16),
            ]),
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Magic Bag

    /// Magic bag scores in hole: destroys all opponent bags already in the hole this round.
    /// Golden bags in the hole are immune and cannot be removed by this effect.
    private func triggerMagicHole(by owner: BagOwner) {
        let opponent: BagOwner = owner == .player ? .ai : .player
        var destroyed = 0
        for bag in activeBags where bag.owner == opponent && !bag.isDestroyed && bag.hasScored && !bag.isGolden {
            destroyBag(bag)
            destroyed += 1
        }
        if destroyed > 0 {
            showMagicPoof(at: CGPoint(x: holeCenter.x, y: holeCenter.y))
            let lbl = makeLabel(
                text: "MAGIC! \(destroyed) CORNHOLE\(destroyed == 1 ? "" : "S") STOLEN!",
                size: max(6, size.width * 0.044),
                color: SKColor(red: 0.12, green: 0.92, blue: 0.42, alpha: 1))
            lbl.position  = CGPoint(x: 0, y: size.height * 0.14)
            lbl.zPosition = 800
            lbl.alpha     = 0
            addChild(lbl)
            lbl.run(SKAction.sequence([
                SKAction.fadeIn(withDuration: 0.18),
                SKAction.wait(forDuration: 1.2),
                SKAction.fadeOut(withDuration: 0.28),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Sparkle-poof visual when a magic bag destroys an opponent bag on contact.
    private func showMagicPoof(at pos: CGPoint) {
        let container = SKNode()
        container.position  = pos
        container.zPosition = 300
        addChild(container)

        let colors: [SKColor] = [
            SKColor(red: 0.12, green: 0.90, blue: 0.40, alpha: 1),
            SKColor(red: 0.60, green: 1.00, blue: 0.60, alpha: 1),
            SKColor(red: 1.00, green: 1.00, blue: 0.80, alpha: 1),
        ]
        for _ in 0..<8 {
            let p = SKSpriteNode(color: colors.randomElement()!,
                                 size: CGSize(width: 4, height: 4))
            p.position = .zero
            container.addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 25...55)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * speed, y: sin(angle) * speed, duration: 0.32),
                    SKAction.fadeOut(withDuration: 0.32),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.40),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Fire Bag

    /// Fire bag lands on board: this bag scores 1 pt; all other board bags this round are destroyed.
    private func triggerFireBoard(at pos: CGPoint, by owner: BagOwner) {
        boardOnFire = true
        showFireBoardOverlay()
        var destroyed = 0
        for bag in activeBags where !bag.isFire && !bag.isDestroyed
                                  && bag.isGrounded && !bag.hasScored && checkIsOnBoard(bag) {
            destroyBag(bag)
            destroyed += 1
        }
        showFireEffect(at: pos)
        let msg = destroyed > 0
            ? "FIRE! \(destroyed) BAG\(destroyed == 1 ? "" : "S") BURNED!"
            : "FIRE! BOARD ABLAZE!"
        showFireMessage(msg, at: CGPoint(x: 0, y: size.height * 0.14))
    }

    /// Fire bag scores in hole: this bag keeps its 3 pts; all other cornholes this round are destroyed.
    private func triggerFireHole(by owner: BagOwner) {
        holeFire = true
        var destroyed = 0
        for bag in activeBags where !bag.isFire && !bag.isDestroyed && bag.hasScored {
            destroyBag(bag)
            destroyed += 1
        }
        showFireEffect(at: CGPoint(x: holeCenter.x, y: holeCenter.y))
        let msg = destroyed > 0
            ? "FIRE! \(destroyed) CORNHOLE\(destroyed == 1 ? "" : "S") BURNED!"
            : "FIRE! HOLE ABLAZE!"
        showFireMessage(msg, at: CGPoint(x: 0, y: size.height * 0.14))
    }

    /// Orange-red particle burst — used for both board and hole fire triggers.
    private func showFireEffect(at pos: CGPoint) {
        let container = SKNode()
        container.position  = pos
        container.zPosition = 300
        addChild(container)

        let colors: [SKColor] = [
            SKColor(red: 1.0,  green: 0.90, blue: 0.10, alpha: 1),   // yellow
            SKColor(red: 1.0,  green: 0.45, blue: 0.05, alpha: 1),   // orange
            SKColor(red: 0.95, green: 0.15, blue: 0.05, alpha: 1),   // red
        ]
        for _ in 0..<14 {
            let p = SKSpriteNode(color: colors.randomElement()!,
                                 size: CGSize(width: CGFloat.random(in: 4...7),
                                              height: CGFloat.random(in: 4...7)))
            p.position = .zero
            container.addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 40...90)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * speed, y: sin(angle) * speed, duration: 0.42),
                    SKAction.fadeOut(withDuration: 0.42),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.50),
            SKAction.removeFromParent(),
        ]))
    }

    /// Floating orange-red message label.
    private func showFireMessage(_ text: String, at pos: CGPoint) {
        let lbl = makeLabel(text: text,
                            size: max(6, size.width * 0.046),
                            color: SKColor(red: 1.0, green: 0.38, blue: 0.05, alpha: 1))
        lbl.position  = pos
        lbl.zPosition = 800
        lbl.alpha     = 0
        lbl.setScale(0.6)
        addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.16),
                SKAction.fadeIn(withDuration: 0.16),
            ]),
            SKAction.wait(forDuration: 1.1),
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.removeFromParent(),
        ]))
    }

    /// Semi-transparent fire overlay drawn over the board while it's ablaze.
    private func showFireBoardOverlay() {
        guard fireBoardOverlay == nil else { return }

        // Base red-orange wash over the entire board
        let overlay = SKSpriteNode(color: SKColor(red: 1.0, green: 0.22, blue: 0.01, alpha: 0.55),
                                   size: CGSize(width: boardHalfW * 2, height: boardHalfH * 2))
        overlay.name      = "fireBoardOverlay"
        overlay.position  = CGPoint(x: 0, y: boardY)
        overlay.zPosition = 19
        overlay.alpha     = 0
        gameWorldNode.addChild(overlay)
        fireBoardOverlay  = overlay

        overlay.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.20),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.32, duration: 0.22),
                SKAction.fadeAlpha(to: 0.62, duration: 0.22),
            ])),
        ]))

        // Continuous ember particles rising from the board surface
        let emitter = SKNode()
        emitter.name      = "fireBoardEmitter"
        emitter.position  = CGPoint(x: 0, y: boardY - boardHalfH)
        emitter.zPosition = 21
        gameWorldNode.addChild(emitter)

        let emberColors: [SKColor] = [
            SKColor(red: 1.0,  green: 0.88, blue: 0.10, alpha: 1),
            SKColor(red: 1.0,  green: 0.45, blue: 0.05, alpha: 1),
            SKColor(red: 0.95, green: 0.12, blue: 0.02, alpha: 1),
        ]
        let spawnEmbers = SKAction.repeatForever(SKAction.sequence([
            SKAction.run { [weak self, weak emitter] in
                guard let self, let emitter else { return }
                for _ in 0..<3 {
                    let p = SKSpriteNode(
                        color: emberColors.randomElement()!,
                        size: CGSize(width: CGFloat.random(in: 3...6),
                                     height: CGFloat.random(in: 3...6)))
                    p.position = CGPoint(x: CGFloat.random(in: -self.boardHalfW...self.boardHalfW),
                                         y: 0)
                    p.zPosition = 1
                    p.alpha = 0
                    emitter.addChild(p)
                    let rise  = CGFloat.random(in: 28...70)
                    let drift = CGFloat.random(in: -18...18)
                    p.run(SKAction.sequence([
                        SKAction.group([
                            SKAction.fadeIn(withDuration: 0.08),
                            SKAction.moveBy(x: drift, y: rise, duration: 0.55),
                            SKAction.sequence([
                                SKAction.wait(forDuration: 0.20),
                                SKAction.fadeOut(withDuration: 0.35),
                            ]),
                        ]),
                        SKAction.removeFromParent(),
                    ]))
                }
            },
            SKAction.wait(forDuration: 0.08),
        ]))
        emitter.run(spawnEmbers, withKey: "embers")

        // "BOARD ON FIRE!" label pinned above the board
        let fireLbl = makeLabel(text: "🔥 BOARD ON FIRE! 🔥",
                                size: max(6, size.width * 0.042),
                                color: SKColor(red: 1.0, green: 0.38, blue: 0.05, alpha: 1))
        fireLbl.name      = "fireBoardLabel"
        fireLbl.position  = CGPoint(x: 0, y: boardY + boardHalfH + 18)
        fireLbl.zPosition = 22
        fireLbl.alpha     = 0
        gameWorldNode.addChild(fireLbl)
        fireLbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.20),
            SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.55, duration: 0.30),
                SKAction.fadeAlpha(to: 1.00, duration: 0.30),
            ])),
        ]))
    }

    // MARK: - Throwing

    private func throwBag(owner: BagOwner, startX: CGFloat, vx: CGFloat, vy: CGFloat, aiBomb: Bool = false) {
        // availableHoneyBags / availableBombBags / availableMagicBags / availableFireBags / availableGoldenBags
        // already decremented on arm.
        let useHoney  = owner == .player && honeyBagSelected
        let useBomb   = (owner == .player && bombBagSelected) || aiBomb
        let useMagic  = owner == .player && magicBagSelected
        let useFire   = owner == .player && fireBagSelected
        let useGolden = owner == .player && goldenBagSelected
        if useHoney {
            honeyBagsUsed += 1
            honeyBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if owner == .player && bombBagSelected {
            bombBagsUsed += 1
            bombBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if useMagic {
            magicBagsUsed += 1
            magicBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if useFire {
            fireBagsUsed += 1
            fireBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        if useGolden {
            goldenBagsUsed += 1
            goldenBagSelected = false
            updateSatchelButton(); refreshSatchelPanelRows()
        }
        let bag = MiniGameBag(owner: owner, startX: startX, startY: throwLineY,
                              isHoney: useHoney, isBomb: useBomb, isMagic: useMagic,
                              isFire: useFire, isGolden: useGolden)
        bag.vx = vx
        bag.vy = vy
        bag.vz = vzInitial

        let speed = sqrt(vx * vx + vy * vy)
        bag.rotV = (Bool.random() ? 1.0 : -1.0) * (0.04 + speed * 0.015)

        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        activeBags.append(bag)

        if owner == .player {
            playerBagsThrown += 1
            lastThrower = .player
        } else {
            aiBagsThrown += 1
            lastThrower = .ai
        }

        gameState = .resolving
        turnIndicator?.isHidden = true

        // Thrower beat the gopher to the punch — gopher dives away.
        if let gopher = activeGopher {
            gopher.diveAway()
            activeGopher = nil
        }

        // Cave match: ~10% of the time, when the dragon isn't out, a bat swoops in,
        // grabs the bag mid-air, and drops it on the board (mostly) or in the hole.
        if isCaveMatch && dragonNode == nil && batNode == nil
            && !useFire && !useMagic && !useBomb && !useGolden && !useHoney
            && Double.random(in: 0..<1) < 0.10 {
            scheduleBatSnatch(for: bag)
        }
    }

    // MARK: - AI

    private func aiThrow() {
        guard gameState == .aiTurn, aiBagsThrown < bagsPerPlayer else { return }

        let startX       = pendingAIStartX
        let flightFrames = 2.0 * vzInitial / gravityPerFrame  // ≈ 60 frames

        // Base aim: hole with noise scaled by weather. Barnum is "good but not great" —
        // a fixed, tighter-than-Tom/Jenny aim that doesn't adapt like Billy.
        let noiseFactor: CGFloat = rainActive ? 3.4 : (selectedOpponent == .barnum ? barnumNoiseFactor : 2.5)
        let noise = holeRadius * noiseFactor
        var aimX = holeCenter.x + CGFloat.random(in: -noise...noise)
        var aimY = holeCenter.y + CGFloat.random(in: -noise * 0.5...noise * 0.5)

        // Tom — mirrors player hole shots: when player has a bag in the hole,
        // strong chance to aim with tight precision and cancel those points.
        if selectedOpponent == .tom {
            let playerHoles = activeBags.filter { $0.owner == .player && $0.hasScored }.count
            if playerHoles > 0, Double.random(in: 0..<1) < 0.55 {
                let preciseNoise = holeRadius * 0.38
                aimX = holeCenter.x + CGFloat.random(in: -preciseNoise...preciseNoise)
                aimY = holeCenter.y + CGFloat.random(in: -preciseNoise * 0.5...preciseNoise * 0.5)
            }
        }

        // Jenny — high chance to aim directly at a player bag resting on the board.
        if selectedOpponent == .jenny {
            let targets = activeBags.filter {
                $0.owner == .player && $0.isGrounded && !$0.hasScored &&
                !$0.hasAppliedGroundScale && checkIsOnBoard($0)
            }
            if let target = targets.randomElement(), Double.random(in: 0..<1) < 0.85 {
                aimX = target.bx + CGFloat.random(in: -10...10)
                aimY = target.by + CGFloat.random(in: -10...10)
            }
        }

        let vx = (aimX - startX) / flightFrames
        let vy = (aimY - throwLineY) / flightFrames

        // Billy — adaptive noise that tightens as the player improves.
        // May also throw bomb bags to destroy player bags on the board or in the hole.
        if selectedOpponent == .billy {
            let billyNoise = holeRadius * billyNoiseFactor
            aimX = holeCenter.x + CGFloat.random(in: -billyNoise...billyNoise)
            aimY = holeCenter.y + CGFloat.random(in: -billyNoise * 0.5...billyNoise * 0.5)
            let billyVx = (aimX - startX) / flightFrames
            let billyVy = (aimY - throwLineY) / flightFrames

            let throwBomb = billyBombBagsRemaining > 0 && Double.random(in: 0..<1) < 0.20
            if throwBomb { billyBombBagsRemaining -= 1 }
            throwBag(owner: .ai, startX: startX, vx: billyVx, vy: billyVy, aiBomb: throwBomb)
            return
        }

        // Tree Spirit — drops magic bags straight down from above.
        // 50% aim near the hole; 50% fall on a random board spot.
        if selectedOpponent == .spirit {
            let targetX: CGFloat
            let targetY: CGFloat
            if Double.random(in: 0..<1) < 0.15 {
                let noise = holeRadius * 1.0
                targetX = holeCenter.x + CGFloat.random(in: -noise...noise)
                targetY = holeCenter.y + CGFloat.random(in: -noise * 0.4...noise * 0.4)
            } else {
                targetX = CGFloat.random(in: -boardHalfW * 0.80 ... boardHalfW * 0.80)
                targetY = CGFloat.random(in: (boardY - boardHalfH * 0.80) ... (boardY + boardHalfH * 0.80))
            }
            dropMagicBagFromAbove(targetX: targetX, targetY: targetY)
            return
        }

        // CathyX — plays by her own inverted rule: a hole-in costs her 3 points, so she
        // deliberately aims for the open board surface (front half, clear of the cup)
        // rather than the hole. Moderate accuracy.
        if selectedOpponent == .cathy {
            let cathyNoise = holeRadius * 1.6
            let cathyAimX  = CGFloat.random(in: -boardHalfW * 0.70 ... boardHalfW * 0.70)
            let frontY     = boardY - boardHalfH * 0.35   // front of board, away from hole band
            let cathyAimY  = frontY + CGFloat.random(in: -cathyNoise * 0.4 ... cathyNoise * 0.4)
            let cathyVx    = (cathyAimX - startX) / flightFrames
            let cathyVy    = (cathyAimY - throwLineY) / flightFrames
            throwBag(owner: .ai, startX: startX, vx: cathyVx, vy: cathyVy)
            return
        }

        throwBag(owner: .ai, startX: startX, vx: vx, vy: vy)
    }

    /// Creates a Spirit magic bag that materialises high above the board and falls straight down.
    private func dropMagicBagFromAbove(targetX: CGFloat, targetY: CGFloat) {
        guard gameState == .aiTurn, aiBagsThrown < bagsPerPlayer else { return }

        let bag = MiniGameBag(owner: .ai, startX: targetX, startY: targetY, isMagic: true)
        bag.bz   = 220          // materialise well above the board
        bag.vx   = CGFloat.random(in: -0.3...0.3)  // tiny flutter
        bag.vy   = 0
        bag.vz   = 0
        bag.rotV = CGFloat.random(in: -0.04...0.04)

        gameWorldNode.addChild(bag.node)
        gameWorldNode.addChild(bag.shadow)
        activeBags.append(bag)

        aiBagsThrown += 1
        lastThrower   = .ai
        gameState     = .resolving
        turnIndicator?.isHidden = true
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Tutorial overlay consumes all input — any tap advances it.
        if let overlay = TutorialOverlay.active(in: self) {
            overlay.advance(); return
        }
        // HUD help button re-presents the tutorial without restarting the round.
        for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        // Pause overlay routing
        if isPausedGame {
            for n in nodes(at: loc) {
                let name = n.name ?? n.parent?.name ?? ""
                if name == "resumeBtn" { resumeGame(); return }
                if TutorialHelpButton.wasTapped(n) { presentTutorial(autoTriggered: false); return }
            }
            return
        }
        if nodes(at: loc).contains(where: { $0.name == "pauseBtn" }) { pauseGame(); return }

        // Quit-confirm modal consumes all input until resolved
        if confirmingQuit { handleButtonTap(at: loc); return }

        guard gameState == .playerTurn else {
            // Allow tapping game-over buttons in any state
            handleButtonTap(at: loc)
            return
        }

        // Swallow touches over UI to prevent a throw from starting.
        // Actions (selectSatchelItem, openPanel, etc.) fire once in touchesEnded.
        if handleButtonTap(at: loc, fireActions: false) { return }

        touchStart = loc
        aimingLine?.removeFromParent()
        let line = SKShapeNode()
        line.strokeColor = SKColor(white: 1, alpha: 0.45)
        line.lineWidth   = 1
        line.zPosition   = 400
        addChild(line)
        aimingLine = line
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let start = touchStart, let line = aimingLine else { return }
        let loc = touch.location(in: self)
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: loc)
        line.path = path
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let end = touch.location(in: self)

        aimingLine?.removeFromParent()
        aimingLine = nil

        if gameState != .playerTurn {
            handleButtonTap(at: end)
            touchStart = nil
            return
        }

        if handleButtonTap(at: end) { touchStart = nil; return }

        guard let start = touchStart else { return }
        touchStart = nil

        guard playerBagsThrown < bagsPerPlayer else { return }

        let dx = end.x - start.x
        let dy = end.y - start.y

        throwBag(owner: .player,
                 startX: turnIndicator?.position.x ?? 0,
                 vx: dx * powerScale,
                 vy: dy * powerScale)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        aimingLine?.removeFromParent()
        aimingLine = nil
        touchStart = nil
    }

    // Returns true if a named button was tapped (consuming the touch).
    // Uses nodes(at:) so nested buttons (inside panels) are found correctly.
    // Pass fireActions:false from touchesBegan to swallow satchel-item touches without
    // triggering selection — selection fires once in touchesEnded to avoid double-toggle.
    @discardableResult
    private func handleButtonTap(at location: CGPoint, fireActions: Bool = true) -> Bool {
        for node in nodes(at: location) {
            var n: SKNode? = node
            while let current = n {
                switch current.name {
                case "satchelButton":
                    if fireActions, !satchelOpen {
                        openSatchelPanel()
                    }
                    return true
                case "satchelCloseBtn":
                    if fireActions { closeSatchelPanel() }
                    return true
                case "satchelBackdrop", "satchelPanelBg":
                    return true  // swallow — panel stays open
                case let name where name?.hasPrefix("satchelItem_") == true:
                    if fireActions,
                       let name = name,
                       let type = ItemType(rawValue: String(name.dropFirst("satchelItem_".count))) {
                        selectSatchelItem(type)
                        closeSatchelPanel()
                    }
                    return true
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
                    playerScore = 0
                    aiScore     = 0
                    roundNumber = 0
                    if rainActive { deactivateRain() }
                    if tomFartActive { deactivateTomFart() }
                    rollWeatherScenarios()
                    startRound()
                    return true
                case "exitBtn":
                    dismissScene(playerWon: playerScore > aiScore)
                    return true
                default:
                    n = current.parent
                }
            }
        }
        return false
    }

    // MARK: - Effects

    private func showHoleEffect(at pos: CGPoint) {
        let flash = SKSpriteNode(color: SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 0.9),
                                 size: CGSize(width: holeRadius * 1.5, height: holeRadius * 1.5))
        flash.position = pos
        flash.zPosition = 50
        gameWorldNode.addChild(flash)

        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.2, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.28),
            ]),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Game-Over Panel

    private func showGameOverPanel(playerWon: Bool) {
        messageNode?.removeFromParent()

        // Spirit loss hint (steers the player toward special bags).
        var hint: (text: String, color: SKColor)? = nil
        if !playerWon && selectedOpponent == .spirit {
            hint = ("SPECIAL BAGS MAY HELP\nAGAINST SUCH A FOE...",
                    SKColor(red: 0.12, green: 0.82, blue: 0.35, alpha: 1))
        } else if !playerWon && selectedOpponent == .cathy {
            hint = ("AIM FOR THE BOARD —\nTHE HOLE WIPES YOUR ROUND!",
                    SKColor(red: 0.85, green: 0.55, blue: 0.30, alpha: 1))
        }

        // Prize lines — only in reward context (world / story), never from the menu.
        var rewards: [GameResultModal.Reward] = []
        if awardsRewards && playerWon {
            switch selectedOpponent {
            case .billy:
                rewards = [GameResultModal.Reward(item: .coin, count: 10),
                           GameResultModal.Reward(item: .bombBag, count: 3)]
            case .bully:
                rewards = [GameResultModal.Reward(item: .coin, count: 10)]
            case .spirit:
                rewards = [GameResultModal.Reward(item: .magicBag, count: 6)]
            case .barnum:
                rewards = [GameResultModal.Reward(item: .fireBag, count: 3)]
            case .tom, .jenny:
                // This win completes the baseball unlock (both Tom & Jenny beaten).
                let beatBoth = (selectedOpponent == .tom && CornholeStatsManager.shared.defeatedJenny)
                            || (selectedOpponent == .jenny && CornholeStatsManager.shared.defeatedTom)
                if beatBoth {
                    rewards = [.unlock("EARNED A BASEBALL!"),
                               .unlock("BASEBALL UNLOCKED")]
                }
            case .cathy:
                // No item reward — beating CathyX opens the graveyard (grave layer
                // cleared by GameScene). Surface that as the win line.
                rewards = [.unlock("GRAVEYARD OPENED!")]
            }
        }

        let panel = GameResultModal.make(
            sceneSize: size,
            won: playerWon,
            title: playerWon ? "VICTORY!" : "DEFEAT",
            subtitle: "YOU \(playerScore)  -  \(aiScore) \(opponentName)",
            detail: "FIRST TO \(winScore)",
            hint: hint,
            rewards: rewards,
            buttons: [GameResultModal.Button(label: "PLAY AGAIN", name: "playAgainBtn", style: .primary),
                      GameResultModal.Button(label: "EXIT", name: "exitBtn", style: .danger)])
        addChild(panel)
        messageNode = panel
    }

    private func showRoundResultMessage(roundPlayer: Int, roundAI: Int) {
        let net = roundPlayer - roundAI
        let headline: String
        let delta: String
        if net > 0 {
            headline = "ROUND TO YOU"
            delta = "+\(net)"
        } else if net < 0 {
            headline = "ROUND TO \(opponentName)"
            delta = "+\(abs(net))"
        } else {
            headline = "ROUND WASH"
            delta = ""
        }

        animateRoundBanner(headline: headline, delta: delta, playerFavored: net >= 0)
    }

    /// CathyX round banner. Player hole-ins are the headline (they nullify your round),
    /// so a player sink is shown first and in the "bad" color. Otherwise fall back to
    /// the board-net swing, mirroring the normal banner.
    private func showCathyRoundResultMessage(boardNet: Int,
                                             playerSank: Bool,
                                             aiSank: Bool) {
        let headline: String
        let delta: String
        let playerFavored: Bool
        if playerSank && boardNet <= 0 {
            headline = "YOU SANK!"
            delta = "ROUND LOST"
            playerFavored = false          // render in opponent color
        } else if aiSank && boardNet >= 0 {
            headline = "\(opponentName) SANK!"
            delta = "ROUND WON"
            playerFavored = true
        } else if boardNet > 0 {
            headline = "ROUND TO YOU"
            delta = "+\(boardNet)"
            playerFavored = true
        } else if boardNet < 0 {
            headline = "ROUND TO \(opponentName)"
            delta = "+\(abs(boardNet))"
            playerFavored = false
        } else {
            headline = "ROUND WASH"
            delta = ""
            playerFavored = true
        }
        animateRoundBanner(headline: headline, delta: delta, playerFavored: playerFavored)
    }

    /// Shared round-end modal: dark wood panel with gold trim showing who took the round
    /// and the score delta. `playerFavored` picks the delta color (green when the player
    /// gains, red when the opponent does).
    private func animateRoundBanner(headline: String, delta: String, playerFavored: Bool) {
        let panelW = min(size.width * 0.72, 360)
        let panelH: CGFloat = delta.isEmpty ? 64 : 96

        let container = SKNode()
        container.zPosition = 900
        container.alpha = 0
        container.setScale(0.85)

        let body = SKSpriteNode(color: SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.96),
                                size: CGSize(width: panelW, height: panelH))
        container.addChild(body)

        let goldColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        let borderT: CGFloat = 2
        let top    = SKSpriteNode(color: goldColor, size: CGSize(width: panelW, height: borderT))
        top.position    = CGPoint(x: 0, y:  panelH/2 - borderT/2)
        let bottom = SKSpriteNode(color: goldColor, size: CGSize(width: panelW, height: borderT))
        bottom.position = CGPoint(x: 0, y: -panelH/2 + borderT/2)
        let left   = SKSpriteNode(color: goldColor, size: CGSize(width: borderT, height: panelH))
        left.position   = CGPoint(x: -panelW/2 + borderT/2, y: 0)
        let right  = SKSpriteNode(color: goldColor, size: CGSize(width: borderT, height: panelH))
        right.position  = CGPoint(x:  panelW/2 - borderT/2, y: 0)
        container.addChild(top); container.addChild(bottom)
        container.addChild(left); container.addChild(right)

        let headlineLbl = makeLabel(text: headline,
                                    size: max(6, size.width * 0.045),
                                    color: goldColor)
        headlineLbl.position = CGPoint(x: 0, y: delta.isEmpty ? -6 : panelH * 0.12)
        container.addChild(headlineLbl)

        if !delta.isEmpty {
            let deltaLbl = makeLabel(text: delta,
                                     size: max(8, size.width * 0.07),
                                     color: playerFavored
                                        ? SKColor(red: 0.45, green: 0.92, blue: 0.50, alpha: 1)
                                        : SKColor(red: 0.95, green: 0.42, blue: 0.42, alpha: 1))
            deltaLbl.position = CGPoint(x: 0, y: -panelH * 0.22)
            container.addChild(deltaLbl)
        }

        addChild(container)

        container.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.18),
                SKAction.scale(to: 1.0, duration: 0.18),
            ]),
            SKAction.wait(forDuration: 1.6),
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.removeFromParent(),
        ]))
    }

    private func handlePlayerCornholeStreak() {
        playerCornholeStreak += 1
        switch playerCornholeStreak {
        case ..<2:
            break
        case 2:
            showStreakBanner(lines: ["2x NICE SHOT!"],
                             color: SKColor(red: 0.95, green: 0.82, blue: 0.30, alpha: 1))
        case 3:
            let canAward = awardsRewards
            var lines = ["3x IN A ROW!", "YOU ARE ON FIRE!"]
            if canAward { lines.append("TAKE A FIRE BEAN BAG!") }
            showStreakBanner(lines: lines,
                             color: SKColor(red: 1.0, green: 0.45, blue: 0.18, alpha: 1))
            if canAward {
                availableFireBags += 1
                fireBagsEarned    += 1
                updateSatchelButton()
                refreshSatchelPanelRows()
            }
        default:
            // 4 or more consecutive — cornholio. Award one golden bag, then keep the streak running.
            let canAward = awardsRewards
            var lines = ["YOU ARE CORNHOLIO!"]
            if canAward { lines.append("TAKE A GOLDEN BAG!") }
            showStreakBanner(lines: lines,
                             color: SKColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1))
            if canAward {
                availableGoldenBags += 1
                goldenBagsEarned    += 1
                updateSatchelButton()
                refreshSatchelPanelRows()
            }
        }
    }

    private func showStreakBanner(lines: [String], color: SKColor) {
        let container = SKNode()
        container.zPosition = 850
        container.alpha = 0
        let fontSize = max(8, size.width * 0.045)
        let lineGap: CGFloat = fontSize * 1.25
        let totalH = lineGap * CGFloat(lines.count - 1)
        for (i, text) in lines.enumerated() {
            let lbl = makeLabel(text: text, size: fontSize, color: color)
            lbl.position = CGPoint(x: 0, y: totalH / 2 - CGFloat(i) * lineGap)
            container.addChild(lbl)
        }
        addChild(container)

        container.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.18),
                SKAction.scale(to: 1.15, duration: 0.18),
            ]),
            SKAction.scale(to: 1.0, duration: 0.10),
            SKAction.wait(forDuration: 1.3),
            SKAction.fadeOut(withDuration: 0.28),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - HUD updates

    private func updateScoreLabels() {
        playerScoreLabel?.text = "YOU: \(playerScore) | \(opponentName): \(aiScore)"
    }

    private func updateRoundLabels() {
        // Show live per-round bag counts in bottom chrome
        (childNode(withName: "rndPlayerLabel") as? SKLabelNode)?.text =
            playerBagsThrown > 0 ? "\(playerBagsThrown)/\(bagsPerPlayer)▪" : ""
        (childNode(withName: "rndAILabel") as? SKLabelNode)?.text =
            aiBagsThrown > 0 ? "▪\(aiBagsThrown)/\(bagsPerPlayer)" : ""
    }

    private func updateTurnIndicator() {
        switch gameState {
        case .playerTurn:
            if goldenBagSelected {
                turnIndicator?.color = SKColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1)  // gold — golden bag armed
            } else if magicBagSelected {
                turnIndicator?.color = SKColor(red: 0.30, green: 1.00, blue: 0.10, alpha: 1)  // fluorescent green — magic bag armed
            } else if fireBagSelected {
                turnIndicator?.color = SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)  // orange — fire bag armed
            } else if honeyBagSelected {
                turnIndicator?.color = SKColor(red: 0.95, green: 0.72, blue: 0.10, alpha: 1)  // golden — honey bag armed
            } else {
                turnIndicator?.color = SKColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)
            }
            applyGoldenIndicatorMarker(goldenBagSelected)
            applyMagicIndicatorMarker(magicBagSelected)
            turnIndicator?.isHidden = false
        case .aiTurn:
            turnIndicator?.color = SKColor(red: 0.30, green: 0.50, blue: 0.90, alpha: 1)
            applyGoldenIndicatorMarker(false)
            applyMagicIndicatorMarker(false)
            turnIndicator?.isHidden = selectedOpponent == .spirit
        default:
            applyGoldenIndicatorMarker(false)
            applyMagicIndicatorMarker(false)
            turnIndicator?.isHidden = true
        }
    }

    /// Adds or removes a ✦ sparkle marker on the throw-line preview bag so it's
    /// obvious at a glance the next throw is a magic bag.
    private func applyMagicIndicatorMarker(_ show: Bool) {
        guard let indicator = turnIndicator else { return }
        let existing = indicator.childNode(withName: "magicSparkleMarker")
        if show {
            if existing == nil {
                let sparkle = SKLabelNode(text: "✦")
                sparkle.name                    = "magicSparkleMarker"
                sparkle.fontName                = "PressStart2P-Regular"
                sparkle.fontSize                = 20
                sparkle.fontColor               = SKColor(red: 0.90, green: 1.0, blue: 0.70, alpha: 1)
                sparkle.verticalAlignmentMode   = .center
                sparkle.horizontalAlignmentMode = .center
                sparkle.position                = .zero
                sparkle.zPosition               = 1
                indicator.addChild(sparkle)
            }
            // Gentle pulse so the preview bag clearly reads as the magic bag
            indicator.removeAction(forKey: "magicPulse")
            indicator.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.65, duration: 0.35),
                SKAction.fadeAlpha(to: 1.00, duration: 0.35),
            ])), withKey: "magicPulse")
        } else {
            existing?.removeFromParent()
            indicator.removeAction(forKey: "magicPulse")
            indicator.alpha = 1.0
        }
    }

    /// Adds or removes a star marker + shimmer on the throw-line preview bag so it's
    /// obvious at a glance the next throw is a golden bag.
    private func applyGoldenIndicatorMarker(_ show: Bool) {
        guard let indicator = turnIndicator else { return }
        let existing = indicator.childNode(withName: "goldenStarMarker")
        if show {
            if existing == nil {
                let star = SKLabelNode(text: "★")
                star.name                    = "goldenStarMarker"
                star.fontName                = "PressStart2P-Regular"
                star.fontSize                = 22
                star.fontColor               = SKColor(white: 1.0, alpha: 0.95)
                star.verticalAlignmentMode   = .center
                star.horizontalAlignmentMode = .center
                star.position                = .zero
                star.zPosition               = 1
                indicator.addChild(star)
            }
            indicator.removeAction(forKey: "goldenShimmer")
            indicator.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.colorize(with: SKColor(red: 1.0, green: 1.0, blue: 0.55, alpha: 1),
                                  colorBlendFactor: 0.55, duration: 0.25),
                SKAction.colorize(withColorBlendFactor: 0.90, duration: 0.25),
            ])), withKey: "goldenShimmer")
        } else {
            existing?.removeFromParent()
            indicator.removeAction(forKey: "goldenShimmer")
            indicator.colorBlendFactor = 0.65
        }
    }

    private func updateWindLabel() {
        let strength = abs(wind.dx)
        let windText: String
        if strength < 0.30 {
            windText = "CALM"
        } else {
            let arrow = wind.dx > 0 ? ">" : "<"
            windText = "\(arrow) \(String(format: "%.1f", strength))"
        }
        if stormActive {
            windLabel?.text = "STORM | \(windText)"
            windLabel?.fontColor = SKColor(red: 0.95, green: 0.90, blue: 0.20, alpha: 1)
        } else if rainActive {
            windLabel?.text = "RAIN | \(windText)"
            windLabel?.fontColor = SKColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1)
        } else {
            windLabel?.text = windText
            windLabel?.fontColor = SKColor(red: 0.941, green: 0.753, blue: 0.376, alpha: 1) // gold
        }
    }

    // MARK: - Rain

    private func rollWeatherScenarios() {
        // Spirit forces a permanent thunderstorm in applySpiritSettings — don't re-roll.
        guard selectedOpponent == .billy else { return }
        rollRainScenario()
        rollThunderstormScenario()
    }

    private func rollRainScenario() {
        rainStartRound = -1
        rainEndRound   = Int.max

        // 40% chance of rain this game
        guard Int.random(in: 0..<10) < 4 else { return }

        rainStartRound = Int.random(in: 1...2)   // rain begins round 1 or 2
        let wholeGame = Bool.random()
        if !wholeGame {
            let duration = Int.random(in: 1...2)
            rainEndRound = rainStartRound + duration
        }
    }

    private func activateRain() {
        rainActive = true
        spawnRainParticles()
        addBoardWetOverlay()
        showRainAnnouncement()
        updateWindLabel()
        // PLACEHOLDER: add rain_start.wav to Copy Bundle Resources
        run(SKAction.playSoundFileNamed("rain_start.wav", waitForCompletion: false))
    }

    private func deactivateRain() {
        rainActive = false

        rainParticleNode?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.6),
            SKAction.removeFromParent(),
        ]))
        rainParticleNode = nil

        boardRainOverlay?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent(),
        ]))
        boardRainOverlay = nil

        let cleared = makeLabel(text: "RAIN STOPPED",
                                size: max(5, size.width * 0.042),
                                color: SKColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 1))
        cleared.position  = CGPoint(x: 0, y: size.height * 0.12)
        cleared.zPosition = 800
        cleared.alpha     = 0
        addChild(cleared)
        cleared.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: 1.2),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent(),
        ]))

        updateWindLabel()
    }

    private func spawnRainParticles() {
        let container = SKNode()
        // Add directly to the scene, not to gameWorldNode (SKEffectNode).
        // Children that move far off-screen inside an SKEffectNode expand its render
        // bounds, which shifts the entire pixellated world — hence the "view moves up"
        // bug when rain starts.
        container.zPosition = 100  // above game world, below chrome at 500
        addChild(container)
        rainParticleNode = container

        let w = size.width
        let h = size.height
        let count = 60

        for _ in 0..<count {
            let drop = SKSpriteNode(
                color: SKColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 0.60),
                size: CGSize(width: 2, height: 10))
            drop.zRotation = -0.12   // slight diagonal slant

            let startX = CGFloat.random(in: -w / 2 ... w / 2)
            let startY = CGFloat.random(in: -h / 2 ... h / 2)
            drop.position = CGPoint(x: startX, y: startY)
            container.addChild(drop)

            let duration = TimeInterval(CGFloat.random(in: 0.22...0.48))
            let fallDist = h + 30
            let driftX   = fallDist * -0.12

            let resetAction = SKAction.customAction(withDuration: 0) { [weak drop] _, _ in
                drop?.position = CGPoint(
                    x: CGFloat.random(in: -w / 2 ... w / 2),
                    y: h / 2 + 15)
            }

            let cycle = SKAction.sequence([
                SKAction.moveBy(x: driftX, y: -fallDist, duration: duration),
                resetAction,
            ])

            let delay = SKAction.wait(forDuration: TimeInterval(CGFloat.random(in: 0...0.5)))
            drop.run(SKAction.sequence([delay, SKAction.repeatForever(cycle)]))
        }
    }

    private func addBoardWetOverlay() {
        let overlay = SKSpriteNode(
            color: SKColor(red: 0.22, green: 0.42, blue: 0.72, alpha: 0.30),
            size: CGSize(width: boardHalfW * 2, height: boardHalfH * 2))
        overlay.position  = CGPoint(x: 0, y: boardY)
        overlay.zPosition = 8
        overlay.setScale(0.90)   // match board visual scale
        gameWorldNode.addChild(overlay)
        boardRainOverlay = overlay

        // Subtle shimmer to suggest wet surface
        let shimmer = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.38, duration: 0.9),
            SKAction.fadeAlpha(to: 0.22, duration: 0.9),
        ])
        overlay.run(SKAction.repeatForever(shimmer))
    }

    private func showRainAnnouncement() {
        let lbl = makeLabel(text: "RAIN! SLIPPERY!",
                            size: max(6, size.width * 0.048),
                            color: SKColor(red: 0.55, green: 0.72, blue: 0.95, alpha: 1))
        lbl.position  = CGPoint(x: 0, y: size.height * 0.12)
        lbl.zPosition = 800
        lbl.alpha     = 0
        addChild(lbl)

        lbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.28),
            SKAction.wait(forDuration: 1.5),
            SKAction.fadeOut(withDuration: 0.38),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Thunderstorm

    private func rollThunderstormScenario() {
        stormStartRound = -1
        stormEndRound   = Int.max

        // Don't stack weather — rain takes precedence
        guard rainStartRound < 0 else { return }

        // 30% chance of thunderstorm this game
        guard Int.random(in: 0..<10) < 3 else { return }

        stormStartRound = Int.random(in: 1...2)
        let wholeGame = Bool.random()
        if !wholeGame {
            let duration = Int.random(in: 1...2)
            stormEndRound = stormStartRound + duration
        }
    }

    private func activateStorm() {
        stormActive = true
        addStormDarkOverlay()
        spawnStormParticles()
        scheduleNextLightningFlash()
        scheduleNextLightningStrike()
        showStormAnnouncement()
        updateWindLabel()

        guard stormAudioNode == nil,
              Bundle.main.url(forResource: "storm", withExtension: "mp3") != nil else { return }
        let audio = SKAudioNode(fileNamed: "storm.mp3")
        audio.autoplayLooped = true
        audio.isPositional   = false
        audio.run(SKAction.changeVolume(to: 0, duration: 0))
        addChild(audio)
        audio.run(SKAction.changeVolume(to: 0.70, duration: 1.2))
        stormAudioNode = audio
    }

    private func deactivateStorm(keepNightTint: Bool = false) {
        stormActive = false
        removeAction(forKey: "stormFlash")
        removeAction(forKey: "stormStrike")

        if let audio = stormAudioNode {
            audio.run(SKAction.sequence([
                SKAction.changeVolume(to: 0, duration: 1.5),
                SKAction.removeFromParent(),
            ]))
            stormAudioNode = nil
        }

        if keepNightTint {
            // Leave the moonlit blue wash in place — rain/wind/lightning still clear.
        } else {
            stormDarkOverlay?.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.8),
                SKAction.removeFromParent(),
            ]))
            stormDarkOverlay = nil
        }

        stormParticleNode?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.6),
            SKAction.removeFromParent(),
        ]))
        stormParticleNode = nil

        stormFlashOverlay?.removeFromParent()
        stormFlashOverlay = nil

        let cleared = makeLabel(text: keepNightTint ? "STORM CALMS" : "STORM PASSED",
                                size: max(7, size.width * 0.055),
                                color: SKColor(red: 0.95, green: 0.90, blue: 0.50, alpha: 1))
        cleared.position  = CGPoint(x: 0, y: size.height * 0.12)
        cleared.zPosition = 800
        cleared.alpha     = 0
        addChild(cleared)
        cleared.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: 1.2),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent(),
        ]))

        updateWindLabel()
    }

    // MARK: - Tom's Fart Ability

    private func activateTomFart() {
        tomFartActive    = true
        fartWobbleTimer  = 0
        targetSpeed      = fartBaseSpeed * 2.2   // indicator moves ~2× faster

        // Green fog cloud centered over the board + hole area
        let fogContainer = SKNode()
        fogContainer.zPosition = 97   // above board, below chrome
        addChild(fogContainer)
        tomFartOverlay = fogContainer

        // Build several overlapping soft circles to simulate a cloudy fog
        let boardCenterY = boardY + (holeCenter.y - boardY) * 0.5
        let fogW = size.width * 0.70
        let fogH = size.height * 0.55
        for _ in 0..<6 {
            let blob = SKSpriteNode(
                color: SKColor(red: CGFloat.random(in: 0.20...0.35),
                               green: CGFloat.random(in: 0.55...0.78),
                               blue:  CGFloat.random(in: 0.10...0.22),
                               alpha: CGFloat.random(in: 0.18...0.32)),
                size: CGSize(width: fogW * CGFloat.random(in: 0.45...0.85),
                             height: fogH * CGFloat.random(in: 0.45...0.85)))
            blob.position = CGPoint(x: CGFloat.random(in: -fogW * 0.25...fogW * 0.25),
                                    y: boardCenterY + CGFloat.random(in: -fogH * 0.20...fogH * 0.20))
            fogContainer.addChild(blob)
            // Gently pulse each blob so the fog feels alive
            let pulseDur = Double.random(in: 0.6...1.2)
            blob.run(.repeatForever(.sequence([
                .fadeAlpha(to: blob.alpha * 0.55, duration: pulseDur),
                .fadeAlpha(to: blob.alpha, duration: pulseDur)
            ])))
        }
        fogContainer.alpha = 0
        fogContainer.run(.fadeIn(withDuration: 0.50))

        // Announcement banner
        showTomFartAnnouncement()

        // Sound — add fart.wav to Copy Bundle Resources to enable; silently skipped if absent
        if Bundle.main.url(forResource: "fart", withExtension: "wav") != nil {
            run(SKAction.playSoundFileNamed("fart.wav", waitForCompletion: false))
        } else {
            run(SKAction.playSoundFileNamed("gopher_pop.wav", waitForCompletion: false))
        }
    }

    private func deactivateTomFart() {
        tomFartActive = false
        targetSpeed   = fartBaseSpeed

        tomFartOverlay?.run(.sequence([
            .fadeOut(withDuration: 0.60),
            .removeFromParent()
        ]))
        tomFartOverlay = nil
    }

    private func showTomFartAnnouncement() {
        // Outer glow backing
        let glow = SKSpriteNode(
            color: SKColor(red: 0.10, green: 0.40, blue: 0.08, alpha: 0.72),
            size: CGSize(width: size.width * 0.76, height: size.height * 0.12))
        glow.position  = CGPoint(x: 0, y: size.height * 0.14)
        glow.zPosition = 810
        glow.alpha     = 0
        addChild(glow)

        let lbl = makeLabel(text: "TOMMY TOOTS! 💨",
                            size: max(7, size.width * 0.052),
                            color: SKColor(red: 0.58, green: 1.00, blue: 0.22, alpha: 1))
        lbl.position  = CGPoint(x: 0, y: size.height * 0.14)
        lbl.zPosition = 820
        lbl.alpha     = 0
        addChild(lbl)

        let seq = SKAction.sequence([
            .fadeIn(withDuration: 0.22),
            .scale(to: 1.08, duration: 0.12),
            .scale(to: 1.00, duration: 0.10),
            .wait(forDuration: 1.6),
            .fadeOut(withDuration: 0.38),
            .removeFromParent()
        ])
        lbl.run(seq)
        glow.run(seq.copy() as! SKAction)
    }

    private func addStormDarkOverlay() {
        // Moonlight tint: cool blue wash at low opacity so the scene stays bright
        let overlay = SKSpriteNode(
            color: SKColor(red: 0.10, green: 0.18, blue: 0.55, alpha: 0.32),
            size: CGSize(width: size.width * 2, height: size.height * 2))
        overlay.zPosition = 95   // above game world, below storm particles
        overlay.alpha = 0
        addChild(overlay)
        stormDarkOverlay = overlay
        overlay.run(SKAction.fadeIn(withDuration: 0.8))
    }

    private func spawnStormParticles() {
        // Add directly to scene (not gameWorldNode) to avoid render-bounds expansion bug
        let container = SKNode()
        container.zPosition = 102
        addChild(container)
        stormParticleNode = container

        let w = size.width
        let h = size.height

        for _ in 0..<90 {
            let drop = SKSpriteNode(
                color: SKColor(red: 0.60, green: 0.65, blue: 0.85, alpha: 0.72),
                size: CGSize(width: 2, height: 12))
            drop.zRotation = -0.20   // steeper diagonal slant than normal rain

            drop.position = CGPoint(
                x: CGFloat.random(in: -w / 2 ... w / 2),
                y: CGFloat.random(in: -h / 2 ... h / 2))
            container.addChild(drop)

            let duration = TimeInterval(CGFloat.random(in: 0.12...0.28))
            let fallDist = h + 30
            let driftX   = fallDist * -0.20

            let resetAction = SKAction.customAction(withDuration: 0) { [weak drop] _, _ in
                drop?.position = CGPoint(
                    x: CGFloat.random(in: -w / 2 ... w / 2),
                    y: h / 2 + 15)
            }
            let cycle = SKAction.sequence([
                SKAction.moveBy(x: driftX, y: -fallDist, duration: duration),
                resetAction,
            ])
            let delay = SKAction.wait(forDuration: TimeInterval(CGFloat.random(in: 0...0.3)))
            drop.run(SKAction.sequence([delay, SKAction.repeatForever(cycle)]))
        }
    }

    // Self-scheduling flash so each interval is freshly randomised
    private func scheduleNextLightningFlash() {
        guard stormActive else { return }
        run(SKAction.sequence([
            SKAction.wait(forDuration: TimeInterval.random(in: 2.5...6.0)),
            SKAction.run { [weak self] in
                guard let self, self.stormActive else { return }
                self.triggerLightningFlash()
                self.scheduleNextLightningFlash()
            },
        ]), withKey: "stormFlash")
    }

    private func triggerLightningFlash() {
        if stormFlashOverlay == nil {
            let flash = SKSpriteNode(
                color: SKColor(red: 0.95, green: 0.95, blue: 0.78, alpha: 0),
                size: CGSize(width: size.width * 2, height: size.height * 2))
            flash.zPosition = 200
            addChild(flash)
            stormFlashOverlay = flash
        }
        guard let flash = stormFlashOverlay else { return }
        // Double-pulse mimics a real lightning strike
        flash.removeAllActions()
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.80, duration: 0.04),
            SKAction.fadeAlpha(to: 0.18, duration: 0.07),
            SKAction.fadeAlpha(to: 0.55, duration: 0.03),
            SKAction.fadeAlpha(to: 0.0,  duration: 0.28),
        ]))
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // Self-scheduling strike so each interval is freshly randomised
    private func scheduleNextLightningStrike() {
        guard stormActive else { return }
        run(SKAction.sequence([
            SKAction.wait(forDuration: TimeInterval.random(in: 7.0...15.0)),
            SKAction.run { [weak self] in
                guard let self, self.stormActive else { return }
                self.triggerLightningStrike()
                self.scheduleNextLightningStrike()
            },
        ]), withKey: "stormStrike")
    }

    private func triggerLightningStrike() {
        // Only target grounded on-board bags that haven't already scored or fallen off
        let targets = activeBags.filter {
            $0.isGrounded && !$0.hasScored && !$0.hasAppliedGroundScale && checkIsOnBoard($0)
        }
        guard let target = targets.randomElement() else { return }

        spawnLightningBolt(at: CGPoint(x: target.bx, y: target.by))
        triggerLightningFlash()

        // Brief delay so the bolt is visible before the bag pops
        run(SKAction.wait(forDuration: 0.15)) { [weak self] in
            self?.zapBag(target)
        }
    }

    private func zapBag(_ bag: MiniGameBag) {
        activeBags.removeAll { $0 === bag }

        bag.node.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.4, duration: 0.08),
                SKAction.fadeAlpha(to: 0.9, duration: 0.08),
            ]),
            SKAction.group([
                SKAction.scale(to: 0.0, duration: 0.20),
                SKAction.fadeOut(withDuration: 0.20),
            ]),
            SKAction.removeFromParent(),
        ]))
        bag.shadow.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.22),
            SKAction.removeFromParent(),
        ]))

        let zapLabel = makeLabel(text: "ZAP!",
                                 size: max(8, size.width * 0.065),
                                 color: SKColor(red: 1.0, green: 0.95, blue: 0.20, alpha: 1))
        zapLabel.position  = CGPoint(x: bag.bx, y: bag.by + 20)
        zapLabel.zPosition = 300
        zapLabel.alpha     = 0
        addChild(zapLabel)
        zapLabel.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.10),
            SKAction.moveBy(x: 0, y: 30, duration: 0.60),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
    }

    private func spawnLightningBolt(at position: CGPoint) {
        let startY = size.height * 0.45
        let steps  = 6
        let stepH  = (startY - position.y) / CGFloat(steps)

        var points = [CGPoint(x: position.x, y: startY)]
        for i in 1..<steps {
            points.append(CGPoint(
                x: position.x + CGFloat.random(in: -18...18),
                y: startY - stepH * CGFloat(i)))
        }
        points.append(position)

        let path = CGMutablePath()
        path.move(to: points[0])
        for pt in points.dropFirst() { path.addLine(to: pt) }

        let bolt = SKShapeNode(path: path)
        bolt.strokeColor = SKColor(red: 1.0, green: 0.97, blue: 0.40, alpha: 1)
        bolt.lineWidth   = 3
        bolt.glowWidth   = 4
        bolt.zPosition   = 250
        addChild(bolt)

        bolt.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.08),
            SKAction.fadeAlpha(to: 0.5, duration: 0.08),
            SKAction.fadeOut(withDuration: 0.20),
            SKAction.removeFromParent(),
        ]))
    }

    private func showStormAnnouncement() {
        let lbl = makeLabel(text: "THUNDERSTORM!",
                            size: max(7, size.width * 0.056),
                            color: SKColor(red: 0.95, green: 0.90, blue: 0.20, alpha: 1))
        lbl.position  = CGPoint(x: 0, y: size.height * 0.12)
        lbl.zPosition = 800
        lbl.alpha     = 0
        addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.15),
            SKAction.wait(forDuration: 1.5),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - First-time Tutorial

    private func showFirstTimeTutorial() {
        presentTutorial(autoTriggered: true)
    }

    /// CathyX rules card. Shown **every** match against CathyX (not gated by
    /// TutorialManager) because the scoring inverts what the player has just learned —
    /// the reminder is needed each time, not only on first encounter. Calls `then` after
    /// the card is dismissed; if the opponent isn't CathyX, runs `then` immediately.
    private func showCathyRulesIfNeeded(then: @escaping () -> Void) {
        guard selectedOpponent == .cathy else { then(); return }
        let steps: [TutorialStep] = [
            .card(title: "CATHYX RULES",
                  body:  "FIRST TO 7 — BUT THE HOLE IS A TRAP! BAG ON BOARD = 1 PT. BAG IN HOLE = ALL YOUR ROUND POINTS WIPED. HIT THE FLYING DUCK = +3 PTS!"),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { then() }
        addChild(overlay)
    }

    /// Presents the cornhole tutorial via the shared `TutorialOverlay`. On
    /// auto-trigger (first play, before the first round starts) we kick off
    /// `startRound()` after completion; on replay (HUD `?` button) we do nothing
    /// since the round is already in progress.
    private func presentTutorial(autoTriggered: Bool) {
        let steps: [TutorialStep] = [
            .card(title: "CORNHOLE",
                  body:  "FIRST PLAYER TO 11 POINTS WINS THE MATCH."),
            .card(title: "AIMING",
                  body:  "DRAG FROM THE BAG TO AIM. LONGER DRAGS THROW HARDER. RELEASE TO TOSS."),
            .card(title: "SCORING",
                  body:  "BAG IN THE HOLE = 3 POINTS. BAG ON THE BOARD = 1 POINT. CANCELLATION RULES APPLY EACH ROUND."),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self = self else { return }
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.cornhole)
                self.showCathyRulesIfNeeded { [weak self] in self?.startRound() }
            }
        }
        addChild(overlay)
    }

    // MARK: - Quit Confirmation

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true

        let panelW = size.width  * 0.70
        let panelH = size.height * 0.30
        let fs     = max(5, size.width * 0.042)

        let panel = SKNode()
        panel.zPosition = 3000
        panel.name      = "confirmPanel"

        let bg = SKSpriteNode(color: SKColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.97),
                              size: CGSize(width: panelW, height: panelH))
        panel.addChild(bg)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        panel.addChild(border)

        let question = makeLabel(text: "QUIT GAME?", size: fs,
                                 color: SKColor(white: 0.88, alpha: 1))
        question.position = CGPoint(x: 0, y: panelH * 0.22)
        panel.addChild(question)

        let cancelBtn = makeButton(label: "CANCEL",
                                   fg: .white,
                                   bg: SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
                                   size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        cancelBtn.position = CGPoint(x: -panelW * 0.24, y: -panelH * 0.22)
        cancelBtn.name     = "cancelQuitBtn"
        panel.addChild(cancelBtn)

        let quitBtn = makeButton(label: "QUIT",
                                 fg: .white,
                                 bg: SKColor(red: 0.50, green: 0.10, blue: 0.10, alpha: 1),
                                 size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        quitBtn.position = CGPoint(x: panelW * 0.24, y: -panelH * 0.22)
        quitBtn.name     = "confirmQuitBtn"
        panel.addChild(quitBtn)

        panel.alpha = 0
        addChild(panel)
        confirmPanel = panel
        panel.run(.fadeIn(withDuration: 0.18))
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        confirmPanel?.run(.sequence([
            .fadeOut(withDuration: 0.15),
            .removeFromParent(),
        ]))
        confirmPanel = nil
    }

    // MARK: - Gopher

    private func maybeStartGopher(for owner: BagOwner) {
        clearGopher()
        // No gophers in the cave — the bag flies over a bottomless chasm.
        guard !isCaveMatch else { return }
        guard Double.random(in: 0..<1) < gopherSpawnChance else { return }

        // Spawn near the front edge of the board so the gopher has a runway —
        // gives the thrower a visible warning + a brief reaction window.
        // Long-distance variant: pop up halfway between the throw line and the
        // board's front edge so the gopher is visible mid-field, not way upstage.
        let spawnY: CGFloat = distanceScale < 1.0
            ? (throwLineY + (boardY - boardHalfH)) * 0.5
            : boardY - boardHalfH - 22
        guard spawnY > throwLineY + 20 else { return }   // not enough room

        let referenceX: CGFloat = owner == .player ? targetX : pendingAIStartX
        let jitter = targetRange * 0.5
        let rawX = referenceX + CGFloat.random(in: -jitter...jitter)
        let spawnX = min(max(rawX, -targetRange), targetRange)

        let gopher = GopherNode()
        gopher.position = CGPoint(x: spawnX, y: spawnY)
        gopher.zPosition = 18
        // Long-distance variant: still smaller than full size, but bumped up from the
        // global distanceScale (0.5) so it reads clearly mid-field.
        gopher.setScale(distanceScale < 1.0 ? 1.5 : 2.0)
        gameWorldNode.addChild(gopher)
        activeGopher = gopher

        run(SKAction.playSoundFileNamed("gopher_pop.wav", waitForCompletion: false))
        gopher.emerge(completion: {})
    }

    private func updateGopher(dt: CGFloat) {
        guard let gopher = activeGopher else { return }

        let targetXNow: CGFloat
        switch gameState {
        case .playerTurn: targetXNow = targetX
        case .aiTurn:     targetXNow = pendingAIStartX
        default:
            gopher.diveAway()
            activeGopher = nil
            return
        }

        let target = CGPoint(x: targetXNow, y: throwLineY)
        gopher.chase(toward: target, dt: dt)

        let dist = hypot(target.x - gopher.position.x, target.y - gopher.position.y)
        if dist < gopher.catchRadius {
            stealThrow(owner: gameState == .playerTurn ? .player : .ai, with: gopher)
        }
    }

    private func stealThrow(owner: BagOwner, with gopher: GopherNode) {
        run(SKAction.playSoundFileNamed("gopher_steal.wav", waitForCompletion: false))
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        if let indicator = turnIndicator {
            indicator.removeAllActions()
            indicator.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 0.2, duration: 0.14),
                    SKAction.fadeOut(withDuration: 0.14),
                ]),
                SKAction.run { [weak indicator] in
                    indicator?.isHidden = true
                    indicator?.alpha = 1
                    indicator?.setScale(1)
                    let pulse = SKAction.sequence([
                        SKAction.scale(to: 1.18, duration: 0.55),
                        SKAction.scale(to: 1.00, duration: 0.55),
                    ])
                    indicator?.run(SKAction.repeatForever(pulse))
                },
            ]))
        }

        let stolen = makeLabel(text: "STOLEN!",
                               size: max(7, size.width * 0.055),
                               color: SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1))
        stolen.position  = CGPoint(x: gopher.position.x, y: gopher.position.y + 18)
        stolen.zPosition = 300
        stolen.alpha     = 0
        gameWorldNode.addChild(stolen)
        stolen.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.10),
            SKAction.moveBy(x: 0, y: 28, duration: 0.70),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))

        if owner == .player {
            playerBagsThrown += 1
            lastThrower = .player
        } else {
            aiBagsThrown += 1
            lastThrower = .ai
        }
        gameState = .resolving

        gopher.catchAndRetreat(completion: { [weak self] in
            self?.activeGopher = nil
        })
        activeGopher = nil

        removeAction(forKey: "pendingAIThrow")

        run(SKAction.wait(forDuration: 0.55)) { [weak self] in
            self?.handleTurnEnd()
        }
    }

    private func clearGopher() {
        activeGopher?.removeFromParent()
        activeGopher = nil
    }

    // MARK: - Crow

    private func scheduleCrow() {
        removeAction(forKey: "crowSchedule")
        guard gameState != .gameOver else { return }
        let delay = TimeInterval.random(in: 8.0...22.0)
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in self?.spawnCrow() },
        ]), withKey: "crowSchedule")
    }

    private func spawnCrow() {
        guard crowNode == nil, gameState != .gameOver else { scheduleCrow(); return }
        crowFlyingRight = true
        let margin: CGFloat = 168 * distanceScale * 0.5 + 20
        let startX: CGFloat = -size.width / 2 - margin
        let endX:   CGFloat =  size.width / 2 + margin

        let crow = makeCrowSprite(facingRight: crowFlyingRight)
        crow.position  = CGPoint(x: startX, y: crowY)
        crow.zPosition = 16
        crow.xScale   *= distanceScale  // preserves facing-direction flip from makeCrowSprite
        crow.yScale   *= distanceScale
        gameWorldNode.addChild(crow)
        crowNode = crow

        let flyDuration = TimeInterval(abs(endX - startX) / 175.0)
        crow.run(SKAction.sequence([
            SKAction.moveTo(x: endX, duration: flyDuration),
            SKAction.removeFromParent(),
            SKAction.run { [weak self, weak crow] in
                if self?.crowNode === crow { self?.crowNode = nil }
                self?.scheduleCrow()
            },
        ]), withKey: "crowFly")
    }

    private static let crowFlyFrames: [SKTexture] = {
        let sheet = SKTexture(imageNamed: "Duck_01")
        sheet.filteringMode = .nearest
        // Sheet is 256×640 — 8 cols × 20 rows of 32×32. Use the SECOND row from the top
        // (6 mallard flap frames, columns 0..5). Art faces right.
        let cols = 6
        let sheetCols: CGFloat = 8
        let sheetRows: CGFloat = 20
        let fw: CGFloat = 1.0 / sheetCols
        let fh: CGFloat = 1.0 / sheetRows
        // SKTexture rect uses bottom-up coords; row index 1 from the top = row (rows-2) from the bottom.
        let y: CGFloat = (sheetRows - 2.0) / sheetRows
        var frames: [SKTexture] = []
        for i in 0..<cols {
            let rect = CGRect(x: CGFloat(i) * fw, y: y, width: fw, height: fh)
            let t = SKTexture(rect: rect, in: sheet)
            t.filteringMode = .nearest
            frames.append(t)
        }
        return frames
    }()

    private func makeCrowSprite(facingRight: Bool) -> SKSpriteNode {
        let frames = CornholeMiniGameScene.crowFlyFrames
        let sprite = SKSpriteNode(texture: frames[0], size: CGSize(width: 168, height: 168))
        // Duck sheet art faces left; flip xScale when flying right.
        if facingRight { sprite.xScale = -1 }
        sprite.run(SKAction.repeatForever(
            SKAction.animate(with: frames, timePerFrame: 0.08, resize: false, restore: false)
        ))
        return sprite
    }

    private func checkCrowCollisions() {
        guard let crow = crowNode else { return }
        let crowPos = crow.position
        for bag in activeBags {
            guard !bag.isGrounded, bag.bz > 2 else { continue }
            let visualY = bag.by + bag.bz * 0.5
            let dx = bag.bx - crowPos.x
            let dy = visualY - crowPos.y
            if dx * dx + dy * dy < 78 * 78 {
                crowHitByBag(bag)
                return
            }
        }
    }

    private func crowHitByBag(_ bag: MiniGameBag) {
        guard let crow = crowNode else { return }
        crowNode = nil
        removeAction(forKey: "crowSchedule")
        crow.removeAction(forKey: "crowFly")

        // CathyX bonus — hitting the duck is +3 to the player on the spot, applied
        // immediately rather than through round cancellation. Encourages high arcs in a
        // game type where the hole is a trap. AI duck-hits don't bonus her.
        if isCathyMatch && bag.owner == .player {
            playerScore += 3
            updateScoreLabels()
            showDuckBonusBanner(at: crow.position)
        }

        // Bag stops horizontally; gravity pulls it straight down next frame
        bag.vx = 0; bag.vy = 0; bag.vz = 0

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        run(SKAction.playSoundFileNamed("quack.wav", waitForCompletion: false))

        // Rapid panic flap
        (crow as? SKSpriteNode)?.removeAllActions()
        (crow as? SKSpriteNode)?.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleY(to: 0.25, duration: 0.06),
            SKAction.scaleY(to: 1.00, duration: 0.06),
        ])))

        // Crow bolts upward and off-screen in the direction it was flying
        let escapeX: CGFloat = crowFlyingRight ? 190 : -190
        crow.run(SKAction.sequence([
            SKAction.moveBy(x: escapeX * 0.25, y: 55, duration: 0.20),
            SKAction.moveBy(x: escapeX * 0.75, y: 130, duration: 0.52),
            SKAction.removeFromParent(),
            SKAction.run { [weak self] in self?.scheduleCrow() },
        ]))

        // "SQUAWK!" callout
        let squawk = makeLabel(text: "SQUAWK!",
                               size: max(7, size.width * 0.048),
                               color: SKColor(red: 1.0, green: 0.85, blue: 0.20, alpha: 1))
        squawk.position  = CGPoint(x: crow.position.x, y: crow.position.y + 20)
        squawk.zPosition = 300
        squawk.alpha     = 0
        gameWorldNode.addChild(squawk)
        squawk.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.09),
            SKAction.moveBy(x: 0, y: 32, duration: 0.65),
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
    }

    /// Floating "+3 DUCK!" label for the CathyX duck-hit bonus. Rises beside the
    /// existing "SQUAWK!" callout and fades; purely visual.
    private func showDuckBonusBanner(at point: CGPoint) {
        let lbl = makeLabel(text: "+3 DUCK!",
                            size: max(8, size.width * 0.052),
                            color: SKColor(red: 1.0, green: 0.85, blue: 0.20, alpha: 1))
        lbl.position  = CGPoint(x: point.x, y: point.y - 18)
        lbl.zPosition = 305
        lbl.alpha     = 0
        gameWorldNode.addChild(lbl)
        lbl.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.10),
            SKAction.moveBy(x: 0, y: 30, duration: 0.85),
            SKAction.fadeOut(withDuration: 0.30),
            SKAction.removeFromParent(),
        ]))
    }

    // MARK: - Dragon (Barnum's cavern)

    /// Queues the next dragon emergence at a random interval. Reschedules itself so the
    /// dragon can strike multiple times per round.
    private func scheduleDragon() {
        removeAction(forKey: "dragonSchedule")
        guard isCaveMatch, gameState != .gameOver else { return }
        let delay = TimeInterval.random(in: 4.0...8.0)
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in self?.spawnDragon() },
        ]), withKey: "dragonSchedule")
    }

    private func spawnDragon() {
        guard dragonNode == nil, isCaveMatch, gameState != .gameOver, !isPausedGame else {
            scheduleDragon(); return
        }

        // The corridor airborne bags pass through; align the dragon + flame with it.
        let flameY = crowY
        // Emerge from one side of the chasm and breathe toward the opposite side.
        let fromRight = Bool.random()
        let edgeX = (size.width * 0.46) * (fromRight ? 1 : -1)

        let dragon = makeDragonNode(facingRight: !fromRight)
        dragon.position  = CGPoint(x: edgeX, y: flameY - 70)   // start sunk in the chasm
        dragon.zPosition = 19
        dragon.alpha     = 0
        gameWorldNode.addChild(dragon)
        dragonNode = dragon

        run(SKAction.playSoundFileNamed("dragon_roar.wav", waitForCompletion: false))
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // Rise → roar/wind-up → breathe flame → sink back → reschedule.
        dragon.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveTo(y: flameY, duration: 0.42),
                SKAction.fadeIn(withDuration: 0.30),
            ]),
            SKAction.wait(forDuration: 0.35),
            SKAction.run { [weak self] in
                self?.breatheFlame(fromX: edgeX, y: flameY, towardRight: !fromRight)
            },
            SKAction.wait(forDuration: 2.7),   // stay up through the sustained burn
            SKAction.group([
                SKAction.moveTo(y: flameY - 70, duration: 0.40),
                SKAction.fadeOut(withDuration: 0.34),
            ]),
            SKAction.removeFromParent(),
            SKAction.run { [weak self, weak dragon] in
                if self?.dragonNode === dragon { self?.dragonNode = nil }
                self?.scheduleDragon()
            },
        ]), withKey: "dragonAct")
    }

    /// Sweeps a wide, organic flame across the corridor for a sustained burn and ignites
    /// every airborne bag that passes through its lane for the full duration.
    private func breatheFlame(fromX startX: CGFloat, y: CGFloat, towardRight: Bool) {
        run(SKAction.playSoundFileNamed("dragon_roar.wav", waitForCompletion: false))
        run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        let dir: CGFloat = towardRight ? 1 : -1
        let reach = size.width * 1.05

        // Sustained burn timing — held ~2s longer than the old single-flash cone.
        let rampIn:  TimeInterval = 0.25
        let hold:    TimeInterval = 2.2
        let fadeOut: TimeInterval = 0.5

        // Flame container at the mouth. Built from several layered, flickering lobes
        // (deep red body → orange → yellow core) so the edges waver organically.
        let flame = SKNode()
        flame.position  = CGPoint(x: startX + 14 * dir, y: y)
        flame.zPosition = 30
        flame.alpha     = 0
        flame.xScale    = 0.2
        gameWorldNode.addChild(flame)

        let layers: [(reach: CGFloat, halfH: CGFloat, color: SKColor, count: Int)] = [
            (reach,        78, SKColor(red: 0.95, green: 0.18, blue: 0.04, alpha: 0.50), 2),
            (reach * 0.86, 58, SKColor(red: 1.00, green: 0.45, blue: 0.06, alpha: 0.70), 2),
            (reach * 0.62, 36, SKColor(red: 1.00, green: 0.82, blue: 0.18, alpha: 0.90), 2),
        ]
        for layer in layers {
            for _ in 0..<layer.count {
                let lobe = makeFlameLobe(reach: layer.reach, halfH: layer.halfH,
                                         dir: dir, color: layer.color)
                lobe.position.y = CGFloat.random(in: -8...8)
                flame.addChild(lobe)
                // Out-of-phase flicker — pulses thickness and brightness for a living look.
                let d1 = TimeInterval.random(in: 0.09...0.16)
                let d2 = TimeInterval.random(in: 0.09...0.16)
                lobe.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.group([
                        SKAction.scaleY(to: CGFloat.random(in: 0.82...1.18), duration: d1),
                        SKAction.fadeAlpha(to: CGFloat.random(in: 0.6...1.0), duration: d1),
                        SKAction.moveBy(x: 0, y: CGFloat.random(in: -6...6), duration: d1),
                    ]),
                    SKAction.group([
                        SKAction.scaleY(to: 1.0, duration: d2),
                        SKAction.fadeAlpha(to: 1.0, duration: d2),
                    ]),
                ])))
            }
        }

        flame.run(SKAction.sequence([
            SKAction.group([
                SKAction.scaleX(to: 1.0, duration: rampIn),
                SKAction.fadeIn(withDuration: rampIn * 0.6),
            ]),
            SKAction.wait(forDuration: hold),
            SKAction.fadeOut(withDuration: fadeOut),
            SKAction.removeFromParent(),
        ]))

        // Rolling embers along the lane for the whole burn.
        let emberBurst = SKAction.run { [weak self] in
            self?.spawnFlameEmbers(fromX: startX, y: y, reach: reach, dir: dir)
        }
        run(SKAction.sequence([
            SKAction.repeat(SKAction.sequence([emberBurst,
                                               SKAction.wait(forDuration: 0.18)]),
                            count: Int(hold / 0.18)),
        ]))

        // Continuously ignite airborne bags crossing the lane for the full burn, so bags
        // that enter the flame later still catch — not just those there at the first frame.
        let bandH: CGFloat = 80
        let scan = SKAction.run { [weak self] in
            guard let self else { return }
            for bag in self.activeBags {
                guard !bag.isGrounded, bag.bz > 2, !bag.isFire else { continue }
                let visualY = bag.by + bag.bz * 0.5
                guard abs(visualY - y) < bandH else { continue }
                self.igniteBag(bag)
            }
        }
        run(SKAction.sequence([
            SKAction.wait(forDuration: rampIn * 0.5),
            SKAction.repeat(SKAction.sequence([scan, SKAction.wait(forDuration: 0.08)]),
                            count: Int((hold + fadeOut) / 0.08)),
        ]), withKey: "dragonFlameScan")
    }

    /// One organic flame lobe — a wavering lens shape from the mouth to a tapered tip.
    private func makeFlameLobe(reach: CGFloat, halfH: CGFloat,
                               dir: CGFloat, color: SKColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: .zero)
        let steps = 7
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = reach * t * dir
            let bulge = sin(t * .pi)                       // 0 at mouth/tip, fat in the middle
            let yTop = halfH * bulge * CGFloat.random(in: 0.7...1.2)
            path.addLine(to: CGPoint(x: x, y: yTop))
        }
        for i in stride(from: steps, through: 1, by: -1) {
            let t = CGFloat(i) / CGFloat(steps)
            let x = reach * t * dir
            let bulge = sin(t * .pi)
            let yBot = -halfH * bulge * CGFloat.random(in: 0.7...1.2)
            path.addLine(to: CGPoint(x: x, y: yBot))
        }
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor   = color
        node.strokeColor = .clear
        node.glowWidth   = 5
        node.blendMode   = .add
        return node
    }

    /// Scatters a few rising embers across the flame lane.
    private func spawnFlameEmbers(fromX startX: CGFloat, y: CGFloat, reach: CGFloat, dir: CGFloat) {
        let emberColors: [SKColor] = [
            SKColor(red: 1.0,  green: 0.90, blue: 0.10, alpha: 1),
            SKColor(red: 1.0,  green: 0.45, blue: 0.05, alpha: 1),
            SKColor(red: 0.95, green: 0.15, blue: 0.05, alpha: 1),
        ]
        for _ in 0..<8 {
            let p = SKSpriteNode(color: emberColors.randomElement()!,
                                 size: CGSize(width: CGFloat.random(in: 4...8),
                                              height: CGFloat.random(in: 4...8)))
            p.position  = CGPoint(x: startX + CGFloat.random(in: 0...reach) * dir,
                                  y: y + CGFloat.random(in: -32...32))
            p.zPosition = 31
            p.blendMode = .add
            gameWorldNode.addChild(p)
            p.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: CGFloat.random(in: -12...12),
                                    y: CGFloat.random(in: 30...75), duration: 0.6),
                    SKAction.fadeOut(withDuration: 0.6),
                ]),
                SKAction.removeFromParent(),
            ]))
        }
    }

    /// Converts an airborne bag into a fire bag mid-flight (recolor + flame marker + poof).
    private func igniteBag(_ bag: MiniGameBag) {
        guard !bag.isFire, !bag.isDestroyed else { return }
        bag.isFire = true

        let fireColor = bag.owner == .player
            ? SKColor(red: 0.95, green: 0.30, blue: 0.05, alpha: 1)
            : SKColor(red: 0.90, green: 0.22, blue: 0.02, alpha: 1)
        bag.node.color            = fireColor
        bag.node.colorBlendFactor = 0.88

        // Flame marker + flicker, mirroring a natively-built fire bag.
        if bag.node.childNode(withName: "igniteFlame") == nil {
            let flame = SKLabelNode(text: "🔥")
            flame.name = "igniteFlame"
            flame.fontSize                = 13
            flame.verticalAlignmentMode   = .center
            flame.horizontalAlignmentMode = .center
            flame.position  = .zero
            flame.zPosition = 1
            bag.node.addChild(flame)
            bag.node.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.70, duration: 0.18),
                SKAction.fadeAlpha(to: 1.00, duration: 0.18),
            ])), withKey: "fireFlicker")
        }

        showFireEffect(at: CGPoint(x: bag.bx, y: bag.by + bag.bz * 0.5))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Cave Bat

    /// Schedules a delayed snatch attempt mid-flight. If, at the time it fires, the
    /// bag is still airborne and nothing else has claimed the airspace (no dragon,
    /// no other bat, not ignited, not destroyed, not yet grounded/scored), a bat
    /// swoops in and carries the bag to a drop point.
    private func scheduleBatSnatch(for bag: MiniGameBag) {
        let delay = Double.random(in: 0.25...0.45)
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self, weak bag] in
                guard let s = self, let bag = bag else { return }
                guard s.isCaveMatch, s.dragonNode == nil, s.batNode == nil,
                      s.gameState != .gameOver, !s.isPausedGame else { return }
                guard !bag.isDestroyed, !bag.isGrounded, !bag.hasScored,
                      !bag.isFire, !bag.isCarriedByBat, bag.bz > 6 else { return }
                s.snatchBagWithBat(bag)
            },
        ]))
    }

    /// Builds the bat, flies it in to the bag, carries the bag to a drop point above
    /// the board, releases the bag (it falls and lands at the target — original
    /// thrower still scores), then flies the bat off the opposite side.
    private func snatchBagWithBat(_ bag: MiniGameBag) {
        // Drop target — 75% random board point, 25% in the hole.
        let dropTarget: CGPoint
        if Double.random(in: 0..<1) < 0.25 {
            dropTarget = holeCenter
        } else {
            dropTarget = CGPoint(
                x: CGFloat.random(in: -boardHalfW * 0.80 ... boardHalfW * 0.80),
                y: CGFloat.random(in: (boardY - boardHalfH * 0.80) ... (boardY + boardHalfH * 0.80))
            )
        }

        // Bat enters from above — diving from the cave ceiling toward the bag.
        // Loop direction will swing toward whichever screen edge is opposite the bag.
        let halfW = size.width / 2
        let halfH = size.height / 2
        let fromRight = bag.bx < 0    // affects loop direction + exit side, not entry
        let exitX   = fromRight ? -halfW - 60 :  halfW + 60
        // Freeze the bag in mid-air *now* (before the telegraph plays). Otherwise
        // its arc would land it on the board before the bat finishes diving.
        // `isCarriedByBat` short-circuits physics, collisions, and the deform spring;
        // the bag just hangs at this position until the carry phase moves it.
        bag.isCarriedByBat = true
        bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
        let bagScreen = CGPoint(x: bag.bx, y: bag.by + bag.bz * 0.5)
        // Bat starts off-screen top, slightly to the side of the bag so the dive
        // has a visible diagonal sweep instead of dropping straight down.
        let entryOffsetX: CGFloat = fromRight ? 70 : -70
        let entryPos = CGPoint(x: bagScreen.x + entryOffsetX, y: halfH + 80)

        // Telegraph — a pulsing yellow exclamation that appears at the snatch point
        // for ~0.45s before the bat arrives, so the player knows where to look.
        let telegraph = SKLabelNode(text: "!")
        telegraph.fontName             = "PressStart2P-Regular"
        telegraph.fontSize             = 22
        telegraph.fontColor            = SKColor(red: 1.0, green: 0.85, blue: 0.20, alpha: 1)
        telegraph.position             = CGPoint(x: bagScreen.x, y: bagScreen.y + 28)
        telegraph.zPosition            = 60
        telegraph.verticalAlignmentMode   = .center
        telegraph.horizontalAlignmentMode = .center
        telegraph.setScale(0.1)
        gameWorldNode.addChild(telegraph)
        telegraph.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.4, duration: 0.18),
                SKAction.fadeAlpha(to: 1.0, duration: 0.10),
            ]),
            SKAction.repeat(SKAction.sequence([
                SKAction.scale(to: 1.0, duration: 0.10),
                SKAction.scale(to: 1.4, duration: 0.10),
            ]), count: 2),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.18),
                SKAction.scale(to: 0.6, duration: 0.18),
            ]),
            SKAction.removeFromParent(),
        ]))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        run(SKAction.playSoundFileNamed("gopher_pop.wav", waitForCompletion: false))

        let bat = makeBatNode(facingRight: !fromRight)
        bat.position  = entryPos
        bat.zPosition = 50
        // Hidden during the telegraph window, then appears and dives.
        bat.alpha = 0
        bat.setScale((distanceScale < 1.0 ? 1.1 : 1.0) * 1.6)   // larger on entry — perspective cue
        gameWorldNode.addChild(bat)
        batNode = bat

        // Phase 0: hold off-screen while the telegraph plays. ~0.45s.
        let waitForTelegraph = SKAction.wait(forDuration: 0.45)
        let appear = SKAction.fadeAlpha(to: 1.0, duration: 0.08)

        // Phase 1: dive from above to the bag. ~0.6s, with a slight ease-in so it
        // accelerates downward like a real swoop. The bat shrinks to its carry
        // size as it "lands" on the bag, selling depth.
        let dive = SKAction.group([
            SKAction.move(to: CGPoint(x: bagScreen.x, y: bagScreen.y + 14), duration: 0.60),
            SKAction.scale(to: (distanceScale < 1.0 ? 1.1 : 1.0), duration: 0.60),
        ])
        dive.timingMode = .easeIn

        // Snap the bag onto the bat: freeze physics, lock its world position to the
        // bag's current spot. The carry phase moves bag.node directly.
        let grab = SKAction.run { [weak self, weak bag] in
            guard let s = self, let bag = bag else { return }
            guard !bag.isDestroyed, !bag.hasScored else { return }
            bag.isCarriedByBat = true
            bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            s.run(SKAction.playSoundFileNamed("hit.mp3", waitForCompletion: false))
        }

        // Phase 2: rise, fly a visible loop with the bag, then descend to the drop
        // point. ~1.6s total — slow enough to read what's happening.
        // The trajectory has three sub-phases (all in one customAction):
        //   t ∈ [0.00, 0.22]  rise from snatch point up to the loop entry
        //   t ∈ [0.22, 0.75]  one full circular loop around `loopCenter`
        //   t ∈ [0.75, 1.00]  glide across to hover above the drop point
        let carryDuration: TimeInterval = 2.4
        let hoverHeight: CGFloat = 70
        let startBatPos = CGPoint(x: bagScreen.x, y: bagScreen.y + 14)
        let endBatPos   = CGPoint(x: dropTarget.x, y: dropTarget.y + hoverHeight + 14)

        // Loop sits between the snatch point and the drop point, biased up-screen
        // so the loop arc is on-camera even when the bag was grabbed low.
        let loopCenter = CGPoint(
            x: (startBatPos.x + endBatPos.x) * 0.5,
            y: max(startBatPos.y, endBatPos.y) + 70
        )
        let loopRadius: CGFloat = 46
        // Loop entry: bottom of the circle — bat sweeps in from below and circles up.
        let loopEntry = CGPoint(x: loopCenter.x, y: loopCenter.y - loopRadius)
        // Loop direction: spin away from the screen edge the bat entered from so the
        // arc reads naturally rather than crossing back over itself.
        let loopCW = fromRight   // entered from right → clockwise loop reads "forward"

        let carry = SKAction.customAction(withDuration: carryDuration) { [weak self, weak bag, weak bat] _, elapsed in
            guard let s = self, let bag = bag, let bat = bat else { return }
            let t = max(0, min(1, CGFloat(elapsed / CGFloat(carryDuration))))

            let bx: CGFloat
            let by: CGFloat
            if t < 0.22 {
                // Rise to loop entry.
                let u = t / 0.22
                let e = u * u * (3 - 2 * u)
                bx = startBatPos.x + (loopEntry.x - startBatPos.x) * e
                by = startBatPos.y + (loopEntry.y - startBatPos.y) * e
            } else if t < 0.75 {
                // Full circle around loopCenter, starting at the bottom (entry).
                let u = (t - 0.22) / (0.75 - 0.22)
                // -π/2 is straight down from center (loopEntry). Sweep ±2π for one revolution.
                let dir: CGFloat = loopCW ? -1 : 1
                let angle = -CGFloat.pi / 2 + dir * (2 * CGFloat.pi) * u
                bx = loopCenter.x + loopRadius * cos(angle)
                by = loopCenter.y + loopRadius * sin(angle)
            } else {
                // Glide from loop entry across to the drop hover position.
                let u = (t - 0.75) / 0.25
                let e = u * u * (3 - 2 * u)
                bx = loopEntry.x + (endBatPos.x - loopEntry.x) * e
                by = loopEntry.y + (endBatPos.y - loopEntry.y) * e
            }
            bat.position = CGPoint(x: bx, y: by)

            // Bag dangles ~14pt below the bat's body. Lift bz gradually so the
            // released bag drops from a clean hover height.
            bag.bx = bx
            let bz = max(0, hoverHeight * (0.55 + 0.45 * t))
            bag.bz = bz
            bag.by = (by - 14) - bz * 0.5
            bag.node.position   = CGPoint(x: bag.bx, y: bag.by + bag.bz * 0.5)
            bag.shadow.position = CGPoint(x: bag.bx + bag.bz * 0.08, y: bag.by)
            bag.shadow.alpha    = max(0.08, 0.35 - bag.bz * 0.005)
            bag.shadow.setScale(max(0.5, 1.0 - bag.bz * 0.005) * s.distanceScale)
            bag.node.zPosition  = 20 + bag.bz * 0.1 - bag.by * 0.02
        }

        // Phase 3: release the bag — set it directly above the drop target with zero
        // velocity, then resume physics (gravity will drop it straight down). The
        // original thrower's `owner` is intact, so scoring credits the right player.
        let release = SKAction.run { [weak bag] in
            guard let bag = bag, !bag.isDestroyed else { return }
            bag.bx = dropTarget.x
            bag.by = dropTarget.y
            bag.bz = hoverHeight
            bag.vx = 0; bag.vy = 0; bag.vz = 0
            bag.rotV = 0
            bag.isCarriedByBat = false
        }

        // Phase 4: flap off-screen upward and to the opposite side — back to the
        // cave ceiling it came from. Scales up again on the way out for visibility.
        let exit = SKAction.group([
            SKAction.move(to: CGPoint(x: exitX, y: halfH + 100), duration: 0.85),
            SKAction.scale(to: (distanceScale < 1.0 ? 1.1 : 1.0) * 1.3, duration: 0.85),
            SKAction.fadeAlpha(to: 0.0, duration: 0.85),
        ])
        exit.timingMode = .easeIn

        bat.run(SKAction.sequence([
            waitForTelegraph, appear, dive, grab, carry, release, exit,
            SKAction.removeFromParent(),
            SKAction.run { [weak self, weak bat] in
                if self?.batNode === bat { self?.batNode = nil }
            },
        ]))
    }

    /// Builds a chunky pixel-art bat: dark body, two flapping triangle wings, glowing eyes.
    private func makeBatNode(facingRight: Bool) -> SKNode {
        let bat = SKNode()
        // Bumped up from near-black so the bat reads against the dark cave floor.
        let fur  = SKColor(red: 0.42, green: 0.28, blue: 0.46, alpha: 1)   // dusky purple
        let dark = SKColor(red: 0.22, green: 0.14, blue: 0.26, alpha: 1)
        let eye  = SKColor(red: 1.00, green: 0.85, blue: 0.20, alpha: 1)

        // Body
        let body = SKSpriteNode(color: fur, size: CGSize(width: 16, height: 14))
        bat.addChild(body)

        // Head
        let head = SKSpriteNode(color: fur, size: CGSize(width: 12, height: 10))
        head.position = CGPoint(x: 0, y: 8)
        bat.addChild(head)

        // Ears (two small triangles)
        for ex in [-4, 4] {
            let ear = makeTriangle(width: 4, height: 6, color: dark, pointingDown: false)
            ear.position = CGPoint(x: CGFloat(ex), y: 14)
            bat.addChild(ear)
        }

        // Eyes
        let eyeL = SKSpriteNode(color: eye, size: CGSize(width: 2, height: 2))
        eyeL.position = CGPoint(x: -3, y: 9)
        bat.addChild(eyeL)
        let eyeR = SKSpriteNode(color: eye, size: CGSize(width: 2, height: 2))
        eyeR.position = CGPoint(x: 3, y: 9)
        bat.addChild(eyeR)

        // Wings — large triangles that flap by squashing horizontally. Each wing
        // sits in a pivot container at the body edge so xScale squashes toward
        // the body (proper wingbeat) rather than collapsing into thin air.
        let leftPivot = SKNode()
        leftPivot.position = CGPoint(x: -8, y: 0)
        bat.addChild(leftPivot)
        let leftWing = makeTriangle(width: 22, height: 14, color: fur, pointingDown: false)
        leftWing.position = CGPoint(x: -11, y: -2)   // base centered 11pt out from pivot
        leftWing.zRotation = -.pi / 2                // base now runs vertical along the body edge
        leftPivot.addChild(leftWing)

        let rightPivot = SKNode()
        rightPivot.position = CGPoint(x: 8, y: 0)
        bat.addChild(rightPivot)
        let rightWing = makeTriangle(width: 22, height: 14, color: fur, pointingDown: false)
        rightWing.position = CGPoint(x: 11, y: -2)
        rightWing.zRotation = .pi / 2
        rightPivot.addChild(rightWing)

        // Flap: squash wing pivot on X axis to read as wingbeats.
        let flap = SKAction.sequence([
            SKAction.scaleX(to: 0.4, duration: 0.12),
            SKAction.scaleX(to: 1.0, duration: 0.12),
        ])
        leftPivot.run(SKAction.repeatForever(flap))
        rightPivot.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 0.12),
            flap,
        ])))

        bat.setScale(distanceScale < 1.0 ? 1.1 : 1.0)
        if !facingRight { bat.xScale *= -1 }
        return bat
    }

    /// An off-board bag that lands in the chasm tumbles straight down and vanishes into
    /// the dark. It counts as a miss (0 pts) and is pulled out of collisions/scoring.
    private func fallIntoChasm(_ bag: MiniGameBag) {
        guard !bag.isFallingInChasm else { return }
        bag.isFallingInChasm = true
        bag.isGrounded = true
        bag.vx = 0; bag.vy = 0; bag.vz = 0; bag.rotV = 0
        // Action-owned from here: excluded from collision resolution and the deform spring.
        bag.hasAppliedGroundScale = true
        bag.node.warpGeometry = nil
        bag.node.removeAllActions()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Top-down view: "falling" reads as receding away from the camera, so the bag
        // shrinks toward nothing in place (no downward screen translation) while spinning
        // and fading into the dark.
        let spin = CGFloat.random(in: 3...6) * (Bool.random() ? 1 : -1)
        let fall = SKAction.group([
            SKAction.scale(to: 0.02, duration: 1.0),
            SKAction.rotate(byAngle: spin, duration: 1.0),
            SKAction.sequence([SKAction.wait(forDuration: 0.45),
                               SKAction.fadeOut(withDuration: 0.55)]),
        ])
        fall.timingMode = .easeIn
        bag.node.run(SKAction.sequence([fall, SKAction.hide()]))
        bag.shadow.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.2),
                                          SKAction.removeFromParent()]))
    }

    /// Builds the dragon head from chunky shapes — green scales, horns, eye, open maw.
    private func makeDragonNode(facingRight: Bool) -> SKNode {
        let dragon = SKNode()
        let scaleColor = SKColor(red: 0.20, green: 0.52, blue: 0.22, alpha: 1)
        let darkScale  = SKColor(red: 0.12, green: 0.34, blue: 0.14, alpha: 1)

        // Head block
        let head = SKSpriteNode(color: scaleColor, size: CGSize(width: 46, height: 38))
        dragon.addChild(head)

        // Snout extending forward
        let snout = SKSpriteNode(color: scaleColor, size: CGSize(width: 26, height: 20))
        snout.position = CGPoint(x: 30, y: -4)
        dragon.addChild(snout)

        // Open maw (dark) with a glowing throat
        let maw = SKSpriteNode(color: SKColor(red: 0.10, green: 0.05, blue: 0.03, alpha: 1),
                               size: CGSize(width: 16, height: 9))
        maw.position = CGPoint(x: 38, y: -7)
        dragon.addChild(maw)
        let glow = SKSpriteNode(color: SKColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 0.9),
                                size: CGSize(width: 8, height: 5))
        glow.position = CGPoint(x: 42, y: -7)
        glow.blendMode = .add
        dragon.addChild(glow)

        // Horns
        for hx in [-10, 6] {
            let horn = makeTriangle(width: 9, height: 16, color: darkScale, pointingDown: false)
            horn.position = CGPoint(x: CGFloat(hx), y: 18)
            dragon.addChild(horn)
        }

        // Brow ridge + eye
        let eyeWhite = SKSpriteNode(color: SKColor(red: 1.0, green: 0.85, blue: 0.20, alpha: 1),
                                    size: CGSize(width: 11, height: 11))
        eyeWhite.position = CGPoint(x: 8, y: 6)
        dragon.addChild(eyeWhite)
        let pupil = SKSpriteNode(color: .black, size: CGSize(width: 4, height: 9))
        pupil.position = CGPoint(x: 11, y: 6)
        dragon.addChild(pupil)

        // Nostril
        let nostril = SKSpriteNode(color: darkScale, size: CGSize(width: 4, height: 4))
        nostril.position = CGPoint(x: 40, y: -1)
        dragon.addChild(nostril)

        dragon.setScale(distanceScale < 1.0 ? 1.3 : 1.0)
        if !facingRight { dragon.xScale *= -1 }
        return dragon
    }

    // MARK: - Opponent Selection

    private func showOpponentPicker() {
        if let pre = preSelectedOpponent {
            selectedOpponent = pre
            switch pre {
            case .billy:  applyBillySettings()
            case .spirit: applySpiritSettings()
            case .bully:  applyBullySettings()
            case .barnum: applyBarnumSettings()
            case .cathy:  applyCathySettings()
            default: break
            }
            rollWeatherScenarios()
            addOpponentPortrait()
            if TutorialManager.shared.hasSeen(TutorialManager.cornhole) {
                showCathyRulesIfNeeded { [weak self] in self?.startRound() }
            } else {
                showFirstTimeTutorial()
            }
            return
        }
        let configs: [OpponentConfig] = [
            OpponentConfig(name: "TOM",    imageName: "tom",
                           traitText: "TOPS YOUR HOLE SHOTS",
                           textureOverride: CornholeMiniGameScene.makeTomPortraitTexture()),
            OpponentConfig(name: "JENNY",  imageName: "jenny",
                           traitText: "KNOCKS BAGS OFF BOARD",
                           textureOverride: CornholeMiniGameScene.makeJennyPortraitTexture()),
            OpponentConfig(name: "BARNUM", imageName: "barnum",
                           traitText: "DRAGON CAVE • TO 21",
                           textureOverride: CornholeMiniGameScene.makeBarnumPortraitTexture()),
            OpponentConfig(name: "BILLY",  imageName: "billy",
                           traitText: "MATCHES YOUR SKILL • TO 21",
                           textureOverride: CornholeMiniGameScene.makeBillyPortraitTexture()),
            OpponentConfig(name: "SPIRIT", imageName: "spirit",
                           traitText: "DROPS MAGIC BAGS • TO 21",
                           textureOverride: CornholeMiniGameScene.makeSpiritPortraitTexture()),
            OpponentConfig(name: "CATHYX", imageName: "cathy",
                           traitText: "HOLE COSTS YOU 3 PTS!",
                           textureOverride: CornholeMiniGameScene.makeCathyPortraitTexture()),
        ]
        let picker = OpponentPickerNode(opponents: configs, sceneSize: size)
        picker.zPosition = 3000
        picker.onSelected = { [weak self] index in
            guard let self else { return }
            switch index {
            case 0: self.selectedOpponent = .tom
            case 1: self.selectedOpponent = .jenny
            case 2:
                self.selectedOpponent = .barnum
                self.applyBarnumSettings()
            case 3:
                self.selectedOpponent = .billy
                self.applyBillySettings()
            case 4:
                self.selectedOpponent = .spirit
                self.applySpiritSettings()
            default:
                self.selectedOpponent = .cathy
                self.applyCathySettings()
            }
            self.rollWeatherScenarios()
            self.addOpponentPortrait()
            if TutorialManager.shared.hasSeen(TutorialManager.cornhole) {
                self.showCathyRulesIfNeeded { [weak self] in self?.startRound() }
            } else {
                self.showFirstTimeTutorial()
            }
        }
        addChild(picker)
    }

    /// Configures Barnum: a 21-point long-distance match thrown across a dark cavern.
    /// No weather, no gophers — instead a dragon periodically rises from the chasm and
    /// breathes flame, turning any bag it catches mid-flight into a fire bag.
    private func applyBarnumSettings() {
        winScore = 21
        rainStartRound  = -1
        rainEndRound    = Int.max
        stormStartRound = -1
        stormEndRound   = Int.max
        isCaveMatch = true
        // Long-distance variant: shrink board, hole, and bags to simulate a longer throw
        distanceScale = 0.5
        rebuildPlayfieldForDistance()
        applyCaveScenery()
    }

    /// Configures CathyX: a standard 11-point match on the normal-distance board, but
    /// with inverted scoring — you only score by landing ON the board, and dropping a
    /// bag in the hole costs the thrower 3 points (see calculateCathyRoundScore). No
    /// special weather or scenery; the twist is purely in how points are tallied.
    private func applyCathySettings() {
        winScore = 7
        isCathyMatch = true
        addCathyHoleMarker()
    }

    /// Paints a chunky red X inside the cornhole for CathyX matches — a visual reminder
    /// that the hole is a trap (-3 pts) in this game type. Sized to the current hole
    /// radius so it survives `distanceScale` changes (none today, but future-proof).
    private func addCathyHoleMarker() {
        guard let board = boardContainerNode else { return }
        board.childNode(withName: "cathyHoleMarker")?.removeFromParent()

        let marker = SKNode()
        marker.name = "cathyHoleMarker"
        let holeRelY = holeCenter.y - boardY
        marker.position = CGPoint(x: 0, y: holeRelY)
        marker.zPosition = 3                          // sits above the hole sprite

        let red       = UIColor(red: 0.92, green: 0.20, blue: 0.18, alpha: 1)
        let length    = holeRadius * 1.30             // crosses just past the rim
        let thickness = max(2.5, holeRadius * 0.18)   // chunky pixel-art stroke

        let bar1 = SKSpriteNode(color: red, size: CGSize(width: length, height: thickness))
        bar1.zRotation = .pi / 4
        marker.addChild(bar1)

        let bar2 = SKSpriteNode(color: red, size: CGSize(width: length, height: thickness))
        bar2.zRotation = -.pi / 4
        marker.addChild(bar2)

        board.addChild(marker)
    }

    /// Configures Tree Spirit game overrides: score to 21, long-distance throw, and
    /// a permanent moonlit thunderstorm (blue night tint + rain + lightning + wind).
    private func applySpiritSettings() {
        winScore = 21
        // Force thunderstorm for the entire match — sells the spooky night setting
        rainStartRound  = -1
        rainEndRound    = Int.max
        stormStartRound = 1
        stormEndRound   = Int.max
        // Long-distance variant: shrink board, hole, and bags to simulate a longer throw
        distanceScale = 0.5
        rebuildPlayfieldForDistance()
    }

    /// Configures Billy's gang member (street-bully ambush): quick 7-point match,
    /// standard difficulty. Used by world-map bully encounters.
    private func applyBullySettings() {
        winScore = 7
    }

    /// Configures all Billy-specific overrides after opponent selection.
    private func applyBillySettings() {
        winScore = 21
        // Force thunderstorm for the entire match — no random rain
        rainStartRound  = -1
        rainEndRound    = Int.max
        stormStartRound = 1
        stormEndRound   = Int.max
        billyNoiseFactor = computeBillyInitialNoise()
        billyBombBagsRemaining = computeBillyBombCount()
        // Long-distance variant: shrink board, hole, and bags to simulate a longer throw
        distanceScale = 0.5
        rebuildPlayfieldForDistance()
    }

    /// Re-runs layout math and rebuilds the board container after `distanceScale` changes.
    /// Bag/gopher/crow visuals pick up the new scale on their next render.
    private func rebuildPlayfieldForDistance() {
        computeLayout()
        boardContainerNode?.removeFromParent()
        boardContainerNode = nil
        setupBoard()
        throwLineNode?.size = CGSize(width: boardHalfW * 1.2, height: 1)
    }

    /// Computes Billy's initial noise factor from the player's career cornhole accuracy.
    /// Returns a value in [0.8, 3.5]: 3.5 = beginner, 0.8 = expert.
    private func computeBillyInitialNoise() -> CGFloat {
        let stats = CornholeStatsManager.shared
        let totalGames = stats.wins + stats.losses
        guard totalGames > 0 else { return 3.2 }
        // ~12 throw opportunities per game (4 bags × ~3 rounds avg)
        let rate = CGFloat(stats.cornholes) / (CGFloat(totalGames) * 12.0)
        let clamped = min(rate, 1.0)
        return max(1.4, 3.8 - clamped * 2.1)
    }

    /// Billy starts with more bomb bags when the player is more skilled (higher stakes).
    private func computeBillyBombCount() -> Int {
        if billyNoiseFactor > 2.8 { return 1 }
        if billyNoiseFactor > 1.8 { return 2 }
        return 3
    }

    private func addOpponentPortrait() {
        opponentPortrait?.removeFromParent()
        let tex: SKTexture
        switch selectedOpponent {
        case .tom:    tex = CornholeMiniGameScene.makeTomPortraitTexture()
        case .jenny:  tex = CornholeMiniGameScene.makeJennyPortraitTexture()
        case .billy:  tex = CornholeMiniGameScene.makeBillyPortraitTexture()
        case .spirit: tex = CornholeMiniGameScene.makeSpiritPortraitTexture()
        case .barnum: tex = CornholeMiniGameScene.makeBarnumPortraitTexture()
        case .bully:  tex = CornholeMiniGameScene.makeBullyPortraitTexture()
        case .cathy:  tex = CornholeMiniGameScene.makeCathyPortraitTexture()
        }
        let portraitSize = CGSize(width: 48, height: 48)
        let bottomH = size.height * 0.09
        let portrait = SKSpriteNode(texture: tex, size: portraitSize)
        portrait.position  = CGPoint(x: -size.width / 2 + 28,
                                     y: -size.height / 2 + bottomH / 2)
        portrait.zPosition = 650
        addChild(portrait)
        opponentPortrait = portrait
    }

    private func addPlayerPortrait() {
        playerPortrait?.removeFromParent()
        let tex = CornholeMiniGameScene.makeJeffPortraitTexture()
        let bottomH = size.height * 0.09
        let portrait = SKSpriteNode(texture: tex, size: CGSize(width: 48, height: 48))
        portrait.position  = CGPoint(x: size.width / 2 - 28,
                                     y: -size.height / 2 + bottomH / 2)
        portrait.zPosition = 650
        addChild(portrait)
        playerPortrait = portrait
    }

    // MARK: - Pause / Resume

    private func pauseGame() {
        guard !isPausedGame, gameState != .gameOver else { return }
        isPausedGame = true
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
        dim.fillColor = SKColor(white: 0, alpha: 0.65); dim.strokeColor = .clear; ov.addChild(dim)

        let panelW: CGFloat = min(W - 48, 280), panelH: CGFloat = 200
        let panel = SKShapeNode(rect: CGRect(x: -panelW / 2, y: -panelH / 2, width: panelW, height: panelH), cornerRadius: 10)
        panel.fillColor   = SKColor(red: 0.10, green: 0.04, blue: 0.02, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        panel.lineWidth   = 2; ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "PAUSED"; title.fontSize = 16
        title.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 56); ov.addChild(title)

        let btnW = panelW - 40, btnH: CGFloat = 44
        let resumeBg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2, width: btnW, height: btnH), cornerRadius: 8)
        resumeBg.fillColor   = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.20)
        resumeBg.strokeColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 0.80)
        resumeBg.lineWidth   = 1.5; resumeBg.position = CGPoint(x: 0, y: 6)
        resumeBg.name = "resumeBtn"; ov.addChild(resumeBg)

        let resumeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        resumeLbl.text = "RESUME"; resumeLbl.fontSize = 11
        resumeLbl.fontColor = SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
        resumeLbl.horizontalAlignmentMode = .center; resumeLbl.verticalAlignmentMode = .center
        resumeLbl.position = CGPoint(x: 0, y: -1); resumeLbl.name = "resumeBtn"; resumeBg.addChild(resumeLbl)

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: 0, y: -62); ov.addChild(help)

        let helpHint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        helpHint.text = "TUTORIAL"; helpHint.fontSize = 7
        helpHint.fontColor = SKColor(white: 0.6, alpha: 0.8)
        helpHint.horizontalAlignmentMode = .center; helpHint.verticalAlignmentMode = .top
        helpHint.position = CGPoint(x: 0, y: -80); ov.addChild(helpHint)
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        if tomFartActive { deactivateTomFart() }
        if playerWon { CornholeStatsManager.shared.recordWin() }
        else         { CornholeStatsManager.shared.recordLoss() }
        if playerWon && selectedOpponent == .tom    { CornholeStatsManager.shared.recordDefeatedTom() }
        if playerWon && selectedOpponent == .jenny  { CornholeStatsManager.shared.recordDefeatedJenny() }
        if awardsRewards && playerWon && selectedOpponent == .billy  { bombBagsEarned  = 3; coinsEarned = 10 }
        if awardsRewards && playerWon && selectedOpponent == .bully  { coinsEarned = 10 }
        if awardsRewards && playerWon && selectedOpponent == .spirit { magicBagsEarned = 6 }
        if awardsRewards && playerWon && selectedOpponent == .barnum { fireBagsEarned  = 3 }
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        SceneTransition.iris(in: view, to: prev)
    }
}
