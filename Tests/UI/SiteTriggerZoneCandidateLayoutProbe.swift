#if DEBUG
import UIKit

/// Runs real production controls in an isolated, device-hosted application.
@MainActor
enum SiteTriggerZoneCandidateLayoutProbe {
    private final class FakeMeshTransport: SiteTriggerZoneMeshConnection.Transport {
        private let lock = NSLock()
        private var current: SiteTriggerZoneMeshConnection.Context?
        private var observer: (() -> Void)?
        private var calls: [String] = []

        var context: SiteTriggerZoneMeshConnection.Context? {
            lock.lock(); defer { lock.unlock() }
            return current
        }

        func connect(_ target: SiteTriggerZoneMeshConnection.Target) {
            lock.lock(); defer { lock.unlock() }
            calls.append("connect:" + target.spaceID)
            current = .init(meshUUID: target.meshUUID, networkID: target.networkID, connected: false)
        }

        func disconnect() {
            lock.lock(); defer { lock.unlock() }
            calls.append("disconnect")
            current = nil
        }

        func loadPrimary(meshUUID: String, networkID: String) {
            lock.lock(); defer { lock.unlock() }
            calls.append("primary")
            current = .init(meshUUID: meshUUID, networkID: networkID, connected: false)
        }

        func addObserver(_ observer: @escaping () -> Void) -> UUID {
            lock.lock(); defer { lock.unlock() }
            self.observer = observer
            return UUID()
        }

        func removeObserver(_ id: UUID?) {
            lock.lock(); defer { lock.unlock() }
            observer = nil
        }

        func simulate(_ target: SiteTriggerZoneMeshConnection.Target, connected: Bool) {
            lock.lock()
            current = .init(meshUUID: target.meshUUID, networkID: target.networkID, connected: connected)
            let callback = observer
            lock.unlock()
            callback?()
        }

        func count(_ call: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            return calls.filter { $0 == call }.count
        }
    }

