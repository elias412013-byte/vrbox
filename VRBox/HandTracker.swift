import Foundation
import CoreVideo
import CoreGraphics
import QuartzCore

struct HandResult {
    var found = false
    var tip = CGPoint.zero      // punta del dedo, normalizada 0...1 (x der, y abajo)
    var palm = CGPoint.zero     // centro de la mano, normalizado
    var area = 0
    var imgW = 1280
    var imgH = 720
    var maskImage: CGImage? = nil
    var centerCb = 0
    var centerCr = 0
    var silhouetteImage: CGImage? = nil
}

/// Detección de mano por color de piel (YCbCr) sobre una grilla pequeña.
/// Funciona en iOS 12 (Vision de manos necesita iOS 14).
final class HandTracker {
    static let gw = 80
    static let gh = 45
    // Región central (en celdas) que se muestrea al calibrar
    static let calX0 = 36
    static let calX1 = 44
    static let calY0 = 19
    static let calY1 = 26

    static var calibRect: CGRect {
        let w = CGFloat(gw), h = CGFloat(gh)
        return CGRect(x: CGFloat(calX0) / w, y: CGFloat(calY0) / h,
                      width: CGFloat(calX1 - calX0) / w, height: CGFloat(calY1 - calY0) / h)
    }

    var wantsMask = true
    var onCalibrated: ((Int, Int, Int, Int) -> Void)?

    private let lock = NSLock()
    private var cbMin = 77, cbMax = 125, crMin = 138, crMax = 175
    private var calibrating = false
    private var calibEnd: CFTimeInterval = 0
    private var sumCb = 0.0, sumCr = 0.0, nCal = 0.0

    func setRange(cbMin: Int, cbMax: Int, crMin: Int, crMax: Int) {
        lock.lock()
        self.cbMin = cbMin; self.cbMax = cbMax; self.crMin = crMin; self.crMax = crMax
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

        let gw = HandTracker.gw, gh = HandTracker.gh
        let now = CACurrentMediaTime()

        lock.lock()
        let cb0 = cbMin, cb1 = cbMax, cr0 = crMin, cr1 = crMax
        let sampling = calibrating && now >= calibEnd - 1.5
        lock.unlock()

        var mask = [UInt8](repeating: 0, count: gw * gh)
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
                if gx >= HandTracker.calX0 && gx < HandTracker.calX1
                    && gy >= HandTracker.calY0 && gy < HandTracker.calY1 {
                    sCb += Double(cb); sCr += Double(cr); sN += 1
                }
                let yy = Int(yPtr[py * yStride + px])
                if yy > 30 && cb >= cb0 && cb <= cb1 && cr >= cr0 && cr <= cr1 && (cr - cb) >= 10 {
                    mask[gy * gw + gx] = 1
                }
            }
        }

        // Calibración
        var calibDone: (Int, Int, Int, Int)? = nil
        lock.lock()
        if calibrating {
            if sampling { sumCb += sCb; sumCr += sCr; nCal += sN }
            if now >= calibEnd {
                if nCal > 0 {
                    let mCb = Int(sumCb / nCal), mCr = Int(sumCr / nCal)
                    cbMin = mCb - 16; cbMax = mCb + 16
                    crMin = mCr - 18; crMax = mCr + 18
                    calibDone = (cbMin, cbMax, crMin, crMax)
                }
                calibrating = false
            }
        }
        lock.unlock()
        if let d = calibDone { onCalibrated?(d.0, d.1, d.2, d.3) }

        // Limpieza de ruido: quitar celdas sueltas
        var clean = [UInt8](repeating: 0, count: gw * gh)
        if gw > 2 && gh > 2 {
            for y in 1..<(gh - 1) {
                for x in 1..<(gw - 1) {
                    let i = y * gw + x
                    if mask[i] == 0 { continue }
                    var c = 0
                    c += Int(mask[i - 1]) + Int(mask[i + 1])
                    c += Int(mask[i - gw]) + Int(mask[i + gw])
                    c += Int(mask[i - gw - 1]) + Int(mask[i - gw + 1])
                    c += Int(mask[i + gw - 1]) + Int(mask[i + gw + 1])
                    if c >= 4 { clean[i] = 1 }
                }
            }
        }
        mask = clean

        // Componente conectado más grande
        let n = gw * gh
        var visited = [Bool](repeating: false, count: n)
        var best: [Int] = []
        var bestScore = -1
        var maxAny = 0
        let minArea = 20
        let maxArea = (n * 35) / 100
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
                // El brazo entra desde abajo: damos prioridad a lo que toca el borde inferior
                var touchesBottom = false
                for i in comp where i / gw >= gh - 2 { touchesBottom = true; break }
                let score = comp.count + (touchesBottom ? 400 : 0)
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
        if wantsMask { result.maskImage = makeImage(mask, r: 0, g: 255, b: 120, a: 255) }

        // Ni muy chico (ruido) ni enorme (pared / fondo del color de la piel)
        if best.count >= minArea {
            var sx = 0, sy = 0
            for i in best { sx += i % gw; sy += i / gw }
            let mx = Double(sx) / Double(best.count)
            let my = Double(sy) / Double(best.count)
            // Punta: la celda más lejana del centro, entre las que están arriba del centro
            // (el antebrazo entra desde abajo)
            var bestD = -1.0
            var tx = mx, ty = my
            for i in best {
                let x = Double(i % gw), y = Double(i / gw)
                if y <= my {
                    let d = (x - mx) * (x - mx) + (y - my) * (y - my)
                    if d > bestD { bestD = d; tx = x; ty = y }
                }
            }
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
            result.silhouetteImage = makeImage(sil, r: 17, g: 20, b: 30, a: 215)
            result.found = true
            result.tip = CGPoint(x: (tx + 0.5) / Double(gw), y: (ty + 0.5) / Double(gh))
            result.palm = CGPoint(x: (mx + 0.5) / Double(gw), y: (my + 0.5) / Double(gh))
        }
        return result
    }

    private func makeImage(_ mask: [UInt8], r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> CGImage? {
        let w = HandTracker.gw, h = HandTracker.gh
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
