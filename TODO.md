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
them — sweep, pull, haul, decontaminate, sell, all wired end to end for Stage 1. The Trader
stall and Decon Station are real geometry in `BaseCamp.luau` with `StationKind` attributes
`DeconService` already matches on. None of that is scaffolding — it's a working vertical
slice of the core loop (PLAN §2).

What's actually missing is exactly the two layers the rule says come *first*:

- **The map.** Only Stage 1 / base camp exists, and even that generator hasn't been run and
  eyeballed yet (§2 below).
- **The next map-anchored feature.** The Trader (sell) is built. The Exhibition/Row
  (PLAN §8 — display instead of sell) is not, and it's a *physical* feature — pedestals are
  instances in the world — so per the rule above it belongs in the same phase as the map,
  not filed under "later" the way it was in the old version of this doc.

Everything else (rebirth, storms, rail network, monetization, pets, contracts, museum, real
audio) genuinely is later: each one either extends a system that doesn't exist yet
(Exhibition) or only pays off once there's more than one stage to play in.

**Phase order:**

| Phase | What | Section | Status |
|-|-|-|-|
| 0 | Rojo port | §1 | done |
| 1 | **The map** — world geometry as code | §2 | **done** |
| 2 | **Map-anchored features** — shops built and working; Exhibition world + contract done, income auto-deposits | §3 | **mostly done** |
| 3 | **Economy & state backbone** — spend path landed; exhibit accrual auto-deposits into `cash` | §4 | in progress |
| 4 | **Mechanical loop content** — Stages 2–4 stocked (41 items) | §5 | **done for MVP** |
| 4 | **The wash bay** — liquid roll economy live; the hose minigame is next | §5b | in progress |
| — | Version control workflow for world content (cross-cutting, not sequenced) | §6 | in progress |
| — | Hardening — bugs found during review (cross-cutting, blocks specific phases — see §7) | §7 | not started |
| — | Documentation (cross-cutting) | §8 | in progress |
| 5 | **Meta / late game** — rebirth, storms, rail, monetization, pets, contracts, museum, audio | §9 | not started |

Work top to bottom within a phase; phases themselves are mostly sequential, but §6/§7/§8 are
cross-cutting and get touched whenever the phase in progress calls for them (e.g. a bug in
§7 that blocks Stage 2 content gets fixed during Phase 4, not deferred to the end).

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
- [x] `build/StageFields.luau` — one active radioactive dig plate, with the field kept under a
      single `StageId` so radiation remains one area rather than three separate stages
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
      Stage 1 pool, the middle stage uses the former Stage 2 pool, and the deep stage uses the
      former Stage 3 pool
- [x] **Burial-plane contract remains intact** — generated field geometry keeps the dig surface
      at the configured Y plane and `World.verify()` still checks the plate thickness and name/
      attribute agreement
- [x] Decide fate of `ReplicatedStorage.Assets.Tools` base meshes — genuinely
      hand-authored (unions, a `SpecialMesh`, an imported model), so they stay binary
- [x] Fix the blackout respawn, which sent players *into Stage 1* — see §7
- [x] **The field is now literally something you wade into**, not just tinted
      ground. `Scenery.luau` gained `OozeSurface` — one translucent Neon plate per
      stage, sized to the whole plate, floating `WADE_HEIGHT` (1.1 studs) above the
      real floor, about half a leg on a default character. It's a second,
      `CanCollide=false` layer, never a change to `Stages.SURFACE_Y` itself — that
      plane is still exactly what `DigService` buries against and what a player's
      feet actually rest on, per `StageFields.luau`'s own "tilt or bump a plate and
      items surface underground" warning. Took two live-tuned passes to get the
      material right: `Neon` at 0.55 transparency still read as solid ground (bloom
      pushes a plate this size to a wall of colour well before `Transparency`
      "looks like" that value), and `Glass` was properly translucent but tinted
      everything blue instead of acid green. Settled on `Neon` at 0.82 transparency
      — sand and props visibly show through, colour stays correct.
