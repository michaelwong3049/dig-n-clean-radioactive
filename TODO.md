# Dig N Clean: Radioactive — Project Tracker

Status board for the Rojo migration and everything after it. Check items off as they land;
add new sections as new features start. Each item keeps a one-line status plus a short
summary underneath — the summary is the "what and why," not a changelog.

Related reading: [`ARCHITECTURE.md`](ARCHITECTURE.md) (module map, world contract, boot
order), [`PLAN.md`](PLAN.md) (game design), [`README.md`](README.md) (getting started).

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
| 1 | **The map** — world geometry as code | §2 | **done** |
| 2 | **Map-anchored features** — shops built and working; Exhibition world + contract done, income pending | §3 | **mostly done** |
| 3 | **Economy & state backbone** — spend path landed; exhibit accrual pending | §4 | in progress |
| 4 | **Mechanical loop content** — Zones 2–4 stocked (41 items) | §5 | **done for MVP** |
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

## 2. The map — world geometry as code — Phase 1 ✅

**Done, verified in Studio.** The whole world is now generated from committed code and
checked by an automated contract pass. `require(...build.World).rebuild()` regenerates
everything and then runs `World.verify()` over the result.

- [x] Reverse-engineer and rebuild `BaseCamp` as a `.luau` generator
- [x] Extract the builder primitives into `build/Kit.luau` — **gated on a byte-diff**:
      the migrated camp reproduces the pre-refactor camp exactly (121 descendants,
      101 BaseParts, checksum `1150820216`, length `10882`), proven against a freshly
      cloned module so a stale `require` cache could not fake the result
- [x] `build/ZoneFields.luau` — one active radioactive dig plate, with the field kept under a
      single `ZoneId` so radiation remains one area rather than three separate zones
- [x] Three staged radiation gates — Stage 1, Stage 2 and Stage 3 sit inside the one field;
      each gate carries `StageId` and `UnlockTier` attributes for future unlock behavior
- [x] `build/Hub.luau` — compact 160×160 central plaza with one straight road into the field
- [x] `build/Shops.luau`, `build/Plots.luau`, `build/Scenery.luau`, `build/Daylight.luau`
- [x] Linear map layout — six plots **in a single column**, each on its own stub feeding
      one spine into the hub (per the requested layout: `[PLOT]--|` x6 into one spine
      into `[SHOP AREA]` into `[RADIATION]`), shops in the centre, radiation to the east,
      with the three progression stages arranged farther into the field
- [x] `build/World.luau` — composer + `verify()`, currently **0 failures**
- [x] One 660×320 radiation field with stage-specific loot: the outer stage uses the former
      Zone 1 pool, the middle stage uses the former Zone 2 pool, and the deep stage uses the
      former Zone 3 pool
- [x] **Burial-plane contract remains intact** — generated field geometry keeps the dig surface
      at the configured Y plane and `World.verify()` still checks the plate thickness and name/
      attribute agreement
- [x] Decide fate of `ReplicatedStorage.Assets.Tools` base meshes — genuinely
      hand-authored (unions, a `SpecialMesh`, an imported model), so they stay binary
- [x] Fix the blackout respawn, which sent players *into Zone 1* — see §7

**Current map direction.** The MVP world is intentionally one radiation area. The old
Zones 2–4 geometry is not generated, but the useful loot pools remain available as the
three internal stages of the main field. This keeps the first map easy to read: plots →
shops → Stage 1 → Stage 2 → Stage 3.

**Deferred deliberately:** the `ToolTiers` generator. All 21 tool variants exist and
work; reproducing them needs a per-part dump like BaseCamp got, because the live scale
does not match `ToolTiers.luau`'s `scale` field (Detector T5 is ×1.22 live against a
configured 1.12). Guessing would risk overwriting 21 correct models with wrong ones and
the place file has no git history to recover from.

## 3. Map-anchored features — Phase 2

- [x] **Three upgrade shops built and working** — Detector, Magnet, Cleaner, colour-coded
      on the plaza. `StationKind="shop"` + `StationId=<Gear.TRACKS name>`.
