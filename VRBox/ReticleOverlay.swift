import UIKit
import QuartzCore

/// Círculo del centro (puntero de la cabeza) y avisos de texto, dibujados encima de cada ojo.
final class ReticleOverlay {
    let root = CALayer()

    private let ringBase = CAShapeLayer()
    private let ringProgress = CAShapeLayer()
    private let dot = CAShapeLayer()
    private let hintLayer = CATextLayer()

    init() {
        root.masksToBounds = true

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

        hintLayer.fontSize = 15
        hintLayer.alignmentMode = .center
        hintLayer.isWrapped = true
        hintLayer.foregroundColor = UIColor.white.cgColor
        hintLayer.backgroundColor = UIColor(white: 0, alpha: 0.6).cgColor
        hintLayer.cornerRadius = 8
        hintLayer.contentsScale = UIScreen.main.scale
        hintLayer.isHidden = true
        root.addSublayer(hintLayer)
    }

    func update(cursor: CGPoint, progress: CGFloat, hovering: Bool, hint: String?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        ringBase.position = cursor
        ringProgress.position = cursor
        dot.position = cursor
        ringBase.strokeColor = (hovering ? UIColor.green : UIColor.white).cgColor
        ringProgress.strokeEnd = progress
        ringProgress.isHidden = progress <= 0.001

        if let h = hint {
            hintLayer.frame = CGRect(x: 8, y: 8, width: max(10, root.bounds.width - 16), height: 48)
            hintLayer.string = h
            hintLayer.isHidden = false
        } else {
            hintLayer.isHidden = true
        }

        CATransaction.commit()
    }
}
