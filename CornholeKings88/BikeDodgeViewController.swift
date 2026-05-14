import UIKit
import SpriteKit

// MARK: - Scene delegate (scene → VC communication)
protocol BikeDodgeSceneDelegate: AnyObject {
    func bikeDodgeSceneDidRequestDismiss(_ scene: BikeDodgeScene)
}

// MARK: - View Controller
final class BikeDodgeViewController: UIViewController {

    private var skView: SKView!
    var onDismiss: (() -> Void)?
    private weak var closeButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        skView = SKView(frame: view.bounds)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
        skView.layer.magnificationFilter = .nearest
        skView.layer.minificationFilter = .nearest
        view.addSubview(skView)

        let btn = buildCloseButton()
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 44),
            btn.heightAnchor.constraint(equalToConstant: 44),
            btn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6)
        ])
        view.bringSubviewToFront(btn)
        closeButton = btn
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard skView.scene == nil else { return }
        let scene = BikeDodgeScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        scene.bikeDodgeDelegate = self
        skView.presentScene(scene)
    }

    // MARK: - Close button builder (matches Racing Mini Game.html .top-btn.close)
    private func buildCloseButton() -> UIButton {
        let btn = UIButton(type: .custom)
        btn.translatesAutoresizingMaskIntoConstraints = false

        // Metallic grey gradient: #5a5a5a → #383838 → #1f1f1f
        let grad = CAGradientLayer()
        grad.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        grad.colors = [
            UIColor(white: 0.354, alpha: 1).cgColor,
            UIColor(white: 0.220, alpha: 1).cgColor,
            UIColor(white: 0.122, alpha: 1).cgColor,
        ]
        grad.locations = [0, 0.5, 1.0]
        grad.cornerRadius = 6
        btn.layer.insertSublayer(grad, at: 0)

        // Border #111, rounded corners
        btn.layer.cornerRadius = 6
        btn.layer.borderWidth = 2
        btn.layer.borderColor = UIColor(white: 0.067, alpha: 1).cgColor

        // Drop shadow (0 4px 0 #0a0a0a, blur 12)
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 4)
        btn.layer.shadowOpacity = 0.75
        btn.layer.shadowRadius = 5
        btn.layer.masksToBounds = false

        // Top highlight inset (inset 0 1px 0 rgba(255,255,255,0.12))
        let highlight = CALayer()
        highlight.frame = CGRect(x: 2, y: 2, width: 40, height: 1)
        highlight.backgroundColor = UIColor(white: 1, alpha: 0.12).cgColor
        btn.layer.addSublayer(highlight)

        // 4 corner rivets — 4×4 circles with metallic radial look
        let rivetXY: [(CGFloat, CGFloat)] = [(4, 4), (36, 4), (4, 36), (36, 36)]
        for (rx, ry) in rivetXY {
            let rv = CALayer()
            rv.frame = CGRect(x: rx, y: ry, width: 4, height: 4)
            rv.cornerRadius = 2
            // Metallic rivet: light top-left, dark bottom-right
            let rvGrad = CAGradientLayer()
            rvGrad.frame = CGRect(origin: .zero, size: CGSize(width: 4, height: 4))
            rvGrad.cornerRadius = 2
            rvGrad.colors = [
                UIColor(white: 0.67, alpha: 1).cgColor,
                UIColor(white: 0.33, alpha: 1).cgColor,
                UIColor(white: 0.13, alpha: 1).cgColor,
            ]
            rvGrad.locations = [0, 0.6, 1.0]
            rvGrad.startPoint = CGPoint(x: 0.35, y: 0.3)
            rvGrad.endPoint   = CGPoint(x: 1.0,  y: 1.0)
            rv.addSublayer(rvGrad)
            btn.layer.addSublayer(rv)
        }

        // X mark as a UIView subview — subviews always composite above the parent's own sublayers,
        // so this is immune to gradient/rivet layer ordering issues.
        let xOverlay = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        xOverlay.backgroundColor = .clear
        xOverlay.isUserInteractionEnabled = false
        let xl = CAShapeLayer()
        xl.frame = xOverlay.bounds
        let xp = CGMutablePath()
        xp.move(to: CGPoint(x: 13, y: 13)); xp.addLine(to: CGPoint(x: 31, y: 31))
        xp.move(to: CGPoint(x: 31, y: 13)); xp.addLine(to: CGPoint(x: 13, y: 31))
        xl.path = xp
        xl.strokeColor = UIColor(red: 0.831, green: 0.267, blue: 0.118, alpha: 1).cgColor
        xl.lineWidth = 2.5
        xl.lineCap = .square
        xl.fillColor = nil
        xOverlay.layer.addSublayer(xl)
        btn.addSubview(xOverlay)

        // Press-down effect: translateY(3px) + reduced shadow
        btn.addTarget(self, action: #selector(closeBtnDown), for: .touchDown)
        btn.addTarget(self, action: #selector(closeBtnUp),
                      for: [.touchUpInside, .touchUpOutside, .touchCancel])
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        return btn
    }

    @objc private func closeBtnDown() {
        UIView.animate(withDuration: 0.06) {
            self.closeButton?.transform = CGAffineTransform(translationX: 0, y: 3)
        }
        closeButton?.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    @objc private func closeBtnUp() {
        UIView.animate(withDuration: 0.12) {
            self.closeButton?.transform = .identity
        }
        closeButton?.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
        onDismiss?()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}

extension BikeDodgeViewController: BikeDodgeSceneDelegate {
    func bikeDodgeSceneDidRequestDismiss(_ scene: BikeDodgeScene) {
        dismiss(animated: true)
        onDismiss?()
    }
}
