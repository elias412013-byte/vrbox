import UIKit
import SceneKit
import AVFoundation
import simd

// MARK: - Utilidades de dibujo
private func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> UIColor {
    return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

private func gImage(_ w: CGFloat, _ h: CGFloat, _ draw: (CGContext) -> Void) -> UIImage {
    let f = UIGraphicsImageRendererFormat()
    f.scale = 1
    let r = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f)
    return r.image { c in draw(c.cgContext) }
}

private func gText(_ text: String, _ rect: CGRect, _ size: CGFloat, _ color: UIColor = .white,
                   bold: Bool = false, align: NSTextAlignment = .center, wrap: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
    let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
    if wrap {
        (text as NSString).draw(in: rect, withAttributes: attrs)
    } else {
        let h = font.lineHeight
        let r = CGRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h)
        (text as NSString).draw(in: r, withAttributes: attrs)
    }
}

private func fillR(_ c: CGContext, _ r: CGRect, _ col: UIColor) {
    c.setFillColor(col.cgColor)
    c.fill(r)
}

private func fillE(_ c: CGContext, _ r: CGRect, _ col: UIColor) {
    c.setFillColor(col.cgColor)
    c.fillEllipse(in: r)
}

private func strokeE(_ c: CGContext, _ r: CGRect, _ col: UIColor, _ w: CGFloat) {
    c.setStrokeColor(col.cgColor)
    c.setLineWidth(w)
    c.strokeEllipse(in: r)
}

private func strokeL(_ c: CGContext, _ a: CGPoint, _ b: CGPoint, _ col: UIColor, _ w: CGFloat) {
    c.setStrokeColor(col.cgColor)
    c.setLineWidth(w)
    c.move(to: a)
    c.addLine(to: b)
    c.strokePath()
}

private func curve(_ a: CGPoint, _ b: CGPoint, _ ctrl: CGPoint, _ col: UIColor, _ w: CGFloat) {
    let p = UIBezierPath()
    p.move(to: a)
    p.addQuadCurve(to: b, controlPoint: ctrl)
    p.lineWidth = w
    col.setStroke()
    p.stroke()
}

// MARK: - Texturas dibujadas por código (ligeras)
private enum Tex {
    static func wallHall() -> UIImage {
        return gImage(128, 128) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 128, height: 128), rgb(214, 196, 150))
            fillR(c, CGRect(x: 0, y: 88, width: 128, height: 40), rgb(120, 90, 60))
            fillR(c, CGRect(x: 0, y: 84, width: 128, height: 4), rgb(190, 170, 125))
            strokeL(c, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 128), rgb(170, 150, 110), 2)
        }
    }
    static func wallRoom() -> UIImage {
        return gImage(128, 128) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 128, height: 128), rgb(170, 205, 225))
            fillR(c, CGRect(x: 0, y: 70, width: 128, height: 10), rgb(255, 255, 255))
            fillR(c, CGRect(x: 0, y: 96, width: 128, height: 32), rgb(90, 120, 150))
            strokeL(c, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 128), rgb(130, 165, 190), 2)
        }
    }
    static func floorHall() -> UIImage {
        return gImage(64, 64) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 64, height: 64), rgb(205, 190, 160))
            fillR(c, CGRect(x: 0, y: 0, width: 32, height: 32), rgb(170, 155, 125))
            fillR(c, CGRect(x: 32, y: 32, width: 32, height: 32), rgb(170, 155, 125))
        }
    }
    static func carpet() -> UIImage {
        return gImage(64, 64) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 64, height: 64), rgb(120, 60, 60))
            fillR(c, CGRect(x: 0, y: 0, width: 32, height: 32), rgb(105, 50, 55))
            fillR(c, CGRect(x: 32, y: 32, width: 32, height: 32), rgb(105, 50, 55))
        }
    }
    static func ceiling() -> UIImage {
        return gImage(64, 64) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 64, height: 64), rgb(225, 225, 225))
            c.setStrokeColor(rgb(170, 170, 170).cgColor)
            c.setLineWidth(2)
            c.stroke(CGRect(x: 1, y: 1, width: 62, height: 62))
        }
    }
    static func sign(_ text: String, _ col: UIColor) -> UIImage {
        return gImage(256, 64) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 256, height: 64), col)
            gText(text, CGRect(x: 0, y: 0, width: 256, height: 64), 34, .white, bold: true)
        }
    }
    static func exitSign(_ open: Bool) -> UIImage {
        return gImage(256, 128) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 256, height: 128), open ? rgb(30, 160, 60) : rgb(150, 40, 40))
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(6)
            c.stroke(CGRect(x: 6, y: 6, width: 244, height: 116))
            gText(open ? "SALIDA" : "CERRADA", CGRect(x: 0, y: 0, width: 256, height: 128), 52, .white, bold: true)
        }
    }

    static func teacher() -> UIImage {
        return gImage(256, 384) { c in
            let skin = rgb(240, 200, 160)
            fillR(c, CGRect(x: 60, y: 205, width: 136, height: 179), rgb(90, 60, 140))
            fillR(c, CGRect(x: 112, y: 200, width: 32, height: 110), rgb(245, 245, 245))
            fillE(c, CGRect(x: 100, y: 196, width: 56, height: 22), rgb(210, 30, 40))
            fillE(c, CGRect(x: 60, y: 40, width: 136, height: 165), skin)
            fillE(c, CGRect(x: 50, y: 95, width: 34, height: 64), rgb(175, 175, 185))
            fillE(c, CGRect(x: 172, y: 95, width: 34, height: 64), rgb(175, 175, 185))
            fillE(c, CGRect(x: 84, y: 96, width: 38, height: 38), .white)
            fillE(c, CGRect(x: 134, y: 96, width: 38, height: 38), .white)
            strokeE(c, CGRect(x: 84, y: 96, width: 38, height: 38), .black, 4)
            strokeE(c, CGRect(x: 134, y: 96, width: 38, height: 38), .black, 4)
            fillE(c, CGRect(x: 98, y: 108, width: 12, height: 12), .black)
            fillE(c, CGRect(x: 146, y: 108, width: 12, height: 12), .black)
            curve(CGPoint(x: 92, y: 150), CGPoint(x: 164, y: 150), CGPoint(x: 128, y: 205), .black, 6)
            fillR(c, CGRect(x: 204, y: 140, width: 26, height: 244), rgb(225, 190, 110))
            for i in 0..<12 { fillR(c, CGRect(x: 204, y: 150 + CGFloat(i) * 20, width: 12, height: 3), .black) }
        }
    }

    static func principal() -> UIImage {
        return gImage(256, 384) { c in
            let skin = rgb(235, 190, 150)
            fillR(c, CGRect(x: 56, y: 200, width: 144, height: 184), rgb(95, 65, 40))
            fillR(c, CGRect(x: 112, y: 196, width: 32, height: 120), rgb(240, 240, 240))
            fillR(c, CGRect(x: 120, y: 205, width: 16, height: 100), rgb(170, 30, 30))
            fillE(c, CGRect(x: 66, y: 40, width: 124, height: 160), skin)
            fillE(c, CGRect(x: 62, y: 28, width: 132, height: 70), rgb(40, 30, 25))
            fillE(c, CGRect(x: 88, y: 96, width: 28, height: 22), .white)
            fillE(c, CGRect(x: 140, y: 96, width: 28, height: 22), .white)
            fillE(c, CGRect(x: 98, y: 102, width: 10, height: 10), .black)
            fillE(c, CGRect(x: 148, y: 102, width: 10, height: 10), .black)
            strokeL(c, CGPoint(x: 84, y: 90), CGPoint(x: 116, y: 98), .black, 6)
            strokeL(c, CGPoint(x: 172, y: 90), CGPoint(x: 140, y: 98), .black, 6)
            fillE(c, CGRect(x: 88, y: 138, width: 80, height: 22), rgb(40, 30, 25))
            fillE(c, CGRect(x: 118, y: 168, width: 20, height: 20), rgb(230, 190, 40))
        }
    }

    static func girl() -> UIImage {
        return gImage(256, 384) { c in
            let skin = rgb(245, 205, 170)
            fillR(c, CGRect(x: 80, y: 210, width: 96, height: 174), rgb(235, 110, 160))
            fillE(c, CGRect(x: 76, y: 50, width: 104, height: 130), skin)
            fillE(c, CGRect(x: 70, y: 36, width: 116, height: 60), rgb(120, 70, 30))
            fillE(c, CGRect(x: 40, y: 80, width: 44, height: 44), rgb(120, 70, 30))
            fillE(c, CGRect(x: 172, y: 80, width: 44, height: 44), rgb(120, 70, 30))
            fillE(c, CGRect(x: 100, y: 100, width: 14, height: 18), .black)
            fillE(c, CGRect(x: 142, y: 100, width: 14, height: 18), .black)
            curve(CGPoint(x: 108, y: 140), CGPoint(x: 148, y: 140), CGPoint(x: 128, y: 168), rgb(190, 40, 60), 5)
            strokeE(c, CGRect(x: 20, y: 150, width: 216, height: 220), rgb(240, 150, 30), 8)
        }
    }

    static func bully() -> UIImage {
        return gImage(256, 384) { c in
            let skin = rgb(225, 175, 135)
            fillR(c, CGRect(x: 40, y: 200, width: 176, height: 184), rgb(40, 90, 170))
            fillE(c, CGRect(x: 20, y: 215, width: 60, height: 120), skin)
            fillE(c, CGRect(x: 176, y: 215, width: 60, height: 120), skin)
            fillR(c, CGRect(x: 60, y: 290, width: 136, height: 28), skin)
            fillE(c, CGRect(x: 70, y: 52, width: 116, height: 150), skin)
            fillE(c, CGRect(x: 64, y: 30, width: 128, height: 80), rgb(200, 40, 40))
            fillR(c, CGRect(x: 120, y: 90, width: 110, height: 16), rgb(200, 40, 40))
            fillE(c, CGRect(x: 94, y: 118, width: 16, height: 14), .black)
            fillE(c, CGRect(x: 146, y: 118, width: 16, height: 14), .black)
            strokeL(c, CGPoint(x: 88, y: 108), CGPoint(x: 114, y: 116), .black, 6)
            strokeL(c, CGPoint(x: 168, y: 108), CGPoint(x: 142, y: 116), .black, 6)
            curve(CGPoint(x: 100, y: 172), CGPoint(x: 156, y: 172), CGPoint(x: 128, y: 150), .black, 6)
        }
    }

    static func robot() -> UIImage {
        return gImage(256, 384) { c in
            fillR(c, CGRect(x: 60, y: 170, width: 136, height: 170), rgb(150, 155, 165))
            fillR(c, CGRect(x: 76, y: 190, width: 104, height: 50), rgb(60, 65, 75))
            fillE(c, CGRect(x: 70, y: 335, width: 44, height: 44), rgb(40, 40, 40))
            fillE(c, CGRect(x: 142, y: 335, width: 44, height: 44), rgb(40, 40, 40))
            fillR(c, CGRect(x: 80, y: 50, width: 96, height: 100), rgb(170, 175, 185))
            fillE(c, CGRect(x: 104, y: 74, width: 48, height: 48), rgb(240, 200, 40))
            fillE(c, CGRect(x: 120, y: 90, width: 16, height: 16), .black)
            strokeL(c, CGPoint(x: 128, y: 50), CGPoint(x: 128, y: 20), .darkGray, 6)
            fillE(c, CGRect(x: 116, y: 8, width: 24, height: 24), rgb(220, 50, 50))
            strokeL(c, CGPoint(x: 196, y: 200), CGPoint(x: 232, y: 330), rgb(120, 80, 40), 10)
            fillR(c, CGRect(x: 205, y: 325, width: 50, height: 40), rgb(200, 160, 60))
        }
    }

    static func notebook() -> UIImage {
        return gImage(128, 128) { c in
            fillR(c, CGRect(x: 24, y: 12, width: 80, height: 104), rgb(205, 40, 50))
            fillR(c, CGRect(x: 24, y: 12, width: 10, height: 104), rgb(140, 20, 30))
            fillR(c, CGRect(x: 44, y: 34, width: 48, height: 40), .white)
            gText("+ −", CGRect(x: 44, y: 34, width: 48, height: 40), 26, .black, bold: true)
        }
    }
    static func coin() -> UIImage {
        return gImage(128, 128) { c in
            fillE(c, CGRect(x: 20, y: 20, width: 88, height: 88), rgb(240, 190, 30))
            strokeE(c, CGRect(x: 28, y: 28, width: 72, height: 72), rgb(190, 140, 10), 6)
            gText("$", CGRect(x: 28, y: 28, width: 72, height: 72), 50, rgb(150, 100, 0), bold: true)
        }
    }
    static func soda() -> UIImage {
        return gImage(128, 128) { c in
            fillR(c, CGRect(x: 40, y: 14, width: 48, height: 100), rgb(40, 170, 220))
            fillR(c, CGRect(x: 40, y: 50, width: 48, height: 24), .white)
            fillR(c, CGRect(x: 44, y: 8, width: 40, height: 8), rgb(190, 195, 200))
            fillR(c, CGRect(x: 44, y: 112, width: 40, height: 8), rgb(190, 195, 200))
        }
    }
    static func chocolate() -> UIImage {
        return gImage(128, 128) { c in
            fillR(c, CGRect(x: 20, y: 36, width: 88, height: 56), rgb(110, 60, 30))
            fillR(c, CGRect(x: 20, y: 52, width: 88, height: 24), rgb(235, 190, 40))
            gText("CHOC", CGRect(x: 20, y: 52, width: 88, height: 24), 20, rgb(110, 60, 30), bold: true)
        }
    }
    static func scissors() -> UIImage {
        return gImage(128, 128) { c in
            strokeE(c, CGRect(x: 26, y: 72, width: 30, height: 30), rgb(220, 60, 60), 8)
            strokeE(c, CGRect(x: 72, y: 72, width: 30, height: 30), rgb(220, 60, 60), 8)
            strokeL(c, CGPoint(x: 44, y: 76), CGPoint(x: 84, y: 14), rgb(200, 205, 215), 8)
            strokeL(c, CGPoint(x: 84, y: 76), CGPoint(x: 44, y: 14), rgb(200, 205, 215), 8)
        }
    }
    static func machine(_ choco: Bool) -> UIImage {
        return gImage(192, 320) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 192, height: 320), choco ? rgb(150, 70, 30) : rgb(30, 110, 190))
            fillR(c, CGRect(x: 16, y: 50, width: 120, height: 200), rgb(40, 50, 60))
            for i in 0..<4 {
                fillR(c, CGRect(x: 22, y: 58 + CGFloat(i) * 46, width: 108, height: 36),
                      choco ? rgb(235, 190, 40) : rgb(220, 240, 250))
            }
            fillR(c, CGRect(x: 146, y: 70, width: 30, height: 90), rgb(200, 200, 200))
            fillR(c, CGRect(x: 30, y: 268, width: 132, height: 34), rgb(20, 20, 20))
            gText(choco ? "CHOCOLATES" : "SODAS", CGRect(x: 0, y: 8, width: 192, height: 36), 24, .white, bold: true)
        }
    }
}

