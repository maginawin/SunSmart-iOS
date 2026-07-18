#!/usr/bin/env bash
set -u

source_file="SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift"
failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local text="$1"
  local pattern="$2"
  local message="$3"

  grep -Fq "$pattern" <<<"$text" || fail "$message"
}

assert_not_contains() {
  local text="$1"
  local pattern="$2"
  local message="$3"

  if grep -Fq "$pattern" <<<"$text"; then
    fail "$message"
  fi
}

source_text="$(<"$source_file")"
update_ui_state="$(sed -n '/^    private func updateUIState() {$/,/^    }$/p' "$source_file")"
update_footer_state="$(sed -n '/^    private func updateFooterViewState() {$/,/^    }$/p' "$source_file")"

assert_contains "$source_text" \
  'private var isSearchingForDevices: Bool {' \
  'Candidate footer must define one source of truth for the active device-search state.'

assert_contains "$source_text" \
  'state == .scanning && (isRefresh || lightSeningMode)' \
  'The shared search-state predicate must preserve the existing scan, refresh, and light-sensing semantics.'

assert_not_contains "$update_ui_state" \
  'revokeBtn.isHidden =' \
  'updateUIState must not independently write revoke visibility.'

assert_not_contains "$update_ui_state" \
  'footerView.addSelectedBtn.isHidden =' \
  'updateUIState must not independently write Add Selected visibility.'

assert_not_contains "$update_ui_state" \
  'footerView.setBatchControlsHidden' \
  'updateUIState must not independently write batch-control visibility.'

assert_contains "$update_ui_state" \
  'updateFooterViewState()' \
  'Every general UI refresh must finish through the centralized footer renderer.'

assert_contains "$update_footer_state" \
  'revokeBtn.isHidden = !isSearchingForDevices' \
  'Footer rendering must show revoke only while devices are actively being searched.'

assert_contains "$update_footer_state" \
  'footerView.addSelectedBtn.isHidden = hidesSelectionControls || isSearchingForDevices' \
  'Footer rendering must hide Add Selected for virtual targets or while searching.'

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'PASS: Professional Candidate footer buttons have one mutually exclusive visibility source.\n'
