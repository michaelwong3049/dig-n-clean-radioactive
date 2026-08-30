# ARCHITECTURE

The code cites this file by name in a dozen headers. This is that file: the map, the
boundaries, and the handful of contracts that are not visible from any single module.

`PLAN.md` is the design. This is the shape the design was built into.

---

## Module map

Rojo mounts three trees. Nothing else in the place is source-controlled.

```
src/shared/     ->  ReplicatedStorage.Shared          (Folder)
src/server/     ->  ServerScriptService.Server        (Script — the one Script in the game)
src/client/     ->  StarterPlayer.StarterPlayerScripts.Client   (LocalScript)
```

```
src/
  shared/                     pure logic + data. Required by BOTH sides.
    Config/                   DATA ONLY. No logic, no requires outside Config/.
      Tuning.luau             global knobs — every magic number in the game
      Rarity.luau             the 8 rarities + the roll-on modifiers
      Stages.luau              the 6 stages
      Gear.luau               the 6 upgrade tracks
      Items.luau              the item catalogue (+ id / stage-rarity indexes)
      ToolTiers.luau          per-tier look: scale, colours, material, glow
    ItemModels/               versioned item-art factories; nil keys use placeholders
      init.luau               model-key registry used by haul + exhibition rendering
      BottleCap.luau          clean 21-crimp crown cap
      DentedTinCan.luau       asymmetrically crushed ribbed food tin
      HouseKey.luau           pressed-silver key with open bow and stepped teeth
      SteelRod.luau           dark reinforcing-steel offcut with diagonal ribs
      Wristwatch.luau         stopped analog dial on a linked oval bracelet
    Util/
      Ticker.luau             the fixed-timestep clock everything runs on
      Spec.luau               design-intent assertions — run after retuning
      TuningReport.luau       generates the survivability matrix from Config/
    Net.luau                  every remote in the game, one table
    Radiation.luau            pure math: exposure, burn, survivable seconds
    Decay.luau                pure math: the decay clock
    Contamination.luau        pure math: the cleaning gate
    StatResolver.luau         profile -> stats. The ONLY place gear math happens.

  server/
    init.server.luau          bootstrap: explicit ORDER, two-phase init/start
    lib/ProfileStore.luau     vendored, unmodified (MadStudioRoblox/ProfileStore)
    build/ModelGallery.luau   manual temporary lot for reviewing all real item models
    Services/
      DataService             ProfileStore wrapper, session-locked persistence
      StageService             who is standing where
      ExposureService         the rad meter, burn, blackout, dropped bags
      DigService              the buried signal field, sweep and haul
      EconomyService          what an item is worth, and the till
      DeconService            docking, scrubbing and racking at every base; sell() exists, no world trader triggers it currently
      ToolService             puts the right model in the player's hands
      DebugService            the tuning console + debug telemetry

  client/
    init.client.luau          bootstrap: mirrors the server's ORDER / init / start
    Controllers/
      DetectorController      sweep dial, ping audio, hold-to-pull
      StationController       the station panel (trader, decon, shop, plot, pedestal)
      HudController           rad meter, vignette, distortion, blackout curtain
      GeigerController        the click bed (reads HudController)
      DebugHudController      every number at once. F3 toggles.
```

---

## Boot

`src/server/init.server.luau` is the only `Script`. Everything else is a `ModuleScript`
it requires. Same on the client with `init.client.luau`.

Two phases, and the split is what lets services reference each other without a
load-order puzzle:

- **`init()`** — build your own state. Do NOT touch another service.
- **`start()`** — connect events and call into other services. Everything exists by now.

Either function may be omitted. `ORDER` in each bootstrap is the dependency graph, and
it is the only place that graph is written down. A module dropped into `Services/` or
`Controllers/` without being added to `ORDER` warns loudly at boot rather than silently
never running.

---

## Server/client boundary

The server owns every number that matters. Controllers render and predict; they never
decide. Anything touching cash, radiation, or item state is the server's call.

Two rules worth stating separately because they are the ones that get eroded:

