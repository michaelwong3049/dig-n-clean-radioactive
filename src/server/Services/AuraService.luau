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
	`/gear aura N`, respawning and the Settings toggle all end the same way: the
	equipped tier (data.gear.aura, what ShopService writes) no longer matches the
	attribute, and the next poll fixes it. Polled rather than evented, like ToolService,
	because the profile is written from several places and none of them owe this file
	a callback.

	HIDE MY AURA (Settings, Net.HideAura). While data.hideAura is on, the attribute is
	cleared rather than set, so every client draws nothing for this player — the aura
	is gone for everyone, which is what was asked for. Nothing else reads the attribute:
	the protection comes from data.gear.aura through StatResolver, so hiding is purely
	cosmetic. The saved value is sent to the owner once per session (the Settings panel
	opens showing it) and echoed back after every change, the same shape as PlotColor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AuraLook = require(Shared.AuraLook)
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)
local Ticker = require(Shared.Util.Ticker)
local Tuning = require(Shared.Config.Tuning)

local DataService = require(script.Parent.DataService)

local AuraService = {}

local AURA_KEY = Gear.profileKey("Aura")

--- Seconds between accepted HIDE MY AURA toggles per player, so a spammed click cannot
--- hammer the profile. A toggle inside it is dropped and the echo snaps the switch back.
local TOGGLE_COOLDOWN = 0.3

local hideRemote: RemoteEvent
local lastToggle: { [Player]: number } = {}
--- Players already sent their saved HideAura value this session.
local toldHidden: { [Player]: boolean } = {}

local function stepPlayer(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	if not toldHidden[player] then
		toldHidden[player] = true
		hideRemote:FireClient(player, data.hideAura == true)
	end
	local character = player.Character
	if character == nil then
		return
	end
	local tier: number? = if data.hideAura == true then nil else math.clamp(data.gear[AURA_KEY] or 1, 1, Gear.maxTier("Aura"))
	if character:GetAttribute(AuraLook.ATTRIBUTE) ~= tier then
		character:SetAttribute(AuraLook.ATTRIBUTE, tier)
	end
end

local function onHideAura(player: Player, hidden: any)
	if type(hidden) ~= "boolean" then
		return
	end
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local now = os.clock()
	if now - (lastToggle[player] or 0) >= TOGGLE_COOLDOWN then
		lastToggle[player] = now
		data.hideAura = hidden
		-- Straight away rather than on the next poll, so the aura goes out (or comes
		-- back) as the switch flips.
		pcall(stepPlayer, player)
	end
	-- Always echo what stuck, so a dropped toggle snaps the switch back.
	hideRemote:FireClient(player, data.hideAura == true)
end

function AuraService.init()
	hideRemote = Net.get("HideAura")
end

function AuraService.start()
	hideRemote.OnServerEvent:Connect(onHideAura)
	Players.PlayerRemoving:Connect(function(player)
		lastToggle[player] = nil
		toldHidden[player] = nil
	end)

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
