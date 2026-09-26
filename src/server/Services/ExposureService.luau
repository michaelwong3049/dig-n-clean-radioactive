--!strict
--[[
	ExposureService.lua — the rad meter. This is the differentiator (PLAN §3).

	Every number here comes out of Shared/Radiation, the same module the client uses to
	draw the HUD, so the meter a player watches and the meter that puts them down can
	never disagree. This service owns the TRUTH; the client owns the picture.

	TWO WAYS TO GO DOWN, kept apart on purpose (PLAN §14):
	  exposure hits 100%  — the green death. Ambient plus what you are carrying.
	  health hits 0       — the white death. From aura failure over-tier, or from a
	                        detonated nuke: its blast and its crater (HazardService).

	BLACKOUT IS NOT A DEATH PENALTY. You keep cash, gear, the locker and anything
	displayed. You lose the dirty bag you were greedily hauling, and it stays on the
	ground where you fell for ninety seconds — glowing, server-visible, and grabbable
	by anyone including the player who watched you go down. PLAN §3.1 is emphatic that
	this punishes greed rather than existence, and that losing progress in a casual
	Roblox digging game kills retention.

	EXCEPT WHEN A BLAST PUTS YOU DOWN. Go down to a detonation -- its hit, or its
	crater's orb burning the last of your health -- and the bag does not drop: every
	nuke in it goes off where you fell, clean or crusted, crates included. Each is a
	real detonation (HazardService), staggered into a chain, so anyone standing close
	takes every hit and can go down to it -- and their bag goes off in turn. Radiation
	(the green death, or plain aura failure) still drops the bag for anyone to grab.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Stages = require(Shared.Config.Stages)
local Radiation = require(Shared.Radiation)
local Decay = require(Shared.Decay)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)
local Bag = require(Shared.Bag)
local Items = require(Shared.Config.Items)
local Weight = require(Shared.Config.Weight)
local Payload = require(Shared.Config.Payload)

local DataService = require(script.Parent.DataService)
local WashService = require(script.Parent.WashService)
local StageService = require(script.Parent.StageService)
-- Read ONLY to name the camp you are standing in on the HUD. CampService requires
-- only DataService, so the direction is safe.
local CampService = require(script.Parent.CampService)
-- Read ONLY for DigService.isLocked, below. The direction is safe: DigService requires
-- DataService and StageService but never this file, so there is no cycle. It is also
-- the pattern ToolService already uses to ask DigService what the player is doing.
local DigService = require(script.Parent.DigService)
-- Craters left by detonated nukes: their burn and the one-off blast hit both land on
-- HEALTH, and this loop is the only thing that writes health. HazardService requires
-- nothing server-side, so this adds no cycle.
local HazardService = require(script.Parent.HazardService)

local ExposureService = {}

local HEALTH_REGEN_PER_SEC = 2.5 -- PLAN §3.5: slowly out of radiation...
local BAG_LIFETIME = 90 -- §3.1, exactly ninety seconds
local DEFAULT_SHOWER_RADIUS = 10

-- A blast death sets the bag off as a CHAIN, one nuke every CHAIN_STAGGER seconds,
-- rather than all on one frame: it reads as a string of booms instead of one, and it
-- spreads the client's detonation FX over a few seconds for a full 34-slot bag. Each
-- goes off a little way from where you fell (up to CHAIN_SCATTER studs) so the
-- craters overlap rather than stacking into a single one.
local CHAIN_STAGGER = 0.15
local CHAIN_SCATTER = 4

-- Roblox's own out-of-the-box jump values, restored whenever a player is not rooted by
-- a dig lock. Hardcoding the engine defaults is safe here only because NOTHING else in
-- the game writes to jump -- this loop is the sole owner, exactly as it is for
-- WalkSpeed. If something ever does start tuning jump (a Boots perk, say), these stop
-- being the right thing to restore and the pair should be captured per-character on
-- spawn instead. Which of the two applies is decided by Humanoid.UseJumpPower, so both
-- are written rather than guessing at the rig.
local DEFAULT_JUMP_POWER = 50
local DEFAULT_JUMP_HEIGHT = 7.2

type State = {
	exposure: number,
	health: number,
	downed: boolean,
	survivableRatchet: number?, -- see stepPlayer's "the countdown does not recover" note
}

local states: { [Player]: State } = {}
local bagContents: { [Instance]: { any } } = {}

-- Debug console only (see DebugService's /speed). A sustained WalkSpeed override:
-- nil follows the player's trained speed as normal (Config/Treadmill), a number pins
-- WalkSpeed to exactly that and ignores the haul penalty. Session-only and deliberately NOT persisted --
-- unlike /cash and /gear, which are real game state, this is a testing convenience
-- that should die with the session.
local speedOverrides: { [Player]: number } = {}

-- Debug console only (see DebugService's /jump). Same shape as speedOverrides, but
-- shaped like JumpHeight (studs) rather than JumpPower -- "height" is the number a
-- person actually means when they ask for a higher jump. JumpPower is still derived
-- and written alongside it (see the tick loop below) for the same reason the two
-- DEFAULT_JUMP_* constants both get written every tick: UseJumpPower decides which
-- one the rig actually honours, and this shouldn't have to guess which.
local jumpOverrides: { [Player]: number } = {}

-- Debug console only (see DebugService's /immunity). Radiation stops reaching the
-- player: no exposure build-up, no aura-failure burn. Deliberately radiation ONLY --
-- a detonation's blast and its crater still hurt, so /boom stays testable while
-- immune. Session-only, like the overrides above.
local immune: { [Player]: boolean } = {}

local stateRemote: any = nil
local blackoutRemote: any = nil
local droppedBagRemote: any = nil

local INFINITE = -1
local function finite(n: number): number
	return if n == math.huge or n ~= n then INFINITE else n
end

local function stateFor(player: Player): State
	local existing = states[player]
	if existing then
		return existing
	end
	local fresh: State = { exposure = 0, health = Tuning.MAX_HEALTH, downed = false, survivableRatchet = nil }
	states[player] = fresh
	return fresh
end

-- ── Showers (PLAN §3.2) ───────────────────────────────────────────────────
--
-- These flush YOU. They do not clean items and they do not stop the decay clock —
-- only a decon station does that. "I am fine" and "my loot is fine" stay two
-- different problems, and a player can be perfectly safe while their bag rots.

-- Cached, because the naive version walked EVERY descendant of Workspace once per
-- player per tick. That is 10 full-world scans a second per player, against a world
-- that will eventually hold six stages of scenery — it was fine at 60 parts and would
-- have quietly become the most expensive thing in the game.
local showerCache: { { position: Vector3, radius: number } } = {}
local cacheAge = math.huge
local CACHE_REFRESH = 2

local function refreshShowerCache()
	table.clear(showerCache)
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Shower") == true then
			table.insert(showerCache, {
				position = descendant.Position,
				radius = (descendant:GetAttribute("Radius") :: number?) or DEFAULT_SHOWER_RADIUS,
			})
		end
	end
end

local function inShower(position: Vector3): boolean
	for _, shower in showerCache do
		if (shower.position - position).Magnitude <= shower.radius then
			return true
		end
	end
	return false
end

-- ── The dropped bag (PLAN §3.1) ────────────────────────────────────────────

--- Tell the bag's owner something about it (Net.DroppedBag), if they are still here.
--- The owner is read off the bag's OwnerId attribute rather than its name, which is
--- display text.
local function tellOwner(bag: BasePart, payload: { [string]: any })
	local owner = Players:GetPlayerByUserId((bag:GetAttribute("OwnerId") :: number?) or 0)
	if owner then
		payload.id = bag:GetAttribute("BagId")
		droppedBagRemote:FireClient(owner, payload)
	end
end

local function giveBagTo(bag: BasePart, taker: Player)
	local contents = bagContents[bag]
	if contents == nil then
		return
	end

	local data = DataService.data(taker)
	if data == nil then
		return
	end

	local stats = StatResolver.get(data)
	local taken = 0
	while #contents > 0 and Bag.used(data) < stats.capacity do
		table.insert(data.carry, table.remove(contents, 1))
		taken += 1
	end

	print(`[bag] {taker.Name} recovered {taken} item(s); {#contents} left in the bag`)

	-- Keep the label honest. Carry capacity means a full bag usually CANNOT be
	-- recovered in one go, so "12 item(s)" hovering over a bag holding 8 is an
	-- outright lie at exactly the moment the player is deciding whether to risk
	-- another trip out to it.
	local prompt = bag:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ObjectText = `{#contents} item(s)`
	end
	local billboard = bag:FindFirstChildOfClass("BillboardGui")
	local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = `dropped bag\n{#contents} item(s)`
	end

	-- The last take is told by the bag's Destroying hook (dropBag), not here.
	if #contents > 0 then
		tellOwner(bag, { items = #contents })
	end

	if #contents == 0 then
		bagContents[bag] = nil
		bag:Destroy()
	end
end

local function dropBag(player: Player, data: any, position: Vector3): number
	-- PLAN §3.1 says you drop your UNCLEANED carry. Read literally: anything you
	-- already scrubbed clean stays with you. Being generous here is deliberate — a
	-- cleaned item represents work already done, and taking it back would punish the
	-- player twice for one mistake.
	local dropped = {}
	for index = #data.carry, 1, -1 do
		local item = data.carry[index]
		if not Contamination.isClean(item.patches or {}) then
			table.insert(dropped, item)
			table.remove(data.carry, index)
		end
	end

	if #dropped == 0 then
		return 0
	end

	local bag = Instance.new("Part")
	bag.Name = `DroppedBag_{player.Name}`
	bag.Size = Vector3.new(2.2, 1.6, 2.2)
	bag.Position = position + Vector3.new(0, 1, 0)
	bag.Anchored = true
	bag.CanCollide = false
	bag.Color = Color3.fromHex("8FE04A")
	bag.Material = Enum.Material.SmoothPlastic
	bag.Parent = Workspace

	-- Matte since the de-neon pass; a low locator light stays, because this is a
	-- recoverable stash sitting out in the world, not decoration -- you need to be able
	-- to spot it to go back for it. Kept dim (was 2.2) so it marks the bag without
	-- lighting the ground around it.
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("8FE04A")
	light.Range = 14
	light.Brightness = 0.8
	light.Parent = bag

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(190, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = bag

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromHex("D6FFB0")
	label.TextStrokeTransparency = 1
	label.Text = `{player.Name}'s bag\n{#dropped} item(s)`
	label.Parent = billboard

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.fromHex("1A1A1A") -- Kit.C.hazardBlack's value — same cartoon black as every other sign
	labelStroke.Thickness = 2
	labelStroke.LineJoinMode = Enum.LineJoinMode.Round
	labelStroke.Parent = label

	-- Anyone can take it. That is the point (§3.1): a free social system that costs
	-- almost nothing to build.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab bag"
	prompt.ObjectText = `{#dropped} item(s)`
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bag
	prompt.Triggered:Connect(function(taker: Player)
		giveBagTo(bag, taker)
	end)

	bagContents[bag] = dropped
	Debris:AddItem(bag, BAG_LIFETIME)

	-- The owner's "get it back" tracker (BagTrackerController). Sent as a position and
	-- a server-clock deadline rather than the part itself: the bag lies where you fell
	-- and you have just been sent to camp, so the part may not be streamed in on your
	-- client at all. Emptied or timed out, it goes the same way -- Destroying.
	bag:SetAttribute("OwnerId", player.UserId)
	bag:SetAttribute("BagId", HttpService:GenerateGUID(false))
	tellOwner(bag, {
		position = bag.Position,
		expiresAt = Workspace:GetServerTimeNow() + BAG_LIFETIME,
		items = #dropped,
	})
	bag.Destroying:Connect(function()
		bagContents[bag] = nil
		tellOwner(bag, { gone = true })
	end)

	return #dropped
end

--- A blast put this player down: EVERY nuke in the bag goes off where they fell, and
--- the bag is empty afterwards. Clean ones too -- dropBag's "washed work stays with
--- you" generosity is the radiation penalty; this one is the whole haul. Each is sized
--- exactly as it was dug (the same Weight * sizeMult * Payload product DigService
--- hands HazardService for a fuse that ran out), so a bag of big rare finds makes a
--- far worse crater field than a bag of scrap.
local function detonateBag(player: Player, data: any, position: Vector3): number
	local blowing = table.clone(data.carry)
	table.clear(data.carry)
	if #blowing == 0 then
		return 0
	end

	-- Onto the ground under where they fell, so the craters sit on it (the root is a
	-- few studs up). Cast before blackout teleports the character away.
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	local ground = if hit then hit.Position else position - Vector3.new(0, 3, 0)

	for index, item in blowing do
		local def = if Items.has(item.itemId) then Items.get(item.itemId) else nil
		local scale = if def then Weight.sizeScale(def.weight) * (def.sizeMult or 1) * Payload.forUid(item.uid) else 1
		local angle = math.random() * math.pi * 2
		local reach = if index == 1 then 0 else math.random() * CHAIN_SCATTER
		local at = ground + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		task.delay(CHAIN_STAGGER * (index - 1), HazardService.detonate, at, item.rarity, scale)
	end

	return #blowing
end

-- ── Blackout ───────────────────────────────────────────────────────────

--- Where a blacked-out player wakes up — and, since the top-of-screen warp bar,
--- where "SHOPS" drops you too (WarpService). It is the one shared answer to "where
--- do you land when you leave the field": the RespawnAnchor in the plaza aisle
--- between the stalls and the Outfitter.
---
--- This used to be FindFirstChildWhichIsA("SpawnLocation") — which searches DIRECT
--- CHILDREN OF WORKSPACE ONLY. BaseCamp parents its spawn inside the camp model, so
--- the search never matched and every blackout fell through to the hardcoded
--- CFrame.new(0, 8, 0) below. That point sat inside Stage 1's footprint: blacking out
--- teleported you into the radioactive field you had just escaped. It was silent for
--- the entire life of the project, which is why the last resort now warns.
---
--- The anchor is a NAMED part rather than "whichever SpawnLocation turns up first",
--- because the world now contains seven of those and picking one arbitrarily would
--- have swapped one wrong answer for another. It sits on the camp's shower grate, so
--- you come round already being flushed — a relief beat instead of a punishment one.
local warnedNoAnchor = false

function ExposureService.baseCampCFrame(): CFrame
	local anchor = Workspace:FindFirstChild("RespawnAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		return anchor.CFrame + Vector3.new(0, 4, 0)
	end

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.CFrame + Vector3.new(0, 4, 0)
	end

	if not warnedNoAnchor then
		warnedNoAnchor = true
		warn("[exposure] no RespawnAnchor and no SpawnLocation in Workspace — blacking out to (0, 8, 0), which may be inside a stage")
	end
	return CFrame.new(0, 8, 0)
end

--- Where you went down, for the death screen: the stage (or camp) name the HUD was
--- showing, and how deep. Read by the caller before blackout teleports you to camp.
type Where = { stageName: string, depth: number }

local function blackout(player: Player, state: State, cause: string, where: Where)
	state.downed = true

	local data = DataService.data(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	-- A blast death sets the bag off; any other death drops it (header).
	local lost, detonated = 0, 0
	if data and root and root:IsA("BasePart") then
		if cause == "blast" then
			detonated = detonateBag(player, data, root.Position)
		else
			lost = dropBag(player, data, root.Position)
		end
	end

	state.exposure = 0
	state.health = Tuning.MAX_HEALTH
	state.survivableRatchet = nil

	if root and root:IsA("BasePart") then
		root.CFrame = ExposureService.baseCampCFrame()
	end

	blackoutRemote:FireClient(player, {
		cause = cause,
		itemsDropped = lost,
		itemsDetonated = detonated,
		stageName = where.stageName,
		depth = where.depth,
	})
	print(`[rads] {player.Name} blacked out ({cause}) — dropped {lost}, detonated {detonated} item(s)`)

	-- Brief grace so they do not immediately re-accrue while the screen is still white.
	task.delay(1.5, function()
		state.downed = false
	end)
end

-- ── Tick ────────────────────────────────────────────────────────────

local function stepPlayer(player: Player, dt: number)
	local data = DataService.data(player)
	if data == nil then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local state = stateFor(player)
	local stats = StatResolver.get(data)
	local stageId = StageService.stageOf(player)
	local ambient = StageService.ambientFor(player)
	-- Metres east of base camp's edge, for the HUD's depth readout. Purely a
	-- function of X position -- 0 in camp, climbing as the player walks the chain.
	local depth = Stages.depthBelowCamp(root.Position.X)

	-- MOVEMENT APPLIED LIVE, HERE, FOR THE SAME REASON THE DECAY CLOCK IS: this loop
	-- already resolves `stats` (which carries `walkSpeed`/`haulPenalty`) and already
	-- has `root`/`character` in hand for every player, every tick. Before this,
	-- NOTHING ever wrote to Humanoid.WalkSpeed outside the /speed debug command (see
	-- DebugService.luau) -- StatResolver.effectiveWalkSpeed existed and Spec.luau
	-- checked its math, but no live system actually applied it, so the speed stat did
	-- nothing you could feel. Recomputing it every tick rather than hooking an event
	-- follows ShopService's own stated rule ("resist the urge to add machinery here...
	-- StatResolver.get() is recomputed every tick, and ToolService... re-equips on a
	-- mismatch") -- the same reason a new tier is in your hands within a third of a
	-- second with no event.
	--
	-- IT IS ALSO WHAT MAKES THE TREADMILL WORK AT ALL. `walkSpeed` is trained now
	-- (Config/Treadmill) and climbs while the player stands on a belt, so the number
	-- this loop reads genuinely changes mid-session -- where a Boots tier only ever
	-- changed at a shop counter. Nothing here had to learn that: the stat moved tracks
	-- underneath StatResolver and this loop still just asks for it.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- LOCKED ON, OR WASHING == ROOTED. Two independent features each need to plant
		-- the player's feet -- DigService's haul lock (see its own header: committing
		-- to a haul plants your feet) and WashService's session (you are standing at a
		-- tub aiming a hose in third person; walking off mid-spray would drag the
		-- camera anchor with you) -- and this loop is the ONLY thing in the game
		-- allowed to write WalkSpeed, so both read from here rather than fighting over
		-- it on alternating ticks.
		--
		-- Jump goes to zero with it, or "rooted" means standing still and hopping off
		-- the signal (or out of the wash) anyway.
		--
		-- The safety of this rests entirely on DigService/WashService releasing their
		-- lock on every path that can invalidate it -- including blacking out, which
		-- teleports the player out of the stage without killing them. That list is
		-- enumerated on releaseLock/finish; a lock that is never released is a player
		-- who can never move.
		if DigService.isLocked(player) or WashService.isWashing(player) then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		else
			-- The debug /speed override, when set, wins over training here -- but NOT over
			-- the root above: an override still leaves you planted while locked to a
			-- signal or washing, same as any other speed.
			local override = speedOverrides[player]
			humanoid.WalkSpeed = override or StatResolver.effectiveWalkSpeed(stats, #data.carry, false)

			-- Same deal for /jump. JumpPower is DERIVED from the requested height via
			-- the standard projectile relation (v0 = sqrt(2 * g * h)) rather than a
			-- second unrelated override number, so both properties stay physically
			-- consistent with each other regardless of which one the rig honours.
			local jumpOverride = jumpOverrides[player]
			if jumpOverride then
				humanoid.JumpHeight = jumpOverride
				humanoid.JumpPower = math.sqrt(2 * Workspace.Gravity * jumpOverride)
			else
				humanoid.JumpPower = DEFAULT_JUMP_POWER
				humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
			end
		end
	end
	-- The decay clock. CarryService now EXISTS and is the obvious owner by name — it
	-- deliberately does not take this, and the reason is ordering. Ticker fires in
	-- boot order, CarryService boots after this service (it needs EconomyService),
	-- so moving the tick there would make the emission read three lines below run
	-- against a bag that is one tick stale. That is a radiation change wearing an
	-- inventory change's clothes, and it is not worth making as a side effect.
	--
	-- To move it: put CarryService ahead of ExposureService in the boot ORDER first,
	-- which means breaking its EconomyService dependency. Until someone wants that,
	-- ticking here — where the bag is already being walked once per tick anyway — is
	-- the honest place for it.
	for _, item in data.carry do
		local changedTo = Decay.tick(item, dt, stats.fuseMult)
		if changedTo then
			print(`[decay] {player.Name}: {item.modifier} {item.rarity} -> {Tuning.DECAY_CONDITIONS[changedTo].name}`)
		end
	end

	local carried = Decay.totalEmission(data.carry, stats.fuseMult)
	local reading = Radiation.resolve(ambient, carried, stats)
	-- /immunity: the reading still names the ambient and the bag (the HUD keeps its
	-- numbers), but none of it lands -- nothing accrues, nothing burns, the aura holds.
	if immune[player] then
		reading.net = 0
		reading.excess = 0
		reading.healthBurn = 0
		reading.failing = false
	end

	-- A DETONATED NUKE'S CRATER BURNS HEALTH, and it is folded into the reading rather
	-- than applied beside it so that everything downstream -- regen stopping, the
	-- SURVIVABLE countdown, the threat colour, the white overlay, the "burn" blackout --
	-- treats standing in a crater exactly like aura failure. `failing` is left alone:
	-- that flag means the AURA gave out, and it has not. The aura does not shield this
	-- either; it is the air itself, a second ago, at a few thousand degrees.
	local craterBurn = HazardService.burnAt(root.Position)
	reading.healthBurn += craterBurn
	-- Always taken, even while downed, so a hit that lands on a blackout is dropped
	-- rather than banked into the next life (HazardService.takeHit).
	local blastHit = HazardService.takeHit(player)

	local showering = inShower(root.Position)

	if not state.downed then
		if showering then
			state.exposure = math.max(0, state.exposure - Tuning.SHOWER_FLUSH_RATE * dt)
		else
			state.exposure = math.clamp(state.exposure + reading.net * dt, 0, Tuning.EXPOSURE_CAP)
		end

		if blastHit > 0 then
			state.health = math.max(0, state.health - blastHit)
		end

		if reading.healthBurn > 0 then
			state.health = math.max(0, state.health - reading.healthBurn * dt)
		else
			-- ...and fully at base camp (PLAN §3.5).
			local rate = if stageId == nil then HEALTH_REGEN_PER_SEC * 6 else HEALTH_REGEN_PER_SEC
			state.health = math.min(Tuning.MAX_HEALTH, state.health + rate * dt)
		end

		local function where(): Where
			local camp = if stageId then nil else CampService.campOf(player)
			return {
				stageName = if stageId then Stages.get(stageId).name elseif camp then camp.name else "Base Camp",
				depth = depth,
			}
		end

		if state.health <= 0 then
			-- Down to a detonation -- its hit this tick, or standing in a crater's orb
			-- when the health ran out -- is a "blast" death, and the bag goes off with
			-- you. Aura failure alone is still "burn": radiation, and the bag drops.
			local blasted = blastHit > 0 or craterBurn > 0
			blackout(player, state, if blasted then "blast" else "burn", where())
		elseif state.exposure >= Tuning.EXPOSURE_CAP then
			blackout(player, state, "exposure", where())
		end
	end

	-- THE DISPLAYED COUNTDOWN DOES NOT RECOVER FROM A PARTIAL RETREAT. Left as a
	-- live recomputation, walking a few steps back out of a hot pocket (or into a
	-- shallower part of a depth-graded stage, PLAN's depth pass) would make
	-- SURVIVABLE jump straight back up, because it is just (cap - exposure) / net
	-- at whatever net happens to be RIGHT NOW. That defeats the point of a deep
	-- push costing a real walk home: the number should read as "you are committed
	-- to getting back to safety by roughly here," not "how do I feel this instant."
	--
	-- So it only ever improves for one reason -- reaching genuine safety (net <= 0
	-- and no burn, or an active shower) -- and otherwise ratchets: it can always
	-- drop immediately (things got worse, show that right away), but if the live
	-- number would be BETTER than what's already showing, it ticks down in real
	-- time instead of jumping to match. A player who fully makes it home sees the
	-- pressure actually lift; one who ducks back a few studs into the same stage
	-- does not get to bank that as extra time.
	local liveSurvivable = Radiation.survivableSeconds(reading, state.exposure, state.health)
	local trulySafe = showering or (reading.net <= 0 and reading.healthBurn <= 0)
	local survivable: number
	if trulySafe then
		state.survivableRatchet = nil
		survivable = liveSurvivable
	elseif state.survivableRatchet == nil or liveSurvivable < state.survivableRatchet then
		state.survivableRatchet = liveSurvivable
		survivable = liveSurvivable
	else
		state.survivableRatchet = math.max(0, state.survivableRatchet - dt)
		survivable = state.survivableRatchet
	end

	-- Outside every stage you are in a camp: a site camp's own name if you are standing
	-- in one (Config/Camps), Base Camp everywhere else -- the name the HUD always used.
	local camp = if stageId then nil else CampService.campOf(player)

	stateRemote:FireClient(player, {
		stageId = stageId,
		stageName = if stageId then Stages.get(stageId).name elseif camp then camp.name else "Base Camp",
		campId = if camp then camp.id else nil,
		ambient = ambient,
		depth = depth,
		inShower = showering,

		exposure = state.exposure,
		exposureFrac = Radiation.exposureFraction(state.exposure),
		health = state.health,
		maxHealth = Tuning.MAX_HEALTH,
		downed = state.downed,

		net = reading.net,
		carried = reading.carried,
		excess = reading.excess,
		healthBurn = reading.healthBurn,
		failing = reading.failing,
		-- Standing in a detonated nuke's crater (HazardService). Its burn is already in
		-- healthBurn; this only lets the HUD name the right cause -- "AURA FAILING" and
		-- its white are the aura's alone (PLAN's one colour rule).
		inCrater = craterBurn > 0,

		greed = Radiation.greedFraction(reading, stats),
		survivable = finite(survivable),
		threat = Radiation.dominantThreat(reading, state.exposure, state.health),

		carrying = #data.carry,
		capacity = stats.capacity,
		auraTolerance = stats.auraTolerance,
		gear = data.gear,
	})
end

-- ── API ─────────────────────────────────────────────────────────────

function ExposureService.exposureOf(player: Player): number
	return stateFor(player).exposure
end

function ExposureService.healthOf(player: Player): number
	return stateFor(player).health
end

--- Used by the debug console's /flush, and by anything that grants a rad flush.
function ExposureService.flush(player: Player)
	local state = stateFor(player)
	state.exposure = 0
	state.health = Tuning.MAX_HEALTH
	state.downed = false
	state.survivableRatchet = nil
end

--- Debug console (/speed). A number pins the player's WalkSpeed there until cleared;
--- nil clears it and hands movement back to their trained speed. The dig/wash root still
--- wins over this -- an override does not let you walk while locked to a signal.
function ExposureService.setSpeedOverride(player: Player, walkSpeed: number?)
	speedOverrides[player] = walkSpeed
end

function ExposureService.speedOverrideOf(player: Player): number?
	return speedOverrides[player]
end

--- Debug console (/jump). A number pins the player's JumpHeight there until cleared
--- (JumpPower is derived from it every tick, see the tick loop above); nil clears it
--- and hands jump back to the engine defaults. The dig/wash root still wins over this,
--- same as /speed.
function ExposureService.setJumpOverride(player: Player, jumpHeight: number?)
	jumpOverrides[player] = jumpHeight
end

function ExposureService.jumpOverrideOf(player: Player): number?
	return jumpOverrides[player]
end

--- Debug console (/immunity). While on, radiation (stage + bag) neither builds
--- exposure nor burns health; blasts and craters still do.
function ExposureService.setImmune(player: Player, enabled: boolean)
	immune[player] = if enabled then true else nil
end

function ExposureService.isImmune(player: Player): boolean
	return immune[player] == true
end

function ExposureService.init()
	stateRemote = Net.get("ExposureState")
	blackoutRemote = Net.get("Blackout")
	droppedBagRemote = Net.get("DroppedBag")
end

function ExposureService.start()
	DataService.onLoaded(function(player, _data)
		stateFor(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		speedOverrides[player] = nil
		jumpOverrides[player] = nil
		immune[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		-- Once per interval for the whole server, not once per player per tick.
		cacheAge += dt
		if cacheAge >= CACHE_REFRESH then
			cacheAge = 0
			refreshShowerCache()
		end

		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player, dt)
			if not ok then
				warn(`[rads] tick failed for {player.Name}: {err}`)
			end
		end
	end)
end

return ExposureService