1. **The field never leaves the server; your own reveal radius may.** This rule used
   to be absolute — `DigService` sent an angle and a strength and nothing else. The
   reveal detector made that impossible to keep as written: a signal inside your
   radius stands up in the world as an **aura**, a real part every client can see, so
   pretending its position is secret would protect nothing while making the HUD worse.

   The rule is therefore scoped rather than dropped:

   * `SweepState` carries contacts **inside the player's own detector radius**, as
     **offsets relative to that player** — never world coordinates, never a uid, and
     never anything the player is not already looking at a glow for.
   * Everything else in the stage — the other forty-odd buried signals — stays exactly
     as invisible as it was.

   That is the property actually worth defending. A digging game that replicates the
   whole field has an ESP script written for it inside a week, and the rarity economy
   is the entire product; a game that tells you where the thing you can already see is
   has lost nothing. The single part the player is actively hauling remains fine for
   the same reason it always was: they are standing on it.

   **Auras are public on purpose.** Every player sees every aura, not just whoever
   revealed it. The cost — a cheap detector tailing an expensive one — is written down
   in `Config/Tuning` under "the reveal". Revealing is still not the same as taking:
   `maxRarity` and `depth` gate the *pull* per-player, so a Bent Coil standing in an
   Oracle's glow gets told it cannot lock on.

2. **The client never names what it wants to dig.** It sends "I am holding the button".
   The server decides which signal that means from where the player actually is.

`Shared/Radiation`, `Shared/Decay` and `Shared/Contamination` are `require`d by both
sides on purpose: the number on the HUD and the number that puts the player down come
out of the same function, so they cannot disagree.

---

## The world contract

`StageService`, `ExposureService`, `DeconService` and `ToolService` read **attributes on
instances in Workspace**, not paths in code. The stages and tool models currently live
only in the `.rbxlx`. The base camp is the exception: its authoritative recipe is
`src/server/build/BaseCamp.luau`, then the generated instances are saved or published
with the place.

### Instances that must exist

| Instance | Read by | If missing |
|---|---|---|
| `Workspace.Stages` (Folder) | `StageService:36`, `DigService:251` | nobody is ever in a stage; no signals spawn |
| `Workspace.Stages.Stage<id>` (BasePart) | `DigService:255`, `DebugService:142` | that stage spawns no signals; `/stage <id>` refuses |
| `Workspace.SignalAuras` (Folder) | created and owned by `DigService` | nothing — it is created on demand at runtime and wiped on boot. Do **not** hand-edit or save it with the place; `DigService.init` destroys any copy it finds, because a saved one would be full of glows over empty ground. |
| `Workspace.BaseCamp` (Model) | `DeconService:54` | `stationOf` is always nil — no docking, scrubbing or selling, anywhere. Generate it with `BaseCamp.rebuild()` as documented in the README. |
| a `SpawnLocation` anywhere in `Workspace` | `ExposureService:221` | blackout respawns to a hardcoded `CFrame.new(0, 8, 0)` |
| `ReplicatedStorage.Assets.Tools` (Folder) | `ToolService:39` | **`require(ToolService)` throws** — see the note below |

`ToolService` reaches its library with a bare dot-index at module scope, so an absent
`Assets` folder is a load-time error rather than a graceful degrade. The boot `pcall`
catches it and logs `[boot] FAILED to require ToolService`; the other seven services
still start.

### Attributes

| Where | Attribute | Type | Meaning |
|---|---|---|---|
| `Workspace.Stages.*` (BasePart) | `StageId` | number | Which `Config/Stages` entry this volume is. Y is ignored; smallest containing XZ volume wins. |

**The stage plate contract**, enforced by `build/StageFields.luau` and checked by
`World.verify()`. Two *independent* lookups have to agree on the same part, and
missing either one fails silently in a different direction:

- `DigService.stagePart` finds it **by name** — `Workspace.Stages.Stage<id>`. Miss this
  and no signals ever spawn there.
- `StageService.stageAt` finds it **by attribute** — `StageId`. Miss this and nobody is
  ever considered to be standing in it, so the field fills with items no one can find.

Also required, and each corresponds to a real silent failure:

