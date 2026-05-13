import SwiftUI
// AVFoundation's Swift 6 audit isn't complete — AVCaptureSession in
// particular isn't yet marked Sendable, but is safe to use from a
// dedicated serial queue. `@preconcurrency` downgrades the resulting
// non-Sendable-capture warnings to a quieter form until Apple completes
// the audit.
@preconcurrency import AVFoundation
import Vision

/// SwiftUI sheet view that asks for camera permission and presents a live
/// camera feed scanning for UPC/EAN/ISBN/QR barcodes. On the first
/// detection it calls `onScan(payload)` and dismisses itself.
struct BarcodeScannerView: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await requestAccessIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .authorized:
            CameraPreview(onScan: { code in
                onScan(code)
                dismiss()
            })
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("Point the camera at a barcode")
                    .font(.footnote)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        case .notDetermined:
            ProgressView("Requesting camera access…")
        case .denied, .restricted:
            permissionDeniedView
        @unknown default:
            Text("Camera not available")
                .foregroundColor(.secondary)
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Camera access denied")
                .font(.headline)
            Text("Enable camera access in Settings to scan barcodes.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func requestAccessIfNeeded() async {
        guard status == .notDetermined else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            status = granted ? .authorized : .denied
        }
    }
}

// MARK: - Camera preview (UIKit bridge)

private struct CameraPreview: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraViewController {
        let controller = BarcodeCameraViewController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeCameraViewController, context: Context) {
        uiViewController.onScan = onScan
    }
}

/// Hosts an `AVCaptureSession` + Vision barcode detector. Surfaces the
/// first detected payload through `onScan` and then stops the session so
/// the camera doesn't keep running while the sheet animates away.
final class BarcodeCameraViewController: UIViewController {
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let detectionQueue = DispatchQueue(label: "in.the-neighborhood.barcode-detection")
    private let detector = BarcodeDetector()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        detector.onPayload = { [weak self] payload in
            guard let self else { return }
            self.onScan?(payload)
        }
        if !session.isRunning {
            let session = self.session
            detectionQueue.async { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            let session = self.session
            detectionQueue.async { session.stopRunning() }
        }
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(detector, queue: detectionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview
    }
}

/// Separate NSObject delegate so the Cocoa callback isn't constrained by
/// `UIViewController`'s `@MainActor` isolation. The callback hops back to
/// the main actor before invoking `onPayload`.
private final class BarcodeDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onPayload: ((String) -> Void)?

    private let lock = NSLock()
    private var hasReported = false

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Cheap early-exit before any expensive Vision work.
        lock.lock()
        let already = hasReported
        lock.unlock()
        if already { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest { [weak self] req, _ in
            guard let self else { return }
            guard let observation = req.results?.first as? VNBarcodeObservation,
                  let payload = observation.payloadStringValue,
                  !payload.isEmpty else { return }

            self.lock.lock()
            let already = self.hasReported
            self.hasReported = true
            self.lock.unlock()
            guard !already else { return }

            DispatchQueue.main.async {
                self.onPayload?(payload)
            }
        }
        request.symbologies = [.ean13, .ean8, .upce, .code128, .qr]

        // Back camera in portrait orientation maps to `.right` in Vision's coordinate space.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try? handler.perform([request])
    }
}
