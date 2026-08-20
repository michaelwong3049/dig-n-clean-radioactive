# Dig N Clean: Radioactive

Sweep the wasteland with a detector, haul what pings up through the soil with a magnet,
and get it home before the decay clock turns it to slag. Then scrub the fallout off it
and sell it — or put it on a pedestal and let it pay you forever.

- **[PLAN.md](PLAN.md)** — the design document. What the game is and why.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — the module map, the server/client boundary,
  the world-instance contract, and the tuning workflow. Read this before changing code.

## Layout

```
src/shared/   ->  ReplicatedStorage.Shared     pure math + Config data, used by both sides
src/server/   ->  ServerScriptService.Server   the one Script, plus Services/
src/client/   ->  StarterPlayer…Scripts.Client the one LocalScript, plus Controllers/
```

Balance lives entirely in `src/shared/Config/`. Retuning should never mean touching a
service.

## Getting started

Toolchain is pinned in [`rokit.toml`](rokit.toml) (Rojo 7.7).

```bash
rokit install       # installs rojo + selene
rojo serve          # then connect from the Rojo plugin in Studio
```

`ProfileStore` is vendored unmodified at `src/server/lib/ProfileStore.luau`, so there
are no package dependencies to install.

> **The place file is not in this repo.** The base camp has a versioned builder, but
> zones and tool models still live only in the gitignored `.rbxlx`. See the "world
> contract" section of ARCHITECTURE.md.

## Building the base camp

[`src/server/build/BaseCamp.luau`](src/server/build/BaseCamp.luau) is the source of
truth for `Workspace.BaseCamp`. It creates ordinary Roblox instances, so the finished
camp renders and runs exactly like geometry placed by hand.

1. Start `rojo serve` and connect the Rojo Studio plugin.
2. In Studio **Edit mode** (not while play-testing), open **View → Command Bar**.
3. Run:

   ```lua
   require(game.ServerScriptService.Server.build.BaseCamp).rebuild()
   ```

4. Confirm that `Workspace.BaseCamp` appeared, then save or publish the place.

The default floor centre is `CFrame.new(0, 0.9, 136)`. To build at another location,
pass a different origin to `rebuild`, for example:

```lua
require(game.ServerScriptService.Server.build.BaseCamp).rebuild(CFrame.new(20, 0.9, 136))
```

After changing the builder, reconnect/sync Rojo if needed and run `rebuild()` again.
Do not make lasting edits by dragging generated parts in Studio; the next rebuild will
replace them. GitHub stores the recipe, while the saved/published place stores the
instances players actually see.

## Working on it

Run both of these in Studio's command bar after changing anything in `Config/`:

```lua
require(game.ReplicatedStorage.Shared.Util.Spec).run()          -- design-intent assertions
require(game.ReplicatedStorage.Shared.Util.TuningReport).run()  -- the survivability matrix
```

In game: **F3** toggles the debug HUD, and `/radhelp` lists the tuning console commands
(`/zone`, `/dig`, `/gear`, `/flush`, `/dock`, `/clear`, `/pocket`).

Lint with [selene](https://kampfkarren.github.io/selene/) (`selene src`).
