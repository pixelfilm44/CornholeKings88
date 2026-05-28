import SpriteKit

/// Shared "QUIT GAME?" confirmation modal used by every mini-game so the
/// quit-out experience looks and behaves identically everywhere.
///
/// Build the panel with `make(sceneSize:)` and add it to the scene (or to the
/// camera node for camera-scrolling scenes). Route taps by node name:
/// `cancelName` dismisses the panel, `quitName` confirms the quit.
enum QuitConfirmModal {
    static let panelName  = "confirmPanel"
    static let cancelName = "cancelQuitBtn"
    static let quitName   = "confirmQuitBtn"

    /// Returns a fully styled, faded-in modal panel anchored at its own origin.
    static func make(sceneSize: CGSize) -> SKNode {
        let panelW = sceneSize.width  * 0.70
        let panelH = sceneSize.height * 0.30
        let fs     = max(5, sceneSize.width * 0.042)

        let panel = SKNode()
        panel.zPosition = 3000
        panel.name      = panelName

        let bg = SKSpriteNode(color: SKColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.97),
                              size: CGSize(width: panelW, height: panelH))
        panel.addChild(bg)

        let border = SKShapeNode(rectOf: CGSize(width: panelW + 3, height: panelH + 3))
        border.strokeColor = SKColor(red: 0.60, green: 0.42, blue: 0.15, alpha: 1)
        border.fillColor   = .clear
        border.lineWidth   = 3
        panel.addChild(border)

        let q = label("QUIT GAME?", size: fs, color: SKColor(white: 0.88, alpha: 1))
        q.position = CGPoint(x: 0, y: panelH * 0.22)
        panel.addChild(q)

        let cancel = button("CANCEL", fg: .white,
                            bg: SKColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
                            size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        cancel.position = CGPoint(x: -panelW * 0.24, y: -panelH * 0.22)
        cancel.name     = cancelName
        panel.addChild(cancel)

        let quit = button("QUIT", fg: .white,
                          bg: SKColor(red: 0.50, green: 0.10, blue: 0.10, alpha: 1),
                          size: CGSize(width: panelW * 0.42, height: fs * 1.8))
        quit.position = CGPoint(x: panelW * 0.24, y: -panelH * 0.22)
        quit.name     = quitName
        panel.addChild(quit)

        panel.alpha = 0
        panel.run(.fadeIn(withDuration: 0.18))
        return panel
    }

    /// True if `node` (or any ancestor) is the cancel button.
    static func isCancel(_ node: SKNode) -> Bool { matches(node, cancelName) }
    /// True if `node` (or any ancestor) is the quit button.
    static func isQuit(_ node: SKNode) -> Bool { matches(node, quitName) }

    private static func matches(_ node: SKNode, _ name: String) -> Bool {
        var n: SKNode? = node
        while let cur = n {
            if cur.name == name { return true }
            n = cur.parent
        }
        return false
    }

    private static func label(_ text: String, size: CGFloat, color: SKColor) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: "PressStart2P-Regular")
        l.fontSize = size
        l.fontColor = color
        l.text = text
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        return l
    }

    private static func button(_ label: String, fg: SKColor, bg: SKColor, size: CGSize) -> SKNode {
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
}
