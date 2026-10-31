import Foundation
import CoreVideo
import CoreGraphics
import QuartzCore

struct HandResult {
    var found = false
    var tip = CGPoint.zero      // punto a seguir, normalizado 0...1 (x der, y abajo)
    var palm = CGPoint.zero     // centro de la mancha, normalizado
    var area = 0
    var imgW = 1280
    var imgH = 720
    var maskImage: CGImage? = nil
    var silhouetteImage: CGImage? = nil
    var centerCb = 0
    var centerCr = 0
}

/// Seguimiento por color (funciona en iOS 12).
/// - Modo marcador: sigue una mancha de color vivo (la punta de color de un tubo, una fibra, etc.).
///   Usa una grilla fina (160x90) para poder seguir cosas delgadas.
/// - Modo mano: detecta piel con una grilla de 80x45.
final class HandTracker {
    var markerMode = true
    var wantsMask = true
    /// (esMarcador, cbMin, cbMax, crMin, crMax)
    var onCalibrated: ((Bool, Int, Int, Int, Int) -> Void)?
    var onCalibrationFailed: (() -> Void)?

    private let lock = NSLock()
    private var skin = (cbMin: 77, cbMax: 125, crMin: 138, crMax: 175)
    // Por defecto: azul. Lo ideal es calibrar con el color real del marcador.
    private var mark = (cbMin: 145, cbMax: 205, crMin: 70, crMax: 125)
    private var calibrating = false
    private var calibEnd: CFTimeInterval = 0
    private var sumCb = 0.0, sumCr = 0.0, nCal = 0.0

    func grid(marker: Bool) -> (w: Int, h: Int) {
        return marker ? (w: 160, h: 90) : (w: 80, h: 45)
    }

