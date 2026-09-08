@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ProcessInfo.processInfo.arguments.contains("camera-smoke")
            ? CameraSmokeController() : ButtonLayoutController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class ButtonLayoutController: UIViewController {
    let result = UILabel()
    let taps = UILabel()
    let stack = UIStackView()
    var mounts: [(UIView) -> UIButton] = []
    var samples: [(container: UIView, button: UIButton)] = []
    var failures: [String] = []
    var started = false
    var tapCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        result.text = "Running"
        result.textColor = .black
        result.accessibilityIdentifier = "result"
        result.numberOfLines = 0
        taps.text = "Taps: 0"
        taps.textColor = .black
        taps.accessibilityIdentifier = "taps"
        let scroll = UIScrollView()
        stack.axis = .vertical
        view.addSubview(result); view.addSubview(taps); view.addSubview(scroll)
        scroll.addSubview(stack)
        result.snp.makeConstraints { make in make.top.equalTo(view.safeAreaLayoutGuide).offset(8); make.left.right.equalToSuperview().inset(12) }
        taps.snp.makeConstraints { make in make.top.equalTo(result.snp.bottom); make.left.equalTo(result) }
        scroll.snp.makeConstraints { make in make.top.equalTo(taps.snp.bottom); make.left.right.bottom.equalToSuperview() }
        stack.snp.makeConstraints { make in make.edges.equalTo(scroll.contentLayoutGuide); make.width.equalTo(scroll.frameLayoutGuide) }
        // MOUNTS
        for mount in mounts {
            let container = UIView()
            stack.addArrangedSubview(container)
            container.snp.makeConstraints { make in make.height.equalTo(SCRYFrom(64)) }
            samples.append((container, mount(container)))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { @MainActor in await exercise() }
    }

    func addDeviceToLabelButton(_ container: UIView) -> UIButton {
        let anchor = UIButton()
        container.addSubview(anchor)
        anchor.snp.makeConstraints { make in make.centerY.equalToSuperview(); make.left.equalToSuperview(); make.width.equalTo(1); make.height.equalTo(32) }
        return anchor
    }

    func verify(_ condition: Bool, _ message: String) {
        if !condition && !failures.contains(message) { failures.append(message) }
    }

    func inspect(_ sample: (container: UIView, button: UIButton), index: Int) {
        let button = sample.button
        verify(!button.hasAmbiguousLayout, "\(index): ambiguous button")
        verify(sample.container.bounds.insetBy(dx: -1, dy: -1).contains(button.frame), "\(index): button outside row \(button.frame)")
        if let arrow = button as? TrailingImageButton {
            verify(!arrow.contentLabel.hasAmbiguousLayout && !arrow.trailingImageView.hasAmbiguousLayout, "\(index): ambiguous arrow")
            verify(arrow.trailingImageView.image != nil, "\(index): missing arrow asset")
            verify(abs(arrow.trailingImageView.frame.maxX - arrow.bounds.maxX) < 1, "\(index): arrow moved from trailing edge")
            verify(arrow.contentLabel.frame.maxX <= arrow.trailingImageView.frame.minX - SCRXFrom(6) + 1, "\(index): title overlaps arrow")
            verify(abs(arrow.contentLabel.frame.minX - SCRXFrom(8)) < 1, "\(index): title inset")
            verify(arrow.contentLabel.text == arrow.currentTitle, "\(index): stale title after reuse")
        } else {
            verify(abs(button.layer.cornerRadius - (index < 6 ? SCRYFrom(5) : 15)) < 0.5, "\(index): corner radius changed \(button.layer.cornerRadius)")
            guard let label = button.titleLabel else { failures.append("\(index): missing label"); return }
            verify(button.bounds.insetBy(dx: -1, dy: -1).contains(label.frame), "\(index): clipped label \(label.frame)")
            verify(abs(label.font.pointSize - SCRYFrom(index < 6 ? 13 : 14)) < 0.5, "\(index): font changed")
            verify(label.text == button.currentTitle, "\(index): selected title did not update")
            if index < 6, let image = button.imageView {
                verify(image.image != nil, "\(index): missing scan image")
                verify(abs(image.frame.minX - SCRXFrom(8)) < 1, "\(index): scan image inset \(image.frame)")
                verify(label.frame.minX >= image.frame.maxX, "\(index): scan text overlaps image")
            }
            if !button.isEnabled {
                let color = label.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor ?? label.textColor
                verify(color == button.titleColor(for: .disabled), "\(index): disabled color changed")
            }
        }
    }

    @MainActor func exercise() async {
        for state in 0..<4 {
            for sample in samples {
                sample.button.isSelected = state == 1
                sample.button.isEnabled = state != 2
                sample.button.isHighlighted = state == 3
                sample.button.setNeedsUpdateConfiguration()
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
            view.layoutIfNeeded()
            for (index, sample) in samples.enumerated() { inspect(sample, index: index) }
        }
        for sample in samples { sample.button.isEnabled = true; sample.button.isSelected = false; sample.button.isHighlighted = false }
        for title in ["Space", "Very long space name that must be truncated without moving the arrow", "非常长的空间名称必须正确截断并保持箭头在右侧"] {
            for sample in samples where sample.button is TrailingImageButton { sample.button.setTitle(title, for: .normal) }
            view.layoutIfNeeded()
            for (index, sample) in samples.enumerated() where sample.button is TrailingImageButton { inspect(sample, index: index) }
        }
        // Reattachment exercises reused views and a second constraint/layout pass.
        let first = samples[0]
        first.button.removeFromSuperview()
        let replacement = mounts[0](first.container)
        samples[0] = (first.container, replacement)
        try? await Task.sleep(nanoseconds: 60_000_000)
        view.layoutIfNeeded()
        inspect(samples[0], index: 0)
        result.accessibilityValue = failures.joined(separator: "; ")
        result.text = failures.isEmpty ? "PASS: 11 button layouts" : "FAIL: button layouts"
        print("WarningButtonLayout: \(result.text!) \(failures)")
    }

    @objc func scanBtnClick() { tapCount += 1; taps.text = "Taps: \(tapCount)" }
    @objc func addDeviceTargetBtnClick() { scanBtnClick() }
    @objc func viewTypeBtnAction() { scanBtnClick() }
    @objc func identifyBtnClick() { scanBtnClick() }
    // METHODS
}
