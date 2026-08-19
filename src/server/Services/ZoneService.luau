--!strict
--[[
	ZoneService.lua — who is standing where.

	One owner for the question "which zone is this player in", because by Phase 4 four
	different systems need the answer and they must never disagree: exposure reads the
	rad rate from it, the loot table reads its odds from it, the border warning card
	fires on its transitions, and the HUD names it on screen.

	ZONES ARE PARTS IN THE WORLD, not numbers in a file. Each is a BasePart under
	Workspace.Zones carrying a ZoneId attribute, so the boundaries can be dragged and
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
local Zones = require(Shared.Config.Zones)
local Ticker = require(Shared.Util.Ticker)

local ZoneService = {}

local current: { [Player]: number? } = {}
local listeners: { (player: Player, newZone: number?, oldZone: number?) -> () } = {}

local function zoneAt(position: Vector3): number?
	local folder = Workspace:FindFirstChild("Zones")
	if folder == nil then
		return nil
	end

	-- Smallest containing volume wins, so a small zone can sit inside a larger one
	-- without the big one swallowing it.
	local best: number? = nil
	local bestVolume = math.huge

	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("ZoneId") :: number?
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

--- Which zone this player is in, or nil for base camp / off the map.
function ZoneService.zoneOf(player: Player): number?
	return current[player]
end

--- Ambient rads/sec where this player is standing, before any gear.
function ZoneService.ambientFor(player: Player): number
	local id = current[player]
	if id == nil then
		return 0
	end
	return Zones.get(id).baseRads * ZoneService.hotPocketFor(player)
end

--- PLAN §4's roaming high-radiation patches. Phase 4 owns them; until then every
--- patch of ground is equally hot and this is always 1.
function ZoneService.hotPocketFor(_player: Player): number
	return 1
end

--- Fires when a player crosses a border. Phase 4 hangs the survivability warning
--- card off this.
function ZoneService.onChanged(fn: (player: Player, newZone: number?, oldZone: number?) -> ())
	table.insert(listeners, fn)
end

function ZoneService.init() end

function ZoneService.start()
	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")

			local zone: number? = nil
			if root and root:IsA("BasePart") then
				zone = zoneAt(root.Position)
			end

			local previous = current[player]
			if zone ~= previous then
				current[player] = zone
				for _, fn in listeners do
					task.spawn(fn, player, zone, previous)
				end
			end
		end
	end)
end

return ZoneService
