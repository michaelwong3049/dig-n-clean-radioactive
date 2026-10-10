--!strict
--[[
	Bombing.luau — PURE MATH for a dropped nuke's bomb stats (numbers in Config/Bombing).

	Shared so the hotbar's hover card (InventoryController) and the server
	(BombService) come out of one function: the damage a player reads before dropping is
	the damage that lands. Everything is derived from the item record, deterministic
	per uid -- nothing is stored, the same seeded-never-stored trick as Payload.forUid --
	except a REFORGED copy's damage/radius wobble, which is stored as `forge` (forgeOf).
]]

local Config = script.Parent.Config
local Cfg = require(Config.Bombing)
local Rarity = require(Config.Rarity)
local Payload = require(Config.Payload)
local Items = require(Config.Items)
local Merge = require(Config.Merge)
local Detonation = require(script.Parent.Detonation)

local Bombing = {}

export type Stats = {
	stars: number,
	damage: number,
	radius: number,
	fuse: number,
	cooldown: number,
}

-- Same shape as Detonation's and Payload's seedOf, salted per stat so the rolls don't
-- correlate with each other or with the size roll.
local function seedOf(uid: string): number
	local total = 0
	for index = 1, #uid do
		total = (total * 31 + string.byte(uid, index)) % 2147483647
	end
	return total
end

local function roll(salt: string, uid: string): number
	return Random.new(seedOf(salt .. uid)):NextNumber()
end

local function vary(salt: string, uid: string): number
	return 1 + (roll(salt, uid) * 2 - 1) * Cfg.VARIANCE
end

--- The copy's damage and radius wobble: a reforged copy's stored `forge` pair
--- (Config/Reforge, Services/ReforgeService), else the seeded per-uid one.
function Bombing.forgeOf(item: any): (number, number)
	local forge = item.forge
	local uid = tostring(item.uid or "")
	local dmg = if type(forge) == "table" and type(forge.dmg) == "number" then forge.dmg else vary("bombdmg:", uid)
	local rad = if type(forge) == "table" and type(forge.rad) == "number" then forge.rad else vary("bombrad:", uid)
	return dmg, rad
end

--- The stage a nuke comes from, for Detonation.stageMults: its item's home stage.
--- Takes a catalogue def (`stages`) or a bag record (`itemId`); a crusted hotbar copy
--- has no itemId yet and reads as Stage 1 -- it cannot be dropped until it is clean.
local function stageOf(item: any): number
	if item.stages then
		return Items.homeStage(item)
	end
	if item.itemId and Items.has(item.itemId) then
		return Items.homeStage(Items.get(item.itemId))
	end
	return 1
end

--- The star rating a bag nuke counts as: the same Rarity.stars every other surface
--- uses (stand card, Nukes panel, trader), stage nudge included. Also what the
--- overhead badge averages (over the bag's best three).
function Bombing.starsOf(item: any): number
	local payload = if item.uid then Payload.forUid(item.uid) else nil
	return Rarity.stars(item.rarity, item.modifier, payload, item.bonus, Items.stageOf(item.itemId))
end

-- The DAMAGE/RADIUS row a bomb reads: the rating WITHOUT its stage nudge (the stage
-- already scales the blast through Detonation.stageMults) and capped at the table's
-- length, so the 10-star rating didn't rebalance bombs. A half star rounds down.
local function powerOf(item: any): number
	local payload = if item.uid then Payload.forUid(item.uid) else nil
	return math.clamp(math.floor(Rarity.stars(item.rarity, item.modifier, payload, item.bonus)), 1, #Cfg.DAMAGE)
end

--- Everything a nuke does as a bomb. `item` needs rarity, modifier and uid (a bag
--- record or the hotbar's described copy of one). `damageMult` is the dropper's
--- StatResolver bombDamageMult (Bomber mastery x Bomb Damage pass; 1 or nil = none).
function Bombing.statsFor(item: any, damageMult: number?): Stats
	local uid = tostring(item.uid or "")
	local stars = math.max(1, Bombing.starsOf(item))
	local power = powerOf(item)
	local payload = Payload.forUid(uid)
	local size = math.clamp(payload ^ Cfg.SIZE_EXP, Cfg.SIZE_MIN, Cfg.SIZE_MAX)
	local hitMult, radiusMult = Detonation.stageMults(stageOf(item))

	local order = if item.rarity and Rarity.DEFS[item.rarity] then Rarity.DEFS[item.rarity].order else 1
	local callout = Payload.calloutFor(payload)
	local dmgWobble, radWobble = Bombing.forgeOf(item)
	local fuse = Cfg.FUSE_BY_RARITY[math.clamp(order, 1, #Cfg.FUSE_BY_RARITY)]
		+ (roll("bombfuse:", uid) * 2 - 1) * Cfg.FUSE_SPREAD
		+ (if callout then Cfg.FUSE_SIZE_BONUS[callout] or 0 else 0)

	return {
		stars = stars,
		damage = math.floor(Cfg.DAMAGE[power] * hitMult * size * dmgWobble * (damageMult or 1) + 0.5),
		radius = math.floor(Cfg.RADIUS[power] * radiusMult * size * radWobble * 10 + 0.5) / 10,
		fuse = math.floor(fuse * 10 + 0.5) / 10,
		cooldown = Cfg.COOLDOWN,
	}
end

--- What a typical copy of one nuke does as a bomb (the Index's AVG cells): its rarity's
--- stars at a neutral size roll, no modifier, no per-uid variance -- but its home
--- stage's multipliers, like every real copy.
function Bombing.averageFor(item: any): (number, number)
	local stars = math.clamp(math.floor(Rarity.stars(item.rarity, nil, 1)), 1, #Cfg.DAMAGE)
	local hitMult, radiusMult = Detonation.stageMults(stageOf(item))
	return math.floor(Cfg.DAMAGE[stars] * hitMult + 0.5), math.floor(Cfg.RADIUS[stars] * radiusMult * 10 + 0.5) / 10
end

--- Can this item be dropped as a bomb? Clean nukes only: a crusted lump is still a
--- "???" find, and a crate is not a nuke. `clean` is passed in because the two sides
--- know it differently (the server from Contamination, the hotbar from `describe`).
function Bombing.canDrop(item: any, clean: boolean): boolean
	return item ~= nil and item.crateId == nil and clean
end

-- How many of a bag's best nukes the overhead badge averages: a bag of one big find
-- and a pile of filler still reads as the big find.
local BADGE_TOP = 3

--- The average star rating of a bag's best BADGE_TOP nukes, 0 for an empty one (the
--- overhead badge). The count is every nuke in the bag, not just the ones averaged.
--- Merge Reactor stars count on top of the 1..10 rating (on request), so a bag of
--- merged 10-star nukes reads past 10 -- up to 10 + Merge.MAX_LEVEL.
function Bombing.averageStars(items: { any }): (number, number)
	local stars = {}
	for _, item in items do
		if item.crateId == nil then
			table.insert(stars, Bombing.starsOf(item) + Merge.levelOf(item))
		end
	end
	table.sort(stars, function(a, b)
		return a > b
	end)
	local top = math.min(#stars, BADGE_TOP)
	local total = 0
	for i = 1, top do
		total += stars[i]
	end
	return if top > 0 then total / top else 0, #stars
end

return Bombing
