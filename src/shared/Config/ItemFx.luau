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

	-- ── STAGE 7: CINDER FIELDS (batch 16) ──────────────────────────────────────

	-- Ashen Nuke. Burnt to its shell: embers smoulder under the ash, flakes drift off.
	ashen_nuke = {
		finish = {
			{ parts = { "Ember" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
		},
		light = { part = "Shell", color = Color3.fromHex("FF7A2A"), brightness = 0.8, range = 0.8 },
		particles = {
			{ part = "AshCap", preset = "smoke", color = Color3.fromHex("5A5560"), rate = 2 },
			{ part = "Shell", preset = "ember", color = Color3.fromHex("FF8A2A"), rate = 3, outward = 0.5 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Ember" }, light = true, period = 3.2, min = 0.3 },
		},
	},

	-- Taped Nuke. Held together with tape: the torn flap flutters and the cardboard
	-- fin twitches like it is about to come apart.
	taped_nuke = {
		spins = {
			{ parts = { "TornFlap" }, pivot = "TornFlap", axis = "X", mode = "swing", deg = 14, period = 1.8 },
			{ parts = { "CardboardFin", "CardTape" }, pivot = "CardboardFin", axis = "Y", mode = "twitch", deg = 10, period = 3.5, duration = 0.25 },
		},
	},

	-- Piggy Nuke. A coin spins over the slot, the curly tail wags and a glint
	-- crosses the coin.
	piggy_nuke = {
		finish = {
			{ parts = { "Coin" }, material = "Metal", color = Color3.fromHex("FFC83A"), reflectance = 0.25 },
		},
		particles = {
			{ part = "Coin", preset = "sparkle", color = Color3.fromHex("FFE38A"), rate = 2 },
		},
		spins = {
			{ parts = { "Coin" }, pivot = "Coin", axis = "Y", rpm = 40 },
			{ parts = { "CurlyTail" }, pivot = "CurlyTail", axis = "Y", mode = "swing", deg = 20, period = 0.9 },
		},
		glint = { parts = { "Coin", "PiggyBody" }, period = 5, sweep = 0.8, color = Color3.new(1, 1, 1), strength = 1.2 },
	},

	-- Cinder Nuke. Magma cracks breathe through the rock and the vent smokes.
	cinder_nuke = {
		finish = {
			{ parts = { "MagmaCrack", "LavaSeam", "VentGlow" }, material = "Neon", color = Color3.fromHex("FF5A12") },
		},
		light = { part = "VentGlow", color = Color3.fromHex("FF6A1A"), brightness = 1.4, range = 0.9 },
		particles = {
			{ part = "VentGlow", preset = "smoke", color = Color3.fromHex("3A3438"), rate = 4 },
			{ part = "VentGlow", preset = "ember", color = Color3.fromHex("FF9A3A"), rate = 5 },
		},
		anims = {
			{ kind = "smoulder", parts = { "MagmaCrack", "LavaSeam", "VentGlow" }, light = true, period = 2.8, min = 0.35 },
		},
	},

	-- Frosted Nuke. Iced over: the crystals glitter, cold mist rolls off and a
	-- frosty glint crosses the shell.
	frosted_nuke = {
		finish = {
			{ parts = { "Icicle", "FinIcicle", "Crystal" }, material = "Glass", color = Color3.fromHex("CFF4FF"), transparency = 0.3 },
			{ parts = { "IceBand" }, material = "Neon", color = Color3.fromHex("8FE4FF") },
		},
		light = { part = "Shell", color = Color3.fromHex("9FE8FF"), brightness = 0.9, range = 0.8 },
		particles = {
			{ part = "SnowCap", preset = "steam", color = Color3.fromHex("E6FBFF"), rate = 3 },
			{ part = "Crystal", preset = "sparkle", color = Color3.fromHex("E6FBFF"), rate = 4 },
		},
		anims = {
			{ kind = "pulse", parts = { "IceBand" }, light = true, period = 3.4, min = 0.5 },
		},
		glint = { parts = { "Shell", "IceBand" }, period = 4.5, sweep = 0.9, color = Color3.fromHex("DFF8FF"), strength = 1.4, stars = 4, starParts = { "Crystal" } },
	},

	-- Tin Can Nuke. The fuse wick is lit: the spark fizzes and throws sparks,
	-- the peeled lid rattles and the hazard badge pulses.
	old_food_tin = {
		finish = {
			{ parts = { "Spark", "SparkBit" }, material = "Neon", color = Color3.fromHex("FFB43A") },
			{ parts = { "Opening" }, material = "Neon", color = Color3.fromHex("7CFF4A") },
		},
		light = { part = "Spark", color = Color3.fromHex("FFA040"), brightness = 1.6, range = 0.9 },
		particles = {
			{ part = "Spark", preset = "arcSpark", color = Color3.fromHex("FFC24A"), rate = 8 },
			{ part = "Spark", preset = "smoke", color = Color3.fromHex("4A4448"), rate = 2 },
			{ part = "Opening", preset = "drift", color = Color3.fromHex("9CFF6A"), rate = 3 },
		},
		spins = {
			{ parts = { "Lid", "LidEdge", "PullRing", "PullTab" }, pivot = "Rim1", axis = "Y", mode = "twitch", deg = 6, duration = 0.15, period = 2.5 },
		},
		anims = {
			{ kind = "flicker", parts = { "Spark", "SparkBit" }, light = true, period = 0.15, min = 0.3, perPart = true },
			{ kind = "pulse", parts = { "Opening" }, period = 2.2, min = 0.5 },
		},
		glint = { parts = { "Body", "Rib", "Rim" }, period = 4, sweep = 0.8, color = Color3.fromHex("FFFFFF"), strength = 1.4 },
	},

	-- Beehive Nuke. The honey runs glassy and glows, the drops glitter, the
	-- entrance breathes warm light and the bees circle the skep.
	beehive_nuke = {
		finish = {
			{ parts = { "HoneyDrip", "HoneyDrop", "HoneyPuddle", "DipperHoney", "HoneyCap" }, material = "Glass", color = Color3.fromHex("FFB21A"), transparency = 0.15 },
			{ parts = { "Cell" }, material = "Glass", color = Color3.fromHex("FFC23A"), transparency = 0.1 },
			{ parts = { "Entrance" }, material = "Neon", color = Color3.fromHex("FF9A1A") },
			{ parts = { "BeeWing" }, material = "Glass", color = Color3.fromHex("E8F4FF"), transparency = 0.4 },
		},
		light = { part = "Entrance", color = Color3.fromHex("FFB43A"), brightness = 1.4, range = 1.0 },
		particles = {
			{ part = "Entrance", preset = "drift", color = Color3.fromHex("FFD24A"), rate = 4 },
			{ part = "HoneyCap", preset = "sparkle", color = Color3.fromHex("FFE08A"), rate = 2 },
		},
		spins = {
			{ parts = { "BeeBody", "BeeHead", "BeeSting", "BeeStripe", "BeeWing" }, pivot = "Skep", axis = "Y", rpm = 14 },
			{ parts = { "HoneyDrop" }, pivot = "HoneyDrop1", axis = "Y", mode = "bob", amp = 0.4, period = 2.4 },
		},
		anims = {
			{ kind = "pulse", parts = { "Entrance" }, light = true, period = 2.6, min = 0.5 },
			{ kind = "flicker", parts = { "BeeWing" }, mode = "transparency", period = 0.12, min = 0.2, perPart = true },
			{ kind = "pulse", parts = { "Cell" }, period = 3.0, min = 0.6, stagger = true },
		},
		glint = { parts = { "HoneyDrip", "DipperHoney" }, period = 3.5, sweep = 0.7, color = Color3.fromHex("FFF0B0"), strength = 1.4 },
	},


	-- Kiln Nuke. The firebox glows through the open door, the coals smoulder, the
	-- chimney smokes and the door creaks on its hinge.
	kiln_nuke = {
		finish = {
			{ parts = { "FireGlow" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
			{ parts = { "Coal" }, material = "Neon", color = Color3.fromHex("FF3A12") },
		},
		light = { part = "FireGlow", color = Color3.fromHex("FF7A2A"), brightness = 1.6, range = 1.0 },
		particles = {
			{ part = "ChimneyCap", preset = "smoke", color = Color3.fromHex("4A4448"), rate = 5 },
			{ part = "FireGlow", preset = "flame", color = Color3.fromHex("FF8A2A"), rate = 6 },
			{ part = "ChimneyCap", preset = "ember", color = Color3.fromHex("FFA040"), rate = 2 },
		},
		spins = {
			{ parts = { "OpenDoor" }, pivot = "DoorHinge", axis = "Y", mode = "swing", deg = 12, period = 3.0 },
		},
		anims = {
			{ kind = "smoulder", parts = { "FireGlow", "Coal" }, light = true, period = 2.2, min = 0.4 },
		},
	},

	-- Lantern Nuke. Lit from inside: the paper glows warm and flickers, the emblems
	-- pulse and the tassel sways on its cord.
	lantern_nuke = {
		finish = {
			{ parts = { "PaperBody" }, material = "Neon", color = Color3.fromHex("FF7A3A"), transparency = 0.1 },
			{ parts = { "EmblemGlow" }, material = "Neon", color = Color3.fromHex("FFE08A") },
		},
		light = { part = "PaperBody", color = Color3.fromHex("FFA050"), brightness = 1.8, range = 1.1 },
		particles = {
			{ part = "TopVent", preset = "ember", color = Color3.fromHex("FFC060"), rate = 2 },
		},
		spins = {
			{ parts = { "TasselStrand", "TasselKnot", "TasselCord" }, pivot = "TasselCord", axis = "X", mode = "swing", deg = 10, period = 2.4 },
		},
		anims = {
			{ kind = "flicker", parts = { "PaperBody" }, light = true, period = 0.5, min = 0.75 },
			{ kind = "pulse", parts = { "EmblemGlow" }, period = 2.8, min = 0.4 },
		},
	},

	-- King Nuke. The jewels glint, the orb glows and turns with its cross, and a
	-- gold glint crosses the bands and crown.
	king_nuke = {
		finish = {
			{ parts = { "Orb" }, material = "Neon", color = Color3.fromHex("FFD86A") },
		},
		light = { part = "Orb", color = Color3.fromHex("FFD86A"), brightness = 1.3, range = 0.9 },
		particles = {
			{ part = "CrownCap", preset = "sparkle", color = Color3.fromHex("FFF0B0"), rate = 5 },
		},
		spins = {
			{ parts = { "CrossH", "CrossV", "Orb" }, pivot = "Orb", axis = "Y", rpm = 10 },
		},
		anims = {
			{ kind = "pulse", parts = { "Orb" }, light = true, period = 3.0, min = 0.55 },
		},
		glint = {
			parts = { "RoyalBand", "CrownBase", "CrownPoint", "CrownArch" },
			period = 3.5,
			sweep = 0.8,
			color = Color3.fromHex("FFF4C8"),
			strength = 1.6,
			stars = 6,
			starParts = { "CrownJewel", "BandJewel" },
		},
	},

	-- Hourglass Nuke. Sand pours through the neck, the dial's hands tick round, the
	-- runes glow and the bulb lines chase round the pillars.
	hourglass_nuke = {
		finish = {
			{ parts = { "SandStream", "Grain" }, material = "Neon", color = Color3.fromHex("FFD27A") },
			{ parts = { "Rune" }, material = "Neon", color = Color3.fromHex("7AD8FF") },
			{ parts = { "BulbLine*" }, material = "Neon", color = Color3.fromHex("FFE9A8") },
		},
		light = { part = "NeckRing", color = Color3.fromHex("FFD27A"), brightness = 1.3, range = 0.9 },
		particles = {
			{ part = "SandStream", preset = "sparkle", color = Color3.fromHex("FFE9A8"), rate = 4 },
		},
		spins = {
			{ parts = { "TopHand" }, pivot = "TopDial", axis = "Y", mode = "tick", rpm = 5, steps = 12 },
			{ parts = { "Grain" }, pivot = "SandStream", axis = "Y", mode = "bob", period = 1.2, amp = 0.4 },
		},
		anims = {
			{ kind = "pulse", parts = { "Rune" }, light = true, period = 2.4, min = 0.35 },
			{ kind = "blink", parts = { "BulbLine*" }, period = 1.6, duty = 0.5, min = 0.2, stagger = true },
		},
	},

	-- Phoenix Nuke. Reborn in fire: the flame heart and nest burn, the flame
	-- halo flickers round the bird, embers rise, the tail eyes glitter and the
	-- crest glows.
	phoenix_nuke = {
		finish = {
			{ parts = { "FlameHeart", "CrestCore" }, material = "Neon", color = Color3.fromHex("FFE08A") },
			{ parts = { "BaseFlame", "HaloFlame", "FinFlame", "FireHalo" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
			{ parts = { "Ember" }, material = "Neon", color = Color3.fromHex("FFA040") },
			{ parts = { "TailEye", "FeatherTipP" }, material = "Neon", color = Color3.fromHex("FFC23A") },
		},
		light = { part = "FlameHeart", color = Color3.fromHex("FF8A2A"), brightness = 2.2, range = 1.3 },
		particles = {
			{ part = "FlameHeart", preset = "flame", color = Color3.fromHex("FF8A2A"), rate = 12 },
			{ part = "AshNest", preset = "ember", color = Color3.fromHex("FFB040"), rate = 8 },
			{ part = "CrestCore", preset = "sparkle", color = Color3.fromHex("FFE08A"), rate = 4 },
			{ part = "AshNest", preset = "smoke", color = Color3.fromHex("3A3230"), rate = 2 },
		},
		spins = {
			{ parts = { "HaloFlame", "FireHalo" }, pivot = "Body", axis = "Y", rpm = 10 },
			{ parts = { "Ember" }, pivot = "Body", axis = "Y", rpm = -6 },
		},
		anims = {
			{ kind = "flicker", parts = { "BaseFlame", "HaloFlame", "FinFlame" }, period = 0.3, min = 0.5, perPart = true },
			{ kind = "heartbeat", parts = { "FlameHeart", "CrestCore" }, light = true, period = 1.6, min = 0.5 },
			{ kind = "glitter", parts = { "TailEye", "Ember" }, period = 1.2, duration = 0.2 },
			{ kind = "smoulder", parts = { "FeatherTipP" }, period = 2.4, min = 0.5 },
		},
		glint = { parts = { "GoldBand", "Crest", "TailEyeRing" }, period = 3.5, sweep = 0.7, color = Color3.fromHex("FFF0B0"), strength = 1.6 },
		ping = { part = "FlameHeart", color = Color3.fromHex("FF8A2A"), period = 3.4 },
	},


	-- Eclipse Nuke. A black void core ringed by a corona: the rays pulse in turn,
	-- the flare arcs crackle and the shards orbit the halo.
	eclipse_nuke = {
		finish = {
			{ parts = { "VoidCore" }, material = "SmoothPlastic", color = Color3.fromHex("050508") },
			{ parts = { "CoronaRing", "CoronaRay", "Limb" }, material = "Neon", color = Color3.fromHex("FFB43A") },
			{ parts = { "FlareArc" }, material = "Neon", color = Color3.fromHex("FF5A1A") },
			{ parts = { "ShardEdge" }, material = "Neon", color = Color3.fromHex("FFD27A") },
		},
		light = { part = "CoronaRing", color = Color3.fromHex("FFA040"), brightness = 2.2, range = 1.3 },
		particles = {
			{ part = "CoronaRing", preset = "shrinkMotes", color = Color3.fromHex("FFD27A"), rate = 14 },
			{ part = "FlareArc", preset = "arcSpark", color = Color3.fromHex("FF8A3A"), rate = 5 },
		},
		spins = {
			{ parts = { "Shard", "ShardEdge", "ShardOrbit" }, pivot = "VoidCore", axis = "Y", rpm = 12 },
			{ parts = { "CoronaRay", "CoronaRing" }, pivot = "VoidCore", axis = "Z", rpm = -4 },
		},
		anims = {
			{ kind = "pulse", parts = { "CoronaRay" }, period = 2.0, min = 0.35, stagger = true },
			{ kind = "pulse", parts = { "CoronaRing", "Limb" }, light = true, period = 3.2, min = 0.6 },
			{ kind = "flicker", parts = { "FlareArc" }, period = 0.25, min = 0.3, perPart = true },
		},
		ping = { part = "CoronaRing", color = Color3.fromHex("FFB43A"), period = 3.2 },
	},

	-- Inferno Nuke. The Anomaly: a white-hot core breaking through its shell,
	-- fireballs circling, fins wheeling, horns swaying, chains rippling,
	-- drips and embers bobbing, lava glowing and shockwaves rolling out.
	inferno_nuke = {
		finish = {
			{ parts = { "WhiteHotCore" }, material = "Neon", color = Color3.fromHex("FFF6DC") },
			{ parts = { "FireGap", "MagmaVein", "LavaPool", "MoltenDrip", "Vent" }, material = "Neon", color = Color3.fromHex("FF5A12") },
			{ parts = { "CentralFlame", "FlameTongue", "FinFlame", "HornFlame", "Fireball", "PillarTip" }, material = "Neon", color = Color3.fromHex("FF8A2A") },
			{ parts = { "FireballTrail", "HeatRing" }, material = "Neon", color = Color3.fromHex("FFB43A"), transparency = 0.35 },
			{ parts = { "AnchorGlow", "HornVein", "Ember" }, material = "Neon", color = Color3.fromHex("FF3A12") },
		},
		light = { part = "WhiteHotCore", color = Color3.fromHex("FF7A2A"), brightness = 2.6, range = 1.4 },
		particles = {
			{ part = "CentralFlame", preset = "flame", color = Color3.fromHex("FF8A2A"), rate = 16 },
			{ part = "Vent", preset = "smoke", color = Color3.fromHex("2A2426"), rate = 6 },
			{ part = "LavaPool", preset = "ember", color = Color3.fromHex("FFA040"), rate = 10 },
			{ part = "WhiteHotCore", preset = "sparkle", color = Color3.fromHex("FFF6DC"), rate = 5 },
		},
		spins = {
			{ parts = { "Fireball", "FireballTrail" }, pivot = "WhiteHotCore", axis = "Y", rpm = 18 },
			{ parts = { "HeatRing" }, pivot = "WhiteHotCore", axis = "Y", rpm = -8 },
			{ parts = { "FireFin", "FinFlame" }, pivot = "ShellSegment1", axis = "Y", rpm = 10 },
			{ parts = { "Horn1", "HornVein1", "HornFlame1" }, pivot = "Horn1", axis = "Z", mode = "swing", deg = 6, period = 2.2 },
			{ parts = { "Horn2", "HornVein2", "HornFlame2" }, pivot = "Horn2", axis = "Z", mode = "swing", deg = -6, period = 2.2 },
			-- (The chains are appended link by link below the table.)
			{ parts = { "MoltenDrip" }, pivot = "MoltenDrip1", axis = "Y", mode = "bob", amp = 0.4, period = 1.0 },
			{ parts = { "Ember" }, pivot = "Ember1", axis = "Y", mode = "bob", amp = 4, period = 3.0 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "WhiteHotCore", "FireGap" }, light = true, period = 1.4, min = 0.55 },
			{ kind = "flicker", parts = { "CentralFlame", "FlameTongue", "FinFlame", "HornFlame" }, period = 0.2, min = 0.45, perPart = true },
			{ kind = "smoulder", parts = { "MagmaVein", "LavaPool", "MoltenDrip", "AnchorGlow", "HornVein" }, period = 2.6, min = 0.4 },
			{ kind = "pulse", parts = { "Shockwave" }, mode = "transparency", period = 2.8, min = 0.2 },
		},
		ping = { part = "ScorchedGround", color = Color3.fromHex("FF6A1A"), period = 2.8 },
	},

	-- ── Stage 8: Cobalt Shelf (batch 17) ──

	-- Sunken Nuke. Air bubbles bob up off the shell and the seaweed sways.
	sunken_nuke = {
		particles = {
			{ part = "FuzeCollar", preset = "drift", color = Color3.fromHex("CFEFFF"), rate = 2 },
		},
		spins = {
			{ parts = { "Bubble" }, pivot = "Bubble1", axis = "Y", mode = "bob", amp = 1.5, period = 2.6 },
			{ parts = { "Seaweed" }, pivot = "Seaweed1", axis = "X", mode = "swing", deg = 10, period = 2.8 },
		},
	},

	-- Conch Nuke. A pearly glint runs over the whorl and the spire tip glows.
	conch_nuke = {
		finish = {
			{ parts = { "LipLining" }, reflectance = 0.2 },
		},
		anims = {
			{ kind = "pulse", parts = { "SpireTip" }, period = 3.2, min = 0.6 },
		},
		glint = { parts = { "Shell", "WhorlRidge", "Lip", "LipLining" }, period = 5, sweep = 0.9, color = Color3.fromHex("FFEFF4"), strength = 1.2 },
	},

	-- Cobalt Nuke. The ore crystals glow cobalt blue and glitter, the veins breathe.
	cobalt_nuke = {
		finish = {
			{ parts = { "OreCrystal", "NoseCrystal" }, material = "Glass", color = Color3.fromHex("3A7BFF"), transparency = 0.15 },
			{ parts = { "Vein" }, material = "Neon", color = Color3.fromHex("2F6BFF") },
		},
		light = { part = "NoseCrystal", color = Color3.fromHex("4A8BFF"), brightness = 1.0, range = 0.8 },
		particles = {
			{ part = "OreCrystal", preset = "sparkle", color = Color3.fromHex("A8C8FF"), rate = 3 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Vein" }, light = true, period = 3.0, min = 0.4 },
		},
	},

	-- Pinball Nuke. The bumpers flash in turn, the lane arrows chase, the flippers
	-- flick and the score blinks.
	pinball_nuke = {
		finish = {
			{ parts = { "BumperCap" }, material = "Neon", color = Color3.fromHex("FF4AA8") },
			{ parts = { "LaneArrow" }, material = "Neon", color = Color3.fromHex("FFD23A") },
			{ parts = { "ScoreDigits" }, material = "Neon", color = Color3.fromHex("FF8A2A") },
			{ parts = { "Pinball" }, reflectance = 0.4 },
		},
		light = { part = "BumperCap1", color = Color3.fromHex("FF6AC0"), brightness = 1.0, range = 0.8 },
		spins = {
			{ parts = { "Flipper1" }, pivot = "Flipper1", axis = "Y", mode = "twitch", deg = 25, period = 2.2, duration = 0.2 },
			{ parts = { "Flipper2" }, pivot = "Flipper2", axis = "Y", mode = "twitch", deg = -25, period = 2.6, duration = 0.2 },
			{ parts = { "Flipper3" }, pivot = "Flipper3", axis = "Y", mode = "twitch", deg = 25, period = 3.0, duration = 0.2 },
			{ parts = { "Flipper4" }, pivot = "Flipper4", axis = "Y", mode = "twitch", deg = -25, period = 2.4, duration = 0.2 },
		},
		anims = {
			{ kind = "blink", parts = { "BumperCap" }, light = true, period = 1.2, duty = 0.5, min = 0.3, stagger = true },
			{ kind = "blink", parts = { "LaneArrow" }, period = 0.9, duty = 0.4, min = 0.2, stagger = true },
			{ kind = "flash", parts = { "ScoreDigits" }, period = 1.8, min = 0.5 },
		},
	},

	-- Diving Bell Nuke. The portholes glow from inside, the gauge needle twitches,
	-- bubbles leak from the valves and the ballast sways on its lines.
	diving_bell_nuke = {
		finish = {
			{ parts = { "PortGlass" }, material = "Neon", color = Color3.fromHex("8FE0FF"), transparency = 0.2 },
		},
		light = { part = "PortGlass1", color = Color3.fromHex("8FE0FF"), brightness = 1.0, range = 0.8 },
		particles = {
			{ part = "Valve", preset = "drift", color = Color3.fromHex("DDF6FF"), rate = 3 },
		},
		spins = {
			{ parts = { "GaugeNeedle" }, pivot = "GaugeFace", axis = "Z", mode = "twitch", deg = 20, period = 2.5, duration = 0.3 },
			{ parts = { "Ballast", "BallastLine" }, pivot = "Shell", axis = "X", mode = "swing", deg = 3, period = 3.2 },
		},
		anims = {
			{ kind = "pulse", parts = { "PortGlass" }, light = true, period = 2.8, min = 0.5 },
		},
	},

	-- Anchor Nuke. The ship's bell rocks with its clapper, and a gold glint crosses
	-- the bands and the anchor ring.
	anchor_nuke = {
		finish = {
			{ parts = { "ShipBell", "Clapper" }, material = "Metal", color = Color3.fromHex("E0B04A"), reflectance = 0.2 },
		},
		spins = {
			{ parts = { "ShipBell", "Clapper" }, pivot = "BellBracket", axis = "X", mode = "swing", deg = 12, period = 2.4 },
		},
		glint = {
			parts = { "GoldBand", "AnchorRing", "ShipBell" },
			period = 4,
			sweep = 0.8,
			color = GLINT_GOLD,
			strength = 1.5,
			stars = 3,
			starParts = { "ShipBell" },
		},
	},

	-- Jellyfish Nuke. Bioluminescent: the rim lights chase, the spots twinkle, the
	-- core breathes, the tentacles drift and the babies bob alongside.
	jellyfish_nuke = {
		finish = {
			{ parts = { "BellDome", "InnerBell", "BabyBell" }, material = "Glass", color = Color3.fromHex("C08AFF"), transparency = 0.35 },
			{ parts = { "RimLight", "BioSpot", "CrownGlow" }, material = "Neon", color = Color3.fromHex("7AF0FF") },
			{ parts = { "Core", "BabyCore", "GonadRing" }, material = "Neon", color = Color3.fromHex("FF7AE0") },
		},
		light = { part = "Core", color = Color3.fromHex("B07AFF"), brightness = 1.6, range = 1.1 },
		particles = {
			{ part = "BellDome", preset = "drift", color = Color3.fromHex("A8F4FF"), rate = 4 },
			{ part = "Core", preset = "sparkle", color = Color3.fromHex("FFC0F0"), rate = 3 },
		},
		spins = {
			{ parts = { "Tentacle", "OralArm", "SpiralTentacle", "Stinger" }, pivot = "Core", axis = "Y", mode = "swing", deg = 8, period = 3.4 },
			{ parts = { "BabyBell1", "BabyCore1", "BabyTentacle1*" }, pivot = "BabyBell1", axis = "Y", mode = "bob", amp = 0.3, period = 2.2 },
			{ parts = { "BabyBell2", "BabyCore2", "BabyTentacle2*" }, pivot = "BabyBell2", axis = "Y", mode = "bob", amp = 0.3, period = 2.2, phase = 0.33 },
			{ parts = { "BabyBell3", "BabyCore3", "BabyTentacle3*" }, pivot = "BabyBell3", axis = "Y", mode = "bob", amp = 0.3, period = 2.2, phase = 0.66 },
		},
		anims = {
			{ kind = "pulse", parts = { "Core", "BabyCore", "GonadRing" }, light = true, period = 2.6, min = 0.45 },
			{ kind = "pulse", parts = { "RimLight" }, period = 1.8, min = 0.25, stagger = true },
			{ kind = "wink", parts = { "BioSpot" }, period = 1.4, min = 0.3, perPart = true },
		},
	},

	-- Arcade Nuke. The marquee bulbs chase, the screen sprites flicker, the neon
	-- trim cycles colour and the token spins over the coin door.
	arcade_nuke = {
		finish = {
			{ parts = { "Screen" }, material = "Neon", color = Color3.fromHex("1A2A5A") },
			{ parts = { "Sprite", "Pixel", "ScoreDigit" }, material = "Neon", color = Color3.fromHex("6BFF3A") },
			{ parts = { "MarqueeBulb" }, material = "Neon", color = Color3.fromHex("FFE08A") },
			{ parts = { "NeonBand", "NeonEdge", "NeonTop", "FinNeon" }, material = "Neon", color = Color3.fromHex("FF3AD8") },
			{ parts = { "TokenCoin" }, material = "Metal", color = Color3.fromHex("FFC83A"), reflectance = 0.25 },
		},
		light = { part = "Screen", color = Color3.fromHex("7A8AFF"), brightness = 1.4, range = 1.0 },
		particles = {
			{ part = "Marquee", preset = "sparkle", color = Color3.fromHex("FFE08A"), rate = 3 },
		},
		spins = {
			{ parts = { "TokenCoin", "TokenMark", "TokenRim" }, pivot = "TokenCoin", axis = "Y", rpm = 45 },
		},
		anims = {
			{ kind = "blink", parts = { "MarqueeBulb" }, period = 1.0, duty = 0.5, min = 0.2, stagger = true },
			{ kind = "flicker", parts = { "Sprite", "Pixel" }, period = 0.4, min = 0.4, perPart = true },
			{ kind = "colorCycle", parts = { "NeonBand", "NeonEdge", "NeonTop", "FinNeon" }, period = 4.0 },
			{ kind = "flicker", parts = { "Screen" }, light = true, period = 0.6, min = 0.75 },
			{ kind = "flash", parts = { "ScoreDigit" }, period = 2.0, min = 0.4 },
		},
	},

	-- Circuit Nuke. Current runs the traces in turn, the status LED blinks, the
	-- chip labels glow and arcs crackle off the capacitors.
	circuit_nuke = {
		finish = {
			{ parts = { "TraceH", "TraceV" }, material = "Neon", color = Color3.fromHex("3AFF8A") },
			{ parts = { "StatusLED", "FuzeChip" }, material = "Neon", color = Color3.fromHex("FF3A3A") },
			{ parts = { "ChipLabel" }, material = "Neon", color = Color3.fromHex("7AD8FF") },
		},
		light = { part = "StatusLED", color = Color3.fromHex("5AFF9A"), brightness = 1.2, range = 0.9 },
		particles = {
			{ part = "Capacitor", preset = "arcSpark", color = Color3.fromHex("8AFFB0"), rate = 3 },
			{ part = "HeatSinkFin", preset = "steam", color = Color3.fromHex("DDEEE8"), rate = 2 },
		},
		anims = {
			{ kind = "pulse", parts = { "TraceH", "TraceV" }, light = true, period = 1.6, min = 0.25, stagger = true },
			{ kind = "blink", parts = { "StatusLED", "FuzeChip" }, period = 0.8, duty = 0.5, min = 0.15 },
			{ kind = "pulse", parts = { "ChipLabel" }, period = 2.4, min = 0.4 },
		},
		glint = { parts = { "GoldRail", "EdgePad", "Pin" }, period = 3.8, sweep = 0.7, color = GLINT_GOLD, strength = 1.4 },
	},

	-- Submarine Nuke. The propeller turns inside its shroud, the portholes glow,
	-- the periscope sweeps, the bow fuze blinks and sonar pings out.
	submarine_nuke = {
		finish = {
			{ parts = { "PortGlass", "PeriscopeLens" }, material = "Neon", color = Color3.fromHex("FFD27A") },
			{ parts = { "BowFuzeTip" }, material = "Neon", color = Color3.fromHex("FF3A3A") },
			{ parts = { "HazardBand" }, material = "Neon", color = Color3.fromHex("FFC21A") },
		},
		light = { part = "Sail", color = Color3.fromHex("FFD27A"), brightness = 1.4, range = 1.0 },
		particles = {
			{ part = "PropHub", preset = "drift", color = Color3.fromHex("DDF6FF"), rate = 6 },
			{ part = "Antenna", preset = "sparkle", color = Color3.fromHex("BFF6FF"), rate = 2 },
		},
		spins = {
			{ parts = { "PropBlade", "PropHub" }, pivot = "PropHub", axisParts = { "PropShroud", "BowFuze" }, rpm = 50 },
			{ parts = { "PeriscopeHead", "PeriscopeLens" }, pivot = "Periscope", axis = "Y", mode = "swing", deg = 40, period = 5.0 },
		},
		anims = {
			{ kind = "pulse", parts = { "PortGlass" }, light = true, period = 3.0, min = 0.5, stagger = true },
			{ kind = "blink", parts = { "BowFuzeTip" }, period = 1.4, duty = 0.3, min = 0.1 },
			{ kind = "pulse", parts = { "HazardBand" }, period = 2.2, min = 0.4 },
		},
		ping = { part = "BowFuzeTip", color = Color3.fromHex("7AE0FF"), period = 1.4 },
	},

	-- Abyssal Nuke. The Mythic: an anglerfish hull from the deep. The lure glows and
	-- sways, photophores wink, the viewports and pressure cracks breathe, the fangs
	-- gleam and a school of little fish circles it.
	abyssal_nuke = {
		finish = {
			{ parts = { "LureOrb", "SubLureOrb", "LureHalo" }, material = "Neon", color = Color3.fromHex("9AFFF0") },
			{ parts = { "Photophore", "LateralLine", "FishEye" }, material = "Neon", color = Color3.fromHex("3AD8FF") },
			{ parts = { "ViewportGlow", "PressureCrack", "DeepHalo" }, material = "Neon", color = Color3.fromHex("2A7AFF") },
			{ parts = { "Maw" }, material = "SmoothPlastic", color = Color3.fromHex("05060A") },
			{ parts = { "FangU", "FangL" }, material = "Glass", color = Color3.fromHex("EAF6FF"), transparency = 0.1 },
		},
		light = { part = "LureOrb", color = Color3.fromHex("8AFFF0"), brightness = 2.2, range = 1.3 },
		particles = {
			{ part = "LureOrb", preset = "shrinkMotes", color = Color3.fromHex("BFFFF6"), rate = 10 },
			{ part = "PressureHull", preset = "drift", color = Color3.fromHex("6AA8FF"), rate = 5 },
			{ part = "Gill", preset = "drift", color = Color3.fromHex("DDF6FF"), rate = 3 },
		},
		spins = {
			{ parts = { "LureStalk", "LureOrb", "LureHalo" }, pivot = "LureStalk", axis = "X", mode = "swing", deg = 8, period = 2.6 },
			{ parts = { "SubLure", "SubLureOrb" }, pivot = "PressureHull", axis = "X", mode = "swing", deg = 5, period = 3.1 },
			{ parts = { "FishBody", "FishTail", "FishEye" }, pivot = "PressureHull", axis = "Y", rpm = 9 },
			{ parts = { "DeepHalo" }, pivot = "PressureHull", axis = "Y", rpm = -4 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "LureOrb", "LureHalo" }, light = true, period = 2.0, min = 0.5 },
			{ kind = "wink", parts = { "Photophore", "SubLureOrb" }, period = 1.6, min = 0.25, perPart = true },
			{ kind = "smoulder", parts = { "ViewportGlow", "PressureCrack", "DeepHalo" }, period = 3.2, min = 0.35 },
			{ kind = "pulse", parts = { "LateralLine" }, period = 2.0, min = 0.3, stagger = true },
		},
		glint = { parts = { "FangU", "FangL" }, period = 3.2, sweep = 0.5, color = Color3.fromHex("EAF8FF"), strength = 1.8, stars = 4 },
		ping = { part = "LureOrb", color = Color3.fromHex("7AFFE8"), period = 2.0 },
	},

	-- Kraken Nuke. The Anomaly: a huge eye watching through an armoured mantle. The
	-- eye glows and its lid twitches, the core window beats, spray
	-- swirl round it, drips fall, the horn tips chase and lightning arcs from the
	-- core window to the eye.
	kraken_nuke = {
		finish = {
			{ parts = { "EyeBall" }, material = "Neon", color = Color3.fromHex("FFE06A") },
			{ parts = { "EyeSlit", "SideSlit" }, material = "SmoothPlastic", color = Color3.fromHex("05060A") },
			{ parts = { "EyeIris", "SideIris" }, material = "Neon", color = Color3.fromHex("FF8A1A") },
			{ parts = { "CoreWindow", "GlowBand", "FinStripe" }, material = "Neon", color = Color3.fromHex("3AFFC8") },
			{ parts = { "HornTip" }, material = "Neon", color = Color3.fromHex("8A5AFF") },
			{ parts = { "Spray", "Drip" }, material = "Glass", color = Color3.fromHex("9AE8FF"), transparency = 0.3 },
		},
		light = { part = "CoreWindow", color = Color3.fromHex("3AFFC8"), brightness = 2.6, range = 1.4 },
		particles = {
			{ part = "CoreWindow", preset = "shrinkMotes", color = Color3.fromHex("9AFFE8"), rate = 12 },
			{ part = "Mantle", preset = "smoke", color = Color3.fromHex("1A1028"), rate = 5 },
			{ part = "Spray", preset = "drift", color = Color3.fromHex("DDF6FF"), rate = 6 },
			{ part = "HornTip", preset = "sparkle", color = Color3.fromHex("C0A0FF"), rate = 4 },
			{ part = "EyeBall", preset = "arcSpark", color = Color3.fromHex("FFD27A"), rate = 2 },
		},
		spins = {
			{ parts = { "Spray" }, pivot = "Mantle", axis = "Y", rpm = -5 },
			{ parts = { "Drip" }, pivot = "Drip1", axis = "Y", mode = "bob", amp = 0.5, period = 1.3 },
			{ parts = { "EyeLid" }, pivot = "EyeBall", axis = "X", mode = "twitch", deg = 30, period = 4.5, duration = 0.25 },
			-- (The arms and tentacles are appended one by one below the table.)
		},
		anims = {
			{ kind = "heartbeat", parts = { "CoreWindow", "GlowBand" }, light = true, period = 1.5, min = 0.5 },
			{ kind = "pulse", parts = { "EyeIris", "SideIris" }, period = 2.4, min = 0.45 },
			{ kind = "pulse", parts = { "EyeBall" }, period = 3.6, min = 0.7 },
			{ kind = "pulse", parts = { "HornTip" }, period = 1.8, min = 0.3, stagger = true },
			{ kind = "smoulder", parts = { "FinStripe" }, period = 2.8, min = 0.4 },
		},
		bolts = {
			{ from = "CoreWindow", to = "EyeBall", color = Color3.fromHex("9AFFE8"), period = 2.4, duration = 0.3, segments = 7, jitter = 0.15, width = 0.08 },
		},
		ping = { part = "Mantle", color = Color3.fromHex("3AFFC8"), period = 3.0 },
	},

	-- ── Stage 9: Glass Barrens (batch 18) ──

	-- Thermos Nuke. Steam curls off the spout, the gauge needle twitches.
	thermos_nuke = {
		particles = {
			{ part = "Spout", preset = "steam", color = Color3.fromHex("F2F6FA"), rate = 4 },
		},
		spins = {
			{ parts = { "GaugeNeedle" }, pivot = "GaugeFace", axis = "Z", mode = "twitch", deg = 25, period = 2.4, duration = 0.3 },
		},
	},

	-- Traffic Cone Nuke. The warning lamp blinks amber and the reflective bands catch light.
	traffic_cone_nuke = {
		finish = {
			{ parts = { "WarnLamp" }, material = "Neon", color = Color3.fromHex("FFB21A") },
			{ parts = { "ReflectBand" }, reflectance = 0.4 },
		},
		light = { part = "WarnLamp", color = Color3.fromHex("FFB21A"), brightness = 1.2, range = 0.9 },
		anims = {
			{ kind = "blink", parts = { "WarnLamp" }, light = true, period = 1.0, duty = 0.5, min = 0.15 },
		},
		glint = { parts = { "ReflectBand" }, period = 4, sweep = 0.7, color = Color3.fromHex("FFFFFF"), strength = 1.3 },
	},

	-- Stained Glass Nuke. The panes turn to lit glass and the rose window turns slowly.
	stained_glass_nuke = {
		finish = {
			{ parts = { "Pane", "FinPane" }, transparency = 0.25 },
			{ parts = { "RosePetal", "RoseCenter" }, material = "Neon", color = Color3.fromHex("FF6A9A") },
		},
		light = { part = "Core", color = Color3.fromHex("FFD9A0"), brightness = 1.2, range = 0.9 },
		spins = {
			{ parts = { "RosePetal", "RoseCenter" }, pivot = "RoseCenter", axis = "Z", rpm = 3 },
		},
		anims = {
			{ kind = "pulse", parts = { "RosePetal", "RoseCenter" }, light = true, period = 3.2, min = 0.55, stagger = true },
		},
	},

	-- Robot Nuke. Eyes glow, chest lights chase, dial needles twitch, antenna blinks.
	robot_nuke = {
		finish = {
			{ parts = { "Eye", "EarLight" }, material = "Neon", color = Color3.fromHex("5AE8FF") },
			{ parts = { "ChestLight" }, material = "Neon", color = Color3.fromHex("7AFF6A") },
			{ parts = { "AntennaBall" }, material = "Neon", color = Color3.fromHex("FF4A4A") },
		},
		light = { part = "Visor", color = Color3.fromHex("5AE8FF"), brightness = 1.0, range = 0.8 },
		spins = {
			{ parts = { "DialNeedle1" }, pivot = "Dial1", axis = "Z", mode = "twitch", deg = 30, period = 2.0, duration = 0.25 },
			{ parts = { "DialNeedle2" }, pivot = "Dial2", axis = "Z", mode = "twitch", deg = -30, period = 2.6, duration = 0.25 },
			{ parts = { "DialNeedle3" }, pivot = "Dial3", axis = "Z", mode = "twitch", deg = 30, period = 3.1, duration = 0.25 },
		},
		anims = {
			{ kind = "pulse", parts = { "Eye", "EarLight" }, light = true, period = 2.8, min = 0.5 },
			{ kind = "blink", parts = { "ChestLight" }, period = 1.2, duty = 0.4, min = 0.2, stagger = true },
			{ kind = "blink", parts = { "AntennaBall" }, period = 1.6, duty = 0.3, min = 0.2 },
		},
	},

	-- Geode Nuke. The cavity crystals glow amethyst and glitter inside the rind.
	geode_nuke = {
		finish = {
			{ parts = { "Crystal", "NoseCrystal", "NoseCrystalMain", "FinCrystal", "HalfCrystal" }, material = "Glass", color = Color3.fromHex("B06AFF"), transparency = 0.15 },
			{ parts = { "CavityGlow", "CrackSeam" }, material = "Neon", color = Color3.fromHex("C88AFF") },
		},
		light = { part = "CavityGlow", color = Color3.fromHex("B06AFF"), brightness = 1.4, range = 1.0 },
		particles = {
			{ part = "Cavity", preset = "sparkle", color = Color3.fromHex("E8C8FF"), rate = 4 },
		},
		anims = {
			{ kind = "smoulder", parts = { "CavityGlow", "CrackSeam" }, light = true, period = 3.0, min = 0.4 },
			{ kind = "glitter", parts = { "Crystal" }, period = 2.5, duration = 0.25 },
		},
	},

	-- Lava Lamp Nuke. Molten blobs rise and sink in a glowing globe, stars orbit.
	lava_lamp_nuke = {
		finish = {
			{ parts = { "Globe" }, material = "Glass", transparency = 0.45 },
			{ parts = { "Blob", "PoolBlob", "EscapeBlob", "Drip" }, material = "Neon", color = Color3.fromHex("FF5A2A") },
			{ parts = { "BaseGlow", "FuzeGlow" }, material = "Neon", color = Color3.fromHex("FFB23A") },
		},
		light = { part = "Globe", color = Color3.fromHex("FF6A2A"), brightness = 1.8, range = 1.1 },
		particles = {
			{ part = "Fuze", preset = "ember", color = Color3.fromHex("FFA040"), rate = 3 },
		},
		spins = {
			{ parts = { "Blob" }, pivot = "Globe", axis = "Y", mode = "bob", amp = 0.12, period = 4.0 },
			{ parts = { "EscapeBlob" }, pivot = "EscapeBlob1", axis = "Y", mode = "bob", amp = 0.8, period = 3.0, phase = 0.5 },
			{ parts = { "StarHoop", "HoopStar" }, pivot = "Globe", axis = "Y", rpm = 6 },
			{ parts = { "Swirl" }, pivot = "Globe", axis = "Y", rpm = -4 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Blob", "PoolBlob", "EscapeBlob" }, light = true, period = 3.4, min = 0.55 },
			{ kind = "wink", parts = { "HoopStar" }, period = 1.4, min = 0.3, perPart = true },
		},
	},

	-- Prism Nuke. A white beam splits into rainbow rays; halos and rings cycle colour.
	prism_nuke = {
		finish = {
			{ parts = { "FacetBody", "MiniPrism", "FinPrism", "Shard", "CrownShard", "FacetGem" }, material = "Glass", color = Color3.fromHex("E8F6FF"), transparency = 0.2, reflectance = 0.3 },
			{ parts = { "WhiteBeam", "SpireSpark" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
			{ parts = { "Ray", "MiniRay", "RainbowHalo", "SpectrumRing", "Flare" }, material = "Neon", color = Color3.fromHex("FF5A5A") },
		},
		light = { part = "FacetBody", color = Color3.fromHex("FFFFFF"), brightness = 1.8, range = 1.2 },
		particles = {
			{ part = "Spire", preset = "sparkle", color = Color3.fromHex("FFFFFF"), rate = 5 },
		},
		spins = {
			{ parts = { "RainbowHalo" }, pivot = "FacetBody", axis = "Y", rpm = 5 },
			{ parts = { "SpectrumRing" }, pivot = "FacetBody", axis = "Y", rpm = -3 },
			{ parts = { "MiniPrism", "MiniRay" }, pivot = "FacetBody", axis = "Y", rpm = 8 },
		},
		anims = {
			{
				kind = "colorCycle",
				parts = { "Ray", "MiniRay", "RainbowHalo", "SpectrumRing", "Flare" },
				period = 4,
				colors = {
					Color3.fromHex("FF4A4A"),
					Color3.fromHex("FFB23A"),
					Color3.fromHex("FFF04A"),
					Color3.fromHex("5AFF6A"),
					Color3.fromHex("4AA8FF"),
					Color3.fromHex("A05AFF"),
				},
			},
			{ kind = "pulse", parts = { "WhiteBeam", "SpireSpark" }, light = true, period = 2.2, min = 0.5 },
		},
		glint = { parts = { "FacetBody", "Edge", "SilverBand" }, period = 4, sweep = 0.8, color = Color3.fromHex("FFFFFF"), strength = 1.6, stars = 3 },
	},

	-- Mech Nuke. The reactor throbs, jets fire, beacons flash, the cannon arm swings
	-- and the missile pods twitch as they lock on.
	mech_nuke = {
		finish = {
			{ parts = { "ReactorCore", "Visor" }, material = "Neon", color = Color3.fromHex("3AE8FF") },
			{ parts = { "JetFlame", "ExhaustGlow", "MuzzleGlow" }, material = "Neon", color = Color3.fromHex("FF8A2A") },
			{ parts = { "JetCore" }, material = "Neon", color = Color3.fromHex("FFE0A0") },
			{ parts = { "Beacon", "AntennaTip" }, material = "Neon", color = Color3.fromHex("FF3A3A") },
		},
		light = { part = "ReactorCore", color = Color3.fromHex("3AE8FF"), brightness = 1.8, range = 1.1 },
		particles = {
			{ part = "JetFlame1", preset = "flame", color = Color3.fromHex("FF9A3A"), rate = 10 },
			{ part = "JetFlame2", preset = "flame", color = Color3.fromHex("FF9A3A"), rate = 10 },
			{ part = "Exhaust", preset = "smoke", color = Color3.fromHex("3A3A40"), rate = 3 },
		},
		spins = {
			{ parts = { "ShoulderR", "ArmR", "CannonBody", "CannonBarrel", "BarrelRing", "MuzzleGlow" }, pivot = "ShoulderR", axis = "X", mode = "swing", deg = 10, period = 3.2 },
			{ parts = { "MissilePod1", "Missile1*", "Tube1*" }, pivot = "MissilePod1", axis = "Y", mode = "twitch", deg = 15, period = 3.0, duration = 0.3 },
			{ parts = { "MissilePod2", "Missile2*", "Tube2*" }, pivot = "MissilePod2", axis = "Y", mode = "twitch", deg = -15, period = 3.6, duration = 0.3 },
			{ parts = { "ReactorFin" }, pivot = "ReactorCore", axis = "Y", rpm = 12 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "ReactorCore" }, light = true, period = 1.6, min = 0.5 },
			{ kind = "flicker", parts = { "JetFlame", "JetCore", "ExhaustGlow" }, period = 0.3, min = 0.5, perPart = true },
			{ kind = "blink", parts = { "Beacon", "AntennaTip" }, period = 1.0, duty = 0.3, min = 0.15, stagger = true },
			{ kind = "flash", parts = { "MuzzleGlow" }, period = 2.4, min = 0.2 },
		},
	},

	-- Chandelier Nuke. Every candle flickers, the crystal drops glitter, the aura
	-- rings turn and a gold glint crosses the bands.
	chandelier_nuke = {
		finish = {
			{ parts = { "FlameA", "FlameB" }, material = "Neon", color = Color3.fromHex("FFB84A") },
			{ parts = { "DropA", "DropB", "RingDrop", "SwagDrop", "Prism", "FinialCrystal" }, material = "Glass", color = Color3.fromHex("E8F4FF"), transparency = 0.2, reflectance = 0.3 },
			{ parts = { "CrownOrb", "AuraRing" }, material = "Neon", color = Color3.fromHex("C88AFF") },
		},
		light = { part = "Shell", color = Color3.fromHex("FFC06A"), brightness = 2.0, range = 1.3 },
		particles = {
			{ part = "FlameA1", preset = "flame", color = Color3.fromHex("FFB84A"), rate = 3 },
			{ part = "FlameB1", preset = "flame", color = Color3.fromHex("FFB84A"), rate = 3 },
			{ part = "Shell", preset = "sparkle", color = Color3.fromHex("FFF2D0"), rate = 6 },
		},
		spins = {
			{ parts = { "AuraRing1" }, pivot = "Shell", axis = "Y", rpm = 5 },
			{ parts = { "AuraRing2" }, pivot = "Shell", axis = "Y", rpm = -4 },
			{ parts = { "Prism", "PendantWire" }, pivot = "Shell", axis = "Y", mode = "swing", deg = 6, period = 3.6 },
		},
		anims = {
			{ kind = "flicker", parts = { "FlameA", "FlameB" }, light = true, period = 0.25, min = 0.6, perPart = true },
			{ kind = "pulse", parts = { "CrownOrb", "AuraRing" }, period = 2.6, min = 0.4, stagger = true },
			{ kind = "glitter", parts = { "DropA", "DropB", "RingDrop" }, period = 2.0, duration = 0.2 },
		},
		glint = { parts = { "GoldBand", "Filigree", "Shell" }, period = 4, sweep = 0.8, color = GLINT_GOLD, strength = 1.5, stars = 3 },
	},

	-- Fulgurite Nuke. Lightning strikes from the cloud to the shell, ball lightning
	-- orbits, and the veins and molten pool glow.
	fulgurite_nuke = {
		finish = {
			{ parts = { "Bolt", "Branch", "BoltCore", "GroundStrike", "GroundStrikeCore", "StrikePoint" }, material = "Neon", color = Color3.fromHex("CFE8FF") },
			{ parts = { "BallLightning", "BallRing", "PlasmaHalo", "CloudGlow" }, material = "Neon", color = Color3.fromHex("8AB8FF") },
			{ parts = { "Vein", "RootGlow", "MoltenPool" }, material = "Neon", color = Color3.fromHex("FF8A2A") },
		},
		light = { part = "FusedShell", color = Color3.fromHex("A8CCFF"), brightness = 2.2, range = 1.3 },
		particles = {
			{ part = "BallLightning1", preset = "arcSpark", color = Color3.fromHex("CFE8FF"), rate = 4 },
			{ part = "MoltenPool", preset = "ember", color = Color3.fromHex("FF9A3A"), rate = 5 },
			{ part = "Cloud1", preset = "smoke", color = Color3.fromHex("2A2A38"), rate = 3 },
		},
		spins = {
			{ parts = { "BallLightning", "BallRing" }, pivot = "FusedShell", axis = "Y", rpm = 8 },
			{ parts = { "OrbitShard" }, pivot = "FusedShell", axis = "Y", rpm = -5 },
			{ parts = { "PlasmaHalo" }, pivot = "FusedShell", axis = "Y", rpm = 4 },
		},
		anims = {
			{ kind = "flash", parts = { "Bolt", "Branch", "BoltCore", "GroundStrike", "GroundStrikeCore" }, light = true, period = 1.8, min = 0.1 },
			{ kind = "flicker", parts = { "BallLightning", "PlasmaHalo", "CloudGlow" }, period = 0.3, min = 0.4, perPart = true },
			{ kind = "smoulder", parts = { "Vein", "RootGlow", "MoltenPool" }, period = 3.0, min = 0.4 },
		},
		bolts = {
			{ from = "Cloud1", to = "FusedShell", color = Color3.fromHex("CFE8FF"), period = 2.2, duration = 0.25, segments = 7, jitter = 0.15, width = 0.08 },
			{ from = "BallLightning1", to = "BallLightning3", color = Color3.fromHex("8AB8FF"), period = 3.0, duration = 0.2, segments = 5, jitter = 0.2, width = 0.05 },
		},
		ping = { part = "Crater", color = Color3.fromHex("A8CCFF"), period = 3.6 },
	},

	-- Mirage Nuke. Half there: the shell plates fade in and out, the halo eye
	-- watches, blades and shards orbit, the sand vortex spins.
	mirage_nuke = {
		finish = {
			{ parts = { "MirrorSlab", "Reflection", "GlassSpike", "GlassFloor" }, material = "Glass", color = Color3.fromHex("DDF4FF"), transparency = 0.3, reflectance = 0.5 },
			{ parts = { "Shimmer", "ReflBand", "LightPillar", "CoreRay", "NoseSpark" }, material = "Neon", color = Color3.fromHex("FFE6B0") },
			{ parts = { "HaloIris" }, material = "Neon", color = Color3.fromHex("3AE8FF") },
			{ parts = { "VoidCore", "HaloPupil" }, material = "SmoothPlastic", color = Color3.fromHex("05060A") },
		},
		light = { part = "HaloEyeBall", color = Color3.fromHex("FFE6B0"), brightness = 2.4, range = 1.4 },
		particles = {
			{ part = "SandVortex", preset = "drift", color = Color3.fromHex("F0D8A0"), rate = 8 },
			{ part = "HaloEyeBall", preset = "sparkle", color = Color3.fromHex("FFFFFF"), rate = 5 },
			{ part = "VoidCore", preset = "shrinkMotes", color = Color3.fromHex("9AE8FF"), rate = 10 },
		},
		spins = {
			{ parts = { "Blade" }, pivot = "VoidCore", axis = "Y", rpm = 6 },
			{ parts = { "OrbitShard" }, pivot = "VoidCore", axis = "Y", rpm = -8 },
			{ parts = { "SunburstRing" }, pivot = "HaloEyeBall", axis = "Z", rpm = 4 },
			{ parts = { "SandVortex" }, pivot = "SandVortex", axis = "Y", rpm = 20 },
		},
		anims = {
			{ kind = "pulse", parts = { "Plate", "FinShard", "NoseShard", "GateEdge" }, mode = "transparency", period = 5.0, min = 0.35 },
			{ kind = "pulse", parts = { "Shimmer", "ReflBand", "LightPillar", "CoreRay" }, light = true, period = 2.4, min = 0.35, stagger = true },
			{ kind = "pulse", parts = { "HaloIris" }, period = 3.0, min = 0.5 },
		},
		glint = { parts = { "MirrorSlab", "Reflection" }, period = 3, sweep = 0.6, color = Color3.fromHex("FFFFFF"), strength = 1.8, stars = 3 },
		ping = { part = "VoidCore", color = Color3.fromHex("FFE6B0"), period = 3.2 },
	},

	-- ── Stage 11: Bloodrock Rift (batch 20) ──

	-- Rubble Nuke. Hot cracks smoulder through the rock and embers spit from the nose.
	rubble_nuke = {
		finish = {
			{ parts = { "Crack" }, material = "Neon", color = Color3.fromHex("FF5A2A") },
		},
		light = { part = "Body", color = Color3.fromHex("FF5A2A"), brightness = 0.8, range = 0.7 },
		particles = {
			{ part = "NoseChunk", preset = "ember", color = Color3.fromHex("FF8A3A"), rate = 2 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Crack" }, light = true, period = 3.4, min = 0.4 },
		},
	},

	-- Bloodstone Nuke. The red gem beats like a heart; the flecks catch the light.
	bloodstone_nuke = {
		finish = {
			{ parts = { "Gem", "FinGem" }, material = "Neon", color = Color3.fromHex("FF2A3A") },
			{ parts = { "Vein" }, material = "Neon", color = Color3.fromHex("B0101E") },
			{ parts = { "Fleck" }, color = Color3.fromHex("C8202E") },
		},
		light = { part = "Gem", color = Color3.fromHex("FF2A3A"), brightness = 1.0, range = 0.8 },
		anims = {
			{ kind = "heartbeat", parts = { "Gem", "FinGem" }, light = true, period = 1.6, min = 0.45 },
			{ kind = "smoulder", parts = { "Vein" }, period = 3.0, min = 0.5 },
			{ kind = "glitter", parts = { "Fleck" }, period = 2.2, duration = 0.2 },
		},
	},

	-- Ruby Vein Nuke. The ruby crystals turn to lit glass and glitter; the veins glow.
	ruby_vein_nuke = {
		finish = {
			{ parts = { "Cluster*", "Crown*", "FinCrystal*", "GroundCrystal*" }, material = "Glass", color = Color3.fromHex("E0182E"), transparency = 0.15 },
			{ parts = { "Vein" }, material = "Neon", color = Color3.fromHex("FF3A4E") },
		},
		light = { part = "CrownMainPrism", color = Color3.fromHex("FF3A4E"), brightness = 1.3, range = 1.0 },
		particles = {
			{ part = "CrownMainTip", preset = "sparkle", color = Color3.fromHex("FFB0B8"), rate = 4 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Vein" }, light = true, period = 3.0, min = 0.45 },
			{ kind = "glitter", parts = { "Cluster*", "Crown*" }, period = 2.4, duration = 0.25 },
		},
	},

	-- Chasm Nuke. Chained over the drop: vents and nose glow, embers rise, heat rings turn.
	chasm_nuke = {
		finish = {
			{ parts = { "NoseGlow", "Vent", "Ember" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
			{ parts = { "HeatRing" }, material = "Neon", color = Color3.fromHex("FFB23A"), transparency = 0.4 },
		},
		light = { part = "NoseGlow", color = Color3.fromHex("FF6A1A"), brightness = 1.4, range = 1.0 },
		particles = {
			{ part = "Vent1", preset = "ember", color = Color3.fromHex("FF8A3A"), rate = 3 },
			{ part = "Vent2", preset = "smoke", color = Color3.fromHex("3A2A2A"), rate = 2 },
		},
		spins = {
			{ parts = { "HeatRing" }, pivot = "Body", axis = "Y", rpm = 5 },
			{ parts = { "Ember" }, pivot = "Body", axis = "Y", mode = "bob", amp = 0.08, period = 2.6, rpm = -3 },
		},
		anims = {
			{ kind = "smoulder", parts = { "NoseGlow", "Vent", "Ember" }, light = true, period = 2.8, min = 0.4 },
		},
	},

	-- Carousel Nuke. The riders go round, the bulbs chase, the top orb glows.
	carousel_nuke = {
		finish = {
			{ parts = { "RimBulb", "RoofBulb", "SkirtBulb" }, material = "Neon", color = Color3.fromHex("FFD98A") },
			{ parts = { "TopOrb", "RiderGem" }, material = "Neon", color = Color3.fromHex("FF4A6A") },
		},
		light = { part = "CanopyUnder", color = Color3.fromHex("FFD98A"), brightness = 1.2, range = 1.0 },
		spins = {
			{ parts = { "Rider*", "Saddle", "Pole", "PoleTwist" }, pivot = "Mast", axis = "Y", rpm = 6 },
			{ parts = { "Flag" }, pivot = "FlagPole", axis = "Y", mode = "swing", deg = 20, period = 1.6 },
		},
		anims = {
			{ kind = "blink", parts = { "RimBulb", "RoofBulb", "SkirtBulb" }, period = 1.2, duty = 0.5, min = 0.3, stagger = true },
			{ kind = "pulse", parts = { "TopOrb", "RiderGem" }, light = true, period = 2.4, min = 0.5 },
		},
	},

	-- Dragon Egg Nuke. Fire leaks through the cracks, the eye glows, the nest smoulders.
	dragon_egg_nuke = {
		finish = {
			{ parts = { "Crack", "CrackHole" }, material = "Neon", color = Color3.fromHex("FF7A1A") },
			{ parts = { "Eye" }, material = "Neon", color = Color3.fromHex("FFD23A") },
			{ parts = { "Ember", "Spark" }, material = "Neon", color = Color3.fromHex("FF5A1A") },
			{ parts = { "Wisp", "WispCore", "HeatRing" }, material = "Neon", color = Color3.fromHex("FFB23A"), transparency = 0.35 },
		},
		light = { part = "CrackHole", color = Color3.fromHex("FF7A1A"), brightness = 1.8, range = 1.2 },
		particles = {
			{ part = "WispCore", preset = "flame", color = Color3.fromHex("FF8A2A"), rate = 4 },
			{ part = "AshBed", preset = "ember", color = Color3.fromHex("FF6A2A"), rate = 3 },
		},
		spins = {
			{ parts = { "HeatRing" }, pivot = "Egg", axis = "Y", rpm = 6 },
			{ parts = { "Wisp", "WispCore" }, pivot = "WispCore", axis = "Y", mode = "bob", amp = 0.3, period = 2.2, rpm = 12 },
			{ parts = { "Pupil" }, pivot = "Eye", axis = "Y", mode = "twitch", deg = 15, period = 3.0, duration = 0.3 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Crack", "CrackHole", "Ember" }, light = true, period = 2.6, min = 0.4 },
			{ kind = "pulse", parts = { "Eye" }, period = 3.2, min = 0.5 },
			{ kind = "flicker", parts = { "Spark" }, period = 0.15, min = 0.2, perPart = true },
		},
	},

	-- Tesla Coil Nuke. Lightning cracks off the toroid; streamers and arcs flicker.
	tesla_coil_nuke = {
		finish = {
			{ parts = { "Arc", "ArcCore", "Streamer", "StreamerTip", "StreamerFork", "BallArc", "GapSpark" }, material = "Neon", color = Color3.fromHex("A8D8FF") },
			{ parts = { "ArcRing", "BallArcRing" }, material = "Neon", color = Color3.fromHex("7AB8FF"), transparency = 0.4 },
			{ parts = { "Coil" }, reflectance = 0.3 },
		},
		light = { part = "Toroid", color = Color3.fromHex("8AC8FF"), brightness = 1.8, range = 1.2 },
		particles = {
			{ part = "RodBall1", preset = "sparkle", color = Color3.fromHex("CFE8FF"), rate = 4 },
		},
		spins = {
			{ parts = { "ArcRing" }, pivot = "Toroid", axis = "Y", rpm = 10 },
			{ parts = { "BallArc", "BallArcRing" }, pivot = "Toroid", axis = "Y", rpm = -14 },
		},
		anims = {
			{ kind = "flicker", parts = { "Arc", "ArcCore", "Streamer", "StreamerTip", "StreamerFork", "BallArc", "GapSpark" }, light = true, period = 0.12, min = 0.2, perPart = true },
		},
		bolts = {
			{ from = "Toroid", to = "RodBall1", color = Color3.fromHex("A8D8FF"), period = 1.4, duration = 0.16 },
			{ from = "Toroid", to = "RodBall2", color = Color3.fromHex("A8D8FF"), period = 1.8, duration = 0.14 },
			{ from = "GapBall1", to = "GapBall2", color = Color3.fromHex("CFE8FF"), period = 0.9, duration = 0.12 },
		},
		glint = { parts = { "Coil" }, period = 4, sweep = 0.7, color = Color3.fromHex("CFE8FF"), strength = 1.3 },
	},

	-- Rift Heart Nuke. The heart beats red inside its ribs; two rings of rock orbit it.
	rift_heart_nuke = {
		finish = {
			{ parts = { "HeartCore" }, material = "Neon", color = Color3.fromHex("FF1A34") },
			{ parts = { "FacetVein" }, material = "Neon", color = Color3.fromHex("FF5A6A") },
			{ parts = { "Aura" }, material = "Neon", color = Color3.fromHex("FF2A44"), transparency = 0.7 },
			{ parts = { "BloodShard*", "CrownCrystal*", "CrownCore*" }, material = "Glass", color = Color3.fromHex("C8102A"), transparency = 0.15 },
			{ parts = { "Halo", "RingTrail1", "RingTrail2", "PedestalCrack" }, material = "Neon", color = Color3.fromHex("FF4A5E") },
		},
		light = { part = "HeartCore", color = Color3.fromHex("FF1A34"), brightness = 2.0, range = 1.3 },
		particles = {
			{ part = "HeartCore", preset = "drift", color = Color3.fromHex("FF4A5E"), rate = 4 },
		},
		spins = {
			{ parts = { "RingRock1*", "RingChip1*", "RingTrail1" }, pivot = "HeartCore", axis = "Y", rpm = 6 },
			{ parts = { "RingRock2*", "RingChip2*", "RingTrail2" }, pivot = "HeartCore", axis = "Y", rpm = -9 },
			{ parts = { "Halo" }, pivot = "Halo", axis = "Y", mode = "bob", amp = 2, period = 2.8, rpm = 8 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "HeartCore", "FacetVein", "Aura" }, light = true, period = 1.2, min = 0.4 },
			{ kind = "glitter", parts = { "BloodShard*", "CrownCrystal*" }, period = 2.4, duration = 0.2 },
			{ kind = "smoulder", parts = { "PedestalCrack" }, period = 3.0, min = 0.4 },
		},
	},

	-- Black Hole Nuke. The accretion disk whirls round a pitch-black horizon; jets pulse.
	black_hole_nuke = {
		finish = {
			{ parts = { "EventHorizon" }, material = "SmoothPlastic", color = Color3.fromHex("000000") },
			{ parts = { "PhotonRing", "NoseCutGlow", "TailCutGlow" }, material = "Neon", color = Color3.fromHex("FFD9A0") },
			{ parts = { "DiskBand", "Stretched" }, material = "Neon", color = Color3.fromHex("FF8A2A") },
			{ parts = { "LensRing", "LensRing2" }, material = "Glass", transparency = 0.6 },
			{ parts = { "JetBeam", "JetRing" }, material = "Neon", color = Color3.fromHex("7AB8FF"), transparency = 0.3 },
			{ parts = { "Star" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
		},
		light = { part = "PhotonRing", color = Color3.fromHex("FFB06A"), brightness = 1.8, range = 1.2 },
		spins = {
			{ parts = { "DiskBand", "Stretched" }, pivot = "EventHorizon", axis = "Y", rpm = 14 },
			{ parts = { "Debris" }, pivot = "EventHorizon", axis = "Y", rpm = 9 },
			{ parts = { "PhotonRing" }, pivot = "EventHorizon", axis = "Y", rpm = -6 },
			{ parts = { "JetRing" }, pivot = "JetBeam", axis = "Y", mode = "bob", amp = 0.15, period = 1.4 },
		},
		anims = {
			{ kind = "pulse", parts = { "JetBeam", "JetRing" }, period = 1.4, min = 0.4 },
			{ kind = "smoulder", parts = { "DiskBand", "PhotonRing" }, light = true, period = 2.6, min = 0.6 },
			{ kind = "wink", parts = { "Star" }, period = 1.6, min = 0.2, perPart = true },
		},
	},

	-- Rift Nuke. Split in two: the halves drift apart and back over a crackling void,
	-- glitch cubes blink, runes chase, the core's orbits spin.
	rift_nuke = {
		finish = {
			{ parts = { "RiftVoid" }, material = "SmoothPlastic", color = Color3.fromHex("08000F") },
			{ parts = { "RiftEdge", "RiftCrackle", "Strand" }, material = "Neon", color = Color3.fromHex("D84AFF") },
			{ parts = { "RiftStar", "HalfAStar", "HalfBStar" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
			{ parts = { "RiftCore", "CoreOrbit" }, material = "Neon", color = Color3.fromHex("FF4AE0") },
			{ parts = { "Rune", "HalfASigilCore", "HalfBSigilCore", "HalfASigilRing", "HalfBSigilRing" }, material = "Neon", color = Color3.fromHex("9A6AFF") },
			{ parts = { "HalfAThrusterGlow", "HalfBThrusterGlow", "HalfAThrusterFlame", "HalfBThrusterFlame", "HalfANoseSpark", "HalfBNoseSpark" }, material = "Neon", color = Color3.fromHex("6AE8FF") },
			{ parts = { "GlitchCube" }, material = "Neon", color = Color3.fromHex("4AFFE0"), transparency = 0.2 },
			{ parts = { "HalfACutFace", "HalfBCutFace", "HalfAVoidFace", "HalfBVoidFace" }, material = "SmoothPlastic", color = Color3.fromHex("12001E") },
		},
		light = { part = "RiftCore", color = Color3.fromHex("D84AFF"), brightness = 2.2, range = 1.4 },
		particles = {
			{ part = "RiftCore", preset = "sparkle", color = Color3.fromHex("F0B8FF"), rate = 6 },
			{ part = "HalfAThrusterCore", preset = "flame", color = Color3.fromHex("6AE8FF"), rate = 3 },
			{ part = "HalfBThrusterCore", preset = "flame", color = Color3.fromHex("6AE8FF"), rate = 3 },
		},
		spins = {
			{ parts = { "HalfA*" }, pivot = "HalfAShell", axisParts = { "RiftCore", "HalfAShell" }, mode = "bob", amp = 0.04, period = 3.2 },
			{ parts = { "HalfB*" }, pivot = "HalfBShell", axisParts = { "RiftCore", "HalfBShell" }, mode = "bob", amp = 0.04, period = 3.2 },
			{ parts = { "CoreOrbit" }, pivot = "RiftCore", axis = "Y", rpm = 20 },
			{ parts = { "Rune1*", "RuneBand1" }, pivot = "RiftCore", axis = "Y", rpm = 4 },
			{ parts = { "Rune2*", "RuneBand2" }, pivot = "RiftCore", axis = "Y", rpm = -4 },
			{ parts = { "GlitchCube" }, pivot = "RiftCore", axis = "Y", mode = "bob", amp = 0.3, period = 2.4, rpm = 8 },
			{ parts = { "Shard" }, pivot = "RiftCore", axis = "Y", mode = "bob", amp = 0.2, period = 3.6, rpm = -5 },
		},
		anims = {
			{ kind = "flicker", parts = { "RiftEdge", "RiftCrackle", "Strand" }, light = true, period = 0.14, min = 0.3, perPart = true },
			{ kind = "wink", parts = { "RiftStar", "HalfAStar", "HalfBStar" }, period = 1.4, min = 0.2, perPart = true },
			{ kind = "blink", parts = { "Rune" }, period = 2.0, duty = 0.5, min = 0.3, stagger = true },
			{ kind = "pulse", parts = { "RiftCore", "CoreOrbit" }, period = 1.8, min = 0.5 },
		},
	},

	-- ── STAGE 12: GROUND ZERO ────────────────────────────────────────────────

	-- Fallout Nuke. The beacon blinks and the Geiger dial glows over a crater still
	-- shedding ash.
	fallout_nuke = {
		finish = {
			{ parts = { "Beacon" }, material = "Neon", color = Color3.fromHex("FF3A2A") },
			{ parts = { "CounterDial" }, material = "Neon", color = Color3.fromHex("B8FF6A") },
			{ parts = { "Crack" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
		},
		light = { part = "Beacon", color = Color3.fromHex("FF3A2A"), brightness = 1.6, range = 1.1 },
		particles = {
			{ part = "Crater", preset = "drift", color = Color3.fromHex("9A9A8A"), rate = 3 },
		},
		anims = {
			{ kind = "blink", parts = { "Beacon" }, light = true, period = 1.2, duty = 0.5, min = 0.2 },
			{ kind = "flicker", parts = { "CounterDial" }, period = 0.15, min = 0.5 },
			{ kind = "smoulder", parts = { "Crack" }, period = 3.0, min = 0.4 },
		},
	},

	-- Warhead Nuke. Arming lights chase round the shell, the fuse tip pulses and the
	-- nozzle burns on its launch pad.
	warhead_nuke = {
		finish = {
			{ parts = { "ArmLight" }, material = "Neon", color = Color3.fromHex("FF3A2A") },
			{ parts = { "FuseTip" }, material = "Neon", color = Color3.fromHex("FFB03A") },
			{ parts = { "NozzleGlow", "Flame" }, material = "Neon", color = Color3.fromHex("FF7A1A") },
			{ parts = { "PadLight" }, material = "Neon", color = Color3.fromHex("FFD23A") },
		},
		light = { part = "NozzleGlow", color = Color3.fromHex("FF7A1A"), brightness = 1.8, range = 1.1 },
		particles = {
			{ part = "Flame", preset = "flame", color = Color3.fromHex("FF8A2A"), rate = 5 },
			{ part = "Pad", preset = "smoke", color = Color3.fromHex("8A8A8A"), rate = 2 },
		},
		anims = {
			{ kind = "blink", parts = { "ArmLight" }, period = 1.2, duty = 0.4, min = 0.2, stagger = true },
			{ kind = "blink", parts = { "PadLight" }, period = 1.6, duty = 0.5, min = 0.3, stagger = true },
			{ kind = "pulse", parts = { "FuseTip" }, period = 0.8, min = 0.3 },
			{ kind = "flicker", parts = { "Flame", "NozzleGlow" }, light = true, period = 0.12, min = 0.5 },
		},
	},

	-- Shockwave Nuke. The flash fires, pressure rings ride up and down and the debris
	-- ring turns round the blast.
	shockwave_nuke = {
		finish = {
			{ parts = { "Flash" }, material = "Neon", color = Color3.fromHex("FFF6D0") },
			{ parts = { "FlashHalo" }, material = "Neon", color = Color3.fromHex("FFD88A"), transparency = 0.5 },
			{ parts = { "GlowBand", "Slot" }, material = "Neon", color = Color3.fromHex("FFB03A") },
			{ parts = { "PressureRing" }, material = "Neon", color = Color3.fromHex("CFEAFF"), transparency = 0.4 },
		},
		light = { part = "Flash", color = Color3.fromHex("FFE2A0"), brightness = 2.0, range = 1.3 },
		particles = {
			{ part = "Ground", preset = "smoke", color = Color3.fromHex("B89A7A"), rate = 3 },
		},
		spins = {
			{ parts = { "Debris", "DustWall" }, pivot = "Flash", axis = "Y", rpm = 4 },
			{ parts = { "PressureRing" }, pivot = "Flash", axis = "Y", mode = "bob", amp = 0.6, period = 2.2 },
		},
		anims = {
			{ kind = "flash", parts = { "Flash", "FlashHalo" }, light = true, period = 2.2, min = 0.4 },
			{ kind = "pulse", parts = { "GlowBand", "Slot" }, period = 1.6, min = 0.5 },
		},
		ping = { part = "Flash", color = Color3.fromHex("FFE2A0"), period = 2.2 },
	},

	-- Mushroom Cloud Nuke. The cap turns, fire smoulders underneath and embers and
	-- smoke drift off the top.
	mushroom_cloud_nuke = {
		finish = {
			{ parts = { "CapFire", "CapGlow" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
			{ parts = { "StemCore", "NoseBurst" }, material = "Neon", color = Color3.fromHex("FFB03A") },
			{ parts = { "Ember" }, material = "Neon", color = Color3.fromHex("FF8A2A") },
		},
		light = { part = "CapGlow", color = Color3.fromHex("FF7A2A"), brightness = 1.8, range = 1.2 },
		particles = {
			{ part = "CapTop", preset = "ember", color = Color3.fromHex("FF8A2A"), rate = 4 },
			{ part = "CapTop", preset = "smoke", color = Color3.fromHex("6A5A4A"), rate = 2 },
		},
		spins = {
			{ parts = { "CapRoll", "CapFire", "CapInner", "Ember" }, pivot = "StemCore", axis = "Y", rpm = 3 },
			{ parts = { "VaporRing" }, pivot = "StemCore", axis = "Y", mode = "bob", amp = 0.08, period = 3.0, rpm = -4 },
		},
		anims = {
			{ kind = "smoulder", parts = { "CapFire", "CapGlow" }, light = true, period = 2.8, min = 0.4 },
			{ kind = "pulse", parts = { "StemCore", "NoseBurst" }, period = 1.8, min = 0.5 },
			{ kind = "wink", parts = { "Ember" }, period = 1.2, min = 0.2, perPart = true },
		},
	},

	-- Reactor Nuke. The open core glows Cherenkov blue, control rods pump in and out
	-- in a wave and the corner beacons chase.
	reactor_core_nuke = {
		finish = {
			{ parts = { "Core" }, material = "Neon", color = Color3.fromHex("3AC8FF") },
			{ parts = { "CutRim" }, material = "Neon", color = Color3.fromHex("8AE6FF") },
			{ parts = { "Beacon" }, material = "Neon", color = Color3.fromHex("FFB03A") },
			{ parts = { "Drip" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
		},
		light = { part = "Core", color = Color3.fromHex("3AC8FF"), brightness = 2.0, range = 1.3 },
		particles = {
			{ part = "Core", preset = "sparkle", color = Color3.fromHex("A8ECFF"), rate = 4 },
			{ part = "Pad", preset = "steam", color = Color3.fromHex("DDEEFF"), rate = 2 },
		},
		spins = {
			{ parts = { "ControlRod1", "RodCap1" }, pivot = "ControlRod1", axis = "Y", mode = "bob", amp = 0.15, period = 2.4, phase = 0 },
			{ parts = { "ControlRod2", "RodCap2" }, pivot = "ControlRod2", axis = "Y", mode = "bob", amp = 0.15, period = 2.4, phase = 0.2 },
			{ parts = { "ControlRod3", "RodCap3" }, pivot = "ControlRod3", axis = "Y", mode = "bob", amp = 0.15, period = 2.4, phase = 0.4 },
			{ parts = { "ControlRod4", "RodCap4" }, pivot = "ControlRod4", axis = "Y", mode = "bob", amp = 0.15, period = 2.4, phase = 0.6 },
			{ parts = { "ControlRod5", "RodCap5" }, pivot = "ControlRod5", axis = "Y", mode = "bob", amp = 0.15, period = 2.4, phase = 0.8 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "Core", "CutRim" }, light = true, period = 1.6, min = 0.5 },
			{ kind = "blink", parts = { "Beacon" }, period = 1.2, duty = 0.3, min = 0.2, stagger = true },
			{ kind = "wink", parts = { "Drip" }, period = 1.8, min = 0.3, perPart = true },
		},
	},

	-- Solar Flare Nuke. A sun in a split shell: granules churn, flares crackle and two
	-- planets orbit it, each on its own tilted ring.
	solar_flare_nuke = {
		finish = {
			{ parts = { "Sun" }, material = "Neon", color = Color3.fromHex("FFB21A") },
			{ parts = { "Granule" }, material = "Neon", color = Color3.fromHex("FFD04A") },
			{ parts = { "Corona", "FlareArc" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
			{ parts = { "Halo" }, material = "Neon", color = Color3.fromHex("FFE08A"), transparency = 0.6 },
			{ parts = { "CutRim" }, material = "Neon", color = Color3.fromHex("FFC04A") },
		},
		light = { part = "Sun", color = Color3.fromHex("FFB03A"), brightness = 2.4, range = 1.5 },
		particles = {
			{ part = "Sun", preset = "ember", color = Color3.fromHex("FFB03A"), rate = 5 },
		},
		spins = {
			{ parts = { "Sun", "Granule", "Corona" }, pivot = "Sun", axis = "Y", rpm = 3 },
			-- Each ring's normal, measured off its planets (Sun is unrotated, so
			-- pivot-local is the template's own frame).
			{ parts = { "Planet1*", "OrbitRing1" }, pivot = "Sun", axisVector = Vector3.new(0.195, -0.921, 0.337), rpm = 8 },
			{ parts = { "Planet2*", "OrbitRing2" }, pivot = "Sun", axisVector = Vector3.new(-0.148, -0.955, -0.256), rpm = -5 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Sun", "Granule" }, light = true, period = 2.4, min = 0.6 },
			{ kind = "flicker", parts = { "FlareArc", "Corona" }, period = 0.2, min = 0.4, perPart = true },
			{ kind = "pulse", parts = { "Halo" }, period = 3.0, min = 0.5 },
		},
	},

	-- Ground Zero Nuke. The light pillar breathes over a molten crater, pillar rings
	-- climb, and chevrons chase down the shell.
	ground_zero_nuke = {
		finish = {
			{ parts = { "LightPillar" }, material = "Neon", color = Color3.fromHex("FFF2C8"), transparency = 0.3 },
			{ parts = { "PillarRing" }, material = "Neon", color = Color3.fromHex("FFD88A") },
			{ parts = { "CraterHeart", "Crack" }, material = "Neon", color = Color3.fromHex("FF5A1A") },
			{ parts = { "CapUnderglow", "NoseFlare" }, material = "Neon", color = Color3.fromHex("FF8A2A") },
			{ parts = { "Chevron" }, material = "Neon", color = Color3.fromHex("FFD23A") },
			{ parts = { "Shockwave" }, material = "Neon", color = Color3.fromHex("FFE2A0"), transparency = 0.5 },
		},
		light = { part = "CraterHeart", color = Color3.fromHex("FF7A2A"), brightness = 2.2, range = 1.4 },
		particles = {
			{ part = "CraterHeart", preset = "ember", color = Color3.fromHex("FF8A2A"), rate = 5 },
			{ part = "CapDome", preset = "smoke", color = Color3.fromHex("5A4A3A"), rate = 2 },
		},
		spins = {
			{ parts = { "PillarRing" }, pivot = "LightPillar", axis = "Y", mode = "bob", amp = 0.2, period = 2.6, rpm = 6 },
			{ parts = { "Debris" }, pivot = "CraterHeart", axis = "Y", rpm = 3 },
		},
		anims = {
			{ kind = "smoulder", parts = { "CraterHeart", "Crack" }, light = true, period = 2.6, min = 0.4 },
			{ kind = "pulse", parts = { "LightPillar", "CapUnderglow" }, period = 1.8, min = 0.5 },
			{ kind = "blink", parts = { "Chevron" }, period = 1.4, duty = 0.4, min = 0.3, stagger = true },
		},
		ping = { part = "Shockwave", color = Color3.fromHex("FFD88A"), period = 3.0 },
	},

	-- Atom Nuke. Split open on its nucleus: the nucleons jostle, the whole electron
	-- cloud turns round it and sparks crackle along the field lines. All three
	-- orbits turn as one rigid group, so each electron stays on its drawn ring.
	atom_nuke = {
		finish = {
			{ parts = { "NucleusCore" }, material = "Neon", color = Color3.fromHex("7AF0FF") },
			{ parts = { "Electron" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
			{ parts = { "Trail" }, material = "Neon", color = Color3.fromHex("6AC8FF"), transparency = 0.4 },
			{ parts = { "OrbitPath", "FieldLine" }, material = "Neon", color = Color3.fromHex("4A9AFF"), transparency = 0.5 },
			{ parts = { "CutGlow" }, material = "Neon", color = Color3.fromHex("8AE6FF") },
			{ parts = { "Spark" }, material = "Neon", color = Color3.fromHex("E0F8FF") },
		},
		light = { part = "NucleusCore", color = Color3.fromHex("7AF0FF"), brightness = 2.4, range = 1.5 },
		particles = {
			{ part = "NucleusCore", preset = "arcSpark", color = Color3.fromHex("BFF4FF"), rate = 5 },
		},
		spins = {
			{ parts = { "Electron", "Trail", "OrbitPath" }, pivot = "NucleusCore", axis = "Y", rpm = 12 },
			{ parts = { "Nucleon", "NucleusCore" }, pivot = "NucleusCore", axis = "Y", mode = "bob", amp = 0.05, period = 1.2, rpm = -10 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "NucleusCore", "CutGlow" }, light = true, period = 1.4, min = 0.5 },
			{ kind = "wink", parts = { "Spark", "Electron" }, period = 0.6, min = 0.1, perPart = true },
			{ kind = "pulse", parts = { "FieldLine" }, period = 2.0, min = 0.4 },
		},
	},

	-- Game Over Nuke. The last one, wheeled out on its cradle: the nose lens stares,
	-- the side port throbs red, the seams smoulder and the tail smokes.
	game_over_nuke = {
		finish = {
			{ parts = { "NoseLens" }, material = "Neon", color = Color3.fromHex("FF1A1A") },
			{ parts = { "SidePortGlow", "TailGlow" }, material = "Neon", color = Color3.fromHex("FF3A1A") },
			{ parts = { "Seam", "SpineSeam", "NoseSeam" }, material = "Neon", color = Color3.fromHex("FF5A2A") },
		},
		light = { part = "NoseLens", color = Color3.fromHex("FF2A1A"), brightness = 2.6, range = 1.6 },
		particles = {
			{ part = "TailGlow", preset = "smoke", color = Color3.fromHex("4A3A3A"), rate = 3 },
			{ part = "TailGlow", preset = "ember", color = Color3.fromHex("FF4A1A"), rate = 4 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "NoseLens", "SidePortGlow" }, light = true, period = 1.8, min = 0.3 },
			{ kind = "smoulder", parts = { "TailGlow" }, period = 2.4, min = 0.4 },
			{ kind = "pulse", parts = { "Seam", "SpineSeam", "NoseSeam" }, period = 3.2, min = 0.3 },
		},
		glint = { parts = { "Body", "NoseDome", "TailSection" }, period = 4.0, sweep = 0.8, color = Color3.fromHex("FFFFFF"), strength = 1.2 },
	},
	-- ── STAGE 10: TOXIC CRYSTAL CAVES ────────────────────────────────────────

	-- Canister Nuke. A rusted drum leaking ooze: the leak and its drips hold a
	-- steady glow. No puddle (tweak-stage10-canister drops it from the template) and
	-- no flicker, on request.
	canister_nuke = {
		finish = {
			{ parts = { "LeakStream", "LeakDrop", "Drip", "DripEnd" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
		},
		light = { part = "LeakStream", color = Color3.fromHex("7CFF3A"), brightness = 1.2, range = 0.9 },
	},

	-- Stalactite Nuke. Crystal shards at the nose glitter, droplets wink and the pool
	-- under the stalagmite glows.
	stalactite_nuke = {
		finish = {
			{ parts = { "NoseCrystalPrism", "NoseCrystalTip", "NoseShard*" }, material = "Glass", color = Color3.fromHex("9AF5E8") },
			{ parts = { "StalagmiteGlow", "Pool" }, material = "Neon", color = Color3.fromHex("5AE8C8") },
			{ parts = { "Droplet", "FinDrop" }, material = "Neon", color = Color3.fromHex("B8FFF0") },
		},
		light = { part = "StalagmiteGlow", color = Color3.fromHex("5AE8C8"), brightness = 1.2, range = 1.0 },
		particles = {
			{ part = "NoseCrystalTip", preset = "sparkle", color = Color3.fromHex("C8FFF4"), rate = 3 },
		},
		anims = {
			{ kind = "glitter", parts = { "NoseCrystalPrism", "NoseShard*" }, period = 1.6, min = 0.4 },
			{ kind = "pulse", parts = { "StalagmiteGlow", "Pool" }, light = true, period = 2.6, min = 0.5 },
			{ kind = "wink", parts = { "Droplet", "FinDrop" }, period = 1.8, min = 0.2, perPart = true },
		},
	},

	-- Glowshroom Nuke. Every cap glows toxic green over violet mycelium, the loose
	-- spores circle the casing on a slow drift, and the crown cap nods on its stem.
	glowshroom_nuke = {
		finish = {
			{ parts = { "Shroom*", "CrownShroomCap", "FinShroom*", "RootShroom*" }, material = "Neon", color = Color3.fromHex("9AFF4A") },
			{ parts = { "Spore" }, material = "Neon", color = Color3.fromHex("C8FF8A") },
			{ parts = { "Mycelium" }, material = "Neon", color = Color3.fromHex("C88AFF") },
		},
		light = { part = "CrownShroomCap", color = Color3.fromHex("9AFF4A"), brightness = 1.6, range = 1.1 },
		particles = {
			{ part = "CrownShroomCap", preset = "spore", color = Color3.fromHex("C8FF8A"), rate = 4 },
		},
		spins = {
			{ parts = { "Spore" }, pivot = "Body", axis = "Y", mode = "bob", amp = 0.04, period = 3.4, rpm = 5 },
			{ parts = { "CrownShroom*" }, pivot = "CrownShroomStem", axis = "Z", mode = "swing", deg = 6, period = 3.2 },
		},
		anims = {
			{ kind = "pulse", parts = { "Shroom*", "CrownShroomCap", "FinShroom*", "RootShroom*" }, light = true, period = 2.4, min = 0.4, perPart = true },
			{ kind = "smoulder", parts = { "Mycelium" }, period = 3.0, min = 0.4 },
		},
	},

	-- Acid Flask Nuke. Acid bubbles in its cage over a live burner; fumes rise off the
	-- stopper.
	acid_flask_nuke = {
		finish = {
			{ parts = { "Acid" }, material = "Neon", color = Color3.fromHex("A8FF2A"), transparency = 0.2 },
			{ parts = { "Bubble", "TubeDrop" }, material = "Neon", color = Color3.fromHex("DAFF8A") },
			{ parts = { "BurnerFlame", "BurnerCore" }, material = "Neon", color = Color3.fromHex("3AA8FF") },
		},
		light = { part = "Acid", color = Color3.fromHex("A8FF2A"), brightness = 1.6, range = 1.1 },
		particles = {
			{ part = "BurnerFlame", preset = "flame", color = Color3.fromHex("4AB8FF"), rate = 4 },
			{ part = "Stopper", preset = "steam", color = Color3.fromHex("CFFF9A"), rate = 3 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "Acid" }, light = true, period = 1.8, min = 0.5 },
			{ kind = "wink", parts = { "Bubble", "TubeDrop" }, period = 0.9, min = 0.2, perPart = true },
			{ kind = "flicker", parts = { "BurnerFlame", "BurnerCore" }, period = 0.12, min = 0.5 },
		},
	},

	-- Crystal Cluster Nuke. Crystals burst out of the casing, the orbit shards circle
	-- and the veins glow underneath.
	crystal_cluster_nuke = {
		finish = {
			{ parts = { "Cluster*", "Crown*", "CrystalFin*", "GroundCrystal*" }, material = "Glass", color = Color3.fromHex("B86AFF") },
			{ parts = { "OrbitShard*" }, material = "Neon", color = Color3.fromHex("D8AAFF") },
			{ parts = { "Vein" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
		},
		light = { part = "CrownMainPrism", color = Color3.fromHex("B86AFF"), brightness = 1.8, range = 1.2 },
		particles = {
			{ part = "CrownMainTip", preset = "sparkle", color = Color3.fromHex("E8CCFF"), rate = 4 },
		},
		spins = {
			{ parts = { "OrbitShard*" }, pivot = "Body", axis = "Y", rpm = 6 },
		},
		anims = {
			{ kind = "glitter", parts = { "Cluster*", "Crown*" }, period = 1.8, min = 0.4 },
			{ kind = "pulse", parts = { "Vein" }, light = true, period = 2.2, min = 0.4 },
		},
	},

	-- Sludge Nuke. Slime slides off the cap, drops wink, and the splash below
	-- steams.
	sludge_nuke = {
		finish = {
			{ parts = { "SlimeCap", "SlimeDrip" }, material = "Neon", color = Color3.fromHex("6AFF2A") },
			{ parts = { "SlimeDrop", "Splash" }, material = "Neon", color = Color3.fromHex("A8FF6A") },
		},
		light = { part = "SlimeCap", color = Color3.fromHex("6AFF2A"), brightness = 1.6, range = 1.1 },
		particles = {
			{ part = "SlimeCap", preset = "drift", color = Color3.fromHex("8AFF4A"), rate = 3 },
			{ part = "Splash", preset = "steam", color = Color3.fromHex("C8FF9A"), rate = 2 },
		},
		anims = {
			{ kind = "smoulder", parts = { "SlimeCap", "SlimeDrip" }, light = true, period = 2.6, min = 0.5 },
			{ kind = "wink", parts = { "SlimeDrop", "Splash" }, period = 1.2, min = 0.2, perPart = true },
		},
	},

	-- Crystal Drill Nuke. The bit spins into the rock face, the headlamp and reactor
	-- band glow, the stack fumes and sparks fly off the tip.
	crystal_drill_nuke = {
		finish = {
			{ parts = { "HeadlampLens" }, material = "Neon", color = Color3.fromHex("FFF2B0") },
			{ parts = { "ReactorBand" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
			{ parts = { "FaceCrystal*" }, material = "Glass", color = Color3.fromHex("6AE8FF") },
		},
		light = { part = "HeadlampLens", color = Color3.fromHex("FFF2B0"), brightness = 2.0, range = 1.3 },
		particles = {
			{ part = "BitTip", preset = "arcSpark", color = Color3.fromHex("BFF4FF"), rate = 5 },
			{ part = "StackCap", preset = "smoke", color = Color3.fromHex("7A8A6A"), rate = 2 },
		},
		spins = {
			{ parts = { "DrillBit", "BitFlute", "BitTip" }, pivot = "DrillBit", axisParts = { "BitCollar", "BitTip" }, rpm = 60 },
		},
		anims = {
			{ kind = "pulse", parts = { "ReactorBand" }, period = 1.6, min = 0.5 },
			{ kind = "flicker", parts = { "HeadlampLens" }, light = true, period = 0.3, min = 0.7 },
			{ kind = "glitter", parts = { "FaceCrystal*" }, period = 2.0, min = 0.4 },
		},
	},

	-- Crystal Spider Nuke. Eyes burn, venom beads on the fangs, the web glints and the
	-- crystal spines glitter along its back.
	crystal_spider_nuke = {
		finish = {
			{ parts = { "Eye" }, material = "Neon", color = Color3.fromHex("FF2A4A") },
			{ parts = { "Venom" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
			{ parts = { "GlowBand" }, material = "Neon", color = Color3.fromHex("B86AFF") },
			{ parts = { "Spine*", "NoseCrystal*" }, material = "Glass", color = Color3.fromHex("C88AFF") },
			{ parts = { "WebLine" }, material = "Neon", color = Color3.fromHex("E8F0FF"), transparency = 0.4 },
		},
		light = { part = "Eye", color = Color3.fromHex("FF2A4A"), brightness = 1.4, range = 0.9 },
		particles = {
			{ part = "Venom", preset = "drift", color = Color3.fromHex("8AFF4A"), rate = 2 },
		},
		anims = {
			{ kind = "blink", parts = { "Eye" }, light = true, period = 2.4, duty = 0.85, min = 0.1 },
			{ kind = "wink", parts = { "Venom" }, period = 1.4, min = 0.3, perPart = true },
			{ kind = "pulse", parts = { "GlowBand", "WebLine" }, period = 2.0, min = 0.4 },
			{ kind = "glitter", parts = { "Spine*" }, period = 1.8, min = 0.4 },
		},
	},

	-- Venom Serpent Nuke. Coiled round the shell, hood flared: eyes glow, venom beads
	-- on the fangs, the tongue flicks and toxic mist curls off its spots.
	venom_serpent_nuke = {
		finish = {
			{ parts = { "Eye" }, material = "Neon", color = Color3.fromHex("FFD23A") },
			{ parts = { "Venom", "Spot" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
			{ parts = { "GlowBand", "HoodMark" }, material = "Neon", color = Color3.fromHex("A8FF4A") },
			{ parts = { "Tongue" }, material = "Neon", color = Color3.fromHex("FF3A5A") },
			{ parts = { "Mist" }, material = "Neon", color = Color3.fromHex("9AFF6A"), transparency = 0.6 },
			{ parts = { "CoilSpine*", "TailTip*" }, material = "Glass", color = Color3.fromHex("6AE8A8") },
		},
		light = { part = "Skull", color = Color3.fromHex("7CFF3A"), brightness = 1.8, range = 1.2 },
		particles = {
			{ part = "Mist1", preset = "drift", color = Color3.fromHex("9AFF6A"), rate = 3 },
			{ part = "Venom1", preset = "drift", color = Color3.fromHex("7CFF3A"), rate = 2 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "Eye" }, light = true, period = 1.6, min = 0.5 },
			{ kind = "flicker", parts = { "Tongue" }, period = 0.25, min = 0.2 },
			{ kind = "wink", parts = { "Spot", "Venom" }, period = 1.6, min = 0.3, perPart = true },
			{ kind = "pulse", parts = { "GlowBand", "HoodMark", "Mist" }, period = 2.4, min = 0.4 },
			{ kind = "glitter", parts = { "CoilSpine*" }, period = 1.8, min = 0.4 },
		},
	},

	-- Shatterpoint Nuke. The core burns through its plates, spire arcs crackle, the
	-- ring of chunks orbits and drops rise off it as the cave breaks open.
	shatterpoint_nuke = {
		finish = {
			{ parts = { "Core" }, material = "Neon", color = Color3.fromHex("7CFF3A") },
			{ parts = { "Spire*", "NoseSpire*", "NoseShard*", "TailShard*", "FinShard" }, material = "Glass", color = Color3.fromHex("A8FFD8") },
			{ parts = { "SpireArc" }, material = "Neon", color = Color3.fromHex("C8FFFF") },
			{ parts = { "RingBand" }, material = "Neon", color = Color3.fromHex("5AE8C8"), transparency = 0.3 },
			{ parts = { "RisingDrop" }, material = "Neon", color = Color3.fromHex("B8FF8A") },
		},
		light = { part = "Core", color = Color3.fromHex("7CFF3A"), brightness = 2.6, range = 1.6 },
		particles = {
			{ part = "Core", preset = "arcSpark", color = Color3.fromHex("C8FFE8"), rate = 5 },
			{ part = "Core", preset = "shrinkMotes", color = Color3.fromHex("9AFF6A"), rate = 4 },
		},
		spins = {
			{ parts = { "RingBand", "RingChunk" }, pivot = "Core", axis = "Y", rpm = 5 },
			{ parts = { "RisingDrop" }, pivot = "Core", axis = "Y", mode = "bob", amp = 0.3, period = 2.4, rpm = -6 },
		},
		anims = {
			{ kind = "heartbeat", parts = { "Core" }, light = true, period = 1.4, min = 0.5 },
			{ kind = "flicker", parts = { "SpireArc" }, period = 0.15, min = 0.3, perPart = true },
			{ kind = "glitter", parts = { "Spire*", "NoseSpire*", "TailShard*" }, period = 1.6, min = 0.4 },
			{ kind = "wink", parts = { "RisingDrop" }, period = 1.2, min = 0.2, perPart = true },
		},
		ping = { part = "Core", color = Color3.fromHex("9AFF6A"), period = 3.0 },
	},
} :: { [string]: ItemFxDef }

-- Inferno's four black chains sway like hanging chain: each link bobs on its own,
-- a wave running from the shell down to the anchor, the top link barely moving and
-- the anchor end moving most. Every group pivots on the chain's anchor so `amp`
-- means the same distance whatever each link's own thickness.
do
	local spins = ItemFx.DEFS.inferno_nuke.spins :: { any }
	local LINKS = 11
	for chain = 1, 4 do
		local anchor = `Anchor{chain}`
		for link = 1, LINKS do
			local parts = { `ChainLink{chain}_{link}` }
			if link == LINKS then
				table.insert(parts, anchor)
				table.insert(parts, `AnchorGlow{chain}`)
			end
			table.insert(spins, {
				parts = parts,
				pivot = anchor,
				axis = "Y",
				mode = "bob",
				amp = 0.2 + 1.0 * (link - 1) / (LINKS - 1),
				period = 2.4,
				phase = (chain - 1) * 0.27 - link * 0.05,
			})
		end
	end
end

-- Kraken's arms writhe: each giant arm swings about the line from its root to its
-- tip, so the curve of the arm sweeps side to side while both ends stay put. Its
-- suckers ride in the same group, or they'd peel off mid-swing (Phoenix's lesson).
-- The five small tentacles do the same, quicker, each on its own phase.
do
	local spins = ItemFx.DEFS.kraken_nuke.spins :: { any }
	for arm = 1, 4 do
		table.insert(spins, {
			parts = { `GiantArm{arm}*`, `ArmSucker{arm}*`, `ArmRoot{arm}`, `ArmTip{arm}` },
			pivot = `ArmRoot{arm}`,
			axisParts = { `ArmRoot{arm}`, `ArmTip{arm}` },
			mode = "swing",
			deg = 14,
			period = 3.2,
			phase = (arm - 1) * 0.25,
		})
	end
	for tentacle = 1, 5 do
		table.insert(spins, {
			parts = { `Tentacle{tentacle}*`, `Sucker{tentacle}*` },
			pivot = `Tentacle{tentacle}_1`,
			axisParts = { `Tentacle{tentacle}_1`, `Tentacle{tentacle}_4` },
			mode = "swing",
			deg = 18,
			period = 2.2,
			phase = (tentacle - 1) * 0.2,
		})
	end
end

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
