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
	--
	-- DigYank replaced a DigInput boolean when the pull became a mash (PLAN §Step 2).
	-- It carries NO PAYLOAD, and that is the security design, not laziness: the client
	-- says "I clicked", never how hard, so the only thing it can lie about is HOW OFTEN.
	-- That one remaining lie is capped by a token bucket on the server -- see the yank
	-- limiter in Services/DigService, and Tuning's PULL_YANK_* block for why the ceiling
	-- sits where it does.
	DigYank = "RemoteEvent", -- client -> server, one per click, no payload
	--
	-- The pull is two beats: you TAP to commit to one buried item, and only then do you
	-- mash it out. DigLock carries a single boolean -- lock, or release -- and never an
	-- item id: the server picks whatever the player is standing on, exactly as it does
	-- for a yank. Locking roots the character, so the RELEASE half of this remote is
	-- load-bearing in a way most remotes are not; every path that can strand a rooted
	-- player is enumerated in Services/DigService.
	DigLock = "RemoteEvent", -- client -> server, true = lock on, false = release
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

	-- The top-of-screen "getting around" bar (client WarpController). The client
	-- sends only a destination NAME -- { dest = "base" | "shops" } -- never a
	-- position, and WarpService re-derives the CFrame server-side, exactly the way
	-- DigService re-derives which signal a yank means. It is REFUSED from inside a
	-- stage (StageService.stageOf ~= nil) so it can never be an escape hatch out of a
	-- lethal field; the bar hides itself there too, so that path is edge-only.
	Warp = "RemoteEvent", -- client -> server, { dest = "base" | "shops" }
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
