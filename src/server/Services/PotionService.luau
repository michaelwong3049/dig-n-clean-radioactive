--!strict
--[[
	PotionService.luau — the potion stash and the ten-minute clocks (Config/Potions).

	THE STASH is `data.potions` (id -> count). The Potion Crate fills it
	(CrateService -> PotionService.fromCrate); the Potions panel drains it.

	THE CLOCKS are CashBoostService's, one per potion: seconds banked in
	`data.potionLeft[id]`, held here as an end time against the real clock while the
	player is in the server and written back every tick, so a hitching server never
	boosts a player whose countdown has hit zero. Each end time goes to the client as a
	Player attribute (Potions.attrFor). StatResolver applies the effects.

	ONE REMOTE, Potions. Client -> server: "ask" (send me the stash) or "drink", id.
	Server -> client: { stash = { id -> count }, got = id?, drank = id? } -- `got` is a
	potion just out of a crate (the client's reveal card), `drank` one just drunk.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Potions = require(Shared.Config.Potions)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local PotionService = {}

local remote: any = nil

-- Player -> potion id -> server time it runs out. Only potions with time left.
local endsAt: { [Player]: { [string]: number } } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function publish(player: Player, id: string)
	local ends = endsAt[player]
	player:SetAttribute(Potions.attrFor(id), ends and ends[id] or 0)
	if id == "speed" then
		-- The Walk Speed badge prints the boosted speed: resend it now rather than at the
		-- next push. Lazy, like ExposureService's: SpeedService boots after this.
		require(script.Parent.SpeedService).refresh(player)
	end
end

local function stashOf(data: any): { [string]: number }
	data.potions = data.potions or {}
	return data.potions
end

--- The stash as sent to the client: every potion id, 0 when none.
local function snapshot(data: any): { [string]: number }
	local stash = stashOf(data)
	local out = {}
	for _, id in Potions.ORDER do
		out[id] = math.max(0, math.floor(tonumber(stash[id]) or 0))
	end
	return out
end

local function push(player: Player, data: any, extra: { [string]: any }?)
	if remote == nil or player.Parent == nil then
		return
	end
	local payload: { [string]: any } = { stash = snapshot(data) }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	remote:FireClient(player, payload)
end

--- Bank `seconds` more of potion `id` on this player (negative takes it away). Mutates
--- only `data` and the clock and never yields.
function PotionService.addTime(player: Player, data: any, id: string, seconds: number)
	assert(Potions.has(id), `PotionService.addTime: unknown potion {id}`)
	local t = now()
	local mine = endsAt[player] or {}
	endsAt[player] = mine
	data.potionLeft = data.potionLeft or {}
	local ends = mine[id]
	local left = if ends then math.max(0, ends - t) else (data.potionLeft[id] or 0)
	left = math.clamp(left + seconds, 0, Potions.MAX_BANKED_SECONDS)
	data.potionLeft[id] = left
	mine[id] = if left > 0 then t + left else nil
	publish(player, id)
end

--- Put `count` of potion `id` in the stash. Never yields.
function PotionService.give(player: Player, data: any, id: string, count: number?)
	assert(Potions.has(id), `PotionService.give: unknown potion {id}`)
	local stash = stashOf(data)
	stash[id] = math.max(0, (tonumber(stash[id]) or 0)) + (count or 1)
	push(player, data)
end

--- The Potion Crate's prize: one potion, every one equally likely, into the stash.
--- The client shows the reveal card off `got`.
function PotionService.fromCrate(player: Player, data: any): string
	local id = Potions.roll(math.random())
	local stash = stashOf(data)
	stash[id] = math.max(0, (tonumber(stash[id]) or 0)) + 1
	push(player, data, { got = id })
	print(`[potion] {player.Name} got a {Potions.get(id).name} from a crate`)
	return id
end

--- Drink one potion `id` from the stash: +DURATION on its clock.
function PotionService.drink(player: Player, id: string): (boolean, string?)
	local data = DataService.data(player)
	if data == nil then
		return false, "not loaded"
	end
	if not Potions.has(id) then
		return false, "no such potion"
	end
	local stash = stashOf(data)
	local have = tonumber(stash[id]) or 0
	if have < 1 then
		return false, "you don't have one"
	end
	stash[id] = have - 1
	PotionService.addTime(player, data, id, Potions.DURATION)
	push(player, data, { drank = id })
	return true, nil
end

local function onLoaded(player: Player, data: any)
	local t = now()
	local mine = {}
	data.potionLeft = data.potionLeft or {}
	for _, id in Potions.ORDER do
		local left = tonumber(data.potionLeft[id]) or 0
		if left > 0 then
			mine[id] = t + left
		end
	end
	endsAt[player] = mine
	for _, id in Potions.ORDER do
		publish(player, id)
	end
	push(player, data)
end

local function step()
	local t = now()
	for player, mine in endsAt do
		local data = DataService.data(player)
		if data == nil then
			continue
		end
		data.potionLeft = data.potionLeft or {}
		for id, ends in mine do
			local left = math.max(0, ends - t)
			data.potionLeft[id] = left
			if left <= 0 then
				mine[id] = nil
				publish(player, id)
			end
		end
	end
end

function PotionService.init()
	remote = Net.get("Potions")
end

function PotionService.start()
	DataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(function(player)
		endsAt[player] = nil
	end)
	remote.OnServerEvent:Connect(function(player: Player, action: any, id: any)
		if action == "ask" then
			local data = DataService.data(player)
			if data then
				push(player, data)
			end
		elseif action == "drink" and type(id) == "string" then
			local ok, refusal = PotionService.drink(player, id)
			if not ok then
				local data = DataService.data(player)
				if data then
					push(player, data, { notice = refusal })
				end
			end
		end
	end)
	Ticker.every(Tuning.TICK_RATE, step, "PotionService")
end

return PotionService
