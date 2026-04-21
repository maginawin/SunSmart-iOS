//
//  PJUIDebugConsoleTracer.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/7.
//

import Foundation
import UIKit
import ObjectiveC.runtime


enum PJUIDebugConsoleTracer {

    private static var started = false
    private static var windowObserver: NSObjectProtocol?

    
    static func start() {
        guard !started else { return }
        started = true

        UIViewController.pj_enableDebugAppearTrace()
        UIControl.pj_enableDebugActionTrace()

        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? UIWindow else { return }
            installTapProbeIfNeeded(on: window)
        }

        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .filter(\.isKeyWindow)
                .forEach { installTapProbeIfNeeded(on: $0) }
        }

        log("started")
    }

   
    static func stop() {
        started = false

        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }

        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { window in
                if let probe = objc_getAssociatedObject(window, &AssociatedKeys.windowTapProbe) as? PJWindowTapProbe {
                    window.removeGestureRecognizer(probe)
                    objc_setAssociatedObject(window, &AssociatedKeys.windowTapProbe, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            }

        log("stopped")
    }

    fileprivate static func logControllerEnter(_ viewController: UIViewController) {
        guard started else { return }

        let navigation = viewController.navigationController.map { String(describing: type(of: $0)) } ?? "nil"
        let tabBar = viewController.tabBarController.map { String(describing: type(of: $0)) } ?? "nil"
        log("enter controller=\(String(describing: type(of: viewController))) nav=\(navigation) tab=\(tabBar)")
    }

    fileprivate static func logControlAction(control: UIControl, action: Selector, target: Any?) {
        guard started else { return }

        let targetName = target.map { String(describing: type(of: $0)) } ?? "nil"
        log("control action=\(NSStringFromSelector(action)) control=\(describe(view: control)) target=\(targetName)")
    }

    fileprivate static func logTappedView(_ view: UIView) {
        guard started else { return }
        log("tap view=\(describe(view: view)) path=\(viewPath(for: view))")
    }

    private static func installTapProbeIfNeeded(on window: UIWindow) {
        guard objc_getAssociatedObject(window, &AssociatedKeys.windowTapProbe) as? PJWindowTapProbe == nil else {
            return
        }

        let probe = PJWindowTapProbe { touchedView in
            logTappedView(touchedView)
        }
        window.addGestureRecognizer(probe)
        objc_setAssociatedObject(window, &AssociatedKeys.windowTapProbe, probe, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func describe(view: UIView) -> String {
        let typeName = String(describing: type(of: view))
        let frame = "frame=\(NSCoder.string(for: view.frame))"
        let address = String(format: "%p", unsafeBitCast(view, to: Int.self))
        let accessibility = view.accessibilityIdentifier ?? "nil"
        return "\(typeName)(\(frame), accessibilityIdentifier=\(accessibility), addr=\(address))"
    }

    private static func viewPath(for view: UIView) -> String {
        var items: [String] = [String(describing: type(of: view))]
        var current = view.superview
        while let currentView = current {
            items.append(String(describing: type(of: currentView)))
            current = currentView.superview
        }
        return items.reversed().joined(separator: " -> ")
    }

    private static func log(_ message: String) {
        print("[PJUIDebug] \(message)")
    }

    private enum AssociatedKeys {
        static var windowTapProbe: UInt8 = 0
    }
}


private final class PJWindowTapProbe: UITapGestureRecognizer, UIGestureRecognizerDelegate {

    private let onTap: (UIView) -> Void

    init(onTap: @escaping (UIView) -> Void) {
        self.onTap = onTap
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handleTap))
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    @objc
    private func handleTap() {
        guard let view,
              let touchedView = view.hitTest(location(in: view), with: nil) else {
            return
        }
        onTap(touchedView)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private extension UIViewController {

    static func pj_enableDebugAppearTrace() {
        struct Holder {
            static var didSwizzle = false
        }
        guard !Holder.didSwizzle else { return }
        Holder.didSwizzle = true

        let original = #selector(viewDidAppear(_:))
        let swizzled = #selector(pj_debug_viewDidAppear(_:))
        swizzleInstanceMethod(self, original: original, swizzled: swizzled)
    }

    @objc
    func pj_debug_viewDidAppear(_ animated: Bool) {
        self.pj_debug_viewDidAppear(animated)
        PJUIDebugConsoleTracer.logControllerEnter(self)
    }
}

private extension UIControl {

    static func pj_enableDebugActionTrace() {
        struct Holder {
            static var didSwizzle = false
        }
        guard !Holder.didSwizzle else { return }
        Holder.didSwizzle = true

        let original = #selector(sendAction(_:to:for:))
        let swizzled = #selector(pj_debug_sendAction(_:to:for:))
        swizzleInstanceMethod(self, original: original, swizzled: swizzled)
    }

    @objc
    func pj_debug_sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        PJUIDebugConsoleTracer.logControlAction(control: self, action: action, target: target)
        self.pj_debug_sendAction(action, to: target, for: event)
    }
}

private func swizzleInstanceMethod(_ cls: AnyClass, original: Selector, swizzled: Selector) {
    guard
        let originalMethod = class_getInstanceMethod(cls, original),
        let swizzledMethod = class_getInstanceMethod(cls, swizzled)
    else {
        return
    }

    let didAddMethod = class_addMethod(
        cls,
        original,
        method_getImplementation(swizzledMethod),
        method_getTypeEncoding(swizzledMethod)
    )

    if didAddMethod {
        class_replaceMethod(
            cls,
            swizzled,
            method_getImplementation(originalMethod),
            method_getTypeEncoding(originalMethod)
        )
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}
