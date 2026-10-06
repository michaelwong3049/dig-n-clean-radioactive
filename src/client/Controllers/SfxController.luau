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
	    else, 3D at their root (via an anchor that follows it, so a streamed-out
	    character goes silent instead of playing 2D map-wide). Your own versions play from your own input instead, a
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
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local AuraLook = require(Shared.AuraLook)
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)

local Prefs = require(script.Parent.Parent.Prefs)
local Sfx = require(script.Parent.Parent.Sfx)

local SfxController = {}

--- A health drop at least this big between two ExposureState payloads is a hit (a
--- blast, a crater), not the steady sickness drain, which is a few HP a second.
local HURT_DROP = 8


--- Heartbeat interval at the drain line (80%) and at a full meter.
local BEAT_SLOW, BEAT_FAST = 1.0, 0.45

type Rig = {
	player: Player,
	-- The 3D sounds hang off this, not off the character: an Attachment on Terrain that
	-- follows the character's root each frame. StreamingEnabled swaps a far character's
	-- root out (and a fresh one back in); a Sound left on a streamed-out root is outside
	-- Workspace, and Roblox plays that as flat 2D -- everybody's magnet hum at full
	-- volume from anywhere on the map. The anchor never leaves Workspace, and with no
	-- root in Workspace every loop is simply off.
	anchor: Attachment,
	aura: Sfx.Loop?,
	haul: Sfx.Loop?,
	hose: Sfx.Loop?,
	auraTier: any,
	digTick: any,
}

local rigs: { [Player]: Rig } = {}
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

local function unrig(player: Player)
	local entry = rigs[player]
	if entry == nil then
		return
	end
	rigs[player] = nil
	for _, loop in { entry.aura, entry.haul, entry.hose } do
		if loop then
			loop:destroy()
		end
	end
	entry.anchor:Destroy()
end

local function rig(player: Player)
	unrig(player)
	local mine = player == localPlayer
	local anchor = Instance.new("Attachment")
	anchor.Name = `Sfx_{player.UserId}`
	anchor.Parent = Workspace.Terrain
	rigs[player] = {
		player = player,
		anchor = anchor,
		aura = Sfx.loop("auraHum", anchor),
		-- Your own haul, hose and dig play off your own input instead, a round trip sooner.
		haul = if mine then nil else Sfx.loop("haulHum", anchor),
		hose = if mine then nil else Sfx.loop("hose", anchor),
		auraTier = nil,
		digTick = nil,
	}
end

--- The character's live root, or nil while it is streamed out / respawning.
local function liveRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root:IsDescendantOf(Workspace) then
		return root
	end
	return nil
end

local function stepRig(entry: Rig)
	local root = liveRoot(entry.player)
	if root == nil then
		for _, loop in { entry.aura, entry.haul, entry.hose } do
			if loop then
				loop:set(false)
			end
		end
		entry.auraTier = nil
		-- Forget the counter, so a character streaming back in does not crunch once.
		entry.digTick = nil
		return
	end
	entry.anchor.WorldPosition = root.Position
	local character = root.Parent :: Model

	local tier = character:GetAttribute(AuraLook.ATTRIBUTE)
	if tier ~= entry.auraTier then
		entry.auraTier = tier
		if entry.aura then
			if type(tier) == "number" then
				local volume, pitch = auraLevel(tier)
				entry.aura.sound.PlaybackSpeed = pitch
				entry.aura:set(true, volume)
			else
				entry.aura:set(false)
			end
		end
		-- No whoosh on buying/changing an aura (cut by request).
	end

	if entry.player ~= localPlayer then
		if entry.haul then
			entry.haul:set(character:GetAttribute("Hauling") == true)
		end
		if entry.hose then
			entry.hose:set(character:GetAttribute("HoseSpraying") == true)
		end
		local count = character:GetAttribute("DigTick")
		if entry.digTick ~= nil and count ~= entry.digTick then
			Sfx.playAt(if math.random() < 0.5 then "dig" else "dig2", entry.anchor)
		end
		entry.digTick = count
	end
end

local function watchPlayers()
	for _, player in Players:GetPlayers() do
		rig(player)
	end
	Players.PlayerAdded:Connect(rig)
	Players.PlayerRemoving:Connect(unrig)
	RunService.Heartbeat:Connect(function()
		for _, entry in rigs do
			stepRig(entry)
		end
	end)
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
	-- The volume sliders (Config/Prefs). Here rather than in the panel, like the mute,
	-- so they hold even if the Settings panel never builds.
	local function applyVolumes()
		Sfx.setVolumes(Prefs.get("volMaster"), Prefs.get("volSfx"), Prefs.get("volUi"), Prefs.get("volGeiger"), Prefs.get("musicLevel"))
	end
	for _, key in { "volMaster", "volSfx", "volUi", "volGeiger", "musicLevel" } do
		Prefs.observe(key, applyVolumes)
	end

	watchPlayers()
	watchVitals()
	task.spawn(watchButtons)
end

return SfxController
