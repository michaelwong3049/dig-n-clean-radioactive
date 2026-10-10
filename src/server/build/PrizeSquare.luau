--!strict
--[[
	PrizeSquare.luau — the small raised square the group chest and the two crate pads
	stand on (Config/GroupReward, Config/CrateShop). World.rebuild() bakes it;
	GroupRewardService builds it at runtime if a saved place predates it, so the chest
	never floats.

	THE SAME FLOOR AS THE SHOP SQUARE, on request (2026-10-06): Hub.SHOP_PAVER pavers
	ringed by a 2-stud Hub.SHOP_KERB band, laid by Hub.tileRect on the plaza's own grid at
	the shop floor's height (PLAZA.topY + SHOP_FLOOR_LIFT), so its checker runs in register
	with the shop strip.

	A RECTANGLE SINCE THE FIVE-BASE ROW (2026-10-09): it stands between the shop strip and
	Stage 1's green border, so it is narrow along X (HALF_X) and long along Z (HALF_Z),
	where the chest and the two pads line up. The path that led to the old shop square is
	gone -- the square sits on the open grey floor, reachable from every side.

	Every edge sits on a 4-stud grid line (x = PLAZA.minX + 4k, z = PLAZA.minZ + 4k), and
	the square is centred on the chest, so moving the chest moves the square with it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupReward = require(ReplicatedStorage.Shared.Config.GroupReward)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local PrizeSquare = {}

PrizeSquare.MODEL_NAME = "PrizeSquare"

PrizeSquare.HALF_X = 18 -- half its depth along X, kerb included (36)
PrizeSquare.HALF_Z = 30 -- half its length along Z, kerb included (60)
local KERB = 2 -- the kerb band, half a tile like the shop strip's

--- The floor's top face: level with the shop square's pavers. The chest and the
--- crate pads stand here (Config FLOOR_Y).
PrizeSquare.TOP_Y = Hub.PLAZA.topY + Hub.SHOP_FLOOR_LIFT

local function lay(parent: Instance, rect: Hub.Rect, pair: { dark: string, light: string })
	Hub.tileRect(parent, rect, { topY = PrizeSquare.TOP_Y, dark = pair.dark, light = pair.light })
end

--- The square, fully formed and UNPARENTED (Kit.swap's contract).
function PrizeSquare.build(): Model
	local model = Instance.new("Model")
	model.Name = PrizeSquare.MODEL_NAME

	local c = GroupReward.CHEST_POSITION
	local x0, x1 = c.X - PrizeSquare.HALF_X, c.X + PrizeSquare.HALF_X -- kerb included
	local z0, z1 = c.Z - PrizeSquare.HALF_Z, c.Z + PrizeSquare.HALF_Z

	-- The kerb: west and east whole, north and south between them.
	lay(model, { minX = x0, maxX = x0 + KERB, minZ = z0, maxZ = z1 }, Hub.SHOP_KERB)
	lay(model, { minX = x1 - KERB, maxX = x1, minZ = z0, maxZ = z1 }, Hub.SHOP_KERB)
	lay(model, { minX = x0 + KERB, maxX = x1 - KERB, minZ = z1 - KERB, maxZ = z1 }, Hub.SHOP_KERB)
	lay(model, { minX = x0 + KERB, maxX = x1 - KERB, minZ = z0, maxZ = z0 + KERB }, Hub.SHOP_KERB)
	-- The pavers.
	lay(model, { minX = x0 + KERB, maxX = x1 - KERB, minZ = z0 + KERB, maxZ = z1 - KERB }, Hub.SHOP_PAVER)
	return model
end

--- Bake the square into Workspace (World.rebuild).
function PrizeSquare.rebuild(parent: Instance?): Model
	local model = Kit.swap(PrizeSquare.MODEL_NAME, PrizeSquare.build, parent) :: Model
	print(`[build] Prize square rebuilt — {#model:GetDescendants()} parts`)
	return model
end

return PrizeSquare
