--!strict
--[[
	Shops.luau — where cash turns back into capability.

	    require(game.ServerScriptService.Server.build.Shops).rebuild()

	THREE STALLS ON THE PLAZA, one per tool you hold: the detector that finds it, the
	magnet that pulls it, and the cleaner that scrubs it. Each is a different colour
	and keeps that colour forever. A young player learns "the coral one is the
	detector shop" once and then navigates by colour rather than by reading signs,
	which is the cheapest legibility win available anywhere in this map.

	PLUS AN OUTFITTER, a real building, and this one is not decoration.
	Gear.TRACKS has seven entries. Three stalls covers Detector, Magnet and Cleaner and
	leaves Suit, Boots and Satchel priced but unbuyable — and the SUIT is the gate
	on every stage in the game. Without a way to buy one, Stage 2 stops being "you can go
	there and here is what it costs" and becomes exactly the locked door PLAN §3.5
	promises never to build. It costs nothing to add because the shop system
	is track-generic: it is four more counters with four more StationIds.

	THE SPLIT BETWEEN THE STALLS AND THIS BENCH IS "DO YOU HOLD IT". The three stalls
	sell the three things ToolService can put in your hands; the Outfitter sells the
	three you wear. Luck briefly sat here too, as a fourth desk selling something you
	do not physically have at all — since moved out to its own button (see the LUCK
	IS NOT HERE note below).

	EVERY TIER OF A TRACK HANGS ON A RAIL BESIDE THE STAND, AND YOU BUY THE ONE YOU
	ARE STANDING AT. The ladder used to be visible only as a list: walk into a radius,
	a scrolling panel of cards opens, pick a row. It is a physical object now — eight
	detectors in a row, cheapest first, each hung from the rail by its own handle with
	its price on a card above it and its own ProximityPrompt — so browsing is WALKING,
	and buying is pressing E in front of the one you want. The models are the real
	ones: Assets/Tools/<Track>/T<n>, exactly what ToolService clones into your hands.

	A STOREFRONT IS A STAND PLUS A WING, AND THAT SPLIT IS THIS PASS. The rack first
	shipped hanging over the counter, which forced the counter to be as long as the
	ladder — a 37-stud desk with one interaction anywhere on it, reading as one
	undifferentiated bench. It is two things now, on one shopfront line: a short STAND
	at the left end (the desk, its sign, its outline on the ground) and, past a gap you
	can see daylight through, the WING — a shelf with the whole ladder over it. So
	"where is the menu" has an answer you can see from across the plaza, instead of one
	you learn by walking into an invisible circle. See "The stand, and the wing beside
	it" for the constants and for why BOTH halves carry the station attributes.

	THE PANEL DID NOT GO AWAY. The stand keeps its StationKind and the card panel
	still opens — that is where the stat blocks live. The rack is the fast path ("I
	know which one I want"), the panel the slow one ("which one SHOULD I want"). Two
	doors on the same purchase; ShopService.buyTier is behind both of them and
	validates identically either way.

	A STALL IS AS WIDE AS ITS TRACK IS LONG. `stallWidth` derives it from
	Gear.maxTier, so the Detector stall (8 tiers) is wider than the Magnet stall (6),
	and adding a tier in Config/Gear widens that one shop with nothing else to edit.
	Posts, slats, shelf, canopy stripe count and both floor markers all key off that
	one number. What it cost: the ring the stalls stand on had to grow from radius 20
	to 32, and the Outfitter had to move from x=-30 to x=-44 to stay clear of the two
	western stalls' backs. Splitting the stand off the rack cost another six studs of
	width on top of that (44.2 / 40.6 / 37.0 now) and moved nothing else — the fronts
	still clear each other by ~21 studs and the Outfitter by ~13.
	`assertNoShopOverlap` proves that arrangement at every rebuild rather than
	trusting this paragraph.

	THE LOOK — the supplied classic-Roblox Gear Store reference, stripped to the
	structure. Each tool stall has studded posts, a slatted rear wall, an open
	counter with a steel cap, a shallow striped canopy and matching valance IN THE
	STALL'S OWN COLOUR (coral / teal / purple against white, no longer the one
	shared awning red), and a floating two-line sign that NAMES WHAT THE STALL
	SELLS (DETECTORS / MAGNETS / CLEANERS) in that same accent, with the tagline
	under it. The Outfitter remains the larger peaked-roof building — now tucked in
	behind the Detector and Cleaner stalls on the west, and open front and back as
	a walk-through — its three counters each billboarded the same way (SUITS /
	BOOTS / SATCHELS).

	THE DECORATION IS GONE, AND THAT WAS A DELIBERATE STRIP. Earlier passes stood a
	blocky shopkeeper behind each counter, a big silhouette prop of the thing sold
	(a detector, a horseshoe magnet, a bucket-and-brush, a hazmat suit…) beside it,
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
	once on the wing's shelf at a radius derived from the ladder's own length — because
	the client's owned-ticks need the offer live at both ends of the storefront and a
	single circle covering both would reach back into the courtyard. Same kind, same
	StationId, and `StationService.at` takes the nearest, so there is exactly one
	answer to "which shop am I at" anywhere on the front. The Outfitter's counters keep
	their tight 6 and stay one part each.

	    SellsTrack = "Detector"   -- this hook sells a rung of this track
	    SellsTier  = 5            -- which rung, indexing Config/Gear directly

	Those two are the rack's own contract, and they sit on the small steel MOUNT
	block, never on a part of the display model — the model is a clone of a place
	asset this file does not own and cannot promise the shape of, while the mount is
	built here and exists even when the art does not. Kit.build tags anything with a
	SellsTrack into Kit.UPGRADE_TAG, which is what ShopService scans to wire the
	prompt and what World.verify() asserts is present.

	THE THREE STALLS SIT IN A TRIANGLE FACING THE MIDDLE. `PLAZA_MID` (x=17.5, z=0)
	is that middle — the plaza midpoint, Hub's grey central spine centreline, the
	camp datum (Hub.CAMP_ORIGIN) and the blackout-respawn anchor, all the same
	point. Each stall stands `STALL_RING_RADIUS` studs out from it at a 120-degree
	spacing and is turned so its own front — the counter side, local +Z — points
	back at PLAZA_MID (`facingOrigin` does the turn). A player standing on the
	respawn anchor is inside the triangle with all three counters facing them; the
	gap between the two western stalls is the way in, aimed at the pad ring the
	players arrive from.

	THAT RING IS 32 STUDS NOW, NOT 20, AND THE COURTYARD IS THE REASON — not a
	collision. Nothing overlaps at radius 20; `assertNoShopOverlap` passes there.
	But three stalls of 38 / 35 / 31 studs at that radius eat ~250 of the 360 degrees
	around the middle, which leaves three 12-stud slots to walk through and a 33-stud
	yard fenced shopfront-to-shopfront. At 32 the same three fronts take ~173 degrees,
	the gaps open to ~62 each, and the middle is a 57-stud square you can cross.

	THE OUTFITTER TUCKS IN BEHIND THE DETECTOR AND CLEANER STALLS, ON THE WEST. It
	used to sit across a centre aisle from a straight row of stalls (row at z=22,
	Outfitter at z=-22), then went through a run of holding spots — z=-55, the
	south edge, the south-east arc, x=-30. Now it sits at (-44, 0) on the grey
	central pad, due west of PLAZA_MID and set well BEHIND the two stalls on that
	side (Detector NW, Cleaner SW) — out on the ground the west pad widening opened
	up (Hub.PAD_WEST_EXTEND), off the way in rather than straddling it, ~16 studs
	clear of the stalls' outer corners. It moved the last 14 studs west because the
	stalls grew: this building's 46-stud span runs north-south (it faces east), so it
	sits broadside to those two backs, and at x=-30 the widened Detector stall came
	within 3.6 studs of it — clear, and not a gap anyone walks down. On the z=0 centreline it faces due east, so
	`facingOrigin` leaves it square, no turn.

	AND IT IS OPEN FRONT AND BACK — A WALK-THROUGH, NOT A DEAD END. Only the two
	side walls are solid now; both gable ends (the +Z centre-facing side and the -Z
	outer side) are open. The three counters sit clear of the ~9-stud gaps between
	them, so the building can be walked straight through rather than being a room
	with a back wall — the +Z end is the counter approach from the plaza, the -Z
	end opens onto the west apron behind.

	`facingOrigin` IS THE ONLY PLACEMENT PRIMITIVE. Both builders lay every part as
	a local offset from the CFrame it returns, so that one CFrame carries a shop's
	whole position AND facing. It reads Hub.PLAZA.topY for the ground plane (the
	plaza is at Stages.SURFACE_Y, not Y=0). This file still reads nothing from
	Plots.luau: Plots requires Hub, Hub requires only Kit, and Shops stays a pure
	statement of positions. Plots.luau's SHOP_CLUSTER_EAST_REACH is already marked
	historical there and stays a conservative bound, not a live measurement of
	anything here.

	THE EAST REACH IS WORTH RE-STATING SINCE THE RING GREW. The Magnet stall took the
	east vertex out from x=37.5 to x=49.5, and its canopy's back edge now reaches
	~x=61 — the eastmost thing this file builds. Stage 1's west edge is x=100 and the
	plot ring's centre is x=32 at radius 180, so there is nothing within 39 studs of
	it in that direction. SHOP_CLUSTER_EAST_REACH (53, measured from PLAZA.maxX)
	remains what its own comment says it is: a frozen constant that keeps the pad ring
	where it is, not a live measurement of this file.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

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
local BUILDER_VERSION = 23

local C, R = Kit.C, Kit.R
local build, billboard = Kit.build, Kit.billboard

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

--- How far each stall vertex sits from PLAZA_MID. WAS 20, and it had to grow with
--- the stalls: a stall is now as wide as its track is long (see `stallWidth`), which
--- took the three of them to 38 / 35 / 31 studs.
---
--- IT IS THE COURTYARD, NOT A COLLISION, THAT SETS THIS NUMBER. Nothing actually
--- overlaps at radius 20 — `assertNoShopOverlap` passes there — but three fronts
--- that wide eat ~250 of the 360 degrees around the middle, leaving three 12-stud
--- slots and a 33-stud yard walled shopfront-to-shopfront. Passable, and a pit. At
--- 32 the same three fronts take ~173 degrees, the gaps open to ~62 degrees each and
--- the middle is a 57-stud square with three real ways into it.
---
--- The assert is still the thing that catches an actual overlap, and this is still
--- the first number to move when it fires.
local STALL_RING_RADIUS = 32

--- The three plaza stalls, one at each vertex of an equilateral triangle centred on
--- PLAZA_MID, each turned by `facingOrigin` so its counter side (local +Z) points
--- back at PLAZA_MID. `bearing` is degrees CCW from due east, so `at` = PLAZA_MID +
--- STALL_RING_RADIUS * (cos, sin) — the same three vertices the old hardcoded `at`
--- pairs named (0 / 120 / -120 reproduce (1,0), (-0.5,+0.866), (-0.5,-0.866)), now
--- derived so the ring radius is a single number to move. Magnet takes the east
--- vertex; Detector (NW) and Cleaner (SW) the two western ones, so the gap a player
--- walks in through faces the pad ring they arrive from.
local STALLS = {
	{ track = "Detector", bearing = 120, color = C.shopDetector, label = "DETECTORS", tagline = "find it deeper" },
	{ track = "Magnet", bearing = 0, color = C.shopMagnet, label = "MAGNETS", tagline = "pull it harder" },
	{ track = "Cleaner", bearing = -120, color = C.shopCleaner, label = "CLEANERS", tagline = "scrub it cleaner" },
}

-- ── The rack ─────────────────────────────────────────────────────────────────
--
-- EVERY TIER OF THE TRACK HANGS ON A RAIL OVER THE WING'S SHELF, beside the stand,
-- and you buy the one you are standing in front of. That is the whole feature: the
-- shop panel used to be the only way to see what a track sold, so a player had to
-- walk into a radius, read a scrolling list of cards and pick a row. Now the ladder
-- is a physical object — eight detectors in a row, cheapest nearest the stand, each
-- with its own price over it and its own ProximityPrompt — and walking the wing IS
-- browsing it.
--
-- THE PANEL IS STILL THERE. This does not replace it; the stand keeps its
-- StationKind and the card panel still opens (that is where the stat blocks live).
-- The rack is the fast path for "I know which one I want", the panel the slow path
-- for "which one SHOULD I want".
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
local RACK_MODEL_SIZE = 2.9 -- longest axis of a hanging tier, after scaling
local RACK_SLOT_WIDTH = RACK_PITCH - 0.6 -- across the rack: never touch the next tier
local RACK_SLOT_DEPTH = 2.4 -- into the stall: never poke through the shelf

--- Which way the virtual holder faces. 180 is square-on to the customer — a
--- character's LookVector is its own -Z and the stall's +Z is the plaza, so 180 turns
--- the holder to face out. That reads BADLY: a tool held out points along its
--- holder's forward axis, so square-on presents every tool nose-first, and
--- RACK_SLOT_DEPTH then binds the scale for two of the three tracks. A tier-1 magnet
--- came out a 1-stud-tall disc pointing at your face.
---
--- 225 is that turned a further 45 into a three-quarter view: the tool's long axis
--- splits ~evenly between across-the-rack and into-the-stall, so its silhouette is
--- legible AND neither the 3.0-stud slot nor the 2.4-stud depth binds hard. Pure
--- profile (270) is the most legible silhouette of all, but it lays the full length
--- across the rack where it has only RACK_PITCH to live in.
---
--- AND THE HOLDER IS TIPPED FORWARD, WHICH IS THE HALF THAT ACTUALLY FIXED THE
--- MAGNETS. Yaw alone still leaves the tool pointing HORIZONTALLY out of its holder,
--- and a horseshoe magnet is a flat thing: presented level it came out 2.19 across
--- and 0.91 tall, a sliver on a rail. -55 degrees of pitch hangs it nose-down off the
--- rail the way a tool hangs on a pegboard, which turns its length into HEIGHT.
--- Measured across all three tracks at tier 1, this pair is the only one that gets
--- every track standing 2.4-2.8 studs tall inside its slot:
---
---     yaw  pitch | Detector          Magnet            Cleaner      (across/up/deep)
---     225      0 | 2.36/2.63/2.40    2.19/0.91/2.40    2.90/2.72/2.34
---     225    -55 | 2.67/2.70/2.40    1.85/2.83/2.40    2.03/2.37/2.40   <- this one
---     270    -55 | 2.90/2.87/1.36    1.57/2.90/2.06    2.13/2.10/2.40
---     225    -75 | 2.68/2.61/2.40    1.70/2.90/1.92    1.59/1.70/2.40
---     180    -70 | 1.10/2.31/2.40    2.03/2.90/0.89    2.53/1.83/2.40
---
--- Yaw is applied in the STALL's frame and pitch in the yawed one (origin * Ry * Rx),
--- not Kit.ang's single XYZ euler — a pitch about the stall's own X before the yaw
--- tips the row sideways instead of tipping each tool forward.
local RACK_PRESENT_YAW = 225
local RACK_PRESENT_PITCH = -55
local SHOPFRONT_Z = 0.6 -- the shopfront line: stand, display shelf and rail all sit on it
local MOUNT_REACH = 11 -- prompt activation distance, from in front of the display shelf

-- ── The stand, and the wing beside it ───────────────────────────────────
--
-- THE STAND IS WHERE YOU TALK TO THE SHOP; THE WING IS WHERE THE STOCK LIVES. The
-- rack used to hang over the counter, which meant the counter had to be as long as
-- the ladder — a 38-stud desk with one interaction on it, and the whole storefront
-- reading as one undifferentiated bench. It is two things now, split along the same
-- shopfront line: a short STAND at the left end of the store (the desk with the
-- station attributes, the sign over it and the outline on the ground in front of it)
-- and, past a gap you can see daylight through, the WING — a lower run of shelf with
-- the whole ladder hanging over it, cheapest nearest the stand.
--
-- SO "WHERE IS THE MENU" HAS A PHYSICAL ANSWER NOW. Walk to the stand for the card
-- panel and its stat blocks; walk down the wing to look at the actual tools and press
-- E on one. Two doors on the same purchase, as before, but you can now see which
-- door is which from across the plaza instead of learning it by walking into a radius.
--
-- BOTH HALVES CARRY THE STATION ATTRIBUTES, AND THAT IS NOT BELT-AND-BRACES. The
-- client's owned-check — the green tick that replaces a price on a tier you already
-- have — is painted from `state.offer`, which only exists while StationService says
-- you are AT this shop (StationController's rack pass says so in as many words). One
-- tight circle on the stand would blank every tick the moment you walked over to look
-- at the tools, which is the exact moment they are worth showing. One circle big
-- enough to cover both would have to be ~44 studs from a stand sitting at the end of
-- the store, and that reaches back past PLAZA_MID — a shop panel opening on the
-- respawn anchor in the middle of the courtyard. Two modest circles, one per half,
-- cover the storefront and nothing else; `StationService.at` returns the NEAREST
-- containing station, and both of these answer with the same kind and the same
-- StationId, so which one wins is a question with one answer.
local STAND_WIDTH = 8 -- the desk itself, wide enough to stand at and no wider
local STAND_EDGE = 2 -- clear lumber outboard of the stand, at the store's left end
local STAND_RACK_GAP = 3 -- the break between stand and wing: this is the whole read
local STAND_RADIUS = STAND_WIDTH / 2 + 6 -- the desk, plus the forecourt you stand in

--- How wide a stall has to be to hold its stand AND its whole ladder. DERIVED, not
--- written down: Detector has 8 tiers and Magnet 6, and a fixed width would either
--- crush the Detector rack or leave the Magnet stall two thirds empty. Every other
--- dimension of a stall (posts, slats, shelf, canopy, floor markers) keys off this,
--- so adding a tier to a track in Config/Gear widens its shop and nothing else has
--- to move.
---
--- IT GREW BY SIX STUDS WHEN THE RACK CAME OFF THE COUNTER. It used to be
--- `rackSpan + 13` — the ladder plus five studs of clear counter either side. The
--- stand now occupies the whole left margin in its own right, so the sum is spelled
--- out left to right instead: edge, stand, gap, half a slot, the ladder, half a slot,
--- end margin. `assertNoShopOverlap` re-proves the triangle at every rebuild, and it
--- passes at the current STALL_RING_RADIUS with ~21 studs to spare between fronts and
--- ~13 to the Outfitter, so nothing had to move to make room for this.
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

--- The shelf under the wing: the ladder, plus the half-slot each end tier needs, plus
--- a stud of lip. The rack's own end posts (span/2 + 1.5) stand just inside it.
local function rackShelfWidth(track: string): number
	return rackSpan(track) + RACK_SLOT_WIDTH + 1
end

--- A stall's vertex on the ring, world XZ.
local function stallAt(spec: { bearing: number }): (number, number)
	local th = math.rad(spec.bearing)
	return PLAZA_MID.x + STALL_RING_RADIUS * math.cos(th), PLAZA_MID.z + STALL_RING_RADIUS * math.sin(th)
end

--- The outfitter's three counters on one bench. Radius 6 at a 13-stud pitch, so
--- no two counters' circles overlap and standing at one is unambiguous. `at` is
--- on the central square at (-44, 0), due west of PLAZA_MID and set back behind
--- the Detector and Cleaner stalls (see the header) — its +Z front faces due
--- east at the centre, so `facingOrigin` leaves it square.
---
--- IT MOVED 14 STUDS FURTHER WEST (-30 -> -44) WHEN THE STALLS GREW. This building's
--- width runs north-south (it faces east), so its 46-stud span sits broadside to the
--- two western stalls' backs — and once those stalls widened to hold their racks,
--- the Detector stall's outer corner came within ~2 studs of this wall on the
--- Detector's own width axis: 3.6 studs, clear but not a gap anyone walks down, and
--- the header's "~27 studs clear of the stalls' backs" would have been a lie. -44
--- restores ~16 studs of real clearance (15.7 to the Detector stall, 17.5 to the
--- Cleaner, both measured by `assertNoShopOverlap`'s own footprints). There is room for it: the grey
--- central pad runs to the plaza's own west edge here (Hub.PAD_WEST_EXTEND), so the
--- west face at x=-52 is still on the pad with ~13 studs of apron behind it.
local OUTFITTER = {
	at = { -44, 0 },
	pitch = 13,
	counters = {
		{ track = "Suit", label = "SUITS", tagline = "survive it longer" },
		{ track = "Boots", label = "BOOTS", tagline = "get home faster" },
		{ track = "Satchel", label = "SATCHELS", tagline = "buy the clock time" },
		-- LUCK IS NOT HERE, and it briefly was. It is the one track you neither hold
		-- nor wear, and a fourth desk here sold it as though it were a satchel. It
		-- moved to a glowing button staked next to the wash pad it actually affects
		-- (build/Plots.buildLuckButton) -- press E, no panel. World.verify() still
		-- asserts every priced track is buyable somewhere; it accepts a `SellsTrack`
		-- attribute as well as a shop counter, which is what keeps that check honest
		-- after this move.
	},
}

--- A build origin on the plaza plane at world (x, z), turned so its local +Z —
--- every shop's counter-facing front — points at (towardX, towardZ). Both
--- builders lay every part as a local offset from what this returns, so this one
--- CFrame is the whole of a shop's position AND its facing.
local function facingOrigin(x: number, z: number, towardX: number, towardZ: number): CFrame
	local topY = Hub.PLAZA.topY
	-- CFrame.lookAt aims local -Z (its LookVector) at the target; the shop fronts
	-- are +Z, so aim -Z at the target's mirror through (x, z) and +Z lands on the
	-- target. Degenerate only if (x, z) == the target, which no caller passes.
	local mirror = Vector3.new(2 * x - towardX, topY, 2 * z - towardZ)
	return CFrame.lookAt(Vector3.new(x, topY, z), mirror)
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

--- The reference roof is one shallow rectangular awning, striped front-to-back,
--- with a short matching valance at the front. Separate studded Plastic parts
--- keep every stripe crisp and give it the chunky classic-Roblox texture.
---
--- `accent` is the stall's own hex — the canopy stripes and valance alternate it
--- with white, so each stall's cloth is its own colour (coral / teal / purple)
--- instead of the shared awning red every stall used to wear. It is the biggest
--- painted surface on the stall, so this is now the loudest of the per-shop
--- colour cues (with the trim cap, floor marker and sign text).
--- `width` IS THE STALL'S OWN WIDTH NOW, not a constant. The canopy used to be a
--- fixed 7 stripes x 2.5 = 17.5 studs because every stall was the same size; a
--- Detector stall is 38 wide and a Magnet stall 31, so the stripe COUNT is derived
--- from the width instead. Forced odd, so the cloth starts and ends on the accent
--- colour rather than on white — an even count reads as a printing error from the
--- ground, and it is the same "the pattern has to close on itself" constraint the
--- plaza's checkerboard tiles are tuned for.
local function buildStripedCanopy(parent: Instance, origin: CFrame, accent: string, width: number)
	local stripeCount = math.max(3, math.floor(width / 2.5))
	if stripeCount % 2 == 0 then
		stripeCount += 1
	end
	local stripeWidth = width / stripeCount
	local totalWidth = width
	local centerZ = -4
	local centerY = 9.8
	local depth = 14.5
	local tiltDegrees = 4
	local frontZ = centerZ + depth / 2
	local frontY = centerY - math.sin(math.rad(tiltDegrees)) * (depth / 2)

	for index = 1, stripeCount do
		local color = if index % 2 == 1 then accent else C.labelText
		local x = -totalWidth / 2 + (index - 0.5) * stripeWidth
		build(parent, origin, {
			name = `CanopyStripe{index}`,
			pos = { x, centerY, centerZ },
			size = { stripeWidth + 0.06, 0.45, depth },
			color = color,
			material = "Plastic",
			rot = Kit.ang(tiltDegrees, 0, 0),
			studs = true,
			canCollide = false,
		})
		build(parent, origin, {
			name = `CanopyValance{index}`,
			pos = { x, frontY - 0.45, frontZ },
			size = { stripeWidth + 0.06, 1.15, 0.45 },
			color = color,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	for _, z in { centerZ - depth / 2 + 0.35, frontZ - 0.35 } do
		local y = centerY - math.sin(math.rad(tiltDegrees)) * (z - centerZ) - 0.38
		build(parent, origin, {
			name = "CanopySupport",
			pos = { 0, y, z },
			size = { totalWidth, 0.4, 0.5 },
			color = C.shopWood,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end
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

--- The floating stall sign, in the reference's two-line hierarchy: the big line
--- names WHAT THE STALL SELLS (DETECTORS / MAGNETS / CLEANERS) in that shop's own
--- accent colour so the sign itself does the colour-navigation, and a smaller
--- white line under it carries the tagline. `accent` is the shop's hex string.
--- The big line is TextScaled so any label length fits its band without
--- re-tuning TextSize.
local function buildStoreBillboard(adornee: BasePart, label: string, tagline: string, accent: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StoreSign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(400, 96)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40
	gui.Parent = adornee

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 56)
	title.BackgroundTransparency = 1
	title.Font = Kit.FONT
	title.Text = label
	title.TextScaled = true
	title.TextColor3 = Color3.fromHex(accent)
	title.TextStrokeColor3 = Color3.fromHex(C.hazardBlack)
	title.TextStrokeTransparency = 0
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(0, 56)
	subtitle.Size = UDim2.new(1, 0, 0, 34)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Kit.FONT
	subtitle.Text = tagline
	subtitle.TextColor3 = Color3.fromHex(C.labelText)
	subtitle.TextSize = 25
	subtitle.TextStrokeColor3 = Color3.fromHex(C.hazardBlack)
	subtitle.TextStrokeTransparency = 0
	subtitle.Parent = gui
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
	material: string?,
	studded: boolean?,
}

--- The counter desk — the interactive part — in grey storefront lumber
--- (C.shopWood) with a coloured trim cap on top in the shop's own accent.
--- Returns the desk so the caller can billboard it. `name` defaults to "Counter"
--- and exists because a plaza stall builds TWO of these on one shopfront (a Stand
--- and a DisplayShelf) and two sibling parts both called "Counter" is a debugging
--- tax nobody needs in the explorer. `material` defaults to
--- "Wood" (the Outfitter's own look); the plaza stalls pass "Plastic" instead,
--- since Roblox's stud-bump texture only renders on Plastic, and that studded
--- look is the whole point of the reskin.
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

	return desk
end

-- ── The gable roof ───────────────────────────────────────────────────────────

--- A simple peaked roof: two flat panels sloping up from the wall tops to a ridge
--- along the building's centreline, plus a capping ridge beam. `halfDepth` is the
--- distance from centre to each wall, `rise` how far the ridge climbs above the
--- wall tops. Positions are derived from the two literal points each panel spans
--- (wall-top eave, centre-line ridge) rather than reasoned out in the abstract --
--- this project has gotten CFrame rotation signs backwards from pure reasoning
--- more than once this session, and deriving from known points is the version
--- that's checkable by eye against the numbers.
---
--- Returns the ridge Y so the caller can float a sign above it. Shared by the
--- plaza stalls (a small roof on posts) and the Outfitter (a much bigger one
--- over real walls) -- the same shape at two different scales. `material`
--- defaults to "Wood" (the Outfitter's own look, unchanged); the plaza stalls
--- pass "Plastic" so the roof shows Roblox's stud-bump texture, matching the
--- reference market stall's studded-block look.
---
--- CLEARANCE, NOT JUST THE CENTRELINE. The eave/ridge points above describe
--- where the panel's own zero-thickness centreline sits -- but a real board has
--- thickness on both sides of that line, so the panel's PHYSICAL underside sits
--- `(thickness/2)*cos(tilt)` below it. Left uncorrected, a flat-topped post
--- built to exactly `wallHeight` pokes up into that underside by that same
--- amount -- invisible on the original round, shallow-pitched posts, and very
--- visible once the posts went square and the roof steeper. `clearance` raises
--- the whole roof (both panels AND the ridge beam, so they stay flush with each
--- other) by that offset, so it's the underside that touches the wall top.
local function buildGableRoof(parent: Instance, origin: CFrame, centerZ: number, wallHeight: number, halfDepth: number, rise: number, width: number, color: string, material: string?): number
	local thickness = 0.6
	local slopeLen = math.sqrt(halfDepth ^ 2 + rise ^ 2)
	local tiltDeg = math.deg(math.atan2(rise, halfDepth))
	local clearance = (thickness / 2) * math.cos(math.rad(tiltDeg))
	local ridgeY = wallHeight + rise + clearance
	local mat = material or "Wood"

	for _, side in { -1, 1 } do
		-- Eave point: (side*halfDepth, wallHeight). Ridge point: (0, wallHeight + rise).
		-- The panel's own centre sits halfway between them, then the whole
		-- panel is lifted by `clearance` (see above).
		build(parent, origin, {
			name = "RoofPanel",
			pos = { 0, wallHeight + rise / 2 + clearance, centerZ + side * halfDepth / 2 },
			size = { width, thickness, slopeLen },
			color = color,
			material = mat,
			rot = Kit.ang(side * tiltDeg, 0, 0),
			canCollide = false,
		})
	end

	build(parent, origin, {
		name = "RoofRidge",
		pos = { 0, ridgeY, centerZ },
		size = { width, 1.1, 1.1 },
		color = C.shopWood,
		material = mat,
		shape = "Cylinder",
		rot = R.cylAlongX,
		canCollide = false,
	})

	return ridgeY
end

-- ── The hanging tier rack ───────────────────────────────────

--- The template for one tier of `track`, or nil if this place has no art for it.
--- Same lookup ToolService.equip does, deliberately: if the model it would put in
--- your hands does not exist, the rack must not pretend it does.
local function tierTemplate(track: string, tier: number): Model?
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

--- Hang one tier's real model under the rail, centred on `target`.
---
--- ORIENTED THE WAY IT IS CARRIED, via the model's own `HoldCFrame` — the attribute
--- ToolService reads to place the thing in a player's hands. Feed it a virtual hand
--- turned to face the customer and the tool lands at exactly the angle a shopkeeper
--- holding it out over the counter would present it at. That matters because the
--- three tracks do NOT share an authored axis: the detector's shaft runs along its
--- local X, the magnet's along its local Z. Any single hand-picked rotation gets one
--- of them right and lies the others flat — the first pass hung a tier-1 magnet
--- 9.7 studs deep, straight back through the counter and out of the slat wall.
--- HoldCFrame is the one piece of per-model orientation this project already
--- maintains, so the rack reads it instead of inventing a second one.
---
--- SCALED FROM THE TIER'S OWN SCALE, NOT FROM 1. `Model:ScaleTo` is ABSOLUTE — it
--- sets scale relative to the model as authored, discarding whatever the instance
--- carries. These templates are all pre-scaled (Config/ToolTiers' `scale` column; a
--- tier-1 magnet ships at 0.300), so `ScaleTo(f)` threw the tier's own size away and
--- came out 35% oversized. It has to be `GetScale() * f`.
---
--- AND `f` IS MEASURED IN THE STALL'S FRAME, ON THREE LIMITS, NOT ONE. A single
--- "longest edge = RACK_MODEL_SIZE" rule leaves the other two axes wherever the art
--- put them, and the two that matter here are neighbours (a model wider than
--- RACK_PITCH overlaps the tier next to it) and depth (one deeper than the counter
--- pokes through it). So the oriented box is projected onto the STALL'S local axes —
--- not the world's, the stall is rotated — and the scale is whichever of the three
--- limits binds hardest.
---
--- THEN RE-CENTRED, which is what makes any of this safe. HoldCFrame places a
--- model's PIVOT, and a pivot is wherever the Handle happens to sit — a detector's
--- is 1.2 studs off its own box centre. Left alone, every tier would hang at a
--- slightly different height and the row would sag and rise across the rack. So the
--- last step measures the box and slides the model so the BOX centre lands on
--- `target`, whatever the art's pivot is doing.
local function hangTierModel(parent: Instance, origin: CFrame, hand: CFrame, target: Vector3, track: string, tier: number): boolean
	local template = tierTemplate(track, tier)
	if template == nil then
		return false
	end

	local clone = template:Clone()
	clone.Name = `T{tier}`

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

	local hold = template:GetAttribute("HoldCFrame")
	if typeof(hold) ~= "CFrame" then
		hold = CFrame.new()
	end
	clone:PivotTo(hand * hold)

	-- The model's box, RE-MEASURED ON THE STALL'S OWN AXES: its 8 corners taken into
	-- the stall's local frame, then min/max per axis. The box GetBoundingBox returns
	-- is aligned to the MODEL, which after a HoldCFrame turn is aligned to neither
	-- the stall nor the world — so its raw X/Y/Z say nothing about how much room the
	-- thing takes up ALONG THE RACK, which is the only extent that can collide with
	-- a neighbour.
	local function localExtents(): Vector3
		local cf, size = clone:GetBoundingBox()
		local half = size / 2
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = -lo
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = origin:PointToObjectSpace(cf * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
					lo, hi = lo:Min(p), hi:Max(p)
				end
			end
		end
		return hi - lo
	end

	local e = localExtents()
	local longest = math.max(e.X, e.Y, e.Z)
	if longest > 0 then
		local f = math.min(RACK_MODEL_SIZE / longest, RACK_SLOT_WIDTH / e.X, RACK_SLOT_DEPTH / e.Z)
		clone:ScaleTo(clone:GetScale() * f)
	end

	local centre = clone:GetBoundingBox().Position
	clone:PivotTo(clone:GetPivot() + (target - centre))
	return true
end

--- The price card over one hanging tier: its name, and what it costs.
---
--- NOT Kit.billboard, and the difference is width. Every other sign in the world
--- stands alone, so Kit.billboard's 200-400px card can be as wide as its text wants.
--- These sit RACK_PITCH studs apart in a row of up to eight, and at that spacing a
--- 200px card overlaps its neighbours into an unreadable smear the moment you walk
--- up to the counter. So: a narrow card, and the name is TextScaled rather than a
--- fixed TextSize, because "Bent Coil" and "Resonance Mapper" have to fit the same
--- band. MaxDistance is short for the same crowding reason — 21 price cards visible
--- from the middle of the plaza is noise, not information.
---
--- NAMED "Sign" WITH "Title" / "Subtitle" CHILDREN, matching Kit.billboard exactly.
--- The client rewrites the subtitle into the owned-check (StationController's rack
--- pass) and finds it by those names; a card that spelled them differently would be
--- invisible to it.
local function buildPriceCard(mount: BasePart, name: string, price: number, accent: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(130, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 28
	-- Same reason Kit.billboard sets this: the stall signs sit near lamps and a sign
	-- should not wash toward white along with whatever it is bolted to.
	gui.LightInfluence = 0
	gui.Parent = mount

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Kit.FONT
	title.Text = name
	title.TextScaled = true
	title.TextColor3 = Color3.fromHex(C.labelText)
	title.TextStrokeTransparency = 0.4
	title.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Position = UDim2.fromOffset(0, 24)
	sub.Size = UDim2.new(1, 0, 0, 20)
	sub.BackgroundTransparency = 1
	sub.Font = Kit.FONT
	sub.TextSize = 16
	sub.Text = `${price}`
	sub.TextColor3 = Color3.fromHex(accent)
	sub.TextStrokeTransparency = 0.5

	-- WHAT THIS LABEL SAYS WHEN NOBODY OWNS THE TIER, stamped onto the label itself.
	-- The client overwrites this subtitle with the green owned-check for whoever is
	-- standing here (StationController's rack pass) and has to be able to put the
	-- price back afterwards. Stamping the as-built values here means it never has to
	-- know the price OR the shop accent to do that -- the same RestText/RestColor
	-- trick LiquidService uses to restore the wash pad sign after announcing a roll.
	sub:SetAttribute("RestText", sub.Text)
	sub:SetAttribute("RestColor", sub.TextColor3)
	sub.Parent = gui
end

--- One hook on the rail: the mount block that carries the sale, the tier's model
--- hanging under it (or a painted stand-in), and the price card over it.
---
--- THE MOUNT IS BUILT WHETHER OR NOT THE ART IS. A missing template costs the stall
--- its silhouette, never its ability to sell — the fallback is a plain block in the
--- shop's accent, and the prompt, the attributes and the billboard are identical
--- either way. World.verify() asserts every priced track is buyable somewhere, and
--- that assertion must not depend on which place file this ran in.
local function buildRackHook(parent: Instance, origin: CFrame, spec: { track: string, color: string }, tier: number, x: number)
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

	-- THE VIRTUAL HAND: a holder standing BEHIND the counter, facing the customer.
	-- A character's own frame has its LookVector on -Z, and the stall's +Z points at
	-- the plaza, so "facing out" is the stall origin turned 180 degrees about Y. Feed
	-- that to hangTierModel and every tool presents at its carried angle, seen from
	-- the front. The translation in it does not matter — hangTierModel re-centres on
	-- `target` afterwards — only the rotation does.
	local hand = origin * Kit.ang(0, RACK_PRESENT_YAW, 0) * Kit.ang(RACK_PRESENT_PITCH, 0, 0)
	local target = (origin * CFrame.new(x, RACK_RAIL_Y - 1.9, SHOPFRONT_Z)).Position
	local hung = hangTierModel(parent, origin, hand, target, spec.track, tier)

	if not hung then
		build(parent, origin, {
			name = `T{tier}Stand`,
			pos = { x, RACK_RAIL_Y - 2.4, SHOPFRONT_Z },
			size = { 1.2, 2.2, 1.2 },
			color = spec.color,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Upgrade"
	prompt.ActionText = `Buy ${def.price}`
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = MOUNT_REACH
	-- The counter is a solid part between the player and the rail, so a line-of-sight
	-- prompt would only ever fire from inside the stall.
	prompt.RequiresLineOfSight = false
	prompt.Parent = mount

	-- Name and price. A client turns this into the green owned-check when the player
	-- is standing here and the server says they already have this tier — see
	-- StationController's rack pass. Built with the price showing because that is
	-- what it says to everyone who has not bought it, which is most people most of
	-- the time.
	buildPriceCard(mount, def.name, def.price, spec.color)
end

--- Every tier of the track, cheapest on the left, hanging over the wing's shelf.
---
--- `origin` IS THE WING'S OWN CENTRE, not the stall's — the caller passes
--- `stallOrigin * CFrame.new(rackX(track), 0, 0)` the same way buildOutfitter shifts
--- a counterOrigin, so everything below stays written as a symmetric offset from zero
--- and this function never has to know where in the store it was hung.
local function buildTierRack(parent: Instance, origin: CFrame, spec: { track: string, color: string })
	local span = rackSpan(spec.track)
	local count = Gear.maxTier(spec.track)

	-- The rail the tiers hang from, and a post at each end carrying it down to the
	-- counter top (2.25, the trim cap's own top face).
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
			pos = { side * (span / 2 + 1.5), (RACK_RAIL_Y + 2.25) / 2, SHOPFRONT_Z },
			size = { 0.5, RACK_RAIL_Y - 2.25, 0.5 },
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
--- and rear slats, an open counter, and a striped canopy + two-line sign both in
--- the stall's own accent colour. The canopy, the sign text, the floor marker
--- and the counter's trim cap — all `spec.color` — are the per-shop identity now
--- that the shopkeeper and the identity prop are gone.
local function buildStall(parent: Instance, spec: { track: string, bearing: number, color: string, label: string, tagline: string })
	local m = Instance.new("Model")
	m.Name = `{spec.track}Shop`

	-- Position AND facing in one CFrame: at this stall's vertex on the ring, turned
	-- so the counter side (+Z) looks back at PLAZA_MID. Y comes from Hub.PLAZA.topY
	-- (the plaza is at Stages.SURFACE_Y, not Y=0). Every part below is a LOCAL
	-- offset from this, so this one line carries the whole stall's placement.
	local atX, atZ = stallAt(spec)
	local origin = facingOrigin(atX, atZ, PLAZA_MID.x, PLAZA_MID.z)

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

	-- Four chunky posts holding the roof up, in grey storefront lumber
	-- (C.shopWood). Square-cut, not round logs — the reference photo's posts read
	-- as sawn beams, and Block needs no
	-- rot (unlike Cylinder, whose long axis is local X and needs R.cylUp to
	-- stand it upright) since a Block's size is already literal {X,Y,Z}.
	-- Plastic, not Wood: Roblox's stud-bump texture only renders on Plastic
	-- (the same reason the plaza's own checkerboard tiles are Plastic), and
	-- that studded look is what makes this read as the chunky reference stall
	-- instead of a plain wood kiosk. Taller than the original kiosk, too — the
	-- reference stall reads as a proper standing structure, not a picnic table.
	--
	-- 2x2, not 1.1x1.1: the stud pattern needs a couple of repeats across a
	-- face to actually read as studded rather than a flat colour -- the same
	-- reason the checkerboard tiles were tuned to exactly 3x3 studs. A 1.1-wide
	-- post face was too narrow for the pattern to be legible even though the
	-- material was already correct.
	local POST_SIZE = 1.5
	local POST_DX = width / 2 - POST_SIZE / 2
	for _, dx in { -POST_DX, POST_DX } do
		for _, dz in { -10, 2 } do
			local postHeight = if dz < 0 then 10 else 9.2
			build(m, origin, {
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
	buildSlatWall(m, origin, width)

	-- The two halves of the shopfront, on one line, with STAND_RACK_GAP of open air
	-- between them — see "The stand, and the wing beside it".
	local sx, rx = standX(spec.track), rackX(spec.track)

	-- THE STAND. This is the part the whole file exists to place correctly: the desk
	-- you walk up to for the card panel, the thing the sign hangs over, and the shop's
	-- own StationId. Eight studs wide and parked at the left end of the store instead
	-- of the 37-stud bench that used to run the whole front, because the ladder no
	-- longer sits on top of it.
	-- material = "Plastic" here (not buildCounter's own "Wood" default) so the
	-- studded look stays consistent across the whole stall -- the Outfitter's
	-- call to the same function passes no material and keeps its original Wood.
	local stand = buildCounter(m, origin * CFrame.new(sx, 0, 0), {
		name = "Stand",
		color = C.steel,
		width = STAND_WIDTH,
		depth = 2.5,
		z = SHOPFRONT_Z,
		stationKind = "shop",
		stationId = spec.track,
		radius = STAND_RADIUS,
		material = "Plastic",
		studded = true,
	})
	buildStoreBillboard(stand, spec.label, spec.tagline, spec.color)

	-- THE WING'S SHELF, carrying the same StationId at its own radius. Not a spare
	-- copy of the stand: the offer that draws the rack's owned-ticks only exists while
	-- StationService has you at this shop, so without a circle out here every tick
	-- blanks the instant you walk over to look at the tools. Two modest circles beat
	-- one 44-stud one that would reach back into the courtyard — the header block on
	-- the stand has the full argument and the numbers.
	buildCounter(m, origin * CFrame.new(rx, 0, 0), {
		name = "DisplayShelf",
		color = C.steel,
		width = rackShelfWidth(spec.track),
		depth = 2.5,
		z = SHOPFRONT_Z,
		stationKind = "shop",
		stationId = spec.track,
		radius = rackShelfWidth(spec.track) / 2 + 6,
		material = "Plastic",
		studded = true,
	})

	-- The ladder itself, hanging over that shelf — see "The hanging tier rack".
	buildTierRack(m, origin * CFrame.new(rx, 0, 0), spec)

	buildStripedCanopy(m, origin, spec.color, width)

	-- TWO FLOOR MARKERS, ONE PER HALF, because there are two different things to do
	-- here now and the ground should say which is which. The box in front of the stand
	-- outlines where you stand for the panel; the long strip in front of the wing marks
	-- the ground you walk ALONG to browse the tools. A stud of gap between them, in the
	-- shop's own colour — never green, see the header.
	buildFloorMarker(m, origin, sx, 3.4, STAND_WIDTH + 3, 5, spec.color)
	buildFloorMarker(m, origin, rx, 3.4, rackShelfWidth(spec.track), 5, spec.color)

	m.Parent = parent
	return m
end

--- A shop's footprint on the plaza, as an oriented rectangle. `backZ`/`frontZ` are
--- the extremes of everything the builder lays down, in the shop's own local z.
local function shopFootprint(x: number, z: number, width: number, backZ: number, frontZ: number): Kit.OrientedRect
	local dirX, dirZ = PLAZA_MID.x - x, PLAZA_MID.z - z
	local len = math.sqrt(dirX * dirX + dirZ * dirZ)
	dirX, dirZ = dirX / len, dirZ / len
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
--- THIS IS HERE BECAUSE THE STALL WIDTHS ARE NOW DERIVED. While every stall was 15
--- studs wide at a hand-picked position, "do they overlap" was answered once by
--- looking at the numbers and stayed answered. It is not answered once any more:
--- adding a tier to a track in Config/Gear widens that track's shop, and past some
--- width the triangle closes on itself. STALL_RING_RADIUS and OUTFITTER.at are the
--- two numbers that then have to move, and this is what says so — at the rebuild
--- that broke it, naming the pair, rather than in a screenshot three weeks later.
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
			rect = shopFootprint(x, z, stallWidth(spec.track), -11.25, 5.9),
		})
	end

	local outfitterWidth = OUTFITTER.pitch * (#OUTFITTER.counters - 1) + 20
	table.insert(rects, {
		name = "Outfitter",
		rect = shopFootprint(OUTFITTER.at[1], OUTFITTER.at[2], outfitterWidth, -8, 8),
	})

	for i = 1, #rects do
		for j = i + 1, #rects do
			assert(
				not Kit.orientedRectsOverlap(rects[i].rect, rects[j].rect),
				`{rects[i].name} overlaps {rects[j].name} — widen STALL_RING_RADIUS ({STALL_RING_RADIUS}) or move OUTFITTER.at`
			)
		end
	end
end

-- ── The outfitter ─────────────────────────────────────────────────────────────

--- The outfitter: a proper building, not a bench under a trim strip. Three
--- shops left Suit, Boots and Satchel priced but unbuyable, and hazard gear that
--- actually reduces incoming damage earns more than a picnic table — two side
--- walls, a peaked roof, and BOTH gable ends open so it reads as a walk-through
--- rather than a room with a back wall. Tucked in behind the Detector and Cleaner
--- stalls on the west of the square; the +Z front (sign, forecourt marker, and
--- the counters just inside) faces due east at PLAZA_MID, the -Z end opens onto
--- the west apron behind. Each counter carries its own billboard naming the track
--- (SUITS / BOOTS / SATCHELS).
local function buildOutfitter(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Outfitter"

	-- Same primitive as the stalls: placed at OUTFITTER.at behind the Detector and
	-- Cleaner stalls, on the z=0 centreline so facingOrigin's aim at PLAZA_MID is
	-- a straight due-east facing with no turn.
	local origin = facingOrigin(OUTFITTER.at[1], OUTFITTER.at[2], PLAZA_MID.x, PLAZA_MID.z)
	local span = OUTFITTER.pitch * (#OUTFITTER.counters - 1)
	local width = span + 20
	local halfDepth = 8
	local wallHeight = 7

	-- Same 0.1 lift as the stall decks, for the same reason: 0.4 thick at y = -0.2 put
	-- this floor's top face on the plaza's own plane and the two z-fought.
	build(m, origin, { name = "Floor", pos = { 0, -0.1, 0 }, size = { width, 0.4, halfDepth * 2 }, color = C.plazaWarm, material = "Plastic" })

	-- Two side walls only. BOTH gable ends are left open: the +Z end faces
	-- PLAZA_MID (east) and is the counter approach, the -Z end opens onto the west
	-- apron behind. That open pair is what makes this a walk-through and not a
	-- room with a back wall.
	for _, dx in { -width / 2, width / 2 } do
		build(m, origin, { name = "SideWall", pos = { dx, wallHeight / 2, 0 }, size = { 0.6, wallHeight, halfDepth * 2 }, color = C.shopWood, material = "Wood" })
	end

	local ridgeY = buildGableRoof(m, origin, 0, wallHeight, halfDepth, 4, width + 2, C.shopOutfitter)

	-- The sign, floating over the open +Z end, facing PLAZA_MID -- the same
	-- Back-face convention the plaza stalls use, for the same reason: whoever is
	-- walking toward this building from the centre is standing on the +Z side.
	-- Matte, in the shop's accent colour -- colour still does the navigation, it
	-- just doesn't glow.
	-- Fixed size, not derived from the building's width — a sign that spans the
	-- whole 46-wide storefront came out as a comically long, thin plank with
	-- "OUTFITTER" lost in the middle of it, which read as stretched-out text even
	-- though TextScaled itself never distorts a glyph. The board's own proportions
	-- were the actual problem.
	local signY = ridgeY + 2.2
	build(m, origin, { name = "SignOutline", pos = { 0, signY, halfDepth - 0.2 }, size = { 15, 3.0, 0.3 }, color = C.hazardBlack, material = "Plastic", canCollide = false })
	local sign = build(m, origin, { name = "Sign", pos = { 0, signY, halfDepth + 0.2 }, size = { 14.4, 2.6, 0.4 }, color = C.shopOutfitter, material = "SmoothPlastic", canCollide = false })
	Kit.surfaceText(sign, Enum.NormalId.Back, "OUTFITTER", C.signText)

	-- The forecourt outline at the +Z end, the approach from the centre, with the
	-- counters just inside it.
	buildFloorMarker(m, origin, 0, halfDepth - 3, width - 6, 8, C.shopOutfitter)

	for index, counter in OUTFITTER.counters do
		local x = -span / 2 + (index - 1) * OUTFITTER.pitch
		local counterOrigin = origin * CFrame.new(x, 0, 0)

		local desk = buildCounter(m, counterOrigin, {
			color = C.shopOutfitter,
			width = 4,
			depth = 2.4,
			z = halfDepth - 3.5,
			stationKind = "shop",
			stationId = counter.track,
			-- Tighter than the plaza stalls: three counters share one building,
			-- and standing at one of them has to be unambiguous.
			radius = 6,
		})
		billboard(desk, 200, 4.4, counter.label, counter.tagline, C.shopOutfitter)
	end

	m.Parent = parent
	return m
end

local function createShops(): Model
	local shops = Instance.new("Model")
	shops.Name = Shops.MODEL_NAME
	Kit.stamp(shops, BUILDER_SOURCE, BUILDER_VERSION)

	-- Before a single part is laid: the widths are derived now, so the ring radius
	-- that fits them is a claim this file has to prove every time, not once.
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
