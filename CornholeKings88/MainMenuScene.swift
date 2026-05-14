import SpriteKit
import UIKit

// MARK: - Delegate
protocol MainMenuSceneDelegate: AnyObject {
    func mainMenuSceneDidSelectBikeRace(_ scene: MainMenuScene)
}

// MARK: - Main Menu Scene
final class MainMenuScene: SKScene {

    weak var menuDelegate: MainMenuSceneDelegate?

    private var W: CGFloat = 0, H: CGFloat = 0

    private struct MenuItem {
        let label: String
        let subLabel: String
        let name: String
        let isPrimary: Bool
    }

    private let items: [MenuItem] = [
        MenuItem(label: "PLAY",       subLabel: "adventure",   name: "story",     isPrimary: true),
        MenuItem(label: "MINI GAMES", subLabel: "pick a game", name: "minigames", isPrimary: false),
        MenuItem(label: "STATS",      subLabel: "records",     name: "stats",     isPrimary: false),
        MenuItem(label: "SETTINGS",   subLabel: "options",     name: "settings",  isPrimary: false),
    ]

    private var buttonSprites: [String: SKSpriteNode] = [:]

    // MARK: - didMove
    override func didMove(to view: SKView) {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        W = size.width
        H = size.height

        backgroundColor = .black

        setupBackground()
        setupCrtOverlay()
        setupTitle()
        setupMenuButtons()
        setupEmbers()
        prewarmAssets()
    }

    // MARK: - Background
    private func setupBackground() {
        let tex: SKTexture
        if UIImage(named: "mainMenu") != nil {
            tex = SKTexture(imageNamed: "mainMenu")
            tex.filteringMode = .nearest
        } else {
            tex = makeSunsetTexture()
        }
        // Scale the image to cover the full scene height while preserving aspect ratio
        let imgAspect = tex.size().width / tex.size().height
        let bgW = max(W, H * imgAspect)
        let bgH = max(H, W / imgAspect)
        let bg = SKSpriteNode(texture: tex, size: CGSize(width: bgW, height: bgH))
        bg.position  = .zero
        bg.zPosition = -10
        addChild(bg)
    }

