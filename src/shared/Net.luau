--!strict
--[[
	Net.lua — every remote in the game, declared in one table.

	ARCHITECTURE.md schedules this for Phase 1. It arrives early because the debug
	HUD needs a channel, and the alternative — one ad-hoc RemoteEvent parented
	wherever it was convenient — is exactly the mess this file exists to prevent.

	The server creates the instances; the client waits for them. Add a line to
	REMOTES and both sides get it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTES: { [string]: string } = {
	-- Debug / tuning harness. Goes away when Phase 2 lands the real HUD.
	DebugState = "RemoteEvent", -- server -> client, one payload per tick

	-- Phase 1: the sweep/dig loop.
	--
	-- SweepState carries contacts INSIDE THE PLAYER'S OWN REVEAL RADIUS, as offsets
	-- relative to that player — never world coordinates, and never anything outside
	-- the radius. Those signals are already standing in the world as auras that every
	-- client can see, so the payload leaks nothing a player is not looking at. The
	-- rest of the field never crosses: a digging game that replicates buried loot
	-- positions gets an ESP script written for it inside a week, and the rarity
	-- economy is the whole product. See the header of Services/DigService.
	SweepState = "RemoteEvent", -- server -> client, one payload per tick
	DigInput = "RemoteEvent", -- client -> server, hold-to-dig on/off
	Unearthed = "RemoteEvent", -- server -> client, the slot-machine moment

	-- Phase 1: base camp. Decontamination and the trader.
	StationState = "RemoteEvent", -- server -> client, what you're standing at and what's in your bag
	StationAction = "RemoteEvent", -- client -> server, scrub / sell / rack
	StationResult = "RemoteEvent", -- server -> client, "sold for $340", "needs Chem Bath"

	-- Phase 2: exposure.
	ExposureState = "RemoteEvent", -- server -> client, the rad meter, once per tick
	Blackout = "RemoteEvent", -- server -> client, you went down and what it cost
}

local Net = {}

local folder: Instance

-- Edit mode counts as neither running-server nor running-client: IsServer() is false
-- and IsClient() is true, so the naive version of this took the client branch and
-- blocked on WaitForChild forever the moment anyone required Net from the command
-- bar. Edit takes the create-if-missing path instead — idempotent, and it keeps
-- static checks from hanging Studio.
--
-- IsEdit() is plugin-security, so calling it straight from a real client script
-- throws "lacking capability Plugin". pcall gives us the answer where we are allowed
-- to have it (the command bar) and a safe `false` everywhere else — which is exactly
-- right, because everywhere else is genuinely not edit mode.
local isEdit = false
do
	local ok, result = pcall(function()
		return RunService:IsEdit()
	end)
	isEdit = ok and result == true
end

if RunService:IsServer() or isEdit then
	local existing = ReplicatedStorage:FindFirstChild("Net")
	if existing then
		folder = existing
	else
		local made = Instance.new("Folder")
		made.Name = "Net"
		made.Parent = ReplicatedStorage
		folder = made
	end

	for name, className in REMOTES do
		if folder:FindFirstChild(name) == nil then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	local found = ReplicatedStorage:WaitForChild("Net", 15)
	assert(found, "Net: the server never created ReplicatedStorage.Net — did the server bootstrap fail?")
	folder = found
end

--- Fetch a remote by name. Yields on the client until it replicates.
function Net.get(name: string): any
	assert(REMOTES[name], `Net: no remote named "{name}" — add it to REMOTES`)
	return folder:WaitForChild(name)
end

return Net
