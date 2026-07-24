#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

planner="SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift"
node_sync="SunSmart/Common/Data/Node+SyncData.swift"
operation_model="SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"

bash scripts/check_fast_add_task_checkpoint_tracker.sh

rg -n -F 'FastAddTaskCheckpointTracker<MeshMessageHandle>' "$planner" >/dev/null \
  || fail "Fast Add plan must own a task checkpoint tracker"
rg -n -F 'func recordSuccessfulMessageHandle(_ messageHandle: MeshMessageHandle)' "$planner" >/dev/null \
  || fail "Fast Add plan must expose task checkpoint recording"
rg -n -F 'taskCheckpointTracker.recordSuccess(for: messageHandle)' "$planner" >/dev/null \
  || fail "Fast Add plan must forward successful handles to the tracker"
rg -n -F 'let deferredBatch = makeTaskCheckpointBatch(tasks: plan.deferredTasks)' "$planner" >/dev/null \
  || fail "Light Fast Add must prepare deferred handles and checkpoints in one batch"
rg -n -F '+ deferredBatch.messageHandles' "$planner" >/dev/null \
  || fail "Light Fast Add must append the prepared deferred handles"
rg -n -F 'taskCheckpointTracker: deferredBatch.tracker' "$planner" >/dev/null \
  || fail "Light Fast Add must reuse the tracker from the same prepared batch"
rg -n -F 'let messageHandles = task.makeMessageHandles()' "$planner" >/dev/null \
  || fail "Fast Add batch must generate each deferred task handle list once"

if rg -n -F 'plan.deferredTasks.flatMap { $0.makeMessageHandles() }' "$planner" >/dev/null; then
  fail "Light Fast Add must not regenerate deferred handles for the append list"
fi
if rg -n -F 'makeTaskCheckpoints(tasks: plan.deferredTasks)' "$planner" >/dev/null; then
  fail "Light Fast Add must not regenerate deferred handles for checkpoints"
fi

rg -n -F 'task.operationType.isSuccessful' "$planner" >/dev/null \
  || fail "Task checkpoint must use the existing strict operation success predicate"
rg -n -F 'syncDatas.filter { !usesTaskScopedVerification($0) }' "$planner" >/dev/null \
  || fail "Light batch verification must exclude task-scoped operations"
rg -n -F 'taskCheckpointTracker.hasFailure' "$planner" >/dev/null \
  || fail "Final Fast Add result must include pending or failed checkpoints"
rg -n -F 'taskCheckpointTracker: FastAddTaskCheckpointTracker(checkpoints: [])' "$planner" >/dev/null \
  || fail "Sensor Fast Add must continue to use an empty task checkpoint tracker"

rg -n -F 'effectiveMemberCount: effectiveMemberCount' "$planner" >/dev/null \
  || fail "Fast Add must preserve effective member count"
rg -n -F 'sensorPublicationSyncMode: SensorPublicationSyncMode = .strictTarget' "$node_sync" >/dev/null \
  || fail "Profile generation must remain strict by default"
rg -n -F 'return publication.retransmit == retransmit' "$node_sync" >/dev/null \
  || fail "Strict sensor publication comparison missing"
rg -n -F '!$0.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: retransmit)' "$operation_model" >/dev/null \
  || fail "sensorEnabled verification must compare the exact retransmit target"

if rg -n 'getNeedSyncGroup|legacyCompatible' "$planner" >/dev/null; then
  fail "Fast Add planner must not use the Group page compatibility result"
fi

rg -n -F 'for path in proximityLightingPath?.paths ?? []' "$node_sync" >/dev/null \
  || fail "empty Path must continue to produce an empty path iteration"
rg -n -F 'for zone in proximityLightingPath?.zones ?? []' "$node_sync" >/dev/null \
  || fail "empty Path must continue to produce an empty zone iteration"

classic="SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift"
professional="SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift"

for controller in "$classic" "$professional"; do
  rg -n -F 'if let plan = self?.fastAddGroupSyncPlan(containing: messageHandle)' "$controller" >/dev/null \
    || fail "$controller must resolve the shared Fast Add plan in the success callback"
  rg -n -F 'plan.recordSuccessfulMessageHandle(messageHandle)' "$controller" >/dev/null \
    || fail "$controller must record the checkpoint after updating Node"
  rg -n -U 'node\.updateData\(message: messageHandle\.message\)\n[[:space:]]+plan\.recordSuccessfulMessageHandle\(messageHandle\)' "$controller" >/dev/null \
    || fail "$controller must update Node before evaluating the task checkpoint"
  rg -n -F 'self.recordFastAddGroupSyncFailure(plan)' "$controller" >/dev/null \
    || fail "$controller must preserve real message failure handling"
done

echo "PASS: Fast Add dual-scene task-scoped verification"