    static func runConnectionSession() async -> [String] {
        let transport = FakeMeshTransport()
        let session = SiteTriggerZoneMeshConnection(primaryMeshUUID: "primary", primaryNetworkID: "0",
                                                    transport: transport, connectionTimeout: 0.25)
        let a = SiteTriggerZoneMeshConnection.Target(spaceID: "A", meshUUID: "mesh-a", networkID: "1")
        let b = SiteTriggerZoneMeshConnection.Target(spaceID: "B", meshUUID: "mesh-b", networkID: "2")
        let c = SiteTriggerZoneMeshConnection.Target(spaceID: "C", meshUUID: "mesh-c", networkID: "3")
        var failures: [String] = []
        func check(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
        func waitFor(_ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(1)
            while !condition(), Date() < deadline {
                try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
            }
            return condition()
        }

        session.select(a, autoConnect: false)
        check(session.phase == .idle && transport.count("connect:A") == 0, "Quick selection connected before Start")
        session.start()
        check(session.phase == .connecting, "Start did not enter Connecting")
        check(await waitFor { transport.count("connect:A") == 1 }, "A did not start connecting")
        transport.simulate(a, connected: true)
        check(await waitFor { session.phase == .connected }, "A did not become connected")
        session.select(a, autoConnect: false)
        check(session.phase == .connected, "Same Space selection lost the connection")

        session.select(b, autoConnect: false)
        check(session.phase == .idle, "Quick Space switch did not reset to Start")
        check(await waitFor { transport.count("primary") == 1 }, "Quick Space switch did not restore Primary")
        session.start()
        check(await waitFor { transport.count("connect:B") == 1 }, "B did not start connecting")
        transport.simulate(a, connected: true)
        try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        check(session.phase == .connecting, "Old Space callback completed the new Space")
        transport.simulate(b, connected: true)
        check(await waitFor { session.phase == .connected }, "B did not become connected")
        transport.simulate(b, connected: false)
        check(await waitFor { session.phase == .failed }, "Unexpected disconnect did not fail")
        session.retry()
        check(session.phase == .connecting, "Retry did not enter Connecting")
        check(await waitFor { transport.count("connect:B") == 2 }, "Retry did not reconnect")
        transport.simulate(b, connected: true)
        check(await waitFor { session.phase == .connected }, "Retry did not recover")

        session.select(c, autoConnect: false)
        check(await waitFor { transport.count("primary") == 2 }, "Second Space switch did not restore Primary")
        session.start()
        check(await waitFor { transport.count("connect:C") == 1 }, "C did not start connecting")
        check(await waitFor { session.phase == .failed }, "Connection timeout did not fail")
        transport.simulate(c, connected: true)
        try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        check(session.phase == .failed, "Late callback cleared failed state without Retry")
        session.retry()
        check(await waitFor { transport.count("connect:C") == 2 }, "Timeout Retry did not reconnect")
        session.select(a, autoConnect: true)
        check(await waitFor { transport.count("connect:A") == 2 }, "Trigger/Manual switch did not auto-connect new Space")
        transport.simulate(c, connected: true)
        try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        check(session.phase == .connecting, "Canceled Space callback completed current Space")
        transport.simulate(a, connected: true)
        check(await waitFor { session.phase == .connected }, "Auto-connected Space did not become connected")
        session.leave()
        check(session.phase == .idle, "Leaving did not clear connection state")
        check(await waitFor { transport.count("primary") == 3 }, "Leaving did not restore Primary")
        let result = failures.isEmpty ? "PASS" : failures.joined(separator: "\n")
        try? result.write(to: outputDirectory.appendingPathComponent("connection-state.txt"), atomically: true, encoding: .utf8)
        return failures
    }

    /// Run separately from the static probes, after the production page has appeared.
    static func runPanelAnimations(in controller: SiteTriggerZoneViewController) async -> [String] {
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        guard let content = controller.view as? SiteTriggerZoneContentView,
              let panel = descendants(content).compactMap({ $0 as? GroupPathSequenceDeviceAddView }).first,
              content.window != nil, UIView.areAnimationsEnabled else {
            return ["Animation probe requires a visible page with animations enabled"]
        }
        var failures: [String] = []
        func check(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
        func pause(_ seconds: Double) async {
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        func displayedFrame(_ view: UIView) -> CGRect { view.layer.presentation()?.frame ?? view.frame }
        func verifyMotion(_ name: String, action: () -> Void) async {
            let start = displayedFrame(panel)
            action()
            var samples: [CGRect] = []
            for _ in 0..<2 {
                await pause(0.08)
                let frame = displayedFrame(panel)
                samples.append(frame)
                check(abs(frame.maxY - start.maxY) < 1, name + ": panel bottom moved")
                check(abs(frame.minY - displayedFrame(content.tableView).maxY - 8) < 1,
                      name + ": list and panel did not move together")
            }
            await pause(0.2)
            let end = displayedFrame(panel)
            check(abs(end.minY - start.minY) > 1, name + ": height did not change")
            check(samples.contains { $0.minY > min(start.minY, end.minY) + 1 && $0.minY < max(start.minY, end.minY) - 1 },
                  name + ": no intermediate animation frame")
            check(abs(end.minY - panel.frame.minY) < 0.5, name + ": animation did not settle")
            check(abs(end.maxY - start.maxY) < 1, name + ": final bottom moved")
        }

        controller.perform(NSSelectorFromString("togglePreview"))
        defer { controller.perform(NSSelectorFromString("togglePreview")) }
        guard let zone = content.items.first(where: { $0.previewCode == "D02" }) else {
            return ["Animation probe must start from live mode"]
        }
        content.layoutIfNeeded()
        await pause(0.1)
        await verifyMotion("Select Item") { content.select?(zone.id) }
        check(!panel.isCollapsed, "Selected Item did not expand")
        await verifyMotion("Collapse arrow") { panel.perform(NSSelectorFromString("collapseBtnAction")) }
        check(panel.isCollapsed && abs(panel.frame.height - 44) < 0.5, "Collapse did not retain the 44pt header")
        await verifyMotion("Expand arrow") { panel.perform(NSSelectorFromString("collapseBtnAction")) }
        check(!panel.isCollapsed, "Arrow did not expand")

        panel.perform(NSSelectorFromString("collapseBtnAction"))
        await pause(0.08)
        await verifyMotion("Reverse collapse") { panel.perform(NSSelectorFromString("collapseBtnAction")) }
        check(!panel.isCollapsed, "Rapid reversal retained the wrong state")

        descendants(panel).compactMap { $0 as? WMMenuView }.first?.selectItem(at: 2)
        await pause(0.35)
        check(!panel.unfoldBtn.isHidden, "Manual fixture needs multiple device rows")
        if !panel.unfoldBtn.isHidden {
            await verifyMotion("Manual rows expand") { panel.unfoldBtn.sendActions(for: .touchUpInside) }
            await verifyMotion("Manual rows collapse") { panel.unfoldBtn.sendActions(for: .touchUpInside) }
        }
        return failures
    }

    static func runInteractions(in controller: SiteTriggerZoneViewController) -> [String] {
        var failures: [String] = []
        func check(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        guard let content = controller.view as? SiteTriggerZoneContentView,
              let panel = descendants(content).compactMap({ $0 as? GroupPathSequenceDeviceAddView }).first,
              let window = content.window else { return ["Missing production page"] }
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        controller.perform(NSSelectorFromString("togglePreview"))
        guard let zone = content.items.first(where: { $0.previewCode == "D02" }),
              let otherZone = content.items.first(where: { $0.previewCode == "S01" }) else { return ["Missing isolated preview fixtures"] }
        content.select?(zone.id)
        content.layoutIfNeeded()
        func selectMode(_ index: Int) {
            descendants(panel).compactMap { $0 as? WMMenuView }.first?.selectItem(at: index)
        }
        check(!panel.isCollapsed && !panel.quickAddView.isHidden, "Selection must open Quick add")
        let start = descendants(panel.quickAddView).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "site-zone-quick-start" }
        start?.sendActions(for: .touchUpInside)
        check(start?.isSelected == false, "Quick Start changed state")
        capture(window, name: "page-quick")
        selectMode(2)
        content.layoutIfNeeded()
        check(panel.manuallyAddView.displayedDeviceCount == 12, "Current Zone members must be excluded")
        func choose(_ selector: String, in view: UIView, row: Int, captureName: String) {
            view.perform(NSSelectorFromString(selector))
            guard let menu = window.subviews.compactMap({ $0 as? TitleSelectView }).last,
                  let table = descendants(menu).compactMap({ $0 as? UITableView }).first else {
                failures.append("Missing production menu: " + selector); return
            }
            menu.layoutIfNeeded()
            check(abs(table.rowHeight - 30) < 0.5, "Production menu row height must be 30pt")
            if selector == "groupFilterSelectAction",
               let source = descendants(view).first(where: { $0.accessibilityIdentifier == "site-zone-space-filter" }) {
                let sourceFrame = source.convert(source.bounds, to: window)
                let menuFrame = table.convert(table.bounds, to: window)
                check(abs(menuFrame.minX - sourceFrame.minX) < 0.5 && abs(menuFrame.maxX - sourceFrame.maxX) < 0.5,
                      "Production Space menu width does not match its control")
                check(abs(menuFrame.minY - sourceFrame.maxY - 4) < 0.5, "Production Space menu is not below its control")
            }
            if selector == "addTypeSelectAction",
               let source = descendants(view).first(where: { $0.accessibilityIdentifier == "site-zone-added-filter" }) {
                let sourceFrame = source.convert(source.bounds, to: window)
                let menuFrame = table.convert(table.bounds, to: window)
                check(abs(menuFrame.width - (isIPad ? 320 : 256)) < 0.5, "Production filter menu width differs from Space")
                check(abs(menuFrame.maxX - sourceFrame.maxX) < 0.5, "Production filter menu must align with its control's right edge")
                check(abs(menuFrame.minY - sourceFrame.maxY - 4) < 0.5, "Production filter menu must open below its control")
                check(abs(menuFrame.height - 60) < 0.5, "Production filter menu must show two 30pt rows")
            }
            capture(window, name: captureName)
            table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: row, section: 0))
            menu.removeFromSuperview()
            content.layoutIfNeeded()
        }
        choose("groupFilterSelectAction", in: panel.manuallyAddView, row: 3, captureName: "page-spaces")
        check(panel.manuallyAddView.displayedDeviceCount == 12, "Ignore must exclude members in another Site Zone")
        choose("addTypeSelectAction", in: panel.manuallyAddView, row: 1, captureName: "page-added-filter")
        for mode in 0..<3 {
            selectMode(mode)
            content.layoutIfNeeded()
            let active: UIView = [panel.quickAddView!, panel.triggerAddView!, panel.manuallyAddView!][mode]
            choose("addTypeSelectAction", in: active, row: 0, captureName: "page-filter-used-\(mode)")
            choose("addTypeSelectAction", in: active, row: 1, captureName: "page-filter-new-\(mode)")
        }
        let includedCount = 12 + otherZone.spaces[0].devices.count
        check(panel.manuallyAddView.displayedDeviceCount == includedCount, "Include added must combine new and other-Zone devices")
        capture(window, name: "page-manual")
        panel.unfoldBtn.sendActions(for: .touchUpInside)
        content.layoutIfNeeded()
        check(panel.manuallyAddView.rowNum > 1, "Manual expand control does not expand rows")
        capture(window, name: "page-manual-expanded")
        selectMode(1)
        content.layoutIfNeeded()
        check(panel.triggerAddView.devices.isEmpty, "Trigger must remain empty without Mesh")
        let filter = descendants(panel.triggerAddView).first { $0.accessibilityIdentifier == "site-zone-added-filter" }
        check(filter?.accessibilityLabel == "used".localizedString, "Modes must share the filter")
        capture(window, name: "page-trigger")
        content.select?(otherZone.id)
        selectMode(2)
        content.layoutIfNeeded()
        check(panel.manuallyAddView.displayedDeviceCount == 12, "Changing Zone must update the exclusion set")
        check(panel.manuallyAddView.selectDevice == nil, "Browsing must not make a member selection")
        if let navigation = controller.navigationController {
            func settleNavigation() {
                let deadline = Date().addingTimeInterval(1)
                repeat {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                } while navigation.transitionCoordinator != nil && Date() < deadline
                navigation.view.layoutIfNeeded()
            }
            for (index, titleKey) in ["quick_add", "trigger_add", "manually_add"].enumerated() {
                selectMode(index)
                content.layoutIfNeeded()
                let active: UIView = [panel.quickAddView!, panel.triggerAddView!, panel.manuallyAddView!][index]
                let selectedZone = content.selectedID
                let selectedSpace = descendants(active).first { $0.accessibilityIdentifier == "site-zone-space-filter" }?.accessibilityLabel
                let selectedFilter = descendants(active).first { $0.accessibilityIdentifier == "site-zone-added-filter" }?.accessibilityLabel
                active.perform(NSSelectorFromString("helpImageAction"))
                settleNavigation()
                if let help = navigation.topViewController as? GroupPathSequenceAddDescriptionController {
                    help.loadViewIfNeeded()
                    help.view.layoutIfNeeded()
                    check(help.navigationItem.title == titleKey.localizedString, "Help opened the wrong mode")
                    check(descendants(help.view).compactMap { $0 as? UILabel }.contains {
                        $0.text == "path_add_description_eligible_message_zone".localizedString
                    }, "Site must reuse the existing Zone help content")
                    capture(window, name: "page-help-\(index)")
                    help.perform(NSSelectorFromString("closeAction"))
                    settleNavigation()
                    content.layoutIfNeeded()
                    check(navigation.topViewController === controller, "Help did not return to Site")
                    check(content.selectedID == selectedZone && !active.isHidden, "Help changed the Zone or mode")
                    check(descendants(active).first { $0.accessibilityIdentifier == "site-zone-space-filter" }?.accessibilityLabel == selectedSpace,
                          "Help changed the selected Space")
                    check(descendants(active).first { $0.accessibilityIdentifier == "site-zone-added-filter" }?.accessibilityLabel == selectedFilter,
                          "Help changed the device filter")
                } else { failures.append("Site did not open the shared help page") }
            }
        } else { failures.append("Missing navigation controller for help validation") }
        controller.perform(NSSelectorFromString("togglePreview"))
        check(!content.items.contains { $0.previewCode != nil }, "Preview members escaped into live mode")
        let result = failures.isEmpty ? "PASS" : failures.joined(separator: "\n")
        try? result.write(to: outputDirectory.appendingPathComponent("interactions.txt"), atomically: true, encoding: .utf8)
        return failures
    }

    static func run(in host: UIView) -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        func visible(_ view: UIView, within root: UIView) -> Bool {
            var current: UIView? = view
            while let value = current, value !== root {
                if value.isHidden || value.alpha == 0 { return false }
                current = value.superview
            }
            return current != nil
        }
        let panel = GroupPathSequenceDeviceAddView()
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        panel.isSequence = false
        panel.contentHeightPolicy = .dynamicSelected
        panel.canAddDevice = false
        let root = SiteTriggerZoneContentView(panel: panel)
        var responder: UIResponder? = host
        while responder != nil && !(responder is UIViewController) { responder = responder?.next }
        guard let parent = responder as? UIViewController else { return ["Layout probe requires a view controller host"] }
        let container = UIViewController()
        container.view = root
        parent.addChild(container)
        host.addSubview(root)
        container.didMove(toParent: parent)
        defer {
            container.willMove(toParent: nil)
            root.removeFromSuperview()
            container.removeFromParent()
        }
        // Configure the shared production panel exactly as the Space selected-zone entry does.
        let spacePanel = GroupPathSequenceDeviceAddView()
        spacePanel.isSequence = false
        spacePanel.contentHeightPolicy = .dynamicSelected
        spacePanel.quickAddView.configureSpaceTriggerZoneQuickAdd(groupTitles: ["Group 1"], enabledStates: [true], selectedGroupIndex: 0, showAddedOnly: false)
        spacePanel.triggerAddView.configureSpaceTriggerZoneFilterLayout(groupTitles: ["Group 1"], enabledStates: [true], selectedGroupIndex: 0, showAddedOnly: false)
        spacePanel.manuallyAddView.configureSpaceTriggerZoneFilterLayout(groupTitles: ["Group 1"], enabledStates: [true], selectedGroupIndex: 0, showAddedOnly: false)
        spacePanel.canAddDevice = true
        spacePanel.setCollapsed(false)
        var spaceHeight: CGFloat = 290
        spacePanel.contentHeightChanged = { spaceHeight = $0 }
        host.insertSubview(spacePanel, belowSubview: root)
        defer { spacePanel.removeFromSuperview() }
        let zone = SiteTriggerZoneItemModel.empty(id: UUID(), name: "Zone 1", canEdit: true)
        panel.contentHeightChanged = { root.setPanelHeight($0) }
        root.render(items: [zone], selectedID: zone.id, canCreate: true, canSave: true)
        panel.updateHeaderIndex(1)
        let spaces: [GroupPathSequenceBrowseConfiguration.Space] = [
            .init(id: "disabled", title: "No Proximity Profile", enabled: false),
            .init(id: "ready", title: "A long Space name that should truncate safely", enabled: true)
        ]
        for size in [CGSize(width: 320, height: 568), CGSize(width: 393, height: 800), CGSize(width: 480, height: 480),
                     CGSize(width: 768, height: 800), CGSize(width: 393, height: 800)] {
            let width = size.width
            root.frame = CGRect(origin: .zero, size: size)
            spacePanel.frame = CGRect(origin: .zero, size: CGSize(width: width, height: spaceHeight))
            spacePanel.layoutIfNeeded()
            spacePanel.refreshPreferredHeight()
            spacePanel.frame.size.height = spaceHeight
            spacePanel.layoutIfNeeded()
            check(abs(spaceHeight - 290) < 0.5, "Space selected single-row baseline changed")
            capture(spacePanel, name: "space-reference-\(Int(width))")
            for scenario in ["devices", "empty-group", "no-spaces", "no-eligible", "no-permission", "unavailable", "devices"] {
                let selected: String? = ["devices", "empty-group"].contains(scenario) ? "ready" : nil
                let messageKey: String? = ["empty-group": "filter_no_devices", "no-eligible": "site_zone_assign_proximity_profile",
                                           "no-permission": "site_zone_editable_space_required", "unavailable": "site_zone_data_retry"][scenario]
                let configuration = GroupPathSequenceBrowseConfiguration(
                    spaces: scenario == "no-spaces" ? [] : spaces,
                    selectedSpaceID: selected,
                    placeholder: (scenario == "no-spaces" ? "site_zone_no_spaces" : "site_zone_no_eligible_spaces").localizedString,
                    includeAdded: true,
                    devices: scenario == "devices" ? (0..<24).map { .init(id: "device-\($0)", name: "Luminaire \($0)") } : [],
                    emptyMessage: messageKey?.localizedString,
                    unavailableMessage: messageKey?.localizedString,
                    selectSpace: { _ in }, changeFilter: { _ in }, retry: scenario == "unavailable" ? {} : nil)
                panel.configureBrowse(configuration)
                panel.setCollapsed(false)
                root.layoutIfNeeded()
                var basePanelHeight: CGFloat?
                for mode in 0..<3 {
                    descendants(panel).compactMap { $0 as? WMMenuView }.first?.selectItem(at: mode)
                    for rows in (mode == 2 && scenario == "devices" ? [1, 3] : [1]) {
                        panel.manuallyAddView.rowNum = rows
                        panel.refreshPreferredHeight()
                        root.setNeedsLayout()
                        root.layoutIfNeeded()
                        panel.layoutIfNeeded()
                        let context = "Candidate \(width) \(scenario) mode=\(mode) rows=\(rows)"
                        let requiredContentHeight = max(160, panel.quickAddView.preferredContentHeight,
                                                        panel.triggerAddView.preferredContentHeight,
                                                        panel.manuallyAddView.preferredContentHeight)
                        for bottomInset: CGFloat in [0, 34, 20, 0] {
                            container.additionalSafeAreaInsets.bottom = bottomInset
                            root.setNeedsLayout()
                            root.layoutIfNeeded()
                            check(root.safeAreaInsets.bottom >= bottomInset, context + ": additional safe area was not applied")
                            let expectedGap = max(root.safeAreaInsets.bottom, SCRYFrom(16))
                            check(abs(root.bounds.maxY - panel.frame.maxY - expectedGap) < 0.5,
                                  context + ": bottom spacing differs from Space rule")
                            check(abs(panel.frame.minY - root.tableView.frame.maxY - 8) < 0.5,
                                  context + ": list spacing changed")
                            check(abs(panel.bounds.height - (104 + requiredContentHeight)) < 0.5,
                                  context + ": panel content was compressed or padded")
                        }
                        if rows == 1 && abs(requiredContentHeight - 186) < 0.5 {
                            check(abs(panel.bounds.height - spacePanel.bounds.height) < 0.5,
                                  context + ": ordinary height differs from Space")
                        }
                        if rows == 1 {
                            if let basePanelHeight { check(abs(panel.bounds.height - basePanelHeight) < 0.5, context + ": switching mode changed panel height") }
                            else { basePanelHeight = panel.bounds.height }
                        }
                        let active: UIView = [panel.quickAddView!, panel.triggerAddView!, panel.manuallyAddView!][mode]
                        let activeFrame = active.convert(active.bounds, to: panel)
                        let spaceContentFrame = spacePanel.quickAddView.convert(spacePanel.quickAddView.bounds, to: spacePanel)
                        check(abs((panel.bounds.maxY - activeFrame.maxY) - (spacePanel.bounds.maxY - spaceContentFrame.maxY)) < 0.5,
                              context + ": content bottom spacing differs from Space")
                        let footer = descendants(panel.quickAddView).compactMap { $0 as? UILabel }.first {
                            $0.accessibilityIdentifier == "site-zone-quick-footer"
                        }
                        check(footer.map { visible($0, within: panel) } == (mode == 0), context + ": wrong Quick footer visibility")
                        if mode == 0, let footer {
                            let frame = footer.convert(footer.bounds, to: active)
                            check(footer.text == "path_quick_add_message".localizedString, context + ": missing localized Quick footer")
                            check(footer.font.pointSize == 12 && footer.textColor == SubText_Color && footer.textAlignment == .center,
                                  context + ": incorrect Quick footer style")
                            check(abs(frame.maxY - (active.bounds.height - 6)) < 0.5, context + ": Quick footer must stay at bottom")
                            for control in descendants(active) where visible(control, within: active) &&
                                ["site-zone-quick-start", "site-zone-quick-message"].contains(control.accessibilityIdentifier ?? "") {
                                check(control.convert(control.bounds, to: active).maxY + 11.5 <= frame.minY,
                                      context + ": Quick footer overlaps content")
                            }
                        }
                        for child in descendants(active) where visible(child, within: active) {
                            check(!child.hasAmbiguousLayout, context + ": ambiguous \(type(of: child))")
                            if let label = child as? UILabel, let text = label.text, !text.isEmpty, let parent = label.superview {
                                check(parent.bounds.insetBy(dx: -1, dy: -1).contains(label.frame), context + ": text outside \(text)")
                                if label.numberOfLines == 0 {
                                    check(label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height <= label.bounds.height + 1,
                                          context + ": clipped \(text)")
                                }
                            }
                        }
                        let filters = descendants(active).filter { $0.accessibilityIdentifier?.hasSuffix("-filter") == true }
                        check(filters.count == 2, context + ": missing filters")
                        if filters.count == 2 { check(!filters[0].frame.intersects(filters[1].frame), context + ": overlapping filters") }
                        let hint = descendants(active).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "site-zone-proximity-hint" }
                        let shouldShowHint = mode != 2 && selected != nil
                        check(hint.map { visible($0, within: active) } == shouldShowHint || (hint == nil && !shouldShowHint),
                              context + ": wrong proximity hint visibility")
                        if shouldShowHint, let hint {
                            let hintFrame = hint.convert(hint.bounds, to: active)
                            check(hint.text == "space_trigger_zone_quick_add_hint".localizedString, context + ": missing localized hint")
                            check(!hint.isUserInteractionEnabled, context + ": hint retained Retry action")
                            check(hint.textColor == AssistText_Color && hint.font.pointSize == 12, context + ": incorrect hint style")
                            check(filters.allSatisfy { hintFrame.minY >= $0.convert($0.bounds, to: active).maxY + 7.5 },
                                  context + ": hint overlaps filters")
                            if mode == 0, let start = descendants(active).first(where: { $0.accessibilityIdentifier == "site-zone-quick-start" }) {
                                check(start.convert(start.bounds, to: active).minY >= hintFrame.maxY + 15.5, context + ": hint overlaps Start")
                            }
                            if mode == 1, let message = descendants(active).compactMap({ $0 as? UILabel }).first(where: { $0.text == "site_zone_not_connected".localizedString }) {
                                check(message.convert(message.bounds, to: active).minY >= hintFrame.maxY + 11.5, context + ": hint overlaps connection status")
                            }
                        }
                        if mode == 0, let start = descendants(active).first(where: { $0.accessibilityIdentifier == "site-zone-quick-start" }) as? UIButton {
                            start.sendActions(for: .touchUpInside)
                            check(!start.isSelected, context + ": Start must remain idle")
                            let state = descendants(active).compactMap { $0 as? UILabel }.first { $0.text == "click_to_start".localizedString }
                            if !start.isHidden, let state {
                                check(!start.convert(start.bounds, to: active).intersects(state.convert(state.bounds, to: active)), context + ": Start overlaps its label")
                            }
                        }
                        if mode == 2, let collection = descendants(active).compactMap({ $0 as? UICollectionView }).first {
                            check(!collection.allowsSelection, context + ": candidate selection is enabled")
                            if scenario == "devices" {
                                collection.delegate?.collectionView?(collection, didSelectItemAt: IndexPath(item: 0, section: 0))
                                check(panel.manuallyAddView.selectDevice == nil, context + ": Manual creates selection")
                                for cell in collection.visibleCells {
                                    check(cell.accessibilityTraits == .staticText && !cell.isSelected, context + ": interactive candidate")
                                    check(!cell.interactions.contains { $0 is UIDragInteraction }, context + ": draggable candidate")
                                }
                            }
                        }
                        if mode == 1 {
                            let collection = descendants(active).compactMap { $0 as? UICollectionView }.first
                            check(collection?.numberOfItems(inSection: 0) == 0, context + ": Trigger has offline candidates")
                        }
                        if width == 393 {
                            capture(root, name: "\(scenario)-mode-\(mode)-rows-\(rows)")
                        }
                    }
                }
                panel.setCollapsed(true)
                root.layoutIfNeeded()
                check(abs(panel.bounds.height - 44) < 0.5, "Collapsed panel must retain the 44pt header")
                check(abs(root.bounds.maxY - panel.frame.maxY - max(root.safeAreaInsets.bottom, SCRYFrom(16))) < 0.5,
                      "Collapsed panel bottom must match the expanded panel")
                panel.clearBrowseTarget()
                panel.setCollapsed(false)
                root.layoutIfNeeded()
                for mode in 0..<3 {
                    descendants(panel).compactMap { $0 as? WMMenuView }.first?.selectItem(at: mode)
                    root.layoutIfNeeded()
                    let active: UIView = [panel.quickAddView!, panel.triggerAddView!, panel.manuallyAddView!][mode]
                    let hints = descendants(active).filter { $0.accessibilityIdentifier == "site-zone-proximity-hint" }
                    check(hints.allSatisfy { !visible($0, within: active) }, "Guide retained the browsing hint")
                }
            }
        }
        for width: CGFloat in [320, 393, 768] {
            root.frame = CGRect(x: 0, y: 0, width: width, height: 800)
            for phase: GroupPathSequenceBrowseConfiguration.ConnectionPhase in [.connecting, .failed, .connected] {
                var retryCount = 0
                var configuration = GroupPathSequenceBrowseConfiguration(
                    spaces: spaces, selectedSpaceID: "ready", placeholder: "", includeAdded: false,
                    devices: (0..<8).map { .init(id: "device-\($0)", name: "Device \($0)") },
                    emptyMessage: nil, unavailableMessage: nil,
                    selectSpace: { _ in }, changeFilter: { _ in }, retry: nil)
                configuration.connectionPhase = phase
                configuration.quickConnectionActive = true
                configuration.startConnection = {}
                configuration.retryConnection = { retryCount += 1 }
                panel.configureBrowse(configuration)
                panel.setCollapsed(false)
                root.layoutIfNeeded()
                for mode in 0..<3 {
                    descendants(panel).compactMap { $0 as? WMMenuView }.first?.selectItem(at: mode)
                    panel.refreshPreferredHeight()
                    root.layoutIfNeeded()
                    let active: UIView = [panel.quickAddView!, panel.triggerAddView!, panel.manuallyAddView!][mode]
                    let context = "Connection \(width) \(phase) mode=\(mode)"
                    guard let status = descendants(panel).compactMap({ $0 as? GroupPathSequenceConnectionStatusView }).first else {
                        failures.append(context + ": status view missing")
                        continue
                    }
                    let shouldShow = true
                    check(visible(status, within: panel) == shouldShow, context + ": status visibility")
                    if shouldShow {
                        let card = status.superview!
                        let frame = status.convert(status.bounds, to: card)
                        check(card.bounds.contains(frame), context + ": status outside card")
                        if let hint = descendants(active).first(where: { $0.accessibilityIdentifier == "site-zone-proximity-hint" }),
                           visible(hint, within: active) {
                            check(hint.convert(hint.bounds, to: panel).maxY + 4 <= status.convert(status.bounds, to: panel).minY,
                                  context + ": status overlaps proximity hint")
                        }
                        for label in descendants(status).compactMap({ $0 as? UILabel }) where !label.isHidden {
                            let labelFrame = label.convert(label.bounds, to: status)
                            check(status.bounds.contains(labelFrame), context + ": status text clipped")
                        }
                    }
                    let retry = descendants(status).compactMap({ $0 as? UIButton }).first { $0.accessibilityIdentifier == "site-zone-connection-retry" }
                    check(retry?.isHidden == (phase != .failed), context + ": Retry visibility")
                    if phase == .failed, mode == 0 {
                        retry?.sendActions(for: .touchUpInside)
                        check(retryCount == 1, context + ": Retry callback")
                    }
                    if mode == 0 {
                        let start = descendants(panel.quickAddView).compactMap({ $0 as? UIButton }).first { $0.accessibilityIdentifier == "site-zone-quick-start" }
                        check(start?.isHidden == true, context + ": Start visible over connection feedback")
                        let footer = descendants(panel.quickAddView).first { $0.accessibilityIdentifier == "site-zone-quick-footer" }
                        check(footer.map { visible($0, within: panel) } == true, context + ": Quick footer hidden")
                    } else if mode == 2 {
                        check(descendants(active).compactMap({ $0 as? UIPageControl }).allSatisfy(\.isHidden),
                              context + ": inactive Manual pagination visible")
                    }
                    if width == 393 { capture(root, name: "connection-\(phase)-mode-\(mode)") }
                }
            }
        }
        if let window = host.window {
            let source = UIView()
            window.addSubview(source)
            defer { source.removeFromSuperview() }
            var selectedID: String?
            var included: Bool?
            let config = GroupPathSequenceBrowseConfiguration(spaces: spaces + (0..<12).map { .init(id: "s\($0)", title: "Space \($0)", enabled: true) },
                selectedSpaceID: "ready", placeholder: "", includeAdded: false, devices: [], emptyMessage: nil, unavailableMessage: nil,
                selectSpace: { selectedID = $0 }, changeFilter: { included = $0 }, retry: nil)
            for width: CGFloat in [100, 186, 260] {
                source.frame = CGRect(x: window.bounds.width - width - 32, y: window.bounds.height - 180, width: width, height: 30)
                for count in [1, 2, 8, 14] {
                    selectedID = nil
                    let menuConfig = GroupPathSequenceBrowseConfiguration(spaces: Array(config.spaces.prefix(count)),
                        selectedSpaceID: "ready", placeholder: "", includeAdded: false, devices: [], emptyMessage: nil, unavailableMessage: nil,
                        selectSpace: { selectedID = $0 }, changeFilter: { _ in }, retry: nil)
                    menuConfig.showSpaces(from: source)
                    if let menu = window.subviews.compactMap({ $0 as? TitleSelectView }).last,
                       let table = descendants(menu).compactMap({ $0 as? UITableView }).first {
                        menu.layoutIfNeeded()
                        let safe = window.bounds.inset(by: window.safeAreaInsets)
                        let frame = table.convert(table.bounds, to: window)
                        let anchor = source.convert(source.bounds, to: window)
                        check(safe.contains(frame), "Space menu leaves the safe area")
                        check(abs(frame.minX - anchor.minX) < 0.5 && abs(frame.maxX - anchor.maxX) < 0.5, "Space menu is not aligned and equal width")
                        check(abs(frame.minY - anchor.maxY - 4) < 0.5, "Space menu must open below its control")
                        check(abs(table.rowHeight - 30) < 0.5, "Space menu row height must be 30pt")
                        check(abs(frame.height - min(CGFloat(min(count, 8)) * 30, safe.maxY - 8 - anchor.maxY - 4)) < 0.5,
                              "Space menu height must use 30pt rows and the available space below")
                        check(table.isScrollEnabled == (CGFloat(count) * 30 > frame.height), "Space menu scrolling does not match its available height")
                        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))
                        check(selectedID == nil, "Disabled Space callback was accepted")
                        capture(window, name: "space-menu-\(Int(width))-\(count)")
                        if count > 1 {
                            table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 1, section: 0))
                            check(selectedID == "ready", "Enabled Space callback missing")
                        }
                        menu.removeFromSuperview()
                    } else { failures.append("Space menu missing") }
                }
            }
            let safe = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: 8, dy: 8)
            for available: CGFloat in [120, 35, 29] {
                for showsSpaces in [false, true] {
                    source.frame = CGRect(x: safe.maxX - 120, y: safe.maxY - available - 34, width: 100, height: 30)
                    if showsSpaces { config.showSpaces(from: source) } else { config.showFilter(from: source) }
                    let menu = window.subviews.compactMap({ $0 as? TitleSelectView }).last
                    if available < 30 {
                        check(menu == nil, "Menu must not open above when less than one row fits below")
                        menu?.removeFromSuperview()
                        continue
                    }
                    guard let menu, let table = descendants(menu).compactMap({ $0 as? UITableView }).first else {
                        failures.append("Menu missing despite room for a 30pt row"); continue
                    }
                    menu.layoutIfNeeded()
                    let frame = table.convert(table.bounds, to: window)
                    let anchor = source.convert(source.bounds, to: window)
                    check(abs(table.rowHeight - 30) < 0.5, "Both menus must use 30pt rows")
                    check(abs(frame.minY - anchor.maxY - 4) < 0.5, "Menu must stay below its control when space is limited")
                    check(safe.contains(frame), "Menu leaves the safe area")
                    if !showsSpaces {
                        check(abs(frame.width - min(isIPad ? 320 : 256, safe.width)) < 0.5, "Filter menu width differs from Space")
                        check(abs(frame.maxX - anchor.maxX) < 0.5, "Filter menu must be right aligned")
                        check(abs(frame.height - min(60, available)) < 0.5, "Filter menu height must fit below")
                        check(table.isScrollEnabled == (available < 60), "Filter menu must scroll only when needed")
                        check(table.numberOfRows(inSection: 0) == 2, "Filter menu must have two choices")
                        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 1, section: 0))
                        check(included == true, "Include other Zones callback missing")
                    }
                    capture(window, name: "menu-\(showsSpaces ? "spaces" : "filter")-\(Int(available))")
                    menu.removeFromSuperview()
                }
            }
        }
        let result = failures.isEmpty ? "PASS" : failures.joined(separator: "\n")
        try? result.write(to: outputDirectory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        return failures
    }

    static func runStage2(in host: UIView) -> [String] {
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        var failures: [String] = []
        func check(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
        let panel = GroupPathSequenceDeviceAddView()
        panel.isSequence = false
        panel.contentHeightPolicy = .dynamicSelected
        panel.canAddDevice = false
        let root = SiteTriggerZoneContentView(panel: panel)
        var responder: UIResponder? = host
        while responder != nil && !(responder is UIViewController) { responder = responder?.next }
        guard let parent = responder as? UIViewController else { return ["Stage 2 probe requires a controller"] }
        let container = UIViewController()
        container.view = root
        parent.addChild(container)
        host.addSubview(root)
        container.didMove(toParent: parent)
        defer {
            container.willMove(toParent: nil)
            root.removeFromSuperview()
            container.removeFromParent()
        }
        panel.contentHeightChanged = { root.setPanelHeight($0) }
        let zoneID = UUID()
        var item = SiteTriggerZoneItemModel(id: zoneID, name: "Zone 1")
        item.spaces = [
            .init(id: "space-A", name: "A very long Space name that should truncate safely", access: .owner,
                  devices: [.init(id: "node-A", name: "A very long device name that should truncate safely")]),
            .init(id: "space-B", name: "Space B", access: .editor,
                  devices: [.init(id: "node-B", name: "Device B")])
        ]
        item.sync.devices = .pending
        item.hasUnsavedChanges = true
        root.render(items: [item], selectedID: zoneID, canCreate: true, canSave: true)
        panel.updateHeaderIndex(1)
        let candidates = [GroupPathSequenceBrowseConfiguration.Device(id: "space-A-node-C", name: "A very long candidate device name"),
                          .init(id: "space-A-node-D", name: "Device D")]
        for width: CGFloat in [320, 393, 768] {
            root.frame = CGRect(x: 0, y: 0, width: width, height: 800)
            var selections: [String] = []
            var quickChanges: [QuickAddState] = []
            var configuration = GroupPathSequenceBrowseConfiguration(
                spaces: [.init(id: "space-A", title: "A very long Space name that should truncate safely", enabled: true)],
                selectedSpaceID: "space-A", placeholder: "", includeAdded: false,
                devices: candidates, emptyMessage: nil, unavailableMessage: nil,
                selectSpace: { _ in }, changeFilter: { _ in }, retry: nil)
            configuration.connectionPhase = .connected
            configuration.quickState = .adding
            configuration.connectedNoticeKey = ""
            configuration.triggerDevices = candidates
            configuration.selectedDeviceID = candidates[0].id
            configuration.selectDevice = { selections.append($0) }
            configuration.changeQuickState = { quickChanges.append($0) }
            panel.configureBrowse(configuration)
            panel.setCollapsed(false)
            root.layoutIfNeeded()
            let context = "Stage 2 \(Int(width))pt"
            let status = descendants(panel).compactMap { $0 as? GroupPathSequenceConnectionStatusView }.first
            check(status?.isHidden == true, context + ": connected overlay obstructs candidates")
            check(!panel.hasAmbiguousLayout, context + ": panel has ambiguous constraints")
            check(!root.tableView.hasAmbiguousLayout, context + ": list has ambiguous constraints")
            check(root.tableView.frame.maxY + 8 <= panel.frame.minY + 0.5,
                  context + ": list overlaps add panel")
            let start = descendants(panel.quickAddView).compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == "site-zone-quick-start" }
            let stop = descendants(panel.quickAddView).compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == "site-zone-quick-stop" }
            check(start?.isHidden == false && stop?.isHidden == false,
                  context + ": Adding controls are missing")
            start?.sendActions(for: .touchUpInside)
            stop?.sendActions(for: .touchUpInside)
            check(quickChanges.count == 2 && quickChanges[0] == .pause && quickChanges[1] == .stop,
                  context + ": Pause/Stop callbacks are incorrect")
            let menu = descendants(panel).compactMap { $0 as? WMMenuView }.first
            menu?.selectItem(at: 1)
            root.layoutIfNeeded()
            let trigger = descendants(panel.triggerAddView).compactMap { $0 as? UICollectionView }.first
            check(trigger?.numberOfItems(inSection: 0) == 2 && trigger?.isHidden == false,
                  context + ": Trigger candidates are not visible")
            if let trigger {
                check(trigger.convert(trigger.bounds, to: panel).maxY + 4 <= panel.bounds.maxY,
                      context + ": Trigger candidates are clipped by the panel")
            }
            trigger?.delegate?.collectionView?(trigger!, didSelectItemAt: IndexPath(item: 0, section: 0))
            menu?.selectItem(at: 2)
            root.layoutIfNeeded()
            let manual = descendants(panel.manuallyAddView).compactMap { $0 as? UICollectionView }.first
            check(manual?.allowsSelection == true && manual?.numberOfItems(inSection: 0) == 2,
                  context + ": Manual candidates are not selectable")
            manual?.delegate?.collectionView?(manual!, didSelectItemAt: IndexPath(item: 1, section: 0))
            check(selections == [candidates[0].id, candidates[1].id], context + ": candidate callbacks crossed modes")
            for view in descendants(panel) where !view.isHidden && view.bounds.width > 0 {
                check(!view.hasAmbiguousLayout, context + ": ambiguous \(type(of: view))")
            }
            if width == 393 { capture(root, name: "stage2-connected-nonempty") }
        }
        let result = failures.isEmpty ? "PASS" : failures.joined(separator: "\n")
        try? result.write(to: outputDirectory.appendingPathComponent("stage2-result.txt"), atomically: true, encoding: .utf8)
        return failures
    }

    private static var outputDirectory: URL {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CandidateProbe-" + language)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func capture(_ view: UIView, name: String) {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { view.layer.render(in: $0.cgContext) }
        try? image.pngData()?.write(to: outputDirectory.appendingPathComponent(name + ".png"))
    }
}
#endif