- [x] **Outfitter bench** — Suit, Boots and Satchel. Not in the original ask, but three
      shops left those three tracks *priced and unbuyable*, and the Suit gates every
      zone, so Zone 2 would have become the locked door PLAN §3.5 promises never to
      build. `Shops.luau` now asserts at build time that every `Gear.TRACKS` entry is
      sold somewhere.
- [x] **Six Exhibition plots** with claim boards, per-plot spawns and pedestal slots
      (3 unlocked, 12 built, 40 addressable). World + data contract only.
- [x] **Decon moved off camp, onto every base.** The shared Decon Station and Decon
      Shower are gone from `BaseCamp.luau`; each plot now builds its own
      `CleansingStation` — one part carrying both `StationKind="decon"` and
      `Shower=true`, sharing a `Radius`, in the open back third of the pad. Clean +
      flush + rack, all local to your own plot; the trip back to camp is sell-only
      now. `World.verify()`'s decon census updated from "exactly 1" to
      "== `Plots.COUNT`"; verified 6 decon stations / 6 showers in the world, 0 at
      camp, 0 verify failures.
- [ ] Verify the Trader and the six per-base Decon stations end-to-end in Play
      (blocked — see §9)
- [ ] Exhibition **income accrual**: yield loop, offline banking, 60s uncrate, duplicate
      damping. Every constant it needs already exists in `Tuning.EXHIBIT_*`; only the
      service is missing. This is the next plan.
- [ ] Set `MaxPlayers = 6` in Studio Game Settings so plots and players are 1:1
      (a place setting — Rojo cannot capture it)

## 4. Economy & state backbone — Phase 3

- [x] **`EconomyService.spend`/`award`** — the missing debit. `data.cash += value` in
      `sell` was the only line in the codebase that touched money; check-and-debit are
      one function so two purchases cannot both clear against the same balance.
- [x] `Gear.PROFILE_KEY` — one capitalised-track → lowercase-profile mapping for all six
      tracks, replacing a 3-entry local in `ToolService`
- [ ] Per-pedestal display state in the profile (extends the existing `exhibit` field)
- [ ] Yield accrual + offline banking (see §3)
- [ ] `StatResolver` hook for exhibition-yield multipliers

## 5. Mechanical loop content — Phase 4

- [x] **Stage loot pools stocked** — 41 items total (was 13), themed per PLAN §4. The
      former Zones 1–4 catalogue remains available, while the active map rolls the former
      Zone 1/2/3 pools in its three internal stages. Verified:
      unique ids, every `baseValue` inside its Rarity band, every nonzero loot weight
      in every zone resolves to a real item.
- [x] Stage 2 and Stage 3 loot progression (`Config/Zones.luau` + `DigService.luau`)
- [ ] Stage gate unlock interaction — gates currently expose `StageId`/`UnlockTier`; wire
      them to the player's progression and open/close behavior when the unlock rule is chosen
- [ ] Radiation burn / suit tolerance / survivability countdown (PLAN §3.5) — the
      HUD countdown is the piece that makes Zone 4 a *choice*; see §9
- [ ] Hot pockets — deliberately NOT built. The design call was "the ooze is the dig
      surface", so `ZoneService.hotPocketFor` stays a stub returning 1.

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

- [x] **Zone-2+ landmine — FIXED.** `DigService.rollItemId` hard-`error()`s for any
      zone whose item catalogue is empty (`Items.luau` currently only stocks Zone 1). The
      call is unprotected in `topUpField()`/`start()`, and `Ticker` has no per-subscriber
      `pcall`, so the throw can starve every service registered after `DigService` in
      `ORDER`. Fix this *as part of* stocking Zone 2's catalogue in §5, not before — the fix
      and the content are the same piece of work. Done both ways: `rollItemId` now
      warns once and returns nil instead of throwing, `Ticker` isolates each subscriber
      in a pcall so one thrower can no longer starve every service after it, and
      `Items.luau` stocks Zones 2-4. Boot log confirms `180 buried signal(s)` (4 x 45)
      with all 10 services up and zero failures.
