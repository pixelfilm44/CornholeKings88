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
    /// True only when launched from the world map / story mode; gates prize display.
    var awardsRewards: Bool = false
    /// AI style injected by story mode; defaults to standard for free-play.
    var aiDifficulty: BaseballAIDifficulty = .standard

    /// When true (free-play picker path), show the Jen/Tommy opponent picker
    /// before play begins. Story path leaves this false and pre-sets aiDifficulty.
    var showOpponentPicker = false
    private var opponentPickerNode: SKNode?

    /// Name shown for the AI in the score HUD ("BOT" by default; "JEN" / "TOM" /
    /// "TOMMY" once an opponent is known). Set by the picker or derived from `aiDifficulty`.
    private var opponentDisplayName = "BOT"

    /// The player-tunable character matching the current opponent, or nil for the
    /// generic BOT (never tuned). Maps by HUD name: JEN → jen, TOM/TOMMY → tom.
    private var tuningCharacter: BaseballAISettings.Character? {
        switch opponentDisplayName {
        case "JEN":          return .jen
        case "TOM", "TOMMY": return .tom
        default:             return nil
        }
    }
    /// Difficulty multiplier set by the player in Settings → Baseball AI (1.0 when untuned / BOT).
    private func aiMult(_ stat: BaseballAISettings.Stat) -> CGFloat {
        guard let c = tuningCharacter else { return 1.0 }
        return BaseballAISettings.shared.multiplier(c, stat)
    }

    // MARK: - HUD (SwiftUI overlay, owned by this scene)
    private let hudViewModel = BaseballHUDViewModel()
    private var hudHostingController: UIHostingController<BaseballHUDView>?
    private var closeUIButton: UIButton?
    private var pauseUIButton: UIButton?
    private var crtUIOverlay: UIView?

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
    private let totalCycles    = 3   // innings
    private let outsPerHalf    = 3   // a batting half ends after 3 outs
    private let strikesPerOut  = 3   // 3 strikes = 1 out (a hit resets the running count)
    private let gravity: CGFloat   = 0.22
    private let distScale: CGFloat = 0.55  // scene-units → display "ft"
    private let homeRunFt: CGFloat = 800   // a hit landing past this display-distance is a home run
    /// World Y of the outfield home-run wall (a hit landing at/below this clears it).
    private var homeRunWallY: CGFloat { batY - homeRunFt / distScale }
    /// Field-side face of the home-run wall — a chasing fielder cannot run past this
    /// into the crowd. (Wall sprite is `size.height * 0.06` tall, centred on `homeRunWallY`.)
    private var fielderWallStopY: CGFloat { homeRunWallY + size.height * 0.03 + 6 }

    // MARK: - Game state
    private var phase: GamePhase = .userBatting
    private var currentCycle  = 1
    // Out / strike tracking for the current half-inning. A half ends at `outsPerHalf`
    // outs; the running strike count rolls to an out at `strikesPerOut` and is reset
    // to 0 by any hit (safe or caught) — i.e. whenever a new batter steps up.
    private var userOuts    = 0
    private var aiOuts      = 0
    private var userStrikes = 0
    private var aiStrikes   = 0
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

    // Phase-transition state (tutorial state is owned by TutorialOverlay itself)
    private var phaseTransitionActive = false

    private var isPausedGame = false
    private var pauseOverlayNode: SKNode?
    private var confirmingQuit = false
    private var confirmPanel: SKNode?

    // Tracks which half is active for HUD display — stays stable through .tracking/.gameOver
    private var isUserBattingHalf = true

    // Bat barrel contact zone (computed from batNode geometry, valid after setupBatter)
    private var batBarrelMinX: CGFloat {
        batNode.position.x - batNode.size.width * batNode.anchorPoint.x + 16
    }
    private var batBarrelMaxX: CGFloat {
        batNode.position.x + batNode.size.width * (1 - batNode.anchorPoint.x)
    }
    private var batBarrelCenterY: CGFloat { batNode.position.y }

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
    // Home-run-wall knockout: > 0 means the fielder is sprawled and frozen for that many frames.
    private var userFielderStunFrames: Int = 0
    private var aiFielderStunFrames:   Int = 0
    private let fielderSpeed:         CGFloat = 4.0
    private let fielderCatchRadius:   CGFloat = 30

    // Opponent character art (jen_sprite / tom_sprite). Built once the opponent is
    // known; the AI fielder runs a walk cycle from these and the AI pitcher figure
    // shows the idle frame. nil for the generic "BOT" (keeps the plain square).
    private enum FieldFacing { case down, up, right, left }
    /// On-screen size of every character figure (player + opponent). The art sits
    /// inside a padded 64×64 cell, so this is larger than the visible character.
    private let characterRenderSize = CGSize(width: 120, height: 120)
    private var aiWalkFrames: [FieldFacing: [SKTexture]] = [:]
    private var aiIdleTexture: SKTexture?
    private var aiFielderFacing: FieldFacing?
    private var userWalkFrames: [FieldFacing: [SKTexture]] = [:]
    private var userIdleTexture: SKTexture?
    private var userFielderFacing: FieldFacing?
    private var aiPitcherFigure:    SKSpriteNode!   // mound figure while AI pitches
    private var playerPitcherFigure: SKSpriteNode!  // mound figure while user pitches
    private var playerBatterFigure: SKSpriteNode!   // plate figure while user bats
    private var aiBatterFigure:     SKSpriteNode!    // plate figure while AI bats

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
        preloadAssets()
        computeLayout()
        setupCameraRig()
        setupGameWorld()
        setupBatter()      // top
        setupPitcher()     // bottom
        setupChargeBar()
        setupFlashLabel()
        setupFielders()
        injectHUD(into: view)
        addCrtOverlay()
        addHelpButton()

        if showOpponentPicker {
            presentOpponentPicker()
        } else {
            opponentDisplayName = defaultOpponentName(for: aiDifficulty)
            proceedToPlay()
        }
    }

    /// HUD name for an opponent when no explicit pick was made (story / free play).
    /// `.powerHitter` is story Jen here — the free-play Tommy path sets the name
    /// explicitly in `selectOpponent`, so it never reaches this fallback.
    private func defaultOpponentName(for d: BaseballAIDifficulty) -> String {
        switch d {
        case .powerHitter:  return "JEN"   // story Jen
        case .greatFielder: return "TOM"   // story Tom
        case .fastPitcher:  return "JEN"
        case .standard:     return "BOT"
        }
    }

    /// Run the tutorial (first play) or jump straight into the game.
    private func proceedToPlay() {
        applyOpponentAppearance()
        if TutorialManager.shared.hasSeen(TutorialManager.baseball) {
            startUserBatting(showModal: true)
        } else {
            presentTutorial(autoTriggered: true)
        }
    }

    // MARK: - Opponent Picker (free-play)

    private func presentOpponentPicker() {
        let W = size.width, H = size.height

        let container = SKNode()
        container.zPosition = 200

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.72),
                               size: CGSize(width: W, height: H))
        dim.name = "oppPickerDim"
        container.addChild(dim)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "CHOOSE OPPONENT"
        title.fontSize = min(16, W / 18)
        title.fontColor = Parchment.deep
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: H * 0.22)
        container.addChild(title)

        let cardW = min(W * 0.38, 150)
        let cardH = min(H * 0.34, 220)
        let gap = min(W * 0.06, 28)

        let jen = makeOpponentCard(title: "JEN", subtitle: "FAST PITCHER",
                                   desc: "THROWS HEAT", name: "baseballOpp_jen",
                                   accent: SKColor(red: 0.85, green: 0.35, blue: 0.55, alpha: 1),
                                   size: CGSize(width: cardW, height: cardH))
        jen.position = CGPoint(x: -(cardW / 2 + gap / 2), y: -H * 0.02)
        container.addChild(jen)

        let tommy = makeOpponentCard(title: "TOMMY", subtitle: "POWER HITTER",
                                     desc: "SWINGS BIG", name: "baseballOpp_tommy",
                                     accent: SKColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1),
                                     size: CGSize(width: cardW, height: cardH))
        tommy.position = CGPoint(x: (cardW / 2 + gap / 2), y: -H * 0.02)
        container.addChild(tommy)

        addChild(container)
        opponentPickerNode = container
    }

    private func makeOpponentCard(title: String, subtitle: String, desc: String,
                                  name: String, accent: SKColor, size cardSize: CGSize) -> SKNode {
        let card = SKSpriteNode(color: Parchment.surface, size: cardSize)
        card.name = name

        let border = SKShapeNode(rectOf: cardSize)
        border.strokeColor = Parchment.edge
        border.lineWidth = 2
        border.fillColor = .clear
        border.name = name
        card.addChild(border)

        let titleLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        titleLabel.text = title
        titleLabel.fontSize = min(16, cardSize.width / 6)
        titleLabel.fontColor = accent
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: cardSize.height * 0.28)
        titleLabel.name = name
        card.addChild(titleLabel)

        let subLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        subLabel.text = subtitle
        subLabel.fontSize = min(8, cardSize.width / 13)
        subLabel.fontColor = Parchment.deep
        subLabel.verticalAlignmentMode = .center
        subLabel.position = .zero
        subLabel.name = name
        card.addChild(subLabel)

        let descLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        descLabel.text = desc
        descLabel.fontSize = min(7, cardSize.width / 15)
        descLabel.fontColor = Parchment.muted
        descLabel.verticalAlignmentMode = .center
        descLabel.position = CGPoint(x: 0, y: -cardSize.height * 0.22)
        descLabel.name = name
        card.addChild(descLabel)

        return card
    }

    private func selectOpponent(_ difficulty: BaseballAIDifficulty) {
        guard opponentPickerNode != nil else { return }
        aiDifficulty = difficulty
        opponentDisplayName = (difficulty == .fastPitcher) ? "JEN" : "TOMMY"
        opponentPickerNode?.removeFromParent()
        opponentPickerNode = nil
        proceedToPlay()
    }

    private func addHelpButton() {
        // Pause and close icons are UIKit buttons added in injectHUD() so they sit above
        // the SwiftUI UIHostingController layer and are actually visible.
        // Only the SK tutorial help button lives here; it renders in the SK layer below
        // the SwiftUI view but the HUD background is transparent over the center area.
        let topInset: CGFloat = view?.safeAreaInsets.top ?? 0
        let hudY = size.height / 2 - topInset - 24

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: -size.width / 2 + 52, y: hudY)
        addChild(help)
    }

    override func willMove(from view: SKView) {
        hudHostingController?.view.removeFromSuperview()
        hudHostingController = nil
        pauseUIButton?.removeFromSuperview()
        pauseUIButton = nil
        closeUIButton?.removeFromSuperview()
        closeUIButton = nil
        crtUIOverlay?.removeFromSuperview()
        crtUIOverlay = nil
    }

    private func preloadAssets() {
        let textures = ["bag_16bit", "jeff_sprite", "jen_sprite", "tom_sprite"].map { name -> SKTexture in
            let t = SKTexture(imageNamed: name)
            t.filteringMode = .nearest
            return t
        }
        SKTexture.preload(textures) { }

        let sounds = ["bag_land.wav",    "phase_change.wav", "strike_call.wav",
                      "bat_whiff.wav",   "bat_crack.wav",    "out_caught.wav",
                      "game_win.wav",    "game_lose.wav",    "crowd_cheer.wav"]
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

        // UIKit pause + close buttons — must sit above the SwiftUI UIHostingController layer,
        // so SK sprites can't be used here (they render below all UIKit subviews).
        let topInset = view.safeAreaInsets.top
        let iconPts: CGFloat = 22   // matches the 22×22 size used by SK sprites in other mini-games
        let btnSize: CGFloat = 44   // generous tap target

        let pause = UIButton(type: .custom)
        pause.setImage(Self.resizedIcon(named: "pauseIcon", to: iconPts), for: .normal)
        pause.frame = CGRect(x: 0, y: topInset, width: btnSize, height: 48)
        pause.addTarget(self, action: #selector(pauseButtonTapped), for: .touchUpInside)
        view.addSubview(pause)
        pauseUIButton = pause

        let close = UIButton(type: .custom)
        close.setImage(Self.resizedIcon(named: "closeIcon", to: iconPts), for: .normal)
        close.frame = CGRect(x: view.bounds.width - btnSize, y: topInset, width: btnSize, height: 48)
        close.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(close)
        closeUIButton = close

        // CRT scanline overlay — must be the topmost UIKit view so scanlines appear over
        // the SwiftUI HUD and the pause/close buttons, matching every other scene.
        let crt = Self.makeCRTView(frame: view.bounds)
        view.addSubview(crt)
        view.bringSubviewToFront(crt)
        crtUIOverlay = crt

        pushHUD()
    }

    @objc private func pauseButtonTapped() { pauseGame() }
    @objc private func closeButtonTapped() { showConfirmQuit() }

    private static func resizedIcon(named: String, to pts: CGFloat) -> UIImage? {
        guard let src = UIImage(named: named) else { return nil }
        let sz = CGSize(width: pts, height: pts)
        return UIGraphicsImageRenderer(size: sz).image { _ in
            src.draw(in: CGRect(origin: .zero, size: sz))
        }
    }

    private static func makeCRTView(frame: CGRect) -> UIView {
        // Matches the SK CRT overlay: 4pt scanlines (2pt clear / 2pt dark) at reduced parchment opacity.
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 4), format: fmt).image { ctx in
            UIColor(white: 0, alpha: 0.25).setFill()
            ctx.fill(CGRect(x: 0, y: 2, width: 2, height: 2))
            // top 2pt remains transparent (renderer fills with clear by default)
        }
        let v = UIView(frame: frame)
        v.autoresizingMask    = [.flexibleWidth, .flexibleHeight]
        v.isUserInteractionEnabled = false
        v.backgroundColor     = UIColor(patternImage: tile)
        v.alpha               = 0.10
        return v
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

        buildHomeRunWall()
    }

    /// Builds the outfield home-run wall and the crowd stands behind it at the
    /// `homeRunFt` distance. These sit far down the field, so the camera only
    /// reveals them on a big hit that clears the wall.
    private func buildHomeRunWall() {
        let wallW = size.width * 2.6
        let wallH = size.height * 0.06
        let wallY = homeRunWallY

        // Crowd stands behind (beyond) the wall — further from the batter (more negative Y).
        let standsH = size.height * 0.55
        let stands = SKSpriteNode(texture: makeCrowdTexture(
            size: CGSize(width: wallW, height: standsH)))
        stands.position  = CGPoint(x: 0, y: wallY - wallH * 0.5 - standsH * 0.5)
        stands.zPosition = -190
        stands.name      = "hrCrowd"
        gameWorldNode.addChild(stands)

        // Warning-track dirt strip in front of the wall (toward the batter).
        let track = SKSpriteNode(
            color: SKColor(red: 0.55, green: 0.36, blue: 0.18, alpha: 1),
            size: CGSize(width: wallW, height: wallH * 0.7))
        track.position  = CGPoint(x: 0, y: wallY + wallH * 0.5 + wallH * 0.35)
        track.zPosition = -185
        gameWorldNode.addChild(track)

        // The wall itself (padded outfield fence + yellow home-run rail on top).
        let wall = SKSpriteNode(texture: makeWallTexture(
            size: CGSize(width: wallW, height: wallH)))
        wall.position  = CGPoint(x: 0, y: wallY)
        wall.zPosition = -180
        gameWorldNode.addChild(wall)

        // Distance call-out on the wall.
        let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        lbl.text      = "\(Int(homeRunFt))ft"
        lbl.fontSize  = max(7, size.width * 0.040)
        lbl.fontColor = SKColor(white: 0.95, alpha: 0.92)
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode   = .center
        lbl.position  = CGPoint(x: 0, y: wallY)
        lbl.zPosition = -179
        gameWorldNode.addChild(lbl)
    }

    /// Procedural crowd texture — dark stands speckled with randomly-colored spectators.
    private func makeCrowdTexture(size: CGSize) -> SKTexture {
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }
        // Dark stadium backing
        ctx.setFillColor(UIColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // Speckled spectators
        let palette: [UIColor] = [
            UIColor(red: 0.85, green: 0.30, blue: 0.30, alpha: 1),
            UIColor(red: 0.30, green: 0.55, blue: 0.90, alpha: 1),
            UIColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1),
            UIColor(red: 0.40, green: 0.80, blue: 0.45, alpha: 1),
            UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1),
            UIColor(red: 0.75, green: 0.45, blue: 0.85, alpha: 1),
        ]
        let dot: CGFloat = 4
        var y: CGFloat = 2
        while y < size.height - dot {
            var x: CGFloat = CGFloat.random(in: 0...dot)
            while x < size.width - dot {
                let c = palette[Int.random(in: 0..<palette.count)]
                ctx.setFillColor(c.cgColor)
                ctx.fill(CGRect(x: x, y: y, width: dot - 1, height: dot - 1))
                x += dot + CGFloat.random(in: 0...3)
            }
            y += dot + 1
        }
        let tex = SKTexture(image: UIGraphicsGetImageFromCurrentImageContext() ?? UIImage())
        tex.filteringMode = .nearest
        return tex
    }

    /// Procedural outfield-wall texture — green padding, vertical seams, yellow top rail.
    private func makeWallTexture(size: CGSize) -> SKTexture {
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return SKTexture() }
        // Padded wall body
        ctx.setFillColor(UIColor(red: 0.06, green: 0.22, blue: 0.10, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        // Vertical pad seams
        ctx.setFillColor(UIColor(red: 0.04, green: 0.14, blue: 0.07, alpha: 1).cgColor)
        var x: CGFloat = 0
        while x < size.width {
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: size.height))
            x += 18
        }
        // Yellow home-run rail along the top
        ctx.setFillColor(UIColor(red: 0.95, green: 0.82, blue: 0.18, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3))
        let tex = SKTexture(image: UIGraphicsGetImageFromCurrentImageContext() ?? UIImage())
        tex.filteringMode = .nearest
        return tex
    }

    private func setupBatter() {
        // Home plate (top of field)
        let plate = SKSpriteNode(
            color: SKColor(white: 0.88, alpha: 0.85),
            size: CGSize(width: 22, height: 14))
        plate.position  = CGPoint(x: 0, y: batY - 14)
        plate.zPosition = 3
        gameWorldNode.addChild(plate)

        // Batter figure (red = player) — shown while the user bats (left side).
        // Anchored near the feet (y=0.18) so larger sprite art grows upward and
        // stays grounded beside the plate.
        playerBatterFigure = SKSpriteNode(
            color: SKColor(red: 0.85, green: 0.22, blue: 0.22, alpha: 1),
            size: CGSize(width: 14, height: 22))
        playerBatterFigure.anchorPoint = CGPoint(x: 0.5, y: 0.18)
        playerBatterFigure.position    = CGPoint(x: -20, y: batY - 9)
        playerBatterFigure.zPosition   = 10
        gameWorldNode.addChild(playerBatterFigure)

        // AI batter figure — shown while the AI bats (right side, mirrored to face
        // the plate). Swapped to the opponent sprite in applyOpponentAppearance().
        aiBatterFigure = SKSpriteNode(
            color: SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1),
            size: CGSize(width: 14, height: 22))
        aiBatterFigure.anchorPoint = CGPoint(x: 0.5, y: 0.18)
        aiBatterFigure.position    = CGPoint(x: 20, y: batY - 9)
        aiBatterFigure.zPosition   = 10
        aiBatterFigure.isHidden    = true
        gameWorldNode.addChild(aiBatterFigure)

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

        // Pitcher figure (blue = AI). Swapped for the opponent sprite once known.
        // Shown while the AI pitches (user batting).
        aiPitcherFigure = SKSpriteNode(
            color: SKColor(red: 0.25, green: 0.48, blue: 0.90, alpha: 1),
            size: CGSize(width: 14, height: 22))
        aiPitcherFigure.anchorPoint = CGPoint(x: 0.5, y: 0.18)
        aiPitcherFigure.position    = CGPoint(x: 0, y: pitcherY - 3)
        aiPitcherFigure.zPosition   = 10
        gameWorldNode.addChild(aiPitcherFigure)

        // Player figure on the mound — shown while the user pitches (AI batting).
        playerPitcherFigure = SKSpriteNode(
            color: SKColor(red: 0.85, green: 0.22, blue: 0.22, alpha: 1),
            size: CGSize(width: 14, height: 22))
        playerPitcherFigure.anchorPoint = CGPoint(x: 0.5, y: 0.18)
        playerPitcherFigure.position    = CGPoint(x: 0, y: pitcherY - 3)
        playerPitcherFigure.zPosition   = 10
        playerPitcherFigure.isHidden    = true
        gameWorldNode.addChild(playerPitcherFigure)
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

    // MARK: - Character art (jeff_sprite / jen_sprite / tom_sprite)

    /// Sheet asset name for the current opponent, or nil for the generic BOT.
    private func opponentSheetName() -> String? {
        switch opponentDisplayName {
        case "JEN":           return "jen_sprite"
        case "TOM", "TOMMY":  return "tom_sprite"
        default:              return nil
        }
    }

    /// Slices a character sheet (64×64 frames, 8-col layout shared with `jeff_sprite`)
    /// into walk-cycle frames per facing plus an idle frame.
    /// Rows (top-down): idle 0/1/2, walk 3/4/5 for down/right/up.
    private func buildSheetFrames(_ sheetName: String) -> (idle: SKTexture?, walk: [FieldFacing: [SKTexture]]) {
        let sheet = SKTexture(imageNamed: sheetName)
        sheet.filteringMode = .nearest
        let texW = sheet.size().width, texH = sheet.size().height
        guard texW > 0, texH > 0 else { return (nil, [:]) }

        let frameW: CGFloat = 64, frameH: CGFloat = 64
        let cols = 6
        let nW = frameW / texW, nH = frameH / texH
        func framesForRow(_ row: Int) -> [SKTexture] {
            // SKTexture rect uses bottom-left origin; sheet rows are top-down.
            let nY = 1.0 - CGFloat(row + 1) * nH
            return (0..<cols).map { col in
                let t = SKTexture(rect: CGRect(x: CGFloat(col) * nW, y: nY, width: nW, height: nH),
                                  in: sheet)
                t.filteringMode = .nearest
                return t
            }
        }
        let walk: [FieldFacing: [SKTexture]] = [
            .down:  framesForRow(3),
            .right: framesForRow(4),
            .up:    framesForRow(5),
            .left:  framesForRow(4),   // rendered mirrored via xScale
        ]
        return (framesForRow(0).first, walk)
    }

    /// Applies character sprites to the player figures (jeff_sprite) and, when the
    /// opponent is Jen/Tom, to the AI pitcher/batter/fielder. BOT keeps plain squares.
    private func applyOpponentAppearance() {
        // Player always uses jeff_sprite at the shared character size — batting,
        // pitching, and running the outfield to catch the AI's hits.
        let jeff = buildSheetFrames("jeff_sprite")
        userWalkFrames  = jeff.walk
        userIdleTexture = jeff.idle
        if let idle = jeff.idle {
            for node in [playerBatterFigure, playerPitcherFigure, userFielderNode] {
                node?.texture          = idle
                node?.colorBlendFactor = 0
                node?.size             = characterRenderSize
            }
        }

        guard let sheetName = opponentSheetName() else { return }   // BOT keeps the square
        let opp = buildSheetFrames(sheetName)
        aiWalkFrames  = opp.walk
        aiIdleTexture = opp.idle
        if let idle = opp.idle {
            for node in [aiFielderNode, aiPitcherFigure, aiBatterFigure] {
                node?.texture          = idle
                node?.colorBlendFactor = 0
                node?.size             = characterRenderSize
            }
            // Batter stands on the right and faces the plate (left).
            aiBatterFigure.xScale = -1
        }
    }

    /// Runs a fielder's walk cycle, choosing the row from the movement direction and
    /// mirroring for left. No-op for a plain-square fielder (no walk frames).
    private func animateFielderRun(node: SKSpriteNode,
                                   walk: [FieldFacing: [SKTexture]],
                                   facing currentFacing: inout FieldFacing?,
                                   dx: CGFloat, dy: CGFloat) {
        guard !walk.isEmpty else { return }
        let dir: FieldFacing
        if abs(dx) > abs(dy) { dir = dx < 0 ? .left : .right }
        else                 { dir = dy > 0 ? .up   : .down }
        node.xScale = (dir == .left) ? -1 : 1
        guard dir != currentFacing else { return }   // already running this way
        currentFacing = dir
        if let frames = walk[dir], !frames.isEmpty {
            node.run(.repeatForever(.animate(with: frames, timePerFrame: 0.10)), withKey: "run")
        }
    }

    /// Stops a fielder's walk cycle and shows its idle frame.
    private func stopFielderRun(node: SKSpriteNode,
                                idle: SKTexture?,
                                facing currentFacing: inout FieldFacing?) {
        node.removeAction(forKey: "run")
        if let idle = idle { node.texture = idle }
        currentFacing = nil
    }

    private func resetFielders() {
        let startY = pitcherY - 80

        userFielderPos    = CGPoint(x: 26, y: startY)
        userFielderTarget = userFielderPos
        userFielderNode.position = userFielderPos
        userFielderNode.isHidden = true
        userFielderNode.removeAction(forKey: "run")
        userFielderNode.removeAction(forKey: "wallCrash")
        userFielderNode.xScale    = 1
        userFielderNode.zRotation = 0
        userFielderFacing      = nil
        if let idle = userIdleTexture { userFielderNode.texture = idle }

        aiFielderPos    = CGPoint(x: -26, y: startY)
        aiFielderTarget = aiFielderPos
        aiFielderNode.position = aiFielderPos
        aiFielderNode.isHidden = true
        aiFielderNode.removeAction(forKey: "run")
        aiFielderNode.removeAction(forKey: "wallCrash")
        aiFielderNode.xScale    = 1
        aiFielderNode.zRotation = 0
        aiFielderFacing      = nil
        if let idle = aiIdleTexture { aiFielderNode.texture = idle }
        aiFielderMoveDelay    = 0
        userFielderMoveDelay  = 0
        userFielderBoost      = 0
        aiFielderStunFrames   = 0
        userFielderStunFrames = 0

        // The pitcher returns to the mound once the chase is over. The pitcher is the
        // AI while the user bats, and the user while the user pitches.
        aiPitcherFigure.isHidden     = !isUserBattingHalf
        playerPitcherFigure.isHidden = isUserBattingHalf
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

    private func startUserBatting(showModal: Bool = true) {
        isUserBattingHalf = true
        phase         = .userBatting
        userOuts      = 0
        userStrikes   = 0
        userHasSwung  = false
        pitchInFlight = false
        isBatCharging = false
        currentChargeLevel = 0
        chargeBarBg.isHidden = true
        batNode.isHidden   = false
        aiBatNode.isHidden = true
        // User bats (left plate); AI pitches (mound).
        playerBatterFigure.isHidden  = false
        aiBatterFigure.isHidden      = true
        aiPitcherFigure.isHidden     = false
        playerPitcherFigure.isHidden = true
        resetBatVisual()
        strikeZone.isHidden = true
        resetFielders()
        animateCamera(to: .zero, duration: 0.30)
        pushHUD()

        if showModal {
            showReadyToBatModal()
            run(.wait(forDuration: 2.6)) { [weak self] in self?.throwAIPitch() }
        } else {
            run(.wait(forDuration: 1.0)) { [weak self] in self?.throwAIPitch() }
        }
    }

    private func startUserPitching() {
        isUserBattingHalf = false
        phase          = .userPitching
        aiOuts         = 0
        aiStrikes      = 0
        pitchInFlight  = false
        isBatCharging  = false
        aiWillPowerSwing = false
        currentChargeLevel = 0
        chargeBarBg.isHidden = true
        batNode.isHidden   = true
        aiBatNode.isHidden = false
        // AI bats (right plate); user pitches (mound).
        playerBatterFigure.isHidden  = true
        aiBatterFigure.isHidden      = false
        aiPitcherFigure.isHidden     = true
        playerPitcherFigure.isHidden = false
        resetBatVisual()
        strikeZone.isHidden = false   // always visible so player can see where to aim
        resetFielders()
        animateCamera(to: .zero, duration: 0.40)
        pushHUD()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        // PLACEHOLDER: add phase_change.wav to Copy Bundle Resources
        run(SKAction.playSoundFileNamed("phase_change.wav", waitForCompletion: false))
        showReadyToPitchModal()
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
        guard phase == .userBatting, userOuts < outsPerHalf, pitchBag == nil else { return }

        pitchInFlight  = false
        swingWindowOpen = false
        userHasSwung    = false
        isBatCharging   = false
        currentChargeLevel = 0
        chargeBarBg.isHidden = true
        resetBatVisual()
        pushHUD()

        let pitch = PitchBag()
        // Restrict to bat barrel x range (-12…24) so every pitch is hittable
        pitch.bx = CGFloat.random(in: -10 ... 18)
        pitch.by = pitcherY                               // start at BOTTOM
        // Jen (fastPitcher) throws heat — faster pitch, harder to time.
        pitch.vy = +CGFloat.random(in: 5.0 ... 8.5) * (aiDifficulty == .fastPitcher ? 1.5 : 1.0) * aiMult(.pitch)   // travel UPWARD
        pitch.vx = CGFloat.random(in: -0.10 ... 0.10)  // nearly straight

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
        guard phase == .userPitching, aiOuts < outsPerHalf, pitchBag == nil else { return }

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

        // 50% chance AI tries a power swing
        aiWillPowerSwing = CGFloat.random(in: 0...1) < 0.50
        if aiWillPowerSwing { aiPowerChargeStartTime = CACurrentMediaTime() }

        // AI hit probability: base 95 %, drops slightly if power-swinging
        let preMissProb: Double = aiWillPowerSwing ? 0.15 : 0.05
        // Tunable contact likelihood (Tom/Jen): scale the base hit chance.
        let preHitProb = min(1.0, max(0.0, (1.0 - preMissProb) * Double(aiMult(.hit))))
        aiWillHit    = Double.random(in: 0...1) < preHitProb
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

        // Bat barrel bounds in world space (based on batNode geometry from setupBatter)
        let barrelMinX = batBarrelMinX          // ≈ -12
        let barrelMaxX = batBarrelMaxX          // ≈  24
        let barrelCenterX = (barrelMinX + barrelMaxX) * 0.5
        let barrelHalfW   = (barrelMaxX - barrelMinX) * 0.5
        let barrelY       = batBarrelCenterY    // batY + 4
        let barrelHalfH: CGFloat = 9

        // Project pitch over the next 14 frames to find the contact frame closest to the barrel Y.
        // A hit only registers when the bag physically passes through the bat barrel.
        var pitchPassesBarrel = false
        var quality: CGFloat = 0.0
        for frame in 0...14 {
            let projX = pitch.bx + pitch.vx * CGFloat(frame)
            let projY = pitch.by + pitch.vy * CGFloat(frame)
            let dy = abs(projY - barrelY)
            if dy < barrelHalfH {
                if projX >= barrelMinX && projX <= barrelMaxX {
                    pitchPassesBarrel = true
                    let xQ = max(0, 1.0 - abs(projX - barrelCenterX) / barrelHalfW)
                    let yQ = max(0, 1.0 - dy / barrelHalfH)
                    quality = max(quality, xQ * 0.7 + yQ * 0.3)
                } else if abs(projX - barrelCenterX) < barrelHalfW + 12 {
                    // Just outside barrel edge — triggers swing window but won't produce quality
                    pitchPassesBarrel = true
                }
            }
        }

        if !pitchPassesBarrel {
            removePitchBag()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            // PLACEHOLDER: add strike_call.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("strike_call.wav", waitForCompletion: false))
            strikeZone.strokeColor = SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8)
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.strikeZone.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.7)
            }
            spawnFloatingText("SWINGING STRIKE!", at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(red: 1, green: 0.18, blue: 0.18, alpha: 1))
            registerUserStrike()
            run(.wait(forDuration: 0.85)) { [weak self] in
                self?.checkBattingHalfDone()
            }
            return
        }

        // Risk/reward: higher charge → up to 60 % whiff chance, but 80 % power bonus on contact
        let whiffProb = chargeLevel * 0.6
        if CGFloat.random(in: 0...1) < whiffProb {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            // PLACEHOLDER: add bat_whiff.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("bat_whiff.wav", waitForCompletion: false))
            strikeZone.strokeColor = SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8)
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.strikeZone.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.7)
            }
            spawnFloatingText("WHIFF!", at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(white: 0.65, alpha: 1))
            registerUserStrike()
            run(.wait(forDuration: 0.85)) { [weak self] in
                self?.checkBattingHalfDone()
            }
            return
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
            // PLACEHOLDER: add bat_crack.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("bat_crack.wav", waitForCompletion: false))
            spawnFloatingText(label, at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(red: 1, green: 0.88, blue: 0.2, alpha: 1))
            launchHitBag(from: CGPoint(x: pitch.bx, y: batY + 4),
                         quality: quality, chargeLevel: chargeLevel, isUser: true)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            // PLACEHOLDER: add bat_whiff.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("bat_whiff.wav", waitForCompletion: false))
            strikeZone.strokeColor = SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8)
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.strikeZone.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.7)
            }
            spawnFloatingText("MISS!", at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(red: 1, green: 0.28, blue: 0.28, alpha: 1))
            registerUserStrike()
            run(.wait(forDuration: 0.85)) { [weak self] in
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

        // Recalculate hit chance — AI is a strong hitter, power swing adds minor risk
        let missProb = 0.05 + Double(aiCharge) * 0.10
        // Tunable contact likelihood (Tom/Jen): scale the base hit chance.
        let hitProb  = min(1.0, max(0.0, (1.0 - missProb) * Double(aiMult(.hit))))
        aiWillHit    = Double.random(in: 0...1) < hitProb

        removePitchBag()

        if aiWillHit {
            aiBatNode.removeAllActions()
            aiBatNode.zRotation = .pi * 0.35
            triggerHitStop()
            run(.wait(forDuration: 0.25)) { [weak self] in
                self?.aiBatNode.run(.rotate(toAngle: 0, duration: 0.18))
            }
            let quality = CGFloat.random(in: 0.82 ... 1.0)
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
            let label = aiCharge > 0.4 ? "\(opponentDisplayName) WHIFF!" : "\(opponentDisplayName) WHIFFS!"
            spawnFloatingText(label, at: CGPoint(x: pitch.bx, y: batY + 22),
                              color: SKColor(white: 0.58, alpha: 1))
            registerAIStrike()
            run(.wait(forDuration: 0.90)) { [weak self] in
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
        // Jen (powerHitter) hits 35% harder and spreads wider when it's her turn to bat.
        let aiPowerBoost: CGFloat = (!isUser && aiDifficulty == .powerHitter) ? 1.35 : 1.0
        // Tunable power dial (Tom/Jen) scales how hard the AI hits (player hits unaffected).
        let baseVY = size.height * 0.009 * power * aiPowerBoost * (isUser ? 1.0 : aiMult(.power))
        let vxSpread = (!isUser && aiDifficulty == .powerHitter) ? baseVY * 0.45 : baseVY * 0.28

        let hit = HitBag()
        hit.bx          = origin.x
        hit.by          = origin.y
        hit.bz          = 4.0
        hit.vy          = -baseVY                          // DOWNWARD into outfield
        hit.vx          = CGFloat.random(in: -vxSpread ... vxSpread)
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
            // AI fielder auto-moves to predicted landing, with a reaction delay and aim error.
            // Tom (greatFielder) covers much more of the field with tighter positioning.
            // The pitcher and fielder are the same person, so the pitcher leaves the mound.
            aiPitcherFigure.isHidden = true
            aiFielderNode.isHidden = false
            let landing = predictLandingPoint(vx: hit.vx, vy: hit.vy, vz: hit.vz,
                                              bx: hit.bx, by: hit.by, bz: hit.bz)
            let errRange: CGFloat = aiDifficulty == .greatFielder ? 14.0 : 38.0
            let err = CGFloat.random(in: -errRange...errRange)
            aiFielderTarget    = CGPoint(x: landing.x + err, y: landing.y + err * 0.4)
            aiFielderMoveDelay = aiDifficulty == .greatFielder ? 10 : 20
        } else {
            // User fielder auto-runs to predicted landing; tapping sprints.
            // The pitcher and fielder are the same person, so the pitcher leaves the mound.
            playerPitcherFigure.isHidden = true
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
        if isPausedGame || confirmingQuit { return }
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
            if aiFielderStunFrames > 0 {
                // Knocked out cold against the home-run wall — lie there, can't move.
                aiFielderStunFrames -= 1
                if aiFielderStunFrames == 0 { standFielderUp(aiFielderNode) }
            } else if aiFielderMoveDelay > 0 {
                aiFielderMoveDelay -= 1
                stopFielderRun(node: aiFielderNode, idle: aiIdleTexture, facing: &aiFielderFacing)
            } else {
                let dx = aiFielderTarget.x - aiFielderPos.x
                let dy = aiFielderTarget.y - aiFielderPos.y
                let d  = hypot(dx, dy)
                if d > 1 {
                    // Tunable run-speed dial (Tom/Jen) scales the AI fielder's chase speed.
                    let step = min(fielderSpeed * aiMult(.run), d)
                    let nx = aiFielderPos.x + dx / d * step
                    let ny = aiFielderPos.y + dy / d * step
                    if ny < fielderWallStopY {
                        // Slammed into the home-run wall — stop dead and get knocked out.
                        aiFielderPos = CGPoint(x: nx, y: fielderWallStopY)
                        aiFielderNode.position = aiFielderPos
                        aiFielderStunFrames = 60
                        knockFielderIntoWall(aiFielderNode, idle: aiIdleTexture, facing: &aiFielderFacing)
                    } else {
                        aiFielderPos = CGPoint(x: nx, y: ny)
                        aiFielderNode.position = aiFielderPos
                        animateFielderRun(node: aiFielderNode, walk: aiWalkFrames,
                                          facing: &aiFielderFacing, dx: dx, dy: dy)
                    }
                } else {
                    stopFielderRun(node: aiFielderNode, idle: aiIdleTexture, facing: &aiFielderFacing)
                }
            }
        }

        // User fielder: auto-runs to predicted landing; tapping adds a speed burst
        if !userFielderNode.isHidden {
            if userFielderStunFrames > 0 {
                userFielderStunFrames -= 1
                if userFielderStunFrames == 0 { standFielderUp(userFielderNode) }
            } else if userFielderMoveDelay > 0 {
                userFielderMoveDelay -= 1
                stopFielderRun(node: userFielderNode, idle: userIdleTexture, facing: &userFielderFacing)
            } else {
                let dx = userFielderTarget.x - userFielderPos.x
                let dy = userFielderTarget.y - userFielderPos.y
                let d  = hypot(dx, dy)
                if d > 1 {
                    let speed = fielderSpeed + userFielderBoost
                    let step  = min(speed, d)
                    let nx = userFielderPos.x + dx / d * step
                    let ny = userFielderPos.y + dy / d * step
                    if ny < fielderWallStopY {
                        // Slammed into the home-run wall — stop dead and get knocked out.
                        userFielderPos = CGPoint(x: nx, y: fielderWallStopY)
                        userFielderNode.position = userFielderPos
                        userFielderBoost = 0
                        userFielderStunFrames = 60
                        knockFielderIntoWall(userFielderNode, idle: userIdleTexture, facing: &userFielderFacing)
                    } else {
                        userFielderPos = CGPoint(x: nx, y: ny)
                        userFielderNode.position = userFielderPos
                        animateFielderRun(node: userFielderNode, walk: userWalkFrames,
                                          facing: &userFielderFacing, dx: dx, dy: dy)
                    }
                } else {
                    stopFielderRun(node: userFielderNode, idle: userIdleTexture, facing: &userFielderFacing)
                }
            }
            userFielderBoost = max(0, userFielderBoost - 0.18)
        }
    }

    /// Topple a fielder flat against the home-run wall with a dizzy-stars puff.
    private func knockFielderIntoWall(_ node: SKSpriteNode, idle: SKTexture?,
                                      facing: inout FieldFacing?) {
        node.removeAction(forKey: "run")
        if let idle = idle { node.texture = idle }
        facing = nil

        // Topple over in whichever way the fielder was facing.
        node.removeAction(forKey: "wallCrash")
        let dir: CGFloat = node.xScale < 0 ? 1 : -1
        let topple = SKAction.rotate(toAngle: dir * .pi / 2, duration: 0.18)
        topple.timingMode = .easeOut
        node.run(topple, withKey: "wallCrash")

        // Dizzy stars rise from the point of impact.
        let stars = SKLabelNode(fontNamed: "PressStart2P-Regular")
        stars.text      = "✦ ✦ ✦"
        stars.fontSize  = 8
        stars.fontColor = Parchment.amber
        stars.verticalAlignmentMode = .center
        stars.position  = CGPoint(x: node.position.x, y: node.position.y + 18)
        stars.zPosition = node.zPosition + 1
        gameWorldNode.addChild(stars)
        stars.run(.sequence([
            .group([.fadeOut(withDuration: 0.9), .moveBy(x: 0, y: 12, duration: 0.9)]),
            .removeFromParent(),
        ]))

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Pick the fielder back up once the knockout wears off.
    private func standFielderUp(_ node: SKSpriteNode) {
        node.removeAction(forKey: "wallCrash")
        node.run(.rotate(toAngle: 0, duration: 0.15))
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
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    // PLACEHOLDER: add strike_call.wav to Copy Bundle Resources
                    run(SKAction.playSoundFileNamed("strike_call.wav", waitForCompletion: false))
                    spawnFloatingText("STRIKE!", at: CGPoint(x: 0, y: batY + 22),
                                      color: SKColor(red: 1, green: 0.18, blue: 0.18, alpha: 1))
                    registerUserStrike()
                    run(.wait(forDuration: 0.85)) { [weak self] in
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
                    aiSwings(pitch: pitch)
                } else {
                    // 25% chance AI chases a ball outside the zone — always misses (a strike)
                    if CGFloat.random(in: 0...1) < 0.25 {
                        removePitchBag()
                        spawnFloatingText("\(opponentDisplayName) SWINGS WILD!", at: CGPoint(x: pitch.bx, y: batY + 22),
                                          color: SKColor(white: 0.58, alpha: 1))
                        registerAIStrike()
                        run(.wait(forDuration: 0.90)) { [weak self] in
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
                    // Called strike — AI took a pitch in the zone
                    spawnFloatingText("CALLED STRIKE!", at: CGPoint(x: 0, y: batY + 22),
                                      color: SKColor(red: 1, green: 0.85, blue: 0.22, alpha: 1))
                    registerAIStrike()
                    run(.wait(forDuration: 0.85)) { [weak self] in
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

        // Camera pans DOWN to follow bag into outfield.
        let targetX = -hit.bx * 0.65
        let targetY = -visualY + size.height * 0.08   // push world up so bag stays on-screen
        cameraOffset.position.x += (targetX - cameraOffset.position.x) * 0.14
        cameraOffset.position.y += (targetY - cameraOffset.position.y) * 0.14

        // Hard guarantee the bag stays on-screen even on a fast/long home-run shot:
        // the bag's on-screen position is cameraOffset.position + bag.position, so
        // clamp the offset to keep it inside a safe margin of the viewport.
        let marginX = size.width  * 0.40
        let marginY = size.height * 0.34
        cameraOffset.position.x = min(max(cameraOffset.position.x, -marginX - hit.bx), marginX - hit.bx)
        cameraOffset.position.y = min(max(cameraOffset.position.y, -marginY - visualY), marginY - visualY)

        // Landing
        if hit.bz <= 0 && hit.vz <= 0 {
            hit.bz = 0; hit.vx = 0; hit.vy = 0
            isTracking = false

            let dist  = hypot(hit.bx, hit.by - batY)
            let ftVal = Int(dist * distScale)
            // A ball that lands at/beyond the outfield wall clears it — a home run,
            // and can never be caught.
            let isHomeRun = hit.by <= homeRunWallY

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // PLACEHOLDER: add bag_land.wav to Copy Bundle Resources
            run(SKAction.playSoundFileNamed("bag_land.wav", waitForCompletion: false))
            showLandingEffect(at: CGPoint(x: hit.bx, y: hit.by))

            if hit.isUserHit {
                let caught = !isHomeRun && hypot(hit.bx - aiFielderPos.x, hit.by - aiFielderPos.y) < fielderCatchRadius
                if isHomeRun {
                    celebrateHomeRun(isUser: true)
                    userDistances.append(dist)
                    registerUserSafeHit()
                    spawnFloatingText("HOME RUN! \(ftVal)FT", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 1, green: 0.85, blue: 0.28, alpha: 1))
                } else if caught {
                    // PLACEHOLDER: add out_caught.wav to Copy Bundle Resources
                    run(SKAction.playSoundFileNamed("out_caught.wav", waitForCompletion: false))
                    registerUserCaughtOut()
                    spawnFloatingText("CAUGHT! OUT \(userOuts)", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 0.35, green: 1.0, blue: 0.35, alpha: 1))
                } else {
                    userDistances.append(dist)
                    registerUserSafeHit()
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
                let caught = !isHomeRun && hypot(hit.bx - userFielderPos.x, hit.by - userFielderPos.y) < fielderCatchRadius
                if isHomeRun {
                    celebrateHomeRun(isUser: false)
                    aiDistances.append(dist)
                    registerAISafeHit()
                    spawnFloatingText("\(opponentDisplayName) HOME RUN! \(ftVal)FT", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1))
                } else if caught {
                    // PLACEHOLDER: add out_caught.wav to Copy Bundle Resources
                    run(SKAction.playSoundFileNamed("out_caught.wav", waitForCompletion: false))
                    registerAICaughtOut()
                    spawnFloatingText("CAUGHT! OUT \(aiOuts)", at: CGPoint(x: hit.bx, y: hit.by + 22),
                                      color: SKColor(red: 1, green: 0.38, blue: 0.38, alpha: 1))
                } else {
                    aiDistances.append(dist)
                    registerAISafeHit()
                    spawnFloatingText("\(opponentDisplayName) \(ftVal)FT!", at: CGPoint(x: hit.bx, y: hit.by + 22),
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

    // MARK: - Outs & strikes (standard 3-out innings)

    private let outRed = SKColor(red: 1, green: 0.28, blue: 0.28, alpha: 1)

    /// A strike against the user at bat. The 3rd strike becomes an out and resets
    /// the running count. Floats a "STRIKEOUT!" call on the out.
    private func registerUserStrike() {
        userStrikes += 1
        if userStrikes >= strikesPerOut {
            userStrikes = 0
            userOuts += 1
            spawnFloatingText("STRIKEOUT! OUT \(userOuts)", at: CGPoint(x: 0, y: batY + 44),
                              color: outRed)
        }
        pushHUD()
    }

    /// A caught fly ball while the user bats — an immediate out; new batter (strikes reset).
    private func registerUserCaughtOut() {
        userOuts += 1
        userStrikes = 0
        pushHUD()
    }

    /// A safe hit (single/home run) while the user bats — no out; new batter (strikes reset).
    private func registerUserSafeHit() {
        userStrikes = 0
        pushHUD()
    }

    private func registerAIStrike() {
        aiStrikes += 1
        if aiStrikes >= strikesPerOut {
            aiStrikes = 0
            aiOuts += 1
            spawnFloatingText("\(opponentDisplayName) STRIKES OUT! OUT \(aiOuts)",
                              at: CGPoint(x: 0, y: batY + 44), color: outRed)
        }
        pushHUD()
    }

    private func registerAICaughtOut() {
        aiOuts += 1
        aiStrikes = 0
        pushHUD()
    }

    private func registerAISafeHit() {
        aiStrikes = 0
        pushHUD()
    }

    // MARK: - Half-inning advancement

    private func checkBattingHalfDone() {
        if userOuts >= outsPerHalf {
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
        if aiOuts >= outsPerHalf {
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

    // MARK: - CRT Overlay
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
                                 endCenter:   CGPoint(x: w/2, y: h/2), endRadius: max(w, h) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: w, height: h))
        overlay.position  = .zero
        overlay.zPosition = 3000
        overlay.isUserInteractionEnabled = false
        addChild(overlay)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Opponent picker (free-play) swallows everything until a card is chosen.
        if opponentPickerNode != nil {
            for n in nodes(at: loc) {
                if n.name == "baseballOpp_jen" { selectOpponent(.fastPitcher); return }
                if n.name == "baseballOpp_tommy" { selectOpponent(.powerHitter); return }
            }
            return
        }

        // Tutorial overlay — any tap advances it.
        if let overlay = TutorialOverlay.active(in: self) {
            overlay.advance(); return
        }
        // HUD help button re-presents the tutorial.
        for n in nodes(at: loc) where TutorialHelpButton.wasTapped(n) {
            presentTutorial(autoTriggered: false); return
        }

        // Quit-confirm modal consumes all input until resolved.
        if confirmingQuit {
            for n in nodes(at: loc) {
                if QuitConfirmModal.isQuit(n)   { hideConfirmPanel(); dismissScene(playerWon: false); return }
                if QuitConfirmModal.isCancel(n) { hideConfirmPanel(); return }
            }
            return
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
        // Phase-transition modal consumes all input.
        if phaseTransitionActive { handleButtonTap(at: loc); return }

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
                case "closeButton":        showConfirmQuit();                         return true
                case "playAgainBtn":       resetGame();                               return true
                case "exitBtn":            dismissScene(playerWon: userAvg >= aiAvg); return true
                default:                   n = cur.parent
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

    /// Home-run celebration: centred flash, crowd cheer (stands pulse), and a sound.
    private func celebrateHomeRun(isUser: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Requires crowd_cheer.wav in Copy Bundle Resources
        run(SKAction.playSoundFileNamed("crowd_cheer.wav", waitForCompletion: false))
        showCentreFlash(isUser ? "HOME RUN!" : "\(opponentDisplayName) GOES YARD!")
        // Crowd jumps up and cheers
        if let crowd = gameWorldNode.childNode(withName: "hrCrowd") {
            crowd.removeAllActions()
            let baseY = crowd.position.y
            crowd.run(.repeat(.sequence([
                .moveBy(x: 0, y: 4, duration: 0.10),
                .moveBy(x: 0, y: -4, duration: 0.10),
            ]), count: 8))
            crowd.run(.sequence([
                .colorize(with: .white, colorBlendFactor: 0.35, duration: 0.12),
                .wait(forDuration: 1.0),
                .colorize(withColorBlendFactor: 0, duration: 0.3),
                .run { crowd.position.y = baseY },
            ]))
        }
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
        // Outs / strikes belong to whoever is currently batting.
        let outs    = isUserBattingHalf ? userOuts    : aiOuts
        let strikes = isUserBattingHalf ? userStrikes : aiStrikes
        let vm = hudViewModel
        vm.opponentName = opponentDisplayName
        DispatchQueue.main.async {
            vm.cycle          = self.currentCycle
            vm.phaseIsbatting = self.isUserBattingHalf
            vm.outs           = outs
            vm.strikes        = strikes
            vm.playerAvgFt    = Int(self.userAvg * self.distScale)
            vm.aiAvgFt        = Int(self.aiAvg   * self.distScale)
        }
    }

    // MARK: - Game over

    private func showGameOver() {
        phase = .gameOver
        let uAvg = userAvg, aAvg = aiAvg
        // PLACEHOLDER: add game_win.wav / game_lose.wav to Copy Bundle Resources
        let resultSound = uAvg >= aAvg ? "game_win.wav" : "game_lose.wav"
        run(SKAction.playSoundFileNamed(resultSound, waitForCompletion: false))
        let playerWon = uAvg > aAvg
        let tied      = uAvg == aAvg
        let userFt    = Int(uAvg * distScale)
        let aiFt      = Int(aAvg * distScale)

        // Reward: a bat is earned when beating Tom (greatFielder) completes both
        // baseball wins — Jen already beaten. The bat unlocks Suburban Jousters.
        var rewards: [GameResultModal.Reward] = []
        if awardsRewards && playerWon
            && aiDifficulty == .greatFielder
            && CornholeStatsManager.shared.defeatedJenBaseball {
            rewards = [.unlock("EARNED A BAT!"), .unlock("JOUSTERS UNLOCKED")]
        }

        let panel = GameResultModal.make(
            sceneSize: size,
            won: playerWon && !tied,
            title: tied ? "IT'S A TIE!" : (playerWon ? "VICTORY!" : "DEFEAT"),
            subtitle: "YOU \(userFt)ft  -  \(aiFt)ft \(opponentDisplayName)",
            detail: "\(totalCycles) INNINGS · AVG DISTANCE",
            rewards: rewards,
            buttons: [GameResultModal.Button(label: "PLAY AGAIN", name: "playAgainBtn", style: .primary),
                      GameResultModal.Button(label: "EXIT", name: "exitBtn", style: .danger)])
        addChild(panel)
        gameOverPanel = panel

        onComplete?(playerWon)
    }

    private func resetGame() {
        gameOverPanel?.removeFromParent()
        gameOverPanel    = nil
        currentCycle     = 1
        userOuts         = 0
        aiOuts           = 0
        userStrikes      = 0
        aiStrikes        = 0
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
        startUserBatting(showModal: false)
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
        let lbl  = makeLabel(label, size: 10, color: fg)
        lbl.zPosition = 1; n.addChild(lbl)
        return n
    }

    // MARK: - Phase Transition Modals

    private func showReadyToBatModal() {
        phaseTransitionActive = true

        let panelW = size.width  * 0.72
        let panelH = size.height * 0.20
        let fs     = max(9, size.width * 0.058)

        let overlay = SKNode()
        overlay.zPosition = 1500
        overlay.name      = "readyToBatOverlay"
        overlay.alpha     = 0

        let back = SKSpriteNode(color: Parchment.paper.withAlphaComponent(0.96),
                                size: CGSize(width: panelW, height: panelH))
        overlay.addChild(back)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = Parchment.edge
        border.fillColor   = .clear
        border.lineWidth   = 3
        overlay.addChild(border)

        let title = makeLabel("READY TO BAT!", size: fs,
                              color: SKColor(red: 0.38, green: 0.90, blue: 0.38, alpha: 1))
        title.position = CGPoint(x: 0, y: panelH * 0.14)
        overlay.addChild(title)

        let sub = makeLabel("HOLD & RELEASE TO SWING", size: max(5, fs * 0.48),
                            color: SKColor(white: 0.68, alpha: 1))
        sub.position = CGPoint(x: 0, y: -panelH * 0.24)
        overlay.addChild(sub)

        addChild(overlay)
        overlay.run(.sequence([
            .fadeIn(withDuration: 0.18),
            .wait(forDuration: 2.0),
            .fadeOut(withDuration: 0.22),
            .removeFromParent(),
            .run { [weak self] in self?.phaseTransitionActive = false },
        ]))
    }

    private func showReadyToPitchModal() {
        phaseTransitionActive = true

        let panelW = size.width  * 0.72
        let panelH = size.height * 0.20
        let fs     = max(9, size.width * 0.058)

        let overlay = SKNode()
        overlay.zPosition = 1500
        overlay.name      = "readyToPitchOverlay"
        overlay.alpha     = 0

        let back = SKSpriteNode(color: Parchment.paper.withAlphaComponent(0.96),
                                size: CGSize(width: panelW, height: panelH))
        overlay.addChild(back)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = Parchment.edge
        border.fillColor   = .clear
        border.lineWidth   = 3
        overlay.addChild(border)

        let title = makeLabel("READY TO PITCH!", size: fs,
                              color: SKColor(red: 0.38, green: 0.78, blue: 1.0, alpha: 1))
        title.position = CGPoint(x: 0, y: panelH * 0.14)
        overlay.addChild(title)

        let sub = makeLabel("SWIPE UP FROM BOTTOM", size: max(5, fs * 0.48),
                            color: SKColor(white: 0.68, alpha: 1))
        sub.position = CGPoint(x: 0, y: -panelH * 0.24)
        overlay.addChild(sub)

        addChild(overlay)
        overlay.run(.sequence([
            .fadeIn(withDuration: 0.18),
            .wait(forDuration: 2.0),
            .fadeOut(withDuration: 0.22),
            .removeFromParent(),
            .run { [weak self] in self?.phaseTransitionActive = false },
        ]))
    }

    // MARK: - First-time Tutorial

    /// Presents the baseball tutorial via the shared `TutorialOverlay`. On
    /// auto-trigger (first play) we start the batting half after completion;
    /// on replay (HUD `?` button) we just resume — the game is already running.
    private func presentTutorial(autoTriggered: Bool) {
        let H = size.height
        let batY = H * 0.28
        let pitcherY = -H * 0.28
        let steps: [TutorialStep] = [
            .hint(at: CGPoint(x: 4, y: batY + 4),
                  title: "BATTING",
                  body:  "HOLD ANYWHERE TO CHARGE. RELEASE WHEN THE PITCH CROSSES THIS ZONE. 3 STRIKES = 1 OUT. BAT TILL 3 OUTS."),
            .hint(at: CGPoint(x: 0, y: pitcherY),
                  title: "PITCHING",
                  body:  "SWIPE UP FROM HERE TO THROW YOUR PITCH. AIM FOR THE STRIKE ZONE AT THE TOP."),
            .hint(at: CGPoint(x: 0, y: pitcherY - 80),
                  title: "FIELDING",
                  body:  "TAP A FIELDER TO SPRINT THEM AT THE BAG. CATCH IT TO GET AN OUT. BEST AVG HIT DISTANCE WINS."),
        ]
        let overlay = TutorialOverlay(steps: steps, sceneSize: size) { [weak self] in
            guard let self = self else { return }
            if autoTriggered {
                TutorialManager.shared.markSeen(TutorialManager.baseball)
                self.startUserBatting(showModal: false)
            }
        }
        addChild(overlay)
    }

    // MARK: - Pause / Resume

    private func pauseGame() {
        guard !isPausedGame, phase != .gameOver else { return }
        isPausedGame = true
        gameWorldNode.speed = 0
        showPauseOverlay()
    }

    private func resumeGame() {
        guard isPausedGame else { return }
        isPausedGame = false
        gameWorldNode.speed = 1
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
        panel.fillColor   = Parchment.paper.withAlphaComponent(0.97)
        panel.strokeColor = Parchment.edge.withAlphaComponent(0.80)
        panel.lineWidth   = 3; ov.addChild(panel)

        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "PAUSED"; title.fontSize = 16
        title.fontColor = Parchment.deep
        title.horizontalAlignmentMode = .center; title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 56); ov.addChild(title)

        let btnW = panelW - 40, btnH: CGFloat = 44
        let resumeBg = SKShapeNode(rect: CGRect(x: -btnW / 2, y: -btnH / 2, width: btnW, height: btnH), cornerRadius: 8)
        resumeBg.fillColor   = Parchment.amber.withAlphaComponent(0.20)
        resumeBg.strokeColor = Parchment.edge.withAlphaComponent(0.80)
        resumeBg.lineWidth   = 1.5; resumeBg.position = CGPoint(x: 0, y: 6)
        resumeBg.name = "resumeBtn"; ov.addChild(resumeBg)

        let resumeLbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
        resumeLbl.text = "RESUME"; resumeLbl.fontSize = 11
        resumeLbl.fontColor = Parchment.deep
        resumeLbl.horizontalAlignmentMode = .center; resumeLbl.verticalAlignmentMode = .center
        resumeLbl.position = CGPoint(x: 0, y: -1); resumeLbl.name = "resumeBtn"; resumeBg.addChild(resumeLbl)

        let help = TutorialHelpButton.make()
        help.position = CGPoint(x: 0, y: -62); ov.addChild(help)

        let helpHint = SKLabelNode(fontNamed: "PressStart2P-Regular")
        helpHint.text = "TUTORIAL"; helpHint.fontSize = 7
        helpHint.fontColor = Parchment.muted
        helpHint.horizontalAlignmentMode = .center; helpHint.verticalAlignmentMode = .top
        helpHint.position = CGPoint(x: 0, y: -80); ov.addChild(helpHint)
    }

    // MARK: - Quit Confirmation

    private func showConfirmQuit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true
        gameWorldNode.speed = 0
        let panel = QuitConfirmModal.make(sceneSize: size)
        addChild(panel)
        confirmPanel = panel
    }

    private func hideConfirmPanel() {
        confirmingQuit = false
        if !isPausedGame { gameWorldNode.speed = 1 }
        confirmPanel?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        confirmPanel = nil
    }

    // MARK: - Dismiss

    private func dismissScene(playerWon: Bool) {
        onComplete?(playerWon)
        guard let view = self.view, let prev = previousScene else { return }
        SceneTransition.iris(in: view, to: prev)
    }
}
