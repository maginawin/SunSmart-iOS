# Lumineux Asset Catalog Grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the 75 existing Lumineux asset sets into the same twelve first-level business groups as SLGSync, while preserving every resource name and byte and making both generators reproduce the grouped structure.

**Architecture:** Add `Lumineux/DesignAssets/asset-groups.json` as the production mapping from resource name to Xcode business group. Static tests keep an independent exact mapping oracle, recursively validate the physical catalog, and resolve all existing image assertions through the mapped location. Both Swift packaging scripts load the same production manifest and reject missing mappings, unknown groups, unexpected locations, or duplicate asset-set names before writing.

**Tech Stack:** Xcode Asset Catalogs, Swift 5 scripts with Foundation/CoreGraphics/ImageIO, Ruby 2.x with Minitest/Xcodeproj/FileUtils, `xcodebuild`, `codesign`, SHA-256.

## Global Constraints

- The only approved first-level groups are `Common`, `Device`, `Energy`, `FireAlarm1.5`, `Firmware`, `Group`, `Path`, `Profile`, `Scene`, `Site`, `Space`, and `Timed`, in that order.
- `AppIcon.appiconset` and `AccentColor.colorset` remain directly under `Lumineux/Assets-Lumineux.xcassets`; every `.imageset` must be inside one approved group.
- The final catalog contains exactly 75 asset sets: 73 `.imageset`, one `.appiconset`, and one `.colorset`.
- Same-name resources use the SLGSync business group; resources absent from SLGSync use the matching SunSmart business group only as a classification reference. Never copy SunSmart or SLGSync artwork into Lumineux.
- Preserve every asset-set name, every existing `Contents.json`, and every existing image byte. The only new catalog metadata is the twelve group-level `Contents.json` files.
- Group metadata must not contain `provides-namespace`; existing `UIImage(named:)` names must remain unchanged.
- Do not modify `SunSmart/Assets.xcassets`, `SLGSync/Assets-SLGSync.xcassets`, shared UIKit code, target signing, Bundle ID, server settings, or the build-time merge algorithm.
- Preserve all pre-existing staged, unstaged, and untracked work. Do not reset, clean, or rewrite unrelated changes.
- Do not install or launch Lumineux on the user's real device.
- Create one focused local commit per task for review. Do not push any commit unless the user explicitly requests a push in a later message.

---

## File Structure

- Create `Lumineux/DesignAssets/asset-groups.json`: production source of truth for the twelve groups and all 75 resource placements.
- Create `Lumineux/Assets-Lumineux.xcassets/{Common,Device,Energy,FireAlarm1.5,Firmware,Group,Path,Profile,Scene,Site,Space,Timed}/Contents.json`: non-namespaced Xcode group metadata.
- Move the existing 73 `.imageset` directories under the mapped business groups; leave `AppIcon.appiconset` and `AccentColor.colorset` at root.
- Modify `Tests/Branding/LumineuxAssetTests.swift`: independent mapping oracle, recursive structure checks, and grouped resource lookup helpers.
- Create `Tests/Branding/LumineuxGeneratorTests.rb`: isolated positive and negative tests for both Swift generators.
- Create `scripts/validate_lumineux_asset_groups.rb`: shared recursive manifest/catalog validator used by both standalone Swift generators.
- Modify `scripts/prepare_lumineux_assets.swift`: load the group manifest and write Logo/AppIcon/AccentColor to mapped directories.
- Modify `scripts/prepare_lumineux_icons.swift`: load the group manifest and write every generated Figma icon to its mapped directory.
- Modify `scripts/check_lumineux_configuration.rb`: check the grouped launch-logo path.
- Modify `scripts/make_lumineux_test_workspace.rb`: recursively count the 75 asset sets before copying the reference catalog.
- Modify `Tests/Branding/LumineuxMergeTests.rb`: characterize same-name overrides and Lumineux-only resources when the brand catalog is grouped.
- Modify `Tests/Branding/README.md` and `docs/lumineux-missing-assets.md`: document the grouped catalog, manifest, generator checks, and unchanged missing-resource semantics.

### Task 1: Add the grouped-catalog contract and physically organize all 75 sets

**Files:**
- Modify: `Tests/Branding/LumineuxAssetTests.swift`

**Interfaces:**
- Consumes: the current flat 75-set Lumineux catalog.
- Produces: `expectedGroups: [String]`, `expectedAssetGroups: [String: String]`, `assetSetURL(named:) -> URL`, `contents(in:) throws -> [String: Any]`, and `image(in:filename:) throws -> CGImage` for all later static assertions.

- [ ] **Step 1: Record the pre-change resource count and protected-path state**

Run:

```bash
git status --short
find Lumineux/Assets-Lumineux.xcassets -type d \( -name '*.imageset' -o -name '*.appiconset' -o -name '*.colorset' \) | sort
git status --short -- SunSmart/Assets.xcassets SLGSync/Assets-SLGSync.xcassets
```

Expected: the first asset command prints 75 paths; the protected catalog status command prints no paths. Keep the full first `git status` output as the preservation baseline for the already dirty worktree.

- [ ] **Step 2: Add the exact group oracle and manifest contract to the static test**

Immediately after `catalog`, add these declarations. The test oracle is intentionally independent of the JSON consumed by production scripts so a coordinated wrong move and wrong manifest cannot pass together.