    private func makeSunsetTexture() -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            let c = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0.08, green: 0.04, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.22, green: 0.08, blue: 0.08, alpha: 1).cgColor,
                UIColor(red: 0.52, green: 0.22, blue: 0.06, alpha: 1).cgColor,
                UIColor(red: 0.20, green: 0.10, blue: 0.04, alpha: 1).cgColor,
                UIColor(red: 0.04, green: 0.02, blue: 0.01, alpha: 1).cgColor,
            ] as CFArray
            let grad = CGGradient(colorsSpace: space, colors: colors,
                                  locations: [0, 0.22, 0.46, 0.68, 1.0])!
            // UIKit renderer has top-left origin; draw top→bottom
            c.drawLinearGradient(grad,
                                 start: .zero,
                                 end: CGPoint(x: 0, y: H),
                                 options: [])
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // MARK: - CRT Overlay
    private func setupCrtOverlay() {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            let c = ctx.cgContext
            // Transparent base so alpha-blend compositing works correctly
            c.clear(CGRect(x: 0, y: 0, width: W, height: H))
            // Scanlines: dark semi-transparent stripe every 3 points
            c.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            var y: CGFloat = 0
            while y < H { c.fill(CGRect(x: 0, y: y, width: W, height: 1)); y += 3 }
            // Vignette: transparent center → dark edges
            let space = CGColorSpaceCreateDeviceRGB()
            let vColors = [UIColor(white: 0, alpha: 0).cgColor,
                           UIColor(white: 0, alpha: 0.18).cgColor,
                           UIColor(white: 0, alpha: 0.70).cgColor] as CFArray
            let vGrad = CGGradient(colorsSpace: space, colors: vColors, locations: [0, 0.55, 1.0])!
            c.drawRadialGradient(vGrad,
                                 startCenter: CGPoint(x: W/2, y: H/2), startRadius: 0,
                                 endCenter:   CGPoint(x: W/2, y: H/2), endRadius: max(W, H) * 0.72,
                                 options: [])
        }
        let overlay = SKSpriteNode(texture: SKTexture(image: img),
                                   size: CGSize(width: W, height: H))
        overlay.position  = .zero
        overlay.zPosition = 90
        // Default alpha blend — transparent pixels pass through, dark pixels darken the scene
        addChild(overlay)
    }

    // MARK: - Floating title (no plaque background)
    private func setupTitle() {
        let font = "PressStart2P-Regular"
        let titleFS: CGFloat = min(34, W / 8)
        let titleColor = SKColor(red: 0xFE/255.0, green: 0xC7/255.0, blue: 0x27/255.0, alpha: 1) // #FEC727
        let shadowColor = SKColor.black
        let topY = H / 2 - H * 0.28 + 120

        let texts: [(String, CGFloat)] = [
            ("CORNHOLE", topY),
            ("KINGS",    topY - titleFS - 10),
        ]

        for (text, y) in texts {
            // Shadow (pixel-font black, slightly offset behind main label)
            let shadow = SKLabelNode(fontNamed: font)
            shadow.text = text
            shadow.fontSize = titleFS
            shadow.fontColor = shadowColor
            shadow.horizontalAlignmentMode = .center
            shadow.verticalAlignmentMode   = .top
            shadow.position  = CGPoint(x: 2, y: y - 3)
            shadow.zPosition = 19
            addChild(shadow)

            let lbl = SKLabelNode(fontNamed: font)
            lbl.text = text
            lbl.fontSize = titleFS
            lbl.fontColor = titleColor
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode   = .top
            lbl.position  = CGPoint(x: 0, y: y)
            lbl.zPosition = 20
            addChild(lbl)
        }
    }

    // MARK: - Menu Buttons (pushed to bottom, no sub-labels)
    private func setupMenuButtons() {
        let font = "PressStart2P-Regular"
        let btnW = min(W * 0.88, 320)
        let primaryH: CGFloat = 58
        let normalH: CGFloat  = 48
        let gap: CGFloat = 10
        let bottomPad: CGFloat = 32

        // Total height of the button stack
        let totalBtnsH = primaryH + CGFloat(items.count - 1) * (normalH + gap)

        // Start Y = bottom of button stack + bottom padding; buttons flow downward
        var curY = -H / 2 + bottomPad + totalBtnsH

        for item in items {
            let btnH = item.isPrimary ? primaryH : normalH
            let tex  = makeButtonTexture(size: CGSize(width: btnW, height: btnH), isPrimary: item.isPrimary)
            let sprite = SKSpriteNode(texture: tex, size: CGSize(width: btnW, height: btnH))
            let centerY = curY - btnH / 2
            sprite.position  = CGPoint(x: 0, y: centerY)
            sprite.zPosition = 20
            sprite.name      = item.name
            addChild(sprite)
            buttonSprites[item.name] = sprite

            // Left-side rivets
            addRivet(at: CGPoint(x: -btnW / 2 + 9, y: centerY + btnH / 2 - 9), radius: 2.5, z: 21)
            addRivet(at: CGPoint(x: -btnW / 2 + 9, y: centerY - btnH / 2 + 9), radius: 2.5, z: 21)

            // Centered title label (no sub-label)
            let titleColor: SKColor = item.isPrimary
                ? SKColor(red: 1.0, green: 0.89, blue: 0.69, alpha: 1)
                : SKColor(red: 0.94, green: 0.75, blue: 0.38, alpha: 1)
            let titleFS: CGFloat = item.isPrimary ? min(14, btnW / 18) : min(11, btnW / 23)

            let lbl = SKLabelNode(fontNamed: font)
            lbl.text                    = item.label
            lbl.fontSize                = titleFS
            lbl.fontColor               = titleColor
            lbl.horizontalAlignmentMode = .left
            lbl.verticalAlignmentMode   = .center
            lbl.position  = CGPoint(x: -btnW / 2 + 22, y: centerY)
            lbl.zPosition = 21
            lbl.name      = item.name
            addChild(lbl)

            // Bobbing arrow
            let arrow = SKLabelNode(fontNamed: font)
            arrow.text                    = "\u{25B6}"
            arrow.fontSize                = min(10, btnW / 28)
            arrow.fontColor               = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 0.85)
            arrow.horizontalAlignmentMode = .right
            arrow.verticalAlignmentMode   = .center
            arrow.position  = CGPoint(x: btnW / 2 - 14, y: centerY)
            arrow.zPosition = 21
            arrow.name      = item.name
            arrow.run(.repeatForever(.sequence([
                .moveBy(x: 2, y: 0, duration: 0.6),
                .moveBy(x: -2, y: 0, duration: 0.6),
            ])))
            addChild(arrow)

            curY -= btnH + gap
        }
    }

    // MARK: - Ember particles
    private func setupEmbers() {
        let positions: [(CGFloat, CGFloat, Double)] = [
            (0.18, 0.18, 0.0), (0.78, 0.24, 0.6), (0.08, 0.46, 1.2),
            (0.88, 0.52, 1.8), (0.18, 0.72, 2.4), (0.72, 0.78, 3.0),
        ]
        for (px, py, delay) in positions {
            let ember = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            ember.fillColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 0.8)
            ember.strokeColor = .clear
            ember.position = CGPoint(x: -W / 2 + px * W, y: H / 2 - py * H)
            ember.zPosition = 5
            ember.run(.repeatForever(.sequence([
                .wait(forDuration: delay),
                .group([
                    .sequence([.fadeAlpha(to: 1.0, duration: 2.0), .fadeAlpha(to: 0.3, duration: 2.0)]),
                    .sequence([.moveBy(x: 0, y: -5, duration: 2.0), .moveBy(x: 0, y: 5, duration: 2.0)]),
                ]),
            ])))
            addChild(ember)
        }
    }

    // MARK: - Texture Builders

    private func addRivet(at pos: CGPoint, radius: CGFloat, z: CGFloat) {
        let r = SKShapeNode(circleOfRadius: radius)
        r.fillColor = SKColor(white: 0.42, alpha: 1)
        r.strokeColor = SKColor(white: 0.20, alpha: 1)
        r.lineWidth = 0.5
        r.position = pos
        r.zPosition = z
        addChild(r)
    }

    private func makeButtonTexture(size: CGSize, isPrimary: Bool) -> SKTexture {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let c = ctx.cgContext
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6)
            c.addPath(path.cgPath); c.clip()

            let space = CGColorSpaceCreateDeviceRGB()
            if isPrimary {
                // Warm wood/brown
                let colors = [
                    UIColor(red: 0.48, green: 0.23, blue: 0.09, alpha: 1).cgColor,
                    UIColor(red: 0.35, green: 0.16, blue: 0.06, alpha: 1).cgColor,
                    UIColor(red: 0.23, green: 0.10, blue: 0.03, alpha: 1).cgColor,
                ] as CFArray
                let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1.0])!
                c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                // Warm glow accent
                c.setFillColor(UIColor(red: 0.78, green: 0.55, blue: 0.16, alpha: 0.20).cgColor)
                c.fillEllipse(in: CGRect(x: size.width * 0.55, y: size.height * 0.25, width: size.width * 0.5, height: size.height * 0.9))
            } else {
                // Iron
                let colors = [
                    UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1).cgColor,
                    UIColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1).cgColor,
                    UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor,
                ] as CFArray
                let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1.0])!
                c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                // Rust spots
                c.setFillColor(UIColor(red: 0.63, green: 0.31, blue: 0.06, alpha: 0.35).cgColor)
                c.fillEllipse(in: CGRect(x: size.width * 0.62, y: size.height * 0.30, width: size.width * 0.42, height: size.height * 0.75))
                c.setFillColor(UIColor(red: 0.55, green: 0.24, blue: 0.04, alpha: 0.28).cgColor)
                c.fillEllipse(in: CGRect(x: -size.width * 0.05, y: size.height * 0.45, width: size.width * 0.28, height: size.height * 0.65))
            }

            // Top highlight
            c.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 1))

            // Bottom shadow
            c.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            c.fill(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3))

            // Border
            c.setStrokeColor(UIColor(white: 0.07, alpha: 1).cgColor)
            c.setLineWidth(2)
            let border = UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2), cornerRadius: 5)
            c.addPath(border.cgPath); c.strokePath()
        }
        let t = SKTexture(image: img); t.filteringMode = .nearest; return t
    }

    // MARK: - Touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let loc = touch.location(in: self)

        // Walk all nodes at touch point (sorted high→low z) and find the first named one.
        // Using nodes(at:) rather than atPoint so the CRT overlay sprite doesn't swallow taps.
        var name = ""
        for node in nodes(at: loc).sorted(by: { $0.zPosition > $1.zPosition }) {
            if let n = node.name, !n.isEmpty { name = n; break }
            if let n = node.parent?.name, !n.isEmpty { name = n; break }
        }
        guard !name.isEmpty else { return }

        if let sprite = buttonSprites[name] {
            sprite.run(.sequence([
                .scale(to: 0.94, duration: 0.07),
                .scale(to: 1.0, duration: 0.07),
            ]))
        }
        handleSelection(name: name)
    }

    private func handleSelection(name: String) {
        switch name {
        case "story":
            let s = StoryModuleScene(size: size)
            s.scaleMode = .resizeFill
            s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            s.startAtCurrentProgress()
            push(to: s)

        case "minigames":
            let s = MiniGamePickerScene(size: size)
            s.scaleMode = .resizeFill
            // Capture the delegate directly — MainMenuScene is deallocated once
            // MiniGamePickerScene replaces it, so [weak self] would be nil by tap time.
            weak var delegate = menuDelegate
            let menuSize = size
            s.onBikeRace = {
                let placeholder = MainMenuScene(size: menuSize)
                delegate?.mainMenuSceneDidSelectBikeRace(placeholder)
            }
            push(to: s)

        case "stats":
            let s = StatsScene(size: size)
            s.scaleMode = .resizeFill
            push(to: s)

        case "settings":
            showComingSoon()

        case "resetStory":
            StoryManager.shared.reset()

        default: break
        }
    }

    private func showComingSoon() {
        let font = "PressStart2P-Regular"
        let lbl = SKLabelNode(fontNamed: font)
        lbl.text = "COMING SOON"
        lbl.fontSize = min(10, W / 30)
        lbl.fontColor = SKColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1)
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: 0, y: 0)
        lbl.zPosition = 50
        addChild(lbl)
        lbl.run(.sequence([
            .wait(forDuration: 1.0),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    // MARK: - Helpers
    private func push(to scene: SKScene) {
        let t = SKTransition.push(with: .up, duration: 0.35)
        t.pausesOutgoingScene = false
        view?.presentScene(scene, transition: t)
    }

    // MARK: - Asset pre-warming
    // Eliminates the first-collision stutter in every mini-game by forcing Metal to
    // compile the CIPixellate shader pipeline and uploading textures/audio to GPU/memory
    // now, while the menu is idle, rather than on the first gameplay frame.
    private func prewarmAssets() {
        // 1. Force Metal to compile the CIPixellate shader pipeline.
        //    All mini-games use SKEffectNode+CIPixellate; the first render of that
        //    combo triggers main-thread shader compilation, which is the main freeze source.
        let shaderWarmup = SKEffectNode()
        shaderWarmup.alpha = 0.001   // nearly invisible but still rendered
        shaderWarmup.zPosition = -100
        if let filter = CIFilter(name: "CIPixellate") {
            filter.setValue(2.0, forKey: "inputScale")
            shaderWarmup.filter = filter
        }
        let dot = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
        shaderWarmup.addChild(dot)
        addChild(shaderWarmup)
        shaderWarmup.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))

        // 2. Pre-upload mini-game textures to the GPU.
        let textureNames = ["bag_16bit", "board_16bit"]
        let textures = textureNames.map { SKTexture(imageNamed: $0) }
        SKTexture.preload(textures) { }

        // 3. Pre-decode audio files so the AVAudio engine doesn't stall on first play.
        //    Run silent sound actions on a throw-away node that is never added to the scene.
        let soundNames = [
            "bag_land.wav", "hole_score.wav", "bat_crack.wav", "bat_whiff.wav",
            "game_win.wav", "game_lose.wav", "round_end.wav", "strike_call.wav",
            "out_caught.wav", "phase_change.wav", "rain_start.wav",
            "dog_bite.wav", "gopher_pop.wav", "gopher_steal.wav",
        ]
        let audioWarmup = SKNode()
        audioWarmup.alpha = 0
        addChild(audioWarmup)
        let soundActions = soundNames.map { SKAction.playSoundFileNamed($0, waitForCompletion: false) }
        audioWarmup.run(.sequence([
            .group(soundActions),
            .wait(forDuration: 0.1),
            .removeFromParent(),
        ]))
    }
}
