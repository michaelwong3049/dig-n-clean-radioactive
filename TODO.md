# Dig N Clean: Radioactive — Project Tracker

Status board for the Rojo migration and everything after it. Check items off as they land;
add new sections as new features start. Each item keeps a one-line status plus a short
summary underneath — the summary is the "what and why," not a changelog.

Related reading: [`ARCHITECTURE.md`](ARCHITECTURE.md) (module map, world contract, boot
order), [`PLAN_4.md`](PLAN_4.md) (game design), [`README.md`](README.md) (getting started).

---

## Legend

- [x] done
- [~] in progress / partially done
- [ ] not started

---

## 0. Build order — read this before picking up new work

Everything below is grouped into numbered sections for tracking, but sections aren't the
build order — **phases** are. The phase a section belongs to is noted in its heading. The
rule that generates the phase order:

> **Build the map first. Then build the things that physically live on the map. Those
> things need money and player state to mean anything. Money and state come out of the
> mechanical actions the player performs. So: map → map-anchored features → the
> economy/state backbone those features read and write → the loop that generates the
> economy.**

The useful discovery from auditing the current code against that rule: **the bottom two
layers are already built.** `EconomyService` (sell, dirty-sell tax, Quarantine Locker) and
`DataService` (profile persistence, cash) are the money/state backbone. `DigService`,
`ToolService`, `DeconService`, and `ExposureService` are the mechanical loop that feeds
them — sweep, pull, haul, decontaminate, sell, all wired end to end for Zone 1. The Trader
stall and Decon Station are real geometry in `BaseCamp.luau` with `StationKind` attributes
`DeconService` already matches on. None of that is scaffolding — it's a working vertical
slice of the core loop (PLAN §2).

What's actually missing is exactly the two layers the rule says come *first*:

- **The map.** Only Zone 1 / base camp exists, and even that generator hasn't been run and
  eyeballed yet (§2 below).
- **The next map-anchored feature.** The Trader (sell) is built. The Exhibition/Row
  (PLAN §8 — display instead of sell) is not, and it's a *physical* feature — pedestals are
  instances in the world — so per the rule above it belongs in the same phase as the map,
  not filed under "later" the way it was in the old version of this doc.

Everything else (rebirth, storms, rail network, monetization, pets, contracts, museum, real
audio) genuinely is later: each one either extends a system that doesn't exist yet
(Exhibition) or only pays off once there's more than one zone to play in.

**Phase order:**

| Phase | What | Section | Status |
|-|-|-|-|
| 0 | Rojo port | §1 | done |
| 1 | **The map** — world geometry as code | §2 | in progress |
| 2 | **Map-anchored features** — verify Trader/Decon, build the Exhibition/Row | §3 | not started |
| 3 | **Economy & state backbone extensions** the Exhibition needs | §4 | not started |
| 4 | **Mechanical loop content expansion** — Zones 2–6 items so the new map has a loop on it | §5 | not started |
| — | Version control workflow for world content (cross-cutting, not sequenced) | §6 | in progress |
| — | Hardening — bugs found during review (cross-cutting, blocks specific phases — see §7) | §7 | not started |
| — | Documentation (cross-cutting) | §8 | in progress |
| 5 | **Meta / late game** — rebirth, storms, rail, monetization, pets, contracts, museum, audio | §9 | not started |

Work top to bottom within a phase; phases themselves are mostly sequential, but §6/§7/§8 are
cross-cutting and get touched whenever the phase in progress calls for them (e.g. a bug in
§7 that blocks Zone 2 content gets fixed during Phase 4, not deferred to the end).

---

## 1. Rojo migration (core port) — Phase 0, done

