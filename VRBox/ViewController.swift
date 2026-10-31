import UIKit
import AVFoundation
import CoreMedia
import CoreMotion
import SceneKit
import simd

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: Cámara
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let leftLayer = AVSampleBufferDisplayLayer()
    private let rightLayer = AVSampleBufferDisplayLayer()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let frameQueue = DispatchQueue(label: "camera.frames")

    // MARK: Escena 3D
    private let scene = SCNScene()
    private let headNode = SCNNode()
    private let leftCam = SCNNode()
    private let rightCam = SCNNode()
    private let leftScn = SCNView()
    private let rightScn = SCNView()
    private let windowMaterial = SCNMaterial()
    private let winW: Float = 1.6
    private let winH: Float = 0.9
    private let winDist: Float = 1.5
    private let texW: CGFloat = 1280
    private let texH: CGFloat = 720

    // MARK: Movimiento (3DoF)
    private let motion = CMMotionManager()
    private var yawFix = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var needsRecenter = true

    // MARK: Interfaz
    private struct Btn { let id: Int; let title: String; let rect: CGRect }
    private var currentApp: String? = nil
    private var hoverID: Int? = nil
    private var hoverStart: CFTimeInterval = 0
    private var selectionLocked = false
    private let dwellTime: CFTimeInterval = 1.0
    private var leftReticle = CALayer()
    private var rightReticle = CALayer()
    private var leftRing = CAShapeLayer()
    private var rightRing = CAShapeLayer()

    override var prefersStatusBarHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .landscape }
    override var shouldAutorotate: Bool { return true }

    // MARK: Ciclo de vida
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Cámara de fondo (passthrough)
        for l in [leftLayer, rightLayer] {
            l.videoGravity = .resizeAspectFill
            l.backgroundColor = UIColor.black.cgColor
            l.masksToBounds = true
            view.layer.addSublayer(l)
        }

        setupScene()

        for (v, cam) in [(leftScn, leftCam), (rightScn, rightCam)] {
            v.scene = scene
            v.pointOfView = cam
            v.backgroundColor = .clear
            v.isOpaque = false
            v.antialiasingMode = .none
            v.preferredFramesPerSecond = 60
            v.rendersContinuously = true
            v.isUserInteractionEnabled = false
            view.addSubview(v)
        }

        // Mira (círculo que se llena) en cada ojo
        (leftReticle, leftRing) = makeReticle()
        (rightReticle, rightRing) = makeReticle()
        view.layer.addSublayer(leftReticle)
        view.layer.addSublayer(rightReticle)

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(recenter)))

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { DispatchQueue.main.async { self.setupCamera() } }
            }
        default:
            break
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startMotion()
        // Recentrado automático una vez, cuando ya te pusiste el visor
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.needsRecenter = true
        }
    }

    @objc private func recenter() { needsRecenter = true }

    // MARK: Escena
    private func setupScene() {
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(headNode)

        for (cam, x) in [(leftCam, Float(-0.032)), (rightCam, Float(0.032))] {
            let camera = SCNCamera()
            camera.zNear = 0.05
            camera.zFar = 50
            camera.fieldOfView = 80
            cam.camera = camera
            cam.position = SCNVector3(x, 0, 0)
            headNode.addChildNode(cam)
        }

        let plane = SCNPlane(width: CGFloat(winW), height: CGFloat(winH))
        windowMaterial.lightingModel = .constant
        windowMaterial.diffuse.contents = renderWindow()
        plane.materials = [windowMaterial]
        let windowNode = SCNNode(geometry: plane)
        windowNode.position = SCNVector3(0, 0, -winDist)
        scene.rootNode.addChildNode(windowNode)
    }

    // MARK: Giroscopio
    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] m, _ in
            guard let m = m else { return }
            self?.handleMotion(m)
        }
    }

    private func handleMotion(_ m: CMDeviceMotion) {
        let a = m.attitude.quaternion
        let q = simd_quatf(ix: Float(a.x), iy: Float(a.y), iz: Float(a.z), r: Float(a.w))
        let landscapeRight = UIApplication.shared.statusBarOrientation != .landscapeLeft
        let c = simd_quatf(angle: landscapeRight ? -Float.pi / 2 : Float.pi / 2,
                           axis: SIMD3<Float>(0, 0, 1))
        let w = simd_quatf(angle: -Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let head = w * q * c

        if needsRecenter {
            let f = head.act(SIMD3<Float>(0, 0, -1))
            let yaw = atan2(-f.x, -f.z)
            yawFix = simd_quatf(angle: -yaw, axis: SIMD3<Float>(0, 1, 0))
            needsRecenter = false
        }

        let final = yawFix * head
        headNode.simdOrientation = final
        updateGaze(forward: final.act(SIMD3<Float>(0, 0, -1)))
    }

    // MARK: Selección con la mirada
    private func updateGaze(forward f: SIMD3<Float>) {
        var hit: Int? = nil
        if f.z < -0.05 {
            let t = winDist / -f.z
            let u = (f.x * t + winW / 2) / winW
            let v = (winH / 2 - f.y * t) / winH
            if u >= 0 && u <= 1 && v >= 0 && v <= 1 {
                let p = CGPoint(x: CGFloat(u) * texW, y: CGFloat(v) * texH)
                hit = buttons().first(where: { $0.rect.contains(p) })?.id
            }
        }

        let now = CACurrentMediaTime()
        if hit != hoverID {
            hoverID = hit
            hoverStart = now
            selectionLocked = false
            windowMaterial.diffuse.contents = renderWindow()
        }

        var progress: CGFloat = 0
        if let id = hoverID, !selectionLocked {
            progress = CGFloat(min(1, (now - hoverStart) / dwellTime))
            if progress >= 1 {
                selectionLocked = true
                progress = 0
                select(id)
            }
        }
        setProgress(progress)
    }

    private func select(_ id: Int) {
        if id == 100 {
            currentApp = nil
        } else {
            currentApp = buttons().first(where: { $0.id == id })?.title
        }
        hoverID = nil
        hoverStart = CACurrentMediaTime()
        selectionLocked = false
        windowMaterial.diffuse.contents = renderWindow()
    }

    // MARK: Pantalla flotante (textura)
    private func buttons() -> [Btn] {
        if currentApp == nil {
            return [
                Btn(id: 0, title: "Navegador", rect: CGRect(x: 240, y: 190, width: 800, height: 100)),
                Btn(id: 1, title: "Galería", rect: CGRect(x: 240, y: 310, width: 800, height: 100)),
                Btn(id: 2, title: "Ajustes", rect: CGRect(x: 240, y: 430, width: 800, height: 100))
            ]
        } else {
            return [Btn(id: 100, title: "Volver al menú", rect: CGRect(x: 240, y: 560, width: 800, height: 100))]
        }
    }

    private func renderWindow() -> UIImage {
        let size = CGSize(width: texW, height: texH)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let hovered = hoverID
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            UIColor(white: 0.5, alpha: 1).setStroke()
            let border = UIBezierPath(rect: CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8))
            border.lineWidth = 4
            border.stroke()

            if let app = self.currentApp {
                self.drawText(app, in: CGRect(x: 0, y: 40, width: size.width, height: 120), size: 72, color: .white, bold: true)
                self.drawText("Aquí irá la app (etapa 2)", in: CGRect(x: 0, y: 280, width: size.width, height: 100), size: 48, color: UIColor(white: 0.7, alpha: 1), bold: false)
            } else {
                self.drawText("VRBox", in: CGRect(x: 0, y: 40, width: size.width, height: 120), size: 80, color: .white, bold: true)
                self.drawText("Mirá un botón 1 segundo para elegirlo", in: CGRect(x: 0, y: 580, width: size.width, height: 80), size: 38, color: UIColor(white: 0.6, alpha: 1), bold: false)
            }

            for b in self.buttons() {
                let fill = (b.id == hovered) ? UIColor(white: 0.40, alpha: 1) : UIColor(white: 0.18, alpha: 1)
                fill.setFill()
                UIBezierPath(roundedRect: b.rect, cornerRadius: 24).fill()
                self.drawText(b.title, in: b.rect, size: 52, color: .white, bold: false)
            }
        }
    }

    private func drawText(_ text: String, in rect: CGRect, size: CGFloat, color: UIColor, bold: Bool) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let h = font.lineHeight
        let r = CGRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h)
        (text as NSString).draw(in: r, withAttributes: attrs)
    }

    // MARK: Mira (círculo)
    private func makeReticle() -> (CALayer, CAShapeLayer) {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)

        let circle = UIBezierPath(arcCenter: CGPoint(x: 20, y: 20), radius: 14,
                                  startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath

        let track = CAShapeLayer()
        track.frame = container.bounds
        track.path = circle
        track.fillColor = nil
        track.strokeColor = UIColor(white: 1, alpha: 0.35).cgColor
        track.lineWidth = 3
        container.addSublayer(track)

        let ring = CAShapeLayer()
        ring.frame = container.bounds
        ring.path = circle
        ring.fillColor = nil
        ring.strokeColor = UIColor.green.cgColor
        ring.lineWidth = 4
        ring.strokeEnd = 0
        ring.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        container.addSublayer(ring)

        let dot = CAShapeLayer()
        dot.path = UIBezierPath(ovalIn: CGRect(x: 17, y: 17, width: 6, height: 6)).cgPath
        dot.fillColor = UIColor.white.cgColor
        container.addSublayer(dot)

        return (container, ring)
    }

    private func setProgress(_ p: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leftRing.strokeEnd = p
        rightRing.strokeEnd = p
        CATransaction.commit()
    }

    // MARK: Cámara
    private func setupCamera() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.setSampleBufferDelegate(self, queue: self.frameQueue)
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.updateOrientation() }
        }
    }

    private func updateOrientation() {
        guard let c = output.connection(with: .video), c.isVideoOrientationSupported else { return }
        c.videoOrientation = UIApplication.shared.statusBarOrientation == .landscapeLeft
            ? .landscapeLeft : .landscapeRight
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        for l in [leftLayer, rightLayer] {
            if l.status == .failed { l.flush() }
            l.enqueue(sampleBuffer)
        }
    }

    // MARK: Layout
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = view.bounds.width / 2
        let h = view.bounds.height
        let lf = CGRect(x: 0, y: 0, width: w, height: h)
        let rf = CGRect(x: w, y: 0, width: w, height: h)
        leftLayer.frame = lf
        rightLayer.frame = rf
        leftScn.frame = lf
        rightScn.frame = rf
        leftReticle.position = CGPoint(x: lf.midX, y: lf.midY)
        rightReticle.position = CGPoint(x: rf.midX, y: rf.midY)
        CATransaction.commit()
        updateOrientation()
    }
}
