# WiFi Gateway No Internet Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` with Inline Execution. Do not use subagents for this project.

**Goal:** Make the WiFi Gateway header display `wifi_no_internet` whenever the authoritative Internet status is `.unavailable`.

**Architecture:** Keep protocol parsing and RSSI classification unchanged. Add one semantic `WiFiHeaderStatus.noInternet` value in `WiFiGatewayViewController`, route only `.unavailable` to it, and protect the mapping with the existing focused shell contract.

**Tech Stack:** Swift, UIKit asset catalogs, Bash focused contracts, Xcode generic iPhoneOS builds.

## Global Constraints

- Modify only the App UI mapping and its focused contract.
- Do not modify `NordicSigMeshSDK`, the header view, assets, localization, dependencies, or target configuration.
- Keep `.normal`, `.unknown/.reserved`, No Signal, Not Connected, and Not Configured behavior unchanged.
- Validate all four shared brand schemes without code signing or Simulator.

---

### Task 1: Add a failing No Internet icon contract

**Files:**

- Modify: `scripts/check_wifi_gateway_wifi_status_header.sh`
- Verify existing resource: `SunSmart/Assets.xcassets/wifi_no_internet.imageset`

**Interfaces:**

- Consumes: the existing `WiFiHeaderStatus` mapping in `WiFiGatewayViewController`.
- Produces: a source contract requiring `.unavailable` to use the `wifi_no_internet` and `wifi_status_no_internet` pair.

- [ ] **Step 1: Extend the focused contract**

Add checks that require:

- a `WiFiHeaderStatus.noInternet` semantic state with icon `wifi_no_internet` and localization key `wifi_status_no_internet`;
- the `.unavailable` switch case to call `updateWiFiHeaderStatus(.noInternet)`;
- the 1x, 2x, and 3x files in `wifi_no_internet.imageset`.

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

`bash scripts/check_wifi_gateway_wifi_status_header.sh`

Expected: FAIL because the current controller has no `WiFiHeaderStatus.noInternet` mapping.

---

### Task 2: Implement the minimal UI mapping fix

**Files:**

- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`

**Interfaces:**

- Consumes: `WiFiGatewayNetworkStatus.unavailable`.
- Produces: `WiFiHeaderStatus.noInternet`, rendered through the existing `updateWiFiHeaderStatus` and `GatewayInformationHeaderView.updateWiFiStatus` path.

- [ ] **Step 1: Define the semantic No Internet state**

Add one static state alongside the existing Excellent, Good, No Signal, and Not Connected states:

- icon name: `wifi_no_internet`;
- localization key: `wifi_status_no_internet`.

- [ ] **Step 2: Route `.unavailable` to the new state**

Replace only the current `.unavailable` temporary state construction with `updateWiFiHeaderStatus(.noInternet)`.

- [ ] **Step 3: Run focused checks and verify GREEN**

Run:

- `bash scripts/check_wifi_gateway_wifi_status_header.sh`
- `bash scripts/check_wifi_gateway_network_connectivity.sh`

Expected: both commands exit 0 and report PASS.

---

### Task 3: Verify shared-target compatibility

**Files:**

- Verify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- Verify: `scripts/check_wifi_gateway_wifi_status_header.sh`

**Interfaces:**

- Consumes: the shared controller and shared `SunSmart/Assets.xcassets`.
- Produces: compile evidence for SunSmart, Archipelago, SLG Sync Plus, and SylSmart.

- [ ] **Step 1: Check the diff**

Run:

- `git diff --check`
- `git status --short`
- `git diff -- SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift scripts/check_wifi_gateway_wifi_status_header.sh`

Expected: no whitespace errors and no unrelated source changes.

- [ ] **Step 2: Build SunSmart**

Run the generic iPhoneOS Debug build with `CODE_SIGNING_ALLOWED=NO`.

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Build Archipelago**

Run the generic iPhoneOS Debug build with `CODE_SIGNING_ALLOWED=NO`.

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Build SLG Sync Plus**

Run the generic iPhoneOS Debug build with `CODE_SIGNING_ALLOWED=NO`.

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Build SylSmart**

Run the generic iPhoneOS Debug build with `CODE_SIGNING_ALLOWED=NO`.

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Record acceptance boundary**

Report code contract and compilation results separately from real Gateway/UI validation. Hardware acceptance still requires a `0x43/0x0F` response whose `network_status` is `0x01` and visual confirmation that the header shows `wifi_no_internet`.
