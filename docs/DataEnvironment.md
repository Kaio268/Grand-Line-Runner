# Data Environment

Grand Tide Rush uses ProfileStore with a datastore name resolved from `DataKeySecrets.DataKey`. That value is the datastore namespace for player profiles. If it changes, existing profiles are still in Roblox DataStore, but the game looks in a different namespace and player data can appear wiped.

## Environment Policy

The public policy lives in `ServerScriptService.Data.DataEnvironment`. It contains place IDs, place roles, environment names, validation rules, and diagnostics. It does not contain raw datastore keys.

- Production main place: `110640828025742`
- Production AFK place: `122987301330026`
- Required production key id: `prod-release-v1`

Production main and AFK both resolve the same `Production` secret entry. That keeps both places on the same release production datastore environment when they are places inside the same Roblox experience/universe.

## Private Secrets

Create the private secrets module at:

```text
src/ServerScriptService/Data/DataKeySecrets.lua
```

This file is git-ignored. It must not be committed, pasted into public logs, or shared in screenshots.

Use `src/ServerScriptService/Data/DataKeySecrets.example.lua` or `docs/examples/DataKeySecrets.example.lua` as the shape. For the fresh release experience, production should use an intentional release namespace such as `GrandTideRush_Production_v1` with `KeyId = "prod-release-v1"`.

The `DataKey` is just the ProfileStore datastore namespace string used by code. It does not need to be created or registered in Roblox Dashboard. A new Roblox experience/universe starts with fresh data even if the same `DataKey` string is used elsewhere. Main and AFK share data only when they are places in the same experience/universe and use the same Production `DataKey`.

## Validation

`DataManager` resolves its key through `DataEnvironment.ResolveDataKey()` before `ProfileStore.New()`.

Live servers fail before profile startup when:

- `DataKeySecrets.lua` is missing.
- The selected environment entry is missing.
- `DataKey` or `KeyId` is blank, whitespace-only, `DefaultKey_123`, or another placeholder.
- A production place is not using `prod-release-v1`.
- A live place ID is not mapped to an environment.
- The DataManager boot mode does not match the place role.

Studio sets diagnostics and warns before errors so publish problems are visible during local checks. Diagnostics are written as workspace attributes:

- `DataEnvironment_Name`
- `DataEnvironment_PlaceRole`
- `DataEnvironment_PlaceId`
- `DataEnvironment_KeyId`
- `DataEnvironment_Valid`
- `DataEnvironment_BootModeValid`

Raw `DataKey` values are never written to attributes or logs.

## Publish Checklist

Before publishing either production place:

1. Confirm `src/ServerScriptService/Data/DataKeySecrets.lua` exists locally.
2. Confirm `git status --short --ignored` shows the secrets file as ignored, not staged.
3. Run the main Rojo build from `default.project.json`.
4. Run the AFK Rojo build from `afk.project.json`.
5. In Studio, verify `DataEnvironment_Name` is `Production`.
6. Verify `DataEnvironment_KeyId` is `prod-release-v1`.
7. Verify main reports `DataEnvironment_PlaceRole = Main`.
8. Verify AFK reports `DataEnvironment_PlaceRole = AFK`.
9. Run `/datadiag` only and compare key fingerprint/length without exposing the raw key.
10. Confirm no restore, migration, wipe, reset, or recovery write command is being run during publish.

## Rotation And Migration

Rotating `DataKey` without migration makes data appear wiped because ProfileStore opens a different datastore namespace.

A safe rotation should be treated as a data migration:

1. Add a new private key id and key material.
2. Keep the historical key readable during the migration window.
3. Build a migration path that reads old profiles and writes validated copies to the new namespace.
4. Verify sample users and rollback behavior in staging.
5. Switch production policy to the new required key id only after migration is complete.
6. Keep the old key preserved privately for rollback until the migration is no longer reversible.
