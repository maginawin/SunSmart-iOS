# Up Down Light Group Vendor Subscription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure up down light devices subscribe their Sunricher vendor server model to group addresses so group multicast up ratio SET is received by devices.

**Architecture:** Keep App group multicast behavior unchanged. Fix the SDK shared group subscription generator so add-group, add-member, restore, and existing sync/repair paths all see the missing vendor model subscription. Scope vendor subscription to Sunricher up down light devices only.

**Tech Stack:** Swift, NordicSigMeshSDK local Swift Package, SunSmart iOS app, SIG Mesh Config Model Subscription Add.

---

### Task 1: Add SDK Test Coverage

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`

- [ ] Add tests proving an up down light node needs a vendor model subscription when added to a group.
- [ ] Add tests proving non-up-down-light nodes do not get the extra vendor subscription.
- [ ] Add tests proving an already subscribed vendor model does not generate a duplicate message.

### Task 2: Add SDK Capability Predicate

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`

- [ ] Add an SDK-level up down light predicate that checks company id `0x0A78`, product id `0x2491`, and `sunricherVendorModel != nil`.
- [ ] Keep the predicate internal to SDK behavior; App UI capability extension can remain unchanged.

### Task 3: Generate Vendor Group Subscription

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`

- [ ] Update `getSubscribeToGroupMessages(_:)` to append `ConfigModelSubscriptionAdd(group:to:)` for the Sunricher vendor model when the node is an up down light and the model is not already subscribed.
- [ ] Preserve existing SIG model subscription behavior.

### Task 4: Keep Local Subscription State Consistent

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Config.swift`

- [ ] Update `subscribe(to:)` to also subscribe the Sunricher vendor model locally for up down light nodes.
- [ ] Leave `unsubscribe(from:)` unchanged because it already removes any model subscribed to the group.

### Task 5: Verify And Commit

**Files:**
- SDK files above.
- App docs:
  - `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light/docs/260615_1439_up_down_light_group_vendor_subscription_analysis.md`
  - `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light/docs/260615_1445_up_down_light_group_vendor_subscription_plan.md`

- [ ] Run focused SDK tests if the environment supports them; if SwiftPM fails due the existing UIKit/macOS package limitation, record that.
- [ ] Run the required iPhoneOS build from the App workspace.
- [ ] Run `git diff --check` for App and SDK.
- [ ] Commit SDK changes separately from App docs.

