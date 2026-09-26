--!strict
--[[
	Shops.luau — where cash turns back into capability.

	    require(game.ServerScriptService.Server.build.Shops).rebuild()

	THREE STALLS ON THE PLAZA, one per tool you hold: the detector that finds it, the
	magnet that pulls it, and the hose that washes it. Each is a different colour
	and keeps that colour forever. A young player learns "the coral one is the
	detector shop" once and then navigates by colour rather than by reading signs,
	which is the cheapest legibility win available anywhere in this map.

	PLUS AN OUTFITTER, a fourth stall, and this one is not decoration.
	Three stalls covers Detector, Magnet and Cleaner and leaves the Aura priced
	but unbuyable — and the AURA is the gate on every stage in the game. Without a way
	to buy one, Stage 2 stops being "you can go there and here is what it costs" and
	becomes exactly the locked door PLAN §3.5 promises never to build. It costs nothing
	to add because the shop system is track-generic: it is more counters with more
	StationIds.

	THE OUTFITTER USED TO BE THREE COUNTERS WIDE. Boots was the middle one, and the
	track was retired when speed stopped being something you buy — see
	Config/Treadmill.luau, and the treadmill build/Plots now stands on every base. The
	building resized itself: its span and width are both derived from
	`#OUTFITTER.counters`, so removing an entry was the whole edit.

	THE SPLIT BETWEEN THE STALLS AND THIS BENCH IS "DO YOU HOLD IT". The three stalls
	sell the three things ToolService can put in your hands; the Outfitter sells the
	three you wear. Luck briefly sat here too, as a fourth desk selling something you
	do not physically have at all — since moved out to its own button (see the LUCK
	IS NOT HERE note below).

	EVERY TIER OF A TRACK HANGS ON A RAIL BESIDE THE STAND, AND YOU PICK THE ONE YOU
	ARE STANDING AT. The ladder used to be visible only as a list: walk into a radius,
	a scrolling panel of cards opens, pick a row. It is a physical object now — eight
	detectors in a row, cheapest first, each hung from the rail and standing on the
	deck, its price on a card above it and its own ProximityPrompt — so browsing is
	WALKING, and pressing E in front of the one you want opens that tier's own shop
	card, whose button buys it. The models are the
	real ones: Assets/Tools/<Track>/T<n>, exactly what ToolService clones into your hands.

	THE GEAR HANGS FLOOR-TO-RAIL, AND THAT STRIP IS THIS PASS. The rack first shipped
	hanging over a waist-high shelf, so every tier came out ~2 studs tall floating
	above the desk — a tier-1 magnet was a half-stud sliver. The shelf is gone. A tier
	now gets the whole rail-to-floor drop: scaled up to fill it and stood on the deck,
	so the shop finally shows the thing it is selling at a size you can read from
	across the plaza. See RACK_DROP_* and `hangTierModel`.

	A STOREFRONT IS A STAND PLUS A WING. A short STAND at the left end (the desk, its
	sign, its outline on the ground) and, past a gap you can see daylight through, the
	WING — the open tier rack. So "where is the menu" has an answer you can see from
	across the plaza. See "The stand, and the wing beside it" for the constants and for
	why BOTH halves carry the station attributes.

	THE PANEL DID NOT GO AWAY. The stand keeps its StationKind and the card panel
	still opens — the whole storefront, every tier side by side. The rack's E opens
	just the one card you walked up to ("I know which one I want"), the stand's E the
	whole row ("which one SHOULD I want"). Both are the same card and the same button,
	so ShopService.buyTier sits behind one door, not two.

	A STALL IS AS WIDE AS ITS TRACK IS LONG. `stallWidth` derives it from
	Gear.maxTier, so the Detector stall (8 tiers) is wider than the Magnet stall (6),
	and adding a tier in Config/Gear widens that one shop with nothing else to edit.
	Posts, slats, shelf, roof plate count and both floor markers all key off that
	one number, which is why moving a stall's `at` (see below) or widening a track
	can turn a comfortable gap into an overlap. `assertNoShopOverlap` proves the
	current arrangement at every rebuild rather than any paragraph here trying to.

	THE LOOK — the supplied classic-Roblox Gear Store reference, stripped to the
	structure. Each tool stall has studded posts, a slatted rear wall, an open
	counter with a steel cap, a shallow riveted steel-plate roof IN THE STALL'S OWN
	COLOUR (coral / teal / purple) with a hazard-striped fascia across its front
	edge (see `buildPlateRoof`), and a small one-line sign centred over the whole stall
	that NAMES WHAT THE STALL SELLS ("Detector Shop" / "Magnet Shop" / "Hose
	Shop") in that same accent. The Outfitter gets the identical shell at its own
	width, its one counter signed the same stall-style way ("Aura Shop") — see
	`buildOutfitter`'s own header for why it used to be a separate building, and
	why it used to be three counters, then two.

	THE DECORATION IS GONE, AND THAT WAS A DELIBERATE STRIP. Earlier passes stood a
	blocky shopkeeper behind each counter, a big silhouette prop of the thing sold
	(a detector, a horseshoe magnet, a bucket-and-brush, an aura mannequin…) beside it,
	a crate and an open chest of clutter on the deck, and a rubber duck on the roof.
	All removed. What identifies a stall now is the sign naming its wares plus its
	accent colour — the sign text, the counter trim cap and the floor-marker
	outline all in the shop's own hue.

	THE LUMBER IS GREY, NOT BROWN. Posts, counters, the Outfitter's walls, roof
	beams and rear slats all paint from C.shopWood / C.shopWoodLight — a cool
	neutral grey, so the built structure reads as painted timber and the shop's own
	accent colour (trim cap, canopy, floor marker) is the only warm thing on the
	stall.

	THE GLOW STAYS OUT OF GREEN. The floor outline marking the buy radius uses the
	shop's own accent colour, never green, so "glowing green" still means exactly
	one thing anywhere in the world: the ooze (PLAN §14).

	THE WORLD CONTRACT (unchanged by the reskin):
	    StationKind = "shop"      -- what kind of thing you are standing at
	    StationId   = "Detector"  -- which track, EXACTLY as spelled in Gear.TRACKS
	    Radius      = <studs>

	StationId rather than a StationKind of "shop_detector" keeps the kind enum small
	and lets one client panel be parameterised by track. It is deliberately the
	capitalised Gear.TRACKS spelling, so no case conversion happens at the world
	boundary — the single lowercase translation lives in Gear.profileKey and nowhere
	else. A plaza stall emits that trio TWICE — once on the stand at STAND_RADIUS and
	once on an invisible RackZone anchor at the wing, at a radius derived from the
	rack's own width — because the client's owned-ticks need the offer live at both
	ends of the storefront and a single circle covering both would reach back into the
	courtyard. Same kind, same StationId, and `StationService.at` takes the nearest, so
	there is exactly one answer to "which shop am I at" anywhere on the front. The
	Outfitter's counters keep their tight 6 and stay one part each.

	    SellsTrack = "Detector"   -- this hook sells a rung of this track
	    SellsTier  = 5            -- which rung, indexing Config/Gear directly

	Those two are the rack's own contract, and they sit on the small steel MOUNT
	block, never on a part of the display model — the model is a clone of a place
	asset this file does not own and cannot promise the shape of, while the mount is
	built here and exists even when the art does not. Kit.build tags anything with a
	SellsTrack into Kit.UPGRADE_TAG, which is what ShopService scans to wire the
	prompt and what World.verify() asserts is present.

	EACH STALL HAS ITS OWN EXPLICIT `at = {x, z}` IN `STALLS`, same shape as
	`OUTFITTER.at` below — there used to be a shared `bearing` + `STALL_RING_RADIUS`
	that forced all three onto one ring around `PLAZA_MID` (x=17.5, z=0, itself the
	plaza midpoint, the camp datum (Hub.CAMP_ORIGIN) and the blackout-respawn anchor,
	all the same point). That constraint is gone: any stall (and the Outfitter) can
	sit anywhere on the plaza now, at any facing — see `facingDirFor` for how a
	shop's front direction is decided and `assertNoShopOverlap` for what still
	stops two of them landing on top of each other.

	TWO ROWS NOW, NOT A GRID WITH SHARED COLUMNS, AND HAND-PLACED RATHER THAN
	DERIVED. North row near z=30: Detector at x=31.87 with Outfitter parked right
	next to it at x=-17.03, the two reading as one pair. South row: Cleaner at
	(37.5, -37.10), Magnet at (-22, -34.43) — close to level with Cleaner but not
	exactly, since these are drag-and-captured positions, not a formula — with the
	Trader kiosk (BaseCamp.luau) sitting in the gap between them. `at` was captured
	directly off the Studio Explorer selection each was dragged to (see the note
	on selecting a nested model by name, not by clicking the plaza in the
	viewport), then hand-transcribed here so a rebuild reproduces it exactly.
	The whole cluster was then shifted 20 east as one block (every `at`, the
	Trader kiosk and Hub's SHOP_ZONE together) to centre it in the plaza octagon.
	Every stall carries an explicit `faceYaw` now: none of their `at`s sits due
	north/south of PLAZA_MID any more, so the default "aim at PLAZA_MID" would
	turn them diagonal.

	THE OUTFITTER IS A PLAZA STALL NOW TOO, not a separate walled building — see
	`buildOutfitter`'s own header for why that changed. It gets the exact same
	shell (`buildStorefrontPosts`, `buildSlatWall`, `buildPlateRoof`) at its
	own width, with three counters standing in for the one stand.

	`facingOrigin` IS THE ONLY PLACEMENT PRIMITIVE. Both builders lay every part as
	a local offset from the CFrame it returns, so that one CFrame carries a shop's
	whole position AND facing. It reads Hub.PLAZA.topY + Hub.PLAZA_LIFT for the ground
	plane (the raised plaza floor; PLAZA.topY is at Stages.SURFACE_Y, not Y=0). This
	file still reads nothing from
	Plots.luau: Plots requires Hub, Hub requires only Kit, and Shops stays a pure
	statement of positions. SHOP_CLUSTER_EAST_REACH (Hub.luau now; it places the plot
	ring's centre) is already marked historical in Plots.luau and stays a
	conservative bound, not a live measurement of anything here.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local ToolModels = require(Shared.ToolModels)
local ToolFX = require(Shared.ToolFX)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)
local ShopThemes = require(script.Parent.ShopThemes)

local Shops = {}

--- The one model every storefront in the world lives under, exported rather than
--- spelled out at each use because THREE places have to agree on it and one of them
--- is in another file. `Kit.swap` finds the old build by this name, `createShops`
--- stamps it, and World.verify() asserts no shop counter exists outside it — that
--- last check is the reason this stopped being a bare string literal. A stall
--- parented anywhere else survives every rebuild (swap only replaces what it can
--- find by name) and still registers as a live station.
Shops.MODEL_NAME = "Shops"

local BUILDER_SOURCE = "src/server/build/Shops.luau"
local BUILDER_VERSION = 47

local C = Kit.C
local build = Kit.build

--- Where the hanging tier models come from: the SAME templates ToolService clones
--- into a player's hands (Assets/Tools/<Track>/T<n>), so the thing on the rail is
--- literally the thing you are buying, not a stand-in sculpted to look like it.
---
--- Resolved with FindFirstChild rather than a dotted path because this folder lives
--- in the PLACE, not in this repo (the tier-model generator is long gone — see
--- Config/ToolTiers' header). A place missing it must still build a shop: every
--- lookup below degrades to the painted fallback block instead of erroring the
--- whole world rebuild over missing art.
local TOOL_LIBRARY: Instance? = nil
do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	TOOL_LIBRARY = if assets then assets:FindFirstChild("Tools") else nil
end

--- The middle everything else here faces: the plaza midpoint, Hub's central-spine
--- centreline, the camp datum and the blackout-respawn anchor, all this one point.
local PLAZA_MID = { x = 17.5, z = 0 }

--- Each plaza stall's world (x, z), same shape as `OUTFITTER.at` — freely
--- placeable, no shared ring or bearing forcing them together. By default
--- `facingOrigin` turns a stall to face PLAZA_MID from wherever `at` puts it; an
--- entry can override that with an explicit `faceYaw` (world degrees, 0 = local +Z
--- along world +Z, matching `Kit.ang`'s Y-euler) when it needs to face somewhere
--- PLAZA_MID does not point from that spot — see the layout below, where two
--- stalls in the same row only read as "in line" because both share a yaw
--- instead of each independently aiming at the middle. `assertNoShopOverlap` (end
--- of `createShops`) resolves the same override before checking, so a moved or
--- re-aimed stall still gets caught if it collides with a neighbour.
---
--- TWO ROWS OF SHOPS, EACH A PAIR PARKED NEXT TO EACH OTHER — hand-placed in
--- Studio (drag the model, not its parts — see the header's note on Explorer
--- selection) and captured from there rather than derived. The two rows are
--- close to level but not exact (Magnet and Cleaner sit a couple of studs apart
--- in z), because this is where they were actually dropped, not a formula.
--- The whole cluster moved 20 east as one block (see the header), so no stall sits
--- at PLAZA_MID's own x=17.5 any more and every one carries an explicit `faceYaw`;
--- Cleaner's 0 is exactly the facing its old default aim produced. `assertNoShopOverlap` (end of
--- `createShops`) is what actually proves none of this collides — not this
--- comment, and not the numbers looking reasonable.
--- `present` is the per-track hang angle for the rail models — see RACK_DROP_* and
--- `hangTierModel`. Tuned against front-on screenshots so each track stands from the
--- deck to (near) the rail without clipping its neighbour: the hose barely tips at all.
--- Magnet has none: it hangs off its hook instead of standing (see RACK_HANG).
---
--- DETECTOR'S `pitch = 0` IS NOT "UNTUNED", IT IS THE TUNED VALUE for the imported
--- per-tier models (tools/studio-migrations/import-detector-models.luau). `hand * hold`
--- is what actually orients a hung tier (`hold` = that tier's `HoldCFrame` attribute,
--- read below in `hangTierModel`), and the OLD detector art's `HoldCFrame` carried a
--- real rotation that a `pitch = -80` here was tuned to compose with. The new art's
--- `HoldCFrame` is an identity rotation (position-only — it already hangs its coil
--- straight down on its own, see that script's header), so any nonzero pitch here now
--- rotates it AWAY from vertical with nothing correcting it — `-80` hung every tier on
--- its side under the rail. Magnet and Cleaner are untouched by that migration and
--- still need a real `pitch` to compose with their own art's `HoldCFrame`.
local STALLS = {
	{ track = "Detector", at = { 31.87, 30 }, faceYaw = 180, color = C.shopDetector, label = "Detector Shop", present = { yaw = 205, pitch = 0 } },
	{ track = "Magnet", at = { -22, -34.43 }, faceYaw = 0, color = C.shopMagnet, label = "Magnet Shop" },
	{ track = "Cleaner", at = { 37.5, -37.10 }, faceYaw = 0, color = C.shopCleaner, label = "Hose Shop", present = { yaw = 196, pitch = -12 } },
}

-- ── The rack ─────────────────────────────────────────────────────────────────
--
-- EVERY TIER OF THE TRACK HANGS ON A RAIL OVER THE WING'S SHELF, beside the stand,
-- and E on the one you are standing in front of opens its shop card. That is the whole feature: the
-- shop panel used to be the only way to see what a track sold, so a player had to
-- walk into a radius, read a scrolling list of cards and pick a row. Now the ladder
-- is a physical object — eight detectors in a row, cheapest nearest the stand, each
-- with its own price over it and its own ProximityPrompt — and walking the wing IS
-- browsing it.
--
-- THE PANEL IS STILL THERE. This does not replace it; the stand keeps its
-- StationKind and the card panel still opens. The rack's E opens one tier's card, the
-- stand's E the whole row of them.
--
-- ONE PROMPT WINS AT A TIME, and that is Roblox's default, not something arranged
-- here: ProximityPromptService's default Exclusivity is OnePerButton, so of the
-- several hooks inside MOUNT_REACH only the closest shows its E. Walking left along
-- the counter hands the prompt from tier to tier, which is exactly the "walk up on
-- the one you want" read.
--
-- WHY THE HOOK CARRIES THE ATTRIBUTES AND NOT THE MODEL. `SellsTrack` + `SellsTier`
-- go on a small solid mount block welded to the rail, never on a part of the display
-- model. The model is a CLONE OF A PLACE ASSET this file does not own — its part
-- names, its part count and its PrimaryPart can all change the next time someone
-- edits the tool art — while the hook is built right here and is guaranteed to exist
-- even when the art is missing entirely (the fallback path below still builds one).
-- ShopService and World.verify() both scan for those attributes, so they have to sit
-- on something this file can promise.
local RACK_PITCH = 3.6 -- centre-to-centre between two hanging tiers
local RACK_END_MARGIN = 3 -- clear shelf past the dearest tier, at the wing's outer end
local RACK_RAIL_Y = 5.4 -- the horizontal bar the tiers hang from
local RACK_SLOT_WIDTH = RACK_PITCH - 0.6 -- across the rack: never touch the next tier
local RACK_SLOT_DEPTH = 3.6 -- into the stall: keep the tier's nose clear of the browse aisle

--- THE HANGING TIER STANDS ON THE STALL FLOOR NOW, not on a counter. The rack used
--- to hang over a waist-high display shelf and every tier came out ~2 studs tall,
--- floating just above the desk — a tier-1 magnet was a 0.5-stud sliver. That shelf
--- is gone (see "The stand, and the wing beside it"), so a tier gets the whole
--- rail-to-floor drop: `hangTierModel` scales it to fill that height, then slides it
--- straight down until its BASE rests on the deck. The read is a rack of real metal
--- detectors in a hardware store, coil on the ground, control box up by the rail.
---
--- A tier that fills the drop meets the rail; a compact one (the hose models are
--- short and blocky) hangs shorter with a slim `Hanger` strap bridging the gap up to
--- the rail, so it still reads as hung rather than floating.
local RACK_DROP_BASE = 0.1 -- local Y a tier's base rests at — the stall deck's top face
local RACK_DROP_TOP = RACK_RAIL_Y - 1.0 -- highest a tier's top may reach — the mount block's underside

--- Ceiling on how far a tier is blown up past the size ToolService hands you. The
--- tool models are authored small (a tier-1 magnet ships at 0.30 scale — it is a
--- thing you hold), and filling the whole drop from that would take a 2.7x blow-up
--- that turns the art chunky. Capped, a cheap tier hangs SHORTER than the drop with a
--- `Hanger` strap up to the mount — which also draws the eye up the rack as the price
--- climbs, cheapest and smallest nearest the stand.
local RACK_MAX_UPSCALE = 1.85

--- Child models to drop from a tier's DISPLAY clone (never the tool you are handed).
--- The magnet art carries a second, tiny "realistically sized" magnet next to the
--- hero one as an in-hand gag; blown up on the rack it just reads as a part dropped
--- on the deck. Matched by name and skipped silently if the art no longer has it —
--- this file does not own the model's shape (see the mount note above).
local RACK_HIDE_ON_DISPLAY = { "Realistically Sized Magnet" }

--- TRACKS THAT HANG OFF THEIR HOOK instead of standing floor-to-rail. A horseshoe
--- magnet stood up on the deck read as a row of U's with the hanger strap stabbed
--- down through each one, and the free tier lay on its side beside them: its art is
--- authored with the poles along -X where every other tier's run along +Z, so one
--- shared `present` angle could never stand all six the same way. So a magnet
--- ignores HoldCFrame and `present` entirely and is posed from its own geometry:
--- `legs` (the grip-frame direction its poles point) goes straight DOWN, `face`
--- (the side its details sit on) turns toward the customer, then the row yaws by
--- `yaw` together for a three-quarter view. Bend up, poles down: how a magnet hangs
--- off a hook, and where the Salvage Magnet's own `lift_hook` already sits.
---
--- SMALLER THAN THE DROP, on purpose. Each tier is fitted to a height that climbs
--- from `height[1]` (the free tier) to `height[2]` (the top one), and hangs with its
--- top `drop` studs under the mount, so the strap (`Hanger`) always shows and the
--- poles never reach the deck. Keyed by tier NAME for the odd-axis tiers, not tier
--- number, so a tier inserted into the line does not inherit someone else's axis.
type HangSpec = {
	legs: Vector3,
	legsByName: { [string]: Vector3 },
	face: Vector3,
	yaw: number,
	height: { number },
	drop: number,
}
local RACK_HANG: { [string]: HangSpec } = {
	Magnet = {
		legs = Vector3.new(0, 0, 1),
		legsByName = { ["Horseshoe Magnet"] = Vector3.new(-1, 0, 0) },
		face = Vector3.new(0, 1, 0),
		yaw = -20,
		height = { 1.4, 3.0 },
		drop = 0.6,
	},
}

--- Which way the virtual holder faces, and it is PER TRACK now (STALLS' `present`).
--- One shared pair cannot stand all three tracks up floor-to-rail: a detector's shaft
--- has to tip ~80 degrees nose-down to drop its coil to the deck, a horseshoe magnet
--- wants ~68, while the hose model is authored ALREADY upright (its HoldCFrame stands
--- it on end) and only wants a few degrees or it topples into the aisle. Yaw swings
--- the tool a little off dead-flat into a three-quarter view so its silhouette reads;
--- pitch tips its top toward the customer.
---
--- Yaw is applied in the STALL's frame and pitch in the yawed one (origin * Ry * Rx),
--- not Kit.ang's single XYZ euler — a pitch about the stall's own X before the yaw
--- tips the row sideways instead of tipping each tool forward.
local SHOPFRONT_Z = 0.6 -- the shopfront line: stand, rack rail and hanging gear all sit on it
local MOUNT_REACH = 11 -- prompt activation distance, from in front of the rack

-- ── The stand, and the wing beside it ───────────────────────────────────
--
-- THE STAND IS WHERE YOU TALK TO THE SHOP; THE WING IS WHERE THE STOCK LIVES. A
-- short STAND at the left end of the store (the desk with the station attributes, the
-- sign over it and the outline on the ground in front of it) and, past a gap you can
-- see daylight through, the WING — the open tier rack, its gear standing on the deck
-- from cheapest nearest the stand.
--
-- SO "WHERE IS THE MENU" HAS A PHYSICAL ANSWER. Walk to the stand for the card panel
-- and its stat blocks; walk down the wing to look at the actual tools and press E on
-- one. Two doors on the same purchase, and you can see which door is which from across
-- the plaza instead of learning it by walking into a radius.
--
-- BOTH HALVES CARRY THE STATION ATTRIBUTES, AND THAT IS NOT BELT-AND-BRACES. The
-- client's owned-check — the green tick that replaces a price on a tier you already
-- have — is painted from `state.offer`, which only exists while StationService says
-- you are AT this shop (StationController's rack pass says so in as many words). One
-- tight circle on the stand would blank every tick the moment you walked over to look
-- at the tools, which is the exact moment they are worth showing. One circle big
-- enough to cover both would have to be ~44 studs from a stand sitting at the end of
-- the store, and that reaches back past PLAZA_MID — a shop panel opening on the
-- respawn anchor in the middle of the courtyard. Two modest circles — the stand's
-- desk and the wing's invisible RackZone anchor — cover the storefront and nothing
-- else; `StationService.at` returns the NEAREST containing station, and both of these
-- answer with the same kind and the same StationId, so which one wins is a question
-- with one answer.
local STAND_WIDTH = 8 -- the desk itself, wide enough to stand at and no wider
local STAND_EDGE = 2 -- clear lumber outboard of the stand, at the store's left end
local STAND_RACK_GAP = 3 -- the break between stand and wing: this is the whole read
local STAND_RADIUS = STAND_WIDTH / 2 + 6 -- the desk, plus the forecourt you stand in

--- How close you have to be to the desk for its E to appear. DELIBERATELY INSIDE
--- STAND_RADIUS (8 against 10), because the prompt and the panel are two halves of one
--- interaction: pressing E only un-dismisses the panel, and the panel can only draw
--- from an `offer` that exists while StationService says you are AT this shop. A reach
--- LARGER than the radius would put an E in front of players standing outside the
--- station, who would press it and get nothing. Two studs of margin is enough for the
--- ~10Hz station tick to have caught up by the time the prompt is pressable.
local STAND_PROMPT_REACH = 8

--- How wide a stall has to be to hold its stand AND its whole ladder. DERIVED, not
--- written down: Detector has 8 tiers and Magnet 6, and a fixed width would either
--- crush the Detector rack or leave the Magnet stall two thirds empty. Every other
--- dimension of a stall (posts, slats, rack, canopy, floor markers) keys off this,
--- so adding a tier to a track in Config/Gear widens its shop and nothing else has
--- to move.
---
--- IT GREW BY SIX STUDS WHEN THE RACK CAME OFF THE COUNTER. It used to be
--- `rackSpan + 13` — the ladder plus five studs of clear counter either side. The
--- stand now occupies the whole left margin in its own right, so the sum is spelled
--- out left to right instead: edge, stand, gap, half a slot, the ladder, half a slot,
--- end margin. `assertNoShopOverlap` re-proves the layout at every rebuild, and at
--- the stalls' current `at` values it passes with ~21 studs to spare between fronts
--- and ~13 to the Outfitter, so nothing had to move to make room for this.
local function rackSpan(track: string): number
	return RACK_PITCH * (Gear.maxTier(track) - 1)
end

local function stallWidth(track: string): number
	return STAND_EDGE + STAND_WIDTH + STAND_RACK_GAP + RACK_SLOT_WIDTH + rackSpan(track) + RACK_END_MARGIN
end

--- The stand's centre, in the stall's own local x: hard against the LEFT end of the
--- store. Left as the customer sees it — a stall's +Z faces PLAZA_MID, so somebody
--- walking up to it has their right hand on the stall's +X, and the ladder that runs
--- cheapest-first from here therefore climbs away to their right.
local function standX(track: string): number
	return -stallWidth(track) / 2 + STAND_EDGE + STAND_WIDTH / 2
end

--- The wing's centre: past the stand, past the gap, then half a ladder. Falls at a
--- constant local x=5 for every track as the numbers currently stand (the stall grows
--- symmetrically about it), which is a coincidence of the arithmetic and not
--- something to hardcode — move any one constant above and it stops being true.
local function rackX(track: string): number
	return standX(track) + STAND_WIDTH / 2 + STAND_RACK_GAP + RACK_SLOT_WIDTH / 2 + rackSpan(track) / 2
end

--- How wide the rack sits: the ladder, plus the half-slot each end tier needs, plus
--- a stud of margin. Drives the wing's station-circle radius and its floor marker.
--- The rack's own end posts (span/2 + 1.5) stand just inside it.
local function rackFootprintWidth(track: string): number
	return rackSpan(track) + RACK_SLOT_WIDTH + 1
end

--- A stall's placed position, world XZ — just its `at`, same as OUTFITTER.at.
local function stallAt(spec: { at: { number } }): (number, number)
	return spec.at[1], spec.at[2]
end

--- The outfitter's counters on one bench. Radius 6 at a 13-stud pitch, so no two
--- counters' circles overlap and standing at one is unambiguous. The bench's own span
--- and width are derived from this list's length, so adding or retiring a track here
--- resizes the building rather than leaving a gap where a counter used to be.
---
--- `at` PUTS THIS RIGHT NEXT TO DETECTORSHOP, in the north row (z=30) —
--- hand-placed alongside it, same as STALLS now (see that table's header).
--- `faceYaw = 180` is an explicit override, same reason DetectorShop and
--- MagnetShop need one: PLAZA_MID does not sit due east of this spot, so the
--- default "aim at PLAZA_MID" would turn this stall's front to face south-east
--- instead of square south at its row-mate, which is what actually reads as
--- "next to it" rather than merely nearby.
local OUTFITTER = {
	at = { -17.03, 30 },
	faceYaw = 180,
	pitch = 13,
	counters = {
		{ track = "Aura", label = "Aura Shop" },
		-- BOOTS IS NOT HERE ANY MORE. The track is retired (Config/Gear's `Gear.Boots`
		-- header): speed is trained on a treadmill at your own base now, not bought at
		-- a counter. Nothing here had to learn that -- dropping it from Gear.TRACKS
		-- is what took it out of the sell path, and this entry only had to go so the
		-- bench would not build a counter selling a track the shop refuses.
		-- NEITHER IS THE SATCHEL, for the same reason: retired (Config/Gear's RETIRED
		-- block), and the haul penalty it carried moved onto the Aura sold here.
		-- LUCK IS NOT HERE, and it briefly was. It is the one track you neither hold
		-- nor wear, and a desk here sold it as though it were a satchel. It
		-- moved to a glowing button staked next to the wash pad it actually affects
		-- (build/Plots.buildLuckButton) -- press E, no panel. World.verify() still
		-- asserts every priced track is buyable somewhere; it accepts a `SellsTrack`
		-- attribute as well as a shop counter, which is what keeps that check honest
		-- after this move.
	},
}

--- The direction a shop's front (local +Z) points in world XZ, as a unit vector.
--- `faceYaw`, when given, is taken literally (0 = world +Z, matching Kit.ang's Y
--- convention) so two shops at different positions can still share an exact
--- facing. Omitted, it falls back to "aim at PLAZA_MID from (x, z)" — the original
--- default every shop had before facing became overridable.
---
--- THE ONE PLACE THIS DIRECTION IS COMPUTED, so a shop's built geometry
--- (`facingOrigin`) and its overlap footprint (`shopFootprint`) can never
--- disagree about which way it faces — they used to each independently assume
--- "toward PLAZA_MID", which only stayed correct because nothing could face
--- anywhere else yet.
local function facingDirFor(x: number, z: number, faceYaw: number?): (number, number)
	if faceYaw then
		local r = math.rad(faceYaw)
		return math.sin(r), math.cos(r)
	end
	local dirX, dirZ = PLAZA_MID.x - x, PLAZA_MID.z - z
	local len = math.sqrt(dirX * dirX + dirZ * dirZ)
	return dirX / len, dirZ / len
end

--- A build origin on the plaza plane at world (x, z), turned so its local +Z —
--- every shop's counter-facing front — points along `facingDirFor(x, z, faceYaw)`.
--- Both builders lay every part as a local offset from what this returns, so this
--- one CFrame is the whole of a shop's position AND its facing.
local function facingOrigin(x: number, z: number, faceYaw: number?): CFrame
	-- The shop square is part of the raised plaza floor (Hub.PLAZA_LIFT), so every stall
	-- stands on that, not on the lawn's PLAZA.topY.
	local topY = Hub.PLAZA.topY + Hub.PLAZA_LIFT
	local dirX, dirZ = facingDirFor(x, z, faceYaw)
	-- CFrame.lookAt aims local -Z (its LookVector) at the target; the shop fronts
	-- are +Z, so aim -Z the opposite way down `dir` and +Z lands facing along it.
	return CFrame.lookAt(Vector3.new(x, topY, z), Vector3.new(x - dirX, topY, z - dirZ))
end

-- ── The floor marker ─────────────────────────────────────────────────────────

--- A rectangular outline on the ground marking the buy radius — the reference
--- photo's floor square, recoloured per shop instead of always blue so it keeps
--- doing the colour-navigation job instead of flattening it. Four thin matte bars
--- rather than a filled plate, matching the "outline, not fill" read the photo has.
local function buildFloorMarker(parent: Instance, origin: CFrame, x: number, z: number, width: number, depth: number, color: string)
	local thickness = 0.4
	for _, bar in {
		{ w = width, d = thickness, dx = 0, dz = -depth / 2 },
		{ w = width, d = thickness, dx = 0, dz = depth / 2 },
		{ w = thickness, d = depth, dx = -width / 2, dz = 0 },
		{ w = thickness, d = depth, dx = width / 2, dz = 0 },
	} do
		build(parent, origin, {
			name = "FloorMarker",
			pos = { x + bar.dx, 0.08, z + bar.dz },
			size = { bar.w, 0.15, bar.d },
			color = color,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end
end

-- ── Reference gear-store details ─────────────────────────────────────────────

--- Four chunky posts holding a canopy up, in grey storefront lumber (C.shopWood).
--- Square-cut, not round logs — the reference photo's posts read as sawn beams,
--- and Block needs no rot (unlike Cylinder, whose long axis is local X and needs
--- R.cylUp to stand it upright) since a Block's size is already literal {X,Y,Z}.
--- Plastic, not Wood: Roblox's stud-bump texture only renders on Plastic, and
--- that studded look is what makes this read as the chunky reference stall
--- instead of a plain wood kiosk.
---
--- Shared by the plaza stalls and the Outfitter — the same four-post frame at
--- whatever `width` the caller's canopy spans.
local function buildStorefrontPosts(parent: Instance, origin: CFrame, width: number)
	local POST_SIZE = 1.5
	local postDX = width / 2 - POST_SIZE / 2
	for _, dx in { -postDX, postDX } do
		for _, dz in { -10, 2 } do
			local postHeight = if dz < 0 then 10 else 9.2
			build(parent, origin, {
				name = "Post",
				pos = { dx, postHeight / 2, dz },
				size = { POST_SIZE, postHeight, POST_SIZE },
				color = C.shopWood,
				material = "Plastic",
				shape = "Block",
				studs = true,
			})
		end
	end
end

--- THE ROOF IS RIVETED STEEL PLATE in the stall's own colour, with a hazard-striped
--- fascia across the front. It replaced the striped cloth canopy and valance on
--- 2026-09-25. The user picked it from Play mockups over a see-through corrugated
--- roof and a shipping-container stall. It matches the Trader's hazmat booth.
---
--- `accent` is the stall's own hex. The plates alternate it with a darker shade of
--- itself, checkered across two rows, so every plate reads as its own sheet of
--- steel. The roof is still the biggest painted surface on the stall, so it stays
--- the loudest per-shop colour cue (with the trim cap, floor marker and sign text).
--- Plates, seams and fascia are studded Plastic like the rest of the stall. Only
--- the rivets are smooth, because they are metal fittings (see Kit's stud rule).
---
--- `width` IS THE STALL'S OWN WIDTH. The plate COUNT is derived from it, about one
--- plate per ROOF_PLATE_TARGET studs, and forced odd so both ends of the roof finish
--- on the same shade. The roof keeps the old canopy's pitch and footprint (centre
--- ROOF_CENTER_Y up at z = ROOF_CENTER_Z, ROOF_DEPTH deep, ROOF_TILT down to the
--- front). That keeps ShopThemes' roof props standing on its ROOF_Y and keeps
--- assertNoShopOverlap's -11.25 back edge true.
local ROOF_CENTER_Y = 9.8
local ROOF_CENTER_Z = -4
local ROOF_DEPTH = 14.5
local ROOF_TILT = 4 -- degrees, front edge low
local ROOF_PLATE_TARGET = 4.6 -- studs across one plate, before rounding to an odd count
local ROOF_PLATE_SHADE = 0.16 -- how much darker the second plate of each checker pair is
local ROOF_STEEL = "59636D" -- seam straps, fascia frame and edge trim
local ROOF_RIVET = "C9D1D8"
local ROOF_RIVET_PITCH = 2 -- studs between rivets along a seam strap
local FASCIA_HEIGHT = 1.5
local FASCIA_STRIPE_WIDTH = 0.6
local FASCIA_STRIPE_PITCH = 1.7
local FASCIA_RIVET_PITCH = 2

--- The roof is solid steel over the whole stall, so the sun never reaches the
--- deck, the rack or the slat wall under it and the shop reads as a dark cave from
--- the plaza. This hangs one invisible panel just under the plates, at their tilt,
--- with a warm SurfaceLight shining down off its Bottom face — the whole roof
--- glows evenly instead of a few hot bulbs. ONE light per stall, Shadows off: a
--- shadow-casting light per stall is the cost the plots dropped their stand lights
--- over. The panel is CanQuery false, so it never eats a prompt or a
--- camera ray the way the invisible WashStand box did.
local CANOPY_LIGHT_COLOR = "FFE7C2" -- warm lamp white, so the accent colours stay true
local CANOPY_LIGHT_BRIGHTNESS = 2.4 -- picked live in Studio: 1.6 still read dim, 2.4 lights the deck without washing the colour out
local CANOPY_LIGHT_RANGE = 14 -- the panel sits ~9.5 up; reaches the deck with room to spare

local function buildCanopyLight(parent: Instance, origin: CFrame, width: number, centerY: number, centerZ: number, depth: number, tiltDegrees: number)
	local panel = build(parent, origin, {
		name = "CanopyLight",
		pos = { 0, centerY - 0.6, centerZ },
		size = { width - 1, 0.1, depth - 1.5 },
		color = CANOPY_LIGHT_COLOR,
		material = "SmoothPlastic",
		rot = Kit.ang(tiltDegrees, 0, 0),
		transparency = 1,
		canCollide = false,
	})
	panel.CanQuery = false
	panel.CanTouch = false
	panel.CastShadow = false

	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = Color3.fromHex(CANOPY_LIGHT_COLOR)
	light.Brightness = CANOPY_LIGHT_BRIGHTNESS
	light.Range = CANOPY_LIGHT_RANGE
	light.Angle = 120
	light.Shadows = false
	light.Parent = panel
end

--- One smooth metal rivet head. Rivets are the roof's most numerous part, so they
--- cast no shadow: a shadow the size of a pea costs the same to draw as a big one.
local function buildRivet(parent: Instance, frame: CFrame, x: number, y: number, z: number, size: number)
	local rivet = build(parent, frame, {
		name = "RoofRivet",
		pos = { x, y, z },
		size = { size, size, size },
		color = ROOF_RIVET,
		material = "Metal",
		shape = "Ball",
		canCollide = false,
	})
	rivet.CastShadow = false
end

--- A straight steel strip: seam straps, fascia frame rails and trim.
local function buildSteelStrip(parent: Instance, frame: CFrame, name: string, pos: { number }, size: { number })
	build(parent, frame, {
		name = name,
		pos = pos,
		size = size,
		color = ROOF_STEEL,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})
end

--- The hazard fascia hangs where the valance used to, across the roof's low front
--- edge. The stripes are rotated bars, not stepped blocks (straight edges read
--- cleaner from the ground). A bar at 45 degrees pokes a little past the band at
--- the top and bottom. The two steel frame rails are sized to cover that, and the
--- end caps cover the part-stripes at each end.
local function buildHazardFascia(parent: Instance, origin: CFrame, width: number)
	local half = ROOF_DEPTH / 2
	local frontZ = ROOF_CENTER_Z + half
	local frontY = ROOF_CENTER_Y - math.sin(math.rad(ROOF_TILT)) * half
	local band = origin * CFrame.new(0, frontY - 0.55, frontZ + 0.2)

	build(parent, band, {
		name = "HazardBand",
		pos = { 0, 0, 0 },
		size = { width + 0.4, FASCIA_HEIGHT, 0.4 },
		color = C.hazard,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})

	local stripeLength = FASCIA_HEIGHT * math.sqrt(2)
	local stripeReach = (FASCIA_HEIGHT + FASCIA_STRIPE_WIDTH * math.sqrt(0.5)) / 2
	local x = -width / 2 + stripeReach - 0.5
	while x <= width / 2 - stripeReach + 0.5 do
		build(parent, band, {
			name = "HazardStripe",
			pos = { x, 0, 0.22 },
			size = { FASCIA_STRIPE_WIDTH, stripeLength, 0.06 },
			color = C.hazardBlack,
			material = "Plastic",
			rot = Kit.ang(0, 0, 45),
			studs = true,
			canCollide = false,
		})
		x += FASCIA_STRIPE_PITCH
	end

	for _, dy in { FASCIA_HEIGHT / 2, -FASCIA_HEIGHT / 2 } do
		buildSteelStrip(parent, band, "FasciaFrame", { 0, dy, 0.1 }, { width + 0.9, 0.5, 0.62 })
		for i = 0, math.floor(width / FASCIA_RIVET_PITCH) do
			buildRivet(parent, band, -width / 2 + i * FASCIA_RIVET_PITCH, dy, 0.44, 0.26)
		end
	end
	for _, side in { -1, 1 } do
		buildSteelStrip(parent, band, "FasciaCap", { side * (width / 2 + 0.2), 0, 0.1 }, { 0.6, FASCIA_HEIGHT + 0.5, 0.64 })
	end
end

local function buildPlateRoof(parent: Instance, origin: CFrame, accent: string, width: number)
	local plateCount = math.max(3, math.floor(width / ROOF_PLATE_TARGET))
	if plateCount % 2 == 0 then
		plateCount += 1
	end
	local plateWidth = width / plateCount
	local darkPlate = Kit.blendHex(accent, "000000", ROOF_PLATE_SHADE)
	local half = ROOF_DEPTH / 2

	-- Everything on the roof is laid in the roof's own tilted frame: x across the
	-- stall, z down the slope (+z is the low front edge), y up out of the steel.
	local roof = origin * CFrame.new(0, ROOF_CENTER_Y, ROOF_CENTER_Z) * Kit.ang(ROOF_TILT, 0, 0)

	-- Two rows of plates, checkered. The back row runs 0.3 past the middle and sits
	-- a hair higher, lapping over the front row the way real roofing sheds rain.
	for col = 1, plateCount do
		local x = -width / 2 + (col - 0.5) * plateWidth
		for row = 1, 2 do
			local back = row == 1
			build(parent, roof, {
				name = "RoofPlate",
				pos = { x, if back then 0.05 else -0.02, if back then -half / 2 + 0.15 else half / 2 },
				size = { plateWidth + 0.02, 0.45, if back then half + 0.3 else half },
				color = if (col + row) % 2 == 0 then accent else darkPlate,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
		end
	end

	-- A riveted strap down every seam between plates, and a wider one on each edge.
	local rivetsPerStrap = math.floor((ROOF_DEPTH - 1.2) / ROOF_RIVET_PITCH) + 1
	for i = 0, plateCount do
		local strapWidth = if i == 0 or i == plateCount then 0.6 else 0.42
		local x = math.clamp(-width / 2 + i * plateWidth, -width / 2 + strapWidth / 2, width / 2 - strapWidth / 2)
		buildSteelStrip(parent, roof, "RoofSeam", { x, 0.33, 0 }, { strapWidth, 0.22, ROOF_DEPTH })
		for j = 0, rivetsPerStrap - 1 do
			buildRivet(parent, roof, x, 0.46, -half + 0.6 + j * (ROOF_DEPTH - 1.2) / (rivetsPerStrap - 1), 0.3)
		end
	end
	-- The lap between the two rows, and the back edge: one rivet mid-plate on each.
	for _, z in { 0.15, -half + 0.3 } do
		buildSteelStrip(parent, roof, "RoofSeam", { 0, 0.33, z }, { width, 0.22, 0.45 })
		for col = 1, plateCount do
			buildRivet(parent, roof, -width / 2 + (col - 0.5) * plateWidth, 0.46, z, 0.3)
		end
	end
	for _, side in { -1, 1 } do
		buildSteelStrip(parent, roof, "RoofEdge", { side * (width / 2 + 0.15), 0.1, 0 }, { 0.3, 0.9, ROOF_DEPTH })
	end

	buildHazardFascia(parent, origin, width)

	-- The two lumber beams the roof rests on, front and back, in the posts' grey.
	for _, z in { ROOF_CENTER_Z - half + 0.35, ROOF_CENTER_Z + half - 0.35 } do
		local y = ROOF_CENTER_Y - math.sin(math.rad(ROOF_TILT)) * (z - ROOF_CENTER_Z) - 0.38
		build(parent, origin, {
			name = "CanopySupport",
			pos = { 0, y, z },
			size = { width, 0.4, 0.5 },
			color = C.shopWood,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	buildCanopyLight(parent, origin, width, ROOF_CENTER_Y, ROOF_CENTER_Z, ROOF_DEPTH, ROOF_TILT)
end

--- Seven separated boards form the open slatted back seen most clearly in the
--- third reference image. The gaps keep the booth airy instead of turning it
--- into a solid shed. `width` is the stall's own width — the boards used to be a
--- flat 14.8 because every stall was 15 wide, and a fixed board behind a 38-wide
--- Detector stall leaves the rack's two end tiers hanging against open sky.
local function buildSlatWall(parent: Instance, origin: CFrame, width: number)
	for index = 1, 7 do
		build(parent, origin, {
			name = `BackSlat{index}`,
			pos = { 0, 0.8 + (index - 1) * 1.2, -10 },
			size = { width - 0.2, 0.88, 0.55 },
			color = C.shopWoodLight,
			material = "Plastic",
			studs = true,
		})
	end
end

-- The icon-disc glyphs, drawn from Frames so the server needs no uploaded art. Keyed
-- by a word in the sign's label; a label with none of them (a camp stall's own name)
-- simply gets no disc and a shorter pill.
local SIGN_ICON_INK = Color3.fromRGB(15, 26, 10)
local SIGN_GLOW_IMAGE = "rbxassetid://76655055685501" -- HudArtwork.IMAGE.glow

local function signShape(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, rot: number?, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.Parent = parent
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = f
	end
	return f
end

local function signRing(parent: Instance, x: number, y: number, w: number, h: number, thickness: number, rot: number?)
	local f = signShape(parent, x, y, w, h, SIGN_ICON_INK, rot, true)
	f.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = SIGN_ICON_INK
	stroke.Thickness = thickness
	stroke.Parent = f
end

--- Draws the glyph for `label` inside a 36x36 `disc` filled with `accentColor`.
local function buildSignIcon(disc: Frame, label: string, accentColor: Color3)
	local lower = label:lower()
	if lower:find("detector") then
		signRing(disc, 18, 18, 24, 24, 2.5)
		signRing(disc, 18, 18, 11, 11, 2.5)
		signShape(disc, 18, 18, 4, 4, SIGN_ICON_INK, 0, true)
	elseif lower:find("magnet") then
		signRing(disc, 18, 20, 20, 20, 5)
		signShape(disc, 18, 12, 30, 14, accentColor) -- hides the ring's top half: a horseshoe
		signShape(disc, 10, 14, 5, 12, SIGN_ICON_INK)
		signShape(disc, 26, 14, 5, 12, SIGN_ICON_INK)
		signShape(disc, 10, 9, 5, 4, Color3.new(1, 1, 1))
		signShape(disc, 26, 9, 5, 4, Color3.new(1, 1, 1))
	elseif lower:find("hose") then
		signRing(disc, 18, 18, 24, 24, 3)
		signRing(disc, 18, 18, 10, 10, 3)
		signShape(disc, 28, 28, 13, 3, SIGN_ICON_INK, 45)
	elseif lower:find("trader") then
		signRing(disc, 18, 18, 24, 24, 2.5)
		signShape(disc, 18, 18, 4, 18, SIGN_ICON_INK) -- a "$": bar + three strokes
		signShape(disc, 18, 13, 12, 3, SIGN_ICON_INK)
		signShape(disc, 18, 18, 12, 3, SIGN_ICON_INK)
		signShape(disc, 18, 23, 12, 3, SIGN_ICON_INK)
	elseif lower:find("aura") then
		signShape(disc, 18, 18, 6, 6, SIGN_ICON_INK, 0, true)
		signRing(disc, 18, 18, 28, 11, 2, 0)
		signRing(disc, 18, 18, 28, 11, 2, 60)
		signRing(disc, 18, 18, 28, 11, 2, 120)
	end
end

--- The floating stall sign: a dark glow pill in the shop's accent colour -- the same
--- family as the HUD's glow-orb tiles -- with a round icon disc and the stall's name
--- ("Detector Shop" / "Magnet Shop" / "Hose Shop" / "Aura Shop"), so the sign does
--- the colour-navigation. `accent` is the shop's hex string. Hung ABOVE the roof (the
--- highest point of `buildPlateRoof`'s plates and rivets is ~10.9 studs up at the
--- stall's own origin, so 11.5 clears it) so it reads over the whole structure
--- instead of hiding behind its own roofline.
---
--- Kit.FONT (FredokaOne) now, matching the HUD tiles it is modelled on; TextScaled
--- so any label length fits the fixed band.
local function buildStoreBillboard(adornee: BasePart, label: string, accent: string, offsetY: number?)
	local accentColor = Color3.fromHex(accent)
	local lower = label:lower()
	local iconed = lower:find("detector") or lower:find("magnet") or lower:find("hose") or lower:find("aura") or lower:find("trader")

	local gui = Instance.new("BillboardGui")
	gui.Name = "StoreSign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(iconed and 250 or 210, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 11.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.Parent = adornee

	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.3, 1.9)
	glow.BackgroundTransparency = 1
	glow.Image = SIGN_GLOW_IMAGE
	glow.ImageColor3 = accentColor
	glow.ImageTransparency = 0.55
	glow.Parent = gui

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.new(1, -10, 0, 44)
	pill.BackgroundColor3 = Color3.fromRGB(17, 26, 17)
	pill.BackgroundTransparency = 0.06
	pill.BorderSizePixel = 0
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.Color = accentColor
	rim.Thickness = 3
	rim.Parent = pill

	local textLeft = 16
	if iconed then
		local disc = signShape(pill, 26, 22, 36, 36, accentColor, 0, true)
		disc.Name = "Icon"
		buildSignIcon(disc, label, accentColor)
		textLeft = 50
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(textLeft, 5)
	title.Size = UDim2.new(1, -(textLeft + 16), 1, -10)
	title.BackgroundTransparency = 1
	title.Font = Kit.FONT
	title.Text = label
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = pill
	Kit.textOutline(title, 2)
end

-- ── The counter ───────────────────────────────────────────────────────────────

export type CounterSpec = {
	name: string?,
	color: string,
	width: number,
	depth: number,
	z: number,
	stationKind: string?,
	stationId: string?,
	radius: number?,
	promptText: string?,
	promptReach: number?,
	material: string?,
	studded: boolean?,
}

--- The counter desk — the interactive part — in grey storefront lumber
--- (C.shopWood) with a coloured trim cap on top in the shop's own accent.
--- Returns the desk so the caller can billboard it. `name` defaults to "Counter"
--- and is passed explicitly by the plaza stalls' one Stand so it does not collide in
--- the explorer with the Outfitter's three "Counter" desks.
---
--- `promptText` OPTS THIS DESK INTO BEING THE THING YOU PRESS E ON, and a desk without
--- it gets no prompt at all. The shop panel does not open on approach any more — see
--- the "you press E" note in the header — so every desk a player is meant to open a
--- panel at needs one. `material` defaults to "Wood"; every caller in this file now
--- passes "Plastic" (with `studded`) instead, since Roblox's stud-bump texture only
--- renders on Plastic, and that studded look is the whole point of the reskin — the
--- default stays plain Wood for whatever calls this without opting in.
local function buildCounter(parent: Instance, origin: CFrame, spec: CounterSpec): BasePart
	local w, d, z = spec.width, spec.depth, spec.z

	local attrs = nil
	if spec.stationKind then
		attrs = { StationKind = spec.stationKind, StationId = spec.stationId, Radius = spec.radius }
	end

	local name = spec.name or "Counter"
	local desk = build(parent, origin, {
		name = name,
		pos = { 0, 1.1, z },
		size = { w, 2.2, d },
		color = C.shopWood,
		material = spec.material or "Wood",
		studs = spec.studded,
		attributes = attrs,
	})

	build(parent, origin, { name = `{name}Trim`, pos = { 0, 2.25, z }, size = { w + 0.4, 0.3, d + 0.4 }, color = spec.color, material = "Plastic", studs = spec.studded, canCollide = false })

	if spec.promptText then
		local prompt = Instance.new("ProximityPrompt")
		-- StationController matches on this name, and on nothing else: the rack's own
		-- hooks are "Upgrade" prompts that buy a tier outright, and the two must never
		-- be confused for each other by whatever is listening.
		prompt.Name = "ViewShop"
		prompt.ActionText = "Browse"
		prompt.ObjectText = spec.promptText
		-- NO HOLD. The rack's buy prompts hold for 0.4s because they spend money on
		-- release; this one opens a window, and a window that makes you hold a key to
		-- look through it is just a slower window.
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = spec.promptReach or STAND_PROMPT_REACH
		-- The trim cap overhangs the desk by a couple of studs, which is enough to
		-- occlude a prompt anchored in the desk's own centre from a player standing at
		-- normal height in front of it.
		prompt.RequiresLineOfSight = false
		prompt.Parent = desk
	end

	return desk
end

-- ── The hanging tier rack ───────────────────────────────────

--- The template for one tier of `track`, or nil if this place has no art for it.
--- Same lookup ToolService.equip does, deliberately: if the model it would put in
--- your hands does not exist, the rack must not pretend it does.
---
--- CODE-AUTHORED TRACKS ARE ASKED FIRST, and for that one reason: it is what the
--- player will actually be handed. Shared/ToolModels owns the Cleaner track's seven
--- hoses now (see its header for why that track left the place file), so a stale
--- `Assets/Tools/Cleaner` folder full of the old brushes and sponges must NOT win here
--- — a rack advertising a Wire Brush that the wash bay then hands you as a Garden Hose
--- is the exact "the thing on the rail is not the thing you get" failure this rack was
--- built to avoid.
---
--- The caller clones what comes back, so handing it a freshly built model rather than
--- a library instance costs one throwaway Model per tier per rebuild and keeps the two
--- paths identical from here down.
local function tierTemplate(track: string, tier: number): Model?
	if ToolModels.has(track) then
		return ToolModels.create(track, tier)
	end
	if TOOL_LIBRARY == nil then
		return nil
	end
	local folder = TOOL_LIBRARY:FindFirstChild(track)
	local model = if folder then folder:FindFirstChild(`T{tier}`) else nil
	if model and model:IsA("Model") and model.PrimaryPart ~= nil then
		return model
	end
	return nil
end

--- Hang one tier's real model under the rail, standing on the stall deck at local `x`.
--- Returns the tier top's local Y (so the caller can bridge a `Hanger` strap up to
--- the rail), or nil when this place has no art for the tier.
---
--- ORIENTED THE WAY IT IS CARRIED, via the model's own `HoldCFrame` — the attribute
--- ToolService reads to place the thing in a player's hands. Feed it a virtual hand
--- turned to face the customer and the tool lands at exactly the angle a shopkeeper
--- holding it out would present it at. That matters because the three tracks do NOT
--- share an authored axis: the detector's shaft runs along its local X, the magnet's
--- along its local Z. Any single hand-picked rotation gets one of them right and lies
--- the others flat — the first pass hung a tier-1 magnet 9.7 studs deep, straight
--- back through the counter and out of the slat wall. HoldCFrame is the one piece of
--- per-model orientation this project already maintains, so the rack reads it instead
--- of inventing a second one — plus the per-track `present` tip (STALLS' `present`).
---
--- SCALED FROM THE TIER'S OWN SCALE, NOT FROM 1. `Model:ScaleTo` is ABSOLUTE — it
--- sets scale relative to the model as authored, discarding whatever the instance
--- carries. These templates are all pre-scaled (Config/ToolTiers' `scale` column; a
--- tier-1 magnet ships at 0.300), so `ScaleTo(f)` threw the tier's own size away and
--- came out 35% oversized. It has to be `GetScale() * f`.
---
--- AND `f` IS THE TIGHTEST OF FOUR LIMITS, measured in the STALL'S frame. Height is
--- the whole rail-to-floor drop (RACK_DROP_TOP - RACK_DROP_BASE) — that is the point
--- of the pass. Width keeps a tier off its neighbour (RACK_SLOT_WIDTH); depth keeps
--- its nose out of the browse aisle (RACK_SLOT_DEPTH). RACK_MAX_UPSCALE caps the
--- blow-up past the authored size so a small-authored model (a tier-1 magnet) does
--- not go chunky filling the drop — it hangs shorter instead, on a strap. Box
--- corners are projected onto the STALL'S local axes (not the world's — the stall is
--- rotated), so a long tool fills the drop and a stubby one stays shorter.
---
--- THEN STOOD ON THE DECK. HoldCFrame places a model's PIVOT, wherever the Handle
--- happens to sit — a detector's is 1.2 studs off its own box centre. Left alone,
--- every tier would hang at a different height. So the last step re-measures the
--- scaled box and slides the model straight down until its BASE is on RACK_DROP_BASE,
--- and across so its centre sits on `x` and on the shopfront line, whatever the art's
--- pivot is doing.
---
--- A RACK_HANG track skips all of that: no `hand`, posed from its own axes, fitted
--- to its tier's display height and hung from the top instead of stood on the deck.
---
--- How much bigger the rack's tool FX particles are than in a player's hands.
--- 2.5x made the old sparkle clouds read clearly from the counter but was "too
--- loud"; the quieter per-detector effects that replaced them want only a nudge.
local RACK_FX_SCALE = 1.5

local function hangTierModel(parent: Instance, origin: CFrame, hand: CFrame?, x: number, track: string, tier: number): number?
	local template = tierTemplate(track, tier)
	if template == nil then
		return nil
	end

	local clone = template:Clone()
	clone.Name = `T{tier}`
	-- The scale it is carried at, before the rack resizes it (see ToolFX below).
	local heldScale = clone:GetScale()

	-- Gag parts that only make sense in the hand — see RACK_HIDE_ON_DISPLAY.
	for _, name in RACK_HIDE_ON_DISPLAY do
		local extra = clone:FindFirstChild(name)
		if extra then
			extra:Destroy()
		end
	end

	-- Display furniture, not physics. An un-anchored clone of a tool built to be
	-- welded into a hand falls through the plaza the instant the world unfreezes,
	-- and a colliding one lets a player shove the whole rack off its rail.
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end

	clone.Parent = parent

	local hang = RACK_HANG[track]
	if hang then
		-- Model-frame basis whose up is "against the legs" and whose back is the
		-- face; its inverse carries legs to the stall's -Y and face to its +Z.
		local legs = hang.legsByName[Gear.tier(track, tier).name] or hang.legs
		local up = -legs
		local basis = CFrame.fromMatrix(Vector3.zero, up:Cross(hang.face), up, hang.face)
		clone:PivotTo(origin * Kit.ang(0, hang.yaw, 0) * basis:Inverse())
	else
		local hold = template:GetAttribute("HoldCFrame")
		if typeof(hold) ~= "CFrame" then
			hold = CFrame.new()
		end
		clone:PivotTo((hand :: CFrame) * hold)
	end

	-- A code-authored template is built for this call and has no parent; a library one
	-- lives in Assets/Tools and must survive. Parentage is the honest test for which is
	-- which, and this is the last line that reads `template`, so the throwaway can go
	-- rather than waiting on a collection pass. Eight tiers times three stalls times
	-- every rebuild is not free.
	if template.Parent == nil then
		template:Destroy()
	end

	-- The model's box IN THE STALL'S OWN FRAME: every BasePart's 8 corners taken into
	-- the stall's local axes, then min/max. Per-part rather than off `GetBoundingBox`
	-- because that returns a box aligned to the MODEL — after a HoldCFrame turn it is
	-- aligned to neither the stall nor the world, so its corners overstate the real
	-- extent, and this pass has to land the base ON the deck, not roughly near it.
	local function localBox(): (Vector3, Vector3)
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				local half = d.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p = origin:PointToObjectSpace(d.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
							lo, hi = lo:Min(p), hi:Max(p)
						end
					end
				end
			end
		end
		return lo, hi
	end

	local lo, hi = localBox()
	local e = hi - lo
	if math.min(e.X, e.Y, e.Z) > 0 then
		local f
		if hang then
			local t = (tier - 1) / math.max(Gear.maxTier(track) - 1, 1)
			local height = hang.height[1] + (hang.height[2] - hang.height[1]) * t
			f = math.min(height / e.Y, RACK_SLOT_WIDTH / e.X, RACK_SLOT_DEPTH / e.Z)
		else
			f = math.min(
				(RACK_DROP_TOP - RACK_DROP_BASE) / e.Y,
				RACK_SLOT_WIDTH / e.X,
				RACK_SLOT_DEPTH / e.Z,
				RACK_MAX_UPSCALE
			)
		end
		clone:ScaleTo(clone:GetScale() * f)
	end

	-- THE RARE RUNGS GLOW ON THE RAIL TOO, with the same ToolFX a player's hands
	-- get, so the rack sells the look you are buying. Applied AFTER the resize,
	-- with the particles grown by however much bigger than in-hand the model now
	-- is (never shrunk, so a magnet squeezed into its slot keeps a readable
	-- effect), then by RACK_FX_SCALE on top -- at in-hand size the sparkles were
	-- specks from the plaza. Lights are not scaled (see ToolFX.apply).
	ToolFX.apply(clone, track, tier, RACK_FX_SCALE * math.max(clone:GetScale() / heldScale, 1))

	-- Re-measure the scaled box and translate (keeping the orientation) so its base
	-- sits on the deck -- or, hung, its top sits `drop` under the mount -- and it is
	-- centred across the rack and on the shopfront line.
	lo, hi = localBox()
	local height = hi.Y - lo.Y
	local topY = if hang then RACK_DROP_TOP - hang.drop else RACK_DROP_BASE + height
	local haveCentre = (lo + hi) / 2
	local wantCentre = Vector3.new(x, topY - height / 2, SHOPFRONT_Z)
	clone:PivotTo(clone:GetPivot() + origin:VectorToWorldSpace(wantCentre - haveCentre))

	return topY
end

--- The price card over one hanging tier: its price, big, with the tier's name small
--- above it.
---
--- SIZED IN STUDS, NOT PIXELS, and that is the whole fix to the rack's old look. The
--- card used to be a fixed 130x46 px on screen at any distance, while the tiers under
--- it are only RACK_PITCH studs apart, so the moment you stood back far enough for
--- that gap to be under 130px the names ran into each other. A BillboardGui's Size in
--- SCALE is measured in studs, so these shrink with the rack as you walk away and a
--- card can never reach the next one: PRICE_CARD_WIDTH is under RACK_PITCH by design.
---
--- PRICE FIRST, on request, picked from a round of mockups: the thing a player scans a
--- rail for is what they can afford, so the price is the big line (LuckiestGuy, gold)
--- and the name the small one (FredokaOne) — both in the HUD's black cartoon outline.
---
--- THE NAME IS SPLIT ONTO TWO LINES HERE, NOT WRAPPED BY THE ENGINE. With a stud-sized
--- card the text has to be TextScaled, and TextScaled + TextWrapped sizes each label
--- to its own box: "Bent Coil" would come out twice the height of "Resonance Mapper"
--- beside it. Splitting long names by hand and growing the name box by one line
--- height per line keeps every line on the rail at the same height (see nameLines).
---
--- NAMED "Sign" WITH "Title" / "Subtitle" CHILDREN, matching Kit.billboard exactly.
--- The client rewrites the subtitle into the owned-check (StationController's rack
--- pass) and finds it by those names; a card that spelled them differently would be
--- invisible to it.
local PRICE_CARD_WIDTH = RACK_PITCH - 0.6 -- studs; the gap to the next card is the 0.6
local PRICE_LINE_HEIGHT = 0.72 -- studs; the price
local NAME_LINE_HEIGHT = 0.46 -- studs, per line of the name
local PRICE_CARD_LIFT = 0.35 -- studs from the mount's top face to the card's bottom edge
local PRICE_GOLD = "FFD84A" -- the cash badge's gold, so a price reads as the same money
-- A name longer than this goes onto two lines: about what FredokaOne fits across
-- PRICE_CARD_WIDTH at NAME_LINE_HEIGHT before TextScaled starts shrinking it. A long
-- name with no space to split at ("Electromagnet") stays one line and shrinks a little.
local NAME_ONE_LINE_MAX = 11

--- "$320,000", not "$320000": every other price in the game is grouped.
local function priceText(price: number): string
	if price <= 0 then
		return "FREE"
	end
	local grouped = tostring(math.floor(price))
	while true do
		local nextText, count = string.gsub(grouped, "^(%-?%d+)(%d%d%d)", "%1,%2")
		grouped = nextText
		if count == 0 then
			break
		end
	end
	return `${grouped}`
end

--- The name as one line, or two split at the space nearest the middle.
local function nameLines(name: string): (string, number)
	if #name <= NAME_ONE_LINE_MAX then
		return name, 1
	end
	local best: number? = nil
	for index = 1, #name do
		if string.sub(name, index, index) == " " then
			if best == nil or math.abs(index - #name / 2) < math.abs(best - #name / 2) then
				best = index
			end
		end
	end
	if best == nil then
		return name, 1
	end
	return string.sub(name, 1, best - 1) .. "\n" .. string.sub(name, best + 1), 2
end

local function buildPriceCard(mount: BasePart, name: string, price: number)
	local nameText, lines = nameLines(name)
	local nameHeight = lines * NAME_LINE_HEIGHT
	local height = nameHeight + PRICE_LINE_HEIGHT

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromScale(PRICE_CARD_WIDTH, height)
	-- The card's CENTRE, so its bottom edge sits PRICE_CARD_LIFT over the mount's top.
	gui.StudsOffsetWorldSpace = Vector3.new(0, mount.Size.Y / 2 + PRICE_CARD_LIFT + height / 2, 0)
	gui.AlwaysOnTop = true
	-- Longer than the old 28 now that a far card is simply small rather than a smear:
	-- a price you can read from the aisle is worth drawing.
	gui.MaxDistance = 44
	-- Same reason Kit.billboard sets this: the stall signs sit near lamps and a sign
	-- should not wash toward white along with whatever it is bolted to.
	gui.LightInfluence = 0
	gui.Parent = mount

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, nameHeight / height)
	title.BackgroundTransparency = 1
	title.Font = Kit.FONT
	title.Text = nameText
	title.TextScaled = true
	title.TextWrapped = false
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.TextColor3 = Color3.fromHex(C.labelText)
	title.TextStrokeTransparency = 1
	title.Parent = gui
	Kit.textOutline(title, 1.5)

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Position = UDim2.fromScale(0, nameHeight / height)
	sub.Size = UDim2.fromScale(1, PRICE_LINE_HEIGHT / height)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.LuckiestGuy
	sub.TextScaled = true
	sub.Text = priceText(price)
	sub.TextColor3 = Color3.fromHex(PRICE_GOLD)
	sub.TextStrokeTransparency = 1
	Kit.textOutline(sub, 2)

	-- WHAT THIS LABEL SAYS WHEN NOBODY OWNS THE TIER, stamped onto the label itself.
	-- The client overwrites this subtitle with the green owned-check for whoever is
	-- standing here (StationController's rack pass) and has to be able to put the
	-- price back afterwards. Stamping the as-built values here means it never has to
	-- know the price OR the colour to do that -- the same RestText/RestColor trick
	-- LiquidService uses to restore the wash pad sign after announcing a roll.
	sub:SetAttribute("RestText", sub.Text)
	sub:SetAttribute("RestColor", sub.TextColor3)
	sub.Parent = gui
end

--- What the rack builders need off a STALLS entry: the track, its accent, and the
--- per-track hang angle. The full STALLS row carries more (at, label, …); this
--- is the slice `buildTierRack` and `buildRackHook` actually read.
type RackSpec = { track: string, color: string, present: { yaw: number, pitch: number }? }

--- One hook on the rail: the mount block that carries the sale, the tier's model
--- standing under it (or a painted stand-in), a slim strap hanging it off the rail,
--- and the price card over it.
---
--- THE MOUNT IS BUILT WHETHER OR NOT THE ART IS. A missing template costs the stall
--- its silhouette, never its ability to sell — the fallback is a plain block in the
--- shop's accent, and the prompt, the attributes and the billboard are identical
--- either way. World.verify() asserts every priced track is buyable somewhere, and
--- that assertion must not depend on which place file this ran in.
local function buildRackHook(parent: Instance, origin: CFrame, spec: RackSpec, tier: number, x: number)
	local def = Gear.tier(spec.track, tier)

	local mount = build(parent, origin, {
		name = `Mount{tier}`,
		pos = { x, RACK_RAIL_Y - 0.5, SHOPFRONT_Z },
		size = { 1.1, 1.0, 1.1 },
		color = C.steelDark,
		material = "Metal",
		canCollide = false,
		-- Kit.build tags anything carrying SellsTrack with Kit.UPGRADE_TAG as it
		-- creates it, which is what ShopService scans to wire the prompt and what
		-- World.verify() asserts is present. Nothing to add here.
		attributes = { SellsTrack = spec.track, SellsTier = tier },
	})

	-- THE VIRTUAL HAND: a holder facing the customer, at this track's `present` tip
	-- (STALLS' `present` and the RACK_DROP_* header). Only the rotation matters —
	-- hangTierModel stands the model on the deck afterwards. Yaw about the stall's Y,
	-- then pitch about the yawed X, so the whole row tips forward together.
	-- A RACK_HANG track (the magnets) has no `present` and poses itself.
	local present = spec.present
	local hand = if present then origin * Kit.ang(0, present.yaw, 0) * Kit.ang(present.pitch, 0, 0) else nil
	local topY = hangTierModel(parent, origin, hand, x, spec.track, tier)

	if topY == nil then
		local blockH = RACK_DROP_TOP - RACK_DROP_BASE
		build(parent, origin, {
			name = `T{tier}Stand`,
			pos = { x, RACK_DROP_BASE + blockH / 2, SHOPFRONT_Z },
			size = { 1.4, blockH, 1.4 },
			color = spec.color,
			material = "SmoothPlastic",
			canCollide = false,
		})
		topY = RACK_DROP_TOP
	end

	-- The strap that hangs a shorter tier off the mount so it reads as hung, not
	-- floating. Sizes itself to the gap: nothing for a detector that already reaches
	-- the mount, a visible drop for a stubby hose.
	local gap = RACK_DROP_TOP - topY
	if gap > 0.4 then
		build(parent, origin, {
			name = `Hanger{tier}`,
			pos = { x, topY + gap / 2, SHOPFRONT_Z },
			size = { 0.16, gap, 0.16 },
			color = C.steelDark,
			material = "Metal",
			canCollide = false,
		})
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Upgrade"
	-- E OPENS THIS TIER'S SHOP CARD; IT DOES NOT BUY. The card (StationController's
	-- rack card) carries the stats, the picture and the Buy / Equip button, and that
	-- button is the only thing that spends money, through the same StationAction the
	-- storefront's cards use. So the prompt says the same thing to everyone, owned or
	-- not, and needs no hold: nothing irreversible happens on it.
	prompt.ActionText = "View"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = MOUNT_REACH
	-- The hanging gear is non-colliding and set CanQuery = false, but the mount sits
	-- high and a customer's sightline to it grazes the rail, so keep the prompt
	-- firing without line of sight.
	prompt.RequiresLineOfSight = false
	prompt.Parent = mount

	-- Name and price. A client turns this into the green owned-check when the player
	-- is standing here and the server says they already have this tier — see
	-- StationController's rack pass. Built with the price showing because that is
	-- what it says to everyone who has not bought it, which is most people most of
	-- the time.
	buildPriceCard(mount, def.name, def.price)
end

--- Every tier of the track, cheapest on the left, standing on the deck below the rail.
---
--- `origin` IS THE WING'S OWN CENTRE, not the stall's — the caller passes
--- `stallOrigin * CFrame.new(rackX(track), 0, 0)` the same way buildOutfitter shifts
--- a counterOrigin, so everything below stays written as a symmetric offset from zero
--- and this function never has to know where in the store it was hung.
local function buildTierRack(parent: Instance, origin: CFrame, spec: RackSpec)
	local span = rackSpan(spec.track)
	local count = Gear.maxTier(spec.track)

	-- The rail the tiers hang from, and a full-height post at each end carrying it
	-- down to the deck — the counter that used to hold the rail up is gone.
	build(parent, origin, {
		name = "RackRail",
		pos = { 0, RACK_RAIL_Y, SHOPFRONT_Z },
		size = { span + 3, 0.5, 0.5 },
		color = C.steel,
		material = "Metal",
		canCollide = false,
	})
	for _, side in { -1, 1 } do
		build(parent, origin, {
			name = "RackPost",
			pos = { side * (span / 2 + 1.5), (RACK_RAIL_Y + RACK_DROP_BASE) / 2, SHOPFRONT_Z },
			size = { 0.5, RACK_RAIL_Y - RACK_DROP_BASE, 0.5 },
			color = C.steel,
			material = "Metal",
			canCollide = false,
		})
	end

	for tier = 1, count do
		buildRackHook(parent, origin, spec, tier, -span / 2 + (tier - 1) * RACK_PITCH)
	end
end

-- ── The plaza stalls ────────────────────────────────────────────────────────────

--- One classic-Roblox gear store, stripped to the structure: studded grey posts
--- and rear slats, an open counter, and a steel-plate roof + sign both in
--- the stall's own accent colour. The roof, the sign text, the floor marker
--- and the counter's trim cap — all `spec.color` — are the per-shop identity now
--- that the shopkeeper and the identity prop are gone.
local function buildStall(parent: Instance, spec: { track: string, at: { number }, faceYaw: number?, color: string, label: string, present: { yaw: number, pitch: number }? })
	local m = Instance.new("Model")
	m.Name = `{spec.track}Shop`

	-- Position AND facing in one CFrame: at this stall's `at`, turned to face
	-- `spec.faceYaw` or (by default) back at PLAZA_MID — see `facingDirFor`. Y
	-- comes from Hub.PLAZA.topY + Hub.PLAZA_LIFT (the raised plaza floor). Every
	-- part below is a LOCAL offset from this, so this one line carries the whole
	-- stall's placement.
	local atX, atZ = stallAt(spec)
	local origin = facingOrigin(atX, atZ, spec.faceYaw)

	-- EVERY DIMENSION BELOW KEYS OFF THIS, and it is a function of how many tiers the
	-- track has (see `stallWidth`). A Detector stall is wider than a Magnet stall
	-- because a Detector ladder is longer, and that is the honest thing for the
	-- building to say.
	local width = stallWidth(spec.track)

	-- A thin blue-grey floor is visible through the open sides in the reference.
	-- It is non-colliding and lifted just enough to avoid z-fighting with the plaza.
	build(m, origin, {
		name = "StallFloor",
		pos = { 0, 0.05, -4 },
		size = { width, 0.1, 12 },
		color = C.steelDark,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})

	-- Taller than the original kiosk, too — the reference stall reads as a proper
	-- standing structure, not a picnic table. See `buildStorefrontPosts`.
	buildStorefrontPosts(m, origin, width)
	buildSlatWall(m, origin, width)

	-- The two halves of the shopfront, on one line, with STAND_RACK_GAP of open air
	-- between them — see "The stand, and the wing beside it".
	local sx, rx = standX(spec.track), rackX(spec.track)

	-- THE STAND. This is the part the whole file exists to place correctly: the desk
	-- you walk up to for the card panel, and the shop's own StationId. Eight studs
	-- wide and parked at the left end of the store instead of the 37-stud bench that
	-- used to run the whole front, because the ladder no longer sits on top of it.
	-- material = "Plastic" here (not buildCounter's own "Wood" default) so the
	-- studded look stays consistent across the whole stall -- the Outfitter's
	-- call to the same function passes no material and keeps its original Wood.
	buildCounter(m, origin * CFrame.new(sx, 0, 0), {
		name = "Stand",
		color = C.steel,
		width = STAND_WIDTH,
		depth = 2.5,
		z = SHOPFRONT_Z,
		stationKind = "shop",
		stationId = spec.track,
		radius = STAND_RADIUS,
		promptText = spec.label,
		material = "Plastic",
		studded = true,
	})

	-- THE SIGN ANCHOR sits at local x=0 — dead centre of the WHOLE stall — rather
	-- than on the stand, which is parked off to one side (see `standX`). Hanging
	-- the sign off the stand read as off-centre against the shop as a whole; an
	-- invisible, non-colliding anchor lets the sign float over the stall's own
	-- midpoint regardless of where the stand or rack sit within it.
	local signAnchor = build(m, origin, {
		name = "SignAnchor",
		pos = { 0, 1.1, SHOPFRONT_Z },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
	})
	signAnchor.CanQuery = false
	buildStoreBillboard(signAnchor, spec.label, spec.color)

	-- THE WING'S STATION CIRCLE, carrying the same StationId at its own radius, on an
	-- invisible anchor now that the shelf under the rack is gone. Not a spare copy of
	-- the stand: the offer that draws the rack's owned-ticks only exists while
	-- StationService has you at this shop, so without a circle out here every tick
	-- blanks the instant you walk over to look at the tools. Two modest circles beat
	-- one 44-stud one that would reach back into the courtyard — the header block on
	-- the stand has the full argument and the numbers. CanQuery off so a transparent
	-- box does not sit in front of the camera or a stray ray (the WashStand lesson).
	local rackZone = build(m, origin * CFrame.new(rx, 0, 0), {
		name = "RackZone",
		pos = { 0, 3, SHOPFRONT_Z },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		attributes = {
			StationKind = "shop",
			StationId = spec.track,
			Radius = rackFootprintWidth(spec.track) / 2 + 6,
		},
	})
	rackZone.CanQuery = false
	rackZone.CanTouch = false

	-- The tier rack itself, standing on the deck — see "The hanging tier rack".
	buildTierRack(m, origin * CFrame.new(rx, 0, 0), spec)

	buildPlateRoof(m, origin, spec.color, width)

	-- The trade's own props, behind the shopfront and on the roof (build/ShopThemes).
	ShopThemes.dressStall(m, origin, spec.track, width, sx)

	-- TWO FLOOR MARKERS, ONE PER HALF, because there are two different things to do
	-- here now and the ground should say which is which. The box in front of the stand
	-- outlines where you stand for the panel; the long strip in front of the wing marks
	-- the ground you walk ALONG to browse the tools. A stud of gap between them, in the
	-- shop's own colour — never green, see the header.
	buildFloorMarker(m, origin, sx, 3.4, STAND_WIDTH + 3, 5, spec.color)
	buildFloorMarker(m, origin, rx, 3.4, rackFootprintWidth(spec.track), 5, spec.color)

	m.Parent = parent
	return m
end

--- A shop's footprint on the plaza, as an oriented rectangle. `backZ`/`frontZ` are
--- the extremes of everything the builder lays down, in the shop's own local z.
local function shopFootprint(x: number, z: number, width: number, backZ: number, frontZ: number, faceYaw: number?): Kit.OrientedRect
	local dirX, dirZ = facingDirFor(x, z, faceYaw)
	local mid = (backZ + frontZ) / 2
	return {
		cx = x + dirX * mid,
		cz = z + dirZ * mid,
		halfWidth = width / 2,
		halfDepth = (frontZ - backZ) / 2,
		-- Kit's yaw convention maps local +Z to world (sin, cos) — see
		-- orientedRectCorners — and a shop's local +Z is exactly `dir`.
		yawDeg = math.deg(math.atan2(dirX, dirZ)),
	}
end

--- No shop on the plaza may sit inside another one.
---
--- THIS IS HERE BECAUSE THE STALL WIDTHS ARE NOW DERIVED, AND `at` IS NOW FREE. While
--- every stall was 15 studs wide at a hand-picked position, "do they overlap" was
--- answered once by looking at the numbers and stayed answered. It is not answered
--- once any more: adding a tier to a track in Config/Gear widens that track's shop,
--- and moving a stall's `at` (by hand, or via the ring values it started at) can walk
--- it into a neighbour. A stall's `at` or OUTFITTER.at are what then have to move,
--- and this is what says so — at the rebuild that broke it, rather than in a
--- screenshot three weeks later.
---
--- Kit.orientedRectsOverlap, not an axis-aligned box: two of the three stalls sit at
--- +/-120 degrees, where a bounding box overstates the footprint badly enough to
--- report collisions that are not there.
local function assertNoShopOverlap()
	local rects: { { name: string, rect: Kit.OrientedRect } } = {}

	for _, spec in STALLS do
		local x, z = stallAt(spec)
		-- -11.25 is the canopy's own back edge (centre -4, depth 14.5) and +5.9 the
		-- floor marker's outer edge (centre 3.4, depth 5) — the two extremes of
		-- everything buildStall lays down.
		table.insert(rects, {
			name = `{spec.track} stall`,
			rect = shopFootprint(x, z, stallWidth(spec.track), -11.25, 5.9, spec.faceYaw),
		})
	end

	local outfitterWidth = OUTFITTER.pitch * (#OUTFITTER.counters - 1) + 20
	table.insert(rects, {
		name = "Outfitter",
		rect = shopFootprint(OUTFITTER.at[1], OUTFITTER.at[2], outfitterWidth, -8, 8, OUTFITTER.faceYaw),
	})

	for i = 1, #rects do
		for j = i + 1, #rects do
			assert(
				not Kit.orientedRectsOverlap(rects[i].rect, rects[j].rect),
				`{rects[i].name} overlaps {rects[j].name} — move one stall's \`at\` in STALLS or OUTFITTER.at`
			)
		end
	end
end

-- ── The outfitter ─────────────────────────────────────────────────────────────

--- The outfitter: the SAME shell the plaza stalls build — StallFloor, studded
--- posts, an open slatted back, a steel-plate roof in the shop's own accent — just
--- sized to its own counter row instead of one stand. The Aura would otherwise be priced but
--- unbuyable, and hazard gear that actually reduces incoming damage earns more than a
--- picnic table. Sits right next to
--- DetectorShop in the north row (see OUTFITTER.at); `faceYaw` points its front
--- south, matching that row-mate. Each counter carries its own stall-style sign naming
--- the track ("Aura Shop") — there is no separate building-level
--- sign, the same as a plaza stall has no sign beyond its one stand's.
---
--- WAS THREE COUNTERS, THEN TWO, NOW ONE — Boots retired, then the Satchel. `span`
--- and `width` below both read `#OUTFITTER.counters`, so the bench shrank on its own
--- and the canopy, floor and posts followed it. The `at` anchor did not move: the
--- building is centred on that point, so it narrowed symmetrically and its row-mate
--- DetectorShop kept its gap.
---
--- USED TO BE A REAL WALLED BUILDING WITH A GABLE ROOF, because three counters
--- side by side read as too wide for one stall-sized canopy at the time. Once
--- the stalls themselves grew to 31-44 studs wide (see `stallWidth`) that
--- stopped being true — the Outfitter's ~46-stud span is no wider than a big
--- stall already is — so the bespoke building came out in favour of matching
--- the stalls exactly, and `buildGableRoof` (walls + roof, unique to that old
--- shape) went with it.
local function buildOutfitter(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Outfitter"

	local origin = facingOrigin(OUTFITTER.at[1], OUTFITTER.at[2], OUTFITTER.faceYaw)
	local span = OUTFITTER.pitch * (#OUTFITTER.counters - 1)
	local width = span + 20

	-- The plaza stalls' own shell, at this building's width — see buildStall.
	build(m, origin, {
		name = "StallFloor",
		pos = { 0, 0.05, -4 },
		size = { width, 0.1, 12 },
		color = C.steelDark,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})
	buildStorefrontPosts(m, origin, width)
	buildSlatWall(m, origin, width)
	buildPlateRoof(m, origin, C.shopOutfitter, width)

	-- One floor marker for the whole counter row — there is no second, rack-side
	-- marker the way a plaza stall has, because there is no rack here.
	buildFloorMarker(m, origin, 0, 3.4, width - 6, 5, C.shopOutfitter)

	local counterX: { [string]: number } = {}
	for index, counter in OUTFITTER.counters do
		local x = -span / 2 + (index - 1) * OUTFITTER.pitch
		counterX[counter.track] = x
		local counterOrigin = origin * CFrame.new(x, 0, 0)

		local desk = buildCounter(m, counterOrigin, {
			color = C.shopOutfitter,
			width = 4,
			depth = 2.4,
			z = SHOPFRONT_Z,
			stationKind = "shop",
			stationId = counter.track,
			-- Tighter than the plaza stalls: the bench was built for several counters
			-- sharing one building, where standing at one has to be unambiguous.
			radius = 6,
			promptText = counter.label,
			-- Scaled to that tighter radius the same way the stand's is to its own,
			-- and for the same reason. It also has to stay under the 13-stud counter
			-- pitch, or the E in front of you would belong to the desk next door.
			promptReach = 5,
			-- Plastic + studded, matching the plaza stands now instead of the
			-- Outfitter's old plain-Wood look — see buildCounter's own doc.
			material = "Plastic",
			studded = true,
		})
		buildStoreBillboard(desk, counter.label, C.shopOutfitter)
	end

	-- The aura shop: a mannequin wearing a live aura behind the Aura desk, a sample
	-- tube per tier either side, and the roof atom (build/ShopThemes).
	ShopThemes.dressOutfitter(m, origin, counterX.Aura)

	m.Parent = parent
	return m
end

-- ── The empty stall ───────────────────────────────────────────────────────────

--- A plaza stall's SHELL with nothing for sale: the same StallFloor, studded posts,
--- slatted back and steel-plate roof `buildStall` puts up, a plain counter across the
--- front with the accent trim, and a sign over the middle -- and deliberately NO
--- StationKind, StationId, RackZone or prompt anywhere on it. An empty stall must not
--- open a shop panel for a track it does not sell, and a StationKind here would also
--- count toward World.verify()'s station census.
---
--- EXPORTED FOR build/CampSite, whose stalls go up before the gear they will sell
--- exists. `origin` is the stall's own frame on the floor it stands on, local +Z its
--- customer side -- the same frame `facingOrigin` hands `buildStall`. Returns the
--- model, already parented. The footprint is `width` across and local z -11.25 (the
--- canopy's back edge) to +2.75 (the front posts), matching `assertNoShopOverlap`.
--- The pill sign, for the Trader kiosk in build/BaseCamp. `offsetY` is studs above `adornee`.
Shops.buildSign = buildStoreBillboard

function Shops.buildStallShell(parent: Instance, origin: CFrame, width: number, accent: string, label: string): Model
	local m = Instance.new("Model")
	m.Name = "EmptyStall"

	build(m, origin, {
		name = "StallFloor",
		pos = { 0, 0.05, -4 },
		size = { width, 0.1, 12 },
		color = C.steelDark,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})
	buildStorefrontPosts(m, origin, width)
	buildSlatWall(m, origin, width)

	-- The counter across the whole front, the plaza stalls' height and trim. No
	-- `stationKind` and no `promptText`, so buildCounter adds neither attributes nor
	-- a prompt (see its own doc).
	local counter = buildCounter(m, origin, {
		color = accent,
		width = width - 4,
		depth = 2.5,
		z = SHOPFRONT_Z,
		material = "Plastic",
		studded = true,
	})
	buildStoreBillboard(counter, label, accent)
	buildPlateRoof(m, origin, accent, width)

	m.Parent = parent
	return m
end

local function createShops(): Model
	local shops = Instance.new("Model")
	shops.Name = Shops.MODEL_NAME
	Kit.stamp(shops, BUILDER_SOURCE, BUILDER_VERSION)

	-- Before a single part is laid: the widths are derived and the `at` positions
	-- are freeform now, so "nothing overlaps" is a claim this file has to prove
	-- every time, not once.
	assertNoShopOverlap()

	for _, spec in STALLS do
		buildStall(shops, spec)
	end
	buildOutfitter(shops)

	-- SELF-CONSISTENCY, NOT GLOBAL COVERAGE, and that distinction is new. This used to
	-- assert every entry in Gear.TRACKS had a counter here — correct while this file
	-- was the only thing in the world that sold anything, and wrong the moment Luck
	-- moved to a button at each base (build/Plots.buildLuckButton). It failed the
	-- next rebuild, which is exactly what a good assert does; it was just asking a
	-- question this file can no longer answer.
	--
	-- So it now checks only what this file DECLARES: every track named in STALLS or
	-- OUTFITTER.counters actually got a counter built with that StationId. That
	-- catches the real local failure (a typo'd track name, a counter that silently
	-- did not build) without claiming to know about selling points it did not make.
	--
	-- "Every priced track is buyable SOMEWHERE" is still checked, once, in
	-- World.verify() — which sees the whole world and knows about both a `shop`
	-- counter and a `SellsTrack` prompt.
	local covered: { [string]: boolean } = {}
	for _, part in shops:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("StationKind") == "shop" then
			covered[part:GetAttribute("StationId") :: string] = true
		end
	end

	local declared: { string } = {}
	for _, spec in STALLS do
		table.insert(declared, spec.track)
	end
	for _, counter in OUTFITTER.counters do
		table.insert(declared, counter.track)
	end
	for _, track in declared do
		assert(covered[track], `{track} is listed in this file but no counter was built for it`)
	end

	return shops
end

function Shops.build(parent: Instance?): Model
	local shops = createShops()
	shops.Parent = parent or Workspace
	return shops
end

function Shops.rebuild(parent: Instance?): Model
	local shops = Kit.swap(Shops.MODEL_NAME, createShops, parent) :: Model
	print(`[build] Shops rebuilt — {#shops:GetChildren()} storefronts, {#STALLS} stalls + {#OUTFITTER.counters} outfitter counters`)
	return shops
end

return Shops
