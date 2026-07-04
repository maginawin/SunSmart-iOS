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

groups_file="SunSmart/Main/Group/Controller/GroupsViewController.swift"

assert_contains "$groups_file" "private struct PendingGroupTap" "Groups list must store pending tap metadata by stable group identity."
assert_contains "$groups_file" "let address: Address" "Pending group tap must keep the group address."
assert_contains "$groups_file" "private var pendingGroupTap: PendingGroupTap\\?" "Groups list must keep a pending group tap instead of a raw IndexPath."
assert_contains "$groups_file" "private func group\\(for address: Address\\) -> Group\\?" "Groups list must resolve the current group by address before acting."
assert_contains "$groups_file" 'first\(where: \{ \$0\.address\.address == address \}\)' "Group lookup must compare current group addresses."
assert_contains "$groups_file" "private func performPendingSingleTap\\(\\)" "Timer callbacks must execute the pending address-based single tap."
assert_contains "$groups_file" "private func groupHandleSingleTap\\(_ group: Group\\)" "Single tap handler must receive a resolved Group."
assert_contains "$groups_file" "tapTimer\\?\\.invalidate\\(\\)" "Pending tap cleanup must invalidate the timer."

assert_not_contains "$groups_file" "lastTappedIndexPath" "Groups list must not keep stale IndexPath as the pending tap identity."
assert_not_contains "$groups_file" "private func groupHandleSingleTap\\(_ indexPath: IndexPath\\)" "Single tap handler must not accept a stale IndexPath."
assert_not_contains "$groups_file" "groupHandleSingleTap\\(indexPath\\)" "Timer callback must not execute single tap by captured IndexPath."
assert_not_contains "$groups_file" "groupHandleSingleTap\\(lastTappedIndexPath\\)" "Fast multi-tap handling must not execute single tap by stale IndexPath."

echo "PASS: Groups tap target stability contract"