```swift
struct AssetGroupManifest: Decodable {
    let groups: [String]
    let assets: [String: String]
}

let expectedGroups = [
    "Common", "Device", "Energy", "FireAlarm1.5", "Firmware", "Group",
    "Path", "Profile", "Scene", "Site", "Space", "Timed"
]
let expectedAssetGroups: [String: String] = [
    "AccentColor": "root",
    "AppIcon": "root",
    "add": "Common",
    "favourite_normal": "Common",
    "favourite_selected": "Common",
    "hud_loading": "Common",
    "import": "Common",
    "launch_logo": "Common",
    "launch_logo_120": "Common",
    "loading": "Common",
    "loading_big": "Common",
    "lumineux_launch_logo": "Common",
    "navigation_back": "Common",
    "reset": "Common",
    "select": "Common",
    "device_add": "Device",
    "device_add_disable": "Device",
    "device_add_setting": "Device",
    "device_add_waiting": "Device",
    "device_all_off": "Device",
    "device_all_on": "Device",
    "device_control_off": "Device",
    "device_control_off_big": "Device",
    "device_control_on": "Device",
    "device_control_on_big": "Device",
    "device_identify": "Device",
    "device_restore": "Device",
    "device_restore_disable": "Device",
    "device_scan": "Device",
    "device_select": "Device",
    "light_value_add": "Device",
    "light_value_minus": "Device",
    "slider_point": "Device",
    "slider_point_disable": "Device",
    "firmware_delete": "Firmware",
    "firmware_history": "Firmware",
    "server_download": "Firmware",
    "auto": "Group",
    "group_control_disable": "Group",
    "group_control_disable_big": "Group",
    "group_empty": "Group",
    "group_off": "Group",
    "group_off_big": "Group",
    "group_on": "Group",
    "group_on_big": "Group",
    "sensor_move": "Group",
    "sync_failed_small": "Group",
    "sync_loading_small": "Group",
    "sync_success_small": "Group",
    "sync_waiting_small": "Group",
    "profile_chart_occupancy_daylight": "Profile",
    "scene_data_value_add": "Scene",
    "scene_data_value_minus": "Scene",
    "scene_empty": "Scene",
    "scene_group_disable": "Scene",
    "scene_group_off": "Scene",
    "scene_group_on": "Scene",
    "menu_icon": "Site",
    "more_vertical": "Site",
    "no_Internet": "Site",
    "site_empty": "Site",
    "space_add": "Space",
    "space_empty": "Space",
    "space_energy_data": "Space",
    "space_group": "Space",
    "space_group_selected": "Space",
    "space_main": "Space",
    "space_main_selected": "Space",
    "space_more": "Space",
    "space_more_selected": "Space",
    "space_scene": "Space",
    "space_scene_selected": "Space",
    "space_timed": "Space",
    "space_timed_selected": "Space",
    "schedule_target_select": "Timed"
]

let groupManifestURL = root.appendingPathComponent("Lumineux/DesignAssets/asset-groups.json")
check(FileManager.default.fileExists(atPath: groupManifestURL.path),
      "Missing Lumineux asset group manifest")
let groupManifest = try JSONDecoder().decode(
    AssetGroupManifest.self,
    from: Data(contentsOf: groupManifestURL)
)
check(groupManifest.groups == expectedGroups,
      "Lumineux groups must match SLGSync order and names")
check(groupManifest.assets == expectedAssetGroups,
      "Lumineux asset group manifest differs from the approved 75-resource mapping")
```

- [ ] **Step 3: Add recursive structure validation and grouped lookup helpers**

Replace the path-based `json(_:)` and `image(_:)` helpers with:

```swift
func setExtension(for name: String) -> String {
    switch name {
    case "AppIcon": return "appiconset"
    case "AccentColor": return "colorset"
    default: return "imageset"
    }
}

func assetSetURL(named name: String) -> URL {
    guard let group = expectedAssetGroups[name] else {
        preconditionFailure("No approved group for \(name)")
    }
    let parent = group == "root" ? catalog : catalog.appendingPathComponent(group)
    return parent.appendingPathComponent("\(name).\(setExtension(for: name))")
}

func contents(in set: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(
        with: Data(contentsOf: set.appendingPathComponent("Contents.json"))
    ) as! [String: Any]
}

func image(in set: URL, filename: String) throws -> CGImage {
    let data = try Data(contentsOf: set.appendingPathComponent(filename))
    return CGImageSourceCreateImageAtIndex(
        CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil
    )!
}

func contents(named name: String) throws -> [String: Any] {
    try contents(in: assetSetURL(named: name))
}

func image(named name: String, filename: String) throws -> CGImage {
    try image(in: assetSetURL(named: name), filename: filename)
}

for group in expectedGroups {
    let directory = catalog.appendingPathComponent(group)
    check(FileManager.default.fileExists(atPath: directory.path),
          "Missing Lumineux asset group: \(group)")
    let metadata = try JSONSerialization.jsonObject(
        with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))
    ) as! [String: Any]
    check(metadata["properties"] == nil,
          "Lumineux asset groups must not provide a namespace: \(group)")
}

let supportedSetExtensions = Set(["imageset", "appiconset", "colorset"])
let enumerator = FileManager.default.enumerator(
    at: catalog,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles]
)!
var discovered: [String: [URL]] = [:]
while let url = enumerator.nextObject() as? URL {
    guard supportedSetExtensions.contains(url.pathExtension) else { continue }
    let name = url.deletingPathExtension().lastPathComponent
    discovered[name, default: []].append(url.standardizedFileURL)
    enumerator.skipDescendants()
}
check(discovered.count == 75, "Lumineux catalog must contain exactly 75 asset names")
check(Set(discovered.keys) == Set(expectedAssetGroups.keys),
      "Lumineux catalog asset names differ from the approved set")
for name in expectedAssetGroups.keys.sorted() {
    let locations = discovered[name] ?? []
    check(locations.count == 1, "Lumineux asset \(name) must appear exactly once")
    check(locations.first == assetSetURL(named: name).standardizedFileURL,
          "Lumineux asset \(name) is in the wrong business group")
}
let rootImagesets = try FileManager.default.contentsOfDirectory(
    at: catalog,
    includingPropertiesForKeys: [.isDirectoryKey]
).filter { $0.pathExtension == "imageset" }
check(rootImagesets.isEmpty, "Lumineux catalog root must not contain imagesets")
```

