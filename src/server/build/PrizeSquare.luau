--!strict
--[[
	PrizeSquare.luau — the small raised square the group chest and the two crate pads
	stand on (Config/GroupReward, Config/CrateShop), and the short path that leads to it
	from the shop square's west kerb. World.rebuild() bakes it; GroupRewardService builds
	it at runtime if a saved place predates it, so the chest never floats.

	THE SAME FLOOR AS THE SHOP SQUARE, on request (2026-10-06: "a small path from the
	square in the middle ... on a smaller square that they're on"): Hub.SHOP_PAVER
	pavers ringed by a 2-stud Hub.SHOP_KERB band, laid by Hub.tileRect on the plaza's own
	grid at the shop square's height (PLAZA.topY + SHOP_FLOOR_LIFT), so its checker runs in
	register with the square it leads from. The path is the same pavers between two kerb
	bands, and opens into the square through a gap in its east kerb.

	Every edge sits on a 4-stud grid line (x = PLAZA.minX - 4k, z = PLAZA.minZ + 4k), and
	the square is centred on the chest, so moving the chest moves the square with it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupReward = require(ReplicatedStorage.Shared.Config.GroupReward)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local PrizeSquare = {}

PrizeSquare.MODEL_NAME = "PrizeSquare"

PrizeSquare.HALF = 30 -- the square's half-width, kerb included (60 x 60)
PrizeSquare.PATH_HALF = 6 -- the path's half-width, kerbs included (12 wide)
local KERB = 2 -- the kerb band, half a tile like the shop square's

--- The floor's top face: level with the shop square's pavers. The chest and the
--- crate pads stand here (Config FLOOR_Y).
PrizeSquare.TOP_Y = Hub.PLAZA.topY + Hub.SHOP_FLOOR_LIFT

local function lay(parent: Instance, rect: Hub.Rect, pair: { dark: string, light: string })
	Hub.tileRect(parent, rect, { topY = PrizeSquare.TOP_Y, dark = pair.dark, light = pair.light })
end

--- The square and its path, fully formed and UNPARENTED (Kit.swap's contract).
function PrizeSquare.build(): Model
	local model = Instance.new("Model")
	model.Name = PrizeSquare.MODEL_NAME

	local c = GroupReward.CHEST_POSITION
	local H, P = PrizeSquare.HALF, PrizeSquare.PATH_HALF
	local x0, x1 = c.X - H, c.X + H -- the square, kerb included
	local z0, z1 = c.Z - H, c.Z + H
	local pathEnd = Hub.PLAZA.minX -- the shop square's west kerb

	-- The square's kerb: west, north and south whole; east split round the path.
	lay(model, { minX = x0, maxX = x0 + KERB, minZ = z0, maxZ = z1 }, Hub.SHOP_KERB)
	lay(model, { minX = x0 + KERB, maxX = x1, minZ = z1 - KERB, maxZ = z1 }, Hub.SHOP_KERB)
	lay(model, { minX = x0 + KERB, maxX = x1, minZ = z0, maxZ = z0 + KERB }, Hub.SHOP_KERB)
	lay(model, { minX = x1 - KERB, maxX = x1, minZ = z0 + KERB, maxZ = c.Z - P + KERB }, Hub.SHOP_KERB)
	lay(model, { minX = x1 - KERB, maxX = x1, minZ = c.Z + P - KERB, maxZ = z1 - KERB }, Hub.SHOP_KERB)
	-- The square's pavers, and the gap in the east kerb the path comes through.
	lay(model, { minX = x0 + KERB, maxX = x1 - KERB, minZ = z0 + KERB, maxZ = z1 - KERB }, Hub.SHOP_PAVER)
	lay(model, { minX = x1 - KERB, maxX = x1, minZ = c.Z - P + KERB, maxZ = c.Z + P - KERB }, Hub.SHOP_PAVER)

	-- The path: pavers between two kerb bands, from the square to the shop square.
	if pathEnd > x1 then
		lay(model, { minX = x1, maxX = pathEnd, minZ = c.Z - P, maxZ = c.Z - P + KERB }, Hub.SHOP_KERB)
		lay(model, { minX = x1, maxX = pathEnd, minZ = c.Z + P - KERB, maxZ = c.Z + P }, Hub.SHOP_KERB)
		lay(model, { minX = x1, maxX = pathEnd, minZ = c.Z - P + KERB, maxZ = c.Z + P - KERB }, Hub.SHOP_PAVER)
	end

	return model
end

--- Bake the square into Workspace (World.rebuild).
function PrizeSquare.rebuild(parent: Instance?): Model
	local model = Kit.swap(PrizeSquare.MODEL_NAME, PrizeSquare.build, parent) :: Model
	print(`[build] Prize square rebuilt — {#model:GetDescendants()} parts`)
	return model
end

return PrizeSquare
