--[[
	SfxController.luau — the sound effects no single screen owns.

	Most cues are played by the controller whose moment they belong to (the till in
	CashController, the hose in WashController, the dig in DetectorController), off
	client/Sfx.luau's catalogue. This file is for the rest:

	  * THE SERVER'S CUES (Net.Sfx): a named one-shot for this player -- a purchase
	    refused for want of cash, a Robux product granted.
	  * THE SWITCH (Net.SfxMuted): Settings' SOUND EFFECTS, saved on the profile. The
	    mute itself happens here, so it holds even if the Settings panel never builds.
	  * OTHER PLAYERS, HEARD. Three attributes the server stamps on each character --
	    DigTick (a counter, bumped per accepted yank), Hauling and HoseSpraying -- are
	    all a client needs to put a dig crunch, a magnet hum or a hose hiss on someone
	    else, 3D on their root. Your own versions play from your own input instead, a
	    round trip sooner, so the local character is skipped for those three.
	  * AURAS, EVERYONE'S. A quiet hum on every character wearing one (AuraTier), louder
	    and lower the higher the tier, and a whoosh when YOUR aura changes to a new tier.
	  * GUI CLICKS. Every button in PlayerGui ticks when Activated -- hooked here, once,
	    as buttons appear, so no panel has to remember to. A button that is mashed or
	    held (the haul button, the pick-up card) opts out with a NoClickSound attribute.
	  * YOUR BODY. The heartbeat once rad sickness drains you (meter 80%+), a low sting
	    stepping into each sickness band, a thud on a sudden big health loss (a blast), a
	    whoosh on respawn. Warps (HOME / SHOPS / camps) are silent, on request.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local AuraLook = require(Shared.AuraLook)
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)

local Sfx = require(script.Parent.Parent.Sfx)

local SfxController = {}

--- A health drop at least this big between two ExposureState payloads is a hit (a
--- blast, a crater), not the steady sickness drain, which is a few HP a second.
local HURT_DROP = 8

--- Seconds after a spawn in which an AuraTier reading is the spawn itself, not a change.
local SPAWN_SETTLE = 1.5

--- Heartbeat interval at the drain line (80%) and at a full meter.
local BEAT_SLOW, BEAT_FAST = 1.0, 0.45

type Rig = {
	character: Model,
	root: BasePart?,
	aura: Sfx.Loop?,
	haul: Sfx.Loop?,
	hose: Sfx.Loop?,
	connections: { RBXScriptConnection },
}

local rigs: { [Model]: Rig } = {}
local localPlayer = Players.LocalPlayer

-- ── Other characters ───────────────────────────────────────────────

local function auraLevel(tier: number): (number, number)
	-- Volume multiplier and pitch: louder and deeper as the tier climbs, with the
	-- Twilight rungs (7+) a clear step richer again.
	local top = math.max(Gear.maxTier("Aura"), 2)
	local t = math.clamp((tier - 2) / (top - 2), 0, 1)
	local volume = 0.6 + 0.8 * t + (if tier >= 7 then 0.4 else 0)
	local pitch = 1.1 - 0.35 * t
	return volume, pitch
end

local function unrig(character: Model)
	local rig = rigs[character]
	if rig == nil then
		return
	end
	rigs[character] = nil
	for _, connection in rig.connections do
		connection:Disconnect()
	end
	for _, loop in { rig.aura, rig.haul, rig.hose } do
		if loop then
			loop:destroy()
		end
	end
end

local function rig(player: Player, character: Model)
	unrig(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") or character.Parent == nil then
		return
	end
	local mine = player == localPlayer
	local entry: Rig = {
		character = character,
		root = root,
		aura = Sfx.loop("auraHum", root),
		haul = if mine then nil else Sfx.loop("haulHum", root),
		hose = if mine then nil else Sfx.loop("hose", root),
		connections = {},
	}
	rigs[character] = entry

	local spawnedAt = os.clock()
	local lastTier: number? = nil

	local function onAura()
		local tier = character:GetAttribute(AuraLook.ATTRIBUTE)
		if entry.aura then
			if type(tier) == "number" then
				local volume, pitch = auraLevel(tier)
				entry.aura.sound.PlaybackSpeed = pitch
				entry.aura:set(true, volume)
			else
				entry.aura:set(false)
			end
		end
		-- The whoosh is yours alone, and only for a real change of tier: never the first
		-- reading after a spawn, and not HIDE MY AURA flipping it off and back on (nil
		-- readings are skipped, so the tier you come back to is no change).
		if mine and type(tier) == "number" then
			if lastTier ~= nil and tier ~= lastTier and os.clock() - spawnedAt > SPAWN_SETTLE then
				Sfx.play("auraEquip")
			end
			lastTier = tier
		end
	end
	table.insert(entry.connections, character:GetAttributeChangedSignal(AuraLook.ATTRIBUTE):Connect(onAura))
	onAura()
	-- Spawned with nothing drawn: that is the free starter rung (never drawn), so the
	-- first aura you buy is a change from it.
	if mine then
		task.delay(SPAWN_SETTLE, function()
			if rigs[character] == entry and lastTier == nil then
				lastTier = 1
			end
		end)
	end

	if not mine then
		local function onHaul()
			if entry.haul then
				entry.haul:set(character:GetAttribute("Hauling") == true)
			end
		end
		local function onHose()
			if entry.hose then
				entry.hose:set(character:GetAttribute("HoseSpraying") == true)
			end
		end
		table.insert(entry.connections, character:GetAttributeChangedSignal("Hauling"):Connect(onHaul))
		table.insert(entry.connections, character:GetAttributeChangedSignal("HoseSpraying"):Connect(onHose))
		table.insert(entry.connections, character:GetAttributeChangedSignal("DigTick"):Connect(function()
			Sfx.playAt(if math.random() < 0.5 then "dig" else "dig2", root)
		end))
		onHaul()
		onHose()
	end

	table.insert(entry.connections, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unrig(character)
		end
	end))
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(rig, player, character)
	end)
	player.CharacterRemoving:Connect(unrig)
	if player.Character then
		task.spawn(rig, player, player.Character)
	end
