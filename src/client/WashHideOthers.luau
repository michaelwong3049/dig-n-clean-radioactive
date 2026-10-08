--!strict
--[[
	WashHideOthers.luau — every OTHER player vanishes from your screen while you wash.

	The bay is first-person and close in, and a friend walking round your base stood
	between the hose and the crust, or hung a name tag across the shot. Your own body is
	already gone (WashController.applyHidden); this does the same for everyone else, on
	this client only -- they still see each other, and they still see you.

	WHAT IS HIDDEN, AND HOW EACH IS GIVEN BACK. Parts and decals take
	LocalTransparencyModifier = 1 (render-only, never replicated, and Roblox's own
	TransparencyController only touches the LOCAL character, so unlike your own body it
	does not need re-asserting every frame). Name tags and the HP bar
	(NameTagController parents them into the character), aura sparkles and lights have
	no such modifier, so their `Enabled` is turned off and the ORIGINAL value is kept
	and restored, never stamped back to true.

	A SWEEP EVERY HALF SECOND rather than a web of DescendantAdded connections: it picks
	up a player who respawns or walks in mid-wash, and an accessory or held nuke that
	loads late, with nothing to disconnect. Anything already hidden is skipped.

	PLAIN TABLES, NOT WEAK ONES -- Instance keys in a weak table are not collected the way
	you would expect (see the project notes). `restore` clears them.
]]

local Players = game:GetService("Players")

local WashHideOthers = {}

local SWEEP = 0.5

--- instance -> what to put back. A number is the LocalTransparencyModifier it had; a
--- boolean is the Enabled it had.
local hidden: { [Instance]: number | boolean } = {}
local active = false
local lastSweep = -math.huge

local function hideOne(inst: Instance)
	if hidden[inst] ~= nil then
		return
	end
	if inst:IsA("BasePart") or inst:IsA("Decal") then
		hidden[inst] = (inst :: any).LocalTransparencyModifier
		;(inst :: any).LocalTransparencyModifier = 1
	elseif
		inst:IsA("LayerCollector")
		or inst:IsA("ParticleEmitter")
		or inst:IsA("Beam")
		or inst:IsA("Trail")
		or inst:IsA("Light")
		or inst:IsA("Highlight")
	then
		-- Highlight has no `Enabled` on older engines; read it guarded.
		local ok, enabled = pcall(function()
			return (inst :: any).Enabled
		end)
		if ok and type(enabled) == "boolean" then
			hidden[inst] = enabled
			;(inst :: any).Enabled = false
		end
	end
end

local function sweep()
	local me = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if player ~= me and character then
			for _, inst in character:GetDescendants() do
				hideOne(inst)
			end
		end
	end
end

function WashHideOthers.begin()
	active = true
	lastSweep = os.clock()
	sweep()
end

--- From the wash render step. Cheap when nothing is due.
function WashHideOthers.tick()
	if active and os.clock() - lastSweep >= SWEEP then
		lastSweep = os.clock()
		sweep()
	end
end

--- Idempotent: exitView can run more than once.
function WashHideOthers.restore()
	active = false
	for inst, was in hidden do
		if inst.Parent ~= nil then
			if type(was) == "number" then
				(inst :: any).LocalTransparencyModifier = was
			else
				(inst :: any).Enabled = was
			end
		end
	end
	table.clear(hidden)
end

return WashHideOthers
