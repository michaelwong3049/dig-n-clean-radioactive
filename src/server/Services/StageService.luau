--!strict
--[[
	StageService.lua — who is standing where.

	One owner for the question "which stage is this player in", because by Phase 4 four
	different systems need the answer and they must never disagree: exposure reads the
	rad rate from it, the loot table reads its odds from it, the border warning card
	fires on its transitions, and the HUD names it on screen.

	STAGES ARE PARTS IN THE WORLD, not numbers in a file. Each is a BasePart under
	Workspace.Stages carrying a StageId attribute, so the boundaries can be dragged and
	resized in Studio. PLAN §4 makes station distance the primary tension lever and says
	to tune it before rad rates — that is a level-design job, and level designers should
	not be editing Lua to do it.

	NOTHING HERE DENIES ENTRY. There is no gate, no unlock check, no permission. PLAN
	§3.5: the wasteland is open end to end from minute one, and the only thing that
	stops a player is the arithmetic in Shared/Radiation.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Stages = require(Shared.Config.Stages)
local Ticker = require(Shared.Util.Ticker)

local StageService = {}

local current: { [Player]: number? } = {}
local listeners: { (player: Player, newStage: number?, oldStage: number?) -> () } = {}

local function stageAt(position: Vector3): number?
	local folder = Workspace:FindFirstChild("Stages")
	if folder == nil then
		return nil
	end

	-- Smallest containing volume wins, so a small stage can sit inside a larger one
	-- without the big one swallowing it.
	local best: number? = nil
	local bestVolume = math.huge

	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("StageId") :: number?
			if id then
				local localPos = part.CFrame:PointToObjectSpace(position)
				local half = part.Size / 2
				-- Y is ignored on purpose: standing on a rock in the Ash Flats is
				-- still standing in the Ash Flats.
				if math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z then
					local volume = part.Size.X * part.Size.Z
					if volume < bestVolume then
						best, bestVolume = id, volume
					end
				end
			end
		end
	end

	return best
end

--- Which stage this player is in, or nil for base camp / off the map.
function StageService.stageOf(player: Player): number?
	return current[player]
end

--- Ambient rads/sec where this player is standing, before any gear.
---
--- DEPTH-BASED, NOT FLAT. `Stages.radsAt` interpolates between a stage's entrance
--- and deepest rate; depthFrac here comes from this player's live X position
--- against the stage's own bounds, so walking further in climbs toward the peak
--- and crossing into the next stage resets to a fresh, higher entrance rate. See
--- Stages.radsAt's header for why this is a separate gradient from the loot-table
--- Stage system, which happens to run the same direction in Stage 1.
function StageService.ambientFor(player: Player): number
	local id = current[player]
	if id == nil then
		return 0
	end

	local depthFrac = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local minX, _minZ, maxX, _maxZ = Stages.bounds(id)
		local width = maxX - minX
		if width > 0 then
			depthFrac = (root.Position.X - minX) / width
		end
	end

	return Stages.radsAt(id, depthFrac) * StageService.hotPocketFor(player)
end

--- PLAN §4's roaming high-radiation patches. Phase 4 owns them; until then every
--- patch of ground is equally hot and this is always 1.
function StageService.hotPocketFor(_player: Player): number
	return 1
end

--- Fires when a player crosses a border. Phase 4 hangs the survivability warning
--- card off this.
function StageService.onChanged(fn: (player: Player, newStage: number?, oldStage: number?) -> ())
	table.insert(listeners, fn)
end

function StageService.init() end

function StageService.start()
	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")

			local stage: number? = nil
			if root and root:IsA("BasePart") then
				stage = stageAt(root.Position)
			end

			local previous = current[player]
			if stage ~= previous then
				current[player] = stage
				for _, fn in listeners do
					task.spawn(fn, player, stage, previous)
				end
			end
		end
	end)
end

return StageService