- [x] **Plots, shop plaza and the radiation field pulled together into one
      connected complex**, per the requested layout: base column — shop area —
      radiation, directly adjacent rather than distant blocks joined by long empty
      roads. Both connectors (`Hub.luau`'s `CampToRadiationRoad`, `Plots.luau`'s
      west trunk) shrank from 60 studs to 20. `Hub.luau` now derives the east
      connector's endpoint from `Stages.get(1)`'s actual west edge instead of a
      second hardcoded `140` next to `Stages.luau`'s own number — one source of
      truth instead of two that could drift. `Plots.PLOT_X`/`SPINE_X` moved
      together by the same 40 studs so the plot-to-spine stub length is
      unchanged; only the spine-to-hub trunk got shorter. `Stage1.center` moved
      from `{470,0}` to `{430,0}`; `stationDistance` re-measured by the same 40
      studs (230→190) per the file's own "measured, not aspirational" rule.
      **Real bug found verifying this**: updating a ModuleScript's `.Source` live
      in Studio does NOT reload code already `require()`'d elsewhere in the same
      session — Luau caches by Instance identity, and
      `ReplicatedStorage.Shared.Config.Stages` had been `require()`'d many times
      earlier in this session through the "fresh-clone-the-Server-folder"
      verification pattern this project uses. Cloning `Server` makes fresh
      copies of everything *under* it, but `Stages` lives in
      `ReplicatedStorage.Shared`, outside that clone, so every "fresh" test was
      still resolving the STALE cached table — `World.verify()` kept passing
      while `workspace.Stages.Stage1` sat exactly where it always had. Caught by
      directly measuring the live part's position and finding it hadn't moved,
      not by trusting a green checkmark. Fixed by destroying and recreating the
      `Stages` ModuleScript instance itself (same name, same parent, same
      source) to force a genuine cache miss on the next `require`.
- [x] **The 20-stud connectors above were still a visible "pathway" — removed
      outright, replaced by the plaza's own floor reaching both neighbours
      directly.** `Hub.PLAZA` is no longer a symmetric 160×160 square; it's a
      rectangle (`halfX=100, halfZ=80`) whose east edge lands exactly on Stage
      1's west edge and whose west edge lands exactly on the plot spine's east
      edge — zero gap, not a short one. `Hub.luau`'s `buildRoad`/`buildRoads`
      (the `CampToRadiationRoad`) and the unused `Hub.GATES` table are deleted;
      `Plots.luau`'s `PlotTrunk` lane is deleted the same way, and
      `PLOT_X`/`SPINE_X` shifted another 10 studs (to `-170`/`-110`) so the
      spine's own east edge (`SPINE_X + 10`, the lane's half-width) lands on
      the plaza's new west edge exactly. `World.verify()`'s plaza-overlap check
      updated for the rectangle (`halfX`/`halfZ` instead of one `size`) —
      `rectsOverlap` already treats an exactly-shared edge as touching, not
      overlapping, so a zero-gap boundary was already safe against it, just
      needed the check itself to stop assuming a square. Verified: `World.verify()`
      passes against a freshly-cloned `Server` folder; live position checks
      confirm the plaza's edges and the spine/stage edges land on the same
      coordinate on both sides; screenshot confirms no gap or road strip
      remains, and each plot still reaches the spine via its own stub.