end

-- ── Your own body ───────────────────────────────────────────────────

local function watchVitals()
	local Hud = require(script.Parent.HudController)

	local lastHealth: number? = nil
	local band = 0
	local beatClock = 0
	local firstSpawn = true

	localPlayer.CharacterAdded:Connect(function()
		lastHealth = nil
		if firstSpawn then
			firstSpawn = false
		else
			Sfx.play("respawn")
		end
	end)
	if localPlayer.Character then
		firstSpawn = false
	end

	Net.get("ExposureState").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local health = payload.health
		if type(health) == "number" then
			if lastHealth and lastHealth - health >= HURT_DROP and not payload.downed then
				Sfx.play("hurt")
			end
			lastHealth = health
		end

		-- The sickness bands: 1 = no regen (50%), 2 = draining (80%). A sting on the
		-- way INTO each, deeper for the worse one; nothing on the way back down.
		local frac = payload.exposureFrac or 0
		local now = if frac >= Tuning.SICKNESS_DRAIN_AT then 2 elseif frac >= Tuning.SICKNESS_NO_REGEN then 1 else 0
		if now > band and not payload.downed then
			Sfx.play("sickness", { speed = if now == 2 then 0.8 else 1 })
		end
		band = now
	end)

	RunService.Heartbeat:Connect(function(dt)
		-- The heartbeat, once sickness is eating health: faster as the meter fills.
		local vitals = Hud.vitals()
		if vitals.sickness > 0 and not vitals.downed then
			local t = math.clamp((vitals.exposureFrac - Tuning.SICKNESS_DRAIN_AT) / (1 - Tuning.SICKNESS_DRAIN_AT), 0, 1)
			beatClock -= dt
			if beatClock <= 0 then
				beatClock = BEAT_SLOW + (BEAT_FAST - BEAT_SLOW) * t
				Sfx.play("heartbeat", { volume = 0.7 + 0.5 * t })
			end
		else
			beatClock = 0
		end

	end)
end

-- ── GUI clicks ──────────────────────────────────────────────────────

local function hookButton(instance: Instance)
	if not instance:IsA("GuiButton") then
		return
	end
	local button = instance :: GuiButton
	button.Activated:Connect(function()
		if not button:GetAttribute("NoClickSound") then
			Sfx.play("click")
		end
	end)
end

local function watchButtons()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	playerGui.DescendantAdded:Connect(hookButton)
	for _, instance in playerGui:GetDescendants() do
		hookButton(instance)
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────

function SfxController.start()
	Net.get("Sfx").OnClientEvent:Connect(function(name)
		if type(name) == "string" and Sfx.DEFS[name] then
			Sfx.play(name)
		end
	end)
	Net.get("SfxMuted").OnClientEvent:Connect(function(muted)
		Sfx.setMuted(muted == true)
	end)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	watchVitals()
	task.spawn(watchButtons)
end

return SfxController
