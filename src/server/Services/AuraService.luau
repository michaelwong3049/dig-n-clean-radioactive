--!strict
--[[
	AuraService.lua — tells everyone which Aura each character is wearing.

	The aura itself is drawn on every CLIENT (client/Controllers/AuraController): it
	is spinning rings and orbiting electrons, which move every frame, and a server-built
	rig would replicate a CFrame per part per frame to every player for a purely
	visual effect. What the server owns is the one fact the drawing needs: the tier.
	It goes on the character as an attribute (AuraLook.ATTRIBUTE), so it replicates to
	everyone with the character and a stranger in a Containment Nimbus is visible to
	exactly the people it advertises to.

	ONE PATH FOR EVERY WAY AN AURA CHANGES. Buying, equipping an older rung,
	`/gear aura N` and respawning all end the same way: the equipped tier
	(data.gear.aura, what ShopService writes) no longer matches the attribute, and the
	next poll fixes it. Polled rather than evented, like ToolService, because the
	profile is written from several places and none of them owe this file a callback.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AuraLook = require(Shared.AuraLook)
local Gear = require(Shared.Config.Gear)
local Ticker = require(Shared.Util.Ticker)
local Tuning = require(Shared.Config.Tuning)

local DataService = require(script.Parent.DataService)

local AuraService = {}

local AURA_KEY = Gear.profileKey("Aura")

local function stepPlayer(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local tier = math.clamp(data.gear[AURA_KEY] or 1, 1, Gear.maxTier("Aura"))
	if character:GetAttribute(AuraLook.ATTRIBUTE) ~= tier then
		character:SetAttribute(AuraLook.ATTRIBUTE, tier)
	end
end

function AuraService.init() end

function AuraService.start()
	-- Every third tick, like ToolService: an aura lighting up a quarter-second after
	-- the purchase is not something anyone can see.
	local counter = 0
	Ticker.every(Tuning.TICK_RATE, function()
		counter += 1
		if counter % 3 ~= 0 then
			return
		end
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player)
			if not ok then
				warn(`[aura] failed for {player.Name}: {err}`)
			end
		end
	end)
end

return AuraService