| Rule | Why |
|---|---|
| A single `BasePart`, direct child of `Workspace.Stages` | Both lookups use non-recursive child access. Terrain cannot be a stage — there are no raycasts anywhere in `src/`. |
| Rotation must be identity | Items bury on the flat top face; a tilted plate puts them under the visible ground. |
| Top face at `Stages.SURFACE_Y` | That plane *is* the walk surface. |
| Thickness ≥ max burial depth (`Tuning.DIG_DEPTH_*`, currently 13.2) | The haul part rises from below the top face; a thin plate lets it show through the underside. |
| `Workspace.Stages` holds plates and **nothing else** | A decoration carrying a `StageId` becomes a stage, and smallest-area-wins means a stray barrel silently becomes the stage you are in. Decor lives in `Workspace.Scenery`. |
| any BasePart in `Workspace` | `Shower` | boolean | Decon shower. Flushes player exposure, does **not** touch items. Since `build/Plots.luau`, each base's cleansing station carries this **on the same part** as `StationKind="decon"` — one stop for both, sharing one `Radius` — rather than two separate structures the way camp used to have them. |
| ″ | `Radius` | number | Shower radius in studs. Optional, default 10. |
| any BasePart **anywhere in `Workspace`** | `StationKind` | `"decon"` \| `"trader"` \| `"shop"` \| `"plot"` \| `"pedestal"` | What you are standing at. Decon freezes decay clocks; trader is a till; shop sells one gear track; plot is an exhibition claim board; pedestal is one display slot. |
| ″ | `StationId` | string | Discriminator within a kind. For `"shop"` it is the **exact `Gear.TRACKS` spelling** (`"Detector"`, `"Suit"`, …). For `"plot"` it is the plot number; for `"pedestal"` it is `"<plot>:<slot>"`. |
| ″ | `Radius` | number | Station radius in studs. Optional, default 12. |
| ″ | *CollectionService tag* `Station` | — | Index only — `StationService` scans tagged parts instead of walking Workspace. `Kit.build` adds it whenever it sets `StationKind`, and `World.verify()` asserts attribute and tag agree in **both** directions. The attribute stays the source of truth. |
| `ReplicatedStorage.Assets.Tools.<Track>.T<n>` (Model) | `HoldCFrame` | CFrame | Offset from the attach point. Optional, defaults to `CFrame.new()`. Tuned in Studio against a live character. |
| ″ | `HoldPart` | string | Body part to weld to. **Optional.** Absent, set to `"RightHand"`, or naming a part the character lacks all fall through to the right hand (R15 `RightHand`, then R6 `Right Arm`). Set it to `HumanoidRootPart` for the detector, which must not bob. |
| ″ | *PrimaryPart* | — | Must be set (the `Grip`). The model's pivot is the handle. |
| a `Player` | `DebugCmd` | string | Scriptable entry point to the tuning console (`DebugService:308`). Set it and the line runs, then the attribute is cleared so the same line can repeat. Exists because Studio's command bar gets its own module cache and cannot reach the live service. |

`<Track>` is one of `Detector`, `Magnet`, `Cleaner`, and `T<n>` indexes the matching
list in `Config/Gear.luau`.

> **Remaining gap:** the place file is gitignored, and three things still cannot be
> reconstructed from the repository alone.
>
> 1. **The tool models** (`ReplicatedStorage.Assets.Tools`) are genuinely hand-authored
>    — unions, a `SpecialMesh`, an imported detector model — so they stay binary. They
>    are not Rojo-managed and never will be.
> 2. **`MaxPlayers = 6`** is a Studio *Game Settings* value, not repo state. It has to
>    be 6 for the six exhibition plots to be 1:1 with players.
> 3. **Everything else is now code.** `build/World.rebuild()` regenerates the hub, the
>    camp, the radiation field, the shops, the plots (each with its own cleansing
>    station), the scenery and the Lighting, and then runs `World.verify()` over the
>    result. A fresh clone needs one command.

---

## Persistence

`DataService` is the only module that may touch DataStores. If you find yourself
calling `DataStoreService` anywhere else, stop.

Session locking is not optional here. Two servers writing one player's exhibit and cash
would duplicate income, and duplicated income in a game with passive earnings is
unrecoverable.

`TEMPLATE` in `DataService` is the schema. `Reconcile()` fills in keys added to it
later, so **adding** a field is safe for existing saves. **Removing** one is not — bump
`STORE_VERSION` if you ever need a clean slate.

ProfileStore's constraints on stored data: no gaps in numeric arrays, no mixed
numeric/string keys in one table, no Instances, no userdata (`Vector3`, `CFrame`, …).
Serialize before you store.

### The logout rule

Every carried item freezes on session end (`Tuning.FREEZE_ON_LOGOUT`). Slagging a
player's bag while they were offline is the fastest way to lose them, and it punishes a
thing that isn't play.

