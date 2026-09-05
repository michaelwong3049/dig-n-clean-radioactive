--!strict
--[[
	Sky.luau — what is OVER your head, per stage. The other half of Config/Stages'
	`fogColor` / `fogEnd`.

	WHY THIS IS A SEPARATE FILE AND NOT FOURTEEN MORE FIELDS ON StageDef. Stages.luau
	is already the longest config in the project and every field on StageDef is
	load-bearing for gameplay — rads, hardness, footprint, loot tilt. The sky is pure
	art direction with no simulation attached, and it is fourteen numbers per stage.
	Folding that in would have doubled StageDef for something no service ever reads.
	Keyed by stage id here instead; Stages stays the gameplay file.

	WHY THE SKY IS PROCEDURAL AND NOT SIX SKYBOX IMAGES.

	The place file was shipping `rbxassetid://6444884337` — Roblox's stock blue-sky
	skybox, dragged in by whoever made the place and written down nowhere. That is
	the exact failure build/Daylight.luau's own header is about: a look that only
	exists because somebody once clicked something in Studio. So build/Daylight now
	CLEARS the six skybox faces, which drops the renderer onto its procedural sky —
	and a procedural sky is driven entirely by Atmosphere and the sun, both of which
	are plain properties this file can own.

	The other reason matters more in play: skybox textures cannot cross-fade.
	Swapping six images on a stage boundary is a hard cut, and AtmosphereController's
	header already has the rule — "a hard cut on a stage boundary reads as a bug; a
	half-second fade reads as walking into different air." Every value below is a
	Color3 or a number, so every one of them tweens. Marketplace skyboxes would also
	have handed a shipped game six third-party asset IDs that somebody else can get
	moderated out from under it.

	THE ARC: A NORMAL DAY THAT CURDLES.

	Config/Stages' ground palette already runs "life fading into a dead wasteland"
	and then turns at Stage 4. The sky is that story told upward, and is deliberately
	SLOWER to turn than the ground — the ground is dead by Stage 3 while the sky is
	still only dusty. It reads as the wasteland spreading up from underfoot rather
	than as six unrelated colour schemes.

	    base camp    a normal bright day. thin air, a few white clouds.
	    1 Ash Flats  the same day with dust in it. barely wrong.
	    2 Suburbs    the light yellows. the cloud deck thickens and goes dun.
	    3 Fallout F. full dust ceiling, khaki, the sun going hazy.
	    4 Exclusion  THE TURN. the sky itself is acid green, lidded with green cloud.
	    5 Reactor    sickly chartreuse, glare climbing, the sun swollen.
	    6 Crater     an amber lid over violet ground. the day is dying.

	Camp stays a clean blue day ON PURPOSE. It is the only place in the game where
	looking up is not a warning, and that contrast is what makes Stage 4 land.

	EVERY COLUMN ESCALATES MONOTONICALLY AND Util/Spec PINS THAT. Density, haze,
	glare, cloud cover, cloud density, sun size, sun rays and clock time only ever go
	up with stage id; brightness only ever goes down. Retune a row and Spec tells you
	whether you have accidentally made a deep stage the pleasant one.

	HAZE IS THE COLOUR KNOB. DENSITY IS NOT. This cost an afternoon of screenshots and
	is the single most useful thing in this file, so it is written down rather than
	rediscovered:

	    atmoHaze     recolours THE SKY ITSELF toward `atmoColor`. It is the only
	                 property that does. Below about 2 the procedural sky stays
	                 Roblox blue no matter what `atmoColor` says.
	    atmoDensity  attenuates DISTANCE. It barely touches the sky dome at all.

	The first draft of this table had it backwards and drove the escalation off
	density, which produced a Stage 4 with a bright blue sky and green clouds — a
	nice day with odd weather, not a poisoned one. Measured live: at Stage 4's colour,
	density 0.48 / haze 1.2 is still blue overhead, while density 0.36 / haze 3.0 is
	fully green. Haze 3.0 is therefore where Stage 4 sits, and every row was refitted
	around haze rather than density.

	The catch is that haze is also what WASHES OUT geometry — it is the same
	scattering term — so it cannot simply be run to the top of its range. Stage 6 at
	density 0.55 / haze 4.8 flattened the entire Crater, walls and ground and cloud
	deck alike, into one featureless amber field. 3.4 is the measured ceiling where
	the violet checkerboard is still legible through amber air, and Util/Spec pins it.

	Stage 6 gets away with less haze than its drama needs because `clockTime` 16.0 is
	doing half the work: a low sun warms the procedural sky toward amber for free.
	Green has no such natural hour, which is exactly why Stage 4 has to buy its colour
	with haze instead.

	CLOUDS MUST BE DARKER THAN THE AIR THEY HANG IN. Same afternoon, same method. The
	first draft picked cloud colours a shade lighter than each stage's sky, on the
	theory that clouds are bright — and at Stage 6 the deck vanished completely,
	because an amber cloud on an amber sky has no contrast to render with. Every
	`cloudColor` below is deliberately darker than its `atmoColor`. A lid reads as a
	lid because it is darker than what it covers.

	WHAT IS NOT HERE. Fog (Stages.fogColor / fogEnd) — it was here first and
	AtmosphereController already tweens it. Depth of field stays off at every stage:
	this game's tension is "how far away is base camp" and blurring the horizon
	fights that directly (build/Daylight's header).
]]

export type SkyLook = {
	-- Atmosphere. With no skybox texture these five ARE the sky: `atmoColor` tints
	-- the air (and so the upper sky), `atmoDecay` is what it decays toward at the
	-- horizon, `atmoDensity` is how much of it there is, `atmoHaze` how milky.
	atmoColor: Color3,
	atmoDecay: Color3,
	atmoDensity: number, -- 0..1; distance attenuation, NOT sky colour. See the header.
	atmoGlare: number, -- 0..10; the bloom of light around the sun
	atmoHaze: number, -- 0..10; THE sky-colour knob, capped at 3.4. See the header.

	-- Terrain.Clouds. The one piece of literal sky SCENERY — a real, moving deck
	-- rather than a tint. `cloudCover` is how much of the sky it covers,
	-- `cloudDensity` how thick and dark it is where it covers. Always DARKER than
	-- `atmoColor` above, or the deck has no contrast and does not render — header.
	cloudColor: Color3,
	cloudCover: number, -- 0..1; never 1, see Stage 6's note
	cloudDensity: number, -- 0..1

	-- The sun and the light it throws. A swelling, weakening, lower sun does more
	-- for "this place is wrong" than any amount of cloud.
	brightness: number, -- Lighting.Brightness
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
	sunRays: number, -- SunRaysEffect.Intensity, 0..1
	sunSize: number, -- Sky.SunAngularSize, degrees
	clockTime: number, -- later = lower sun = longer shadows = the day dying
}

local Sky = {}

--- Base camp, the plaza, and anywhere the client has no stage for. A normal day.
--- These values MUST match build/Daylight.apply()'s own — the server writes this
--- look into Lighting at build time and it is what the client tweens back TO when
--- you walk home. Change one, change the other. Daylight reads this table directly
--- so that they cannot drift; the duplication is gone, the coupling is deliberate.
Sky.BASE = {
	atmoColor = Color3.fromHex("E6F7E0"),
	atmoDecay = Color3.fromHex("9FD8B0"),
	atmoDensity = 0.22,
	atmoGlare = 0.15,
	atmoHaze = 0.6,

	cloudColor = Color3.fromHex("F2F7F0"),
	cloudCover = 0.38,
	cloudDensity = 0.28,

	brightness = 2.4,
	outdoorAmbient = Color3.fromHex("7E9488"),
	colorShiftTop = Color3.fromHex("FFF3D6"),
	sunRays = 0.08,
	sunSize = 12,
	clockTime = 13.6,
} :: SkyLook

--- Keyed by Stages.DEFS id. A stage with no entry falls back to BASE, which is the
--- right failure mode: an unskinned stage looks like a normal day, not like a bug.
Sky.LOOKS = {
	-- 1 — ASH FLATS. Deliberately almost nothing. Stage 1's fog is still base camp's
	-- pale blue (CFF3FF) and its west end is literal grass; if the sky turned here
	-- there would be no "before" left for Stage 4 to be a departure from.
	[1] = {
		atmoColor = Color3.fromHex("E9F4DE"),
		atmoDecay = Color3.fromHex("A9D2A6"),
		atmoDensity = 0.25,
		atmoGlare = 0.18,
		atmoHaze = 1.0,

		cloudColor = Color3.fromHex("DCE4D8"),
		cloudCover = 0.44,
		cloudDensity = 0.33,

		brightness = 2.35,
		outdoorAmbient = Color3.fromHex("7E9488"),
		colorShiftTop = Color3.fromHex("FFF1D0"),
		sunRays = 0.12,
		sunSize = 12.5,
		clockTime = 13.8,
	},

	-- 2 — THE SUBURBS. Follows the ground. Stage 2's fog stopped being green and went
	-- dusty tan (E8D9B0) for exactly the clash reason its own comment gives, and the
	-- sky does the same. The cloud deck is the first thing here that reads as WEATHER
	-- rather than as a filter over the same day.
	[2] = {
		atmoColor = Color3.fromHex("F0E6C2"),
		atmoDecay = Color3.fromHex("C9B87E"),
		atmoDensity = 0.28,
		atmoGlare = 0.24,
		atmoHaze = 1.6,

		cloudColor = Color3.fromHex("BFAE86"),
		cloudCover = 0.52,
		cloudDensity = 0.42,

		brightness = 2.25,
		outdoorAmbient = Color3.fromHex("8B8A70"),
		colorShiftTop = Color3.fromHex("FFEDC0"),
		sunRays = 0.18,
		sunSize = 13.5,
		clockTime = 14.2,
	},

	-- 3 — FALLOUT FIELDS. The dust ceiling closes. This is the last stage that could
	-- plausibly be a bad day on Earth, which is the whole job of the row: Stage 4 has
	-- to arrive as a different planet, and it can only do that from here.
	[3] = {
		atmoColor = Color3.fromHex("E7D2A6"),
		atmoDecay = Color3.fromHex("B79868"),
		atmoDensity = 0.32,
		atmoGlare = 0.30,
		atmoHaze = 2.2,

		cloudColor = Color3.fromHex("9C8154"),
		cloudCover = 0.58,
		cloudDensity = 0.50,

		brightness = 2.15,
		outdoorAmbient = Color3.fromHex("8C8163"),
		colorShiftTop = Color3.fromHex("FFE4AC"),
		sunRays = 0.24,
		sunSize = 14.5,
		clockTime = 14.7,
	},

	-- 4 — THE EXCLUSION BELT. WHERE THE SKY TURNS, one stage after the ground did.
	-- Stage 4's fog has been acid green (6FE04A) since long before this file existed
	-- and nothing above the horizon ever agreed with it; now it does. Green cloud
	-- over dead brown ground with hot-pink ooze is not a palette anyone would choose
	-- for a nice place, which is the point — Stage 4 is the dive.
	[4] = {
		atmoColor = Color3.fromHex("B8F09C"),
		atmoDecay = Color3.fromHex("4FA83A"),
		-- MEASURED, not chosen. density 0.48 / haze 1.2 is still a blue sky here;
		-- 0.36 / 3.0 is the green one, with the checkerboard walls still legible
		-- through it. See the header's haze-is-the-colour-knob note.
		atmoDensity = 0.36,
		atmoGlare = 0.38,
		atmoHaze = 3.0,

		cloudColor = Color3.fromHex("5E9E45"),
		cloudCover = 0.66,
		cloudDensity = 0.60,

		brightness = 2.05,
		outdoorAmbient = Color3.fromHex("6F8F5C"),
		colorShiftTop = Color3.fromHex("E8FFC4"),
		sunRays = 0.34,
		sunSize = 16,
		clockTime = 15.1,
	},

	-- 5 — REACTOR GROUNDS. Green going yellow, tracking the stage's own C8E85A fog.
	-- The glare is the story here: the sun is swelling and smearing through the haze,
	-- so the brightest thing in the sky is also the least legible one.
	[5] = {
		atmoColor = Color3.fromHex("DEF082"),
		atmoDecay = Color3.fromHex("9EB83C"),
		atmoDensity = 0.41,
		atmoGlare = 0.48,
		atmoHaze = 3.2,

		cloudColor = Color3.fromHex("8A9A38"),
		cloudCover = 0.72,
		cloudDensity = 0.68,

		brightness = 1.92,
		outdoorAmbient = Color3.fromHex("8A9152"),
		colorShiftTop = Color3.fromHex("F4FFA8"),
		sunRays = 0.44,
		sunSize = 18,
		clockTime = 15.5,
	},

	-- 6 — THE CRATER. Amber lid (the stage's own FFD24A fog) over violet ground
	-- (5B1FA8). Complementary, on purpose: nothing else in the game puts those two
	-- together, so the endgame field does not read as a harder version of anywhere —
	-- it reads as somewhere else. Cover stops at 0.87 rather than sealing over; PLAN
	-- §16 makes the Crater a heist, and a heist you cannot see the sun during is
	-- just a dark room.
	[6] = {
		atmoColor = Color3.fromHex("FFE49E"),
		atmoDecay = Color3.fromHex("B8742E"),
		-- 3.4 IS THE CEILING FOR THE WHOLE GAME, measured here: at 4.8 (with density
		-- 0.55) the Crater flattened into one featureless amber field — walls, ground
		-- and cloud deck all gone. Util/Spec pins it so nobody raises it for drama.
		atmoDensity = 0.46,
		atmoGlare = 0.60,
		atmoHaze = 3.4,

		-- Burnt amber, several shades DOWN from the FFE49E air above. At E9B24E — a
		-- shade UP, as the first draft had it — the deck disappeared into the sky
		-- entirely. See the header.
		cloudColor = Color3.fromHex("8A5A22"),
		cloudCover = 0.78,
		cloudDensity = 0.74,

		brightness = 1.78,
		outdoorAmbient = Color3.fromHex("9A7A48"),
		colorShiftTop = Color3.fromHex("FFD98A"),
		sunRays = 0.56,
		sunSize = 21,
		clockTime = 16.0,
	},
} :: { [number]: SkyLook }

--- The look for a stage, or the base-camp look for nil / an unskinned stage.
function Sky.get(stageId: number?): SkyLook
	if stageId == nil then
		return Sky.BASE
	end
	return Sky.LOOKS[stageId] or Sky.BASE
end

return Sky
