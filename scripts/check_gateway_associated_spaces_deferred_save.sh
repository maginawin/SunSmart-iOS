#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
associated_controller="SunSmart/Main/Device/Gateway/Controller/GatewayAssociatedSpacesController.swift"

rg -n "NetworkRequest\.shared\.request\(\.gateway(Bind|Unbind)Space" "$associated_controller" \
  && fail "Associated Spaces picker must not bind or unbind spaces before Gateway SAVE."

rg -n "gateway\.save\(\)|gateway\.associatedSpaces\.(append|remove|removeAll)" "$associated_controller" \
  && fail "Associated Spaces picker must not persist the Gateway model before Gateway SAVE."

rg -n "associatedSpacesSelectCallback\?\(self\.selectSpaces\)" "$associated_controller" >/dev/null \
  || fail "Associated Spaces picker must return the selected draft spaces to the Gateway page."

rg -n "private func gatewayAssociatedSpacesToDisplay\(\) -> \[GatewaySpaceData\]" "$gateway_controller" >/dev/null \
  || fail "Gateway page must render Associated Spaces from a draft-aware source."

rg -n "private func saveAssociatedSpacesIfNeeded\(" "$gateway_controller" >/dev/null \
  || fail "Gateway SAVE must own cloud bind/unbind persistence for Associated Spaces."

rg -n "setGatewayModel\.associatedSpaces = spaces" "$gateway_controller" >/dev/null \
  || fail "Gateway page must apply Associated Spaces picker results to the unsaved draft model."

echo "PASS: Gateway Associated Spaces changes are deferred until Gateway SAVE."
