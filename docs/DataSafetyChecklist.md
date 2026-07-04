# Data Safety Checklist

Use this checklist before publishing the fresh release Main place or AFK Lobby place.

## Place Setup

1. Confirm Main and AFK Lobby are two places inside the same Roblox experience/universe.
2. Confirm the Main place id matches `DataEnvironment.lua`, `DataInit.server.lua`, and `GrandLineRushEconomy.lua`.
3. Confirm the AFK Lobby place id matches `DataEnvironment.lua`, `AFKBoot.server.lua`, and `GrandLineRushEconomy.lua`.
4. Never connect `default.project.json` to the AFK Lobby place.
5. Never connect `afk.project.json` to the Main place.

## Key Setup

1. Confirm `src/ServerScriptService/Data/DataKeySecrets.lua` exists locally.
2. Confirm the real secrets file is ignored and not tracked by Git.
3. Confirm Production uses `KeyId = "prod-v1"`.
4. Confirm Production uses the intended release `DataKey`.
5. Confirm Production does not use `DefaultKey_123`, blanks, `REPLACE_ME`, `YOUR_KEY_HERE`, or any placeholder text.
6. Confirm Staging and Development use separate non-production keys.

## Build Checks

1. Run the main Rojo build from `default.project.json`.
2. Run the AFK Rojo build from `afk.project.json`.
3. Run `tools/validate-startup-build.ps1` against the fresh build outputs and confirm no stale `Data_Key` boot code is present.
4. Confirm no generated `.rbxlx` output is staged by accident.
5. Confirm `git status --short --ignored` does not show the real `DataKeySecrets.lua` as staged or tracked.

## Studio Checks

1. Start the Main place in Studio.
2. Verify `DataEnvironment_Name = Production`.
3. Verify `DataEnvironment_KeyId = prod-v1`.
4. Verify `DataEnvironment_PlaceRole = Main`.
5. Verify `DataEnvironment_BootModeValid = true`.
6. Run `/datadiag` and compare key fingerprint/length without sharing the raw key.
7. Repeat the same checks in the AFK Lobby place, expecting `DataEnvironment_PlaceRole = AFK`.

## Data Behavior Checks

1. Join with a test account in Main.
2. Make a small data change that should save.
3. Rejoin Main and confirm the change loads.
4. Enter AFK Lobby and confirm the same profile is used.
5. Return from AFK Lobby and confirm the profile is still consistent.

## Do Not Run During Publish

- Do not run `/datarecover mode=restore`.
- Do not run `/wipeplayer`.
- Do not run `/resetprogress`.
- Do not run `ResetData`, `HardResetData`, `LoadBackup`, or any migration command.
- Do not rotate the Production `DataKey` after release without a reviewed migration plan.
