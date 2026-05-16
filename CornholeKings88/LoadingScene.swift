import SpriteKit
import AVFoundation
import CoreImage
import UIKit

// Shown once at app launch. Aggressively warms every code path that previously
// stuttered on first use in a mini-game — Metal shader variants, audio decode,
// font glyph rasterization, haptic engines, and Core Animation layer animations —
// so the first collision in any mini-game runs frame-perfect.
final class LoadingScene: SKScene {

    var onComplete: (() -> Void)?

    // Hold references so AVAudioPlayer instances don't get freed before they're
    // copied into the SKAction sound cache. We pass them off to a singleton.
    private static var preloadedAudio: [AVAudioPlayer] = []

    private var prewarmStarted = false
    private var prewarmFinished = false
    private var elapsed: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var minDisplaySeconds: TimeInterval = 0.9

    private var loadingLabel: SKLabelNode!
    private var dotsCount = 0

    override func didMove(to view: SKView) {
        // Cold app launch — restore hearts to full for the new session.
        HeartsManager.shared.refill()
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .black

        // Title
        let title = SKLabelNode(fontNamed: "PressStart2P-Regular")
        title.text = "CORNHOLE KINGS"
        title.fontSize = 18
        title.fontColor = SKColor(red: 0.95, green: 0.80, blue: 0.20, alpha: 1)
        title.position = CGPoint(x: 0, y: 20)
        addChild(title)

        // Loading text — animated dots
        loadingLabel = SKLabelNode(fontNamed: "PressStart2P-Regular")
        loadingLabel.text = "LOADING"
        loadingLabel.fontSize = 10
        loadingLabel.fontColor = .white
        loadingLabel.position = CGPoint(x: 0, y: -30)
        addChild(loadingLabel)

        loadingLabel.run(.repeatForever(.sequence([
            .run { [weak self] in
                guard let self = self else { return }
                self.dotsCount = (self.dotsCount + 1) % 4
                self.loadingLabel.text = "LOADING" + String(repeating: ".", count: self.dotsCount)
            },
            .wait(forDuration: 0.25),
        ])))
    }

    override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        let dt = min(0.1, currentTime - lastTime)
        lastTime = currentTime
        elapsed += dt

        // Defer prewarm one frame so the loading UI paints before we start blocking.
        if !prewarmStarted && elapsed > 0.05 {
            prewarmStarted = true
            runPrewarm()
        }

