#!/usr/bin/env bash
set -euo pipefail

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  expected pattern: $pattern"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    echo "FAIL: $message"
    echo "  file: $file"
    echo "  unexpected pattern: $pattern"
    exit 1
  fi
}

settings_file="SunSmart/Common/Data/LabSettings.swift"
lab_file="SunSmart/Main/Site/Controller/LabViewController.swift"
helper_file="SunSmart/Common/Data/LightGroupControlCommandSender.swift"
ack_file="SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift"
lights_file="SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift"
light_detail_file="SunSmart/Main/Device/Controller/DeviceLightViewController.swift"
groups_file="SunSmart/Main/Group/Controller/GroupsViewController.swift"
group_file="SunSmart/Main/Group/Controller/GroupViewController.swift"
en_strings="SunSmart/en.lproj/Localizable.strings"
zh_strings="SunSmart/zh-Hans.lproj/Localizable.strings"

test -f "$helper_file" || {
  echo "FAIL: Light/Group TTL helper is missing"
  echo "  file: $helper_file"
  exit 1
}

assert_contains "$settings_file" "overrideLightGroupControlTTL" "LabSettings must store the TTL override switch"
assert_contains "$settings_file" "lightGroupControlTTL" "LabSettings must store the TTL value"
assert_contains "$settings_file" "lightGroupControlTTLOverride" "LabSettings must expose optional TTL override"
assert_contains "$settings_file" "min\\(max\\(.*0\\).*127\\)" "LabSettings must clamp TTL to 0...127"

assert_contains "$lab_file" "overrideLightGroupControlTTL" "Lab screen must show the TTL override switch"
assert_contains "$lab_file" "light_group_control_ttl_scope" "Lab screen must explain the affected scope"
assert_contains "$lab_file" "lightGroupControlTTL" "Lab screen must expose the TTL value"
assert_contains "$lab_file" "visibleRows" "Lab screen must use dynamic rows so TTL value is hidden when override is disabled"
assert_contains "$lab_file" "visibleRows\\.count" "Lab screen row count must follow visible rows"
assert_contains "$lab_file" "tableView\\.reloadData\\(\\)" "Lab screen must refresh visible rows when the TTL override switch changes"
assert_not_contains "$lab_file" "Row\\.allCases\\.count" "Lab screen must not always show all Lab rows"
assert_not_contains "$lab_file" "lightGroupControlTTLScope" "Lab screen must not show a separate TTL scope row"
assert_contains "$lab_file" "light_group_control_ttl_range\"\\.localizedString[[:space:]]*\\+[[:space:]]*\"\\\\n\\\\n\"[[:space:]]*\\+[[:space:]]*\"light_group_control_ttl_scope\"\\.localizedString" "TTL input dialog must show range and scope text together"

assert_contains "$helper_file" "enum LightGroupControlCommandSender" "Helper must define LightGroupControlCommandSender"
assert_contains "$helper_file" "LabSettings\\.lightGroupControlTTLOverride" "Helper must read Lab TTL override centrally"
assert_contains "$helper_file" "setNodeOnOff" "Helper must support node on/off"
assert_contains "$helper_file" "setNodeLightness" "Helper must support node lightness"
assert_contains "$helper_file" "setNodeColorTemperature" "Helper must support node CCT"
assert_contains "$helper_file" "identify" "Helper must support single-light Identify"
assert_contains "$helper_file" "setGroupOnOff" "Helper must support group on/off"
assert_contains "$helper_file" "setGroupLightness" "Helper must support group lightness"
assert_contains "$helper_file" "setGroupColorTemperature" "Helper must support group CCT"
assert_contains "$helper_file" "setAllOnOff" "Helper must support all lights on/off"
assert_contains "$helper_file" "setAllLightness" "Helper must support all lights lightness"
assert_contains "$helper_file" "defaultTTL: ttlOverride" "Helper must pass the Lab TTL override to MeshAPI"

