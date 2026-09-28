--!strict
--[[
	ItemFx.luau — what each imported nuke does once it is out of its crust: which of
	its own parts glow, go see-through or turn, and what light and particles it gives
	off.

	Config/ RULE (Tuning.luau's header): data only, no game logic, no requires of
	anything outside Config/. Shared/ItemFx tags the models; the client's
	ItemFxController reads this table and does all the work.

	THE PARTS ARE ALREADY THERE. The imported art names its effect parts (`Lens`,
	`GlowSeam`, `RiftEye`, `BottleBody`, `GhostShell`, `BeaconLamp`...), but every
	import migration forces `Material = Metal`, and every MeshPart carries a
	SurfaceAppearance that overrides material and colour alike. So they render as
	painted metal. An entry here only NAMES parts; nothing is modelled.

	PART NAMES MATCH THREE WAYS: exactly; after stripping trailing digits and
	underscores (`GlowSeam` matches all of `GlowSeam1_1`..`GlowSeam6_4`, `GimbalRing3`
	only itself); or by prefix with a trailing `*` (`Glyph1*` is rotor 1's glyphs,
	`Glyph11`..`Glyph110`, where plain `Glyph` would take all thirty). Spec checks
	every name against the live templates, so a re-import that renames a part fails
	loudly instead of quietly losing its glow.

	NEON IS ALLOWED HERE, ON REQUEST (2026-09-21) — the de-neon rule in build/Kit is
	about the world reading as paint, and the user set it aside for the loot. Bloom
	stays OFF (build/Daylight); Neon without bloom still renders as a flat,
	self-lit colour.

	NOTHING RUNS UNDER THE CRUST. The controller waits for ItemCrust.isCrusted to go
	false, so the glow switches on at the wash reveal rather than leaking through the
	rock and naming the item early.

	FIELDS
	  finish     part-look overrides. Setting `material` or `color` destroys the
	             matched parts' SurfaceAppearance (it would override both);
	             `transparency`, `reflectance`, `tint` or `ramp` alone keeps it.
	             `tint` multiplies the painted colour map (SurfaceAppearance.Color),
	             or Part.Color on a part whose paint was baked in (see
	             tools/studio-migrations/bake-nuke-texture-colours.luau), so it
	             can only darken or warm: lemon-yellow paint times a peach
	             tint reads as deep gold, but green paint can't be tinted orange.
	             `ramp` sets transparency from the level number in the name
	             (`FadePlate<N>_k`), `from` at level 1 to `to` at `levels`.
	  light      ONE PointLight. `range` is a multiple of the model's longest extent,
	             so it follows each context's display size (held, wash, exhibit, yard).
	  particles  emitters from the controller's presets: drift | sparkle | arcSpark |
	             shrinkMotes | smoke | ember | steam | spore | flame. `rate` is per
	             second; `burstEvery` (seconds) instead fires `burstCount` at once on
	             a timer and leaves the emitter idle in between. `outward` emits
	             from a point that far (times the part's size) out from the model's
	             axis instead of from the part's box: for a part flush on the shell,
	             whose particles would otherwise be born inside it and never seen.
	  anims      pulse | flash | heartbeat | blink | flicker | wink | colorCycle |
	             smoulder | glitter, each a 0..1 wave over `period` seconds, floored
	             at `min`. `light = true` also drives the light (at most one anim per
	             item may). `mode = "transparency"` fades the parts out instead of
	             dimming them; `perPart` gives each part its own random stream
	             (flicker/wink); `stagger` spreads the parts evenly across one period,
	             in name order, so a row of lamps chases instead of blinking together.
	               smoulder   a slow organic breathing, three sines at unrelated
	                          rates, each part on its own phase: coals, hot edges.
	               glitter    each part on its own timer (about every `period`)
	                          flashes toward white, or a colour picked from
	                          `colors`, for `duration`. Writes Part.Color, so the
	                          parts need a finish that sets their colour.
	             colorCycle with `mode = "tint"` cycles the SurfaceAppearance tint
	             instead of Part.Color, so the painted detail stays.
	  spins      move a group of parts about `pivot`'s centre, along the pivot's local
	             `axis`, along `axisVector` (pivot-local), or along the line from
	             `axisParts[1]` to `axisParts[2]`. The pivot may be in its own group
	             (a coin spinning on its own centre). `mode`:
	               spin    continuous at `rpm` (the default)
	               tick    `rpm`, but in `steps` jumps per turn, like a clock hand
	               swing   back and forth by `deg` over `period`, offset by `phase`
	               twitch  still, then a `deg` jerk for `duration` every ~`period`
	               bob     slides back and forth along the axis over `period`
	                       (offset by `phase`), `amp` times the pivot's own size
	                       along it each way, while still turning at `rpm` (0 by
	                       default): a core floating inside its setting.
	             `parent` (an index into this list) nests a group inside another one,
	             gimbal-style. A part joins the first group that claims it. Spins only
	             run on anchored models; a held item is welded to the hand and skips
	             them.
	  ping       an expanding ring off one part, fired once per `period`, in step
	             with a blink of the same period.
	  seam       a thin glowing band round one part at mid-height, breathing over
	             `period`. For a single-mesh model with no seam of its own to light.
	  glint      a bright vertical streak sliding across `parts` every ~`period`
	             seconds, taking `sweep` seconds per pass, on whichever side faces
	             the camera and on over the top. `color` times `strength` sets its
	             brightness: above 1 it reads as light rather than white paint. List
	             only the parts that should shine; a highlight crossing rust looks
	             wrong. `stars` spots scattered over `starParts` (or `parts`) each
	             flash a star flare as the streak crosses them.
	  bolts      jagged lightning strokes from `from`'s centre to `to`'s, each one
	             striking about every `period` seconds and crackling for `duration`
	             (re-drawn in a new zig-zag every few frames while it is lit).
	             `segments` kinks, `jitter` how far each kink strays sideways as a
	             fraction of the stroke's length. `width` is in studs at the
	             reference size. A strike also flares the item's light, if it has one.
]]

export type Finish = {
	parts: { string },
	material: string?,
	color: Color3?,
	transparency: number?,
	reflectance: number?,
	tint: Color3?,
	ramp: { from: number, to: number, levels: number }?,
}

export type Light = {
	part: string,
	color: Color3,
	brightness: number,
	range: number,
}

export type Particles = {
	part: string,
	preset: string,
	color: Color3,
	rate: number,
	burstEvery: number?,
	burstCount: number?,
	outward: number?,
}

export type Anim = {
	kind: string,
	parts: { string }?,
	light: boolean?,
	period: number,
	min: number?,
	duty: number?,
	duration: number?,
	onChance: number?,
	mode: string?,
	perPart: boolean?,
	stagger: boolean?,
	colors: { Color3 }?,
}

export type Spin = {
	parts: { string }?,
	except: { string }?,
	pivot: string,
	axis: string?,
	axisVector: Vector3?,
	axisParts: { string }?,
	mode: string?,
	rpm: number?,
	steps: number?,
	deg: number?,
	period: number?,
	phase: number?,
	duration: number?,
	amp: number?,
	parent: number?,
}

export type Ping = {
	part: string,
	color: Color3,
	period: number,
}

export type Seam = {
	part: string,
	color: Color3,
	thickness: number,
	period: number,
}

export type Glint = {
	parts: { string },
	period: number,
	sweep: number,
	color: Color3,
	strength: number,
	stars: number?,
	starParts: { string }?,
	starColor: Color3?,
	starSize: number?,
}

export type Bolt = {
	from: string,
	to: string,
	color: Color3,
	period: number,
	duration: number,
	segments: number?,
	jitter: number?,
	width: number?,
}

export type ItemFxDef = {
	finish: { Finish }?,
	light: Light?,
	particles: { Particles }?,
	anims: { Anim }?,
	spins: { Spin }?,
	ping: Ping?,
	seam: Seam?,
	glint: Glint?,
	bolts: { Bolt }?,
}

local ItemFx = {}

-- Shared palette. Rad green is the same hue family as Stage 4's ooze, pushed
-- brighter so it reads as light rather than as liquid.
local RAD_GREEN = Color3.fromHex("6BFF3A")
local SOFT_GREEN = Color3.fromHex("8DFF5A")
local CHERENKOV = Color3.fromHex("3FA9FF")

-- The imported gold is painted lemon yellow. This cream tint takes the lemon out
-- and leaves a warm gold; anything peachier reads as orange peel. The glint that
-- sweeps it is a warm white.
local GOLD_TINT = Color3.fromHex("FFE9C0")
local GLINT_GOLD = Color3.fromHex("FFF0C8")

-- Any nuke that rolled PRISTINE (Rarity.MODIFIERS) shines on top of its own effects.
-- Gold is a slow warm sweep over the gold parts only; Pristine is its opposite: an
-- icy blue-white flash across the WHOLE model, quicker and more often, with plenty
-- of cyan star flares and a few frost sparkles in the air. The cyan is the stand
-- card's Pristine sticker colour. `parts` stays empty: the controller takes every
-- visible part of the model.
ItemFx.PRISTINE = {
	glint = {
		parts = {},
		period = 2.6,
		sweep = 0.55,
		color = Color3.fromHex("DDF8FF"),
		strength = 2.6,
		stars = 8,
		starColor = Color3.fromHex("7DF9FF"),
		starSize = 0.7,
	} :: Glint,
	sparkle = { color = Color3.fromHex("BFF6FF"), rate = 2.5 },
}

ItemFx.DEFS = {
	-- Atomic Bomb (Mythic). The flavour says "still glowing, still humming", so this
	-- one leaks the light. The casing seams and nose ring breathe green, the arming
	-- ports are live amber, and the fuze tip blinks like it is counting.
	live_fuel_rod = {
		finish = {
			{ parts = { "GlowSeam", "NoseGlow", "TailCore" }, material = "Neon", color = RAD_GREEN },
			{ parts = { "ArmingPort" }, material = "Neon", color = Color3.fromHex("FFB020") },
			{ parts = { "FuzeTip" }, material = "Neon", color = Color3.fromHex("FF3B2F") },
		},
		light = { part = "Casing", color = RAD_GREEN, brightness = 1.6, range = 1.1 },
		particles = {
			{ part = "Casing", preset = "drift", color = RAD_GREEN, rate = 3 },
		},
		anims = {
			{ kind = "pulse", parts = { "GlowSeam", "NoseGlow", "TailCore", "ArmingPort" }, light = true, period = 2.2, min = 0.35 },
			{ kind = "blink", parts = { "FuzeTip" }, period = 1.0, duty = 0.18, min = 0.12 },
		},
	},

	-- Glowing Nuke. "Glows a soft green even in the dark": portholes, seams and the
	-- core stack all light up.
	glowing_sample_jar = {
		finish = {
			{ parts = { "Lens", "SeamGlow", "CoreHalo", "CoreCrown" }, material = "Neon", color = SOFT_GREEN },
		},
		light = { part = "CoreStack", color = SOFT_GREEN, brightness = 1.3, range = 1.0 },
		particles = {
			{ part = "CoreHalo", preset = "drift", color = SOFT_GREEN, rate = 2.5 },
		},
		anims = {
			{ kind = "pulse", parts = { "Lens", "SeamGlow", "CoreHalo", "CoreCrown" }, light = true, period = 3.0, min = 0.55 },
		},
	},

	-- Warped Nuke. "Spun the wrong way, hard": the shell is wrung like a towel and
	-- torn open on a rift. The rift is a dark vortex with a bright core, the cracks
	-- round it glow, and the torn-off debris circles the body.
	bent_door_wheel = {
		finish = {
			{ parts = { "Rift" }, material = "Neon", color = Color3.fromHex("2A1F8F"), transparency = 0.15 },
			{ parts = { "RiftCore" }, material = "Neon", color = Color3.fromHex("E6FBFF") },
			{ parts = { "GlowCrack" }, material = "Neon", color = Color3.fromHex("3C8CFF") },
		},
		light = { part = "RiftCore", color = Color3.fromHex("4FA8FF"), brightness = 1.5, range = 0.9 },
		particles = {
			{ part = "Rift", preset = "shrinkMotes", color = Color3.fromHex("8FD8FF"), rate = 18 },
			{ part = "TwistedShell", preset = "spore", color = Color3.fromHex("8FD8FF"), rate = 7 },
			{ part = "RiftCore", preset = "sparkle", color = Color3.fromHex("E6FBFF"), rate = 5 },
		},
		anims = {
			{ kind = "pulse", parts = { "RiftCore", "GlowCrack" }, light = true, period = 2.6, min = 0.45 },
		},
		spins = {
			{ parts = { "Debris" }, pivot = "TwistedShell", axis = "Y", rpm = -9 },
		},
	},

	-- Bottled Nuke. A corked, wax-sealed bottle with a little nuke (InnerShell,
	-- InnerFin, InnerFuze) modelled inside: the bottle goes glass so it finally shows.
	buried_coin_jar = {
		finish = {
			{
				parts = { "Bottle", "BottleBase" },
				material = "Glass",
				color = Color3.fromHex("CFE8D6"),
				transparency = 0.55,
			},
		},
		particles = {
			{ part = "Bottle", preset = "sparkle", color = Color3.fromHex("FFFFFF"), rate = 1.5 },
		},
	},

	-- Glassy Nuke. "Fused into glass": the whole shell has gone to sea-green glass,
	-- running and dripping off the fins, with bubbles trapped in it and loose shards
	-- that catch the light. None of these parts carry a SurfaceAppearance.
	glassy_ground_chip = {
		finish = {
			{
				parts = { "FusedShell", "MeltedFin", "Drip", "FinDrip" },
				material = "Glass",
				color = Color3.fromHex("5FC9BF"),
				transparency = 0.45,
			},
			{ parts = { "DripBead", "Shard" }, material = "Glass", color = Color3.fromHex("A8F0E6"), transparency = 0.3 },
			{ parts = { "Bubble" }, material = "Glass", color = Color3.fromHex("F2FFFF"), transparency = 0.35 },
		},
		particles = {
			{ part = "FusedShell", preset = "sparkle", color = Color3.fromHex("E8FFFB"), rate = 1.2 },
		},
		anims = {
			{ kind = "glitter", parts = { "Shard", "DripBead" }, period = 3.5, duration = 0.25 },
		},
	},

	-- Fading Nuke. "Went dark in under a second": the base is still solid, but the
	-- plates above it fade out row by row into ghost lines, motes drift off the top,
	-- and the dissolve edge flashes and dies away. The motes bob up and down in
	-- three out-of-step clusters as they circle, and the ghost lines turn slowly.
	cracked_glow_badge = {
		finish = {
			{ parts = { "GhostLine" }, material = "ForceField", color = Color3.fromHex("9FE8FF") },
			{ parts = { "Plate", "PlateEdge" }, ramp = { from = 0.05, to = 0.85, levels = 7 } },
			{ parts = { "Mote" }, material = "Neon", color = Color3.fromHex("CFF4FF"), transparency = 0.4 },
			{ parts = { "DissolveEdge" }, material = "Neon", color = Color3.fromHex("BDF6FF") },
		},
		light = { part = "DissolveEdge", color = Color3.fromHex("9FE8FF"), brightness = 1.8, range = 0.9 },
		anims = {
			{ kind = "flash", parts = { "DissolveEdge" }, light = true, period = 3.2, min = 0.08 },
			{
				kind = "flicker",
				parts = { "Mote" },
				period = 0.8,
				min = 0.1,
				onChance = 0.7,
				mode = "transparency",
				perPart = true,
			},
		},
		particles = {
			{ part = "DissolveEdge", preset = "drift", color = Color3.fromHex("CFF4FF"), rate = 4 },
		},
		spins = {
			{ parts = { "Mote1", "Mote4", "Mote7", "Mote10" }, pivot = "SolidBase", mode = "bob", amp = 0.14, period = 3.4, rpm = 6 },
			{ parts = { "Mote2", "Mote5", "Mote8", "Mote11" }, pivot = "SolidBase", mode = "bob", amp = 0.14, period = 4.1, phase = 0.33, rpm = -5 },
			{ parts = { "Mote3", "Mote6", "Mote9", "Mote12" }, pivot = "SolidBase", mode = "bob", amp = 0.14, period = 3.7, phase = 0.66, rpm = 8 },
			{ parts = { "GhostLine" }, pivot = "SolidBase", axis = "Y", rpm = -4 },
		},
	},

	-- Static Nuke. A Tesla coil on a warhead: a ladder arc climbs between the two
	-- electrode horns, flickering like a bad connection, the fin arcs crackle with it,
	-- and sparks fly off the horns.
	old_headphones = {
		finish = {
			{ parts = { "LadderArc", "FinArc" }, material = "Neon", color = Color3.fromHex("D8F0FF") },
			{ parts = { "SparkNode", "NodeGlow" }, material = "Neon", color = Color3.fromHex("5AA8FF") },
			{ parts = { "StaticHalo", "CoronaRing" }, material = "Neon", color = Color3.fromHex("9CCBFF"), transparency = 0.5 },
		},
		light = { part = "LadderArc1", color = Color3.fromHex("9CCBFF"), brightness = 1.6, range = 0.9 },
		particles = {
			{ part = "ElectrodeHorn1", preset = "arcSpark", color = Color3.fromHex("CFE8FF"), rate = 10 },
			{ part = "ElectrodeHorn2", preset = "arcSpark", color = Color3.fromHex("CFE8FF"), rate = 10 },
		},
		anims = {
			{
				kind = "flicker",
				parts = { "LadderArc", "FinArc" },
				light = true,
				period = 0.09,
				min = 0,
				onChance = 0.72,
				mode = "transparency",
			},
			{ kind = "pulse", parts = { "SparkNode", "NodeGlow", "StaticHalo", "CoronaRing" }, period = 1.2, min = 0.5 },
		},
	},

	-- Reactor Nuke. Painted yellow as imported; now the Cherenkov blue a real
	-- core gives off, with the whole cage slowly turning around it on the cradle.
	reactor_rod = {
		finish = {
			{ parts = { "CorePit" }, material = "Neon", color = CHERENKOV },
			{ parts = { "PitSeam" }, material = "Neon", color = Color3.fromHex("A8E4FF") },
		},
		light = { part = "CorePit", color = CHERENKOV, brightness = 1.8, range = 1.1 },
		particles = {
			{ part = "CorePit", preset = "drift", color = Color3.fromHex("8FD0FF"), rate = 2 },
		},
		anims = {
			{ kind = "pulse", parts = { "CorePit", "PitSeam" }, light = true, period = 2.6, min = 0.6 },
		},
		spins = {
			{
				except = { "CorePit", "PitSeam", "Plinth", "CradlePost", "CradleLeg", "WarningPlacard" },
				pivot = "CorePit",
				axis = "Y",
				rpm = 6,
			},
		},
	},

	-- Cosmic Nuke (Mythic). A working orrery round a little star. Each gimbal ring
	-- turns on the axis through its own pivot pair, nested outer to inner the way a
	-- real gimbal carries its rings, and each ring takes its planet, moon and tick
	-- marks with it. The dust specks circle slowly and twinkle.
	stopped_second_hand = {
		finish = {
			{ parts = { "StarCore" }, material = "Neon", color = Color3.fromHex("FFF1C4") },
			{ parts = { "CoronaSpike" }, material = "Neon", color = Color3.fromHex("FFC94A"), transparency = 0.25 },
			{ parts = { "NoseStar" }, material = "Neon", color = Color3.fromHex("FFD66B") },
			{ parts = { "Speck" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
		},
		light = { part = "StarCore", color = Color3.fromHex("FFD98A"), brightness = 1.7, range = 1.1 },
		particles = {
			{ part = "StarCore", preset = "sparkle", color = Color3.fromHex("FFE9A8"), rate = 7 },
		},
		anims = {
			{ kind = "pulse", parts = { "StarCore", "CoronaSpike", "NoseStar" }, light = true, period = 4.0, min = 0.75 },
			{
				kind = "flicker",
				parts = { "Speck" },
				period = 0.7,
				min = 0.1,
				onChance = 0.8,
				mode = "transparency",
				perPart = true,
			},
		},
		spins = {
			-- 1: the outer ring.
			{
				parts = { "GimbalRing3", "Pivot31", "Pivot32", "Tick3*", "Planet3", "MoonOrbit3", "Moon3" },
				pivot = "StarCore",
				axisParts = { "Pivot32", "Pivot31" },
				rpm = 4,
			},
			-- 2: the middle ring, carried by ring 1.
			{
				parts = { "GimbalRing2", "Pivot21", "Pivot22", "Tick2*", "Planet2", "MoonOrbit2", "Moon2" },
				pivot = "StarCore",
				axisParts = { "Pivot21", "Pivot22" },
				rpm = -7,
				parent = 1,
			},
			-- 3: the inner ring, carried by ring 2.
			{
				parts = { "GimbalRing1", "Pivot11", "Pivot12", "Tick1*", "Planet1", "MoonOrbit1", "Moon1" },
				pivot = "StarCore",
				axisParts = { "Pivot11", "Pivot12" },
				rpm = 11,
				parent = 2,
			},
			-- 4: the dust ring drifts round on its own, slow.
			{ parts = { "Speck" }, pivot = "StarCore", axis = "Y", rpm = 2.5 },
		},
	},

	-- Sky-Glow Nuke. "Lights up the crater at night all by itself": aurora ribbons
	-- cycling colour out of step with each other inside a lattice canopy, lit vane
	-- slots, a beacon on the crown mast, and the widest light in the set. The
	-- outer ribbons turn on slightly tilted axes, so each one wobbles as it goes
	-- round, and the three inner ribbons gyre round the core like a gyroscope.
	skyglow_core_fragment = {
		finish = {
			{ parts = { "AuroraCore" }, material = "Neon", color = Color3.fromHex("3FF2D0") },
			{ parts = { "AuroraRibbon", "InnerRibbon" }, material = "Neon", color = Color3.fromHex("3FF2D0") },
			{ parts = { "VaneSlot" }, material = "Neon", color = Color3.fromHex("3FF2D0"), transparency = 0.3 },
			{ parts = { "CrownBeacon" }, material = "Neon", color = Color3.fromHex("C9FFF4") },
		},
		light = { part = "AuroraCore", color = Color3.fromHex("3FF2D0"), brightness = 1.4, range = 2.0 },
		anims = {
			{
				kind = "colorCycle",
				parts = { "AuroraRibbon", "InnerRibbon" },
				period = 7,
				colors = { Color3.fromHex("3FF2D0"), Color3.fromHex("7CFF6B"), Color3.fromHex("A06BFF") },
			},
			{ kind = "pulse", parts = { "AuroraCore", "VaneSlot" }, light = true, period = 5, min = 0.6 },
			{ kind = "blink", parts = { "CrownBeacon" }, period = 2.4, duty = 0.2, min = 0.2 },
		},
		spins = {
			{ parts = { "AuroraRibbon1" }, pivot = "AuroraRibbon1", axisVector = Vector3.new(0.14, 1, 0), rpm = 7 },
			{ parts = { "AuroraRibbon2" }, pivot = "AuroraRibbon2", axisVector = Vector3.new(-0.1, 1, 0.1), rpm = -5 },
			{ parts = { "AuroraRibbon3" }, pivot = "AuroraRibbon3", axisVector = Vector3.new(0, 1, 0.14), rpm = 9 },
			{ parts = { "InnerRibbon1" }, pivot = "AuroraCore", axis = "X", rpm = 18 },
			{ parts = { "InnerRibbon2" }, pivot = "AuroraCore", axis = "Z", rpm = -14 },
			{ parts = { "InnerRibbon3" }, pivot = "AuroraCore", axisVector = Vector3.new(1, 0, 1), rpm = 22 },
		},
	},

	-- Alien Nuke. A living hull under a chitin carapace: bio-nodes with a heartbeat,
	-- glowing feeler tips, and an eye between the lids that blinks now and then.
	ufo_fragment = {
		finish = {
			{ parts = { "IrisCore" }, material = "Neon", color = Color3.fromHex("D4FF3A") },
			{ parts = { "BioNode", "FeelerTip" }, material = "Neon", color = Color3.fromHex("7DFF2F") },
		},
		light = { part = "IrisCore", color = Color3.fromHex("9CFF3A"), brightness = 1.3, range = 0.9 },
		anims = {
			{ kind = "heartbeat", parts = { "BioNode", "FeelerTip" }, light = true, period = 1.6, min = 0.35 },
			{ kind = "wink", parts = { "IrisCore" }, period = 5.5, duration = 0.12, min = 0.05 },
		},
	},

	-- Black-Box Nuke. An underwater-locator-style beacon: a short orange strobe and a
	-- sonar ring off the tip every flash, with the case's status lamps chasing.
	blackbox_recorder = {
		finish = {
			{ parts = { "BeaconTip" }, material = "Neon", color = Color3.fromHex("FF8A1F") },
			{ parts = { "StatusLamp" }, material = "Neon", color = Color3.fromHex("5CFF6A") },
		},
		light = { part = "BeaconTip", color = Color3.fromHex("FF8A1F"), brightness = 2.6, range = 1.2 },
		anims = {
			{ kind = "blink", parts = { "BeaconTip" }, light = true, period = 1.4, duty = 0.09, min = 0.08 },
			{ kind = "blink", parts = { "StatusLamp" }, period = 1.8, duty = 0.3, min = 0.2, stagger = true },
		},
		ping = { part = "BeaconTip", color = Color3.fromHex("FF9A3A"), period = 1.4 },
	},

	-- ── Shine ─────────────────────────────────────────────────────────────
	-- Gold, gems and pearls don't give off light; they catch it. So none of these
	-- carry a PointLight. They shine by a warmer finish, a glint sweeping across the
	-- polished parts, and star flares as it passes.

	-- Golden Nuke. "Gold-plated. Somebody really wanted this one to shine." A gold
	-- shell wreathed in laurel under a signet crest, with a clear orb on the nose
	-- and modelled star glints that wink as the light moves.
	gold_ring = {
		-- No gold tint: this model's baked gold is already warm.
		finish = {
			{ parts = { "NoseOrb" }, material = "Glass", color = Color3.fromHex("F2FAFF"), transparency = 0.15 },
		},
		anims = {
			{ kind = "glitter", parts = { "NoseOrb" }, period = 1.8, duration = 0.3 },
			{
				kind = "wink",
				parts = { "GlintH", "GlintV" },
				period = 1.6,
				min = 0,
				mode = "transparency",
				perPart = true,
			},
		},
		glint = {
			parts = { "Shell", "FineBand", "Laurel", "SignetBezel" },
			period = 4.5,
			sweep = 0.9,
			color = GLINT_GOLD,
			strength = 2.6,
			stars = 5,
		},
	},

	-- Gilded Nuke. "Gold doesn't care what it's welded to." A fluted gold egg under a
	-- crown, rubies set round its waist: the most ornate gold of the set, so the
	-- rubies glitter red and the glint throws its stars off the crown points.
	gold_signet = {
		finish = {
			{
				parts = {
					"Shell",
					"Flute",
					"Fin",
					"FinScroll",
					"FiligreeBand",
					"CrownBand",
					"CrownArch",
					"CrownPoint",
					"GemSetting",
				},
				tint = GOLD_TINT,
			},
			{ parts = { "Ruby" }, material = "Glass", color = Color3.fromHex("B0102C"), transparency = 0.1 },
		},
		anims = {
			{
				kind = "glitter",
				parts = { "Ruby" },
				period = 2.2,
				duration = 0.3,
				colors = { Color3.fromHex("FF8A9C") },
			},
		},
		glint = {
			parts = { "Shell", "Flute", "FiligreeBand", "CrownBand" },
			period = 5,
			sweep = 0.9,
			color = GLINT_GOLD,
			strength = 2.6,
			stars = 4,
			starParts = { "Ruby", "CrownPoint" },
		},
	},

	-- Bullion Nuke (Epic). "Cast in gold. Somebody got greedy." A faceted gold shell
	-- on a heap of ingots, coins and a nugget -- the most gold of the set, so the
	-- strongest and most frequent glint.
	bullion_bar = {
		finish = {
			{
				parts = { "FacetedShell", "Ingot", "Coin", "GoldNugget", "FinialCollar", "Fin", "Buckle" },
				tint = GOLD_TINT,
			},
		},
		particles = {
			{ part = "GoldNugget", preset = "sparkle", color = Color3.fromHex("FFE7A6"), rate = 1.2 },
		},
		glint = {
			parts = { "FacetedShell", "Ingot", "Coin" },
			period = 3.6,
			sweep = 0.8,
			color = GLINT_GOLD,
			strength = 3,
			stars = 7,
		},
	},

	-- Diamond Nuke (Epic). "Catches light nobody else out here can see." One big
	-- brilliant in a pronged cup, ringed with small stones: the brilliant goes clear
	-- so the shards inside show, its kite facets and the small stones throw white and
	-- the odd flash of rainbow fire, and the modelled star glints wink. The core
	-- ball inside floats up and down, turning, with its two orbit rings gyring
	-- round it and the loose shards circling.
	diamond_brooch = {
		finish = {
			{ parts = { "InnerCore" }, material = "Neon", color = Color3.fromHex("CFF3FF"), transparency = 0.1 },
			{
				parts = { "BrilliantBody" },
				material = "Glass",
				color = Color3.fromHex("DDF2FF"),
				transparency = 0.45,
			},
			{
				parts = { "KiteA", "KiteB", "HaloStone", "GirdleStone", "ChannelStone", "FinStone" },
				material = "Glass",
				color = Color3.fromHex("E6F6FF"),
				transparency = 0.3,
			},
		},
		light = { part = "InnerCore", color = Color3.fromHex("BFEFFF"), brightness = 0.9, range = 0.8 },
		particles = {
			{ part = "BrilliantBody", preset = "sparkle", color = Color3.fromHex("FFFFFF"), rate = 1.5 },
		},
		spins = {
			{ parts = { "InnerCore", "CoreSpark" }, pivot = "InnerCore", mode = "bob", amp = 0.22, period = 3.2, rpm = 20 },
			{ parts = { "CoreOrbit1" }, pivot = "InnerCore", axis = "X", rpm = 22, parent = 1 },
			{ parts = { "CoreOrbit2" }, pivot = "InnerCore", axis = "Z", rpm = -16, parent = 1 },
			{ parts = { "CoreShard" }, pivot = "InnerCore", axis = "Y", rpm = -12, parent = 1 },
		},
		anims = {
			{ kind = "pulse", parts = { "InnerCore" }, light = true, period = 3.2, min = 0.55 },
			{
				kind = "glitter",
				parts = { "KiteA", "KiteB", "HaloStone", "GirdleStone", "ChannelStone", "FinStone" },
				period = 5,
				duration = 0.22,
				colors = {
					Color3.fromHex("FFFFFF"),
					Color3.fromHex("FFFFFF"),
					Color3.fromHex("FFFFFF"),
					Color3.fromHex("B8F4FF"),
					Color3.fromHex("FFD2F4"),
					Color3.fromHex("FFF2A8"),
				},
			},
			{
				kind = "wink",
				parts = { "GlintH", "GlintV" },
				period = 1.6,
				min = 0,
				mode = "transparency",
				perPart = true,
			},
		},
		glint = {
			parts = { "BrilliantBody", "TableEdge", "CrownEdge" },
			period = 4,
			sweep = 0.7,
			color = Color3.fromHex("F4FBFF"),
			strength = 2.6,
			stars = 6,
			starParts = { "KiteA", "KiteB", "HaloStone" },
		},
	},

	-- Pearl Nuke. "Strung with pearls, saved for good occasions." A pearl egg sitting
	-- in an open clam, a strand swagged round it. Pearls have a soft lustre, not a
	-- hard glint: a gentle band over the cream shell, and a pastel sheen that runs
	-- round the strand.
	pearl_necklace = {
		-- Warm on purpose: the sky's cyan fill turns anything near-white grey-blue,
		-- and a lilac or mint tint reads as a blue pearl.
		finish = {
			{ parts = { "Shell", "Fin", "FinEdge" }, tint = Color3.fromHex("FFE4CC") },
		},
		-- These pearls are plain parts (no SurfaceAppearance), so the sheen cycles
		-- Part.Color directly rather than a tint.
		anims = {
			{
				kind = "colorCycle",
				parts = { "StrandPearl", "CrownPearl" },
				period = 6,
				colors = {
					Color3.fromHex("FFF6EA"),
					Color3.fromHex("FFE4E8"),
					Color3.fromHex("FFEFD9"),
					Color3.fromHex("F6E9FF"),
				},
			},
		},
		glint = {
			parts = { "Shell", "ClamUpper" },
			period = 5,
			sweep = 1.1,
			color = Color3.fromHex("FFF4F0"),
			strength = 2,
			stars = 5,
			starParts = { "StrandPearl", "CrownPearl" },
			starColor = Color3.fromHex("FFEAF4"),
			starSize = 0.4,
		},
	},

	-- ── Heat ──────────────────────────────────────────────────────────────

	-- Exposed Nuke. The casing has been peeled open on its hinges and the core
	-- canister stands bare inside a ribbed frame, so nothing holds the current in:
	-- the canister's bands chase green, the sculpted arcs round it flicker, and
	-- real bolts jump from the canister to the frame. The two orbit rings wheel
	-- round it in opposite directions, the loose bolts drift round it, the
	-- peeled panels flap on their hinges, and the gauges' needles can't settle.
	film_canister = {
		finish = {
			{ parts = { "CanisterGlow" }, material = "Neon", color = Color3.fromHex("33FF55") },
			{ parts = { "Arc" }, material = "Neon", color = Color3.fromHex("C4FF9A") },
			{ parts = { "GlowPool" }, material = "Neon", color = Color3.fromHex("33FF55"), transparency = 0.6 },
			{ parts = { "TopLamp" }, material = "Neon", color = Color3.fromHex("FF3B2F") },
		},
		light = { part = "Canister", color = Color3.fromHex("33FF55"), brightness = 2, range = 1.2 },
		particles = {
			{ part = "Canister", preset = "drift", color = SOFT_GREEN, rate = 2 },
			{ part = "Arc1", preset = "arcSpark", color = Color3.fromHex("C4FF9A"), rate = 4 },
			{ part = "Arc3", preset = "arcSpark", color = Color3.fromHex("C4FF9A"), rate = 3 },
			{
				part = "CoolantLoop",
				preset = "steam",
				color = Color3.fromHex("DCE8E0"),
				rate = 0,
				burstEvery = 4.5,
				burstCount = 6,
			},
		},
		anims = {
			{ kind = "pulse", parts = { "CanisterGlow", "GlowPool" }, light = true, period = 1.8, min = 0.45, stagger = true },
			{ kind = "flicker", parts = { "Arc" }, period = 0.12, min = 0.2, perPart = true },
			{ kind = "blink", parts = { "TopLamp" }, period = 1.2, duty = 0.2, min = 0.1 },
		},
		spins = {
			{ parts = { "OrbitRing1" }, pivot = "Canister", axis = "Y", rpm = 22 },
			{ parts = { "OrbitRing2" }, pivot = "Canister", axis = "Y", rpm = -15 },
			{ parts = { "LooseBolt" }, pivot = "Canister", axis = "Y", mode = "bob", amp = 0.06, period = 3.2, rpm = 7 },
			{ parts = { "PanelSkin1", "PanelHinge1" }, pivot = "PanelHinge1", axis = "Y", mode = "swing", deg = 6, period = 3.1 },
			{ parts = { "PanelSkin2", "PanelHinge2" }, pivot = "PanelHinge2", axis = "Y", mode = "swing", deg = 5, period = 3.7, phase = 0.4 },
			{ parts = { "PanelSkin3", "PanelHinge3" }, pivot = "PanelHinge3", axis = "Y", mode = "swing", deg = 6, period = 2.8, phase = 0.7 },
			{ parts = { "GaugeNeedle1" }, pivot = "Gauge1", axis = "X", mode = "twitch", deg = 35, period = 1.6, duration = 0.2 },
			{ parts = { "GaugeNeedle2" }, pivot = "Gauge2", axis = "X", mode = "swing", deg = 30, period = 1.3 },
		},
		bolts = {
			{ from = "CanisterGlow2", to = "FrameRib3", color = Color3.fromHex("B8FF8A"), period = 2.2, duration = 0.18 },
			{ from = "CanisterGlow3", to = "FrameRib7", color = Color3.fromHex("B8FF8A"), period = 2.8, duration = 0.18 },
			{ from = "CanisterGlow1", to = "FrameRib5", color = Color3.fromHex("B8FF8A"), period = 3.4, duration = 0.15 },
		},
	},

	-- Ignition Nuke. "Pulled from a car pointed away from town." A hot-rod coil
	-- nuke with its ignition live: the four spark plugs throw blue lightning up to
	-- the distributor and the whirling spark ring on top, the coil pack surges and
	-- bolts to the cap, every strike flares the light, the exhausts burn, the
	-- tachometer's needle revs and the start button blinks.
	ignition_coil = {
		finish = {
			{ parts = { "Arc" }, material = "Neon", color = Color3.fromHex("9FDBFF") },
			{ parts = { "SparkHalo" }, material = "Neon", color = Color3.fromHex("3FA9FF"), transparency = 0.3 },
			{ parts = { "SparkBead" }, material = "Neon", color = Color3.fromHex("E6F6FF") },
			{ parts = { "CoilWinding" }, material = "Neon", color = Color3.fromHex("3FA9FF") },
			{ parts = { "ExhaustFlame" }, material = "Neon", color = Color3.fromHex("FF7A1A"), transparency = 0.35 },
			{ parts = { "ExhaustCore" }, material = "Neon", color = Color3.fromHex("FFE08A") },
			{ parts = { "StartButton", "TachRedline" }, material = "Neon", color = Color3.fromHex("FF3B2F") },
		},
		light = { part = "DistributorCap", color = Color3.fromHex("7FC8FF"), brightness = 1.2, range = 1.2 },
		particles = {
			{ part = "Arc1", preset = "arcSpark", color = Color3.fromHex("9FDBFF"), rate = 5 },
			{ part = "Arc2", preset = "arcSpark", color = Color3.fromHex("9FDBFF"), rate = 5 },
			{ part = "Arc3", preset = "arcSpark", color = Color3.fromHex("9FDBFF"), rate = 5 },
			{ part = "Arc4", preset = "arcSpark", color = Color3.fromHex("9FDBFF"), rate = 5 },
			{ part = "SparkHalo", preset = "sparkle", color = Color3.fromHex("E6F6FF"), rate = 4 },
			{ part = "ExhaustTip1", preset = "smoke", color = Color3.fromHex("6E7074"), rate = 1.5 },
			{ part = "ExhaustTip2", preset = "smoke", color = Color3.fromHex("6E7074"), rate = 1.5 },
		},
		anims = {
			{ kind = "pulse", parts = { "SparkHalo", "SparkBead" }, light = true, period = 0.9, min = 0.35 },
			{ kind = "flicker", parts = { "Arc" }, period = 0.1, min = 0.15, perPart = true },
			{ kind = "pulse", parts = { "CoilWinding" }, period = 0.6, min = 0.3 },
			{ kind = "flicker", parts = { "ExhaustFlame", "ExhaustCore" }, period = 0.08, min = 0.5, perPart = true },
			{ kind = "blink", parts = { "StartButton" }, period = 1.4, duty = 0.3, min = 0.15 },
		},
		spins = {
			{ parts = { "SparkBead" }, pivot = "SparkHalo", axis = "Y", rpm = 45 },
			{ parts = { "TachNeedle" }, pivot = "Tachometer", axisVector = Vector3.new(-0.79, 0, -0.61), mode = "swing", deg = 35, period = 1.1 },
		},
		bolts = {
			{ from = "Arc1", to = "CenterTower", color = Color3.fromHex("7FC8FF"), period = 1.6, duration = 0.16 },
			{ from = "Arc2", to = "SparkBead3", color = Color3.fromHex("7FC8FF"), period = 1.9, duration = 0.14 },
			{ from = "Arc3", to = "CenterTower", color = Color3.fromHex("7FC8FF"), period = 1.7, duration = 0.16 },
			{ from = "Arc4", to = "SparkBead6", color = Color3.fromHex("7FC8FF"), period = 2.1, duration = 0.14 },
			{ from = "CoilTerminal", to = "LeadTower3", color = Color3.fromHex("A8E0FF"), period = 2.6, duration = 0.2, width = 0.09 },
		},
	},

	-- Scorched Nuke. "Rated to hold back anything. Didn't." Still burning: the ember
	-- cracks breathe like coals, the burnt fuze smoulders at the top with small
	-- flames licking off it, and smoke and sparks rise. A Common, so it smoulders;
	-- no bonfire. The soot and blisters stay dark.
	scorched_metal_plate = {
		finish = {
			{ parts = { "EmberCrack", "FuzeEmber" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
		},
		light = { part = "EmberCrack2", color = Color3.fromHex("FF7A2A"), brightness = 1.3, range = 0.9 },
		particles = {
			{ part = "FuzeEmber", preset = "flame", color = Color3.fromHex("FF8A2A"), rate = 18, outward = 0.35 },
			{
				part = "EmberCrack3",
				preset = "flame",
				color = Color3.fromHex("FF7A22"),
				rate = 0,
				burstEvery = 2.5,
				burstCount = 5,
				outward = 0.4,
			},
			{ part = "EmberCrack1", preset = "ember", color = Color3.fromHex("FFA040"), rate = 3, outward = 0.4 },
			{ part = "BurntFuze", preset = "smoke", color = Color3.fromHex("2E2724"), rate = 1.5, outward = 0.35 },
		},
		anims = {
			{ kind = "smoulder", parts = { "EmberCrack", "FuzeEmber" }, light = true, period = 1.6, min = 0.35 },
		},
	},

	-- Core Nuke (Legendary). "Warm through three layers of metal. Never once cooled."
	-- A shielded cask on a pedestal over a glowing pit, lid hoisted off: the pit
	-- breathes amber like a coal, the coolant risers pulse up one after the other, and
	-- three orbit rings turn round the cask at their own speeds. Embers rise off the
	-- pit. Amber, not the Reactor Nuke's Cherenkov blue or the Scorched Nuke's fire.
	reactor_core_sample = {
		finish = {
			{ parts = { "Pit" }, material = "Neon", color = Color3.fromHex("FFB454") },
			{ parts = { "PitSeam" }, material = "Neon", color = Color3.fromHex("FF7A2E") },
			{ parts = { "RiserGlow" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
		},
		light = { part = "Pit", color = Color3.fromHex("FF9A4A"), brightness = 1.9, range = 1.1 },
		particles = {
			{ part = "Pit", preset = "ember", color = Color3.fromHex("FFB454"), rate = 3 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Pit", "PitSeam" }, light = true, period = 2.4, min = 0.55 },
			{ kind = "pulse", parts = { "RiserGlow" }, stagger = true, period = 3.6, min = 0.3 },
		},
		spins = {
			{ parts = { "OrbitRing1" }, pivot = "Cask", axis = "Y", rpm = 5 },
			{ parts = { "OrbitRing2" }, pivot = "Cask", axis = "Y", rpm = -8 },
			{ parts = { "OrbitRing3" }, pivot = "Cask", axis = "Y", rpm = 12 },
		},
	},
	-- ── Batch 13 newcomers ───────────────────────────────────────────────

	-- Booster Nuke (Mythic). Four strap-on boosters round the core: the engine bells
	-- still hold a dull glow, the emblem on the flank pulses, and the porthole is
	-- clear glass with nobody behind it.
	booster_rocket = {
		finish = {
			{
				parts = { "EngineGlow", "NozzleGlow", "BoosterGlow", "BoosterBellGlow" },
				material = "Neon",
				color = Color3.fromHex("FF7A2A"),
			},
			{ parts = { "EmblemCore" }, material = "Neon", color = RAD_GREEN },
			{ parts = { "PortholeGlass" }, material = "Glass", color = Color3.fromHex("BFE6FF"), transparency = 0.4 },
		},
		light = { part = "EngineGlow", color = Color3.fromHex("FF8A3A"), brightness = 1.4, range = 1.0 },
		anims = {
			{
				kind = "smoulder",
				parts = { "EngineGlow", "NozzleGlow", "BoosterGlow", "BoosterBellGlow" },
				light = true,
				period = 2.2,
				min = 0.4,
			},
			{ kind = "pulse", parts = { "EmblemCore" }, period = 2.8, min = 0.4 },
		},
	},

	-- The Big One (Anomaly). A black monolith hovering over a cracked ground plate:
	-- the glow under it breathes, the cracks answer it, and a ring of debris orbits
	-- the slab on a faint trace.
	unlabeled_cylinder = {
		finish = {
			{ parts = { "HoverGlow" }, material = "Neon", color = Color3.fromHex("B46BFF") },
			{ parts = { "GroundCrack" }, material = "Neon", color = Color3.fromHex("7A3CFF") },
			{ parts = { "OrbitTrace" }, material = "Neon", color = Color3.fromHex("D9C2FF"), transparency = 0.6 },
		},
		light = { part = "HoverGlow", color = Color3.fromHex("A45CFF"), brightness = 2, range = 1.3 },
		particles = {
			{ part = "HoverGlow", preset = "shrinkMotes", color = Color3.fromHex("D2B0FF"), rate = 6 },
		},
		anims = {
			{ kind = "pulse", parts = { "HoverGlow", "GroundCrack" }, light = true, period = 3.8, min = 0.4 },
		},
		spins = {
			{ parts = { "OrbitDebris", "OrbitTrace" }, pivot = "Monolith", axis = "Y", rpm = 6 },
		},
	},
	-- ── Motion + shine pass ──────────────────────────────────────────────

	-- Rusty Nuke (Common). "Rusted solid": the whole shell goes to corroded metal,
	-- the bands and fins a darker, flakier brown, and the modelled corrosion
	-- patches a raw orange so they read as fresh rust breaking through.
	steel_rod = {
		finish = {
			{ parts = { "Shell", "TailTaper" }, material = "CorrodedMetal", color = Color3.fromHex("9A4A22") },
			{
				parts = { "HoopBand", "EquatorSeam", "Fin", "TailCap", "TailShroud", "ShroudFloor" },
				material = "CorrodedMetal",
				color = Color3.fromHex("5C2E17"),
			},
			{ parts = { "Corrosion" }, material = "CorrodedMetal", color = Color3.fromHex("C8621F") },
		},
	},

	-- Lucky Nuke. A four-leaf clover plate and a horseshoe on a gold-banded shell:
	-- the gold catches a sweeping glint with star flares, the clover leaves go a
	-- polished emerald that glitters, and green-and-gold sparkles hang round it.
	rusty_horseshoe = {
		finish = {
			{ parts = { "Horseshoe", "GoldBand", "CloverPlate", "FinTip" }, reflectance = 0.3 },
			{ parts = { "CloverLeaf", "CloverStem" }, color = Color3.fromHex("2FC24E"), reflectance = 0.25 },
		},
		light = { part = "CloverPlate", color = Color3.fromHex("9CFF8A"), brightness = 0.9, range = 0.8 },
		particles = {
			{ part = "Shell", preset = "sparkle", color = Color3.fromHex("FFE9A0"), rate = 3 },
			{ part = "CloverPlate", preset = "sparkle", color = Color3.fromHex("8CFF7A"), rate = 3 },
		},
		anims = {
			{
				kind = "glitter",
				parts = { "CloverLeaf" },
				period = 2.2,
				duration = 0.25,
				colors = { Color3.fromHex("FFFFFF"), Color3.fromHex("C8FFB0"), Color3.fromHex("FFF2A8") },
			},
		},
		glint = {
			parts = { "Horseshoe", "GoldBand", "CloverPlate", "Shell" },
			period = 3.5,
			sweep = 0.7,
			color = GLINT_GOLD,
			strength = 2.4,
			stars = 6,
			starParts = { "Horseshoe", "GoldBand", "CloverPlate" },
		},
	},

	-- Flare Nuke. "Never got its chance to light up the sky", but it's trying: the
	-- flame twists on the burn port, sparks circle it rising and falling, and the
	-- pull cord sways from the firing cap.
	unlit_signal_flare = {
		finish = {
			{ parts = { "Spark" }, material = "Neon", color = Color3.fromHex("FFC04A") },
		},
		light = { part = "FlameCore", color = Color3.fromHex("FF9A3A"), brightness = 1.1, range = 0.9 },
		particles = {
			{ part = "FlameCore", preset = "ember", color = Color3.fromHex("FFB347"), rate = 5 },
		},
		anims = {
			{ kind = "flicker", parts = { "Spark" }, light = true, period = 0.3, min = 0.35, perPart = true },
		},
		spins = {
			{ parts = { "Spark" }, pivot = "FlameCore", mode = "bob", amp = 0.25, period = 1.8, rpm = 30 },
			{ parts = { "FlameCore" }, pivot = "FlameCore", axis = "Y", rpm = 40 },
			{ parts = { "FlameOuter" }, pivot = "FlameCore", axis = "Y", rpm = -25 },
			{ parts = { "PullCord", "PullRing" }, pivot = "FiringCap", axis = "X", mode = "swing", deg = 9, period = 2.4 },
		},
	},

	-- Mutant Nuke. Infected: glowing pustules and veins on a heartbeat, the root
	-- tendrils writhing at the base, the growths twitching, and ooze dripping off
	-- the shoulders.
	mutant_carrot = {
		finish = {
			{ parts = { "Pustule*" }, material = "Neon", color = Color3.fromHex("9BFF3A") },
			{ parts = { "Vein" }, material = "Neon", color = Color3.fromHex("4CD62A"), transparency = 0.25 },
			{ parts = { "Drip", "OozeCap" }, material = "Neon", color = RAD_GREEN, transparency = 0.15 },
		},
		light = { part = "Shell", color = RAD_GREEN, brightness = 1.2, range = 1.0 },
		particles = {
			{ part = "OozeCap", preset = "spore", color = SOFT_GREEN, rate = 3 },
			{ part = "Shell", preset = "spore", color = RAD_GREEN, rate = 2 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "Pustule*", "Vein" }, light = true, period = 1.4, min = 0.35 },
		},
		spins = {
			{ parts = { "Tendril1" }, pivot = "Tendril1", axis = "X", mode = "swing", deg = 7, period = 2.6 },
			{ parts = { "Tendril2" }, pivot = "Tendril2", axis = "Z", mode = "swing", deg = 7, period = 3.1, phase = 0.3 },
			{ parts = { "Tendril3" }, pivot = "Tendril3", axis = "X", mode = "swing", deg = 6, period = 2.2, phase = 0.6 },
			{ parts = { "Growth1", "Pustule1*" }, pivot = "Growth1", axis = "Z", mode = "twitch", deg = 8, period = 2.5, duration = 0.15 },
			{ parts = { "Growth3", "Pustule3*" }, pivot = "Growth3", axis = "X", mode = "twitch", deg = 8, period = 3, duration = 0.15 },
			{ parts = { "Growth4", "Pustule4*" }, pivot = "Growth4", axis = "Z", mode = "twitch", deg = -8, period = 2.8, duration = 0.15 },
			{ parts = { "Drip" }, pivot = "Drip1", mode = "bob", amp = 0.35, period = 1.8 },
		},
	},
	-- ── Batch 14 ─────────────────────────────────────────────────────────

	-- Prototype Nuke (Stage 1 Legendary). A test rig nobody switched off: the
	-- sample orb floats in its window with three gimbal rings tumbling round it,
	-- the hex cells orbit the shell, rising and falling, the field coils and hex
	-- cells chase with charge, the test rings turn, sparks
	-- jump off the arcs and the tip lens pings like it is still transmitting.
	prototype_nuke = {
		finish = {
			{ parts = { "Orb" }, material = "Neon", color = Color3.fromHex("7FF7FF") },
			{ parts = { "OrbRing" }, material = "Neon", color = Color3.fromHex("C8FBFF"), transparency = 0.3 },
			{ parts = { "Coil", "Hex", "NozzleGlow", "TipLens", "Lamp" }, material = "Neon", color = Color3.fromHex("3CE6F5") },
			{ parts = { "Spark" }, material = "Neon", color = Color3.fromHex("E6FDFF") },
			{ parts = { "Screen" }, material = "Neon", color = Color3.fromHex("5BFFB0") },
			{ parts = { "PanelLamp" }, material = "Neon", color = Color3.fromHex("FFB43A") },
			{ parts = { "WindowBack" }, material = "Glass", color = Color3.fromHex("9FE9FF"), transparency = 0.5 },
		},
		light = { part = "Orb", color = Color3.fromHex("6FEFFF"), brightness = 1.6, range = 1.0 },
		particles = {
			{ part = "Spark1", preset = "arcSpark", color = Color3.fromHex("CFFBFF"), rate = 8 },
			{ part = "Spark3", preset = "arcSpark", color = Color3.fromHex("CFFBFF"), rate = 8 },
			{ part = "NozzleGlow", preset = "drift", color = Color3.fromHex("8FF3FF"), rate = 2 },
		},
		anims = {
			{ kind = "pulse", parts = { "Orb", "OrbRing" }, light = true, period = 2.4, min = 0.55 },
			{ kind = "pulse", parts = { "Coil", "Hex", "NozzleGlow" }, period = 1.6, min = 0.35, stagger = true },
			{ kind = "flicker", parts = { "Spark" }, period = 0.1, min = 0, onChance = 0.6, mode = "transparency", perPart = true },
			{ kind = "flicker", parts = { "Screen" }, period = 0.25, min = 0.6 },
			{ kind = "blink", parts = { "PanelLamp", "Lamp", "TipLens" }, period = 1.2, min = 0.2, stagger = true },
		},
		spins = {
			{ parts = { "Orb" }, pivot = "Orb", mode = "bob", amp = 0.12, period = 2.4, rpm = 12 },
			{ parts = { "OrbRing1" }, pivot = "Orb", axis = "Y", rpm = 40 },
			{ parts = { "OrbRing2" }, pivot = "Orb", axis = "X", rpm = -30 },
			{ parts = { "OrbRing3" }, pivot = "Orb", axis = "Z", rpm = 24 },
			{ parts = { "Ring3" }, pivot = "Shell", axis = "Y", rpm = 14 },
			{ parts = { "Ring2" }, pivot = "Shell", axis = "Y", rpm = -10 },
			-- The ten hex cells orbit the shell, rising and falling as they go.
			{ parts = { "Hex", "HexEdge" }, pivot = "Shell", axis = "Y", mode = "bob", amp = 0.04, period = 3.2, rpm = 8 },
		},
		ping = { part = "TipLens", color = Color3.fromHex("7FF7FF"), period = 2.4 },
	},

	-- Humming Nuke (Stage 4 Epic). "Hums if you hold it": the tuning fork on top
	-- rings (its echo lines shimmer and a tone ring pings off it), the sine
	-- ribbons round the shell ripple past each other, the speaker cone pumps, the
	-- coil windings turn in their drums and the VU meter dances.
	strange_metal_chip = {
		finish = {
			{ parts = { "ForkEcho", "ToneRing" }, material = "Neon", color = Color3.fromHex("8FF0FF"), transparency = 0.2 },
			{ parts = { "SineRibbon" }, material = "Neon", color = Color3.fromHex("59D8EF"), transparency = 0.25 },
			{ parts = { "VUBar", "BushingTip", "SpeakerDome" }, material = "Neon", color = Color3.fromHex("6BF3FF") },
		},
		light = { part = "ForkBase", color = Color3.fromHex("7FE8FF"), brightness = 1.2, range = 0.9 },
		particles = {
			{ part = "ForkBow", preset = "shrinkMotes", color = Color3.fromHex("BFF6FF"), rate = 4 },
		},
		anims = {
			{ kind = "flicker", parts = { "ForkEcho" }, period = 0.06, min = 0, onChance = 0.7, mode = "transparency", perPart = true },
			{ kind = "pulse", parts = { "ToneRing", "SineRibbon" }, light = true, period = 1.1, min = 0.4, stagger = true },
			{ kind = "flicker", parts = { "VUBar" }, period = 0.12, min = 0, onChance = 0.65, mode = "transparency", perPart = true },
			{ kind = "blink", parts = { "BushingTip" }, period = 0.9, min = 0.2, stagger = true },
		},
		spins = {
			{ parts = { "ForkProng", "ForkEcho" }, pivot = "ForkStem", axis = "Y", mode = "twitch", deg = 4, period = 0.4, duration = 0.05 },
			{ parts = { "ToneRing" }, pivot = "ForkBase", axis = "Y", rpm = 30 },
			{ parts = { "SineRibbon1", "SineRibbon3" }, pivot = "Shell", axis = "Y", rpm = 12 },
			{ parts = { "SineRibbon2" }, pivot = "Shell", axis = "Y", rpm = -16 },
			{ parts = { "SpeakerCone", "SpeakerDome" }, pivot = "SpeakerRim", axisVector = Vector3.new(0.5, 0, 0.87), mode = "bob", amp = 0.08, period = 0.35 },
			{ parts = { "CoilWinding1" }, pivot = "CoilDrum1", axis = "Y", rpm = 45 },
			{ parts = { "CoilWinding2" }, pivot = "CoilDrum2", axis = "Y", rpm = -45 },
		},
		ping = { part = "ToneRing1", color = Color3.fromHex("9FF4FF"), period = 1.1 },
	},

	-- Polished Nuke (Stage 5 Common). "Mirror-bright": the shell and bands go
	-- glossy, a white highlight sweeps them with star flares, the nose orb
	-- glitters and the modelled glint crosses wink in and out.
	shiny_metal_blade = {
		finish = {
			{ parts = { "Shell", "Fin" }, reflectance = 0.35 },
			{ parts = { "BrightBand", "TailCap", "NoseOrb" }, color = Color3.fromHex("E8EDF2"), reflectance = 0.5 },
			{ parts = { "GlintH", "GlintV" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
		},
		particles = {
			{ part = "Shell", preset = "sparkle", color = Color3.fromHex("F4F8FF"), rate = 2 },
		},
		anims = {
			{ kind = "glitter", parts = { "NoseOrb", "BrightBand" }, period = 2.4, duration = 0.25 },
			{ kind = "wink", parts = { "GlintH", "GlintV" }, period = 1.8, min = 0, mode = "transparency", perPart = true },
		},
		glint = {
			parts = { "Shell", "BrightBand", "NoseOrb", "TailCap", "Fin" },
			period = 3.5,
			sweep = 0.8,
			color = Color3.fromHex("FFFFFF"),
			strength = 2.6,
			stars = 5,
		},
	},

	-- Pristine Nuke (Stage 6 Epic). "Not a scratch on it": a showroom piece on its
	-- velvet plinth. Chrome rings and nose mirror-bright, a slow highlight
	-- sweeps the whole shell throwing star flares, the foil seal and nose bead
	-- glitter gold and white, and a few sparkles hang in the air round it.
	untouched_ground_sample = {
		finish = {
			{ parts = { "Shell" }, reflectance = 0.3 },
			{ parts = { "ChromeRing", "NoseTip", "NoseBead", "MountCup", "TailCap" }, color = Color3.fromHex("EEF2F6"), reflectance = 0.55 },
			{ parts = { "FoilSeal", "PlinthRim" }, color = Color3.fromHex("D9B45A"), reflectance = 0.4 },
			{ parts = { "GlintH", "GlintV" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
		},
		light = { part = "NoseTip", color = Color3.fromHex("F4F8FF"), brightness = 0.6, range = 0.8 },
		particles = {
			{ part = "Shell", preset = "sparkle", color = Color3.fromHex("FFFFFF"), rate = 3 },
			{ part = "VelvetTop", preset = "sparkle", color = Color3.fromHex("FFE9A8"), rate = 1 },
		},
		anims = {
			{
				kind = "glitter",
				parts = { "NoseBead", "FoilSeal", "ChromeRing" },
				period = 2,
				duration = 0.3,
				colors = { Color3.fromHex("FFFFFF"), Color3.fromHex("FFF2C0") },
			},
			{ kind = "wink", parts = { "GlintH", "GlintV" }, period = 1.6, min = 0, mode = "transparency", perPart = true },
		},
		glint = {
			parts = { "Shell", "ChromeRing", "NoseTip", "FoilSeal" },
			period = 4,
			sweep = 1,
			color = Color3.fromHex("FFFFFF"),
			strength = 2.8,
			stars = 6,
			starParts = { "Shell", "ChromeRing", "NoseTip" },
		},
	},
} :: { [string]: ItemFxDef }

--- The same effects on a supply crate's imported model (Assets.CrateTemplates), keyed
--- `crate_<crateId>`. Kept apart from DEFS: Spec checks every DEFS key is a nuke.
--- Shared/CrateFx tags the crate; ItemFxController runs it like any item.
ItemFx.CRATE_DEFS = {
	-- Void: the core turns inside its glass dome, the two rings orbit it in opposite
	-- directions, and the shards drift up and down round it.
	crate_nuke3 = {
		spins = {
			{ parts = { "void_core", "core_shell" }, pivot = "void_core", axis = "Y", rpm = 18 },
			{ parts = { "orbit_ring_1" }, pivot = "void_core", axis = "Y", rpm = 30 },
			{ parts = { "orbit_ring_2" }, pivot = "void_core", axis = "Y", rpm = -22 },
			{ parts = { "floating_shard_1", "floating_shard_3", "floating_shard_5" }, pivot = "void_core", mode = "bob", amp = 0.6, period = 3.2, rpm = 12 },
			{ parts = { "floating_shard_2", "floating_shard_4" }, pivot = "void_core", mode = "bob", amp = 0.6, period = 3.8, phase = 0.5, rpm = -10 },
		},
	},
} :: { [string]: ItemFxDef }

return ItemFx