- [x] **Ungated debug console — FIXED.** `/gear`, `/dig`,
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
- [x] **Blackout dropped players INTO Zone 1 — FIXED.** `ExposureService` looked up the
      respawn with `FindFirstChildWhichIsA("SpawnLocation")`, which searches direct
      children of Workspace only; `BaseCamp` nests its spawn, so every blackout fell
      through to a hardcoded `(0, 8, 0)` that sat inside Zone 1's footprint. Silent for
      the life of the project. Now resolves a named `RespawnAnchor` (on the shower
      grate, so you wake up mid-flush), falls back recursively, and **warns** on the
      last resort.
- [x] **`Ticker:stop()` mutating mid-iteration — FIXED** alongside the pcall work.
- [ ] **`bagContents` leak** — a dropped bag nobody fully recovers is destroyed by `Debris`
      after 90s, but the `Instance` key into `bagContents` is never cleared, so the destroyed
      part and its item payload stay referenced for the life of the server.
- [ ] **`DebugState` payload gaps** — never sends `inShower`; hardcodes `downed = false`. Two
      branches in `DebugHudController` are permanently dead as a result.
- [ ] **Orphaned haul part** — if a player's character disappears mid-pull (death, despawn),
      the in-progress haul part is left anchored in the world, visible to everyone, marking a
      buried item's exact spot until the player's character exists again.
- [x] **Sell button rendered `SELL  $$340`** — pre-existing double-`$`. In Luau backtick
      strings `${x}` is a literal `$` plus an interpolation, so `$${x}` prints two. Fixed
      on both the sell and the new buy button.
- [ ] Minor/latent: `Ticker.every` still ignores the rate of any call after the first
      subscriber (documented in place rather than changed, since everything runs at
      `Tuning.TICK_RATE`); `DataService.onPlayerAdded` has a narrow double-session
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
- [x] `ARCHITECTURE.md` — station attribute table extended (`shop`/`plot`/`pedestal`,
      `StationId`, the `Station` tag), the zone plate contract documented as a table of
      rules-and-why, and the "remaining gap" note rewritten now that the world is code
- [x] `PLAN.md` §14 rewritten — the old "desaturated ash-grey" direction contradicted
      the built world. The rule is now *saturated everywhere, radiation is the only
      thing that glows*, which keeps §14's real insight (one channel means danger) and
      changes only which channel
- [x] Fixed stale `PLAN_4.md` links across `ARCHITECTURE.md`, `README.md`, `TODO.md`
- [ ] Document the Exhibition's income contract once the accrual service lands
- [ ] Document a `ToolTiers` generator if/when it is reconstructed

**Summary.** `ARCHITECTURE.md` documents contracts that were previously implicit —
instance/attribute names services expect to find in the place file (`ZoneId`, `Shower`,
`StationKind`, `HoldPart`, `HoldCFrame`), which fields are optional vs. required and what
happens when they're missing, the `DebugCmd` attribute hook, and the full profile schema —
each fact checked against the actual code, not asserted from memory. It was revised once
already after the build/docs review caught four factual misses (an over-strict description
of `HoldPart`, an undocumented `DebugCmd` entry point, two missing required-instance
callouts, and a missing `/pocket` command in the console list).

---

## 9. Blocked / needs a human

- [ ] **Studio's Play toggle is wedged.** `start_stop_play` reports "Start play hasn't
      finished yet" and will not enter or leave Play. Needs a manual Play/Stop (or a
      Studio restart) to clear. Everything below is waiting on that, not on code.
- [ ] Live purchase test: buy at $200 (expect gear 1→2, cash exactly −120, held model
      swaps within ~0.5s), then retry at $80 and assert it is refused **with no state
      change** — the negative case matters more than the positive one, since a shop
      that debits on failure is worse than no shop.
- [ ] Live blackout test: `/zone 4`, wait for blackout, assert the player lands at the
      `RespawnAnchor` and `zoneOf == nil`.
- [ ] Trader / Decon end-to-end regression after the `StationService` migration.
- [ ] Border warning card (PLAN §4) — Zone 4 is ~7 seconds to blackout in a Cloth Wrap
      and sits 50 studs behind the camp wall. The fence, verge and sign are in; the
      HUD countdown is not. `ZoneService.onChanged` and `Radiation.survivableSeconds`
      both already exist and are unused, so this is ~60 lines.

---

## 10. Meta / late game — Phase 5, not yet scoped

Pulled from `PLAN.md` for later triage — nothing here has been sized or planned yet.
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
