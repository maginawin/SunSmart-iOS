# Sensor Server Publication Retransmit Design

## Context

The existing SAVE Profile and group member mutation flows reuse the group synchronization path. That path builds profile sync data through `Node.getNodeSyncProfiles(group:)` and currently configures publication targets only for Sensor Server models through `ProfileType.sensorEnabled`.

The current configured Sensor Server publication targets are:

- Presence Detected Sensor Server for `occupancy_daylight`, `vacancy_daylight`, `occupancy`, and `vacancy` profiles.
- Ambient Light Sensor Server for `occupancy_daylight`, `vacancy_daylight`, and `daylight` profiles, limited to the group's selected ambient light sensor node.

The app does not configure Scene Server publication in this SAVE Profile path. This design does not add Scene Server publication behavior.

## Goal

When the app configures Sensor Server publication for a group profile, it should set publication retransmit based on the effective number of members in the group. For SAVE Profile this is the current member count. For add/remove member sync this is the final intended member count after the mutation:

- `0...3` members: retransmit count `2`, retransmit interval `100 ms`.
- `4+` members: retransmit count `1`, retransmit interval `100 ms`.

The publication period remains disabled. The changed setting is the publication retransmit field, not periodic publishing.

## Non-Goals

- Do not add Scene Server publication target configuration.
- Do not change Scene Store, Scene Delete, Light LC, schedule, switch, emergency fire, or calibration publication behavior.
- Do not change the publication target address, app key, friendship credentials, TTL, or publish period for Sensor Server publication.

## Design

Extend `ProfileType.sensorEnabled` to carry a target retransmit value, defaulting to `.disabled` so unrelated callers remain source-compatible where possible:

```swift
case sensorEnabled(
    sensorModels: [Model],
    publishAddress: Address,
    delay: TimeInterval = 0,
    retransmit: Publish.Retransmit = .disabled
)
```

Add a small helper near the group/profile sync logic to compute the target retransmit from the group's effective member count. For normal SAVE Profile sync, the effective count is `group.nodes.count`. For group member mutation sync, the effective count is the final intended count after applying `inNodes` and `outNodes`, because removed nodes may still appear in `group.nodes` until the unsubscribe flow finishes. The helper should return `Publish.Retransmit(2, timesWithInterval: 0.1)` for groups with three or fewer effective members, and `Publish.Retransmit(1, timesWithInterval: 0.1)` for groups with four or more effective members.

Update `Node.getNodeSyncProfiles(group:)` or its calling sync context so Sensor Server publication sync is triggered when either the publication target address is wrong or the publication retransmit does not match the effective group-size rule. This replaces the current address-only checks for the Sensor Server publication enable path.

When generating messages in `ProfileType.getMessageHandles(node:)`, use the retransmit value carried by `.sensorEnabled` in `ConfigModelPublicationSet(Publish(...))`. Keep `period` behavior unchanged: disabled unless the existing `delay` argument is greater than zero.

## Success Criteria

The sync success check for `.sensorEnabled` must verify the full target publication configuration used by this feature:

- Sensor Server publication address equals the group address.
- Sensor Server publication retransmit count and interval equal the expected values for the effective group size.

This prevents a model with the correct target address but stale retransmit settings from being treated as already synchronized.

## Data Flow

SAVE Profile:

1. `ProfileSettingsViewController.saveAction()` persists the selected profile through the existing callback.
2. If any group node needs sync, it opens `SyncDevicesViewController(type: .group(...))`.
3. The sync controller calls `node.getSyncData(type: .group(group))`.
4. `getNodeSyncProfiles(group:)` evaluates Sensor Server publication target and retransmit.
5. `.sensorEnabled` produces `ConfigModelPublicationSet` with the expected retransmit.

Add or remove members:

1. `GroupMembersViewController.saveAction()` computes added and removed nodes.
2. It opens `SyncDevicesViewController(type: .group(group, inNodes: addNodes, outNodes: exitNodes))`.
3. Existing and added in-group nodes are evaluated through the same `.group` sync builder.
4. The sync setup computes the final intended member count after `addNodes` and `exitNodes`, so retransmit changes are picked up when the member count crosses the four-device threshold.

## Error Handling

This change does not introduce new user-visible errors. `ConfigModelPublicationSet` failures should continue to follow the existing sync failure handling path. The implementation should avoid force-unwrapping new optional message creation paths beyond existing local patterns when practical.

## Testing

Add focused tests or lightweight verification around the sync-building logic where the project can support it:

- A group with `0...3` effective members generates Sensor Server publication sync with retransmit count `2` and interval `100 ms`.
- A group with `4+` effective members generates Sensor Server publication sync with retransmit count `1` and interval `100 ms`.
- A Sensor Server model with the correct target address but wrong retransmit is included in `.sensorEnabled`.
- A Sensor Server model with the correct target address and correct retransmit is not included again.
- Existing SAVE Profile and group members flows still route through `.group` sync without adding Scene Server publication tasks.