        if prewarmFinished && elapsed >= minDisplaySeconds {
            onComplete?()
            onComplete = nil   // one-shot
        }
    }

    // MARK: - Prewarm
    private func runPrewarm() {
        prewarmHaptics()
        prewarmFontGlyphs()
        prewarmCoreAnimation()
        prewarmShaderVariants()
        prewarmAudio()
        prewarmTextures { [weak self] in
            self?.prewarmFinished = true
        }
    }

    // 1. Touch each haptic generator so the Taptic Engine spins up.
    private func prewarmHaptics() {
        _ = HapticsManager.shared
        UIImpactFeedbackGenerator(style: .light).prepare()
        UIImpactFeedbackGenerator(style: .medium).prepare()
        UIImpactFeedbackGenerator(style: .heavy).prepare()
        UINotificationFeedbackGenerator().prepare()
    }

    // 2. Rasterize every PressStart2P glyph the mini-games will ever show.
    //    SKLabelNode lazily rasterizes glyphs per character on first render;
    //    pre-touching them now eliminates per-character hitches mid-game.
    private func prewarmFontGlyphs() {
        let chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz +-:.!?×▶▲♥"
        for fontSize: CGFloat in [8, 10, 12, 16, 20] {
            let lbl = SKLabelNode(fontNamed: "PressStart2P-Regular")
            lbl.text = chars
            lbl.fontSize = fontSize
            lbl.alpha = 0.001
            lbl.position = CGPoint(x: 0, y: -size.height)
            addChild(lbl)
            lbl.run(.sequence([.wait(forDuration: 0.4), .removeFromParent()]))
        }
        let helv = SKLabelNode(fontNamed: "Helvetica-Bold")
        helv.text = chars
        helv.fontSize = 14
        helv.alpha = 0.001
        helv.position = CGPoint(x: 0, y: -size.height)
        addChild(helv)
        helv.run(.sequence([.wait(forDuration: 0.4), .removeFromParent()]))
    }

    // 3. Run a CAKeyframeAnimation on the view's layer so Core Animation
    //    doesn't spin up its first-time pipeline during a crash shake.
    private func prewarmCoreAnimation() {
        guard let layer = view?.layer else { return }
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.values = [0, 0.5, 0]
        anim.duration = 0.2
        layer.add(anim, forKey: "prewarmShake")
    }

    // 4. Force Metal to compile the shader variants the mini-games use:
    //    (a) SKEffectNode + CIPixellate filter (universal mini-game pixelation)
    //    (b) SKSpriteNode with colorBlendFactor > 0 (bike crash colorize action)
    //    (c) SKShapeNode fill + stroke (HUD panels)
    private func prewarmShaderVariants() {
        // (a) Pixellate effect node
        let effect = SKEffectNode()
        if let filter = CIFilter(name: "CIPixellate") {
            filter.setValue(2.0, forKey: "inputScale")
            effect.filter = filter
        }
        effect.alpha = 0.001
        effect.zPosition = -100
        let dot = SKSpriteNode(color: .white, size: CGSize(width: 4, height: 4))
        effect.addChild(dot)
        addChild(effect)

        // (b) Color-blended textured sprite — exercises the colorize Metal shader.
        //     Use a real image so the variant for textured-with-color-blend compiles.
        let tex = makeOnePixelTexture(color: .white)
        let blendSprite = SKSpriteNode(texture: tex, size: CGSize(width: 8, height: 8))
        blendSprite.color = SKColor(red: 1, green: 0.4, blue: 0, alpha: 1)
        blendSprite.colorBlendFactor = 0.001
        blendSprite.alpha = 0.001
        blendSprite.position = CGPoint(x: 0, y: -size.height)
        addChild(blendSprite)
        blendSprite.run(.sequence([
            // Drive the colorize blend through several values to hit every code path.
            .colorize(with: .red,    colorBlendFactor: 1.0, duration: 0.05),
            .colorize(with: .white,  colorBlendFactor: 0.5, duration: 0.05),
            .colorize(withColorBlendFactor: 0.0, duration: 0.05),
            .removeFromParent(),
        ]))

        // (c) Shape node — fill + stroke + dash pattern.
        let shape = SKShapeNode(rectOf: CGSize(width: 6, height: 6), cornerRadius: 1)
        shape.fillColor = SKColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.5)
        shape.strokeColor = SKColor(red: 1, green: 1, blue: 0, alpha: 0.5)
        shape.lineWidth = 1
        shape.alpha = 0.001
        shape.position = CGPoint(x: 0, y: -size.height)
        addChild(shape)
        shape.run(.sequence([.wait(forDuration: 0.4), .removeFromParent()]))

        // Remove the effect node after a few frames so Metal has compiled.
        effect.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
    }

    // 5. Pre-decode every audio file via AVAudioPlayer.prepareToPlay() — silent.
    //    The players are held in a static so the audio data stays warm in memory.
    //    The mini-games call SKAction.playSoundFileNamed; that uses a separate cache,
    //    so we also fire each sound once at zero volume via a muted SKAudioNode to
    //    populate SpriteKit's cache without an audible playback.
    private func prewarmAudio() {
        let filenames = [
            "bag_land.wav", "hole_score.wav", "bat_crack.wav", "bat_whiff.wav",
            "game_win.wav", "game_lose.wav", "round_end.wav", "strike_call.wav",
            "out_caught.wav", "phase_change.wav", "rain_start.wav",
            "dog_bite.wav", "gopher_pop.wav", "gopher_steal.wav",
            "hit.mp3", "storm.mp3",
        ]
        for filename in filenames {
            let name = (filename as NSString).deletingPathExtension
            let ext  = (filename as NSString).pathExtension
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = 0
                player.prepareToPlay()
                LoadingScene.preloadedAudio.append(player)
            }
            // Also seed SpriteKit's internal SKAction sound cache via a silent audio
            // node. autoplayLooped=false keeps it quiet; the file is decoded on add.
            let node = SKAudioNode(url: url)
            node.autoplayLooped = false
            node.run(.changeVolume(to: 0, duration: 0))
            addChild(node)
            node.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
        }
    }

    // 6. Preload static image-named textures so the GPU upload happens now.
    private func prewarmTextures(completion: @escaping () -> Void) {
        let names = ["bag_16bit", "board_16bit", "player", "mainMenu"]
        let textures = names.compactMap { name -> SKTexture? in
            guard UIImage(named: name) != nil else { return nil }
            let t = SKTexture(imageNamed: name)
            t.filteringMode = .nearest
            return t
        }
        if textures.isEmpty {
            completion()
            return
        }
        SKTexture.preload(textures) {
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - Helpers
    private func makeOnePixelTexture(color: UIColor) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: fmt).image { ctx in
            ctx.cgContext.setFillColor(color.cgColor)
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest
        return t
    }
}
