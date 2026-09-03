--!strict
--[[
	ToolTiers.lua — what each gear tier LOOKS like. Data only, like the rest of Config/.

	One base model per track gets scaled, repainted and lit according to these rows, so
	twenty-one variants come out of three models. That is not a shortcut — it is how a
	progression should read: the family stays recognisable so a player knows at a glance
	they are looking at a detector, while size and colour tell them WHICH one.

	The progression is deliberate, and it is the same story in all three tracks:
	  scavenged junk  -> military surplus -> industrial -> laboratory -> exotic
	  rust and wood   -> olive and steel  -> yellow     -> teal/violet -> bright white

	TIER 1 IS NEVER REPAINTED. The base models were chosen because they look right;
	tier 1 ships exactly as authored, and everything above it is a departure from that.

	Row fields:
	  scale  — multiplier on the base model's size
	  body   — the large parts
	  accent — the small parts (tips, boxes, fittings)
	  material
	  glow   — nil, or a colour: an accent tint for the smallest parts (a bright cool
	           colour on the exotic tiers). NB the world has no Neon or bloom any more
	           (see Kit.C's header) -- whatever renders these must keep them matte.
]]

export type TierLook = {
	name: string,
	scale: number,
	body: Color3,
	accent: Color3,
	material: Enum.Material,
	glow: Color3?,
}

local ToolTiers = {}

-- Which model in Assets/Tools each track is built from.
--
-- CLEANER IS NO LONGER ONE OF THEM, and the entry is kept only so a place that still
-- has the old folder does not read as a missing key. That track's seven tiers are
-- built from primitives by Shared/ToolModels/Hose, in git, with a real silhouette per
-- rung instead of one model recoloured — which is also the way out of this file being
-- a recipe with no cook. Detector and Magnet still come out of the place.
ToolTiers.BASE = {
	Detector = "Detector",
	Magnet = "Magnet",
	Cleaner = "Cleaner",
}

-- Names mirror Gear.lua exactly. If they ever disagree, Gear.lua wins.
-- The detector's scale spread is deliberately TIGHT. It is carried at arm's length
-- with the coil skimming the floor, so its length is constrained by how high a
-- character's hand is off the ground (~2.1 studs) — a detector that grows 50% has to
-- be held almost horizontal to avoid burying its coil, which stops reading as
-- sweeping. Tier is carried by COLOUR here, and only nudged by size.
ToolTiers.Detector = {
	{ name = "Bent Coil", scale = 1.00, body = Color3.fromHex("6B4A2F"), accent = Color3.fromHex("3E2F22"), material = Enum.Material.Plastic },
	{ name = "Scavenger MkI", scale = 1.03, body = Color3.fromHex("7A7A72"), accent = Color3.fromHex("4A4A44"), material = Enum.Material.Metal },
	{ name = "Surplus Geiger", scale = 1.06, body = Color3.fromHex("5C6B3F"), accent = Color3.fromHex("38412A"), material = Enum.Material.Metal },
	{ name = "Pulse Array", scale = 1.09, body = Color3.fromHex("45657F"), accent = Color3.fromHex("2B3F4F"), material = Enum.Material.Metal },
	{ name = "Isotope Scanner", scale = 1.12, body = Color3.fromHex("2E8B8B"), accent = Color3.fromHex("1B5252"), material = Enum.Material.Metal, glow = Color3.fromHex("5FE3E3") },
	{ name = "Resonance Mapper", scale = 1.15, body = Color3.fromHex("6B4FA8"), accent = Color3.fromHex("3E2E63"), material = Enum.Material.Metal, glow = Color3.fromHex("B08CFF") },
	{ name = "Deep Core Array", scale = 1.19, body = Color3.fromHex("C89B3C"), accent = Color3.fromHex("7A5E24"), material = Enum.Material.Metal, glow = Color3.fromHex("FFD772") },
	{ name = "The Oracle", scale = 1.22, body = Color3.fromHex("EDEDED"), accent = Color3.fromHex("9FE8FF"), material = Enum.Material.Metal, glow = Color3.fromHex("CFF6FF") },
} :: { TierLook }

-- The magnet starts deliberately tiny (PLAN: the base tier is a toy horseshoe), so
-- this line grows more than the others. A Singularity Coil should dwarf it.
ToolTiers.Magnet = {
	{ name = "Horseshoe Magnet", scale = 1.00, body = Color3.fromHex("C0392B"), accent = Color3.fromHex("B4B8BE"), material = Enum.Material.SmoothPlastic },
	{ name = "Salvage Magnet", scale = 1.25, body = Color3.fromHex("8E3B2E"), accent = Color3.fromHex("6E7278"), material = Enum.Material.Metal },
	{ name = "Electromagnet", scale = 1.55, body = Color3.fromHex("B87333"), accent = Color3.fromHex("3A3A3A"), material = Enum.Material.Metal },
	{ name = "Winch Coil", scale = 1.90, body = Color3.fromHex("D4A017"), accent = Color3.fromHex("2E2E2E"), material = Enum.Material.Metal },
	{ name = "Rail Coil", scale = 2.30, body = Color3.fromHex("2E86DE"), accent = Color3.fromHex("1B3A5C"), material = Enum.Material.Metal, glow = Color3.fromHex("7FD0FF") },
	{ name = "Singularity Coil", scale = 2.80, body = Color3.fromHex("7A3FD4"), accent = Color3.fromHex("EDEDED"), material = Enum.Material.Metal, glow = Color3.fromHex("D6A6FF") },
} :: { TierLook }

-- THE ONLY TRACK WHOSE ROWS ARE ACTUALLY READ AT RUNTIME. The note above this table
-- used to say the line "changes OBJECT, not just finish — a Chem Bath is not a brush
-- with a different paint job", and that bespoke silhouettes were the most worthwhile
-- art job left. They got built: Shared/ToolModels/Hose authors seven hoses from
-- primitives and asks this table for their colours. So `body`, `accent`, `glow` and
-- `material` below are live values, not a recipe waiting for a cook.
--
-- `scale` IS 1.00 ALL THE WAY DOWN, AND THAT IS NOT AN OVERSIGHT. The column exists
-- because Detector and Magnet are ONE base model reused eight and six times, so a
-- multiplier is the only size knob they have. Seven authored silhouettes carry their
-- own size — the Plasma Lance is long because it is drawn long, not because it is a
-- Garden Hose blown up 50%. Keeping a second size knob on top is how a tier ends up
-- 8% off its own drawing for no reason anyone can find later. Change a hose's size in
-- ToolModels/Hose's FORMS table, not here.
--
-- "TIER 1 IS NEVER REPAINTED" (see this file's header) DOES NOT BIND HERE EITHER. That
-- rule protects a hand-authored base model that was chosen because it looked right;
-- tier 1 of this track is drawn to spec like the other six, so it gets a palette like
-- the other six. Dull rubber and grey plastic: it is the free rung and it should read
-- as the free rung.
--
-- Tier 2 is the one palette that is pinned rather than chosen — build/Plots parks a
-- tier-2 hose on every plot's pump, and hoseGreen/hoseBrass are the colours that prop
-- has always been, matched to Kit.C's own hose entries.
ToolTiers.Cleaner = {
	{ name = "Garden Hose", scale = 1.00, body = Color3.fromHex("3E7D52"), accent = Color3.fromHex("B9C2C6"), material = Enum.Material.SmoothPlastic },
	{ name = "Patched Fire Hose", scale = 1.00, body = Color3.fromHex("2FA36A"), accent = Color3.fromHex("C8A24A"), material = Enum.Material.SmoothPlastic },
	{ name = "Pressure Lance", scale = 1.00, body = Color3.fromHex("3F7FBF"), accent = Color3.fromHex("C9D6E0"), material = Enum.Material.Metal },
	{ name = "Chem Injector", scale = 1.00, body = Color3.fromHex("7A4FA8"), accent = Color3.fromHex("D8C6F0"), material = Enum.Material.Metal },
	{ name = "Ultrasonic Jet", scale = 1.00, body = Color3.fromHex("2E9BA8"), accent = Color3.fromHex("BFF2F7"), material = Enum.Material.Metal, glow = Color3.fromHex("7FE8F2") },
	{ name = "Ion Cannon", scale = 1.00, body = Color3.fromHex("EDEDED"), accent = Color3.fromHex("6FC8FF"), material = Enum.Material.Metal, glow = Color3.fromHex("9FDCFF") },
	{ name = "Plasma Lance", scale = 1.00, body = Color3.fromHex("D43FA0"), accent = Color3.fromHex("FFE0F4"), material = Enum.Material.Metal, glow = Color3.fromHex("FF9FE0") },
} :: { TierLook }

function ToolTiers.get(track: string, tier: number): TierLook
	local list = (ToolTiers :: any)[track]
	assert(list, `unknown tool track "{track}"`)
	return list[math.clamp(tier, 1, #list)]
end

function ToolTiers.count(track: string): number
	return #((ToolTiers :: any)[track])
end

return ToolTiers
