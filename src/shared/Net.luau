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

	-- The backpack, as the player sees it. Fires only when the bag actually CHANGES
	-- (contents, decay condition, value or clean state) rather than on every tick — the
	-- bag is static for most of a run, and the smooth countdown on the detail card is
	-- computed client-side from Shared/Decay instead of being streamed.
	CarryState = "RemoteEvent", -- server -> client, on change

	-- Phase 1: base camp. Decontamination and the trader.
	StationState = "RemoteEvent", -- server -> client, what you're standing at and what's in your bag
	StationAction = "RemoteEvent", -- client -> server, scrub / sell / rack
	StationResult = "RemoteEvent", -- server -> client, "sold for $340", "needs Chem Bath"

	-- The wash pad (Config/Liquids). What is loaded and how much of it is left,
	-- change-driven like CarryState rather than per-tick, because a canister moves on
	-- a roll and on a spent charge and at no other time.
	--
	-- THERE WAS A SECOND REMOTE HERE, LiquidRoll, carrying the roll reveal. It is gone
	-- with the panel it fed: the pad announces its own result in the world now (it
	-- flashes the liquid's colour and names it on its own billboard, LiquidService),
	-- which every player on that base can see rather than just the one who stepped on
	-- it. The only client-side liquid surface left is a persistent corner badge, and a
	-- badge renders fine from idempotent state.
	LiquidState = "RemoteEvent", -- server -> client, on change

	-- Which carried item the player is physically holding. The tub refuses to wash
	-- anything you are not holding, so this had to become real state rather than the
	-- client-only hotbar selection it used to be.
	HoldInput = "RemoteEvent", -- client -> server, "hold this uid" (or nil for nothing)

	-- The wash bay. WashState is the session; WashInput is aim + intent, never
	-- progress -- the server owns the clock, exactly as the scrub timer did before it.
	WashState = "RemoteEvent", -- server -> client, the session (nil payload = ended)
	WashInput = "RemoteEvent", -- client -> server, { spraying, patchIndex }

	-- Phase 2: exposure.
	ExposureState = "RemoteEvent", -- server -> client, the rad meter, once per tick
	Blackout = "RemoteEvent", -- server -> client, you went down and what it cost

	-- The index GUI. One snapshot of data.discovered on load; the client tops it up
	-- itself from Unearthed's itemId as new discoveries happen, so this never needs
	-- to fire a second time.
	IndexState = "RemoteEvent", -- server -> client, once per load

	-- The persistent cash badge. Fires only when data.cash actually changes (sell,
	-- spend, award, or a debug /cash) plus once on load -- not per tick, since cash
	-- moves far less often than exposure does.
	CashState = "RemoteEvent", -- server -> client, on change
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