`DataService` then **thaws on rejoin**, which is a deliberate deviation. `Decay.freeze()`
is one-way, so a literal permanent freeze would make "dig a Legendary, log out, log back
in" a zero-risk way to defuse any item — strictly optimal, and it would gut PLAN §3.6.
Thawing keeps the promise that matters (nothing rots while you are away) without paying
for it with the whole mechanic. To restore the literal reading, delete `thawCarry()` and
its call site.

---

## Data schemas

A carried item — `Decay.CarriedItem`, plus `patches` which `DigService` adds when the
item leaves the ground:

```lua
{
    uid      = "…",      -- GUID; also the signal's uid
    itemId   = "…",      -- key into Config/Items
    rarity   = "Rare",
    modifier = "None",
    elapsed  = 0,        -- seconds of DECAY time. NEVER a wall-clock timestamp.
    frozen   = false,    -- true once docked / racked / logged out
    patches  = { 3, 1 }, -- contamination hardnesses; empty = clean
}
```

`elapsed` being a duration rather than a timestamp is the single most important choice
in the save format. Storing `unearthedAt = os.time()` looks fine and then silently slags
every player's backpack the first time someone logs off for a day.

The profile itself — `TEMPLATE` in `DataService`, which is the authoritative copy:

```lua
{
    cash = 0, xp = 0, level = 1,
    gear    = { detector = 1, magnet = 1, cleaner = 1, suit = 1, boots = 1, satchel = 1 },
    carry   = {},   -- array of the carried item above. The backpack.
    locker  = {},   -- Quarantine Locker: found, not yet cleanable.
    exhibit = { slots = 8, pedestals = {}, bankedCash = 0, bankedAt = 0 },  -- all 8 stands free; `slots` no longer changes
    discovered  = {},  -- itemId -> true, drives the museum
    perks       = {},  -- perkId -> true, read by StatResolver
    multipliers = {},  -- rebirth / gamepass / pet, pre-summed. Read by StatResolver.
    cleanTokens = 0, rebirths = 0,
    railStations = {},
    stats = { deepestStage = 1, itemsCleaned = 0, slagged = 0, dives = 0 },
}
```

`multipliers` is the key every rebirth, gamepass and pet bonus lives under; without it
they would have nowhere to go, since `StatResolver` is the only place gear math happens.

---

## Two failure states, kept apart

The design has two ways to go down and they must never bleed into each other:

| | source | shielded by | meter | screen |
|---|---|---|---|---|
| **Exposure** | ambient **+** what you carry | suit (ambient) / satchel (carried) | `exposure` → 100 | **green** |
| **Burn** | ambient only, past suit tolerance | suit tolerance | `health` → 0 | **white** |

Consequences that were both bugs in the first draft, and are now pinned by `Util/Spec`:

- Suit tolerance is checked against **ambient only**. If carried emission counted toward
  burn, a full backpack would trigger the "you should not be here" white screen inside
  your own rated stage.
- The suit does **not** shield you from your own backpack — the loot is inside the suit
  with you. That is what gives the Satchel track its real job, and without it the greed
  dial stops working the moment you buy a mid-tier suit.

White is used exactly once in this entire game, which is why it reads instantly.

---

## Tuning workflow

`Config/` is the source of truth for balance. Retuning must never mean touching a
service. After changing any number in there, run both of these from Studio's command
bar:

```lua
require(game.ReplicatedStorage.Shared.Util.Spec).run()          -- did I break the design?
require(game.ReplicatedStorage.Shared.Util.TuningReport).run()  -- what does it look like now?
```

`Spec` asserts design *intent* as ranges, not exact values — it catches "you moved a
number and the Dive is now 4 seconds" without freezing the balance. `TuningReport`
regenerates the survivability matrix that `Config/Gear.luau`'s header documents; paste
its output back into the design doc so the doc stops drifting away from the game.

In-game, **F3** toggles the debug HUD and `/radhelp` lists the tuning console
(`DebugService`): `/stage`, `/dig`, `/gear`, `/flush`, `/dock`, `/clear`, `/pocket`
(a stub that reports hot pockets are unbuilt), and `/radhelp` itself. `/radhelp`
enumerates `COMMANDS` at runtime, so anything added there shows up without being
listed here.

> The console has **no authorisation check** — the commands register for every
> player on every server. `/gear` and `/dig` write straight to the profile and persist.
> Gate it on `RunService:IsStudio()` or a UserId allowlist before any public release.
