#if DEBUG
import UIKit

/// Run in a device-hosted test app using the production views and resources.
/// This is intentionally not a member of any shipping target.
@MainActor
enum SiteTriggerZoneItemLayoutProbe {
    static func run(in host: UIView) -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        func descendants(_ view: UIView) -> [UIView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        func inspect(_ view: UIView, context: String) {
            for child in descendants(view) where !child.isHidden {
                check(!child.hasAmbiguousLayout, "\(context): ambiguous \(type(of: child)) \((child as? UILabel)?.text ?? "")")
                if let image = child as? UIImageView {
                    check(image.image != nil, "\(context): missing image \(image.accessibilityIdentifier ?? "")")
                }
                if let label = child as? UILabel, let parent = label.superview {
                    check(parent.bounds.insetBy(dx: -1, dy: -1).contains(label.frame), "\(context): label outside container: \(label.text ?? "")")
                    if label.numberOfLines == 0 {
                        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
                        check(needed <= label.bounds.height + 1, "\(context): clipped multiline text")
                    }
                }
            }
        }
        let fixtures = SiteTriggerZonePreviewFixtures.makeItems { "\("zone".localizedString) \($0)" }
        let cell = SiteTriggerZoneItemCell(style: .default, reuseIdentifier: "probe")
        let header = SiteTriggerZoneItemHeaderView(reuseIdentifier: "probe-header")
        host.addSubview(cell)
        host.addSubview(header)
        defer { cell.removeFromSuperview(); header.removeFromSuperview() }

        // The same reused views are repeatedly resized; this catches stale grids and constraints.
        for width: CGFloat in [288, 351, 398, 736, 480, 320, 351] {
            let referenceContent = SiteTriggerZoneContentView(panel: UIView())
            let empty = SiteTriggerZoneItemModel.empty(id: UUID(), name: "Reference", canEdit: true)
            referenceContent.render(items: [empty], selectedID: empty.id, canCreate: false, canSave: true)
            let referenceHeader = referenceContent.tableView(referenceContent.tableView, viewForHeaderInSection: 0) as! GroupPathSequencePathHeaderView
            host.addSubview(referenceHeader)
            referenceHeader.frame = CGRect(x: 0, y: 0, width: width, height: 40)
            referenceHeader.setNeedsLayout()
            referenceHeader.layoutIfNeeded()
            let referenceName = referenceHeader.nameLabel.convert(referenceHeader.nameLabel.bounds, to: referenceHeader)
            let referenceButtons = [referenceHeader.testBtn!, referenceHeader.resetBtn!, referenceHeader.deleteBtn!, referenceHeader.saveBtn!]
            let referenceFrames = referenceButtons.map { $0.convert($0.bounds, to: referenceHeader) }
            referenceHeader.removeFromSuperview()
            for item in fixtures where !item.usesEmptyStyle {
                var unselectedName: CGRect?
                var unselectedCellHeight: CGFloat?
                for selected in [false, true] {
                    let context = "\(item.previewCode ?? "") width=\(width) selected=\(selected)"
                    cell.configure(item, selected: selected, width: width)
                    let size = cell.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required,
                                                          verticalFittingPriority: .fittingSizeLevel)
                    check(size.height.isFinite && size.height > 32, "\(context): invalid cell height")
                    if selected {
                        check(abs(size.height - (unselectedCellHeight ?? 0)) < 0.5, "\(context): selection changes card height")
                    } else { unselectedCellHeight = size.height }
                    cell.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
                    cell.setNeedsLayout()
                    cell.layoutIfNeeded()
                    inspect(cell.contentView, context: context)
                    let all = descendants(cell.contentView)
                    let dividers = all.filter { $0.accessibilityIdentifier?.hasPrefix("site-zone-divider-") == true }
                    check(dividers.count == item.spaces.count - 1, "\(context): divider count")
                    let locks = all.filter { $0.accessibilityIdentifier == "site-zone-lock" }
                    check(locks.count == (item.canEdit ? 0 : item.spaces.count), "\(context): whole-Zone locks")
                    let devices = all.filter { $0.accessibilityIdentifier?.hasPrefix("site-zone-device-") == true }
                    check(devices.count == item.spaces.filter(\.canDisplayDevices).reduce(0) { $0 + $1.devices.count }, "\(context): restricted devices leaked")
                    if width == 351 && item.previewCode == "S01" {
                        check(abs(size.height - 120) < 1, "Single Space Figma reference height: \(size.height)")
                    }
                    header.configure(item, selected: selected, width: width, actionsEnabled: true)
                    header.frame = CGRect(x: 0, y: 0, width: width, height: 40)
                    header.setNeedsLayout()
                    header.layoutIfNeeded()
                    inspect(header.contentView, context: context + " header")
                    let name = descendants(header.contentView).first { $0.accessibilityIdentifier == "site-zone-item-name" }!
                    let nameFrame = name.convert(name.bounds, to: header)
                    check(abs(nameFrame.minX - referenceName.minX) < 0.5 && abs(nameFrame.minY - referenceName.minY) < 0.5,
                          "\(context): title position differs from No Data")
                    check(abs(nameFrame.maxY - referenceName.maxY) < 0.5, "\(context): title-to-card gap differs from No Data")
                    if let unselectedName {
                        check(abs(nameFrame.minY - unselectedName.minY) < 0.5 && abs(nameFrame.maxY - unselectedName.maxY) < 0.5,
                              "\(context): selection changes title-to-card gap")
                    } else { unselectedName = nameFrame }
                    let buttons = descendants(header.contentView).compactMap { $0 as? UIButton }
                        .filter { $0.accessibilityIdentifier?.hasPrefix("site-zone-item-") == true }.sorted { $0.tag < $1.tag }
                    check(buttons.count == (selected && item.canEdit ? 4 : 0), "\(context): wrong action group")
                    let readonly = descendants(header.contentView).filter { $0.accessibilityIdentifier == "site-zone-view-only" }
                    check(readonly.count == (item.canEdit ? 0 : 1), "\(context): View only changes on selection")
                    for (index, button) in buttons.enumerated() {
                        let frame = button.convert(button.bounds, to: header)
                        let reference = referenceFrames[index]
                        check(abs(frame.minX - reference.minX) < 0.5 && abs(frame.minY - reference.minY) < 0.5 &&
                              abs(frame.width - reference.width) < 0.5 && abs(frame.height - reference.height) < 0.5,
                              "\(context): action position/size differs from No Data")
                    }
                }
            }
        }
        let panel = UIView()
        let content = SiteTriggerZoneContentView(panel: panel)
        host.addSubview(content)
        defer { content.removeFromSuperview() }
        content.frame = CGRect(x: 0, y: 0, width: 383, height: 800)
        content.setStatus(nil)
        content.setPanelHeight(200)
        let readonly = fixtures.first { $0.previewCode == "Q04" }!
        content.render(items: fixtures, selectedID: readonly.id, canCreate: false, canSave: true, isPreview: true)
        content.layoutIfNeeded()
        check(panel.isHidden && panel.bounds.height == 0, "Read-only selection hides the previous add target")
        let editable = fixtures.first { $0.previewCode == "S01" }!
        content.render(items: fixtures, selectedID: editable.id, canCreate: false, canSave: true, isPreview: true)
        content.layoutIfNeeded()
        check(!panel.isHidden && abs(panel.bounds.height - 200) < 1, "Editable selection restores the panel height")
        check(!content.addButton.isEnabled, "Preview cannot create live Zones")
        for selectedID: UUID? in [nil, editable.id, readonly.id] {
            content.render(items: fixtures, selectedID: selectedID, canCreate: false, canSave: true, isPreview: true)
            content.layoutIfNeeded()
            for index in fixtures.indices {
                check(content.tableView(content.tableView, heightForHeaderInSection: index) == 40,
                      "Header height must match No Data regardless of selection and access")
            }
        }
        let empties = (0..<100).map { SiteTriggerZoneItemModel.empty(id: UUID(), name: "\("zone".localizedString) \($0 + 1)", canEdit: true) }
        content.render(items: empties, selectedID: empties[0].id, canCreate: true, canSave: true)
        content.layoutIfNeeded()
        let table = content.tableView
        check(table.numberOfSections == 100, "Returning to 100 live empty Zones retains all items")
        check(content.tableView(table, heightForRowAt: IndexPath(row: 0, section: 0)) == 72, "Legacy No Data height is unchanged")
        check(content.tableView(table, heightForHeaderInSection: 0) == 40, "Legacy No Data header height is unchanged")
        check(table.bounds.height > 60 && table.frame.maxY <= panel.frame.minY, "List remains above the bottom panel")
        var preview = SiteTriggerZonePreviewState()
        let original = fixtures.first { $0.previewCode == "D02" }!
        preview.begin(items: [original])
        var heights: [CGFloat] = []
        for space in original.spaces {
            for device in space.devices {
                let before = preview.items[0]
                content.render(items: [before], selectedID: original.id, canCreate: false, canSave: true, isPreview: true)
                content.layoutIfNeeded()
                heights.append(table.rectForRow(at: IndexPath(row: 0, section: 0)).height)
                preview.apply(.remove(spaceID: space.id, deviceID: device.id), zoneID: original.id,
                              expectedRevision: preview.revision!, zoneName: { "Zone \($0)" })
            }
        }
        content.render(items: preview.items, selectedID: original.id, canCreate: false, canSave: true, isPreview: true)
        content.layoutIfNeeded()
        check(table.rectForRow(at: IndexPath(row: 0, section: 0)).height == 72, "Final removal uses actual 72pt empty row")
        check(zip(heights, heights.dropFirst()).allSatisfy { $0 >= $1 }, "Removal never grows the card")
        let emptyHeader = content.tableView(table, viewForHeaderInSection: 0)!
        host.addSubview(emptyHeader)
        emptyHeader.frame = CGRect(x: 0, y: 0, width: 351, height: 40)
        emptyHeader.layoutIfNeeded()
        inspect(emptyHeader, context: "Empty pending header")
        let emptyControls = descendants(emptyHeader).compactMap { $0 as? UIButton }
        check(emptyControls.contains { $0.accessibilityIdentifier == "site-zone-metadata-sync" }, "Empty Zone retains sync explanation")
        check(emptyControls.filter { $0.accessibilityIdentifier?.contains("-test-") == true || $0.accessibilityIdentifier?.contains("-reset-") == true }
            .allSatisfy { !$0.isEnabled }, "Empty Test and Reset are disabled")
        emptyHeader.removeFromSuperview()
        for width: CGFloat in [288, 393, 768] {
            let alert = SiteTriggerZoneItemStyle.syncAlert()
            host.addSubview(alert)
            alert.frame = CGRect(x: 0, y: 0, width: width, height: 800)
            alert.layoutIfNeeded()
            inspect(alert.contentView, context: "Sync dialog width=\(width)")
            check(alert.bounds.contains(alert.contentView.frame), "Sync dialog stays inside resized host")
            check(abs(alert.contentView.bounds.width - min(302, width - 32)) < 1, "Sync dialog width=\(alert.contentView.bounds.width), host=\(width), safeArea=\(alert.safeAreaLayoutGuide.layoutFrame.width)")
            check(alert.firstBtn.bounds.height == 60 && alert.secondBtn.isHidden, "Sync dialog has one 60pt OK action")
            alert.removeFromSuperview()
        }
        return failures
    }
}
#endif
