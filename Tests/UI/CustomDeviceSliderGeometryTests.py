"""Exercise the production slider geometry with a configurable UISlider stub.

Run: python3 Tests/UI/CustomDeviceSliderGeometryTests.py
Verifies layout math and trim overlays with direct/nested image-view fixtures.
Does not exercise UIKit touch tracking, animations or actual rendering.
"""

from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[2]
source = (root / "SunSmart/Common/View/CustomDeviceSlider.swift").read_text()


def method(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    # Select both OS branches on the host; leave the production geometry intact.
    return source[start:end].replace("#available(iOS 27.0, *)", "usesModernGeometry")


swift = r"""
import Foundation
import CoreGraphics

final class UIImage: NSObject {
    let size: CGSize
    init(size: CGSize) { self.size = size }
}
enum LayoutDirection { case leftToRight, rightToLeft }
enum ControlState { case normal, highlighted, disabled }

class UIView: NSObject {
    var frame = CGRect.zero { didSet { bounds.size = frame.size } }
    var bounds = CGRect.zero
    var isHidden = false
    var clipsToBounds = false
    weak var superview: UIView?
    var subviews: [UIView] = []
    var allSubviews: [UIView] { subviews + subviews.flatMap { $0.allSubviews } }
    func removeFromSuperview() {
        superview?.subviews.removeAll { $0 === self }
        superview = nil
    }
    func addSubview(_ view: UIView) {
        view.removeFromSuperview()
        subviews.append(view)
        view.superview = self
    }
    func insertSubview(_ view: UIView, belowSubview sibling: UIView) {
        view.removeFromSuperview()
        subviews.insert(view, at: subviews.firstIndex { $0 === sibling }!)
        view.superview = self
    }
    func bringSubviewToFront(_ view: UIView) { addSubview(view) }
    private var globalOrigin: CGPoint {
        let parent = superview?.globalOrigin ?? .zero
        return CGPoint(x: parent.x + frame.minX - bounds.minX,
                       y: parent.y + frame.minY - bounds.minY)
    }
    func convert(_ rect: CGRect, to view: UIView?) -> CGRect {
        let target = view?.globalOrigin ?? .zero
        return rect.offsetBy(dx: globalOrigin.x - target.x, dy: globalOrigin.y - target.y)
    }
    func convert(_ rect: CGRect, from view: UIView) -> CGRect { view.convert(rect, to: self) }
}
class UIImageView: UIView {
    var image: UIImage?
    init(image: UIImage?) { self.image = image; super.init() }
}

class UISlider: UIView {
    var minimumValue: Float = 0
    var maximumValue: Float = 100
    var currentThumbImage: UIImage? = UIImage(size: CGSize(width: 40, height: 40))
    var normalThumbImage: UIImage? = UIImage(size: CGSize(width: 40, height: 40))
    var highlightedThumbImage: UIImage?
    var state = ControlState.normal
    var effectiveUserInterfaceLayoutDirection = LayoutDirection.leftToRight
    var usesModernGeometry = true
    var systemThumbWidth: CGFloat = 72
    var systemTrackInset: CGFloat = 17

    func thumbImage(for state: ControlState) -> UIImage? {
        switch state {
        case .normal: return normalThumbImage
        case .highlighted: return highlightedThumbImage
        case .disabled: return nil
        }
    }

    func trackRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + systemTrackInset, y: bounds.midY - 3,
               width: bounds.width - systemTrackInset * 2, height: 6)
    }

    func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        let progress = CGFloat((value - minimumValue) / (maximumValue - minimumValue))
        return CGRect(x: rect.minX + (rect.width - systemThumbWidth) * progress,
                      y: rect.midY - 20, width: systemThumbWidth, height: 40)
    }
}

class CustomDeviceSlider: UISlider {
    var limitRange: ClosedRange<Int>?
    var lastBounds: CGRect?
    let minLineView = UIView()
    let maxLineView = UIView()
    private var trackRect: CGRect?
"""
swift += method("override func thumbRect(") + "\n"
swift += method("override func trackRect(") + "\n"
swift += method("private func updateLimitUI(").replace("private func", "func") + "\n}\n"
swift += r"""
var checks = 0
func expect(_ actual: CGRect?, _ expected: CGRect, _ label: String) {
    guard let actual,
          abs(actual.minX - expected.minX) < 0.0001,
          abs(actual.minY - expected.minY) < 0.0001,
          abs(actual.width - expected.width) < 0.0001,
          abs(actual.height - expected.height) < 0.0001 else {
        let message = "\(label): expected \(expected), got \(String(describing: actual))\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
    checks += 1
}

let bounds = CGRect(x: 10, y: 20, width: 300, height: 40)
let slider = CustomDeviceSlider()
func thumb(_ value: Float, in bounds: CGRect = bounds) -> CGRect {
    slider.thumbRect(forBounds: bounds, trackRect: slider.trackRect(forBounds: bounds), value: value)
}
func expectThumb(_ value: Float, centerX: CGFloat, _ label: String) {
    let result = thumb(value)
    expect(result, CGRect(x: centerX - 20, y: 20, width: 40, height: 40), label)
    expect(slider.lastBounds, result, "floating label: " + label)
}

// iOS 27.0.1 device log: currentThumbImage is nil despite a normal image;
// UIKit supplies a stretched track with a negative height at either endpoint.
slider.currentThumbImage = nil
let deviceBounds = CGRect(x: 0, y: 0, width: 235.66666666666666, height: 43)
expect(slider.trackRect(forBounds: deviceBounds),
       CGRect(x: 0, y: 20.5, width: 235.66666666666666, height: 2), "normal image enables custom track")
let deviceSamples: [(Float, CGRect, CGRect)] = [
    (0, CGRect(x: -9.224186927642705, y: 19.145493843224273,
               width: 241.59940363334434, height: -0.7090123135514546),
        CGRect(x: -15, y: 1.5, width: 40, height: 40)),
    (100, CGRect(x: 3.116502242152478, y: 19.217488789237663,
                 width: 241.2840657698057, height: -0.5650224215246724),
          CGRect(x: 210.66666666666666, y: 1.5, width: 40, height: 40))
]
for (value, incomingTrack, expected) in deviceSamples {
    let result = slider.thumbRect(forBounds: deviceBounds, trackRect: incomingTrack, value: value)
    expect(result, expected, "device endpoint \(value), independent of stretched track")
    expect(slider.lastBounds, expected, "device endpoint floating label \(value)")
}
for state in [ControlState.highlighted, .disabled] {
    slider.state = state
    expectThumb(0, centerX: 15, "normal image fallback for \(state)")
}
slider.state = .highlighted
slider.highlightedThumbImage = UIImage(size: CGSize(width: 30, height: 24))
expect(thumb(0), CGRect(x: 0, y: 28, width: 30, height: 24), "prefer image for active state")
slider.state = .normal
slider.currentThumbImage = slider.normalThumbImage

// Wider system thumbs and inset system tracks must not affect the custom image.
for systemWidth: CGFloat in [40, 72, 96] {
    slider.systemThumbWidth = systemWidth
    expect(slider.trackRect(forBounds: bounds),
           CGRect(x: 10, y: 39, width: 300, height: 2), "full width, centered track")
    expectThumb(0, centerX: 15, "minimum covers left endpoint")
    expectThumb(50, centerX: 160, "midpoint")
    expectThumb(100, centerX: 305, "maximum covers right endpoint")
}
expectThumb(-10, centerX: 15, "below minimum")
expectThumb(110, centerX: 305, "above maximum")

slider.minimumValue = 2700
slider.maximumValue = 6500
expectThumb(2700, centerX: 15, "CCT minimum")
expectThumb(4600, centerX: 160, "CCT midpoint")
expectThumb(6500, centerX: 305, "CCT maximum")

slider.minimumValue = 0
slider.maximumValue = 100
slider.limitRange = 20...80
expectThumb(0, centerX: 73, "lower trim remains effective")
expectThumb(100, centerX: 247, "upper trim remains effective")
expectThumb(50, centerX: 160, "allowed value remains unchanged")
slider.limitRange = nil

slider.effectiveUserInterfaceLayoutDirection = .rightToLeft
expectThumb(0, centerX: 305, "RTL minimum")
expectThumb(100, centerX: 15, "RTL maximum")
slider.effectiveUserInterfaceLayoutDirection = .leftToRight

slider.minimumValue = 30
slider.maximumValue = 30
expectThumb(30, centerX: 15, "collapsed value range stays finite")
slider.minimumValue = 0
slider.maximumValue = 100
for width: CGFloat in [0, 4] {
    let smallBounds = CGRect(x: 10, y: 20, width: width, height: 40)
    let expected = CGRect(x: 10 + width / 2 - 20, y: 20, width: 40, height: 40)
    expect(thumb(0, in: smallBounds), expected, "narrow layout minimum")
    expect(thumb(100, in: smallBounds), expected, "narrow layout maximum")
}

// Old OS behavior and absent-image fallback still use the original superclass path.
slider.usesModernGeometry = false
slider.systemThumbWidth = 40
let legacyTrack = CGRect(x: 27, y: 37, width: 266, height: 2)
expect(slider.trackRect(forBounds: bounds), legacyTrack, "legacy track")
expect(thumb(0), CGRect(x: 12, y: 18, width: 40, height: 40), "legacy minimum")
expect(thumb(100), CGRect(x: 268, y: 18, width: 40, height: 40), "legacy maximum")

slider.usesModernGeometry = true
slider.currentThumbImage = nil
slider.normalThumbImage = nil
slider.systemThumbWidth = 72
expect(slider.trackRect(forBounds: bounds), legacyTrack, "no image track fallback")
expect(thumb(0), CGRect(x: 32, y: 18, width: 72, height: 40), "no image thumb fallback")
expect(slider.lastBounds, CGRect(x: 32, y: 18, width: 72, height: 40), "fallback label position")

// Gray trim segments must work with both direct and nested UIKit image views.
let trim = CustomDeviceSlider()
trim.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
trim.currentThumbImage = nil
let trackView = UIView()
trackView.frame = trim.bounds
trim.addSubview(trackView)
let thumbView = UIImageView(image: trim.normalThumbImage)
trim.addSubview(thumbView)
func updateTrim(_ range: ClosedRange<Int>?) {
    trim.limitRange = range
    let track = trim.trackRect(forBounds: trim.bounds)
    thumbView.frame = trim.thumbRect(forBounds: trim.bounds, trackRect: track, value: 50)
    trim.updateLimitUI()
}
func expectSegment(_ view: UIView, _ rect: CGRect?, host: UIView, _ label: String) {
    if let rect {
        expect(view.convert(view.bounds, to: trim), rect, label)
        guard view.superview === host else { fatalError("wrong trim host: " + label) }
    } else {
        guard view.superview == nil else { fatalError("stale trim segment: " + label) }
    }
    checks += 1
}
func expectBelowThumb(in host: UIView, thumbBranch: UIView) {
    let thumbIndex = host.subviews.firstIndex { $0 === thumbBranch }!
    for segment in [trim.minLineView, trim.maxLineView] where segment.superview != nil {
        guard host.subviews.firstIndex(where: { $0 === segment })! < thumbIndex else {
            fatalError("trim must stay below the thumb")
        }
        checks += 1
    }
}
updateTrim(1...83)
expectSegment(trim.minLineView, CGRect(x: 0, y: 19, width: 3, height: 2), host: trim, "direct low trim")
expectSegment(trim.maxLineView, CGRect(x: 249, y: 19, width: 51, height: 2), host: trim, "direct high trim")
expectBelowThumb(in: trim, thumbBranch: thumbView)

updateTrim(20...80)
expectSegment(trim.minLineView, CGRect(x: 0, y: 19, width: 60, height: 2), host: trim, "changed low trim")
expectSegment(trim.maxLineView, CGRect(x: 240, y: 19, width: 60, height: 2), host: trim, "changed high trim")
updateTrim(0...83)
expectSegment(trim.minLineView, nil, host: trim, "high trim only")
updateTrim(1...100)
expectSegment(trim.maxLineView, nil, host: trim, "low trim only")
for range: ClosedRange<Int>? in [0...100, nil, -10...120] {
    updateTrim(1...83)
    updateTrim(range)
    expectSegment(trim.minLineView, nil, host: trim, "clear low trim")
    expectSegment(trim.maxLineView, nil, host: trim, "clear high trim")
}

let container = UIView()
container.frame = CGRect(x: -10, y: -4, width: 320, height: 48)
container.bounds.origin = CGPoint(x: 3, y: 7)
trim.addSubview(container)
container.addSubview(thumbView)
updateTrim(1...83)
// thumbRect is expressed in slider coordinates; emulate UIKit's nested placement.
thumbView.frame = trim.convert(trim.lastBounds!, to: container)
trim.updateLimitUI()
expectSegment(trim.minLineView, CGRect(x: 0, y: 19, width: 3, height: 2), host: container, "nested low trim")
expectSegment(trim.maxLineView, CGRect(x: 249, y: 19, width: 51, height: 2), host: container, "nested high trim")
expectBelowThumb(in: container, thumbBranch: thumbView)

// A narrow, clipping thumb wrapper must not clip the full-width trim segments.
thumbView.removeFromSuperview()
container.removeFromSuperview()
let wrapper = UIView()
wrapper.frame = CGRect(x: 130, y: 0, width: 40, height: 40)
wrapper.clipsToBounds = true
trim.addSubview(wrapper)
wrapper.addSubview(thumbView)
updateTrim(1...83)
thumbView.frame = trim.convert(trim.lastBounds!, to: wrapper)
trim.updateLimitUI()
expectSegment(trim.maxLineView, CGRect(x: 249, y: 19, width: 51, height: 2), host: trim, "outside narrow wrapper")
expectBelowThumb(in: trim, thumbBranch: wrapper)

trim.addSubview(thumbView)
wrapper.removeFromSuperview()
// A rendered copy of the configured image can be identified by its frame and size.
thumbView.image = UIImage(size: CGSize(width: 40, height: 40))
updateTrim(1...83)
expectSegment(trim.maxLineView, CGRect(x: 249, y: 19, width: 51, height: 2), host: trim, "copied thumb image")
thumbView.removeFromSuperview()
trim.updateLimitUI()
expectSegment(trim.maxLineView, nil, host: trim, "missing thumb clears old overlays")
trim.addSubview(thumbView)
updateTrim(1...83)

trim.effectiveUserInterfaceLayoutDirection = .rightToLeft
updateTrim(1...83)
expectSegment(trim.minLineView, CGRect(x: 297, y: 19, width: 3, height: 2), host: trim, "RTL low trim")
expectSegment(trim.maxLineView, CGRect(x: 0, y: 19, width: 51, height: 2), host: trim, "RTL high trim")
trim.effectiveUserInterfaceLayoutDirection = .leftToRight
trim.frame.size.width = 600
updateTrim(1...83)
expectSegment(trim.maxLineView, CGRect(x: 498, y: 19, width: 102, height: 2), host: trim, "resize high trim")
trim.maximumValue = trim.minimumValue
updateTrim(1...83)
expectSegment(trim.minLineView, nil, host: trim, "empty range clears low trim")
expectSegment(trim.maxLineView, nil, host: trim, "empty range clears high trim")

// Legacy rendering retains its container and proportional widths.
trim.maximumValue = 100
trim.usesModernGeometry = false
trim.currentThumbImage = trim.normalThumbImage
trackView.addSubview(thumbView)
updateTrim(1...83)
expectSegment(trim.maxLineView, CGRect(x: 249, y: 17, width: 51, height: 2), host: trackView, "legacy high trim")
expectBelowThumb(in: trackView, thumbBranch: thumbView)

print("CustomDeviceSliderGeometryTests passed: \(checks) checks")
"""

with tempfile.TemporaryDirectory(prefix="slider-geometry-") as directory:
    fixture = Path(directory) / "main.swift"
    binary = Path(directory) / "SliderGeometryTests"
    fixture.write_text(swift)
    subprocess.run(["swiftc", str(fixture), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
