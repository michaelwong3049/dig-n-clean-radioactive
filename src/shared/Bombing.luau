--!strict
--[[
	Bombing.luau — PURE MATH for a dropped nuke's bomb stats (numbers in Config/Bombing).

	Shared so the hotbar's hover card (InventoryController) and the server
	(BombService) come out of one function: the damage a player reads before dropping is
	the damage that lands. Everything is derived from the item record, deterministic
	per uid -- nothing is stored, the same seeded-never-stored trick as Payload.forUid.
]]

local Config = script.Parent.Config
local Cfg = require(Config.Bombing)
local Rarity = require(Config.Rarity)
local Payload = require(Config.Payload)

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

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- The star rating a bag nuke counts as: the same Rarity.stars every other surface
--- uses (stand card, Nukes panel, trader). Also what the overhead badge averages.
function Bombing.starsOf(item: any): number
	return Rarity.stars(item.rarity, item.modifier, if item.uid then Payload.forUid(item.uid) else nil)
end

--- Everything a nuke does as a bomb. `item` needs rarity, modifier and uid (a bag
--- record or the hotbar's described copy of one).
function Bombing.statsFor(item: any): Stats
	local uid = tostring(item.uid or "")
	local stars = math.max(1, Bombing.starsOf(item))
	local payload = Payload.forUid(uid)
	local size = math.clamp(payload ^ Cfg.SIZE_EXP, Cfg.SIZE_MIN, Cfg.SIZE_MAX)
	local span = math.max(1, #Cfg.DAMAGE - 1)
	local through = (stars - 1) / span

	local fuse = lerp(Cfg.FUSE_MIN, Cfg.FUSE_MAX, roll("bombfuse:", uid)) + (stars - 1) * Cfg.FUSE_PER_STAR
	local cooldown = lerp(Cfg.COOLDOWN_MIN, Cfg.COOLDOWN_MAX, through)
		+ (roll("bombcool:", uid) * 2 - 1) * Cfg.COOLDOWN_JITTER

	return {
		stars = stars,
		damage = math.floor(Cfg.DAMAGE[stars] * size * vary("bombdmg:", uid) + 0.5),
		radius = math.floor(Cfg.RADIUS[stars] * size * vary("bombrad:", uid) * 10 + 0.5) / 10,
		fuse = math.floor(fuse * 10 + 0.5) / 10,
		cooldown = math.floor(math.clamp(cooldown, Cfg.COOLDOWN_MIN, Cfg.COOLDOWN_MAX) * 10 + 0.5) / 10,
	}
end

--- What a typical copy of one nuke does as a bomb (the Index's AVG cells): its rarity's
--- stars at a neutral size roll, no modifier, no per-uid variance.
function Bombing.averageFor(item: any): (number, number)
	local stars = math.max(1, Rarity.stars(item.rarity, nil, 1))
	return Cfg.DAMAGE[stars], Cfg.RADIUS[stars]
end

--- Can this item be dropped as a bomb? Clean nukes only: a crusted lump is still a
--- "???" find, and a crate is not a nuke. `clean` is passed in because the two sides
--- know it differently (the server from Contamination, the hotbar from `describe`).
function Bombing.canDrop(item: any, clean: boolean): boolean
	return item ~= nil and item.crateId == nil and clean
end

--- The average star rating over a bag, 0 for an empty one (the overhead badge).
function Bombing.averageStars(items: { any }): (number, number)
	local total, count = 0, 0
	for _, item in items do
		if item.crateId == nil then
			total += Bombing.starsOf(item)
			count += 1
		end
	end
	return if count > 0 then total / count else 0, count
end

return Bombing