    /// Región central (en celdas de la grilla del modo) que se muestrea al calibrar
    func calibCells(marker: Bool) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        if marker { return (x0: 68, x1: 92, y0: 33, y1: 57) }
        return (x0: 36, x1: 44, y0: 19, y1: 26)
    }

    func calibRect(marker: Bool) -> CGRect {
        let c = calibCells(marker: marker)
        let g = grid(marker: marker)
        let w = CGFloat(g.w), h = CGFloat(g.h)
        return CGRect(x: CGFloat(c.x0) / w, y: CGFloat(c.y0) / h,
                      width: CGFloat(c.x1 - c.x0) / w, height: CGFloat(c.y1 - c.y0) / h)
    }

    func setRange(marker: Bool, cbMin: Int, cbMax: Int, crMin: Int, crMax: Int) {
        lock.lock()
        if marker {
            mark = (cbMin, cbMax, crMin, crMax)
        } else {
            skin = (cbMin, cbMax, crMin, crMax)
        }
        lock.unlock()
    }

    func beginCalibration(duration: CFTimeInterval) {
        lock.lock()
        calibrating = true
        calibEnd = CACurrentMediaTime() + duration
        sumCb = 0; sumCr = 0; nCal = 0
        lock.unlock()
    }

    var calibrationRemaining: CFTimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return calibrating ? max(0, calibEnd - CACurrentMediaTime()) : 0
    }

    func process(_ pb: CVPixelBuffer) -> HandResult? {
        guard CVPixelBufferGetPlaneCount(pb) >= 2 else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return nil }

        let w = CVPixelBufferGetWidthOfPlane(pb, 0)
        let h = CVPixelBufferGetHeightOfPlane(pb, 0)
        let cw = CVPixelBufferGetWidthOfPlane(pb, 1)
        let ch = CVPixelBufferGetHeightOfPlane(pb, 1)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
        let cPtr = cBase.assumingMemoryBound(to: UInt8.self)

        let marker = markerMode
        let g = grid(marker: marker)
        let gw = g.w, gh = g.h
        let n = gw * gh
        let now = CACurrentMediaTime()
        let cc = calibCells(marker: marker)

        lock.lock()
        let r = marker ? mark : skin
        let sampling = calibrating && now >= calibEnd - 1.5
        lock.unlock()

        var mask = [UInt8](repeating: 0, count: n)
        var sCb = 0.0, sCr = 0.0, sN = 0.0

        for gy in 0..<gh {
            let py = (gy * h + h / 2) / gh
            let cy = min(ch - 1, py / 2)
            for gx in 0..<gw {
                let px = (gx * w + w / 2) / gw
                let cx = min(cw - 1, px / 2)
                let ci = cy * cStride + cx * 2
                let cb = Int(cPtr[ci])
                let cr = Int(cPtr[ci + 1])
                let dcb = cb - 128, dcr = cr - 128
                let chroma2 = dcb * dcb + dcr * dcr

                if gx >= cc.x0 && gx < cc.x1 && gy >= cc.y0 && gy < cc.y1 {
                    // En modo marcador solo cuentan los colores vivos (ignora el fondo gris)
                    if !marker || chroma2 >= 900 {
                        sCb += Double(cb); sCr += Double(cr); sN += 1
                    }
                }

                let yy = Int(yPtr[py * yStride + px])
                var hit = false
                if yy > 30 && cb >= r.cbMin && cb <= r.cbMax && cr >= r.crMin && cr <= r.crMax {
                    if marker {
                        hit = chroma2 >= 625   // color vivo: lejos del gris (128,128)
                    } else {
                        hit = (cr - cb) >= 10
                    }
                }
                if hit { mask[gy * gw + gx] = 1 }
            }
        }

        // Calibración
        var calibDone: (Bool, Int, Int, Int, Int)? = nil
        var calibFailed = false
        lock.lock()
        if calibrating {
            if sampling { sumCb += sCb; sumCr += sCr; nCal += sN }
            if now >= calibEnd {
                if nCal >= 8 {
                    let mCb = Int(sumCb / nCal), mCr = Int(sumCr / nCal)
                    if marker {
                        mark = (mCb - 18, mCb + 18, mCr - 18, mCr + 18)
                        calibDone = (true, mark.cbMin, mark.cbMax, mark.crMin, mark.crMax)
                    } else {
                        skin = (mCb - 16, mCb + 16, mCr - 18, mCr + 18)
                        calibDone = (false, skin.cbMin, skin.cbMax, skin.crMin, skin.crMax)
                    }
                } else {
                    calibFailed = true
                }
                calibrating = false
            }
        }
        lock.unlock()
        if let d = calibDone { onCalibrated?(d.0, d.1, d.2, d.3, d.4) }
        if calibFailed { onCalibrationFailed?() }

        // Limpieza de ruido: quitar celdas sueltas
        let need = marker ? 2 : 4
        var clean = [UInt8](repeating: 0, count: n)
        for y in 1..<(gh - 1) {
            for x in 1..<(gw - 1) {
                let i = y * gw + x
                if mask[i] == 0 { continue }
                var c = 0
                c += Int(mask[i - 1]) + Int(mask[i + 1])
                c += Int(mask[i - gw]) + Int(mask[i + gw])
                c += Int(mask[i - gw - 1]) + Int(mask[i - gw + 1])
                c += Int(mask[i + gw - 1]) + Int(mask[i + gw + 1])
                if c >= need { clean[i] = 1 }
            }
        }
        mask = clean

        // Mejor mancha válida
        var visited = [Bool](repeating: false, count: n)
        var best: [Int] = []
        var bestScore = -1
        var maxAny = 0
        let minArea = marker ? 10 : 20
        let maxArea = marker ? (n * 10) / 100 : (n * 35) / 100
        var stack: [Int] = []
        for start in 0..<n where mask[start] == 1 && !visited[start] {
            var comp: [Int] = []
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let cur = stack.popLast() {
                comp.append(cur)
                let x = cur % gw
                let y = cur / gw
                if x > 0 { let nb = cur - 1; if mask[nb] == 1 && !visited[nb] { visited[nb] = true; stack.append(nb) } }
                if x < gw - 1 { let nb = cur + 1; if mask[nb] == 1 && !visited[nb] { visited[nb] = true; stack.append(nb) } }
                if y > 0 { let nb = cur - gw; if mask[nb] == 1 && !visited[nb] { visited[nb] = true; stack.append(nb) } }
                if y < gh - 1 { let nb = cur + gw; if mask[nb] == 1 && !visited[nb] { visited[nb] = true; stack.append(nb) } }
            }
            if comp.count > maxAny { maxAny = comp.count }
            if comp.count >= minArea && comp.count <= maxArea {
                var score = comp.count
                if !marker {
                    // El brazo entra desde abajo: prioridad a lo que toca el borde inferior
                    var touchesBottom = false
                    for i in comp where i / gw >= gh - 2 { touchesBottom = true; break }
                    if touchesBottom { score += 400 }
                }
                if score > bestScore { bestScore = score; best = comp }
            }
        }

        var result = HandResult()
        result.imgW = w
        result.imgH = h
        result.area = best.isEmpty ? maxAny : best.count
        if sN > 0 {
            result.centerCb = Int(sCb / sN)
            result.centerCr = Int(sCr / sN)
        }
        if wantsMask { result.maskImage = makeImage(mask, w: gw, h: gh, r: 0, g: 255, b: 120, a: 255) }

        if best.count >= minArea {
            var sx = 0, sy = 0
            var minY = gh, maxY = 0
            for i in best {
                let x = i % gw, y = i / gw
                sx += x; sy += y
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
            let mx = Double(sx) / Double(best.count)
            let my = Double(sy) / Double(best.count)
            result.palm = CGPoint(x: (mx + 0.5) / Double(gw), y: (my + 0.5) / Double(gh))

            if marker {
                // Cursor = el extremo de arriba del marcador (la punta de la fibra / del tubo)
                let band = minY + max(1, (maxY - minY) / 4)
                var tsx = 0, tsy = 0, tn = 0
                for i in best {
                    let y = i / gw
                    if y <= band { tsx += i % gw; tsy += y; tn += 1 }
                }
                if tn > 0 {
                    result.tip = CGPoint(x: (Double(tsx) / Double(tn) + 0.5) / Double(gw),
                                         y: (Double(tsy) / Double(tn) + 0.5) / Double(gh))
                } else {
                    result.tip = result.palm
                }
            } else {
                // Mano: punta = celda más lejana del centro entre las que están arriba del centro
                var bestD = -1.0
                var tx = mx, ty = my
                for i in best {
                    let x = Double(i % gw), y = Double(i / gw)
                    if y <= my {
                        let d = (x - mx) * (x - mx) + (y - my) * (y - my)
                        if d > bestD { bestD = d; tx = x; ty = y }
                    }
                }
                result.tip = CGPoint(x: (tx + 0.5) / Double(gw), y: (ty + 0.5) / Double(gh))

                var sil = [UInt8](repeating: 0, count: n)
                for i in best {
                    let x = i % gw, y = i / gw
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0 && nx < gw && ny >= 0 && ny < gh { sil[ny * gw + nx] = 1 }
                        }
                    }
                }
                result.silhouetteImage = makeImage(sil, w: gw, h: gh, r: 17, g: 20, b: 30, a: 215)
            }
            result.found = true
        }
        return result
    }

    private func makeImage(_ mask: [UInt8], w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) where mask[i] == 1 {
            rgba[i * 4] = r
            rgba[i * 4 + 1] = g
            rgba[i * 4 + 2] = b
            rgba[i * 4 + 3] = a
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
