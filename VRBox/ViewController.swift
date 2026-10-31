import UIKit
import AVFoundation
import CoreMedia

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let leftLayer = AVSampleBufferDisplayLayer()
    private let rightLayer = AVSampleBufferDisplayLayer()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let frameQueue = DispatchQueue(label: "camera.frames")

    override var prefersStatusBarHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .landscape }
    override var shouldAutorotate: Bool { return true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        for l in [leftLayer, rightLayer] {
            l.videoGravity = .resizeAspectFill
            l.backgroundColor = UIColor.black.cgColor
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = view.bounds.width / 2
        let h = view.bounds.height
        leftLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)
        rightLayer.frame = CGRect(x: w, y: 0, width: w, height: h)
        CATransaction.commit()
        updateOrientation()
    }
}
