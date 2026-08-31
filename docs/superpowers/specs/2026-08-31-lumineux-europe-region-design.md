# Lumineux Europe Region Design

## Goal

Make the Lumineux target follow the existing SLGSync region behavior while using Europe instead of North America.

## Behavior

- Lumineux exposes Europe as its only server region.
- When no server region exists in Keychain, Lumineux saves Europe during app launch.
- An existing Keychain server region is preserved, matching SLGSync semantics.
- The main menu does not expose the server-selection entry for Lumineux.
- Other targets retain their current region defaults and menu behavior.

## Implementation

Use the existing `Lumineux` Swift compilation condition and extend the same three conditional branches already used by SLGSync:

1. Add a Lumineux branch to `ServerRegion.defaultRegions` returning `[.europe]`.
2. Add a Lumineux launch branch that saves `.europe` only when `Keychain.getServerRegion()` returns `nil`.
3. Include Lumineux among brands whose `MainMenuView` options omit `.serverSelection`.

No new user-visible text, data model, migration, or shared brand abstraction is required.

## Verification

- Run a regression contract that compiles the shared sources with the Lumineux flag and verifies the effective default-region and menu behavior.
- Run the existing Lumineux configuration checker.
- Build the Lumineux target for a signing-disabled generic iOS destination.
- Inspect the final diff to ensure only the approved branches and task documentation changed.
