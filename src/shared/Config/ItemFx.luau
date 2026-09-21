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
	             so it can only darken or warm: lemon-yellow paint times a peach
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

export type ItemFxDef = {
	finish: { Finish }?,
	light: Light?,
	particles: { Particles }?,
	anims: { Anim }?,
	spins: { Spin }?,
	ping: Ping?,
	seam: Seam?,
	glint: Glint?,
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

-- Sky-Glow's ribbons and their end caps. The caps are named `AuroraRibbon<N>End<k>`,
-- which the base-name rule does not fold into `AuroraRibbon`, so they are listed.
local AURORA_RIBBONS = {
	"AuroraRibbon",
	"AuroraRibbon1End",
	"AuroraRibbon2End",
	"AuroraRibbon3End",
	"AuroraRibbon4End",
}

ItemFx.DEFS = {
	-- Atomic Bomb (Mythic). The flavour says "still glowing, still humming", so this
	-- one leaks the light. The casing seams breathe green, the tail lamp is armed.
	live_fuel_rod = {
		finish = {
			{ parts = { "CasingSeam" }, material = "Neon", color = RAD_GREEN },
			{ parts = { "TailLamp" }, material = "Neon", color = Color3.fromHex("FF3B2F") },
			{ parts = { "ArmingPlug" }, material = "Neon", color = Color3.fromHex("FFB020") },
		},
		light = { part = "Shell", color = RAD_GREEN, brightness = 1.6, range = 1.1 },
		particles = {
			{ part = "Shell", preset = "drift", color = RAD_GREEN, rate = 3 },
		},
		anims = {
			{ kind = "pulse", parts = { "CasingSeam", "ArmingPlug" }, light = true, period = 2.2, min = 0.35 },
			{ kind = "blink", parts = { "TailLamp" }, period = 1.0, duty = 0.18, min = 0.12 },
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

	-- Warped Nuke. The rift on its back is a whole portal: a dark vortex surface, three
	-- swirl bands turning at different speeds, a bright eye in the middle.
	bent_door_wheel = {
		finish = {
			{ parts = { "RiftSurface" }, material = "Neon", color = Color3.fromHex("2A1F8F"), transparency = 0.15 },
			{ parts = { "SwirlBand" }, material = "Neon", color = Color3.fromHex("56D8FF") },
			{ parts = { "RiftEye" }, material = "Neon", color = Color3.fromHex("E6FBFF") },
			{ parts = { "GlowSeam", "EmitterLens" }, material = "Neon", color = Color3.fromHex("3C8CFF") },
		},
		light = { part = "RiftEye", color = Color3.fromHex("4FA8FF"), brightness = 1.5, range = 0.9 },
		particles = {
			{ part = "RiftSurface", preset = "shrinkMotes", color = Color3.fromHex("8FD8FF"), rate = 8 },
		},
		anims = {
			{ kind = "pulse", parts = { "RiftEye", "GlowSeam", "EmitterLens" }, light = true, period = 2.6, min = 0.45 },
		},
		spins = {
			{ parts = { "SwirlBand1" }, pivot = "RiftFrame", axisParts = { "Shell", "RiftFrame" }, rpm = 16 },
			{ parts = { "SwirlBand2" }, pivot = "RiftFrame", axisParts = { "Shell", "RiftFrame" }, rpm = 24 },
			{ parts = { "SwirlBand3" }, pivot = "RiftFrame", axisParts = { "Shell", "RiftFrame" }, rpm = 34 },
		},
	},

	-- Bottled Nuke. "Packed in a glass jar": the jar is glass, and the little nuke
	-- modelled inside it finally shows.
	buried_coin_jar = {
		finish = {
			{
				parts = { "BottleBody", "BottleShoulder", "BottleNeck", "BottleBase" },
				material = "Glass",
				color = Color3.fromHex("CFE8D6"),
				transparency = 0.55,
			},
		},
		particles = {
			{ part = "BottleBody", preset = "sparkle", color = Color3.fromHex("FFFFFF"), rate = 1.5 },
		},
	},

	-- Glassy Nuke. "Fused into glass": a see-through shell with bubbles trapped in it
	-- and a warm core still glowing at the centre.
	glassy_ground_chip = {
		finish = {
			{ parts = { "Shell", "GlassDrip" }, material = "Glass", color = Color3.fromHex("5FC9BF"), transparency = 0.5 },
			{ parts = { "Bubble" }, material = "Glass", color = Color3.fromHex("F2FFFF"), transparency = 0.35 },
			{ parts = { "TrappedCore" }, material = "Neon", color = Color3.fromHex("FF8A3D") },
		},
		light = { part = "TrappedCore", color = Color3.fromHex("FF8A3D"), brightness = 0.9, range = 0.7 },
		anims = {
			{ kind = "pulse", parts = { "TrappedCore" }, light = true, period = 3.4, min = 0.5 },
		},
	},

	-- Fading Nuke. "Went dark in under a second": a ghost afterimage of the shell,
	-- plates fading out step by step, and a core that flashes and dies away.
	cracked_glow_badge = {
		finish = {
			{ parts = { "GhostShell", "GhostTail" }, material = "ForceField", color = Color3.fromHex("9FE8FF") },
			{ parts = { "FadePlate" }, ramp = { from = 0.1, to = 0.85, levels = 10 } },
			{ parts = { "Wisp" }, material = "Neon", color = Color3.fromHex("CFF4FF"), transparency = 0.4 },
			{ parts = { "FadingCore" }, material = "Neon", color = Color3.fromHex("BDF6FF") },
		},
		light = { part = "FadingCore", color = Color3.fromHex("9FE8FF"), brightness = 1.8, range = 0.9 },
		anims = {
			{ kind = "flash", parts = { "FadingCore", "Wisp" }, light = true, period = 3.2, min = 0.08 },
		},
	},

	-- Static Nuke. An arc between the two electrode horns, flickering like a bad
	-- connection, throwing sparks off its ends.
	old_headphones = {
		finish = {
			{ parts = { "Arc", "ArcEnd" }, material = "Neon", color = Color3.fromHex("D8F0FF") },
			{ parts = { "SparkNode" }, material = "Neon", color = Color3.fromHex("5AA8FF") },
		},
		light = { part = "Arc", color = Color3.fromHex("9CCBFF"), brightness = 1.6, range = 0.9 },
		particles = {
			{ part = "ArcEnd1", preset = "arcSpark", color = Color3.fromHex("CFE8FF"), rate = 10 },
			{ part = "ArcEnd2", preset = "arcSpark", color = Color3.fromHex("CFE8FF"), rate = 10 },
		},
		anims = {
			{
				kind = "flicker",
				parts = { "Arc", "ArcEnd" },
				light = true,
				period = 0.09,
				min = 0,
				onChance = 0.72,
				mode = "transparency",
			},
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

	-- Cosmic Nuke (Mythic). A working armillary. Each gimbal ring turns on its own
	-- pin axis, nested outer to inner the way a real gimbal carries its rings. The
	-- satellites orbit and the dust ring twinkles.
	stopped_second_hand = {
		finish = {
			{ parts = { "StarCore" }, material = "Neon", color = Color3.fromHex("FFF1C4") },
			{ parts = { "Corona" }, material = "Neon", color = Color3.fromHex("FFC94A"), transparency = 0.35 },
			{ parts = { "Flare" }, material = "Neon", color = Color3.fromHex("FFD66B") },
			{ parts = { "DustGrain" }, material = "Neon", color = Color3.fromHex("FFFFFF") },
		},
		light = { part = "StarCore", color = Color3.fromHex("FFD98A"), brightness = 1.7, range = 1.1 },
		particles = {
			{ part = "StarCore", preset = "sparkle", color = Color3.fromHex("FFE9A8"), rate = 7 },
		},
		anims = {
			{ kind = "pulse", parts = { "StarCore", "Corona" }, light = true, period = 4.0, min = 0.75 },
			{
				kind = "flicker",
				parts = { "DustGrain" },
				period = 0.7,
				min = 0.1,
				onChance = 0.8,
				mode = "transparency",
				perPart = true,
			},
		},
		spins = {
			-- 1: the outer ring, on the near-vertical pins the cradle holds it by.
			{
				parts = { "GimbalRing3", "GimbalSpoke31", "GimbalSpoke32", "GimbalSpoke33", "GimbalSpoke34", "GimbalPin31", "GimbalPin32" },
				pivot = "StarCore",
				axisParts = { "GimbalPin32", "GimbalPin31" },
				rpm = 4,
			},
			-- 2: the flat middle ring and its dust, carried by ring 1.
			{
				parts = { "GimbalRing2", "GimbalSpoke21", "GimbalSpoke22", "GimbalSpoke23", "GimbalSpoke24", "GimbalPin21", "GimbalPin22", "DustGrain" },
				pivot = "StarCore",
				axisParts = { "GimbalPin21", "GimbalPin22" },
				rpm = -7,
				parent = 1,
			},
			-- 3: the inner ring, carried by ring 2.
			{
				parts = { "GimbalRing1", "GimbalSpoke11", "GimbalSpoke12", "GimbalSpoke13", "GimbalSpoke14", "GimbalPin11", "GimbalPin12" },
				pivot = "StarCore",
				axisParts = { "GimbalPin11", "GimbalPin12" },
				rpm = 11,
				parent = 2,
			},
			-- 4: the satellites orbit on their own, slow.
			{ parts = { "Satellite", "SatelliteRing" }, pivot = "StarCore", axis = "Y", rpm = 2.5 },
		},
	},

	-- Sky-Glow Nuke. "Lights up the crater at night all by itself": aurora ribbons
	-- cycling colour out of step with each other, lit vane slots, and the widest
	-- light in the set.
	skyglow_core_fragment = {
		finish = {
			{ parts = { "AuroraCore" }, material = "Neon", color = Color3.fromHex("3FF2D0") },
			{ parts = AURORA_RIBBONS, material = "Neon", color = Color3.fromHex("3FF2D0") },
			{ parts = { "VaneSlot" }, material = "Neon", color = Color3.fromHex("3FF2D0"), transparency = 0.3 },
			{ parts = { "GlowBleed" }, material = "Neon", color = Color3.fromHex("3FF2D0"), transparency = 0.55 },
		},
		light = { part = "AuroraCore", color = Color3.fromHex("3FF2D0"), brightness = 1.4, range = 2.0 },
		anims = {
			{
				kind = "colorCycle",
				parts = AURORA_RIBBONS,
				period = 7,
				colors = { Color3.fromHex("3FF2D0"), Color3.fromHex("7CFF6B"), Color3.fromHex("A06BFF") },
			},
			{ kind = "pulse", parts = { "AuroraCore", "VaneSlot", "GlowBleed" }, light = true, period = 5, min = 0.6 },
		},
	},

	-- Alien Nuke. Veins with a heartbeat, and an eye that blinks now and then.
	ufo_fragment = {
		finish = {
			{ parts = { "IrisCore" }, material = "Neon", color = Color3.fromHex("D4FF3A") },
			{ parts = { "IrisRing" }, material = "Neon", color = Color3.fromHex("9CFF3A") },
			{ parts = { "Vein", "FeelerPod" }, material = "Neon", color = Color3.fromHex("7DFF2F") },
		},
		light = { part = "IrisCore", color = Color3.fromHex("9CFF3A"), brightness = 1.3, range = 0.9 },
		anims = {
			{ kind = "heartbeat", parts = { "Vein", "FeelerPod" }, light = true, period = 1.6, min = 0.35 },
			{ kind = "wink", parts = { "IrisCore", "IrisRing" }, period = 5.5, duration = 0.12, min = 0.05 },
		},
	},

	-- Black-Box Nuke. An underwater-locator-style beacon: a short orange strobe and a
	-- sonar ring off the lamp every flash.
	blackbox_recorder = {
		finish = {
			{ parts = { "BeaconLamp" }, material = "Neon", color = Color3.fromHex("FF8A1F") },
		},
		light = { part = "BeaconLamp", color = Color3.fromHex("FF8A1F"), brightness = 2.6, range = 1.2 },
		anims = {
			{ kind = "blink", parts = { "BeaconLamp" }, light = true, period = 1.4, duty = 0.09, min = 0.08 },
		},
		ping = { part = "BeaconLamp", color = Color3.fromHex("FF9A3A"), period = 1.4 },
	},

	-- ── Shine ─────────────────────────────────────────────────────────────
	-- Gold, gems and pearls don't give off light; they catch it. So none of these
	-- carry a PointLight. They shine by a warmer finish, a glint sweeping across the
	-- polished parts, and star flares as it passes.

	-- Golden Nuke. "Gold-plated. Somebody really wanted this one to shine." The
	-- whole shell is polished gold, and the signet stone on top is a clear gem.
	gold_ring = {
		finish = {
			{
				parts = { "Shell", "TailTaper", "Fin", "ChasedBand", "RingCollar", "SignetBezel" },
				tint = GOLD_TINT,
			},
			{ parts = { "SignetStone" }, material = "Glass", color = Color3.fromHex("F2FAFF"), transparency = 0.15 },
		},
		anims = {
			{ kind = "glitter", parts = { "SignetStone" }, period = 1.8, duration = 0.3 },
		},
		glint = {
			parts = { "Shell", "TailTaper", "ChasedBand", "RingCollar", "SignetBezel" },
			period = 4.5,
			sweep = 0.9,
			color = GLINT_GOLD,
			strength = 2.6,
			stars = 5,
		},
	},

	-- Gilded Nuke. "Gold doesn't care what it's welded to." Gold leaf on junk: the
	-- shell is corroded scrap, and only the gold trim and a ruby catch the glint.
	-- This is also what tells it apart from the Golden Nuke, which shares its model.
	gold_signet = {
		finish = {
			{ parts = { "Shell", "TailTaper", "Fin" }, material = "CorrodedMetal", color = Color3.fromHex("5E5249") },
			{ parts = { "ChasedBand", "RingCollar", "SignetBezel" }, tint = GOLD_TINT },
			{ parts = { "SignetStone" }, material = "Glass", color = Color3.fromHex("B0102C"), transparency = 0.1 },
		},
		anims = {
			{
				kind = "glitter",
				parts = { "SignetStone" },
				period = 2.2,
				duration = 0.3,
				colors = { Color3.fromHex("FF8A9C") },
			},
		},
		glint = {
			parts = { "ChasedBand", "RingCollar", "SignetBezel", "SignetStone" },
			period = 5,
			sweep = 0.9,
			color = GLINT_GOLD,
			strength = 2.6,
			stars = 3,
		},
	},

	-- Bullion Nuke (Epic). "Cast in gold. Somebody got greedy." A stack of bars,
	-- the most gold of the set, so the strongest and most frequent glint.
	bullion_bar = {
		finish = {
			{ parts = { "Ingot", "NoseCone", "TailTaper", "Fin" }, tint = GOLD_TINT },
		},
		particles = {
			{ part = "Ingot2", preset = "sparkle", color = Color3.fromHex("FFE7A6"), rate = 1.2 },
		},
		glint = {
			parts = { "Ingot", "NoseCone" },
			period = 3.6,
			sweep = 0.8,
			color = GLINT_GOLD,
			strength = 3,
			stars = 7,
		},
	},

	-- Diamond Nuke (Epic). "Catches light nobody else out here can see." The gem
	-- goes clear, and its facets throw white and the odd flash of rainbow fire.
	diamond_brooch = {
		finish = {
			{
				parts = { "GemPavilion", "GemCrown", "GemTable", "Culet" },
				material = "Glass",
				color = Color3.fromHex("DDF2FF"),
				transparency = 0.45,
			},
			{
				parts = { "CrownFacet", "PavilionFacet" },
				material = "Glass",
				color = Color3.fromHex("E6F6FF"),
				transparency = 0.3,
			},
		},
		particles = {
			{ part = "GemCrown", preset = "sparkle", color = Color3.fromHex("FFFFFF"), rate = 1.5 },
		},
		anims = {
			{
				kind = "glitter",
				parts = { "CrownFacet", "PavilionFacet", "GemTable" },
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
		},
		glint = {
			parts = { "GemCrown", "GemPavilion", "GemTable" },
			period = 4,
			sweep = 0.7,
			color = Color3.fromHex("F4FBFF"),
			strength = 2.6,
			stars = 6,
			starParts = { "CrownFacet", "PavilionFacet", "GemTable" },
		},
	},

	-- Pearl Nuke. "Strung with pearls, saved for good occasions." Pearls have a
	-- soft lustre, not a hard glint: a gentle band over the cream shell, and a
	-- pastel sheen that runs round the strand.
	pearl_necklace = {
		-- Warm on purpose: the sky's cyan fill turns anything near-white grey-blue,
		-- and a lilac or mint tint reads as a blue pearl.
		finish = {
			{ parts = { "Shell", "TailTaper", "Fin" }, tint = Color3.fromHex("FFE4CC") },
			{ parts = { "StrandClasp", "CrownCollar" }, tint = GOLD_TINT },
		},
		anims = {
			{
				kind = "colorCycle",
				mode = "tint",
				parts = { "Pearl", "CrownPearl" },
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
			parts = { "Shell", "TailTaper", "CrownCollar" },
			period = 5,
			sweep = 1.1,
			color = Color3.fromHex("FFF4F0"),
			strength = 2,
			stars = 5,
			starParts = { "Pearl", "CrownPearl" },
			starColor = Color3.fromHex("FFEAF4"),
			starSize = 0.4,
		},
	},

	-- ── Heat ──────────────────────────────────────────────────────────────

	-- Exposed Nuke. The casing is cut open down one side, and the core canister
	-- inside glows: the light is hung inside the frame, so it spills out through
	-- the gap onto the struts and panels. The coolant elbows vent now and then.
	-- A purer green than RAD_GREEN: a whole canister of that in Neon reads lime.
	film_canister = {
		finish = {
			{ parts = { "CoreCanister" }, material = "Neon", color = Color3.fromHex("33FF55") },
			{ parts = { "GlowRing" }, material = "Neon", color = Color3.fromHex("C4FF9A") },
		},
		light = { part = "CoreCanister", color = Color3.fromHex("33FF55"), brightness = 2, range = 1.2 },
		particles = {
			{ part = "CoreCanister", preset = "drift", color = SOFT_GREEN, rate = 2 },
			{
				part = "PipeElbow1",
				preset = "steam",
				color = Color3.fromHex("DCE8E0"),
				rate = 0,
				burstEvery = 4,
				burstCount = 6,
			},
			{
				part = "PipeElbow2",
				preset = "steam",
				color = Color3.fromHex("DCE8E0"),
				rate = 0,
				burstEvery = 5,
				burstCount = 6,
			},
		},
		anims = {
			{ kind = "pulse", parts = { "CoreCanister", "GlowRing" }, light = true, period = 2.8, min = 0.6 },
		},
	},

	-- Scorched Nuke. "Rated to hold back anything. Didn't." Still burning: the
	-- embers breathe like coals, the torn plate's tips glow, small flames lick up
	-- off it, and smoke and sparks rise. A Common, so it smoulders; no bonfire.
	-- The blister plates stay dark: lit, their flat rectangles read as stickers.
	scorched_metal_plate = {
		finish = {
			{ parts = { "Ember", "CurledPlateEnd" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
		},
		light = { part = "Ember2", color = Color3.fromHex("FF7A2A"), brightness = 1.3, range = 0.9 },
		particles = {
			{ part = "CurledPlate", preset = "flame", color = Color3.fromHex("FF8A2A"), rate = 24, outward = 0.35 },
			{
				part = "Ember3",
				preset = "flame",
				color = Color3.fromHex("FF7A22"),
				rate = 0,
				burstEvery = 2.5,
				burstCount = 5,
				outward = 0.4,
			},
			{ part = "Ember2", preset = "ember", color = Color3.fromHex("FFA040"), rate = 3, outward = 0.4 },
			{ part = "CurledPlate", preset = "smoke", color = Color3.fromHex("2E2724"), rate = 1.5, outward = 0.35 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Ember", "CurledPlateEnd" }, light = true, period = 1.6, min = 0.35 },
		},
	},

	-- Core Nuke (Legendary). "Warm through three layers of metal. Never once cooled."
	-- The lid is off, so the pit sits exposed in the throat and still glows amber: it
	-- breathes like a coal, the collar and the four initiators breathe out of step with
	-- it, and the heat runs down the three shield bands one after the other, top band
	-- first, like warmth soaking outward through the layers. Embers rise off the pit.
	-- Amber, not the Reactor Nuke's Cherenkov blue or the Scorched Nuke's fire orange.
	reactor_core_sample = {
		finish = {
			{ parts = { "Pit" }, material = "Neon", color = Color3.fromHex("FFB454") },
			{ parts = { "PitCollar" }, material = "Neon", color = Color3.fromHex("FF7A2E") },
			{ parts = { "Initiator" }, material = "Neon", color = Color3.fromHex("FF4A2A") },
			{ parts = { "ShieldBand" }, material = "Neon", color = Color3.fromHex("FF6A1A") },
		},
		light = { part = "Pit", color = Color3.fromHex("FF9A4A"), brightness = 1.9, range = 1.1 },
		particles = {
			{ part = "Pit", preset = "ember", color = Color3.fromHex("FFB454"), rate = 3 },
		},
		anims = {
			{ kind = "smoulder", parts = { "Pit", "PitCollar", "Initiator" }, light = true, period = 2.4, min = 0.55 },
			{ kind = "pulse", parts = { "ShieldBand" }, stagger = true, period = 3.6, min = 0.3 },
		},
	},
} :: { [string]: ItemFxDef }

return ItemFx
