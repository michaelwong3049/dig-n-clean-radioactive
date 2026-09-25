--!strict
--[[
	HazardService.luau — nukes that went off, and the craters they leave.

	DigService decides WHEN a nuke blows (its pull fuse ran out, Config/Detonation);
	this file owns everything after that:

	  THE BLAST. One hit of health off everyone inside the blast radius, the moment it
	  goes off, falling from `hit` at ground zero to BLAST_EDGE of it at the rim. It is
	  banked here and TAKEN by ExposureService on its next tick, because ExposureService
	  is the only thing allowed to write health -- the same "one owner" rule it keeps
	  for WalkSpeed. The knockback is not done here at all: a character's physics
	  belongs to its own client, so every client reads the Detonation remote and flings
	  its own player (DetonationController).

	  THE CRATER. A glowing orb of hot air over the blast point that burns health off
	  anyone inside it, for `orbLife` seconds, shrinking and cooling over the last part
	  of that (Shared/Detonation.orbStrength). ExposureService asks burnAt() once per
	  player per tick and folds the answer into the reading's healthBurn, so the HUD,
	  the SURVIVABLE countdown, the white burn overlay and the blackout all treat it
	  exactly like aura failure without knowing it is a different thing.

	EVERYONE IN RANGE, not just the puller -- on request. It is a shared server and a
	detonation is a shared event: the armed nuke ticks and glows red where everyone can
	see it for the seconds before it goes, and the orb is impossible to miss afterwards.

	THE CRATER IS A PART IN WORKSPACE, carrying its numbers as attributes, with nothing
	drawn on it. Every visual (the scorched ground, the fissures, the orb itself) is
	built client-side off those attributes, which is also how a player who joins while a
	crater is still hot sees it. Timestamps are Workspace:GetServerTimeNow(), which both
	sides share.

	REQUIRES NOTHING SERVER-SIDE. DigService calls in (detonate) and ExposureService
	calls in (burnAt, takeHit), and ExposureService already requires DigService -- so
	this sits below both in the boot ORDER and depends on neither.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local DetonationConfig = require(Shared.Config.Detonation)
local Detonation = require(Shared.Detonation)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local HazardService = {}

type Crater = {
	position: Vector3,
	blast: Detonation.Blast,
	bornAt: number, -- Workspace:GetServerTimeNow()
	marker: BasePart,
}

local craters: { Crater } = {}

-- Blast damage owed to each player, banked by detonate() and paid out by
-- ExposureService on its next tick (takeHit). Summed, so two blasts on one tick both land.
local pendingHits: { [Player]: number } = {}

local detonationRemote: any = nil

local function folder(): Folder
	local existing = Workspace:FindFirstChild(DetonationConfig.FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = DetonationConfig.FOLDER
	made.Parent = Workspace
	return made
end

--- A nuke went off at `position` (the surface point over where it was buried).
--- `visualScale` is how big it looked -- Weight.sizeScale * sizeMult * Payload, the
--- product its haul lump was :ScaleTo'd by.
function HazardService.detonate(position: Vector3, rarity: string, visualScale: number)
	local blast = Detonation.blastFor(rarity, visualScale)

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local hit = Detonation.hitAt((root.Position - position).Magnitude, blast)
			if hit > 0 then
				pendingHits[player] = (pendingHits[player] or 0) + hit
			end
		end
	end

	local now = Workspace:GetServerTimeNow()

	-- The marker is the crater's identity and nothing else: invisible, out of every
	-- query and collision, carrying the numbers the client dresses it from.
	local marker = Instance.new("Part")
	marker.Name = "Crater"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	marker.Transparency = 1
	marker.Size = Vector3.one
	marker.CFrame = CFrame.new(position)
	marker:SetAttribute("Rarity", rarity)
	marker:SetAttribute("OrbRadius", blast.orbRadius)
	marker:SetAttribute("OrbLife", blast.orbLife)
	marker:SetAttribute("BornAt", now)
	marker.Parent = folder()

	table.insert(craters, {
		position = position,
		blast = blast,
		bornAt = now,
		marker = marker,
	})

	detonationRemote:FireAllClients({
		position = position,
		rarity = rarity,
		blastRadius = blast.blastRadius,
		orbRadius = blast.orbRadius,
	})

	print(`[boom] {rarity} nuke detonated at {math.floor(position.X)}, {math.floor(position.Z)} — orb {string.format("%.1f", blast.orbRadius)} studs for {blast.orbLife}s`)
end

--- Health/sec the craters are burning off whoever stands at `position`. Summed, so
--- overlapping craters stack -- two nukes gone off side by side are worse than one.
function HazardService.burnAt(position: Vector3): number
	if #craters == 0 then
		return 0
	end

	local now = Workspace:GetServerTimeNow()
	local total = 0
	for _, crater in craters do
		local strength = Detonation.orbStrength(now - crater.bornAt, crater.blast.orbLife)
		if strength > 0 then
			local distance = (position - crater.position).Magnitude
			total += Detonation.orbBurnAt(distance, crater.blast.orbRadius, crater.blast.orbBurn, strength)
		end
	end
	return total
end

--- The blast damage banked for this player since the last call, and clear it. Called
--- by ExposureService once per tick whether or not it can apply it, so a hit taken
--- while already blacked out is dropped rather than landing on the next life.
function HazardService.takeHit(player: Player): number
	local hit = pendingHits[player]
	if hit == nil then
		return 0
	end
	pendingHits[player] = nil
	return hit
end

function HazardService.init()
	detonationRemote = Net.get("Detonation")

	-- Craters are runtime objects, but Workspace is a thing people save from Studio. A
	-- folder of them published into the place would stand there forever with nothing
	-- burning and nothing cleaning them up -- same guard as DigService's auras.
	local stale = Workspace:FindFirstChild(DetonationConfig.FOLDER)
	if stale then
		stale:Destroy()
	end
end

function HazardService.start()
	Players.PlayerRemoving:Connect(function(player)
		pendingHits[player] = nil
	end)

	-- Spent craters go, marker and all -- the client tears its visuals down with it.
	Ticker.every(Tuning.TICK_RATE, function()
		if #craters == 0 then
			return
		end
		local now = Workspace:GetServerTimeNow()
		for index = #craters, 1, -1 do
			local crater = craters[index]
			if now - crater.bornAt >= crater.blast.orbLife then
				crater.marker:Destroy()
				table.remove(craters, index)
			end
		end
	end)
end

return HazardService
