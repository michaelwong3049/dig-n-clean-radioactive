--!strict
--[[
	CrateService.lua — opening the supply crates you dig up (Config/Crates).

	THE VERB. Hold a crate from your bag and a native "Open" prompt appears on it
	(client CrateController). Triggering it sends CrateOpen with the crate's uid; the
	server checks that uid is the crate IN YOUR HANDS (`data.heldUid`), spends it and
	rolls the prize. The client never names a prize, a crate type or anything else.

	  NUKE CRATE   -> Crates.rollNuke. The nuke goes into `data.carry` CLEAN (no
	                  patches), IDENTIFIED (index credit, IdentifyService) and FROZEN (no
	                  decay clock -- it was sealed in a crate, not buried in slag). It
	                  takes the crate's slot, so a full bag can always open a crate. The
	                  reel popup is CrateOpened.
	  LIQUID CRATE -> LiquidService.openCrate, which grants the fluid exactly like a
	                  bottle roll and plays the bottle's own brew popup (FluidSpin).

	THE REVEAL IS NOT SPOILED BY THE WORLD. While the reel plays, the new nuke is kept
	out of your hands and the ItemIdentified announcement is held back; both land when
	the reel does, the announcement with `staged = true` so the dig banner stands down
	for the popup (the same flag the wash bay's own reveal uses).
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Crates = require(Shared.Config.Crates)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Bag = require(Shared.Bag)
local StatResolver = require(Shared.StatResolver)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IdentifyService = require(script.Parent.IdentifyService)
local EconomyService = require(script.Parent.EconomyService)
local DigService = require(script.Parent.DigService)
local WashService = require(script.Parent.WashService)
local LiquidService = require(script.Parent.LiquidService)

local CrateService = {}

--- How long the nuke reel spins, and where in the strip it lands. The client centres
--- the strip on `land` exactly the way the brew popup does.
local REEL_SECONDS = 4.5
local REEL_LAND = 30
local REEL_TAIL = 4

--- The modifiers a crated nuke can come with. A prize never comes out Cracked or
--- Slagged; the rest keep their normal relative weights. Explicit order so the roll is
--- stable (see Liquids.ORDER for why that matters).
local PRIZE_MODIFIERS = { "None", "Pristine", "Irradiated", "Fused", "PrewarSealed" }

local openRemote: any = nil
local openedRemote: any = nil

--- Set while a player's reel is playing, so a second open cannot stack under it.
local opening: { [Player]: boolean } = {}

local function rollModifier(): string
	local total = 0
	for _, name in PRIZE_MODIFIERS do
		total += Rarity.MODIFIERS[name].weight
	end
	local pick = math.random() * total
	for _, name in PRIZE_MODIFIERS do
		pick -= Rarity.MODIFIERS[name].weight
		if pick <= 0 then
			return name
		end
	end
	return "None"
end

local function openNuke(player: Player, data: any, crateId: string)
	local itemId = Crates.rollNuke(crateId, math.random())
	if itemId == nil then
		warn(`[crate] {crateId} has an empty prize table`)
		return
	end
	local def = Items.get(itemId)

	local carried = {
		uid = HttpService:GenerateGUID(false),
		itemId = itemId,
		rarity = def.rarity,
		modifier = rollModifier(),
		elapsed = 0,
		frozen = true,
		patches = {},
	}
	table.insert(data.carry, carried)
	local first, previous = IdentifyService.identify(player, carried)

	local reel = table.create(REEL_LAND + REEL_TAIL)
	for i = 1, REEL_LAND + REEL_TAIL do
		local id = if i == REEL_LAND then itemId else Crates.rollNuke(crateId, math.random()) or itemId
		local entry = Items.get(id)
		reel[i] = { itemId = id, name = entry.name, rarity = entry.rarity }
	end

	local value = EconomyService.valueOf(carried, StatResolver.get(data))
	opening[player] = true
	openedRemote:FireClient(player, {
		crate = crateId,
		reel = reel,
		land = REEL_LAND,
		seconds = REEL_SECONDS,
		result = itemId,
		name = def.name,
		flavor = def.flavor,
		rarity = def.rarity,
		modifier = carried.modifier,
		value = value,
		firstFind = first,
	})
	print(`[crate] {player.Name} opened a {Crates.get(crateId).name}: {carried.modifier} {def.rarity} {def.name}`)

	task.delay(REEL_SECONDS, function()
		opening[player] = nil
		if player.Parent == nil then
			return
		end
		IdentifyService.announce(player, carried, first, { staged = true, previousBest = previous })
		-- Into your hands now the reel has landed, unless you have picked something
		-- else up or locked onto a signal in the meantime.
		local live = DataService.data(player)
		if live and live.heldUid == "" and not DigService.isLocked(player) and EconomyService.find(live, carried.uid) then
			live.heldUid = carried.uid
		end
	end)
end

--- Open the crate `uid`, which must be the one in the player's hands.
function CrateService.open(player: Player, uid: string): (boolean, string?)
	local data = DataService.data(player)
	if data == nil then
		return false, "not loaded"
	end
	if opening[player] then
		return false, "already opening one"
	end
	if data.heldUid ~= uid then
		return false, "hold the crate to open it"
	end
	if DigService.isLocked(player) or WashService.isWashing(player) then
		return false, "your hands are busy"
	end

	local entry, index = Bag.findCrate(data, uid)
	if entry == nil or index == nil or not Crates.has(entry.crateId) then
		return false, "you aren't carrying that crate"
	end

	table.remove(data.crates, index)
	data.heldUid = ""
	data.stats.cratesOpened = (data.stats.cratesOpened or 0) + 1

	local def = Crates.get(entry.crateId)
	if def.kind == "nuke" then
		openNuke(player, data, entry.crateId)
	else
		LiquidService.openCrate(player, data, entry.crateId)
	end
	return true, nil
end

--- Give a player a crate straight into their bag (DebugService's /crate).
function CrateService.grant(player: Player, crateId: string): boolean
	local data = DataService.data(player)
	if data == nil or not Crates.has(crateId) then
		return false
	end
	data.crates = data.crates or {}
	table.insert(data.crates, { uid = HttpService:GenerateGUID(false), crateId = crateId })
	return true
end

function CrateService.init()
	openRemote = Net.get("CrateOpen")
	openedRemote = Net.get("CrateOpened")
end

function CrateService.start()
	openRemote.OnServerEvent:Connect(function(player: Player, uid: any)
		if type(uid) ~= "string" then
			return
		end
		local ok, refusal = CrateService.open(player, uid)
		if not ok then
			openedRemote:FireClient(player, { notice = refusal })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		opening[player] = nil
	end)
end

return CrateService