// MARK: - Sonido (todo generado por código, sin archivos)
private final class SoundBank {
    var enabled = true
    private var players: [String: AVAudioPlayer] = [:]

    init() {
        add("jingle", [(523.25, 0.16), (659.25, 0.16), (783.99, 0.16), (1046.5, 0.32),
                       (783.99, 0.16), (659.25, 0.16), (880.0, 0.16), (783.99, 0.40)])
        add("ok", [(880, 0.08), (1318, 0.14)])
        add("bad", [(220, 0.22), (150, 0.30)])
        add("coin", [(988, 0.06), (1319, 0.14)])
        add("tick", [(1500, 0.03)])
        add("jump", [(600, 0.05), (900, 0.08)])
        add("push", [(130, 0.18), (90, 0.18)])
        add("alarm", [(900, 0.15), (700, 0.15), (900, 0.15), (700, 0.15), (900, 0.15), (700, 0.15)])
        add("win", [(523.25, 0.14), (659.25, 0.14), (783.99, 0.14), (1046.5, 0.5)])
        add("lose", [(440, 0.25), (370, 0.25), (294, 0.5)])
    }

    private func add(_ name: String, _ notes: [(Double, Double)]) {
        if let p = try? AVAudioPlayer(data: SoundBank.wav(notes)) {
            p.prepareToPlay()
            players[name] = p
        }
    }

    func play(_ name: String) {
        guard enabled, let p = players[name] else { return }
        p.currentTime = 0
        p.play()
    }

    func stopAll() {
        for (_, p) in players { p.stop() }
    }

    private static func wav(_ notes: [(Double, Double)]) -> Data {
        let sr = 22050
        var samples = [Int16]()
        for (f, d) in notes {
            let n = Int(Double(sr) * d)
            for i in 0..<n {
                let t = Double(i) / Double(sr)
                let attack = min(1.0, t / 0.008)
                let release = min(1.0, Double(n - i) / (Double(sr) * 0.03))
                let v = sin(2.0 * Double.pi * f * t) * attack * release * 0.4
                samples.append(Int16(max(-1.0, min(1.0, v)) * 32000.0))
            }
        }
        var d = Data()
        func u32(_ x: UInt32) { var v = x.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { var v = x.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!)
        u32(UInt32(36 + samples.count * 2))
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!)
        u32(UInt32(samples.count * 2))
        samples.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
}

// MARK: - El juego
final class SchoolGame {

    // Mapa
    private let GW = 40
    private let GH = 28
    private let cell: Float = 2.0
    private var grid: [[Bool]] = []
    private var roomMap: [[Bool]] = []
    private let colRanges: [(Int, Int)] = [(4, 9), (11, 16), (18, 23), (25, 30), (32, 35)]
    private var barCells = Set<Int>()      // celdas cerradas para todos (detención)
    private var bullyCells = Set<Int>()    // celdas cerradas solo para el jugador