Update each existing assertion with these concrete forms. The Logo, manifest-icon, and empty-state loops use:

```swift
let imageSet = assetSetURL(named: name)
let entries = try contents(named: name)["images"] as! [[String: String]]
let pixels = try image(named: name, filename: entry["filename"]!)
```

The supplied `auto` checks use:

```swift
let autoSet = assetSetURL(named: "auto")
let autoEntries = try contents(named: "auto")["images"] as! [[String: String]]
let pixels = try image(named: "auto", filename: filename)
let data = try Data(contentsOf: autoSet.appendingPathComponent(filename))
```

The AppIcon and AccentColor checks use:

```swift
let iconEntries = try contents(named: "AppIcon")["images"] as! [[String: String]]
let icon = try image(named: "AppIcon", filename: iconEntries[0]["filename"]!)
let colors = try contents(named: "AccentColor")["colors"] as! [[String: Any]]
```

After these replacements, search the test for `catalog.appendingPathComponent("auto.imageset`, `json("`, and `image("`; none may remain.

- [ ] **Step 4: Run the new contract and verify the expected red state**

Run:

```bash
swift Tests/Branding/LumineuxAssetTests.swift
```

Expected: FAIL with `Missing Lumineux asset group manifest`. The failure proves the new contract is active before the production manifest or physical move exists.

- [ ] **Step 5: Review the test-only diff**

Run:

```bash
git diff -- Tests/Branding/LumineuxAssetTests.swift
git diff --check -- Tests/Branding/LumineuxAssetTests.swift
```

Expected: only the independent group contract and grouped lookup refactor appear; no production files have changed in this task.

#### Phase B: Create the group manifest and move the existing catalog without changing bytes

**Files:**
- Create: `Lumineux/DesignAssets/asset-groups.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Common/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Device/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Energy/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/FireAlarm1.5/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Firmware/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Group/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Path/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Profile/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Scene/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Site/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Space/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Timed/Contents.json`
- Move: all 73 existing `Lumineux/Assets-Lumineux.xcassets/*.imageset` directories to their manifest groups.

**Interfaces:**
- Consumes: `expectedAssetGroups` from Task 1 as the independent oracle.
- Produces: JSON schema `{ "groups": [String], "assets": { String: String } }`, where `root` is the only non-group placement marker.

- [ ] **Step 1: Snapshot every existing asset-set file before moving it**

Run this from the repository root:

```bash
/usr/bin/ruby -rdigest -e '
catalog = "Lumineux/Assets-Lumineux.xcassets"
extensions = %w[imageset appiconset colorset]
sets = Dir.glob(File.join(catalog, "**", "*")).select do |path|
  File.directory?(path) && extensions.include?(File.extname(path).delete_prefix("."))
end
abort("Expected 75 asset sets, got #{sets.length}") unless sets.length == 75
lines = sets.flat_map do |set|
  name = File.basename(set).sub(/\.(imageset|appiconset|colorset)\z/, "")
  Dir.glob(File.join(set, "**", "*")).select { |path| File.file?(path) }.map do |path|
    inner = path.delete_prefix(set + "/")
    "#{name}/#{inner} #{Digest::SHA256.file(path).hexdigest}"
  end
end.sort
File.write("/private/tmp/lumineux-assets-before.sha256", lines.join("\n") + "\n")
puts "snapshotted #{sets.length} asset sets and #{lines.length} files"
'
```

Expected: `snapshotted 75 asset sets and N files`, with `N` greater than 75.

- [ ] **Step 2: Add the production manifest with the exact approved mapping**

Create `Lumineux/DesignAssets/asset-groups.json` with the same twelve-element `groups` array and 75 key/value pairs shown in Task 1. Use this exact top-level shape and the exact `root` values:

```json
{
  "groups": [
    "Common",
    "Device",
    "Energy",
    "FireAlarm1.5",
    "Firmware",
    "Group",
    "Path",
    "Profile",
    "Scene",
    "Site",
    "Space",
    "Timed"
  ],
  "assets": {
    "AccentColor": "root",
    "AppIcon": "root",
    "add": "Common",
    "auto": "Group",
    "device_add": "Device",
    "device_add_disable": "Device",
    "device_add_setting": "Device",
    "device_add_waiting": "Device",
    "device_all_off": "Device",
    "device_all_on": "Device",
    "device_control_off": "Device",
    "device_control_off_big": "Device",
    "device_control_on": "Device",
    "device_control_on_big": "Device",
    "device_identify": "Device",
    "device_restore": "Device",
    "device_restore_disable": "Device",
    "device_scan": "Device",
    "device_select": "Device",
    "favourite_normal": "Common",
    "favourite_selected": "Common",
    "firmware_delete": "Firmware",
    "firmware_history": "Firmware",
    "group_control_disable": "Group",
    "group_control_disable_big": "Group",
    "group_empty": "Group",
    "group_off": "Group",
    "group_off_big": "Group",
    "group_on": "Group",
    "group_on_big": "Group",
    "hud_loading": "Common",
    "import": "Common",
    "launch_logo": "Common",
    "launch_logo_120": "Common",
    "light_value_add": "Device",
    "light_value_minus": "Device",
    "loading": "Common",
    "loading_big": "Common",
    "lumineux_launch_logo": "Common",
    "menu_icon": "Site",
    "more_vertical": "Site",
    "navigation_back": "Common",
    "no_Internet": "Site",
    "profile_chart_occupancy_daylight": "Profile",
    "reset": "Common",
    "scene_data_value_add": "Scene",
    "scene_data_value_minus": "Scene",
    "scene_empty": "Scene",
    "scene_group_disable": "Scene",
    "scene_group_off": "Scene",
    "scene_group_on": "Scene",
    "schedule_target_select": "Timed",
    "select": "Common",
    "sensor_move": "Group",
    "server_download": "Firmware",
    "site_empty": "Site",
    "slider_point": "Device",
    "slider_point_disable": "Device",
    "space_add": "Space",
    "space_empty": "Space",
    "space_energy_data": "Space",
    "space_group": "Space",
    "space_group_selected": "Space",
    "space_main": "Space",
    "space_main_selected": "Space",
    "space_more": "Space",
    "space_more_selected": "Space",
    "space_scene": "Space",
    "space_scene_selected": "Space",
    "space_timed": "Space",
    "space_timed_selected": "Space",
    "sync_failed_small": "Group",
    "sync_loading_small": "Group",
    "sync_success_small": "Group",
    "sync_waiting_small": "Group"
  }
}
```

