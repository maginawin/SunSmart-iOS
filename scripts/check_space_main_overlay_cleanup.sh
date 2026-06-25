#!/usr/bin/env bash
set -euo pipefail

menu_file="SunSmart/Common/View/MenuPopView.swift"
space_file="SunSmart/Main/Space/Controller/SpaceViewController.swift"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

grep -q "static func hide(animation: Bool = true)" "$menu_file" \
  || fail "MenuPopView.hide must accept an animation parameter and keep a default call site"

grep -q "keyWindow().subviews.compactMap" "$menu_file" \
  || fail "MenuPopView.hide must collect all MenuPopView instances from keyWindow"

grep -q "popViews.forEach" "$menu_file" \
  || fail "MenuPopView.hide must dismiss all matching MenuPopView instances"

grep -q "hide(animation: false)" "$menu_file" \
  || fail "MenuPopView.show must remove existing menus before adding a new one"

grep -q "MenuPopView.hide(animation: false)" "$space_file" \
  || fail "SpaceViewController must proactively clear MenuPopView overlays"

grep -q "clearTransientWindowMenus" "$space_file" \
  || fail "SpaceViewController should use a scoped helper for transient menu cleanup"

echo "PASS: Space Main overlay cleanup contract is present"