    // Tipos
    private enum Phase { case menu, options, settings, playing, notebook, paused, caught, won }
    private enum ItemKind { case soda, chocolate, scissors }
    private struct Btn {
        let id: String
        let title: String
        let rect: CGRect
        var dwell: Double = 1.0
    }
    private final class Actor {
        enum Kind { case teacher, principal, girl, bully, robot }
        let kind: Kind
        let node: SCNNode
        var x: Float = 0
        var z: Float = 0
        var active = true
        var timer: Float = 0
        var cooldown: Float = 0
        var state = 0
        var wp = 0
        var post = 0
        var pathTimer: Float = 0
        var nextCX = -1
        var nextCY = -1
        var pushLeft: Float = 0
        var pushDX: Float = 0
        var pushDZ: Float = 0
        init(kind: Kind, node: SCNNode) { self.kind = kind; self.node = node }
    }
    private final class Pickup {
        enum Kind { case notebook, coin, scissors }
        let kind: Kind
        let node: SCNNode
        let x: Float
        let z: Float
        var taken = false
        init(kind: Kind, node: SCNNode, x: Float, z: Float) { self.kind = kind; self.node = node; self.x = x; self.z = z }
    }
    private final class Machine {
        let choco: Bool
        let x: Float
        let z: Float
        init(choco: Bool, x: Float, z: Float) { self.choco = choco; self.x = x; self.z = z }
    }
    private enum Target { case notebook(Pickup), machine(Machine) }

    // Públicos
    var onExit: (() -> Void)?
    var dwellEnabled = true
    var headOrient = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private(set) var isActive = false
    private(set) var progress: CGFloat = 0
    private(set) var hovering = false
    private(set) var hintText: String? = nil

    // Vistas y escena
    private let leftView: SCNView
    private let rightView: SCNView
    private let scene = SCNScene()
    private let head = SCNNode()
    private let camL = SCNNode()
    private let camR = SCNNode()
    private var built = false
    private var orientWorld = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private let spawnYaw: Float = -Float.pi / 2

    // Nodos
    private let panelNode = SCNNode()
    private let hudRoot = SCNNode()
    private var hudTop = SCNNode()
    private var hudInv = SCNNode()
    private var hudBarFill = SCNNode()
    private var exitNodes: [SCNNode] = []

    // Estado de juego
    private var phase: Phase = .menu
    private var px: Float = 40
    private var pz: Float = 28
    private var stamina: Float = 100
    private var exhausted = false
    private var infStamina: Float = 0
    private var isRunning = false
    private var collected = 0
    private var coins = 0
    private var wrongCount = 0
    private var inventory: [ItemKind?] = [nil, nil, nil]
    private var selected = 0
    private var endgame = false
    private var exitsOpen = false
    private var gameTime: Float = 0
    private var tickTimer: Float = 0
    private var pushVX: Float = 0
    private var pushVZ: Float = 0
    private var inDetention = false
    private var detentionTimer: Float = 0
    private var stickX: Float = 0
    private var stickY: Float = 0
    private var runHeld = false
    private var hudDirty = true

    // Opciones
    private var visitor = false
    private var difficulty = 1
    private var voiceOn = true
    private var helpOn = true

    // Personajes y objetos
    private var teacher: Actor!
    private var principal: Actor!
    private var girl: Actor!
    private var bully: Actor!
    private var robot: Actor!
    private var pickups: [Pickup] = []
    private var machines: [Machine] = []

    // Cuerda
    private var ropeActive = false
    private var ropeTime: Float = 0
    private var ropeCycle = 0
    private var ropeCount = 0
    private var ropeJumped = false
    private var ropeFailed = false
    private var ropeWindow = false

    // Libreta
    private var currentNotebook: Pickup?
    private var problemIndex = 0
    private var curQuestion = ""
    private var curOptions: [String] = []
    private var curAnswer = 0

    // Mensajes y panel
    private var messageText = ""
    private var messageUntil: Float = 0
    private var panelButtons: [Btn] = []
    private var panelTitle = ""
    private var panelSub = ""
    private var panelQuestion: String? = nil
    private var hoverID: String? = nil
    private var hoverStart: CFTimeInterval = 0
    private var locked = false
    private var panelDirty = false
    private var lastPanelRender: CFTimeInterval = 0

    // Audio
    private let sounds = SoundBank()
    private let synth = AVSpeechSynthesizer()

    // Texturas de objetos (cache)
    private var itemImages: [UIImage] = []

    // Puestos fijos
    private let bullyPosts: [(Float, Float, [(Int, Int)])] = [
        (21, 28, [(10, 13), (10, 14)]),
        (59, 28, [(29, 13), (29, 14)]),
        (39, 4, [(19, 1), (19, 2)]),
        (39, 52, [(19, 25), (19, 26)])
    ]
    private let girlPosts: [(Float, Float)] = [(40, 4), (76, 40), (40, 52), (4, 16)]
    private let principalWP: [(Float, Float)] = [(4, 4), (76, 4), (76, 28), (4, 28), (4, 52), (76, 52), (76, 28), (4, 28)]
    private let robotWP: [(Float, Float)] = [(76, 52), (4, 52), (4, 4), (76, 4)]

    // MARK: Inicio / fin
    init(left: SCNView, right: SCNView) {
        leftView = left
        rightView = right
        let d = UserDefaults.standard
        if d.object(forKey: "g_visitor") != nil { visitor = d.bool(forKey: "g_visitor") }
        if d.object(forKey: "g_diff") != nil { difficulty = max(0, min(2, d.integer(forKey: "g_diff"))) }
        if d.object(forKey: "g_sound") != nil { sounds.enabled = d.bool(forKey: "g_sound") }
        if d.object(forKey: "g_voice") != nil { voiceOn = d.bool(forKey: "g_voice") }
        if d.object(forKey: "g_help") != nil { helpOn = d.bool(forKey: "g_help") }
    }

    private func saveOptions() {
        let d = UserDefaults.standard
        d.set(visitor, forKey: "g_visitor")
        d.set(difficulty, forKey: "g_diff")
        d.set(sounds.enabled, forKey: "g_sound")
        d.set(voiceOn, forKey: "g_voice")
        d.set(helpOn, forKey: "g_help")
    }

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        if !built {
            buildWorld()
            built = true
        }
        isActive = true
        leftView.scene = scene
        rightView.scene = scene
        leftView.pointOfView = camL
        rightView.pointOfView = camR
        resetState()
        phase = .menu
        showPanel()
    }

    func stop() {
        isActive = false
        synth.stopSpeaking(at: .immediate)
        sounds.stopAll()
    }

    // MARK: Entradas
    func stick(x: Float, y: Float) { stickX = x; stickY = y }
    func run(_ on: Bool) { runHeld = on }

    func padName(_ name: String) {
        switch name {
        case "A":
            if phase == .playing { interactA() } else { clickPointer() }
        case "←", "↑":
            if phase == .playing { selectSlot(-1) }
        case "→", "↓":
            if phase == .playing { selectSlot(1) }
        case "RT":
            useItem()
        case "Menú":
            togglePause()
        default:
            break
        }
    }

    private func clickPointer() {
        guard panelVisible, let id = hoverID else { return }
        locked = true
        hoverStart = CACurrentMediaTime()
        panelAction(id)
    }

    private var panelVisible: Bool { return phase != .playing }

    private func selectSlot(_ d: Int) {
        selected = (selected + d + 3) % 3
        hudDirty = true
    }

    private func togglePause() {
        if phase == .playing {
            phase = .paused
            showPanel()
        } else if phase == .paused {
            phase = .playing
            hidePanel()
        }
    }

    // MARK: Construcción del mundo
    private func carve(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, room: Bool) {
        for y in y0...y1 {
            for x in x0...x1 {
                grid[y][x] = true
                roomMap[y][x] = room
            }
        }
    }

    private func buildGrid() {
        grid = Array(repeating: Array(repeating: false, count: GW), count: GH)
        roomMap = grid
        carve(1, 1, 38, 2, room: false)
        carve(1, 25, 38, 26, room: false)
        carve(1, 1, 2, 26, room: false)
        carve(37, 1, 38, 26, room: false)
        carve(3, 13, 36, 14, room: false)
        for xs in colRanges {
            carve(xs.0, 4, xs.1, 11, room: true)
            carve(xs.0 + 2, 12, xs.0 + 3, 12, room: false)
            carve(xs.0, 16, xs.1, 23, room: true)
            carve(xs.0 + 2, 15, xs.0 + 3, 15, room: false)
        }
    }

    private func material(_ img: UIImage, repeatX: Float = 1, repeatY: Float = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.minificationFilter = .linear
        m.diffuse.magnificationFilter = .linear
        m.diffuse.mipFilter = .linear
        if repeatX != 1 || repeatY != 1 {
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        }
        return m
    }

