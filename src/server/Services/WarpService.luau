--!strict
--[[
	WarpService.luau — the top-of-screen "getting around" bar's one server verb.

	The client's WarpController shows two buttons whenever the player is standing in
	no stage — BASE and SHOPS — and this is what those buttons call. The client sends
	a destination NAME and nothing else (`{ dest = "base" | "shops" }`); this file
	re-derives the actual CFrame server-side, the same way DigService decides which
	buried signal a yank meant from where the player is standing rather than trusting
	the client to name it (ARCHITECTURE.md, "the client never names what it wants").

	IT IS NOT AN ESCAPE HATCH. The wasteland is open and the only thing that stops a
	player is the arithmetic in Shared/Radiation (PLAN §3.5) — a button that lifts you
	out of a lethal field for free would gut that. So a Warp from inside a stage is
	REFUSED here, not merely hidden by the bar: `StageService.stageOf` must be nil.
	The bar hides itself in stages too, so a legitimate client never reaches the
	refusal; it is here for the one that lies.

	DESTINATIONS, AND WHY THEY ARE NOT THIS FILE'S TO DEFINE:
	  base   -> ExhibitService.plotSpawn(player), the same PlotSpawn assign() already
	            routes this player's respawns to. nil (no plot this session, all six
	            taken) falls through to the shop anchor, so the button is never dead.
	  shops  -> ExposureService.baseCampCFrame(), the RespawnAnchor in the plaza
	            aisle between the stalls and the Outfitter — already the shared
	            "where you land when you leave the field" point (blackout uses it).

	Neither is looked up from Workspace here: this service owns the RULE (are you
	allowed to, and where does the name point), not the geometry.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local StageService = require(script.Parent.StageService)
local DigService = require(script.Parent.DigService)
local ExhibitService = require(script.Parent.ExhibitService)
local ExposureService = require(script.Parent.ExposureService)

local WarpService = {}

--- Spam guard. The move itself is idempotent, but firing it repeatedly while the
--- character is still settling reads as a rubber-band; one hop per this many seconds
--- is plenty for a navigation button.
local COOLDOWN = 0.5
local lastWarp: { [Player]: number } = {}

--- Lift so the character drops onto the pad rather than spawning inside it — the
--- same +4 ExhibitService.teleportToSpawn and DebugService's /stage both use.
local DROP_IN = Vector3.new(0, 4, 0)

local function destinationFor(player: Player, dest: string): CFrame?
	if dest == "shops" then
		return ExposureService.baseCampCFrame()
	elseif dest == "base" then
		local spawn = ExhibitService.plotSpawn(player)
		if spawn then
			return spawn.CFrame + DROP_IN
		end
		-- No plot this session. The shop anchor is a safe, sensible landing rather
		-- than leaving the button do nothing.
		return ExposureService.baseCampCFrame()
	end
	return nil
end

local function onWarp(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local dest = payload.dest
	if dest ~= "base" and dest ~= "shops" then
		return
	end

	-- Never out of a live field. See the header.
	if StageService.stageOf(player) ~= nil then
		return
	end
	-- Rooted mid-haul: DigService releases the lock on every path that can
	-- invalidate it and a teleport is not one of those paths, so refuse rather than
	-- strand a rooted player somewhere new.
	if DigService.isLocked(player) then
		return
	end

	local now = os.clock()
	local previous = lastWarp[player]
	if previous ~= nil and now - previous < COOLDOWN then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local target = destinationFor(player, dest)
	if target == nil then
		return
	end

	lastWarp[player] = now
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
end

function WarpService.init() end

function WarpService.start()
	Net.get("Warp").OnServerEvent:Connect(function(player: Player, payload: any)
		local ok, err = pcall(onWarp, player, payload)
		if not ok then
			warn(`[warp] {player.Name}: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastWarp[player] = nil
	end)
end

return WarpService
