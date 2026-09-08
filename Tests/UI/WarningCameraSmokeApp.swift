import AVFoundation

final class CameraSmokeController: UIViewController {
    private let result = UILabel()
    private let preview = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
    private var scanner: LBXScanWrapper?
    private var callbacks = 0
    private var failures: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        result.textColor = .black
        result.numberOfLines = 0
        result.text = "Waiting for camera permission"
        result.accessibilityIdentifier = "camera-result"
        view.addSubview(result)
        result.snp.makeConstraints { make in make.center.equalToSuperview(); make.left.right.equalToSuperview().inset(20) }
        Task { @MainActor in await exercise() }
    }

    @MainActor private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    @MainActor private func exercise() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            result.text = "FAIL: camera permission denied"
            return
        }
        let payload = "warning-camera-fixture"
        if let code = LBXScanWrapper.createCode(codeType: "CIQRCodeGenerator", codeString: payload,
                                               size: CGSize(width: 256, height: 256), qrColor: .black, bkColor: .white) {
            if LBXScanWrapper.recognizeQRImage(image: code).first?.strScanned != payload {
                failures.append("QR image recognition")
            }
        } else { failures.append("QR image generation") }
        let scanner = LBXScanWrapper(videoPreView: preview, isCaptureImg: true) { [weak self] results in
            guard let self else { return }
            dispatchPrecondition(condition: .onQueue(.main))
            self.callbacks += 1
            if results.count != 1 || results.first?.strScanned != payload || results.first?.imgScanned == nil {
                self.failures.append("Photo result missing")
            }
        }
        self.scanner = scanner
        scanner.start()
        guard await waitFor({ scanner.session.isRunning }) else {
            result.text = "FAIL: camera session did not start"
            return
        }
        scanner.isNeedScanResult = false
        scanner.arrayResult = [LBXScanResult(str: payload, img: nil, barCodeType: AVMetadataObject.ObjectType.qr.rawValue, corner: nil)]
        scanner.captureImage()
        scanner.captureImage()
        if !(await waitFor({ self.callbacks == 1 })) { failures.append("First capture") }
        scanner.start()
        _ = await waitFor({ scanner.session.isRunning })
        scanner.isNeedScanResult = false
        scanner.captureImage()
        scanner.stop()
        try? await Task.sleep(nanoseconds: 700_000_000)
        if callbacks != 1 { failures.append("Cancelled photo delivered") }
        scanner.start()
        _ = await waitFor({ scanner.session.isRunning })
        scanner.isNeedScanResult = false
        scanner.captureImage()
        if !(await waitFor({ self.callbacks == 2 })) { failures.append("Restart capture") }
        scanner.stop()
        result.accessibilityValue = failures.joined(separator: "; ")
        result.text = failures.isEmpty ? "PASS: camera photo and restart" : "FAIL: camera smoke"
        // Photos remain in memory only and are never displayed or written to disk.
    }
}