- [x] Port all 30 scripts from the live Studio session into `src/`
- [x] Vendor `ProfileStore` from upstream instead of transcribing
- [x] Fix `default.project.json` (drop dead `Packages`/`ServerPackages` mounts)
- [x] Verify byte-for-byte fidelity against Studio
- [x] Verify `rojo build` succeeds and produces the expected instance tree
- [x] Three-way review (fidelity / correctness / build-and-docs)
- [x] Write `ARCHITECTURE.md` from scratch (code cited it; it didn't exist)
- [x] Rewrite `README.md` for the new layout
- [x] Toolchain cleanup: pin `selene` in `rokit.toml`, fix `.gitignore` place-file glob
- [x] Commit and push (`feat/port-to-rojo`, tracking `origin`)

**Summary.** The game previously existed only inside a running Studio session — the repo
was an empty `rojo init` skeleton (`Hello.luau` + two bootstraps). Every script, service,
and controller was read out of Studio via the MCP tools and written to `src/` under the
same names Studio used, because the boot order (`init.server.luau`'s `ORDER` table) and
every relative `require` (`script.Services`, `script.Parent.Config`, etc.) depend on that
exact structure.

Verification was byte-level, not eyeballed: length + checksum for every file against
Studio's live `.Source`, which caught one real transcription slip (a Unicode em-space
typed as a regular space in `DebugHudController`) and confirmed everything else exact. A
follow-up fidelity review used a stronger position-weighted rolling checksum and confirmed
all 88 `require()` calls in the repo resolve correctly under the Rojo mapping.

Three review passes ran in parallel afterward — port fidelity, Luau correctness, and
build/docs accuracy — and their findings are tracked in §7 below rather than fixed inline,
since the point of this phase was parity with the working game, not improving it.

---

## 2. The map — world geometry as code — Phase 1

The place file (`.rbxlx`) is gitignored, so historically the *world* — zones, base camp,
tool models — lived nowhere but Studio and nowhere in version control. Two generators that
originally built parts of it (base camp, tool tiers) were run once from the command bar and
never saved, which is the exact failure mode this section exists to stop happening again.

This phase comes first because everything downstream reads real `Instance`s out of the
world — `StationKind`, `ZoneId`, `Shower`, `Radius` attributes that `DeconService`,
`ExposureService`, and `ZoneService` all key off of. There is no feature to build *on* the
map until the map exists.

- [x] Reverse-engineer and rebuild `BaseCamp` as a `.luau` generator
- [x] Statically verify the world contract: `StationKind`/`Shower`/`Radius` attribute names,
      types, and the `"BaseCamp"` model name were checked line-by-line against every
      `GetAttribute` call in `DeconService.luau`/`ExposureService.luau` — exact match
      (Counter → `StationKind="trader"`, Basin → `StationKind="decon"`, Grate →
      `Shower=true`, all `Radius=`12/12/7`).
- [x] Run `BaseCamp.rebuild()` in Studio and confirm it reproduces the camp visually —
      done 2026-08-19. Before rebuilding, `BaseCamp.build()` was run into a scratch
      folder alongside the live hand-placed camp and diff-checked: total descendant
      count (121 vs 121), and every station's exact `Position` (Floor, SpawnLocation,
      Trader.Counter, DeconStation.Basin, DeconShower.Grate) matched the live camp to
      the stud. Screenshot confirmed it reads as the camp (gate, awning, shower gantry).
- [x] Confirm the attributes land correctly **at runtime** — after the swap, read back
      `StationKind`/`Radius`/`Shower` directly off the new live instances; all six values
      correct (`trader`/12, `decon`/12, `true`/7).
- [x] Delete/replace the hand-placed `BaseCamp` in the live place — done. The old
      hand-placed `Folder` was destroyed and replaced with the generator's `Model`
      (stamped `GeneratedBy`/`BuilderVersion`) via `BaseCamp.rebuild()`. No visual or
      functional regressions found; nothing needed fixing in `BaseCamp.luau` itself.
- [~] Reconstruct the `ToolTiers` generator (recolors/rescales `_Base` models into `T1..Tn`)
      — **re-scoped, not just unstarted.** All 21 live variants (`Detector.T1-T8`,
      `Magnet.T1-T6`, `Cleaner.T1-T7`) already exist in Studio and are not broken — this
      isn't blocking anything today. But it's a bigger reverse-engineering job than it
      looked: checked whether live part sizes are `_Base size × ToolTiers.luau's scale`
      and they are not (e.g. Detector T5's `Grip` scales at ×1.22, but `ToolTiers.Detector[5].scale`
      is 1.12 — off by a full tier, and `Model:GetScale()` doesn't line up with tier
      scale either, since these models were already scaled down once for hand-carry
      before any tier scaling was applied on top). The real transform needs the same
      per-part dump-and-diff treatment BaseCamp got, across 21 variants instead of one
      model. Scoping this as its own task rather than guessing — see note below.
- [ ] Write a `Zones` generator (six boxes, positions, sizes, `ZoneId` — driven by `Config/Zones.luau`)
      — **blocked on missing data, not missing code.** `Config/Zones.luau` has zero
      spatial fields (no position, no size — only `baseRads`, `soilHardness`,
      `stationDistance`, `fogColor`, `loot`). The only zone that exists live,
      `Workspace.Zones.Zone1`, is a single flat `Part` (300×2×265 @ `(0, 0, -17.5)`,
      Sand) with no scenery. There's no prior layout to reverse-engineer here, unlike
      BaseCamp — this one needs a layout decided, not discovered. Holding for your
      direction on how the six zones should be arranged before writing anything.
- [x] Decide fate of `ReplicatedStorage.Assets.Tools` base meshes — confirmed by
      inspection: `_Base.Magnet` variants are `UnionOperation`s, `_Base.Cleaner.Handle`
      carries a `SpecialMesh`, `_Base.Detector` wraps an imported "Metal Detector Ctx 3030"
      model. All genuinely non-proceduralizable geometry — stays binary, referenced by
      the existing Studio instances, not rewritten as code. No action needed.
- [ ] Place Zones 2–3 geometry (full content, per MVP slice PLAN §15) and Zone 4 (empty
      but diggable and lethal — PLAN §15 explicitly wants Zone 4 buildable with *only* a
      loot table and rad rate, no hand-built content, as the cheapest possible test of
      whether players Dive) — blocked on the same layout direction as the Zones generator above

**2026-08-19 validation note.** Ran the actual validation pass with a connected Studio
session. Base camp: **fully done**, generator-owned, verified live, nothing to fix. Tool
tiers: **not broken, but reconstructing the generator is a separate, real task** — flagged
rather than guessed at, since a wrong reconstruction risks overwriting 21 correct live
models with incorrect ones and there's no git history for the place file to recover from.
Zones: genuinely blocked on a design decision (spatial layout), not an implementation gap —
this is the map-building direction still to come.

**Summary.** `src/server/build/BaseCamp.luau` is a from-scratch generator, not a transcription
— it was built by dumping every part's transform, size, color, material, and attributes out
of the live `BaseCamp` model (101 parts, confirmed zero unions/meshes, so 100% reconstructable
in code), then rewriting that dump as loops: 7 awning slats on a 1.25 pitch, 5 shower jets on
a 2.1 pitch, 4 corner posts, mirrored gate lamps, etc., instead of 101 hardcoded positions.
Only 6 distinct part rotations exist across the whole model, all clean whole-degree Euler
angles, which is what made the loop form possible.

It exposes `BaseCamp.build(origin?, parent?)` and `BaseCamp.rebuild(origin?)` — the latter
destroys and replaces whatever's currently at `Workspace.BaseCamp`. It is a **build tool**,
not a service: nothing requires it at boot, and it's meant to be run deliberately from the
command bar after an edit. Each generated model is stamped with `GeneratedBy` /
`BuilderVersion` attributes so a stray hand-edit is identifiable later.

This is the pattern going forward for anything without real mesh/union geometry: describe it
in a `.luau` file, commit that, run it once to materialize. The tradeoff, stated plainly for
whoever edits this next — once a structure is generator-owned, **dragging it in Studio is a
lie**: the next `rebuild()` reverts silent hand-edits. Change the number in the file instead.

Not yet done: actually running the new generator against the live place and eyeballing the
result. Until that happens this is "written and internally consistent," not "verified."
Also not yet done, and newly scoped into this section rather than left implicit: the actual
Zone 2–4 geometry. The mechanical loop (§5) has nowhere to run without it.

---

## 3. Map-anchored features — Phase 2

The things that live physically on the map, in the order the player would actually meet
them. The Trader and Decon Station already exist as geometry + service logic; what's new
here is verifying that pair end-to-end and then building the one big physical feature the
game doesn't have yet.

- [ ] **Verify the Trader stall end-to-end.** `BaseCamp.luau` places a part with
      `StationKind = "trader"`; `EconomyService.sell` and the dirty-sell tax are written.
      Confirm the client can actually walk up, prompt, and sell once §2's `rebuild()` step
      is verified — this is wiring verification, not new code.
- [ ] **Verify the Decon Station end-to-end** the same way (`StationKind = "decon"`,
      `DeconService`'s station matching, `StationController` on the client).
- [ ] **Build the Exhibition / Row (PLAN §8).** Not started at all — no pedestal instances,
      no display state, no yield accrual anywhere in the codebase today. Scope for the MVP
      slice (PLAN §15): 6 pedestal slots, one vitrine tier, tourists + collectors only, no
      sets, no Row cosmetics, **but with offline banking** (the number PLAN §15 says is
      worth the most real data).
  - [ ] Pedestal instances at base camp (map geometry — belongs in `BaseCamp.luau` or a
        sibling generator, not hand-placed, per the §2 rule)
  - [ ] Server-side display/undisplay flow: lock item from selling while displayed, 60s
        "crating" delay to pull one off (PLAN §8.7)
  - [ ] Yield accrual loop (base rate by rarity, PLAN §8.2 table) + offline banking (25% of
        online rate, capped 4h)
  - [ ] Guard: Slag cannot be displayed (PLAN §3.6, §8.7)
  - [ ] Minimal visitor stub: tourists only for MVP (constant small admission); collectors
        can wait for buyout offers to matter
- [ ] Create a plan for the Exhibition build (per this project's CLAUDE.md: any feature
      this size gets a plan reviewed with the user before implementation starts) — this
      TODO entry is the placeholder for that; write the actual plan when Phase 2 starts.

**Why this phase, not later.** The old version of this doc filed the Exhibition under
"not started / not yet scoped," grouped with rebirth and the rail network — systems that
genuinely are late-game. But the Exhibition isn't gated on anything except the map (§2) and
the economy backbone (§4, which mostly already exists). It's the second thing a new player
does in the scripted first-session flow (PLAN §12, the "put it up — people pay to look"
beat at 2:30), and per the build-order rule in §0, a map-anchored feature belongs right
after the map, not at the end of the list.

---

## 4. Economy & state backbone extensions — Phase 3

`EconomyService` and `DataService` already handle cash, profile persistence, the sell
pipeline, and the Quarantine Locker — that groundwork does not need to be rebuilt. What's
missing is the slice of state the Exhibition (§3) specifically needs, which didn't exist
because nothing has needed it yet.

- [ ] Per-pedestal display state in the player profile (which item, since when, current
      vitrine tier) — extends the existing `ProfileStore` schema, doesn't replace it
- [ ] Yield accrual: either a `Ticker`-driven per-second job (matches the existing pattern
      in `ExposureService`) or a lazy compute-on-read from a stored timestamp — decide based
      on how offline banking (§3) is implemented, since offline players can't run a live tick
- [ ] `StatResolver` hook for exhibition-yield multipliers (rebirth/gamepass hooks already
      exist there for `sellMultiplier` — same pattern, new stat)
- [ ] Decide where "duplicate damping" (PLAN §8.2 — 2nd copy 40%, 3rd 15%, 4th+ 5%) is
      computed: per-pedestal at accrual time, keyed off how many other displayed items
      share the same item id

**Why this phase, not folded into §3.** These are backbone changes (schema, accrual timing,
`StatResolver` wiring) that the Exhibition's server logic will call into, same relationship
`EconomyService`/`DataService` already have with `DigService`/`DeconService`. Splitting them
out keeps "what does the pedestal instance do when you interact with it" (§3) separate from
"what does the profile actually store" (this section) — useful because the schema decision
should get nailed down once, not iterated per pedestal feature.

---

## 5. Mechanical loop content expansion — Phase 4

`DigService`, `ToolService`, `DeconService`, and `ExposureService` already implement sweep →
pull → haul → decontaminate → sell/display for Zone 1. This phase is *content*, not new
systems: give Zones 2–4 (the ones §2 places geometry for) something to actually run the
existing loop against.

- [ ] Zone 2–4 item catalogues in `Config/Items.luau` (currently only Zone 1 is stocked —
      this is also what §7's zone-2 landmine bug is waiting on; do not place Zone 2 without
      it, see §7)
- [ ] Zone 2–4 rad rates / rated-suit tuning per PLAN §4's table
- [ ] Detector/magnet/cleaning-tool tiers needed to farm Zones 2–4 (PLAN §6 lines; MVP slice
      per PLAN §15: detector 1–4, magnet 1–3, cleaning tool 1–4, suit 1–3, boots 1–3,
      satchel 1–2)
- [ ] Radiation burn / suit tolerance / survivability countdown (PLAN §3.5) — the mechanic
      that makes an unrated Zone 4 walkable-but-lethal instead of walled off
- [ ] Hot pockets for Zone 1–4 (`ZoneService.hotPocketFor` is currently a stub returning 1
      always — see §7)

**Deliberately excludes** Zones 5–6, which the MVP slice (PLAN §15) doesn't call for and
which don't need to exist for the Phase-1-through-4 loop to be testable end to end.

---

## 6. Version control workflow for world content

- [x] Establish the three-tier approach: code/procedural (mergeable) → static `.model.json` /
      `.rbxmx` (mergeable-ish, single-owner) → whole `.rbxlx` (never — no diffs, no merges)
- [x] Confirm the current game is unusually well-suited to the code tier (base camp and tool
      tiers are already provably procedural; only two meshes are genuinely hand-authored art)
- [ ] Add `.gitattributes` marking `*.rbxlx` / `*.rbxmx` as binary (prevents Git from offering
      line-merges it can't actually perform)
- [ ] Decide: commit the `.rbxlx` as a crude backup now, or wait until more of `Workspace` is
      generator-owned and only the remaining hand-built art needs a place-file snapshot

**Summary.** The open question was "how do I get my Studio map onto GitHub." The honest
answer is there's no automatic sync — something has to bridge instances and text, and you
pick the direction. For anything already procedural (loops, patterns, arithmetic spacing),
writing a `.luau` builder and committing *that* gives real diffs and real merges, at the cost
of giving up freehand dragging on whatever the generator owns. For genuinely hand-sculpted
art or imported meshes, that tradeoff doesn't make sense — those stay binary, get a single
owner, and get merged by "whoever touched it last re-exports," not by Git.

Given the base camp turned out to be zero-union, zero-mesh, arithmetic-pitch geometry, and
`ToolTiers.luau` already exists as an orphaned recipe for a lost generator, this game leans
unusually hard toward the code tier — most of `Workspace` and `ReplicatedStorage.Assets` can
plausibly become generators, leaving only the couple of actually-modeled meshes as binary
assets referenced by ID.

---

## 7. Hardening — bugs found during review

Per your call: the port is validated for parity, but these are pre-existing issues in the
*original* game logic (not introduced by the port), and you wanted to test the migrated code
in Studio before touching any of it. Nothing below has been changed. Re-verify after testing,
since line numbers may drift with any edit. Two of these are flagged **blocking** because a
later phase runs straight into them.

- [ ] **Zone-2+ landmine — blocks Phase 4.** `DigService.rollItemId` hard-`error()`s for any
      zone whose item catalogue is empty (`Items.luau` currently only stocks Zone 1). The
      call is unprotected in `topUpField()`/`start()`, and `Ticker` has no per-subscriber
      `pcall`, so the throw can starve every service registered after `DigService` in
      `ORDER`. Fix this *as part of* stocking Zone 2's catalogue in §5, not before — the fix
      and the content are the same piece of work.
- [ ] **Ungated debug console — should land before any real playtesting.** `/gear`, `/dig`,
      `/flush` etc. register for every player on every server with no `RunService:IsStudio()`
      or allowlist check, and write straight to the persisted profile. Fine in solo testing,
      not fine the moment Phase 2/3 work needs a second person in the server to look at an
      Exhibition.
- [ ] **`SweepState` is invertible** — `strength = 1 - distance/radius` is exact and
      client-derivable (radius is in `ReplicatedStorage.Shared.Config.Gear`, ships to the
      client). Combined with the `angle` already sent, this reconstructs the buried item's
      exact position — the one thing `DigService`'s own header says it exists to prevent.
- [ ] **`Radiation.greedFraction` omits `levelResist`** while `net` includes it, so the
      reported "greed" fraction over-reports (up to ~1.67× at max level) and clamps to 100%
      for high-level players. `Spec.luau`'s tests don't catch it because every test case uses
      `levelResist = 0`.
- [ ] **`bagContents` leak** — a dropped bag nobody fully recovers is destroyed by `Debris`
      after 90s, but the `Instance` key into `bagContents` is never cleared, so the destroyed
      part and its item payload stay referenced for the life of the server.
- [ ] **`DebugState` payload gaps** — never sends `inShower`; hardcodes `downed = false`. Two
      branches in `DebugHudController` are permanently dead as a result.
- [ ] **Orphaned haul part** — if a player's character disappears mid-pull (death, despawn),
      the in-progress haul part is left anchored in the world, visible to everyone, marking a
      buried item's exact spot until the player's character exists again.
- [ ] Minor/latent (no current caller triggers them, but worth knowing): `Ticker.every`
      ignores the rate of any call after the first subscriber; `Ticker:stop()` mutates
      `subscribers` mid-iteration; `DataService.onPlayerAdded` has a narrow double-session
      window; `DeconService` can leave a stale `holding` flag with a spurious toast.

**Summary.** Three angles of review — port fidelity, Luau correctness (which independently
reimplemented the radiation/decay math in Python and machine-verified all 24 `Spec.luau`
design assertions pass against the shipped tuning numbers), and build/docs accuracy — turned
up eight real defects, all pre-existing in the game as it ran in Studio, none introduced by
the port. Kept as a checklist rather than fixed immediately because behavior parity was the
goal of the migration and these are design/security decisions, not transcription errors.
Two are now flagged as phase-blocking above; the rest stay deferred until an in-engine test
pass, per your original call.

---

## 8. Documentation

- [x] `ARCHITECTURE.md` — module map, boot order, server/client trust boundary, world
      instance/attribute contract, persistence & the logout rule, tuning workflow
- [x] `README.md` — getting started, layout, tuning commands
- [x] `TODO.md` — this file
- [ ] Fold the BaseCamp generator's existence + usage into `ARCHITECTURE.md` once verified
- [ ] Document the `ToolTiers`/`Zones` generators the same way, once they exist
- [ ] Document the Exhibition's world/attribute contract in `ARCHITECTURE.md` once §3 lands
      (pedestal instance shape, display-state attributes) — same treatment the world
      contract already gets for stations and zones

**Summary.** `ARCHITECTURE.md` documents contracts that were previously implicit —
instance/attribute names services expect to find in the place file (`ZoneId`, `Shower`,
`StationKind`, `HoldPart`, `HoldCFrame`), which fields are optional vs. required and what
happens when they're missing, the `DebugCmd` attribute hook, and the full profile schema —
each fact checked against the actual code, not asserted from memory. It was revised once
already after the build/docs review caught four factual misses (an over-strict description
of `HoldPart`, an undocumented `DebugCmd` entry point, two missing required-instance
callouts, and a missing `/pocket` command in the console list).

---

## 9. Meta / late game — Phase 5, not yet scoped

Pulled from `PLAN_4.md` for later triage — nothing here has been sized or planned yet.
Listed so it's visible, not because it's next. Each depends on either the Exhibition (§3)
existing or on there being more than one real zone (§5) to make the system meaningful —
that's what makes this genuinely last rather than an arbitrary ordering choice.

- [ ] Zones 5–6 content (Reactor Grounds, The Crater — beyond the MVP slice)
- [ ] Rebirth / "Decontamination Protocol" (PLAN §9.3) — depends on the Exhibition existing,
      since the entire design point is "the Exhibition survives rebirth and nothing else does"
- [ ] Rail network (PLAN §5.3, §10.12) — needs multiple zones with real distance to matter
- [ ] Fallout storms (PLAN §4, §10.8) — needs multiple zones to feel server-wide
- [ ] Museum / Collection Wall (PLAN §10.10) — needs an item catalogue bigger than Zone 1's
- [ ] Field Contracts (PLAN §10.14), Pets (PLAN §10.15)
- [ ] Monetization (PLAN §11) — deliberately last; PLAN §11 itself says nothing sold should
      be required to reach the Crater, so this can't be tuned before the Crater loop exists
- [ ] Real audio (current geiger/ping sounds are Roblox stock placeholders, per PLAN §14)

---

*Update this file as items move between sections — don't let it drift out of sync with
reality the way `ToolTiers.luau` drifted from its own lost generator.*
