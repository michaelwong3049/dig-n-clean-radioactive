--!strict
--[[
	SulfurFlats.luau — Stage 10, Sulfur Flats: a volcanic salt pan, venting and
	steaming, crusted yellow round every crack.

	    called from build/Scenery's buildStageScenery (Stage 10)

	WHAT IS OUT HERE, landmarks first:

	  * FUMAROLES — stepped mounds of sulfur crust round a vent, needle crystals on the
	    rim, the vent still glowing in its throat and steaming on most of them.
	  * ACID POOLS — the stage's lime `ooze`, glowing, with bubbles standing on it and a
	    pale crust rim; acrid fume off a couple of them.
	  * SULFUR CRYSTALS — clusters of bright yellow needles.
	  * HEX CRUST — patches of the pan cracked into honeycomb plates, the way a drying
	    salt flat splits. Flat, so they cross the lane.
	  * THE GROUND — sulfur grit, pale crust smears and stray needles.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local SulfurFlats = {}

local SEED = 10100

local FUMAROLES = 8
local FUMAROLE_STEAM = 5
local FUMAROLE_LIGHTS = 3
local ACID_POOLS = 7
local POOL_LIGHTS = 4
local POOL_FUMES = 2
local CRYSTAL_CLUSTERS = 12
local HEX_PATCHES = 9

local CELL = 13
local GRIT_CHANCE = 0.11
local SMEAR_CHANCE = 0.12
local NEEDLE_CHANCE = 0.05

local SULFUR = { K.hex("F2E04A"), K.hex("EBD13A"), K.hex("F7EA6A") }
--- Ochre and rust-brown, not more yellow: the mustard ground swallowed every yellow
--- crust shot live, so the smears and skirts go darker to separate from it.
local CRUST = { K.hex("8A6A1E"), K.hex("A07A20"), K.hex("6E5418") }
--- The fumarole mounds: pale gypsum crust, whiter toward the base, so the stack stands
--- off the ground and the sulfur on its rim reads as a colour of its own.
local GYPSUM = { K.hex("E8E2C0"), K.hex("D9CFA0"), K.hex("CFC28A") }
local STAIN = K.hex("C27A1E")
local VENT = K.hex("1A1508")
local THROAT = K.hex("FFB02E")
local RIM = K.hex("E8E0A0")
local GRIT = { K.hex("8A7420"), K.hex("E5CF4A"), K.hex("5E5018") }

type Palette = { acid: Color3, acidDeep: Color3, hexLight: Color3, hexDark: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	local ground = K.hex(def.color)
	return {
		acid = K.hex(def.ooze.bright),
		acidDeep = K.hex(def.ooze.deep),
		hexLight = K.shade(ground, 0.28),
		hexDark = K.shade(ground, -0.12),
	}
end

local function needles(parent: Instance, at: Vector3, count: number, maxH: number, rng: Random)
	for _ = 1, count do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, maxH * 0.3)
		local h = rng:NextNumber(0.35, 1) * maxH
		K.crystal(parent, "Needle", at + Vector3.new(math.cos(t) * d, 0, math.sin(t) * d), h, h * rng:NextNumber(0.14, 0.2), math.deg(t) + 90, rng:NextNumber(5, 35), K.pick(rng, SULFUR), { studs = true })
	end
end

-- ── Fumaroles ──────────────────────────────────────────────────────────────────

local function fumarole(parent: Instance, at: Vector3, rng: Random, steam: boolean, light: boolean)
	local model = Instance.new("Model")
	model.Name = "Fumarole"
	local base = rng:NextNumber(9, 13)
	local tiers = rng:NextInteger(3, 4)
	local y = 0
	local d = base
	-- Leans a touch, so the stack reads as built up by what came out of it.
	local ox, oz = 0, 0
	local drift = rng:NextNumber(0, math.pi * 2)
	for i = 1, tiers do
		local h = rng:NextNumber(1, 1.4)
		local cf = CFrame.new(at.X + ox, at.Y + y + h / 2, at.Z + oz)
		K.column(model, "Crust", cf, h, d, if i == tiers then SULFUR[1] else GYPSUM[math.min(i, #GYPSUM)], { studs = true })
		-- Lumps of crust round each tier's edge: bare stacked discs shot live as a
		-- wedding cake, and a broken rim is what reads as built up by what came out.
		if i < tiers then
			for _ = 1, rng:NextInteger(3, 5) do
				local t = rng:NextNumber(0, math.pi * 2)
				local r = d * rng:NextNumber(0.5, 0.56)
				K.rock(model, at.X + ox + math.cos(t) * r, at.Z + oz + math.sin(t) * r, at.Y + y, rng:NextNumber(1.3, 2.1), GYPSUM, rng, "CrustLump")
			end
		end
		y += h
		d *= rng:NextNumber(0.62, 0.72)
		ox += math.cos(drift) * 0.25
		oz += math.sin(drift) * 0.25
	end
	local top = Vector3.new(at.X + ox, at.Y + y, at.Z + oz)
	-- The throat: a dark ring with the heat showing at the bottom of it.
	local dTop = d / 0.67
	K.column(model, "Vent", CFrame.new(top + Vector3.new(0, 0.03, 0)), 0.08, dTop * 0.72, VENT)
	local throat = K.column(model, "Throat", CFrame.new(top + Vector3.new(0, 0.06, 0)), 0.08, dTop * 0.34, THROAT, { neon = true })
	if light then
		K.glow(throat, THROAT, 10, 1.1)
	end
	-- Needles crowding the rim, and orange-brown staining run down one side.
	needles(model, top + Vector3.new(dTop * 0.42, -0.1, 0), rng:NextInteger(3, 5), 1.8, rng)
	needles(model, top + Vector3.new(-dTop * 0.3, -0.1, dTop * 0.3), rng:NextInteger(2, 4), 1.4, rng)
	for _ = 1, rng:NextInteger(1, 2) do
		local yaw = rng:NextNumber(0, 360)
		local cf = CFrame.new(at.X, at.Y + y * 0.5, at.Z) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(0, 0, -base * 0.36) * CFrame.Angles(math.rad(-38), 0, 0)
		K.block(model, "Stain", cf, Vector3.new(rng:NextNumber(0.8, 1.6), y * 1.1, 0.12), STAIN)
	end
	-- A skirt of crust smeared round its foot.
	K.blob(model, "Skirt", at.X, at.Z, at.Y + 0.01, base * 1.6, 0.04, GYPSUM[3], rng)
	if steam then
		local a = K.anchor(model, "SteamVent", top + Vector3.new(0, 0.2, 0), Vector3.new(dTop * 0.3, 0.2, dTop * 0.3))
		K.smoke(a, "Steam", {
			from = K.hex("F5F1DC"),
			to = K.hex("E8E2B0"),
			size = { 0.8, 2.6, 6 },
			opacity = 0.45,
			lifetime = { 4, 6.5 },
			rate = 4,
			speed = { 3, 4.5 },
			spread = 8,
			accel = K.WIND + Vector3.new(0, 0.3, 0),
		})
	end
	model.Parent = parent
end

-- ── Acid pools ─────────────────────────────────────────────────────────────────

local function acidPool(parent: Instance, at: Vector3, rng: Random, palette: Palette, light: boolean, fume: boolean)
	local model = Instance.new("Model")
	model.Name = "AcidPool"
	local size = rng:NextNumber(6, 12)
	K.blob(model, "CrustRim", at.X, at.Z, at.Y + 0.01, size * 1.35, 0.05, RIM, rng)
	K.blob(model, "AcidShallows", at.X, at.Z, at.Y + 0.025, size * 1.12, 0.05, palette.acidDeep, rng)
	local head = K.blob(model, "Acid", at.X, at.Z, at.Y + 0.045, size, 0.05, palette.acid, rng, { neon = true, transparency = 0.15 })
	for _ = 1, rng:NextInteger(3, 6) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, size * 0.3)
		local s = rng:NextNumber(0.3, 0.8)
		K.block(model, "Bubble", CFrame.new(at.X + math.cos(t) * d, at.Y + 0.05, at.Z + math.sin(t) * d), Vector3.new(s, s, s), K.shade(palette.acid, 0.4), { shape = Enum.PartType.Ball, transparency = 0.25, reflectance = 0.2 })
	end
	if light then
		K.glow(head, palette.acid, 12, 1)
	end
	if fume then
		local a = K.anchor(model, "FumeVent", at + Vector3.new(0, 0.2, 0), Vector3.new(size * 0.5, 0.2, size * 0.5))
		K.smoke(a, "AcidFume", {
			from = K.shade(palette.acid, 0.3),
			to = K.hex("E6EDC8"),
			size = { 1, 2.5, 4.5 },
			opacity = 0.3,
			lifetime = { 3.5, 5.5 },
			rate = 2.5,
			speed = { 0.8, 1.6 },
			spread = 30,
			accel = K.WIND * 0.8 + Vector3.new(0, 0.2, 0),
		})
	end
	model.Parent = parent
end

-- ── Crystals and the hex crust ─────────────────────────────────────────────────

local function crystalCluster(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "SulfurCrystals"
	K.blob(model, "CrystalCrust", at.X, at.Z, at.Y + 0.012, rng:NextNumber(2.5, 4), 0.04, CRUST[3], rng)
	needles(model, at, rng:NextInteger(4, 7), rng:NextNumber(1.2, 2.1), rng)
	model.Parent = parent
end

--- A regular hexagon laid flat: three R x sqrt(3)R rectangles at 0/60/120 degrees, whose
--- corners are exactly the hexagon's six vertices.
local function hexPlate(parent: Instance, cf: CFrame, r: number, color: Color3)
	for k = 0, 2 do
		K.block(parent, "HexPlate", cf * CFrame.Angles(0, math.rad(k * 60), 0), Vector3.new(r, 0.08, r * math.sqrt(3)), color, { shadow = false })
	end
end

--- A patch of the pan cracked into honeycomb: plates on an axial hex grid with a crack
--- between each, the patch thinning out toward its edge.
local function hexPatch(parent: Instance, f: K.Field, at: Vector3, rng: Random, palette: Palette, lift: number)
	local model = Instance.new("Model")
	model.Name = "HexCrust"
	local r = rng:NextNumber(1.6, 2.4)
	local gap = 0.35
	local step = math.sqrt(3) * r + gap
	local radius = 2
	-- Held a whole patch-width inside the field: a site is only a centre.
	local cx, cz = K.clamp(f, at.X, at.Z, step * (radius + 0.5))
	local frame = CFrame.new(cx, at.Y + 0.045 + lift, cz) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 60)), 0)
	for q = -radius, radius do
		for s = math.max(-radius, -q - radius), math.min(radius, -q + radius) do
			local ring = math.max(math.abs(q), math.abs(s), math.abs(q + s))
			-- The outer ring only in part, so the patch has a ragged edge.
			if ring == radius and rng:NextNumber() < 0.5 then
				continue
			end
			local x = step * (q + s / 2)
			local z = step * (s * math.sqrt(3) / 2)
			local color = if rng:NextNumber() < 0.6 then palette.hexLight else palette.hexDark
			-- Flats face along X (a rectangle's long side runs along Z), so rotate 30
			-- degrees to lay the pointy-top grid above flush.
			hexPlate(model, frame * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(30), 0), r, color)
		end
	end
	model.Parent = parent
end

function SulfurFlats.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "SulfurFlats"

	local taken: { { number } } = {}
	for i, at in K.sites(f, FUMAROLES, 28, rng, 6) do
		fumarole(folder, at, rng, i <= FUMAROLE_STEAM + 1 and i ~= 3, i % 3 == 1 and i <= FUMAROLE_LIGHTS * 3)
		table.insert(taken, { at.X, at.Z, 13 })
	end
	for i, at in K.sites(f, ACID_POOLS, 24, rng, -10, taken) do
		acidPool(folder, at, rng, palette, i <= POOL_LIGHTS, i % 3 == 2 and i <= POOL_FUMES * 3)
		table.insert(taken, { at.X, at.Z, 12 })
	end
	for _, at in K.sites(f, CRYSTAL_CLUSTERS, 11, rng, 0, taken) do
		crystalCluster(folder, at, rng)
		table.insert(taken, { at.X, at.Z, 5 })
	end
	for i, at in K.sites(f, HEX_PATCHES, 18, rng, -16, taken) do
		-- Alternate lifts, in case two patches meet.
		hexPatch(folder, f, at, rng, palette, (i % 2) * 0.004)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		local roll = rng:NextNumber()
		if roll < GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		elseif roll < GRIT_CHANCE + SMEAR_CHANCE then
			local lift = ((2 * col + row) % 4) * 0.003
			K.blob(ground, "CrustSmear", x, z, groundY + 0.008 + lift, rng:NextNumber(3, 8), 0.04, K.pick(rng, CRUST), rng, nil, 0.0025)
		elseif roll < GRIT_CHANCE + SMEAR_CHANCE + NEEDLE_CHANCE and not K.onLane(z) then
			needles(ground, Vector3.new(x, groundY, z), rng:NextInteger(1, 3), 1, rng)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return SulfurFlats