- [ ] **Step 3: Create the twelve non-namespaced group metadata files**

For each approved group, create `Contents.json` with these exact bytes and no `properties` key:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

The empty `Energy`, `FireAlarm1.5`, and `Path` directories still receive this file so the first-level structure matches SLGSync.

- [ ] **Step 4: Move each existing imageset according to the manifest**

Run the following mechanical move only after the manifest and all group directories exist:

```bash
/usr/bin/ruby -rjson -rfileutils -e '
catalog = File.expand_path("Lumineux/Assets-Lumineux.xcassets")
manifest = JSON.parse(File.read("Lumineux/DesignAssets/asset-groups.json"))
manifest.fetch("assets").sort.each do |name, group|
  next if group == "root"
  matches = Dir.glob(File.join(catalog, "**", "#{name}.imageset"))
  abort("Expected one source for #{name}, found #{matches.length}") unless matches.length == 1
  source = File.expand_path(matches.first)
  target = File.join(catalog, group, "#{name}.imageset")
  next if source == target
  abort("Refusing to overwrite #{target}") if File.exist?(target)
  FileUtils.mv(source, target)
end
'
```

Expected: all 73 `.imageset` directories move under approved groups; `AppIcon.appiconset` and `AccentColor.colorset` remain at root.

- [ ] **Step 5: Compare the post-move bytes against the saved snapshot**

Run the same snapshot logic against the grouped catalog and compare it:

```bash
/usr/bin/ruby -rdigest -e '
catalog = "Lumineux/Assets-Lumineux.xcassets"
extensions = %w[imageset appiconset colorset]
sets = Dir.glob(File.join(catalog, "**", "*")).select do |path|
  File.directory?(path) && extensions.include?(File.extname(path).delete_prefix("."))
end
abort("Expected 75 asset sets, got #{sets.length}") unless sets.length == 75
lines = sets.flat_map do |set|
  name = File.basename(set).sub(/\.(imageset|appiconset|colorset)\z/, "")
  Dir.glob(File.join(set, "**", "*")).select { |path| File.file?(path) }.map do |path|
    inner = path.delete_prefix(set + "/")
    "#{name}/#{inner} #{Digest::SHA256.file(path).hexdigest}"
  end
end.sort
File.write("/private/tmp/lumineux-assets-after.sha256", lines.join("\n") + "\n")
puts "snapshotted #{sets.length} asset sets and #{lines.length} files"
'
diff -u /private/tmp/lumineux-assets-before.sha256 /private/tmp/lumineux-assets-after.sha256
```

Expected: `diff` prints nothing and exits 0.

- [ ] **Step 6: Run the static contract to verify the grouped catalog is green**

Run:

```bash
swift Tests/Branding/LumineuxAssetTests.swift
```

Expected: PASS and the existing summary still reports 65 Figma-vector icons, one supplied PNG, four empty states, Retina Logos, AppIcon, and AccentColor.

- [ ] **Step 7: Review only the manifest, group metadata, and moves**

Run:

```bash
git status --short -- Lumineux/Assets-Lumineux.xcassets Lumineux/DesignAssets/asset-groups.json
git diff --summary -- Lumineux/Assets-Lumineux.xcassets
git diff --check -- Lumineux/Assets-Lumineux.xcassets Lumineux/DesignAssets/asset-groups.json
```

Expected: 73 directory moves/add-delete pairs, two root sets retained, twelve group metadata files, and one group manifest. No image content modifications appear beyond the already-existing baseline changes recorded in Task 1.

- [ ] **Step 8: Commit the independently green grouped-catalog task**

Run:

```bash
git add Tests/Branding/LumineuxAssetTests.swift Lumineux/DesignAssets/asset-groups.json Lumineux/Assets-Lumineux.xcassets
git diff --cached --check
git commit -m "refactor: group Lumineux asset catalog"
```

Expected: one local commit containing the static contract, manifest, group metadata, and physical asset moves. Do not push.

### Task 2: Make both Swift generators reproduce and police the grouping

**Files:**
- Create: `Tests/Branding/LumineuxGeneratorTests.rb`
- Create: `scripts/validate_lumineux_asset_groups.rb`
- Modify: `scripts/prepare_lumineux_assets.swift`
- Modify: `scripts/prepare_lumineux_icons.swift`

**Interfaces:**
- Consumes: `Lumineux/DesignAssets/asset-groups.json` with `AssetGroupManifest { groups: [String], assets: [String: String] }`.
- Produces: `LumineuxAssetGroups.validate(catalog:, manifest:) -> Hash`, a CLI that emits validated manifest JSON, and the small Swift integration functions `loadAssetGroupManifest() throws -> AssetGroupManifest` and `assetSetDirectory(named:type:) throws -> URL`.

- [ ] **Step 1: Write isolated generator regression tests**

Create `Tests/Branding/LumineuxGeneratorTests.rb` with four cases:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

class LumineuxGeneratorTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  ICON_SCRIPT = File.join(ROOT, 'scripts/prepare_lumineux_icons.swift')
  ASSET_SCRIPT = File.join(ROOT, 'scripts/prepare_lumineux_assets.swift')

  def with_fixture
    Dir.mktmpdir('lumineux-generators-') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'Lumineux'))
      FileUtils.cp_r(File.join(ROOT, 'Lumineux/DesignAssets'), File.join(directory, 'Lumineux/DesignAssets'))
      FileUtils.cp_r(File.join(ROOT, 'Lumineux/Assets-Lumineux.xcassets'),
                     File.join(directory, 'Lumineux/Assets-Lumineux.xcassets'))
      yield directory
    end
  end

  def run_script(script, directory)
    Open3.capture3('/usr/bin/xcrun', 'swift', script, chdir: directory)
  end

  def rewrite_manifest(directory)
    path = File.join(directory, 'Lumineux/DesignAssets/asset-groups.json')
    manifest = JSON.parse(File.read(path))
    yield manifest
    File.write(path, JSON.pretty_generate(manifest) + "\n")
  end

  def test_generators_keep_every_imageset_out_of_the_catalog_root
    with_fixture do |directory|
      [ASSET_SCRIPT, ICON_SCRIPT].each do |script|
        _stdout, stderr, status = run_script(script, directory)
        assert status.success?, stderr
      end
      catalog = File.join(directory, 'Lumineux/Assets-Lumineux.xcassets')
      assert_empty Dir.glob(File.join(catalog, '*.imageset'))
      assert File.directory?(File.join(catalog, 'Common/launch_logo.imageset'))
      assert File.directory?(File.join(catalog, 'Device/device_select.imageset'))
      assert File.directory?(File.join(catalog, 'Profile/profile_chart_occupancy_daylight.imageset'))
      assert File.directory?(File.join(catalog, 'Timed/schedule_target_select.imageset'))
    end
  end

  def test_icon_generator_rejects_a_missing_mapping
    with_fixture do |directory|
      rewrite_manifest(directory) { |manifest| manifest.fetch('assets').delete('add') }
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Missing asset group for add/, stderr)
    end
  end

  def test_icon_generator_rejects_an_unknown_group
    with_fixture do |directory|
      rewrite_manifest(directory) { |manifest| manifest.fetch('assets')['add'] = 'Unknown' }
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Unknown asset group Unknown for add/, stderr)
    end
  end

  def test_icon_generator_rejects_duplicate_asset_locations
    with_fixture do |directory|
      catalog = File.join(directory, 'Lumineux/Assets-Lumineux.xcassets')
      FileUtils.cp_r(File.join(catalog, 'Common/add.imageset'), File.join(catalog, 'add.imageset'))
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Duplicate asset set add/, stderr)
    end
  end

  def test_icon_generator_rejects_an_asset_outside_its_mapped_group
    with_fixture do |directory|
      catalog = File.join(directory, 'Lumineux/Assets-Lumineux.xcassets')
      FileUtils.mv(File.join(catalog, 'Common/add.imageset'),
                   File.join(catalog, 'Device/add.imageset'))
      _stdout, stderr, status = run_script(ICON_SCRIPT, directory)
      refute status.success?
      assert_match(/Asset set add exists outside mapped group/, stderr)
    end
  end
end
```

- [ ] **Step 2: Run the generator tests and verify the expected red state**

Run:

```bash
ruby Tests/Branding/LumineuxGeneratorTests.rb
```

Expected: FAIL because the current generators write generated `.imageset` directories at catalog root and ignore missing/unknown group mappings and duplicate locations.

- [ ] **Step 3: Centralize catalog validation in one Ruby helper**

Create `scripts/validate_lumineux_asset_groups.rb` with a `LumineuxAssetGroups.validate(catalog:, manifest:)` module function and CLI. The function must parse the manifest, require the exact twelve-group array, reject mappings outside `root` or the approved groups, recursively index `.imageset`/`.appiconset`/`.colorset`, reject missing mappings and duplicate basenames, and require every existing set to equal its mapped physical path. On success, return the parsed manifest; the CLI prints that manifest as JSON for the Swift caller.

Use these exact public constants and errors:

```ruby
module LumineuxAssetGroups
  APPROVED_GROUPS = %w[
    Common Device Energy FireAlarm1.5 Firmware Group Path Profile Scene Site Space Timed
  ].freeze
  SET_EXTENSIONS = %w[.imageset .appiconset .colorset].freeze
  ROOT_GROUP = 'root'
  class Error < StandardError; end
end
```

The CLI contract is:

```ruby
if $PROGRAM_NAME == __FILE__
  abort('usage: validate_lumineux_asset_groups.rb CATALOG MANIFEST') unless ARGV.length == 2
  begin
    puts JSON.generate(LumineuxAssetGroups.validate(catalog: ARGV[0], manifest: ARGV[1]))
  rescue LumineuxAssetGroups::Error, JSON::ParserError, KeyError => error
    warn error.message
    exit 1
  end
end
```

Error text consumed by the generator tests must contain exactly `Missing asset group for NAME`, `Unknown asset group GROUP for NAME`, `Duplicate asset set NAME`, or `Asset set NAME exists outside mapped group`, as applicable.

- [ ] **Step 4: Load the validated manifest from each standalone Swift generator**

After each script defines `root`, `catalog`, and `designAssets`, add the small integration boundary below. The catalog-walking and group-list logic stays only in the Ruby helper.

```swift
struct AssetGroupManifest: Decodable {
    let groups: [String]
    let assets: [String: String]
}

func loadAssetGroupManifest() throws -> AssetGroupManifest {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
    process.arguments = [
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("validate_lumineux_asset_groups.rb").path,
        catalog.path,
        designAssets.appendingPathComponent("asset-groups.json").path
    ]
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    let errorText = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    precondition(process.terminationStatus == 0, errorText)
    return try JSONDecoder().decode(
        AssetGroupManifest.self,
        from: output.fileHandleForReading.readDataToEndOfFile()
    )
}

let assetGroupManifest = try loadAssetGroupManifest()

