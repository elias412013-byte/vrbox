import UIKit
import QuartzCore

/// Capa que se dibuja encima de cada ojo: detección, esqueleto, cursor y avisos.
final class HandOverlay {
    let root = CALayer()
    var imgSize = CGSize(width: 1280, height: 720)

    private let maskLayer = CALayer()
    private let skeleton = CAShapeLayer()
    private let joints = CAShapeLayer()
    private let calibBox = CAShapeLayer()
    private let ringBase = CAShapeLayer()
    private let ringProgress = CAShapeLayer()
    private let dot = CAShapeLayer()
    private let hintLayer = CATextLayer()

    init() {
        root.masksToBounds = true

        maskLayer.opacity = 0.4
        maskLayer.magnificationFilter = .nearest
        root.addSublayer(maskLayer)

        skeleton.fillColor = nil
        skeleton.strokeColor = UIColor(red: 0, green: 0.85, blue: 1, alpha: 1).cgColor
        skeleton.lineWidth = 3
        skeleton.lineCap = .round
        root.addSublayer(skeleton)

        joints.fillColor = UIColor.white.cgColor
        joints.strokeColor = nil
        root.addSublayer(joints)

        calibBox.fillColor = nil
        calibBox.strokeColor = UIColor.yellow.cgColor
        calibBox.lineWidth = 3
        calibBox.lineDashPattern = [8, 6]
        root.addSublayer(calibBox)

        ringBase.path = UIBezierPath(arcCenter: .zero, radius: 18, startAngle: 0,
                                     endAngle: .pi * 2, clockwise: true).cgPath
        ringBase.fillColor = nil
        ringBase.lineWidth = 3
        ringBase.strokeColor = UIColor.white.cgColor
        root.addSublayer(ringBase)

        ringProgress.path = UIBezierPath(arcCenter: .zero, radius: 26, startAngle: -.pi / 2,
                                         endAngle: .pi * 1.5, clockwise: true).cgPath
        ringProgress.fillColor = nil
        ringProgress.lineWidth = 5
        ringProgress.strokeColor = UIColor.green.cgColor
        ringProgress.strokeEnd = 0
        root.addSublayer(ringProgress)

        dot.path = UIBezierPath(ovalIn: CGRect(x: -3, y: -3, width: 6, height: 6)).cgPath
        dot.fillColor = UIColor.white.cgColor
        root.addSublayer(dot)

        hintLayer.fontSize = 13
        hintLayer.alignmentMode = .center
        hintLayer.isWrapped = true
        hintLayer.foregroundColor = UIColor.white.cgColor
        hintLayer.backgroundColor = UIColor(white: 0, alpha: 0.6).cgColor
        hintLayer.cornerRadius = 8
        hintLayer.contentsScale = UIScreen.main.scale
        hintLayer.isHidden = true
        root.addSublayer(hintLayer)
    }

    /// Convierte un punto normalizado de la imagen de la cámara a coordenadas de esta capa
    /// (la cámara se muestra con "aspect fill", centrada).
    func mapPoint(_ n: CGPoint) -> CGPoint {
        let sw = root.bounds.width, sh = root.bounds.height
        guard imgSize.width > 0, imgSize.height > 0 else { return .zero }
        let s = max(sw / imgSize.width, sh / imgSize.height)
        let dw = imgSize.width * s, dh = imgSize.height * s
        return CGPoint(x: (sw - dw) / 2 + n.x * dw, y: (sh - dh) / 2 + n.y * dh)
    }

    func update(maskImage: CGImage?, showMask: Bool,
                palm: CGPoint?, tip: CGPoint?, showSkeleton: Bool,
                cursor: CGPoint, progress: CGFloat, hovering: Bool,
                hint: String?, calibRect: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if showMask, let img = maskImage {
            let a = mapPoint(.zero), b = mapPoint(CGPoint(x: 1, y: 1))
            maskLayer.frame = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
            maskLayer.contents = img
            maskLayer.isHidden = false
        } else {
            maskLayer.isHidden = true
        }

        if showSkeleton, let p = palm, let t = tip {
            let P = mapPoint(p), T = mapPoint(t)
            let line = UIBezierPath()
            line.move(to: P)
            line.addLine(to: T)
            line.append(UIBezierPath(ovalIn: CGRect(x: P.x - 12, y: P.y - 12, width: 24, height: 24)))
            skeleton.path = line.cgPath
            let jp = UIBezierPath()
            for f in [0.0, 0.33, 0.66, 1.0] {
                let k = CGFloat(f)
                let c = CGPoint(x: P.x + (T.x - P.x) * k, y: P.y + (T.y - P.y) * k)
                jp.append(UIBezierPath(ovalIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)))
            }
            joints.path = jp.cgPath
            skeleton.isHidden = false
            joints.isHidden = false
        } else {
            skeleton.isHidden = true
            joints.isHidden = true
        }

        if let r = calibRect {
            let a = mapPoint(r.origin)
            let b = mapPoint(CGPoint(x: r.maxX, y: r.maxY))
            calibBox.path = UIBezierPath(rect: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)).cgPath
            calibBox.isHidden = false
        } else {
            calibBox.isHidden = true
        }

        ringBase.position = cursor
        ringProgress.position = cursor
        dot.position = cursor
        ringBase.strokeColor = (hovering ? UIColor.green : UIColor.white).cgColor
        ringProgress.strokeEnd = progress
        ringProgress.isHidden = progress <= 0.001

        if let h = hint {
            hintLayer.frame = CGRect(x: 8, y: 8, width: max(10, root.bounds.width - 16), height: 40)
            hintLayer.string = h
            hintLayer.isHidden = false
        } else {
            hintLayer.isHidden = true
        }

        CATransaction.commit()
    }
}
