import UIKit
import AVFoundation

class ViewController: UIViewController {
    private let session = AVCaptureSession()
    private var leftLayer: AVCaptureVideoPreviewLayer!
    private var rightLayer: AVCaptureVideoPreviewLayer!
    private let sessionQueue = DispatchQueue(label: "camera.session")

    override var prefersStatusBarHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .landscape }
    override var shouldAutorotate: Bool { return true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        leftLayer = AVCaptureVideoPreviewLayer(session: session)
        rightLayer = AVCaptureVideoPreviewLayer(session: session)
        for l in [leftLayer!, rightLayer!] {
            l.videoGravity = .resizeAspectFill
            l.masksToBounds = true
            view.layer.addSublayer(l)
        }

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

    private func setupCamera() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width / 2
        let h = view.bounds.height
        leftLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)
        rightLayer.frame = CGRect(x: w, y: 0, width: w, height: h)

        let orientation: AVCaptureVideoOrientation =
            UIApplication.shared.statusBarOrientation == .landscapeLeft ? .landscapeLeft : .landscapeRight
        for l in [leftLayer!, rightLayer!] {
            if let c = l.connection, c.isVideoOrientationSupported {
                c.videoOrientation = orientation
            }
        }
    }
}