func assetSetDirectory(named name: String, type: String) throws -> URL {
    guard let group = assetGroupManifest.assets[name] else {
        preconditionFailure("Missing asset group for \(name)")
    }
    let parent = group == "root" ? catalog : catalog.appendingPathComponent(group)
    let directory = parent.appendingPathComponent("\(name).\(type)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
```

In `prepare_lumineux_assets.swift`, define `designAssets` next to `root` and keep the Logo source unchanged:

```swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let designAssets = root.appendingPathComponent("Lumineux/DesignAssets")
let appIcon = sourceImage("Lumineux/DesignAssets/app_logo_1024.png")
let catalog = root.appendingPathComponent("Lumineux/Assets-Lumineux.xcassets")
```

- [ ] **Step 5: Route all generator outputs through `assetSetDirectory`**

In `prepare_lumineux_icons.swift`, replace the root write with:

```swift
let directory = try assetSetDirectory(named: asset.asset, type: "imageset")
```

In `prepare_lumineux_assets.swift`, replace the three output constructions with:

```swift
let directory = try assetSetDirectory(named: name, type: "imageset")
```

```swift
let iconDirectory = try assetSetDirectory(named: "AppIcon", type: "appiconset")
```

```swift
let accentDirectory = try assetSetDirectory(named: "AccentColor", type: "colorset")
try writeJSON(["colors": [["idiom": "universal", "color": ["color-space": "srgb", "components": ["red": "0x4D", "green": "0x73", "blue": "0x8A", "alpha": "1.000"]]]], "info": info], to: accentDirectory)
```

- [ ] **Step 6: Run the isolated generator tests**

Run:

```bash
ruby Tests/Branding/LumineuxGeneratorTests.rb
```

Expected: five runs, no failures or errors. The positive fixture keeps all `.imageset` directories grouped; the four negative fixtures exit non-zero with the exact expected validation message.

- [ ] **Step 7: Regenerate the real catalog and prove no resource moved or duplicated**

Run:

```bash
swift scripts/prepare_lumineux_assets.swift
swift scripts/prepare_lumineux_icons.swift
swift Tests/Branding/LumineuxAssetTests.swift
find Lumineux/Assets-Lumineux.xcassets -mindepth 1 -maxdepth 1 -type d -name '*.imageset'
```

Expected: both generators and the static test pass; the final `find` prints nothing. Re-run the post-move SHA snapshot from Task 1 and compare it with `/private/tmp/lumineux-assets-after.sha256`; expected no changes for the sets rewritten by the generators and no change for supplied PNG/empty-state sets not managed by them.

- [ ] **Step 8: Review the generator boundary**

Run:

```bash
git diff -- scripts/validate_lumineux_asset_groups.rb scripts/prepare_lumineux_assets.swift scripts/prepare_lumineux_icons.swift Tests/Branding/LumineuxGeneratorTests.rb
git diff --check -- scripts/validate_lumineux_asset_groups.rb scripts/prepare_lumineux_assets.swift scripts/prepare_lumineux_icons.swift Tests/Branding/LumineuxGeneratorTests.rb
```

Expected: no artwork manipulation changes, no new recoloring, and no change to `icon-manifest.json`; only path resolution and validation are added.

- [ ] **Step 9: Commit the generator workflow**

Run:

```bash
git add scripts/validate_lumineux_asset_groups.rb scripts/prepare_lumineux_assets.swift scripts/prepare_lumineux_icons.swift Tests/Branding/LumineuxGeneratorTests.rb
git diff --cached --check
git commit -m "build: preserve Lumineux asset groups"
```

Expected: one local commit containing the shared validator, both generator integrations, and generator regressions. Do not push.

### Task 3: Adapt remaining path consumers and lock recursive merge behavior

**Files:**
- Modify: `scripts/check_lumineux_configuration.rb:45-52`
- Modify: `scripts/make_lumineux_test_workspace.rb:38-46`
- Modify: `Tests/Branding/LumineuxMergeTests.rb`

**Interfaces:**
- Consumes: grouped catalog from Task 1.
- Produces: recursive reference-catalog counting and grouped-path merge characterization; `Lumineux/Scripts/merge_assets.rb` remains byte-for-byte unchanged.

- [ ] **Step 1: Update the launch-logo configuration assertion**

Replace the old root path in `scripts/check_lumineux_configuration.rb` with:

```ruby
assert(ROOT.join('Lumineux/Assets-Lumineux.xcassets/Common/lumineux_launch_logo.imageset').directory?,
       'Lumineux dedicated launch image set is missing')
```

- [ ] **Step 2: Make the temporary XCTest workspace count asset sets recursively**

Replace the top-level directory count in `scripts/make_lumineux_test_workspace.rb` with:

```ruby
asset_set_extensions = %w[.imageset .appiconset .colorset]
brand_sets = Dir.glob(File.join(brand_catalog, '**', '*')).select do |path|
  File.directory?(path) && asset_set_extensions.include?(File.extname(path))
end
abort("Expected 75 complete Lumineux catalog sets for reference catalog; found #{brand_sets.length}") unless brand_sets.length == 75
```

Keep the existing recursive `FileUtils.cp_r(File.join(brand_catalog, '.'), reference_catalog)` copy unchanged.

- [ ] **Step 3: Add a grouped Lumineux-only merge characterization**

Add this test to `Tests/Branding/LumineuxMergeTests.rb`:

```ruby
def test_preserves_group_path_for_a_brand_only_set
  with_catalogs do |common, brand, output|
    write_catalog(common)
    write_catalog(brand)
    write_set(brand, 'Profile/chart.imageset', {
      'Contents.json' => '{"images":["brand-only"]}',
      'chart@2x.png' => 'brand-only pixels'
    })

    LumineuxAssetMerger.merge(common: common, brand: brand, output: output)

    set = File.join(output, 'Profile', 'chart.imageset')
    assert_equal 'brand-only pixels', File.binread(File.join(set, 'chart@2x.png'))
    assert_equal 1, Dir.glob(File.join(output, '**', 'chart.imageset')).length
  end
end
```

In `test_replaces_common_set_at_its_original_path_without_stale_files`, change the brand fixture from `logo.imageset` to `Common/logo.imageset`. Keep the expected merged destination `Common/logo.imageset`; this proves same-name resolution remains name-based even after both catalogs are grouped.

- [ ] **Step 4: Run the focused Ruby regression suite**

Run:

```bash
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
```

Expected: the merge suite increases by one run with no failure; the configuration suite reports `PASS: Lumineux target resolves its independent configuration and resources.` The merge script itself has no diff.

- [ ] **Step 5: Generate the runtime-test workspace as a recursive-copy smoke test**

Run:

```bash
branding_tmp="$(mktemp -d /private/tmp/lumineux-grouped-branding.XXXXXX)"
/usr/bin/ruby -e 'File.write("/private/tmp/lumineux-grouped-branding-root", ARGV.fetch(0))' "$branding_tmp"
ruby scripts/make_lumineux_test_workspace.rb "$branding_tmp/runtime"
test -d "$branding_tmp/runtime/LumineuxReference.xcassets/Common"
test -d "$branding_tmp/runtime/LumineuxReference.xcassets/Profile"
find "$branding_tmp/runtime/LumineuxReference.xcassets" -type d \( -name '*.imageset' -o -name '*.appiconset' -o -name '*.colorset' \) | wc -l
```

Expected: workspace creation succeeds, both group checks pass, and the count is 75.

- [ ] **Step 6: Confirm the merger implementation was not changed**

Run:

```bash
git diff -- Lumineux/Scripts/merge_assets.rb
git diff --check -- scripts/check_lumineux_configuration.rb scripts/make_lumineux_test_workspace.rb Tests/Branding/LumineuxMergeTests.rb
```

Expected: the first command prints nothing; the second exits 0.

- [ ] **Step 7: Commit the recursive path-consumer regressions**

Run:

```bash
git add scripts/check_lumineux_configuration.rb scripts/make_lumineux_test_workspace.rb Tests/Branding/LumineuxMergeTests.rb
git diff --cached --check
git commit -m "test: cover grouped Lumineux catalogs"
```

Expected: one local commit containing only path-consumer and merge characterization changes. Do not push.

### Task 4: Document the new structure and run full static, runtime, build, and signing verification

**Files:**
- Modify: `Tests/Branding/README.md`
- Modify: `docs/lumineux-missing-assets.md`
- Modify: `docs/superpowers/plans/2026-08-31-lumineux-asset-catalog-grouping.md`

**Interfaces:**
- Consumes: completed grouped catalog and all regression tooling.
- Produces: an evidence-backed handoff with static tests, iPhone 16 runtime checks, Lumineux generic-device build/signing, merged-catalog comparison, and SunSmart simulator isolation.

- [ ] **Step 1: Document the catalog organization and generator command**

Add this section near the top of `Tests/Branding/README.md`, after “检查范围”:

```markdown
### Catalog 物理分组

`Lumineux/Assets-Lumineux.xcassets` 使用与 SLGSync 相同的十二个一级业务目录：`Common`、`Device`、`Energy`、`FireAlarm1.5`、`Firmware`、`Group`、`Path`、`Profile`、`Scene`、`Site`、`Space`、`Timed`。`AppIcon` 与 `AccentColor` 保留在根目录；当前 73 个 imageset 全部位于业务目录中。

`Lumineux/DesignAssets/asset-groups.json` 是生成器的分组来源。`icon-manifest.json` 中的 `Tabs`、`Navigation`、`Buttons` 等字段只描述 Figma 来源，不决定 Xcode 目录。两个资源生成器会拒绝缺失分组、未知分组、错误位置和同名重复资源；重新运行后不得在 catalog 根目录生成 imageset。
```

Add `ruby Tests/Branding/LumineuxGeneratorTests.rb` to the static command block before `swift Tests/Branding/LumineuxAssetTests.swift`.

At the top of `docs/lumineux-missing-assets.md`, add:

```markdown
> 目录说明：已接入的 Lumineux 资源按 SLGSync 的十二个业务分组保存；SLGSync 不存在的同名资源只参考 SunSmart 的业务目录归类。该规则不代表复用或复制 SunSmart 图片，也不改变下文对缺失素材的判断。
```

- [ ] **Step 2: Run all static checks**

Run:

```bash
ruby Tests/Branding/LumineuxGeneratorTests.rb
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
swift Tests/Branding/LumineuxAssetTests.swift
bash scripts/check_nordic_sdk_dependency.sh
git diff --check
git diff --cached --check
```

Expected: every test/check exits 0. The SDK check confirms the existing package configuration only; no SDK file is modified.

- [ ] **Step 3: Run the existing Lumineux runtime suite on iPhone 16 in English**

Use the `branding_tmp` workspace created in Task 4 and the existing local package checkout:

```bash
branding_tmp="$(/bin/cat /private/tmp/lumineux-grouped-branding-root)"
source_packages_dir=/Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages
xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -clonedSourcePackagesDirPath "$source_packages_dir" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$branding_tmp/grouped-en.xcresult" \
  -testLanguage en -testRegion US -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: all existing Lumineux branding/runtime tests pass apart from the suite's explicitly expected negative controls. If the saved simulator ID is unavailable, obtain the current iPhone 16 x86_64 ID with `xcrun simctl list devices available` and substitute that concrete ID before retrying.

- [ ] **Step 4: Re-run the built runtime suite in Simplified Chinese**

Run:

```bash
branding_tmp="$(/bin/cat /private/tmp/lumineux-grouped-branding-root)"
source_packages_dir=/Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages
xcodebuild \
  -workspace "$branding_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -derivedDataPath "$branding_tmp/DerivedData" \
  -clonedSourcePackagesDirPath "$source_packages_dir" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$branding_tmp/grouped-zh.xcresult" \
  -testLanguage zh-Hans -testRegion CN -parallel-testing-enabled NO -jobs 4 \
  test-without-building CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: the same runtime coverage passes in Simplified Chinese.

- [ ] **Step 5: Export and visually review the runtime screenshots**

Run:

```bash
branding_tmp="$(/bin/cat /private/tmp/lumineux-grouped-branding-root)"
xcrun xcresulttool get test-results summary --path "$branding_tmp/grouped-en.xcresult"
xcrun xcresulttool get test-results summary --path "$branding_tmp/grouped-zh.xcresult"
xcrun xcresulttool export attachments --path "$branding_tmp/grouped-en.xcresult" --output-path "$branding_tmp/screenshots-en"
xcrun xcresulttool export attachments --path "$branding_tmp/grouped-zh.xcresult" --output-path "$branding_tmp/screenshots-zh"
```

Open the exported Launch, Welcome, Sites, Space, Group, Scene, Profile, device-state, Tab, navigation, and button screenshots. Verify the Lumineux artwork still loads, with no SunSmart fallback, blank image, clipping, stretching, overlap, or constraint warning. This visual review is required by the repository UI rule even though the intended change is only physical resource organization.

- [ ] **Step 6: Build and verify the signed Lumineux generic-device app**

Create a dedicated normal-Library DerivedData directory so the known Run Script sandbox behavior is exercised. Request sandbox approval when executing because this path is outside the repository write root.

```bash
verification_root="$(mktemp -d /Users/sr/Library/Developer/Xcode/DerivedData3/LumineuxGrouping.XXXXXX)"
source_packages_dir=/Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages
/usr/bin/ruby -e 'File.write("/private/tmp/lumineux-grouping-build-root", ARGV.fetch(0))' "$verification_root"
xcodebuild \
  -workspace SunSmart.xcworkspace \
  -scheme Lumineux -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$verification_root/AppBuild" \
  -clonedSourcePackagesDirPath "$source_packages_dir" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  build
app="$verification_root/AppBuild/Build/Products/Debug-iphoneos/Lumineux.app"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/codesign -dvv "$app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
```

Expected: build succeeds without duplicate asset warnings; signing verification succeeds; Team is `JTD3WYUC58`; bundle identifier is `com.azoula.sunsmart.Lumineux`.

- [ ] **Step 7: Compare all 75 source sets with the generated merged catalog by asset name**

Run:

```bash
verification_root="$(/bin/cat /private/tmp/lumineux-grouping-build-root)"
/usr/bin/ruby -rdigest -e '
source = "Lumineux/Assets-Lumineux.xcassets"
merged = File.join(ARGV.fetch(0), "AppBuild/Build/Intermediates.noindex/SunSmart.build/Debug-iphoneos/Lumineux.build/DerivedSources/LumineuxAssets/Assets-Lumineux-Merged.xcassets")
extensions = %w[.imageset .appiconset .colorset]
index = lambda do |catalog|
  sets = Dir.glob(File.join(catalog, "**", "*")).select do |path|
    File.directory?(path) && extensions.include?(File.extname(path))
  end
  sets.to_h { |path| [File.basename(path), path] }
end
source_sets = index.call(source)
merged_sets = index.call(merged)
abort("Expected 75 Lumineux source sets, got #{source_sets.length}") unless source_sets.length == 75
source_sets.each do |name, source_set|
  merged_set = merged_sets.fetch(name)
  source_files = Dir.glob(File.join(source_set, "**", "*")).select { |path| File.file?(path) }
  source_files.each do |path|
    relative = path.delete_prefix(source_set + "/")
    target = File.join(merged_set, relative)
    abort("Missing merged file #{name}/#{relative}") unless File.file?(target)
    abort("Merged bytes differ for #{name}/#{relative}") unless Digest::SHA256.file(path).hexdigest == Digest::SHA256.file(target).hexdigest
  end
end
puts "PASS: 75 grouped Lumineux asset sets match the merged catalog by name and bytes"
' "$verification_root"
```

Expected: the printed 75-set PASS message.

- [ ] **Step 8: Build SunSmart for the iPhone 16 simulator**

Run:

```bash
branding_tmp="$(/bin/cat /private/tmp/lumineux-grouped-branding-root)"
source_packages_dir=/Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages
xcodebuild \
  -workspace SunSmart.xcworkspace \
  -scheme SunSmart -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -derivedDataPath "$branding_tmp/SunSmartDerivedData" \
  -clonedSourcePackagesDirPath "$source_packages_dir" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  build CODE_SIGNING_ALLOWED=NO ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: `** BUILD SUCCEEDED **`; SunSmart compiles its normal common catalog and is unaffected by Lumineux grouping.

- [ ] **Step 9: Perform the final scope and worktree audit**

Run:

```bash
git status --short
git status --short -- SunSmart/Assets.xcassets SLGSync/Assets-SLGSync.xcassets
git diff -- Lumineux/Scripts/merge_assets.rb SunSmart/Assets.xcassets SLGSync/Assets-SLGSync.xcassets
git diff --check
git diff --cached --check
```

Expected: protected catalog status and protected diff commands print nothing; the merger has no diff; all previously recorded unrelated/staged/untracked work is still present; only approved Lumineux catalog organization, manifest, generator/test path handling, and documentation changes are new. Stop without pushing, installing, or launching the real-device app.

- [ ] **Step 10: Commit the documentation and final verification record**

Run:

```bash
git add Tests/Branding/README.md docs/lumineux-missing-assets.md docs/superpowers/plans/2026-08-31-lumineux-asset-catalog-grouping.md
git diff --cached --check
git commit -m "docs: record Lumineux asset grouping"
```

Expected: one local documentation commit. Do not push.