assert_contains "$ack_file" "defaultTTL: UInt8\\? = nil" "ACK tracker must accept a TTL override"
assert_contains "$ack_file" "defaultTTL: defaultTTL" "ACK tracker must pass TTL override to MeshAPI"

assert_contains "$lights_file" "LightGroupControlCommandSender\\.setNodeOnOff" "Lights list single-light on/off must use helper"
assert_contains "$lights_file" "LightGroupControlCommandSender\\.setAllOnOff" "All lights on/off must use helper"
assert_contains "$lights_file" "LightGroupControlCommandSender\\.setAllLightness" "All lights brightness must use helper"

assert_contains "$light_detail_file" "LightGroupControlCommandSender\\.identify" "Single-light Identify must use helper"
assert_contains "$light_detail_file" "LightGroupControlCommandSender\\.setNodeOnOff" "Light detail on/off must use helper"
assert_contains "$light_detail_file" "LightGroupControlCommandSender\\.setNodeLightness" "Light detail brightness must use helper"
assert_contains "$light_detail_file" "LightGroupControlCommandSender\\.setNodeColorTemperature" "Light detail CCT must use helper"

assert_contains "$groups_file" "LightGroupControlCommandSender\\.setGroupOnOff" "Group list on/off must use helper"
assert_contains "$group_file" "LightGroupControlCommandSender\\.setGroupOnOff" "Group detail on/off must use helper"
assert_contains "$group_file" "LightGroupControlCommandSender\\.setGroupLightness" "Group brightness must use helper"
assert_contains "$group_file" "LightGroupControlCommandSender\\.setGroupColorTemperature" "Group CCT must use helper"
assert_contains "$group_file" "LightGroupControlCommandSender\\.setNodeOnOff" "Group member single-light on/off must use helper"

assert_contains "$en_strings" "override_light_group_control_ttl" "English strings must include TTL override switch"
assert_contains "$en_strings" "light_group_control_ttl" "English strings must include TTL value row"
assert_contains "$en_strings" "light_group_control_ttl_scope" "English strings must include scope description"
assert_contains "$zh_strings" "override_light_group_control_ttl" "Simplified Chinese strings must include TTL override switch"
assert_contains "$zh_strings" "light_group_control_ttl" "Simplified Chinese strings must include TTL value row"
assert_contains "$zh_strings" "light_group_control_ttl_scope" "Simplified Chinese strings must include scope description"
assert_contains "$zh_strings" "\"lab\" = \"实验室\";" "Simplified Chinese strings must translate the Lab title"
assert_contains "$zh_strings" "\"display_light_ack_details\" = \"显示灯控 ACK 详情\";" "Simplified Chinese strings must translate light ACK details"
assert_contains "$zh_strings" "\"override_light_group_control_ttl\" = \"覆盖灯具/分组控制 TTL\";" "Simplified Chinese strings must translate the TTL override switch"
assert_contains "$zh_strings" "\"light_group_control_ttl\" = \"灯具/分组控制 TTL\";" "Simplified Chinese strings must translate the TTL value row"
assert_contains "$zh_strings" "\"light_group_control_ttl_scope\" = \"仅影响灯具和分组的灯控命令，其他功能不受影响。\";" "Simplified Chinese strings must translate the TTL scope description"
assert_not_contains "$zh_strings" "\"display_light_ack_details\" = \"Display light ACK details\";" "Simplified Chinese strings must not leave light ACK details in English"

while IFS= read -r file; do
  case "$file" in
    "$helper_file"|"$lights_file"|"$light_detail_file"|"$groups_file"|"$group_file")
      ;;
    *)
      assert_not_contains "$file" "LightGroupControlCommandSender" "TTL helper must not be wired outside approved Light/Group control entry points"
      ;;
  esac
done < <(rg -l "LightGroupControlCommandSender" SunSmart --glob '*.swift' || true)

echo "PASS: Lab Light/Group TTL contract"
