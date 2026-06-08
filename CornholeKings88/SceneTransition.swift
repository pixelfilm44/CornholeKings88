import UIKit
import SpriteKit

/// NES-style scene transitions. Iris wipes a circular hole closed over the
/// current scene, swaps to the next scene under cover of black, then opens
/// the circle back up. Single entry point used by world ↔ mini-game swaps.
enum SceneTransition {

    /// Iris-out → swap → iris-in. The mask layer sits on the SKView so the
    /// effect spans the scene transition itself.
    static func iris(in view: SKView,
                     to next: SKScene,
                     outDuration: CFTimeInterval = 0.18,
                     holdDuration: CFTimeInterval = 0.04,
                     inDuration: CFTimeInterval = 0.20,
                     completion: (() -> Void)? = nil) {

        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = .black
        overlay.isUserInteractionEnabled = true   // swallow taps mid-transition
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)

        let center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
        let maxRadius = hypot(overlay.bounds.width, overlay.bounds.height) * 0.5 + 8

        let mask = CAShapeLayer()
        mask.frame = overlay.bounds
        mask.fillRule = .evenOdd
        overlay.layer.mask = mask

        func path(radius: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.addRect(overlay.bounds)
            let r = max(radius, 0.5)
            p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                    width: r * 2, height: r * 2))
            return p
        }

        // Start fully open (only the rect outside the big circle is opaque,
        // and since the circle covers the whole view, nothing is opaque).
        mask.path = path(radius: maxRadius)

        // Phase 1 — iris out (circle shrinks → screen turns black).
        let shrink = CABasicAnimation(keyPath: "path")
        shrink.fromValue = path(radius: maxRadius)
        shrink.toValue   = path(radius: 0)
        shrink.duration  = outDuration
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        mask.add(shrink, forKey: "irisOut")
        mask.path = path(radius: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + outDuration + holdDuration) { [weak view, weak overlay] in
            guard let view = view, let overlay = overlay else {
                completion?()
                return
            }

            // Swap scenes while screen is fully black.
            view.presentScene(next)

            // Keep overlay on top of the new scene's view layer.
            view.bringSubviewToFront(overlay)

            // Defer one runloop so the new scene paints its first frame
            // before we start opening the iris.
            DispatchQueue.main.async {
                let grow = CABasicAnimation(keyPath: "path")
                grow.fromValue = path(radius: 0)
                grow.toValue   = path(radius: maxRadius)
                grow.duration  = inDuration
                grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
                grow.fillMode = .forwards
                grow.isRemovedOnCompletion = false
                mask.add(grow, forKey: "irisIn")
                mask.path = path(radius: maxRadius)

                DispatchQueue.main.asyncAfter(deadline: .now() + inDuration + 0.02) { [weak overlay] in
                    overlay?.removeFromSuperview()
                    completion?()
                }
            }
        }
    }
}