- [x] **That spine was still a visible pathway between the plots and the shop
      area — deleted outright, plaza grown to touch every plot pad directly.**
      Screenshot feedback: the radiation side read as attached, the plot side
      still didn't — a thin diagonal lane with six stubs branching off it is
      still "a pathway," even a short one. `Hub.PLAZA` is no longer expressed as
      half-extents from the origin; it's `{minX=-137, maxX=100, minZ=-191,
      maxZ=191}` — `minX` is the plot pads' own east edge
      (`Plots.PLOT_X + Plots.PAD.width/2`), `minZ`/`maxZ` span the whole plot
      column (`Plots.CENTERS`' extremes ± half of `Plots.PAD.depth`), so all six
      plots border the plaza along one continuous seam instead of feeding into
      it through a lane network. `Plots.SPINE_X`, `buildWestNetwork`, and
      `buildLane` are all deleted from `Plots.luau`. The dependency direction
      flipped: `Plots.luau` no longer requires `Hub` at all (nothing left to
      read `Hub.PLAZA` for); `Hub.luau` now carries hand-written, commented
      knowledge of `Plots.luau`'s constants instead, since Hub can't require
      Plots back without a cycle (Plots already requires Hub in the other
      commit's world). Keeping the two in sync when either changes is now a
      manual, comment-documented obligation on Hub.luau's side — flagged
      explicitly in both files' headers so it isn't a silent trap later.
      Verified: `World.verify()` passes against a freshly-cloned `Server`
      folder; live position checks confirm the plaza's west edge and BOTH the
      first and last plot's pad edges land on the exact same coordinate
      (-137); screenshot confirms the plaza now spans the full plot column
      height with zero gap or road anywhere along that edge.

**Current map direction.** The MVP world is intentionally one radiation area. The old
Stages 2–4 geometry is not generated, but the useful loot pools remain available as the
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
- [x] **Shops reskinned cartoony/nuclear.** Wood-plank market stalls → glossy
      SmoothPlastic toxic-waste drums: chunky barrel body, black hazard-stripe
      bands, a rounded dome canopy on posts, a hand-built radiation trefoil
      (`buildTrefoil` — three blocks radiating from a hub, no image asset needed),
      and a black "outline" plate behind each sign for a toy-packaging pop.
      Applied to all three stalls and the Outfitter's three counters. The one
      glow accent (a small vial on each counter) is **cyan, not green** —
      PLAN §14's rule is that acid green means danger exclusively, so the
      product glow deliberately uses a different colour rather than diluting
      that signal. World positions and both Radius values (12 stalls, 6
      outfitter) are untouched; this only changed what things look like.
      Two real sizing bugs caught by screenshot and fixed before commit: the
      first-pass dome was 22 studs wide over a 6-wide barrel (read as a giant
      balloon on a stick) and the sign board was still sized for the old
      20-wide wooden deck. Also caught two Cylinder axis-ordering mistakes
      (`size[1]` is always the axis length, not the diameter) that would have
      rendered the glow vial as a squat oval and the trefoil discs as thin
      tubes poking at the viewer instead of flat coins.
- [x] **Each shop now sells a recognisable prop of the actual item, not just a
      colour.** The barrel reskin told you "this is a shop"; it didn't tell you
      *which* one without reading the sign. Six new hand-built props, one per
      `Gear.TRACKS` entry: a detector (flat coil + shaft + control box + grip),
      a horseshoe magnet (classic red-with-white-tips, not the shop's own
      colour — the cliché colouring is what makes the shape read instantly),
      a bucket + suds + scrub brush for the cleaner, and for the Outfitter a
      standing hazmat mannequin, a pair of boots, and a satchel with a strap.
      `buildIdentityProp` dispatches on track so `buildStall`/`buildOutfitter`
      call one function without caring which shop they're building.
      Two placement bugs caught by screenshot, not shipped: the outfitter
      props first sat directly behind their barrel on the approach axis, where
      the barrel's own silhouette hid almost the whole prop — moved to a small
      sideways offset instead, mirroring how the main stalls already place
      their prop beside the barrel rather than behind it. And boots/satchel
      first used `C.canvas`, which is close enough to the outfitter's own
      yellow that both nearly vanished against the bench — switched to
      `C.wood` (dark brown) for actual contrast. World positions, both Radius
      values, and the barrel/dome/trefoil kit are all unchanged.
- [x] **Shops reskinned again — toy-store kiosk, not toxic drum.** The nuclear-drum
      look above is gone, replaced with the generic "friendly Roblox shop" a
      reference photo asked for directly: a wood counter booth on four wood posts
      under a candy-striped, scalloped awning, a little blocky shopkeeper standing
      behind the counter, a glowing bubble sign floating over the roof peak, and a
      glowing floor outline marking the buy radius. Per-shop colour-coding and the
      identity-prop system both carry over unchanged — the booth shape is now
      identical for every shop, so the prop beside the counter (plus a new wood
      crate of clutter next to it) is still the only thing that says *which* shop
      it is. `buildTrefoil`/`buildBarrel` removed (dead code, nothing referenced
      their output once the drum was gone); `Kit.C` already had wood tones from the
      boots/satchel props, no new palette entries needed. World positions and both
      Radius values (12 stalls, 6 outfitter) are untouched — same promise as the
      first reskin. Two real bugs caught by screenshot, not shipped: the sign's
      width/height were swapped in the size array (rendered as a giant black
      obelisk instead of a wide board), and the sign's `SurfaceGui` text was
      painted on the face pointing away from the direction players actually
      approach from (silently blank from every angle a player would ever stand at
      — caught by checking from the approach camera angle, not just confirming the
      parts existed). A third bug turned out to be in `Kit.surfaceText` itself, not
      Shops.luau: any sign with a `PointLight` on the same part (the new glowing
      signs) was blowing its own text out to a blank wash, because `SurfaceGui`
      defaults to full `LightInfluence`. Fixed once, at the shared helper, so every
      sign in the game benefits rather than working around it per caller.
- [x] **Magnet shop tried a second awning style — a bowed, rolled-edge canopy.** A
      third reference photo (a different game's "Sell Loot" kiosk) showed a curved
      rather than flat awning, with thick rolled wood scrolls at each edge and no
      side/back walls at all. Tried on the Magnet stall alone, deliberately, rather
      than rolled out to all three — `STALLS` entries now take an optional
      `roofStyle` field, and `buildStall` branches on it. The curve is faked with 7
      flat panels walked around a shallow arc (`buildArchAwning`), since Roblox
      parts can't bend; posts are wider and shorter to match. Green stripes in the
      reference became the shop's own cyan — green stays reserved for radiation
      (PLAN §14), so the reference's colour choice didn't carry over, only its shape
      did. Two real bugs caught by screenshot before shipping, both arithmetic: the
      arc segments' Y-rotation logic put the stall's DEPTH in the wrong size slot
      (rendered as a wall of vertical spikes, not roof panels), and the peak-height
      formula was missing a term (`pivotY - R*cos` instead of `pivotY -
      R*(1-cos)`), which put the entire arch underground. Fixed by checking a
      straight-on screenshot against the actual reference photo, not just
      confirming `World.verify()` stayed green — verify only checks the world
      CONTRACT (station census, stage plates, no overlaps), never geometry someone
      would recognise as "wrong shape."
- [x] **Shop parts switched from `SmoothPlastic` to `Plastic`.** Every shop part
      except the wood posts/counters and the deliberately-glowing Neon signs was on
      `SmoothPlastic` — Roblox's glossiest finish, close to acrylic — which read as
      shiny rather than the flat toy-block look the rest of the world uses. Plain
      `Plastic` (matte, bumpy) everywhere else instead.
- [x] **The bowed awning rolled out to all three plaza stalls plus the Outfitter,
      replacing the flat scalloped one everywhere.** `buildArchAwning` gained
      `width`/`halfAngle` parameters instead of a hardcoded radius, since the same
      shape now has to cover both a ~14-wide stall roof (a deep 35° bow) and the
      Outfitter's ~40-wide backboard trim (a wide, shallow 12° bow) — one fixed
      radius could not do both. `roofStyle`/`isArch` branching and the now-fully-dead
      `buildAwning` (flat stripes + ball scallops) were removed rather than left
      behind unused.
- [x] **Outfitter bench** — Suit, Boots and Satchel. Not in the original ask, but three
      shops left those three tracks *priced and unbuyable*, and the Suit gates every
      stage, so Stage 2 would have become the locked door PLAN §3.5 promises never to
      build. `Shops.luau` now asserts at build time that every `Gear.TRACKS` entry is
      sold somewhere.
- [x] **Outfitter rebuilt as a real building, not a bench.** It sells the gear
      that reduces incoming damage — hazard suits, boots, satchels — so it earns a
      building rather than a picnic table under a trim strip. Four walls (open at
      the front, facing the camp gate), a real peaked roof (`buildGableRoof`: two
      flat panels tilted up from the wall tops to a centre ridge, plus a ridge cap
      — this project's usual "fake the curve/slope with flat blocks" trick), and
      the three counters moved inside against the back wall. The bowed awning trim
      that capped the old backboard is gone entirely, replaced by the roof.
      World positions and all three Radius values (6 each) are untouched. Verified
      in Studio from an angled camera (a dead-on front view hid the ridge and made
      the roof read as flat, which cost one confused screenshot before checking
      the actual part positions/rotations directly and finding the geometry was
      correct all along).
- [x] **The bowed arch canopy removed from the plaza stalls too, replaced with
      `buildGableRoof` at stall scale.** After going up on the Outfitter, the same
      "archway" look on Detector/Magnet/Cleaner didn't land either — every shop now
      uses the one peaked-roof builder, at two different scales (a small roof on
      four posts for a stall, a full building for the Outfitter), and the bowed
      canopy is gone completely. `buildArchAwning` deleted as fully dead code —
      nothing called it any more once the Outfitter stopped too.
- [x] **Outfitter sign shrunk, AND the real cause of the stretch fixed underneath
      it.** First pass shrank the board (38→15 studs wide) on the theory that
      `TextScaled` never distorts glyphs, so the board's own proportions had to be
      the problem. Wrong, or at least incomplete — the actual letters were still
      stretched horizontally afterward, on every sign, not just this one.
      `Kit.surfaceText`'s `SurfaceGui.PixelsPerStud` was being silently ignored
      the whole time: that property does nothing unless `SizingMode` is
      explicitly set to `Enum.SurfaceGuiSizingMode.PixelsPerStud`. Without it,
      every sign's canvas defaulted to a fixed roughly-square size regardless of
      the part's actual face shape, so text got laid out square and then the
      whole canvas was squashed/stretched onto the real (much wider) face — the
      true source of "the text itself is stretched," on every board in the game,
      not a per-sign sizing issue. Fixed once at the shared helper.
- [x] **Six Exhibition plots** with claim boards, per-plot spawns and pedestal slots
      (3 unlocked, 40 addressable). World + data contract only.
- [x] **Base layout revamped to match the requested sketch** — cleansing station at
      the top of the base (pushed to local z=20, right under the name sign) with
      8 stands flanking it in two columns of 4 (`Plots.COL_X = ±25`, paired off
      row by row via `slotOffset`), replacing the old centred 5-wide grid.
      `Plots.VISIBLE_SLOTS` dropped from 12 to 8 to match. Stand instances renamed
      `Plinth{n}` → `Stand{n}` (cosmetic only — `StationKind` stays `"pedestal"`
      everywhere, nothing reads the instance name). Verified: `World.verify()`
      passes with 0 failures; world-space positions checked directly
      (`CleansingStation.Basin` local z=20, row-1 stands z=15, row-4 stands
      z=-15) rather than trusted from a screenshot alone.
- [x] **Decon moved off camp, onto every base.** The shared Decon Station and Decon
      Shower are gone from `BaseCamp.luau`; each plot now builds its own
      `CleansingStation` — one part carrying both `StationKind="decon"` and
      `Shower=true`, sharing a `Radius`. Clean + flush + rack, all local to your
      own plot. `World.verify()`'s decon census updated from "exactly 1" to
      "== `Plots.COUNT`"; verified 6 decon stations /
      6 showers in the world, 0 at camp, 0 verify failures.
- [x] **Camp walls and the Trader removed.** The camp used to be a walled box
      (5 wall parts) sitting inside the open plaza with the trader stall boxed off
      inside it; both are gone now, so the plaza reads as one open shop area —
      floor, gate posts/lamps and the sign are all that's left of `BaseCamp.luau`
      (12 descendants, down from 52). **This means there is currently no sell
      point anywhere in the world** — `EconomyService.sell` and the `"sell"` verb
      in `DeconService`'s action router still work, nothing in the world can
      trigger them until a trader (or some other cash-out point) is placed again.
      Flagged loudly in `BaseCamp.luau`'s header, not silently dropped.
      `World.verify()` no longer asserts a trader count. Verified: `World.verify()`
      passes with 0 failures against the emptied camp.
- [x] **Camp entrance gate removed too.** The two gate posts, their lamps, and the
      "BASE CAMP" sign spanning between them read as an archway framing the
      approach — same complaint as the shops' arch canopy, different structure.
      Removed rather than reworked into something smaller; the camp is now just
      the floor and the join `SpawnLocation`, identified by what's standing on it
      (the shops, the plots) rather than a sign over the door. `BUILDER_VERSION`
      bumped to 5. Verified: `World.verify()` passes with 0 failures.
- [ ] **No sell point exists.** Decide where cash-out lives now — back at camp as a
      single shared trader again, one per base like the cleansing station, folded
      into the cleansing station itself, or deferred entirely in favour of the
      Exhibition income loop once that's built. Blocks any real economy testing
      until decided.
- [ ] Verify the six per-base Decon stations end-to-end in Play (blocked — see §9)
- [x] Exhibition **income accrual**: `ExhibitService.luau` — plot assignment (per-session,
      never persisted, matching `Plots.luau`'s own contract), yield loop (duplicate damping,
      hourly cap approximated as a rate clamp), offline banking, 60s uncrate delay, and
      the four new actions (`display`/`undisplay`/`collect`/`buySlot`) wired through the
      existing `StationState`/`StationAction`/`StationResult` triad — no new remotes,
      mirroring the `ShopService` delegation pattern exactly. `StationController.luau` grew
      matching "plot" (claim board: banked cash, COLLECT, next-slot price, BUY SLOT) and
      "pedestal" (locked/occupied/empty states; the empty+unlocked picker reuses the same
      carry-list rows the decon panel already draws) panels. `World.verify()` passes; a
      function-level smoke test against a freshly-cloned `Server` folder confirmed
      `plotViewFor`/`standViewFor` compute correctly and `display`/`collect` fail closed
      for a player with no loaded profile. **Full Play-mode regression (buy at $200, retry
      at $80, display/undisplay/collect with a real character) is still blocked — see §9,
      same wedged Play toggle.**
- [x] **All 8 display stands free from the start.** The cash-bought slot track is gone:
      `EXHIBIT_STARTING_SLOTS`/`Gear.pedestalPrice`/`ExhibitService.buySlot`/the `"buySlot"`
      action and the BUY SLOT panel button all removed; `EXHIBIT_MAX_SLOTS` is now 8 to
      match `Plots.VISIBLE_SLOTS`. `data.exhibit.slots` stays in the schema (constant 8) and
      is clamped up on load for pre-change saves. Stands build with no locked/dim state.
- [x] **Exhibition income auto-deposits; the claim board is gone.** `ExhibitService`
      sweeps accrued yield straight into `data.cash` on a ~5s cadence (and the offline
      haul the moment a profile loads), so there is no pot to walk over to. Removed with
      it: the `ClaimBoard` prop and its `PLOT n` billboard, the `"plot"` station kind,
      `ExhibitService.collect`/`plotViewFor`/`PlotView`, the `collect` action in
      `DeconService`, the client "plot" panel in `StationController`, and
      `World.verify()`'s plot-board census check. `data.exhibit.bankedCash` is now just
      a sub-dollar carry between deposits.
- [ ] Set `MaxPlayers = 6` in Studio Game Settings so plots and players are 1:1
      (a place setting — Rojo cannot capture it)

## 4. Economy & state backbone — Phase 3

- [x] **`EconomyService.spend`/`award`** — the missing debit. `data.cash += value` in
      `sell` was the only line in the codebase that touched money; check-and-debit are
      one function so two purchases cannot both clear against the same balance.
- [x] `Gear.PROFILE_KEY` — one capitalised-track → lowercase-profile mapping for all six
      tracks, replacing a 3-entry local in `ToolService`
- [x] Per-pedestal display state in the profile — `data.exhibit.pedestals` stays a dense
      array (each entry carries its own `slot` field) to satisfy ProfileStore's no-gaps
      rule rather than being indexed by slot number; see §3
- [x] Yield accrual + offline banking (see §3)
- [x] `StatResolver` hook for exhibition-yield multipliers — `yieldMultiplier` already
      existed (Curator perk hook, built before `ExhibitService` existed to read it);
      `ExhibitService.rawRatePerSecond` is the first caller

## 5. Mechanical loop content — Phase 4

- [x] **Stage loot pools stocked** — 41 items total (was 13), themed per PLAN §4. The
      former Stages 1–4 catalogue remains available, while the active map rolls the former
      Stage 1/2/3 pools in its three internal stages. Verified:
      unique ids, every `baseValue` inside its Rarity band, every nonzero loot weight
      in every stage resolves to a real item.
- [x] Stage 2 and Stage 3 loot progression (`Config/Stages.luau` + `DigService.luau`)
- [ ] Stage gate unlock interaction — gates currently expose `StageId`/`UnlockTier`; wire
      them to the player's progression and open/close behavior when the unlock rule is chosen
- [ ] Radiation burn / suit tolerance / survivability countdown (PLAN §3.5) — the
      HUD countdown is the piece that makes Stage 4 a *choice*; see §9
- [ ] Hot pockets — deliberately NOT built. The design call was "the ooze is the dig
      surface", so `StageService.hotPocketFor` stays a stub returning 1.
- [x] **Stock Stage 5 (Reactor Grounds) and Stage 6 (The Crater)** — 23 items added
      (12 + 11), themed per PLAN §4 (fuel rods/control tech/black-box data; anomalies/
      one-of-a-kind relics). `reactor_control` extends across the Stage 4/5 boundary;
      `crater_relics` is new for Stage 6's showpiece tier. Both fields now roll real
      loot instead of hitting the empty-pool warning.
- [x] **Re-weight stages 4–6 for the doubled signal density** — moot. The per-rarity
      `loot` weight tables are gone (detector luck replaced `maxRarity`, and per-item
      `odds` now drives the roll). Each stage carries one `rarityTilt` scalar instead,
      solved for a target Rare+ share, and there is no per-rarity weight left to drift
      with `SIGNALS_PER_STAGE`. See `Config/Stages.luau`'s header + `Config/Items.luau`
      "The dig roll".
- [ ] **An on-site station for The Crater** — PLAN §16 calls it a heist, not a hike, and
      "short" has to mean short from its own station. At the far end of the east chain the
      honest walk from the nearest cleansing station is ~1800 studs, about two minutes.
      `stationDistance = 1799` is the warning, not the design.

## 5b. The wash bay — Phase 4

PLAN §2 step 4 calls cleaning "a **skill mini-interaction**, not a progress bar" and §16
hedges that if it doesn't work, fall back to a hold-to-clean bar with the potency gate.
We shipped the fallback. This section is the two-slice plan to ship the real thing.

- [x] **The liquid roll economy** — `Config/Liquids.luau` (10 liquids), the `Luck` gear
      track (7 tiers), `LiquidService`, a **wash pad** on every base
      (`StationKind = "roller"`, `build/Plots.buildWashPad`), a Luck counter at the
      Outfitter, roller mode on the station panel, and `LiquidController`'s roll reveal
      + loaded-liquid badge. Drives the EXISTING hold-to-scrub bar, so the whole economy
      is playable and tunable before any camera work exists.
      Three invariants, all pinned in `Util/Spec`: liquid potency is capped at **+2** so
      the Cleaner track stays PLAN §2's second gate; **Plain Water is unlimited**, so no
      player can ever be unable to clean; and luck only ever moves mass **up** the table,
      never inverting a pair.
- [x] **The hose minigame** — the piece PLAN §2 actually asks for. `WashService` owns the
      session (the client reports aim and intent, never progress — the same boundary the
      scrub timer had); `WashController` takes the camera to a third-person framing on
      the `WashCam` anchor, the item is rendered **server-side** on the `WashStand` so
      bystanders see it, and one glowing blob per patch is scattered over it. Hold LMB to
      spray in the loaded liquid's colour. Patches above effective potency render crusted
      and visibly refuse the stream — the Quarantine Locker taught in 3D rather than in a
      red button label. Entry is `press E while holding the item`, so `heldUid` became
      real profile state (CarryService) and ToolService welds it into the off hand.
      The scrub path is GONE from DeconService rather than kept as a fallback: two
      implementations of one gate is how they drift.
- [x] **Strip the pad's UI** — the roller panel mode, the roll reveal card and the
      `LiquidRoll` remote are all deleted. The pad announces in the world instead, and
      Luck moved from an Outfitter counter to a wooden sign with a ProximityPrompt.
      `StationController` gained a `PANEL_KINDS` allowlist, because the decon branch is
      the render fallthrough and deleting the roller branch made the wash pad open a
      panel titled TRADER — caught in play, not in review.
- [ ] **The Quarantine Locker needs a world object.** Removing the decon panel (on
      request — walking up to the tub should show only the E prompt) took RACK and the
      locker rows with it. The locker still exists in the profile and `DeconService`
      still implements `rack`, but nothing in the world triggers either any more, so
      PLAN §10.2's "wish list made of your own bad luck" is currently unreachable. It
      wants to be a physical rack beside the tub with its own prompt — which is what
      §10.2 describes anyway, and better than the row it lost.
- [ ] **Replicate the spray** — the stream is client-local in the slice above, which is
      against `ToolService`'s "what you hold is public storytelling" rule. It is
      defensible only because every cleansing station sits on its owner's own private
      base (`build/Plots.luau`) and there is no bystander to tell the story to. Revisit
      if bases ever become walk-in.

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

- [x] **Stage-2+ landmine — FIXED.** `DigService.rollItemId` hard-`error()`s for any
      stage whose item catalogue is empty (`Items.luau` currently only stocks Stage 1). The
      call is unprotected in `topUpField()`/`start()`, and `Ticker` has no per-subscriber
      `pcall`, so the throw can starve every service registered after `DigService` in
      `ORDER`. Fix this *as part of* stocking Stage 2's catalogue in §5, not before — the fix
      and the content are the same piece of work. Done both ways: `rollItemId` now
      warns once and returns nil instead of throwing, `Ticker` isolates each subscriber
      in a pcall so one thrower can no longer starve every service after it, and
      `Items.luau` stocks Stages 2-4. Boot log confirms `180 buried signal(s)` (4 x 45)
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
- [x] **Blackout dropped players INTO Stage 1 — FIXED.** `ExposureService` looked up the
      respawn with `FindFirstChildWhichIsA("SpawnLocation")`, which searches direct
      children of Workspace only; `BaseCamp` nests its spawn, so every blackout fell
      through to a hardcoded `(0, 8, 0)` that sat inside Stage 1's footprint. Silent for
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
      `StationId`, the `Station` tag), the stage plate contract documented as a table of
      rules-and-why, and the "remaining gap" note rewritten now that the world is code
- [x] `PLAN.md` §14 rewritten — the old "desaturated ash-grey" direction contradicted
      the built world. The rule is now *saturated everywhere, radiation is the only
      thing that glows*, which keeps §14's real insight (one channel means danger) and
      changes only which channel
- [x] Fixed stale `PLAN_4.md` links across `ARCHITECTURE.md`, `README.md`, `TODO.md`
- [ ] Document the Exhibition's income contract once the accrual service lands
- [ ] Document a `ToolTiers` generator if/when it is reconstructed

**Summary.** `ARCHITECTURE.md` documents contracts that were previously implicit —
instance/attribute names services expect to find in the place file (`StageId`, `Shower`,
`StationKind`, `HoldPart`, `HoldCFrame`), which fields are optional vs. required and what
happens when they're missing, the `DebugCmd` attribute hook, and the full profile schema —
each fact checked against the actual code, not asserted from memory. It was revised once
already after the build/docs review caught four factual misses (an over-strict description
of `HoldPart`, an undocumented `DebugCmd` entry point, two missing required-instance
callouts, and a missing `/pocket` command in the console list).

---

## 9. Blocked / needs a human

- [ ] **Studio's Play toggle is wedged.** `start_stop_play` times out and will not enter
      or leave Play (reconfirmed this pass — a fresh attempt failed with a request
      timeout after 2+ minutes, Studio left cleanly in Edit mode). Needs a manual
      Play/Stop (or a Studio restart) to clear. Everything below is waiting on that,
      not on code.
- [ ] Live purchase test: buy at $200 (expect gear 1→2, cash exactly −120, held model
      swaps within ~0.5s), then retry at $80 and assert it is refused **with no state
      change** — the negative case matters more than the positive one, since a shop
      that debits on failure is worse than no shop.
- [ ] Live blackout test: `/stage 4`, wait for blackout, assert the player lands at the
      `RespawnAnchor` and `stageOf == nil`.
- [ ] Decon end-to-end regression after the `StationService` migration. No trader
      to regression-test any more — it's been removed from the world (see §3).
- [ ] Live Exhibition test: display an item at your own stand (real carry list, real
      station derived from standing at a real pedestal), confirm it renders on the
      physical stand and blocks undisplay for 60s, and that the cash badge ticks up on
      its own (~5s cadence) while something is displayed — no claim board to visit.
      `ExhibitService`'s pure logic (`standViewFor`, fail-closed with no profile) is
      already smoke-tested outside Play — see §3 — but nothing has exercised the
      position-derived station security property or the actual `Workspace` render
      (`Display{n}` color/transparency) with a real character yet.
- [ ] Border warning card (PLAN §4) — Stage 4 is ~7 seconds to blackout in a Cloth Wrap
      and sits 50 studs behind the camp wall. The fence, verge and sign are in; the
      HUD countdown is not. `StageService.onChanged` and `Radiation.survivableSeconds`
      both already exist and are unused, so this is ~60 lines.

---

## 10. Meta / late game — Phase 5, not yet scoped

Pulled from `PLAN.md` for later triage — nothing here has been sized or planned yet.
Listed so it's visible, not because it's next. Each depends on either the Exhibition (§3)
existing or on there being more than one real stage (§5) to make the system meaningful —
that's what makes this genuinely last rather than an arbitrary ordering choice.

- [ ] Stages 5–6 content (Reactor Grounds, The Crater — beyond the MVP slice)
- [ ] Rebirth / "Decontamination Protocol" (PLAN §9.3) — depends on the Exhibition existing,
      since the entire design point is "the Exhibition survives rebirth and nothing else does"
- [ ] Rail network (PLAN §5.3, §10.12) — needs multiple stages with real distance to matter
- [ ] Fallout storms (PLAN §4, §10.8) — needs multiple stages to feel server-wide
- [ ] Museum / Collection Wall (PLAN §10.10) — needs an item catalogue bigger than Stage 1's
- [ ] Field Contracts (PLAN §10.14), Pets (PLAN §10.15)
- [ ] Monetization (PLAN §11) — deliberately last; PLAN §11 itself says nothing sold should
      be required to reach the Crater, so this can't be tuned before the Crater loop exists
- [ ] Real audio (current geiger/ping sounds are Roblox stock placeholders, per PLAN §14)

---

*Update this file as items move between sections — don't let it drift out of sync with
reality the way `ToolTiers.luau` drifted from its own lost generator.*
