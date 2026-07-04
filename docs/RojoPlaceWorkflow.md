# Rojo Place Workflow

Grand Tide Rush has two Roblox places in one experience:

- Main Place, `Grand Tide Rush`: `128382161567643`
- AFK Lobby Place, `AFK Lobby`: `84534597236418`

Use one repo, but connect each place to its own Rojo project.

## Main Place

1. Open the main `Grand Tide Rush` place in Roblox Studio.
2. Verify the place ID before syncing:
   ```lua
   print(game.Name, game.PlaceId)
   ```
3. Serve the main project:
   ```sh
   rojo serve default.project.json
   ```
4. Connect Studio to `grand-tide-rush-main`.
5. Publish only to place `128382161567643`.

## AFK Lobby

1. Open the `AFK Lobby` place in Roblox Studio.
2. Verify the place ID before syncing:
   ```lua
   print(game.Name, game.PlaceId)
   ```
3. Serve the AFK project:
   ```sh
   rojo serve afk.project.json
   ```
4. Connect Studio to `grand-tide-rush-afk`.
5. Publish only to place `84534597236418`.

## Safeguards

- Never connect `default.project.json` to the AFK Lobby place.
- Never connect `afk.project.json` to the main place.
- Run `tools/validate-startup-build.ps1` against fresh Rojo build outputs before publishing.
- If the wrong boot script reaches the wrong place, the place guard should warn and stop booting.
- `afk.project.json` intentionally keeps `$ignoreUnknownInstances = true`; clean old polluted AFK instances manually after verifying the AFK place ID instead of relying on destructive deletion sync.
