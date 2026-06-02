# Data Incident Recovery

Use this workflow when players appear to have reset data after data environment or publishing changes.

## What Is Safe To Prove First

`DataManager` opens ProfileStore with a datastore name resolved from `DataEnvironment` and private `DataKeySecrets`. The per-player key is still `Player_<UserId>`.

The risky change is the source of the ProfileStore name:

- old runtime: `script:GetAttribute("Data_Key")`
- new runtime: `DataKeySecrets.Production.DataKey`

If old production used an uncaptured Studio-only `Data_Key`, current production may be reading a different namespace. That usually means old data is still in another namespace, not overwritten.

## Live Diagnostics

Use an authenticated admin-only command in a live server:

```text
/datadiag
```

It reports only redacted values: place id, environment, place role, key id, key fingerprint, key length, source, validity, and boot-mode validity. It never prints raw datastore keys.

Expected production main values:

```text
name=Production
role=Main
keyId=prod-historical-v1
valid=true
bootModeValid=true
```

Do not infer public-server state from local Studio alone.

## Emergency Rules

If live servers are saving default-looking profiles, shut down affected servers while investigating. Do not run `ResetData`, `HardResetData`, admin wipe commands, broad restore commands, or repeated experimental publishes.

Preserve current profiles even if they look wrong. They are evidence of which namespace was active during the incident.

## One Player First

Pick one affected user with known pre-incident progress. Use:

```text
/datarecover mode=dryrun userId=<UserId> source=production target=production
```

If the production namespace lacks old data, add the suspected historical namespace privately under `RecoveryStores` in `DataKeySecrets.lua`, then compare against that alias:

```text
/datarecover mode=dryrun userId=<UserId> source=historical-fallback target=production
```

If a different suspected uncaptured old `Data_Key` is found, add it privately under `RecoveryStores` in `DataKeySecrets.lua`, then reference only its alias:

```text
/datarecover mode=dryrun userId=<UserId> source=OldProductionCandidate target=production
```

The command prints summaries and fingerprints only. It does not print raw keys and does not restore unless explicitly confirmed.

## Restore Gate

Only restore one player after dry-run evidence proves the source namespace is correct:

```text
/datarecover mode=restore userId=<UserId> source=<alias> target=production confirm=RESTORE_ONE_PLAYER
```

This is one-player only. Broad migration requires a separate reviewed implementation and manual approval after the test player is verified in live UI.