    private func makeSprite(_ img: UIImage, w: CGFloat, h: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: w, height: h)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.isDoubleSided = true
        plane.materials = [m]
        let sprite = SCNNode(geometry: plane)
        sprite.position = SCNVector3(0, Float(h) / 2, 0)
        let bc = SCNBillboardConstraint()
        bc.freeAxes = .Y
        sprite.constraints = [bc]
        let holder = SCNNode()
        holder.addChildNode(sprite)
        scene.rootNode.addChildNode(holder)
        return holder
    }

    private func cellCenter(_ cx: Int, _ cy: Int) -> (Float, Float) {
        return (Float(cx) * cell + cell / 2, Float(cy) * cell + cell / 2)
    }

    private func buildWorld() {
        buildGrid()
        scene.background.contents = rgb(10, 10, 16)
        scene.fogColor = rgb(10, 10, 16)
        scene.fogStartDistance = 8
        scene.fogEndDistance = 34
        scene.rootNode.addChildNode(head)
        for (cam, x) in [(camL, Float(-0.032)), (camR, Float(0.032))] {
            let c = SCNCamera()
            c.zNear = 0.05
            c.zFar = 60
            c.fieldOfView = 80
            cam.camera = c
            cam.position = SCNVector3(x, 0, 0)
            head.addChildNode(cam)
        }
        itemImages = [Tex.soda(), Tex.chocolate(), Tex.scissors()]

        buildGeometry()
        buildActors()
        buildPickups()
        buildMachines()
        buildExits()
        buildHUD()
        buildPanel()
    }

    private func buildGeometry() {
        // Paredes (solo las que tocan piso), fusionadas en pocas mallas
        let parent = SCNNode()
        let boxHall = SCNBox(width: 2, height: 3, length: 2, chamferRadius: 0)
        boxHall.materials = [material(Tex.wallHall())]
        let boxRoom = SCNBox(width: 2, height: 3, length: 2, chamferRadius: 0)
        boxRoom.materials = [material(Tex.wallRoom())]
        for y in 0..<GH {
            for x in 0..<GW where !grid[y][x] {
                var near = false
                var hall = false
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0 && ny >= 0 && nx < GW && ny < GH && grid[ny][nx] {
                            near = true
                            if !roomMap[ny][nx] { hall = true }
                        }
                    }
                }
                if near {
                    let n = SCNNode(geometry: hall ? boxHall : boxRoom)
                    n.position = SCNVector3(Float(x) * cell + 1, 1.5, Float(y) * cell + 1)
                    parent.addChildNode(n)
                }
            }
        }
        scene.rootNode.addChildNode(parent.flattenedClone())

        // Piso
        let floorPlane = SCNPlane(width: CGFloat(GW) * 2, height: CGFloat(GH) * 2)
        floorPlane.materials = [material(Tex.floorHall(), repeatX: Float(GW), repeatY: Float(GH))]
        let floorNode = SCNNode(geometry: floorPlane)
        floorNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        floorNode.position = SCNVector3(Float(GW), 0, Float(GH))
        scene.rootNode.addChildNode(floorNode)

        // Alfombra de las aulas
        let carpetMat = Tex.carpet()
        for (i, xs) in colRanges.enumerated() {
            for top in [true, false] {
                _ = i
                let y0 = top ? 4 : 16, y1 = top ? 11 : 23
                let w = CGFloat((xs.1 - xs.0 + 1) * 2), h = CGFloat((y1 - y0 + 1) * 2)
                let p = SCNPlane(width: w, height: h)
                p.materials = [material(carpetMat, repeatX: Float(xs.1 - xs.0 + 1), repeatY: Float(y1 - y0 + 1))]
                let n = SCNNode(geometry: p)
                n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                n.position = SCNVector3(Float(xs.0 + xs.1 + 1), 0.01, Float(y0 + y1 + 1))
                scene.rootNode.addChildNode(n)
            }
        }

        // Techo
        let ceil = SCNPlane(width: CGFloat(GW) * 2, height: CGFloat(GH) * 2)
        ceil.materials = [material(Tex.ceiling(), repeatX: Float(GW), repeatY: Float(GH))]
        let ceilNode = SCNNode(geometry: ceil)
        ceilNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        ceilNode.position = SCNVector3(Float(GW), 3, Float(GH))
        scene.rootNode.addChildNode(ceilNode)

        // Carteles sobre las puertas
        let names = ["Aula 1", "Aula 2", "Aula 3", "Aula 4", "Detención",
                     "Aula 5", "Aula 6", "Aula 7", "Dirección", "Cantina"]
        var idx = 0
        for top in [true, false] {
            for xs in colRanges {
                let signCol: UIColor = (idx == 4) ? rgb(150, 40, 40) : (idx == 8 ? rgb(90, 60, 30) : (idx == 9 ? rgb(190, 110, 20) : rgb(30, 90, 60)))
                let img = Tex.sign(names[idx], signCol)
                let box = SCNBox(width: 4, height: 0.8, length: 2, chamferRadius: 0)
                let wallM = material(Tex.wallHall())
                let signM = material(img)
                // orden de caras: +z, +x, -z, -x, arriba, abajo
                box.materials = top ? [signM, wallM, wallM, wallM, wallM, wallM] : [wallM, wallM, signM, wallM, wallM, wallM]
                let n = SCNNode(geometry: box)
                let row = top ? 12 : 15
                n.position = SCNVector3(Float(xs.0 + 3) * cell, 2.6, Float(row) * cell + 1)
                scene.rootNode.addChildNode(n)
                idx += 1
            }
        }
    }

    private func buildActors() {
        teacher = Actor(kind: .teacher, node: makeSprite(Tex.teacher(), w: 1.1, h: 1.9))
        principal = Actor(kind: .principal, node: makeSprite(Tex.principal(), w: 1.1, h: 2.0))
        girl = Actor(kind: .girl, node: makeSprite(Tex.girl(), w: 1.0, h: 1.5))
        bully = Actor(kind: .bully, node: makeSprite(Tex.bully(), w: 1.3, h: 1.9))
        robot = Actor(kind: .robot, node: makeSprite(Tex.robot(), w: 1.1, h: 1.5))
    }

    private func buildPickups() {
        let nbImg = Tex.notebook(), coinImg = Tex.coin(), scImg = Tex.scissors()
        // 7 libretas en 7 aulas distintas (las aulas 0-3 de arriba y 5-7 de abajo)
        let nbRooms = [0, 1, 2, 3, 5, 6, 7]
        for (k, r) in nbRooms.enumerated() {
            let xs = colRanges[r % 5]
            let top = r < 5
            let bx = Float(xs.0 * 2) + ((k % 2 == 0) ? 2.4 : Float((xs.1 - xs.0 + 1) * 2) - 2.4)
            let bz = top ? Float(4 * 2) + 2.4 : Float(24 * 2) - 2.4
            let node = makeSprite(nbImg, w: 0.6, h: 0.6)
            node.position = SCNVector3(bx, 0, bz)
            pickups.append(Pickup(kind: .notebook, node: node, x: bx, z: bz))
        }
        // Monedas: una en cada aula y 4 en los pasillos
        var coinPts: [(Float, Float)] = []
        for xs in colRanges {
            coinPts.append((Float(xs.0 + xs.1 + 1), 14))
            coinPts.append((Float(xs.0 + xs.1 + 1), 36))
        }
        coinPts.append(contentsOf: [(40, 4), (76, 16), (4, 40), (40, 52), (56, 28), (24, 28)])
        for p in coinPts {
            let node = makeSprite(coinImg, w: 0.4, h: 0.4)
            node.position = SCNVector3(p.0, 0, p.1)
            pickups.append(Pickup(kind: .coin, node: node, x: p.0, z: p.1))
        }
        // Tijeras
        for p in [(Float(14), Float(40)), (Float(62), Float(16))] {
            let node = makeSprite(scImg, w: 0.5, h: 0.5)
            node.position = SCNVector3(p.0, 0, p.1)
            pickups.append(Pickup(kind: .scissors, node: node, x: p.0, z: p.1))
        }
    }

    private func buildMachines() {
        // Cantina (aula J, columnas 32-35, filas 16-23): máquinas en la pared este
        let defs: [(Bool, Float, Float, Float)] = [(true, 71.95, 38, -Float.pi / 2), (false, 71.95, 43, -Float.pi / 2),
                                                   (false, 5.95, 34, -Float.pi / 2)]
        for d in defs {
            let plane = SCNPlane(width: 1.3, height: 2.1)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Tex.machine(d.0)
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(d.1, 1.05, d.2)
            n.eulerAngles = SCNVector3(0, d.3, 0)
            scene.rootNode.addChildNode(n)
            machines.append(Machine(choco: d.0, x: d.1, z: d.2))
        }
    }

    private func buildExits() {
        // Salida norte (pared superior, anillo izquierdo) y sur (pared inferior, anillo derecho)
        let defs: [(Float, Float, Float)] = [(4, 2.0, 0), (76, 54.0, Float.pi)]
        for d in defs {
            let plane = SCNPlane(width: 3.0, height: 1.5)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Tex.exitSign(false)
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(d.0, 1.5, d.1 + (d.2 == 0 ? 0.02 : -0.02))
            n.eulerAngles = SCNVector3(0, d.2, 0)
            scene.rootNode.addChildNode(n)
            exitNodes.append(n)
        }
    }

    private func hudPlane(_ w: CGFloat, _ h: CGFloat, _ x: Float, _ y: Float, order: Int = 200) -> SCNNode {
        let p = SCNPlane(width: w, height: h)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        p.materials = [m]
        let n = SCNNode(geometry: p)
        n.position = SCNVector3(x, y, -1.0)
        n.renderingOrder = order
        hudRoot.addChildNode(n)
        return n
    }

    private func buildHUD() {
        head.addChildNode(hudRoot)
        hudTop = hudPlane(0.9, 0.14, 0, 0.40)
        hudInv = hudPlane(0.72, 0.22, 0, -0.30)
        let bg = hudPlane(0.6, 0.05, 0, -0.45)
        bg.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 0, alpha: 0.6)
        hudBarFill = hudPlane(0.58, 0.035, 0, -0.45, order: 201)
        hudBarFill.geometry?.firstMaterial?.diffuse.contents = rgb(60, 220, 90)
    }

    private func buildPanel() {
        let p = SCNPlane(width: 1.6, height: 0.9)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        p.materials = [m]
        panelNode.geometry = p
        panelNode.renderingOrder = 150
        panelNode.isHidden = true
        scene.rootNode.addChildNode(panelNode)
    }

    // MARK: Estado
    private func resetState() {
        px = 40; pz = 28
        stamina = 100; exhausted = false; infStamina = 0; isRunning = false
        collected = 0; coins = 0; wrongCount = 0
        inventory = [nil, nil, nil]; selected = 0
        endgame = false; exitsOpen = false
        pushVX = 0; pushVZ = 0
        inDetention = false; detentionTimer = 0
        ropeActive = false
        barCells.removeAll(); bullyCells.removeAll()
        messageText = ""; messageUntil = 0
        gameTime = 0
        for p in pickups { p.taken = false; p.node.isHidden = false }
        setExitsOpen(false)

        teacher.x = 40; teacher.z = 52; teacher.timer = 0; teacher.pushLeft = 0; teacher.nextCX = -1
        principal.x = 76; principal.z = 28; principal.state = 0; principal.cooldown = 0; principal.wp = 0
        robot.x = 4; robot.z = 52; robot.state = 0; robot.cooldown = 4; robot.wp = 0
        girl.post = 0; girl.cooldown = 0
        girl.x = girlPosts[0].0; girl.z = girlPosts[0].1
        bully.post = 0
        activateBully()
        for a in [teacher!, principal!, robot!, girl!, bully!] { syncNode(a) }
        hudDirty = true
        updateHead()
    }

    private func setExitsOpen(_ open: Bool) {
        exitsOpen = open
        for n in exitNodes { n.geometry?.firstMaterial?.diffuse.contents = Tex.exitSign(open) }
    }

    private func syncNode(_ a: Actor) {
        a.node.position = SCNVector3(a.x, 0, a.z)
    }

    private func message(_ t: String, _ secs: Float = 2.5) {
        messageText = t
        messageUntil = gameTime + secs
    }

    private func say(_ text: String) {
        guard voiceOn, sounds.enabled else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
        u.rate = 0.47
        u.pitchMultiplier = 0.75
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    // MARK: Paneles (menús del juego)
    private func showPanel() {
        hoverID = nil
        locked = false
        layoutPanel()
        placePanel()
        panelNode.isHidden = false
        panelNode.geometry?.firstMaterial?.diffuse.contents = renderPanel()
        hudRoot.isHidden = (phase == .menu || phase == .options || phase == .settings)
    }

    private func hidePanel() {
        panelNode.isHidden = true
        hoverID = nil
        hudRoot.isHidden = false
    }

    private func placePanel() {
        let f = forward2D()
        panelNode.position = SCNVector3(px + f.0 * 1.6, 1.55, pz + f.1 * 1.6)
        panelNode.eulerAngles = SCNVector3(0, atan2(-f.0, -f.1), 0)
    }

    private func layoutPanel() {
        var b: [Btn] = []
        func add(_ id: String, _ t: String, _ y: CGFloat, w: CGFloat = 600) {
            b.append(Btn(id: id, title: t, rect: CGRect(x: (1280 - w) / 2, y: y, width: w, height: 88)))
        }
        panelTitle = ""
        panelSub = ""
        panelQuestion = nil
        switch phase {
        case .menu:
            panelTitle = "LA ESCUELA"
            panelSub = "Juntá las 7 libretas y escapá del Profe"
            add("play", "Jugar", 230)
            add("opt", "Opciones", 335)
            add("set", "Configuración", 440)
            add("exit", "Salir", 545)
        case .options:
            panelTitle = "Opciones"
            add("visitor", "Modo visitante: " + (visitor ? "SÍ" : "NO"), 200, w: 780)
            add("diff", "Dificultad: " + ["Fácil", "Normal", "Difícil"][difficulty], 310, w: 780)
            add("back", "Volver", 480)
            panelSub = "Visitante: recorré todo sin que nadie te persiga"
        case .settings:
            panelTitle = "Configuración"
            add("snd", "Sonido: " + (sounds.enabled ? "SÍ" : "NO"), 170, w: 780)
            add("voice", "Voz del profe: " + (voiceOn ? "SÍ" : "NO"), 270, w: 780)
            add("help", "Ayuda de controles: " + (helpOn ? "SÍ" : "NO"), 370, w: 780)
            add("back", "Volver", 500)
        case .paused:
            panelTitle = "Pausa"
            add("resume", "Continuar", 230)
            add("restart", "Reiniciar", 335)
            add("tomenu", "Salir al menú del juego", 440, w: 780)
        case .notebook:
            panelTitle = "Libreta \(collected + 1)/7 · Problema \(problemIndex + 1)/3"
            panelQuestion = curQuestion
            for (i, o) in curOptions.enumerated() {
                add("a\(i)", ["A) ", "B) ", "C) "][i] + o, 330 + CGFloat(i) * 105, w: 800)
            }
        case .caught:
            panelTitle = "¡Te atrapó el Profe!"
            panelSub = "Libretas juntadas: \(collected)/7"
            add("retry", "Reintentar", 330)
            add("tomenu", "Menú del juego", 440)
        case .won:
            panelTitle = "¡ESCAPASTE!"
            panelSub = "Juntaste las 7 libretas y saliste de la escuela"
            add("retry", "Jugar de nuevo", 330)
            add("tomenu", "Menú del juego", 440)
        case .playing:
            break
        }
        panelButtons = b
    }

    private func renderPanel() -> UIImage {
        let hot = hoverID
        return gImage(1280, 720) { c in
            fillR(c, CGRect(x: 0, y: 0, width: 1280, height: 720), UIColor(white: 0.05, alpha: 0.92))
            c.setStrokeColor(rgb(200, 170, 80).cgColor)
            c.setLineWidth(6)
            c.stroke(CGRect(x: 6, y: 6, width: 1268, height: 708))
            gText(self.panelTitle, CGRect(x: 0, y: 40, width: 1280, height: 100), self.phase == .notebook ? 44 : 72, rgb(255, 230, 140), bold: true)
            if !self.panelSub.isEmpty {
                gText(self.panelSub, CGRect(x: 0, y: 140, width: 1280, height: 60), 34, UIColor(white: 0.8, alpha: 1))
            }
            if let q = self.panelQuestion {
                gText(q, CGRect(x: 80, y: 120, width: 1120, height: 190), 54, .white, bold: true, wrap: true)
            }
            for b in self.panelButtons {
                let isHot = (b.id == hot)
                (isHot ? rgb(120, 100, 40) : rgb(50, 50, 60)).setFill()
                UIBezierPath(roundedRect: b.rect, cornerRadius: 20).fill()
                gText(b.title, b.rect.insetBy(dx: 12, dy: 0), 44, .white)
            }
            if self.phase == .menu || self.phase == .options || self.phase == .settings {
                gText(self.dwellEnabled ? "Mirá un botón 1 segundo (o apretá A)" : "Apuntá con la cabeza y apretá A",
                      CGRect(x: 0, y: 660, width: 1280, height: 44), 28, UIColor(white: 0.6, alpha: 1))
            }
        }
    }

    private func panelAction(_ id: String) {
        switch id {
        case "play": beginPlay(); return
        case "opt": phase = .options
        case "set": phase = .settings
        case "back": phase = .menu
        case "exit": onExit?(); return
        case "visitor": visitor.toggle(); saveOptions()
        case "diff": difficulty = (difficulty + 1) % 3; saveOptions()
        case "snd": sounds.enabled.toggle(); saveOptions()
        case "voice": voiceOn.toggle(); saveOptions()
        case "help": helpOn.toggle(); saveOptions()
        case "resume": phase = .playing; hidePanel(); return
        case "restart", "retry": resetState(); beginPlay(); return
        case "tomenu": resetState(); phase = .menu
        case "a0": answer(0); return
        case "a1": answer(1); return
        case "a2": answer(2); return
        default: break
        }
        showPanel()
    }

    private func beginPlay() {
        resetState()
        phase = .playing
        hidePanel()
        sounds.play("jingle")
        say("¡Hola, alumno! Soy el Profe Regla. Juntá las siete libretas y escapá. ¡Si podés!")
        message(helpOn ? "Stick: caminar · LT: correr · A: usar · ←/→: inventario · RT: usar objeto" : "¡Buena suerte!", 6)
        if visitor { message("MODO VISITANTE: recorré todo tranquilo", 6) }
    }

    // MARK: Libretas y problemas
    private func openNotebook(_ p: Pickup) {
        currentNotebook = p
        problemIndex = 0
        phase = .notebook
        loadProblem()
        showPanel()
        sayProblem()
    }

    private func sayProblem() {
        var s = curQuestion
        s = s.replacingOccurrences(of: "+", with: " más ")
        s = s.replacingOccurrences(of: "−", with: " menos ")
        s = s.replacingOccurrences(of: "×", with: " por ")
        s = s.replacingOccurrences(of: "= ?", with: " igual a cuánto")
        say(s)
    }

    private func loadProblem() {
        let r = makeProblem(n: collected + 1, idx: problemIndex)
        curQuestion = r.0
        curOptions = r.1
        curAnswer = r.2
    }

    private func answer(_ i: Int) {
        if i == curAnswer {
            sounds.play("ok")
        } else {
            sounds.play("bad")
            if !visitor { wrongCount += 1 }
            say("¡Incorrecto!")
        }
        problemIndex += 1
        if problemIndex >= 3 {
            finishNotebook()
        } else {
            loadProblem()
            showPanel()
            sayProblem()
        }
    }

    private func finishNotebook() {
        currentNotebook?.taken = true
        currentNotebook?.node.isHidden = true
        collected += 1
        hudDirty = true
        phase = .playing
        hidePanel()
        if collected == 7 && !visitor {
            startEndgame()
        } else if collected == 1 && !visitor {
            message("Libreta 1/7 · ¡El Profe te va a buscar!", 3.5)
            say("¡Muy bien! Ahora vas a ver.")
        } else {
            message("Libreta \(collected)/7", 3)
        }
    }

    private func startEndgame() {
        endgame = true
        setExitsOpen(true)
        sounds.play("alarm")
        say("¡Ya no hay escapatoria!")
        message("¡LAS SALIDAS ESTÁN ABIERTAS! ¡Corré!", 6)
    }

    private func makeProblem(n: Int, idx: Int) -> (String, [String], Int) {
        if idx == 2 && n >= 2 {
            let weird: [(String, [String])] = [
                ("¿Cuánto es 0 ÷ 0 + la raíz cuadrada de un martes?", ["−7", "∞", "42"]),
                ("Resolvé: (manzanas × ∞) − √(−9) = ¿?", ["9", "nada", "λ"]),
                ("Si 8 ovejas cruzan un río al revés, ¿cuánto pesa el lunes?", ["13", "4,5", "azul"]),
                ("x² + y² = ¿hoy?   (x = ayer, y = mañana)", ["0", "−1", "999"])
            ]
            let w = weird[Int(arc4random_uniform(UInt32(weird.count)))]
            return (w.0, w.1, -1)
        }
        let lvl = min(n, 6)
        let range = UInt32(5 + lvl * 3)
        var a = Int(arc4random_uniform(range)) + 1
        var b = Int(arc4random_uniform(range)) + 1
        let kind = lvl <= 1 ? Int(arc4random_uniform(2)) : Int(arc4random_uniform(3))
        var q = ""
        var ans = 0
        switch kind {
        case 0:
            q = "\(a) + \(b) = ?"
            ans = a + b
        case 1:
            if b > a { swap(&a, &b) }
            q = "\(a) − \(b) = ?"
            ans = a - b
        default:
            a = Int(arc4random_uniform(UInt32(2 + lvl))) + 2
            b = Int(arc4random_uniform(8)) + 2
            q = "\(a) × \(b) = ?"
            ans = a * b
        }
        var opts = [ans]
        var tries = 0
        while opts.count < 3 && tries < 60 {
            tries += 1
            let off = Int(arc4random_uniform(7)) - 3
            let cand = ans + (off == 0 ? 4 : off)
            if cand >= 0 && !opts.contains(cand) { opts.append(cand) }
        }
        while opts.count < 3 { opts.append(ans + opts.count + 5) }
        opts.shuffle()
        let ci = opts.firstIndex(of: ans) ?? 0
        return (q, opts.map { String($0) }, ci)
    }

    // MARK: Geometría y movimiento
    private func forward2D() -> (Float, Float) {
        let v = orientWorld.act(SIMD3<Float>(0, 0, -1))
        let l = sqrt(v.x * v.x + v.z * v.z)
        if l < 0.01 { return (0, -1) }
        return (v.x / l, v.z / l)
    }

    private func wallAt(_ x: Float, _ z: Float) -> Bool {
        let cx = Int(floor(x / cell)), cy = Int(floor(z / cell))
        if cx < 0 || cy < 0 || cx >= GW || cy >= GH { return true }
        return !grid[cy][cx] || barCells.contains(cy * GW + cx)
    }

    private func collides(_ x: Float, _ z: Float, _ r: Float, player: Bool) -> Bool {
        let x0 = Int(floor((x - r) / cell)), x1 = Int(floor((x + r) / cell))
        let z0 = Int(floor((z - r) / cell)), z1 = Int(floor((z + r) / cell))
        for cy in z0...z1 {
            for cx in x0...x1 {
                if cx < 0 || cy < 0 || cx >= GW || cy >= GH || !grid[cy][cx] { return true }
                let i = cy * GW + cx
                if barCells.contains(i) { return true }
                if player && bullyCells.contains(i) { return true }
            }
        }
        return false
    }

    private func movePlayer(_ dx: Float, _ dz: Float) {
        if !collides(px + dx, pz, 0.35, player: true) { px += dx }
        if !collides(px, pz + dz, 0.35, player: true) { pz += dz }
    }

    private func moveActor(_ a: Actor, _ dx: Float, _ dz: Float) {
        if !collides(a.x + dx, a.z, 0.4, player: false) { a.x += dx }
        if !collides(a.x, a.z + dz, 0.4, player: false) { a.z += dz }
    }

    private func dst(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float) -> Float {
        let dx = ax - bx, dz = az - bz
        return sqrt(dx * dx + dz * dz)
    }

    private func los(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float) -> Bool {
        let dx = bx - ax, dz = bz - az
        let d = sqrt(dx * dx + dz * dz)
        let steps = max(1, Int(d / 0.6))
        if steps > 1 {
            for i in 1..<steps {
                let t = Float(i) / Float(steps)
                if wallAt(ax + dx * t, az + dz * t) { return false }
            }
        }
        return true
    }

    private func bfsNext(_ fx: Int, _ fy: Int, _ tx: Int, _ ty: Int) -> (Int, Int)? {
        if fx == tx && fy == ty { return nil }
        if tx < 0 || ty < 0 || tx >= GW || ty >= GH || fx < 0 || fy < 0 || fx >= GW || fy >= GH { return nil }
        var dd = [Int](repeating: -1, count: GW * GH)
        var q = [Int]()
        q.reserveCapacity(GW * GH)
        let start = ty * GW + tx
        let goal = fy * GW + fx
        dd[start] = 0
        q.append(start)
        var qi = 0
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while qi < q.count {
            let cur = q[qi]
            qi += 1
            if cur == goal { break }
            let cx = cur % GW, cy = cur / GW
            for (dx, dy) in dirs {
                let nx = cx + dx, ny = cy + dy
                if nx < 0 || ny < 0 || nx >= GW || ny >= GH { continue }
                let ni = ny * GW + nx
                if dd[ni] >= 0 || !grid[ny][nx] || barCells.contains(ni) { continue }
                dd[ni] = dd[cur] + 1
                q.append(ni)
            }
        }
        if dd[goal] < 0 { return nil }
        var best: (Int, Int)? = nil
        var bd = dd[goal]
        for (dx, dy) in dirs {
            let nx = fx + dx, ny = fy + dy
            if nx < 0 || ny < 0 || nx >= GW || ny >= GH { continue }
            let d = dd[ny * GW + nx]
            if d >= 0 && d < bd {
                bd = d
                best = (nx, ny)
            }
        }
        return best
    }

    private func stepActor(_ a: Actor, toX tx: Float, toZ tz: Float, speed: Float, dt: Float) {
        let ac = (Int(floor(a.x / cell)), Int(floor(a.z / cell)))
        let tc = (Int(floor(tx / cell)), Int(floor(tz / cell)))
        var gx = tx, gz = tz
        if ac.0 != tc.0 || ac.1 != tc.1 {
            a.pathTimer -= dt
            if a.nextCX < 0 || a.pathTimer <= 0 || (ac.0 == a.nextCX && ac.1 == a.nextCY) {
                if let n = bfsNext(ac.0, ac.1, tc.0, tc.1) {
                    a.nextCX = n.0
                    a.nextCY = n.1
                } else {
                    a.nextCX = -1
                }
                a.pathTimer = 0.25
            }
            if a.nextCX >= 0 {
                let c = cellCenter(a.nextCX, a.nextCY)
                gx = c.0
                gz = c.1
            }
        }
        var dx = gx - a.x, dz = gz - a.z
        let d = sqrt(dx * dx + dz * dz)
        if d > 0.001 { dx /= d; dz /= d }
        let step = min(speed * dt, d)
        moveActor(a, dx * step, dz * step)
    }

    private func patrol(_ a: Actor, _ wps: [(Float, Float)], _ speed: Float, _ dt: Float) {
        let t = wps[a.wp % wps.count]
        if dst(a.x, a.z, t.0, t.1) < 1.8 {
            a.wp = (a.wp + 1) % wps.count
            return
        }
        stepActor(a, toX: t.0, toZ: t.1, speed: speed, dt: dt)
    }

    // MARK: Bucle principal
    private func updateHead() {
        let yaw = simd_quatf(angle: spawnYaw, axis: SIMD3<Float>(0, 1, 0))
        orientWorld = yaw * headOrient
        head.simdOrientation = orientWorld
        head.position = SCNVector3(px, 1.6, pz)
    }

    func update(dt dtD: Double) {
        guard isActive else { return }
        let dt = Float(dtD)
        gameTime += dt
        updateHead()
        updatePointer()
        if phase == .playing { playUpdate(dt) }
        updateHint()
        refreshHUD(dt)
    }

    private func updatePointer() {
        guard panelVisible else {
            hoverID = nil
            progress = 0
            hovering = false
            return
        }
        let now = CACurrentMediaTime()
        var hit: String? = nil
        let b = leftView.bounds
        for h in leftView.hitTest(CGPoint(x: b.midX, y: b.midY), options: nil) {
            if h.node === panelNode {
                let lc = h.localCoordinates
                let p = CGPoint(x: (CGFloat(lc.x) + 0.8) / 1.6 * 1280, y: (0.45 - CGFloat(lc.y)) / 0.9 * 720)
                hit = panelButtons.first(where: { $0.rect.contains(p) })?.id
                break
            }
        }
        if hit != hoverID {
            hoverID = hit
            hoverStart = now
            locked = false
            panelDirty = true
        }
        hovering = hoverID != nil
        progress = 0
        if dwellEnabled, let id = hoverID, !locked, let btn = panelButtons.first(where: { $0.id == id }) {
            let e = now - hoverStart
            progress = CGFloat(min(1, e / btn.dwell))
            if e >= btn.dwell {
                locked = true
                progress = 0
                panelAction(id)
                return
            }
        }
        if panelDirty && now - lastPanelRender > 0.08 {
            panelDirty = false
            lastPanelRender = now
            panelNode.geometry?.firstMaterial?.diffuse.contents = renderPanel()
        }
    }

    private func playUpdate(_ dt: Float) {
        // Movimiento
        let f = forward2D()
        let rx = -f.1, rz = f.0
        var mx = f.0 * stickY + rx * stickX
        var mz = f.1 * stickY + rz * stickX
        let len = sqrt(mx * mx + mz * mz)
        if len > 1 { mx /= len; mz /= len }
        let moving = len > 0.1
        let frozen = ropeActive
        var running = false
        if runHeld && moving && !frozen && (stamina > 0 || infStamina > 0 || visitor) && !exhausted { running = true }
        if running {
            if infStamina <= 0 && !visitor {
                stamina -= 26 * dt
                if stamina <= 0 { stamina = 0; exhausted = true }
            }
        } else {
            stamina = min(100, stamina + (moving ? 10 : 18) * dt)
            if exhausted && stamina > 30 { exhausted = false }
        }
        infStamina = max(0, infStamina - dt)
        isRunning = running
        if !frozen {
            let speed: Float = running ? 4.8 : 2.6
            movePlayer(mx * speed * dt, mz * speed * dt)
        }
        // Empujón del robot
        if abs(pushVX) > 0.05 || abs(pushVZ) > 0.05 {
            movePlayer(pushVX * dt, pushVZ * dt)
            let decay = max(0, 1 - 4.5 * dt)
            pushVX *= decay
            pushVZ *= decay
        }
        head.position = SCNVector3(px, 1.6, pz)

        // Detención
        if inDetention {
            detentionTimer -= dt
            if detentionTimer <= 0 {
                inDetention = false
                barCells.removeAll()
                message("Podés salir de la detención", 3)
            } else {
                message("Detención: \(Int(ceil(detentionTimer))) s", 1.0)
            }
        }

        // Objetos
        updatePickups()

        // Personajes
        if !visitor {
            updateTeacher(teacher, dt)
            updatePrincipal(principal, dt)
            updateRobot(robot, dt)
            updateBully(bully, dt)
            updateGirl(girl, dt)
        }
        for a in [teacher!, principal!, robot!, girl!, bully!] {
            a.node.isHidden = visitor || (a === bully && !a.active)
            syncNode(a)
        }

        // Salida
        if exitsOpen && !visitor {
            if (pz < 3.4 && abs(px - 4) < 2.6) || (pz > 52.6 && abs(px - 76) < 2.6) {
                phase = .won
                sounds.play("win")
                showPanel()
            }
        }
    }

    private func updatePickups() {
        for p in pickups where !p.taken {
            let bob = 0.9 + 0.08 * sin(gameTime * 3 + p.x)
            switch p.kind {
            case .notebook:
                p.node.position = SCNVector3(p.x, bob - 0.5, p.z)
            case .coin:
                p.node.position = SCNVector3(p.x, bob - 0.5, p.z)
                if dst(px, pz, p.x, p.z) < 1.1 {
                    p.taken = true
                    p.node.isHidden = true
                    coins += 1
                    hudDirty = true
                    sounds.play("coin")
                }
            case .scissors:
                p.node.position = SCNVector3(p.x, bob - 0.5, p.z)
                if dst(px, pz, p.x, p.z) < 1.1 {
                    if let slot = inventory.firstIndex(where: { $0 == nil }) {
                        inventory[slot] = .scissors
                        p.taken = true
                        p.node.isHidden = true
                        hudDirty = true
                        sounds.play("coin")
                        message("Conseguiste tijeras", 2.5)
                    }
                }
            }
        }
    }

    // MARK: Personajes
    private func teacherSpeed() -> Float {
        let mult: Float = difficulty == 0 ? 0.8 : (difficulty == 2 ? 1.2 : 1.0)
        var s = (2.2 + 0.30 * Float(collected) + 0.45 * Float(wrongCount)) * mult
        if endgame { s *= 1.35 }
        return min(s, 7.2)
    }

    private func updateTeacher(_ a: Actor, _ dt: Float) {
        if a.pushLeft > 0 {
            let s = min(a.pushLeft, 12 * dt)
            moveActor(a, a.pushDX * s, a.pushDZ * s)
            a.pushLeft -= s
            return
        }
        if a.timer > 0 { a.timer -= dt; return }
        if collected == 0 { return }
        stepActor(a, toX: px, toZ: pz, speed: teacherSpeed(), dt: dt)
        let d = dst(a.x, a.z, px, pz)
        tickTimer -= dt
        if d < 22 && tickTimer <= 0 {
            sounds.play("tick")
            tickTimer = max(0.22, min(1.2, d / 18))
        }
        if d < 1.05 { caught() }
    }

    private func caught() {
        guard phase == .playing, !visitor else { return }
        phase = .caught
        sounds.play("lose")
        say("¡Te atrapé!")
        showPanel()
    }

    private func updatePrincipal(_ a: Actor, _ dt: Float) {
        if a.cooldown > 0 { a.cooldown -= dt }
        let d = dst(a.x, a.z, px, pz)
        if a.state == 1 {
            stepActor(a, toX: px, toZ: pz, speed: 4.6, dt: dt)
            if los(a.x, a.z, px, pz) { a.timer = 0 } else { a.timer += dt }
            if d < 1.3 && !inDetention {
                sendToDetention(a)
            } else if a.timer > 4 || inDetention {
                a.state = 0
            }
            return
        }
        patrol(a, principalWP, 2.0, dt)
        if a.cooldown <= 0 && isRunning && d < 11 && !inDetention && los(a.x, a.z, px, pz) {
            a.state = 1
            a.timer = 0
            say("¡Eh! ¡No corras en los pasillos!")
            message("¡El Director te vio correr!", 2.5)
        }
    }

    private func sendToDetention(_ a: Actor) {
        inDetention = true
        detentionTimer = 15
        a.state = 0
        a.cooldown = 25
        px = 68
        pz = 16
        pushVX = 0
        pushVZ = 0
        ropeActive = false
        barCells.insert(12 * GW + 34)
        barCells.insert(12 * GW + 35)
        sounds.play("alarm")
        say("¡Detención por correr!")
        message("Detención: 15 s", 3)
    }

    private func updateRobot(_ a: Actor, _ dt: Float) {
        if a.cooldown > 0 { a.cooldown -= dt }
        let d = dst(a.x, a.z, px, pz)
        if a.state == 0 {
            patrol(a, robotWP, 1.7, dt)
            if a.cooldown <= 0 && d < 12 && !inDetention && los(a.x, a.z, px, pz) {
                a.state = 1
                a.timer = 0
                sounds.play("alarm")
                message("¡El Barredor te vio!", 2)
            }
        } else {
            stepActor(a, toX: px, toZ: pz, speed: 5.6, dt: dt)
            a.timer += dt
            if d < 1.2 {
                var dx = px - a.x, dz = pz - a.z
                let l = max(0.01, sqrt(dx * dx + dz * dz))
                dx /= l
                dz /= l
                pushVX = dx * 20
                pushVZ = dz * 20
                a.state = 0
                a.cooldown = 9
                sounds.play("push")
                message("¡El Barredor te empujó!", 2)
            } else if a.timer > 6 {
                a.state = 0
                a.cooldown = 6
            }
        }
    }

    private func activateBully() {
        let post = bullyPosts[bully.post % bullyPosts.count]
        bully.x = post.0
        bully.z = post.1
        bully.active = true
        bully.timer = 0
        bullyCells.removeAll()
        for c in post.2 { bullyCells.insert(c.1 * GW + c.0) }
        bully.node.isHidden = visitor
    }

    private func deactivateBully(_ cooldown: Float) {
        bully.active = false
        bully.cooldown = cooldown
        bully.node.isHidden = true
        bullyCells.removeAll()
        bully.post += 1
    }

    private func updateBully(_ a: Actor, _ dt: Float) {
        if !a.active {
            a.cooldown -= dt
            if a.cooldown <= 0 { activateBully() }
            return
        }
        let d = dst(a.x, a.z, px, pz)
        if d < 2.6 {
            let have = inventory.indices.filter { inventory[$0] != nil }
            if !have.isEmpty {
                let slot = have[Int(arc4random_uniform(UInt32(have.count)))]
                let name = itemName(inventory[slot])
                inventory[slot] = nil
                hudDirty = true
                sounds.play("push")
                say("¡Dame eso!")
                message("El Matón te robó: \(name)", 3)
                deactivateBully(50)
            } else {
                a.timer += dt
                message("El Matón no te deja pasar. Traé algo...", 1.0)
                if a.timer > 8 { deactivateBully(25) }
            }
        } else {
            a.timer = 0
        }
    }

    private func itemName(_ k: ItemKind?) -> String {
        guard let k = k else { return "nada" }
        switch k {
        case .soda: return "una soda"
        case .chocolate: return "un chocolate"
        case .scissors: return "las tijeras"
        }
    }

    private func updateGirl(_ a: Actor, _ dt: Float) {
        if a.cooldown > 0 { a.cooldown -= dt }
        if ropeActive {
            updateRope(dt)
            return
        }
        let d = dst(a.x, a.z, px, pz)
        if a.cooldown <= 0 && d < 3.4 && !inDetention {
            ropeActive = true
            ropeTime = 0
            ropeCycle = 0
            ropeCount = 0
            ropeJumped = false
            ropeFailed = false
            sounds.play("alarm")
            say("¡Saltá la cuerda conmigo!")
        }
    }

    private func updateRope(_ dt: Float) {
        ropeTime += dt
        let cycle: Float = 1.3
        let t = ropeTime.truncatingRemainder(dividingBy: cycle)
        ropeWindow = t > cycle - 0.5
        let cyc = Int(ropeTime / cycle)
        if cyc > ropeCycle {
            ropeCycle = cyc
            if ropeJumped && !ropeFailed {
                ropeCount += 1
                sounds.play("jump")
            } else {
                ropeCount = 0
                sounds.play("bad")
            }
            ropeJumped = false
            ropeFailed = false
            if ropeCount >= 5 { endRope(cut: false) }
        }
    }

    private func endRope(cut: Bool) {
        ropeActive = false
        girl.cooldown = cut ? 45 : 50
        girl.post += 1
        let p = girlPosts[girl.post % girlPosts.count]
        girl.x = p.0
        girl.z = p.1
        message(cut ? "¡Cortaste la cuerda!" : "¡Bien saltado!", 2.5)
        sounds.play("ok")
    }

    // MARK: Interacción
    private func target() -> Target? {
        let f = forward2D()
        var best: Target? = nil
        var bd: Float = 99
        func consider(_ x: Float, _ z: Float, _ t: Target) {
            let dx = x - px, dz = z - pz
            let d = sqrt(dx * dx + dz * dz)
            if d < 2.8 && d > 0.01 && (dx * f.0 + dz * f.1) / d > 0.83 && d < bd {
                bd = d
                best = t
            }
        }
        for p in pickups where p.kind == .notebook && !p.taken { consider(p.x, p.z, .notebook(p)) }
        for m in machines { consider(m.x, m.z, .machine(m)) }
        return best
    }

    private func interactA() {
        if ropeActive {
            if ropeWindow && !ropeJumped { ropeJumped = true } else { ropeFailed = true }
            return
        }
        guard let t = target() else { return }
        switch t {
        case .notebook(let p):
            openNotebook(p)
        case .machine(let m):
            let cost = m.choco ? 2 : 3
            if coins < cost {
                message("Te faltan monedas (cuesta \(cost))", 2)
                sounds.play("bad")
                return
            }
            guard let slot = inventory.firstIndex(where: { $0 == nil }) else {
                message("Inventario lleno", 2)
                return
            }
            coins -= cost
            inventory[slot] = m.choco ? .chocolate : .soda
            hudDirty = true
            sounds.play("coin")
            message(m.choco ? "Compraste un chocolate" : "Compraste una soda", 2)
        }
    }

    private func useItem() {
        guard phase == .playing, let item = inventory[selected] else { return }
        switch item {
        case .soda:
            inventory[selected] = nil
            hudDirty = true
            let dx = teacher.x - px, dz = teacher.z - pz
            let d = max(0.01, sqrt(dx * dx + dz * dz))
            let f = forward2D()
            if !visitor && d < 9 && (dx * f.0 + dz * f.1) / d > 0.8 {
                teacher.pushLeft = 9
                teacher.pushDX = dx / d
                teacher.pushDZ = dz / d
                teacher.timer = 4
                sounds.play("push")
                message("¡Soda directa! El Profe salió volando", 3)
            } else {
                message("¡Fallaste! La soda se perdió", 2)
                sounds.play("bad")
            }
        case .chocolate:
            inventory[selected] = nil
            hudDirty = true
            stamina = 100
            exhausted = false
            infStamina = 12
            sounds.play("ok")
            message("¡Energía a tope por 12 s!", 3)
        case .scissors:
            if ropeActive {
                inventory[selected] = nil
                hudDirty = true
                endRope(cut: true)
            } else {
                message("Las tijeras sirven para cortar la cuerda", 2)
            }
        }
    }

    // MARK: HUD y avisos
    private func updateHint() {
        var h: String? = nil
        if phase == .playing {
            if ropeActive {
                var s = "Cuerda \(ropeCount)/5  " + (ropeWindow ? "¡¡SALTÁ (A)!!" : "esperá...")
                if inventory.contains(where: { $0 == .scissors }) { s += "  (RT: cortar)" }
                h = s
            } else if gameTime < messageUntil {
                h = messageText
            } else if let t = target() {
                switch t {
                case .notebook: h = "A: abrir libreta"
                case .machine(let m): h = "A: comprar " + (m.choco ? "chocolate (2 monedas)" : "soda (3 monedas)")
                }
            }
            if h == nil && visitor { h = "Modo visitante" }
        } else if gameTime < messageUntil {
            h = messageText
        }
        hintText = h
    }

    private func labelImage(_ text: String, _ w: CGFloat, _ h: CGFloat, _ size: CGFloat) -> UIImage {
        return gImage(w, h) { c in
            fillR(c, CGRect(x: 0, y: 0, width: w, height: h), UIColor(white: 0, alpha: 0.55))
            gText(text, CGRect(x: 0, y: 0, width: w, height: h), size, .white, bold: true)
        }
    }

    private func refreshHUD(_ dt: Float) {
        if hudDirty {
            hudDirty = false
            hudTop.geometry?.firstMaterial?.diffuse.contents =
                labelImage("Libretas \(collected)/7     Monedas \(coins)", 640, 100, 40)
            let sel = selected
            let inv = inventory
            let icons = itemImages
            hudInv.geometry?.firstMaterial?.diffuse.contents = gImage(390, 120) { c in
                for i in 0..<3 {
                    let r = CGRect(x: CGFloat(i) * 130 + 5, y: 5, width: 110, height: 110)
                    fillR(c, r, UIColor(white: 0, alpha: 0.55))
                    c.setStrokeColor((i == sel ? rgb(255, 220, 60) : UIColor(white: 0.5, alpha: 1)).cgColor)
                    c.setLineWidth(i == sel ? 6 : 2)
                    c.stroke(r)
                    if let k = inv[i] {
                        let idx = (k == .soda) ? 0 : (k == .chocolate ? 1 : 2)
                        icons[idx].draw(in: r.insetBy(dx: 8, dy: 8))
                    }
                }
            }
        }
        let ratio = max(0, min(1, stamina / 100))
        hudBarFill.scale = SCNVector3(ratio, 1, 1)
        hudBarFill.position = SCNVector3(-0.29 * (1 - ratio), -0.45, -1.0)
    }
}
