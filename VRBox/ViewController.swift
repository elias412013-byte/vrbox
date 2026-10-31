import UIKit
import AVFoundation
import CoreMedia
import CoreMotion
import SceneKit
import simd
import WebKit
import Photos

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, WKNavigationDelegate {

    // MARK: Tipos
    private enum Screen { case menu, browser, gallery, photo, settings }
    private enum HandStyle { case silhouette, skeleton, debug }

    private struct Btn {
        let id: String
        let title: String
        let rect: CGRect
        var dwell: CFTimeInterval = 1.0
        var repeatAfter: CFTimeInterval? = nil
        var drawn = true
    }

    // MARK: Cámara y manos
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let leftLayer = AVSampleBufferDisplayLayer()
    private let rightLayer = AVSampleBufferDisplayLayer()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let frameQueue = DispatchQueue(label: "camera.frames")
    private let tracker = HandTracker()
    private let leftOverlay = HandOverlay()
    private let rightOverlay = HandOverlay()
    private var handVisible = false
    private var missCount = 0
    private var smoothTip: CGPoint? = nil
    private var palmPoint: CGPoint? = nil
    private var lastMask: CGImage? = nil
    private var lastSil: CGImage? = nil
    private var lastArea = 0
    private var lastCb = 0
    private var lastCr = 0

    // MARK: Escena 3D
    private let scene = SCNScene()
    private let headNode = SCNNode()
    private let leftCam = SCNNode()
    private let rightCam = SCNNode()
    private let leftScn = SCNView()
    private let rightScn = SCNView()
    private let pivot = SCNNode()
    private let windowNode = SCNNode()
    private let keyboardNode = SCNNode()
    private let windowMat = SCNMaterial()
    private let keyboardMat = SCNMaterial()
    private let winW: Float = 1.6
    private let winH: Float = 0.9
    private let kbW: Float = 1.6
    private let kbH: Float = 0.55
    private let winDist: Float = 1.5
    private let texW: CGFloat = 1280
    private let texH: CGFloat = 720
    private let kbTexH: CGFloat = 440
    private var windowScale: Float = 1.0
    private var winYaw: Float = 0
    private var winPitch: Float = 0

    // MARK: Movimiento (3DoF)
    private let motion = CMMotionManager()
    private var yawFix = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var needsRecenter = true

    // MARK: Estado de la interfaz
    private var screen: Screen = .menu
    private var moving = false
    private var isTyping = false
    private var clickMode = false
    private var handStyle: HandStyle = .silhouette
    private var gazeEnabled = true
    private var windowButtons: [Btn] = []
    private var keyboardButtons: [Btn] = []
    private var hoverID: String? = nil
    private var hoverStart: CFTimeInterval = 0
    private var locked = false
    private var windowDirty = false
    private var kbDirty = false
    private var lastRender: CFTimeInterval = 0
    private var hintText = ""
    private var hintUntil: CFTimeInterval = 0
    private var link: CADisplayLink?

    // MARK: Navegador
    private var webView: WKWebView?
    private var webImage: UIImage?
    private var addressBuffer = ""
    private var currentURL = ""
    private var snapTimer: Timer?
    private var snapBusy = false

    // MARK: Galería
    private var assets: [PHAsset] = []
    private var thumbs: [String: UIImage] = [:]
    private var thumbRequested = Set<String>()
    private var galleryPage = 0
    private var photoIndex = 0
    private var fullImage: UIImage?
    private var galleryRequested = false
    private var galleryDenied = false

    override var prefersStatusBarHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .landscape }
    override var shouldAutorotate: Bool { return true }

    // MARK: Ciclo de vida
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

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

        view.layer.addSublayer(leftOverlay.root)
        view.layer.addSublayer(rightOverlay.root)

        loadCalibration()
        tracker.onCalibrated = { [weak self] a, b, c, d in
            DispatchQueue.main.async {
                self?.saveCalibration(a, b, c, d)
                self?.flashHint("Calibración lista ✓", 2.5)
            }
        }

        refreshWindow()
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
        if link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.preferredFramesPerSecond = 30
            l.add(to: .main, forMode: .common)
            link = l
        }
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

        scene.rootNode.addChildNode(pivot)

        let wPlane = SCNPlane(width: CGFloat(winW), height: CGFloat(winH))
        windowMat.lightingModel = .constant
        wPlane.materials = [windowMat]
        windowNode.geometry = wPlane
        windowNode.position = SCNVector3(0, 0, -winDist)
        pivot.addChildNode(windowNode)

        let kPlane = SCNPlane(width: CGFloat(kbW), height: CGFloat(kbH))
        keyboardMat.lightingModel = .constant
        kPlane.materials = [keyboardMat]
        keyboardNode.geometry = kPlane
        keyboardNode.position = SCNVector3(0, -0.76, 0.06)
        keyboardNode.eulerAngles = SCNVector3(-0.45, 0, 0)
        keyboardNode.isHidden = true
        windowNode.addChildNode(keyboardNode)
    }

    private func setScale(_ s: Float) {
        windowScale = max(0.4, min(2.2, s))
        windowNode.scale = SCNVector3(windowScale, windowScale, windowScale)
    }

    private func resetWindow() {
        winYaw = 0
        winPitch = 0
        pivot.eulerAngles = SCNVector3(0, 0, 0)
        setScale(1.0)
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
            winYaw = 0
            winPitch = 0
            pivot.eulerAngles = SCNVector3(0, 0, 0)
        }

        let orient = yawFix * head
        headNode.simdOrientation = orient

        if moving {
            // La pantalla sigue tu mirada hasta que elijas FIJAR
            let f = orient.act(SIMD3<Float>(0, 0, -1))
            let ty = atan2(-f.x, -f.z)
            let tp = asin(max(-1, min(1, f.y)))
            var dy = ty - winYaw
            while dy > Float.pi { dy -= 2 * Float.pi }
            while dy < -Float.pi { dy += 2 * Float.pi }
            winYaw += dy * 0.25
            winPitch += (tp - winPitch) * 0.25
            pivot.eulerAngles = SCNVector3(winPitch, winYaw, 0)
        }
    }

    // MARK: Manos
    private func handleHand(_ r: HandResult) {
        lastMask = r.maskImage
        lastArea = r.area
        lastCb = r.centerCb
        lastCr = r.centerCr
        let size = CGSize(width: r.imgW, height: r.imgH)
        leftOverlay.imgSize = size
        rightOverlay.imgSize = size
        if r.found {
            lastSil = r.silhouetteImage
            missCount = 0
            handVisible = true
            palmPoint = r.palm
            if let s = smoothTip {
                smoothTip = CGPoint(x: s.x + (r.tip.x - s.x) * 0.45, y: s.y + (r.tip.y - s.y) * 0.45)
            } else {
                smoothTip = r.tip
            }
        } else {
            missCount += 1
            if missCount > 6 {
                handVisible = false
                lastSil = nil
                smoothTip = nil
                palmPoint = nil
            }
        }
    }

    private func loadCalibration() {
        let d = UserDefaults.standard
        if d.object(forKey: "cbMin") != nil {
            tracker.setRange(cbMin: d.integer(forKey: "cbMin"), cbMax: d.integer(forKey: "cbMax"),
                             crMin: d.integer(forKey: "crMin"), crMax: d.integer(forKey: "crMax"))
        }
    }

    private func saveCalibration(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        let u = UserDefaults.standard
        u.set(a, forKey: "cbMin"); u.set(b, forKey: "cbMax")
        u.set(c, forKey: "crMin"); u.set(d, forKey: "crMax")
    }

    private func flashHint(_ text: String, _ seconds: CFTimeInterval) {
        hintText = text
        hintUntil = CACurrentMediaTime() + seconds
    }

    // MARK: Bucle principal (30 fps)
    private func cursorPoint(_ ov: HandOverlay, finger: Bool) -> CGPoint {
        if finger, let t = smoothTip { return ov.mapPoint(t) }
        return CGPoint(x: ov.root.bounds.midX, y: ov.root.bounds.midY)
    }

    private func findButton(_ id: String) -> Btn? {
        if let b = windowButtons.first(where: { $0.id == id }) { return b }
        return keyboardButtons.first(where: { $0.id == id })
    }

    private func markDirty(_ id: String?) {
        guard let id = id else { return }
        if id.hasPrefix("k.") { kbDirty = true } else { windowDirty = true }
    }

    @objc private func tick() {
        let b = leftScn.bounds
        guard b.width > 10 else { return }
        let now = CACurrentMediaTime()

        // 1) Puntero: dedo si hay mano, si no la mirada (centro de la vista)
        let finger = handVisible && smoothTip != nil
        var pt = CGPoint(x: b.midX, y: b.midY)
        if finger, let t = smoothTip { pt = leftOverlay.mapPoint(t) }
        let calibRemaining = tracker.calibrationRemaining
        let pointerOK = (finger || gazeEnabled || moving) && calibRemaining <= 0

        // 2) ¿Qué hay debajo del puntero?
        var hitID: String? = nil
        var px = CGPoint.zero
        if pointerOK {
            for h in leftScn.hitTest(pt, options: nil) {
                let lc = h.localCoordinates
                if h.node === windowNode {
                    px = CGPoint(x: (CGFloat(lc.x) + CGFloat(winW) / 2) / CGFloat(winW) * texW,
                                 y: (CGFloat(winH) / 2 - CGFloat(lc.y)) / CGFloat(winH) * texH)
                    hitID = windowButtons.first(where: { $0.rect.contains(px) })?.id
                    break
                } else if h.node === keyboardNode {
                    px = CGPoint(x: (CGFloat(lc.x) + CGFloat(kbW) / 2) / CGFloat(kbW) * texW,
                                 y: (CGFloat(kbH) / 2 - CGFloat(lc.y)) / CGFloat(kbH) * kbTexH)
                    hitID = keyboardButtons.first(where: { $0.rect.contains(px) })?.id
                    break
                }
            }
        }

        // 3) Tiempo de espera (el círculo se llena)
        if hitID != hoverID {
            markDirty(hoverID)
            markDirty(hitID)
            hoverID = hitID
            hoverStart = now
            locked = false
        }
        var progress: CGFloat = 0
        if let id = hoverID, !locked, let btn = findButton(id) {
            let elapsed = now - hoverStart
            progress = CGFloat(max(0, min(1, elapsed / btn.dwell)))
            if elapsed >= btn.dwell {
                if let rep = btn.repeatAfter {
                    hoverStart = now + rep - btn.dwell
                } else {
                    locked = true
                }
                progress = 0
                perform(id, px: px)
            }
        }

        // 4) Avisos y overlays
        var hint: String? = nil
        if calibRemaining > 0 {
            hint = "Tapá el cuadro amarillo con tu mano (\(Int(ceil(calibRemaining))))"
        } else if moving {
            hint = "Mirá a donde querés la pantalla y elegí FIJAR"
        } else if now < hintUntil {
            hint = hintText
        } else if handStyle == .debug {
            hint = "Mano: " + (finger ? "SÍ" : "NO") + " · celdas \(lastArea) · centro Cb/Cr \(lastCb)/\(lastCr)"
        }
        let calibRect: CGRect? = calibRemaining > 0 ? HandTracker.calibRect : nil

        leftOverlay.update(maskImage: lastMask, showMask: handStyle == .debug, silhouette: lastSil, showSilhouette: handStyle == .silhouette,
                           palm: finger ? palmPoint : nil, tip: finger ? smoothTip : nil,
                           showSkeleton: handStyle != .silhouette,
                           cursor: cursorPoint(leftOverlay, finger: finger),
                           progress: progress, hovering: hoverID != nil,
                           hint: hint, calibRect: calibRect)
        rightOverlay.update(maskImage: lastMask, showMask: handStyle == .debug, silhouette: lastSil, showSilhouette: handStyle == .silhouette,
                            palm: finger ? palmPoint : nil, tip: finger ? smoothTip : nil,
                            showSkeleton: handStyle != .silhouette,
                            cursor: cursorPoint(rightOverlay, finger: finger),
                            progress: progress, hovering: hoverID != nil,
                            hint: hint, calibRect: calibRect)

        // 5) Redibujar texturas si hizo falta (máx. ~12 veces por segundo)
        if (windowDirty || kbDirty) && now - lastRender > 0.08 {
            lastRender = now
            if windowDirty { refreshWindow() }
            if kbDirty { refreshKeyboard() }
        }
    }

    // MARK: Acciones
    private func perform(_ id: String, px: CGPoint) {
        switch id {
        case "home": goHome()
        case "shrink": setScale(windowScale / 1.08)
        case "grow": setScale(windowScale * 1.08)
        case "move": moving = true; isTyping = false
        case "fix": moving = false
        case "app.browser": screen = .browser; ensureWebView(); startSnapshots()
        case "app.gallery": screen = .gallery; galleryPage = 0
        case "app.settings": screen = .settings
        case "web.back": if let w = webView, w.canGoBack { w.goBack() }
        case "web.addr": isTyping = true; addressBuffer = ""
        case "web.go": goToAddress()
        case "web.up": scrollWeb(-200)
        case "web.down": scrollWeb(200)
        case "web.click": clickMode.toggle()
        case "web.area": clickWeb(at: px)
        case "g.prev": galleryPage = max(0, galleryPage - 1)
        case "g.next": if (galleryPage + 1) * 8 < assets.count { galleryPage += 1 }
        case "p.back": screen = .gallery
        case "p.prev": photoIndex = max(0, photoIndex - 1); loadFull()
        case "p.next": photoIndex = min(max(0, assets.count - 1), photoIndex + 1); loadFull()
        case "s.style": cycleHandStyle()
        case "s.gaze": gazeEnabled.toggle()
        case "s.calib": tracker.beginCalibration(duration: 4.0)
        case "s.center": needsRecenter = true
        case "s.reset": resetWindow()
        default:
            if id.hasPrefix("g."), let i = Int(id.dropFirst(2)) {
                photoIndex = galleryPage * 8 + i
                screen = .photo
                loadFull()
            } else if id.hasPrefix("k.") {
                typeKey(id)
            }
        }
        refreshWindow()
        refreshKeyboard()
    }

    private func handStyleName() -> String {
        switch handStyle {
        case .silhouette: return "Silueta oscura"
        case .skeleton: return "Esqueleto"
        case .debug: return "Detección (datos)"
        }
    }

    private func cycleHandStyle() {
        switch handStyle {
        case .silhouette: handStyle = .skeleton
        case .skeleton: handStyle = .debug
        case .debug: handStyle = .silhouette
        }
    }

    private func goHome() {
        screen = .menu
        isTyping = false
        moving = false
        stopSnapshots()
    }

    private func typeKey(_ id: String) {
        switch id {
        case "k.del": if !addressBuffer.isEmpty { addressBuffer.removeLast() }
        case "k.space": addressBuffer += " "
        case "k.com": addressBuffer += ".com"
        case "k.enter": goToAddress()
        default: addressBuffer += String(id.dropFirst(2))
        }
    }

    // MARK: Navegador web
    private func ensureWebView() {
        if webView != nil { return }
        let cfg = WKWebViewConfiguration()
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 342), configuration: cfg)
        w.navigationDelegate = self
        w.isUserInteractionEnabled = false
        w.layer.zPosition = -10   // queda detrás de todo, pero "visible" para el sistema
        view.addSubview(w)
        webView = w
        if let u = URL(string: "https://www.google.com") { w.load(URLRequest(url: u)) }
    }

    private func startSnapshots() {
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(timeInterval: 0.35, target: self, selector: #selector(snap),
                                         userInfo: nil, repeats: true)
    }

    private func stopSnapshots() {
        snapTimer?.invalidate()
        snapTimer = nil
    }

    @objc private func snap() {
        guard screen == .browser, let w = webView, !snapBusy else { return }
        snapBusy = true
        let cfg = WKSnapshotConfiguration()
        cfg.snapshotWidth = NSNumber(value: 800)
        w.takeSnapshot(with: cfg) { [weak self] image, _ in
            guard let self = self else { return }
            self.snapBusy = false
            if let image = image {
                self.webImage = image
                if self.screen == .browser { self.windowDirty = true }
            }
        }
    }

    private func goToAddress() {
        let t = addressBuffer.trimmingCharacters(in: .whitespaces)
        isTyping = false
        guard !t.isEmpty else { return }
        ensureWebView()
        var urlStr: String
        if !t.contains(" ") && t.contains(".") {
            urlStr = t.hasPrefix("http") ? t : "https://" + t
        } else {
            let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            urlStr = "https://www.google.com/search?q=" + q
        }
        if let u = URL(string: urlStr) { webView?.load(URLRequest(url: u)) }
    }

    private func scrollWeb(_ delta: CGFloat) {
        guard let sv = webView?.scrollView else { return }
        var off = sv.contentOffset
        let maxY = max(0, sv.contentSize.height - sv.bounds.height)
        off.y = max(0, min(maxY, off.y + delta))
        sv.setContentOffset(off, animated: false)
    }

    private func clickWeb(at px: CGPoint) {
        guard let w = webView else { return }
        let x = px.x / texW * w.bounds.width
        let y = (px.y - 172) / 548 * w.bounds.height
        let js = "(function(){var e=document.elementFromPoint(\(x),\(y));if(!e)return;var t=(e.tagName||'').toUpperCase();if(t==='INPUT'||t==='TEXTAREA'||t==='SELECT')return;e.click();})()"
        w.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        currentURL = webView.url?.absoluteString ?? ""
        windowDirty = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url?.absoluteString ?? ""
        windowDirty = true
    }

    // MARK: Galería
    private func prepareGallery() {
        if !galleryRequested {
            galleryRequested = true
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    guard status == .authorized || status.rawValue == 4 else {
                        self.galleryDenied = true
                        self.windowDirty = true
                        return
                    }
                    let opts = PHFetchOptions()
                    opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                    opts.fetchLimit = 200
                    let res = PHAsset.fetchAssets(with: .image, options: opts)
                    var list: [PHAsset] = []
                    res.enumerateObjects { a, _, _ in list.append(a) }
                    self.assets = list
                    self.windowDirty = true
                }
            }
        }
        let start = galleryPage * 8
        for i in 0..<8 where start + i < assets.count {
            requestThumb(assets[start + i])
        }
    }

    private func requestThumb(_ a: PHAsset) {
        let id = a.localIdentifier
        if thumbs[id] != nil || thumbRequested.contains(id) { return }
        thumbRequested.insert(id)
        let o = PHImageRequestOptions()
        o.deliveryMode = .fastFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = false
        PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 360, height: 300),
                                              contentMode: .aspectFill, options: o) { [weak self] img, _ in
            DispatchQueue.main.async {
                guard let self = self, let img = img else { return }
                self.thumbs[id] = img
                self.windowDirty = true
            }
        }
    }

    private func loadFull() {
        fullImage = nil
        guard photoIndex >= 0 && photoIndex < assets.count else { return }
        let idx = photoIndex
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.isNetworkAccessAllowed = false
        PHImageManager.default().requestImage(for: assets[idx], targetSize: CGSize(width: 1280, height: 720),
                                              contentMode: .aspectFit, options: o) { [weak self] img, _ in
            DispatchQueue.main.async {
                guard let self = self, self.photoIndex == idx, let img = img else { return }
                self.fullImage = img
                self.windowDirty = true
            }
        }
    }

    // MARK: Botones
    private func makeWindowButtons() -> [Btn] {
        if moving {
            return [Btn(id: "fix", title: "FIJAR AQUÍ", rect: CGRect(x: 340, y: 270, width: 600, height: 180))]
        }
        var b: [Btn] = [
            Btn(id: "home", title: "Inicio", rect: CGRect(x: 20, y: 12, width: 190, height: 66)),
            Btn(id: "shrink", title: "−", rect: CGRect(x: 225, y: 12, width: 100, height: 66), dwell: 0.5, repeatAfter: 0.35),
            Btn(id: "grow", title: "+", rect: CGRect(x: 335, y: 12, width: 100, height: 66), dwell: 0.5, repeatAfter: 0.35),
            Btn(id: "move", title: "Mover", rect: CGRect(x: 445, y: 12, width: 190, height: 66))
        ]
        switch screen {
        case .menu:
            b.append(Btn(id: "app.browser", title: "Navegador", rect: CGRect(x: 240, y: 190, width: 800, height: 90)))
            b.append(Btn(id: "app.gallery", title: "Galería", rect: CGRect(x: 240, y: 290, width: 800, height: 90)))
            b.append(Btn(id: "app.settings", title: "Ajustes", rect: CGRect(x: 240, y: 390, width: 800, height: 90)))
            b.append(Btn(id: "s.calib", title: "Calibrar mano", rect: CGRect(x: 240, y: 490, width: 800, height: 90)))
        case .browser:
            b.append(Btn(id: "web.back", title: "←", rect: CGRect(x: 20, y: 98, width: 90, height: 66), dwell: 0.8))
            b.append(Btn(id: "web.addr", title: "", rect: CGRect(x: 120, y: 98, width: 740, height: 66)))
            b.append(Btn(id: "web.go", title: "Ir", rect: CGRect(x: 870, y: 98, width: 90, height: 66)))
            b.append(Btn(id: "web.up", title: "▲", rect: CGRect(x: 970, y: 98, width: 90, height: 66), dwell: 0.5, repeatAfter: 0.5))
            b.append(Btn(id: "web.down", title: "▼", rect: CGRect(x: 1070, y: 98, width: 90, height: 66), dwell: 0.5, repeatAfter: 0.5))
            b.append(Btn(id: "web.click", title: clickMode ? "Clic ✓" : "Clic", rect: CGRect(x: 1170, y: 98, width: 90, height: 66), dwell: 0.8))
            if clickMode {
                b.append(Btn(id: "web.area", title: "", rect: CGRect(x: 0, y: 172, width: 1280, height: 548), dwell: 1.2, drawn: false))
            }
        case .gallery:
            let start = galleryPage * 8
            for i in 0..<8 where start + i < assets.count {
                let col = CGFloat(i % 4), row = CGFloat(i / 4)
                b.append(Btn(id: "g.\(i)", title: "", rect: CGRect(x: 40 + col * 303, y: 105 + row * 245, width: 290, height: 230), drawn: false))
            }
            b.append(Btn(id: "g.prev", title: "◀", rect: CGRect(x: 340, y: 610, width: 200, height: 80), dwell: 0.8))
            b.append(Btn(id: "g.next", title: "▶", rect: CGRect(x: 740, y: 610, width: 200, height: 80), dwell: 0.8))
        case .photo:
            b.append(Btn(id: "p.prev", title: "◀", rect: CGRect(x: 240, y: 640, width: 200, height: 70), dwell: 0.8))
            b.append(Btn(id: "p.back", title: "Galería", rect: CGRect(x: 480, y: 640, width: 320, height: 70)))
            b.append(Btn(id: "p.next", title: "▶", rect: CGRect(x: 840, y: 640, width: 200, height: 70), dwell: 0.8))
        case .settings:
            let items: [(String, String)] = [
                ("s.style", "Mano: " + handStyleName()),
                ("s.gaze", "Selección con la mirada: " + (gazeEnabled ? "SÍ" : "NO")),
                ("s.calib", "Calibrar color de piel"),
                ("s.center", "Recentrar vista"),
                ("s.reset", "Restablecer pantalla")
            ]
            for (i, it) in items.enumerated() {
                b.append(Btn(id: it.0, title: it.1, rect: CGRect(x: 240, y: 100 + CGFloat(i) * 94, width: 800, height: 82)))
            }
        }
        return b
    }

    private func makeKeyboardButtons() -> [Btn] {
        let rows: [[String]] = [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ"],
            ["z", "x", "c", "v", "b", "n", "m", ".", "/", "-"]
        ]
        var b: [Btn] = []
        for (r, row) in rows.enumerated() {
            for (c, key) in row.enumerated() {
                b.append(Btn(id: "k." + key, title: key,
                             rect: CGRect(x: CGFloat(c) * 128 + 4, y: CGFloat(r) * 86 + 6, width: 120, height: 78),
                             dwell: 0.55, repeatAfter: 0.9))
            }
        }
        b.append(Btn(id: "k.del", title: "Borrar", rect: CGRect(x: 4, y: 350, width: 300, height: 78), dwell: 0.55, repeatAfter: 0.7))
        b.append(Btn(id: "k.space", title: "espacio", rect: CGRect(x: 312, y: 350, width: 560, height: 78), dwell: 0.55, repeatAfter: 0.9))
        b.append(Btn(id: "k.com", title: ".com", rect: CGRect(x: 880, y: 350, width: 180, height: 78), dwell: 0.7))
        b.append(Btn(id: "k.enter", title: "Ir", rect: CGRect(x: 1068, y: 350, width: 208, height: 78), dwell: 0.7))
        return b
    }

    // MARK: Dibujo de las pantallas
    private func refreshWindow() {
        windowDirty = false
        windowButtons = makeWindowButtons()
        if screen == .gallery { prepareGallery() }
        windowMat.diffuse.contents = renderWindow()
    }

    private func refreshKeyboard() {
        kbDirty = false
        let show = screen == .browser && isTyping && !moving
        keyboardNode.isHidden = !show
        keyboardButtons = show ? makeKeyboardButtons() : []
        if show { keyboardMat.diffuse.contents = renderKeyboard() }
    }

    private func screenTitle() -> String {
        switch screen {
        case .menu: return "VRBox"
        case .browser: return "Navegador"
        case .gallery, .photo: return "Galería"
        case .settings: return "Ajustes"
        }
    }

    private func renderWindow() -> UIImage {
        let size = CGSize(width: texW, height: texH)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let gray = UIColor(white: 0.62, alpha: 1)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            UIColor(white: 0.5, alpha: 1).setStroke()
            let border = UIBezierPath(rect: CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8))
            border.lineWidth = 4
            border.stroke()

            if self.moving {
                self.drawText("Moviendo la pantalla", in: CGRect(x: 0, y: 120, width: 1280, height: 100), size: 64, bold: true)
                self.drawText("Mirá a donde la querés y elegí FIJAR", in: CGRect(x: 0, y: 500, width: 1280, height: 80), size: 40, color: gray)
            } else {
                self.drawText(self.screenTitle(), in: CGRect(x: 660, y: 12, width: 580, height: 66), size: 40, color: gray, align: .right)
                switch self.screen {
                case .menu:
                    self.drawText("VRBox", in: CGRect(x: 0, y: 100, width: 1280, height: 90), size: 72, bold: true)
                    self.drawText("Apuntá con el dedo (o mirá) 1 segundo para elegir", in: CGRect(x: 0, y: 600, width: 1280, height: 50), size: 32, color: gray)
                    self.drawText("Primero: Calibrar mano (tapá el cuadro amarillo con tu mano)", in: CGRect(x: 0, y: 650, width: 1280, height: 50), size: 28, color: gray)
                case .browser:
                    if let img = self.webImage {
                        img.draw(in: CGRect(x: 0, y: 172, width: 1280, height: 548))
                    } else {
                        self.drawText("Cargando…", in: CGRect(x: 0, y: 380, width: 1280, height: 80), size: 48, color: gray)
                    }
                case .gallery:
                    self.drawGallery(gray: gray)
                case .photo:
                    if let img = self.fullImage {
                        self.drawFit(img, in: CGRect(x: 20, y: 95, width: 1240, height: 535))
                    } else {
                        self.drawText("Cargando…", in: CGRect(x: 0, y: 340, width: 1280, height: 80), size: 48, color: gray)
                    }
                case .settings:
                    break
                }
            }

            for b in self.windowButtons where b.drawn {
                let hot = (b.id == self.hoverID)
                let isAddr = b.id == "web.addr"
                var fill = hot ? UIColor(white: 0.42, alpha: 1) : UIColor(white: 0.18, alpha: 1)
                if isAddr { fill = hot ? UIColor(white: 0.25, alpha: 1) : UIColor(white: 0.10, alpha: 1) }
                fill.setFill()
                let path = UIBezierPath(roundedRect: b.rect, cornerRadius: 20)
                path.fill()
                if isAddr && self.isTyping {
                    UIColor.green.setStroke()
                    path.lineWidth = 3
                    path.stroke()
                }
                if isAddr {
                    var t = self.isTyping ? self.addressBuffer + "|" : (self.currentURL.isEmpty ? "Buscar o escribir URL" : self.currentURL)
                    if t.hasPrefix("https://") { t = String(t.dropFirst(8)) }
                    self.drawText(t, in: b.rect.insetBy(dx: 18, dy: 0), size: 32, align: .left)
                } else {
                    let big = b.rect.height > 90
                    self.drawText(b.title, in: b.rect, size: big ? 52 : (b.rect.height < 70 ? 36 : 40))
                }
            }
        }
    }

    private func drawGallery(gray: UIColor) {
        if galleryDenied {
            drawText("Sin acceso a las fotos", in: CGRect(x: 0, y: 260, width: 1280, height: 80), size: 52, bold: true)
            drawText("Activalo en Ajustes de iOS › VRBox › Fotos", in: CGRect(x: 0, y: 350, width: 1280, height: 60), size: 34, color: gray)
            return
        }
        if assets.isEmpty {
            drawText("No hay fotos para mostrar", in: CGRect(x: 0, y: 320, width: 1280, height: 80), size: 48, color: gray)
            return
        }
        let start = galleryPage * 8
        for i in 0..<8 where start + i < assets.count {
            let col = CGFloat(i % 4), row = CGFloat(i / 4)
            let r = CGRect(x: 40 + col * 303, y: 105 + row * 245, width: 290, height: 230)
            if let img = thumbs[assets[start + i].localIdentifier] {
                drawFill(img, in: r)
            } else {
                UIColor(white: 0.15, alpha: 1).setFill()
                UIBezierPath(roundedRect: r, cornerRadius: 14).fill()
            }
            if hoverID == "g.\(i)" {
                UIColor.green.setStroke()
                let p = UIBezierPath(roundedRect: r, cornerRadius: 14)
                p.lineWidth = 8
                p.stroke()
            }
        }
        let pages = (assets.count + 7) / 8
        drawText("\(galleryPage + 1) / \(pages)", in: CGRect(x: 540, y: 610, width: 200, height: 80), size: 38, color: gray)
    }

    private func renderKeyboard() -> UIImage {
        let size = CGSize(width: texW, height: kbTexH)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor(white: 0.05, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for b in self.keyboardButtons {
                let hot = (b.id == self.hoverID)
                (hot ? UIColor(white: 0.45, alpha: 1) : UIColor(white: 0.20, alpha: 1)).setFill()
                UIBezierPath(roundedRect: b.rect, cornerRadius: 14).fill()
                self.drawText(b.title, in: b.rect, size: b.rect.width > 200 ? 38 : 46)
            }
        }
    }

    private func drawText(_ text: String, in rect: CGRect, size: CGFloat, color: UIColor = .white,
                          bold: Bool = false, align: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byTruncatingTail
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let h = font.lineHeight
        let r = CGRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h)
        (text as NSString).draw(in: r, withAttributes: attrs)
    }

    private func drawFill(_ img: UIImage, in rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 14).addClip()
        let s = max(rect.width / img.size.width, rect.height / img.size.height)
        let w = img.size.width * s
        let h = img.size.height * s
        img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        ctx?.restoreGState()
    }

    private func drawFit(_ img: UIImage, in rect: CGRect) {
        let s = min(rect.width / img.size.width, rect.height / img.size.height)
        let w = img.size.width * s
        let h = img.size.height * s
        img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
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
            self.output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
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
        if let pb = CMSampleBufferGetImageBuffer(sampleBuffer), let res = tracker.process(pb) {
            DispatchQueue.main.async { self.handleHand(res) }
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
        leftOverlay.root.frame = lf
        rightOverlay.root.frame = rf
        CATransaction.commit()
        updateOrientation()
    }
}
