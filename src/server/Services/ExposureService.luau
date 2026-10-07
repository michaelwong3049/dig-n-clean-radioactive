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
	displayed. The BAG is another matter: however you go down -- radiation, aura
	failure or a blast -- the WHOLE bag drops where you fell, clean nukes and all, for
	ninety seconds, and anyone who has reached Stage 4 (Tuning.STEAL_MIN_STAGE) can
	steal it straight away. Getting back to it first is
	the race. Every take by someone else is reported to the owner by name
	(Net.DroppedBag stolenBy, BagTrackerController's toast). A bomb kill is still the
	sharpest way to go after another player's haul (Services/BombService), and the
	overhead star badge (NameTagController) is how you pick who is worth it. Supply
	crates that are already washed (data.crates) stay with you; they are not nukes.

	THE LABEL OVER THE BAG IS DRAWN BY EACH CLIENT (DroppedBagController), not here, so
	it can reach the owner from anywhere and everyone else only up close. The bag
	carries what it needs as attributes: OwnerId, OwnerName, Items, ExpiresAt, Protected.

	RECOVER BAG (Tuning.BAG_RECOVER_PRODUCT_ID) puts a dropped bag's whole contents back
	in the owner's carry for Robux. Two things keep it from duplicating items or selling
	an empty bag:
	  - ONE TABLE, MOVED ONCE. A bag's items live only in bagContents[bag]. A steal and
	    the purchase grant both take them out of that table, synchronously, so whichever
	    runs first has them and the other finds nothing. The grant never copies.
	  - THE OWNER GETS A HEAD START. For Tuning.BAG_STEAL_GRACE seconds after the drop
	    only the owner may take from it, and pressing Recover HOLDS the bag (no steals,
	    no time-out) until the purchase dialog closes or the receipt lands, capped at
	    Tuning.BAG_RECOVER_HOLD_MAX seconds per bag. The server opens the prompt itself,
	    after the hold is in place, so there is no gap between the two.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Stages = require(Shared.Config.Stages)
local Radiation = require(Shared.Radiation)
local Decay = require(Shared.Decay)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)
local Bag = require(Shared.Bag)

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
-- Read ONLY to tell a base's shower (owner-only) from a camp one. ExhibitService never
-- requires this file, so there is no cycle.
local ExhibitService = require(script.Parent.ExhibitService)
-- Recover Bag's receipt. ProductService requires only DataService and SfxService.
local ProductService = require(script.Parent.ProductService)

local ExposureService = {}

local HEALTH_REGEN_PER_SEC = 2.5 -- PLAN §3.5: slowly out of radiation...
local BAG_LIFETIME = 90 -- §3.1, exactly ninety seconds
local DEFAULT_SHOWER_RADIUS = 10

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
	survivableBurning: boolean?, -- whether the ratchet above was set by a burn clock
}

local states: { [Player]: State } = {}
local bagContents: { [Instance]: { any } } = {}
-- Who has already taken from each dropped bag that was not theirs, so the Thief
-- mastery's `bagsStolen` counts a bag once however many trips it takes to empty.
local bagThieves: { [Instance]: { [Player]: boolean } } = {}
-- Per dropped bag: when it dropped (for the steal grace) and its Recover hold, if one
-- is running -- `holdStart` set while the owner's purchase dialog is open, `holdUsed`
-- the seconds already spent of Tuning.BAG_RECOVER_HOLD_MAX.
type BagMeta = { droppedAt: number, holdStart: number?, holdUsed: number }
local bagMeta: { [Instance]: BagMeta } = {}
-- The bag each player's open Recover purchase is for.
local pendingRecover: { [Player]: Instance } = {}

-- ── Kills (the Bomber mastery, Config/Masteries) ─────────────────────────────
--
-- A death within a few seconds of a dropped bomb hurting you is that bomber's kill
-- (HazardService.killerOf). Downing the same player again inside KILL_REPEAT_SECONDS
-- does not count twice, so two friends cannot trade bombs to farm the mastery.
local KILL_REPEAT_SECONDS = 5 * 60
local lastKillOf: { [Player]: { [number]: number } } = {}

local function creditKill(victim: Player)
	local killer = HazardService.killerOf(victim)
	if killer == nil then
		return
	end
	local data = DataService.data(killer)
	if data == nil then
		return
	end
	local mine = lastKillOf[killer]
	if mine == nil then
		mine = {}
		lastKillOf[killer] = mine
	end
	local now = os.clock()
	local previous = mine[victim.UserId]
	if previous and now - previous < KILL_REPEAT_SECONDS then
		print(`[kill] {killer.Name} downed {victim.Name} again inside {KILL_REPEAT_SECONDS}s; not counted`)
		return
	end
	mine[victim.UserId] = now
	data.stats.kills = (data.stats.kills or 0) + 1
	print(`[kill] {killer.Name} blew up {victim.Name} ({data.stats.kills} kills)`)
end

--- A player went down (a blackout or a real character death): count it on their own
--- Settings > Stats page, then credit whoever bombed them.
local function noteDeath(victim: Player)
	local data = DataService.data(victim)
	if data then
		data.stats.deaths = (data.stats.deaths or 0) + 1
	end
	creditKill(victim)
end

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
local noticeRemote: any = nil

local INFINITE = -1
local function finite(n: number): number
	return if n == math.huge or n ~= n then INFINITE else n
end

--- Max health grows with the equipped aura tier (Tuning.maxHealthFor), x2 with the
--- 2x Health pass (StatResolver healthMult).
local function maxHealthOf(player: Player): number
	local data = DataService.data(player)
	local base = Tuning.maxHealthFor(data and data.gear and data.gear.aura)
	return if data then base * StatResolver.get(data).healthMult else base
end

local function stateFor(player: Player): State
	local existing = states[player]
	if existing then
		return existing
	end
	local fresh: State = { exposure = 0, health = maxHealthOf(player), downed = false, survivableRatchet = nil }
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
--
-- The refresh reads Kit's Shower tag rather than walking Workspace: even once per
-- 2 s, a full walk of ~177k instances to find 7 showers stalled the server for
-- 45-90 ms each time — a frame hitch every 2 seconds. The attribute stays the
-- source of truth; the tag is only the index (same as StationService).
local SHOWER_TAG = "Shower"
local showerCache: { { position: Vector3, radius: number, plot: number?, heals: boolean } } = {}
local cacheAge = math.huge
local CACHE_REFRESH = 2

local function refreshShowerCache()
	table.clear(showerCache)
	for _, descendant in CollectionService:GetTagged(SHOWER_TAG) do
		if
			descendant:IsA("BasePart")
			and descendant:GetAttribute("Shower") == true
			and descendant:IsDescendantOf(Workspace)
		then
			table.insert(showerCache, {
				position = descendant.Position,
				radius = (descendant:GetAttribute("Radius") :: number?) or DEFAULT_SHOWER_RADIUS,
				-- A base's cleansing station flushes its owner only; camp showers are on no plot.
				plot = ExhibitService.plotIndexOf(descendant),
				-- Base Camp's heal pads (build/HealPads) are showers that also heal.
				heals = descendant:GetAttribute("HealPad") == true,
			})
		end
	end
end

--- (showering, healing): in any shower you may use, and whether one of them is a
--- heal pad.
local function inShower(player: Player, position: Vector3): (boolean, boolean)
	local showering, healing = false, false
	for _, shower in showerCache do
		if
			(shower.position - position).Magnitude <= shower.radius
			and ExhibitService.ownsPlotStation(player, shower.plot)
		then
			showering = true
			healing = healing or shower.heals
		end
	end
	return showering, healing
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

local function itemsText(n: number): string
	return if n == 1 then "1 item" else `{n} items`
end

--- Whether the owner's Recover hold is still running on this bag.
local function isHeld(bag: Instance): boolean
	local meta = bagMeta[bag]
	if meta == nil or meta.holdStart == nil then
		return false
	end
	return os.clock() - meta.holdStart < Tuning.BAG_RECOVER_HOLD_MAX - meta.holdUsed
end

--- Only the owner may take from it right now: the steal grace, or a Recover hold.
local function isProtected(bag: Instance): boolean
	local meta = bagMeta[bag]
	if meta == nil then
		return false
	end
	return os.clock() - meta.droppedAt < Tuning.BAG_STEAL_GRACE or isHeld(bag)
end

--- Mirror isProtected onto the bag for the other clients' prompt wording.
local function refreshProtected(bag: Instance)
	if bag.Parent ~= nil then
		bag:SetAttribute("Protected", isProtected(bag))
	end
end

--- End a Recover hold, banking the time it used against the per-bag cap.
local function releaseHold(bag: Instance)
	local meta = bagMeta[bag]
	if meta and meta.holdStart then
		meta.holdUsed = math.min(Tuning.BAG_RECOVER_HOLD_MAX, meta.holdUsed + (os.clock() - meta.holdStart))
		meta.holdStart = nil
	end
	refreshProtected(bag)
end

--- Time a bag out at its deadline -- unless a Recover hold is running, in which case
--- look again when the hold can no longer be (the dialog closing releases it sooner).
local function expireLater(bag: Instance, delay: number)
	task.delay(delay, function()
		if bag.Parent == nil or bagContents[bag] == nil then
			return
		end
		local meta = bagMeta[bag]
		if isHeld(bag) and meta and meta.holdStart then
			local left = Tuning.BAG_RECOVER_HOLD_MAX - meta.holdUsed - (os.clock() - meta.holdStart)
			expireLater(bag, math.max(left, 0) + 0.1)
			return
		end
		bag:Destroy()
	end)
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

	-- The owner's head start (header, "RECOVER BAG"): nobody else for the first few
	-- seconds, or while the owner's Recover purchase is open.
	if bag:GetAttribute("OwnerId") ~= taker.UserId and isProtected(bag) then
		noticeRemote:FireClient(taker, "this bag is protected for a moment")
		return
	end

	-- Stealing is for players who have made it to Stage 4 (Tuning.STEAL_MIN_STAGE);
	-- your own bag you can always recover. Read live as well as from the save, because
	-- deepestStage only catches up on MasteryService's next look.
	if bag:GetAttribute("OwnerId") ~= taker.UserId then
		local deepest = math.max(tonumber(data.stats.deepestStage) or 1, StageService.stageOf(taker) or 1)
		if deepest < Tuning.STEAL_MIN_STAGE then
			noticeRemote:FireClient(taker, `reach Stage {Tuning.STEAL_MIN_STAGE} to steal bags`)
			return
		end
	end

	local stats = StatResolver.get(data)
	local taken = 0
	while #contents > 0 and Bag.used(data) < stats.capacity do
		table.insert(data.carry, table.remove(contents, 1))
		taken += 1
	end

	if taken == 0 then
		noticeRemote:FireClient(taker, "bag full — sell at trader or store in locker")
		return
	end

	local stolen = bag:GetAttribute("OwnerId") ~= taker.UserId
	if stolen then
		local thieves = bagThieves[bag]
		if thieves == nil then
			thieves = {}
			bagThieves[bag] = thieves
		end
		if not thieves[taker] then
			thieves[taker] = true
			data.stats.bagsStolen = (data.stats.bagsStolen or 0) + 1
		end
	end
	print(`[bag] {taker.Name} {if stolen then "stole" else "recovered"} {taken} item(s); {#contents} left in the bag`)

	-- Keep the label honest. Carry capacity means a full bag usually CANNOT be
	-- emptied in one go, so "12 items" hovering over a bag holding 8 is an outright
	-- lie at exactly the moment the player is deciding whether to risk another trip
	-- out to it. The label is the clients' (DroppedBagController); it reads Items.
	bag:SetAttribute("Items", #contents)
	local prompt = bag:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ObjectText = itemsText(#contents)
	end

	-- A theft is told to the owner by name, even the take that empties the bag (it
	-- goes out before Destroying's "gone"). The owner's own takes need no news beyond
	-- the count; Destroying tells them when the bag is gone.
	if stolen then
		tellOwner(bag, { items = #contents, stolenBy = taker.DisplayName, stolenCount = taken })
	elseif #contents > 0 then
		tellOwner(bag, { items = #contents })
	end

	if #contents == 0 then
		bagContents[bag] = nil
		bag:Destroy()
	end
end

local SACK_CANVAS = Color3.fromHex("5E7A2E")
local SACK_SHADE = Color3.fromHex("46601F")
local SACK_TIE = Color3.fromHex("F2C12E")
local BAG_MAX_SCALE = 1.8

--- Where the bag's root sits: its base on whatever is under the fall point, so the
--- sack slumps on the ground instead of floating at hip height.
local function restOnGround(position: Vector3, character: Model?, scale: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if character then { character } else {}
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	local groundY = if hit then hit.Position.Y else position.Y - 3
	return Vector3.new(position.X, groundY + 1.2 * scale, position.Z)
end

local function sackPart(root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = root.CFrame * offset
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Color = color
	part.Material = Enum.Material.Fabric
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = root
	return part
end

--- An ellipsoid: round Shapes force circles, a Sphere SpecialMesh does not.
local function sackBlob(root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3): Part
	local part = sackPart(root, name, size, offset, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

--- A slumped canvas sack: squat body, pinched neck tied off with a yellow
--- cord and a flared tuft.
local function buildSack(root: BasePart, scale: number)
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * scale
	end
	-- A random lean and turn so two bags in one spot don't look stamped.
	local lean = CFrame.Angles(math.rad(math.random(-8, 8)), math.rad(math.random(0, 359)), math.rad(math.random(-8, 8)))
	local function at(x: number, y: number, z: number): CFrame
		return lean * CFrame.new(x * scale, y * scale, z * scale)
	end

	sackBlob(root, "Body", v(2.3, 1.7, 2.1), at(0, -0.35, 0), SACK_CANVAS)
	sackBlob(root, "Bulge", v(1.5, 1.1, 1.3), at(0.45, -0.7, 0.35), SACK_SHADE)
	sackBlob(root, "Shoulder", v(1.5, 0.9, 1.4), at(0, 0.3, 0), SACK_CANVAS)
	sackPart(root, "Neck", v(0.7, 0.5, 0.5), at(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90)), SACK_SHADE).Shape =
		Enum.PartType.Cylinder
	local tie = sackPart(root, "Tie", v(0.18, 0.62, 0.62), at(0, 0.72, 0) * CFrame.Angles(0, 0, math.rad(90)), SACK_TIE)
	tie.Shape = Enum.PartType.Cylinder
	tie.Material = Enum.Material.SmoothPlastic
	sackBlob(root, "Tuft", v(0.9, 0.45, 0.8), at(0.05, 1.05, 0) * CFrame.Angles(0, 0, math.rad(12)), SACK_CANVAS)
	sackPart(root, "TieEnd", v(0.1, 0.5, 0.1), at(0.28, 0.5, 0.22) * CFrame.Angles(0, 0, math.rad(-25)), SACK_TIE).Material =
		Enum.Material.SmoothPlastic
end

--- Owed the one-time "upgrade your aura" popup: DeconService's "tutorialSeen" allowlist.
local function auraTipOwed(player: Player): boolean
	local data = DataService.data(player)
	return data ~= nil and table.find(data.tutorialsSeen or {}, "aura") == nil
end

--- Drop the WHOLE bag where the player fell, for anyone to take (header).
local function dropBag(player: Player, data: any, position: Vector3): number
	-- Every death drops everything, washed nukes too: going down out there is how you
	-- lose a haul to someone else. (It was the dirty part only, owner-only, on a
	-- radiation death -- PLAN §3.1 -- until bags became stealable whatever the cause.)
	-- Emptied in place: other services hold this table.
	local dropped = table.clone(data.carry)
	table.clear(data.carry)

	if #dropped == 0 then
		return 0
	end

	-- Heavier losses make a bigger sack: +5% per item from 0.85x, capped at 1.8x
	-- (19+ items), so a full 34-slot bag stays grabbable and doesn't bury the path.
	local scale = math.min(0.85 + 0.05 * #dropped, BAG_MAX_SCALE)

	-- The root is an invisible hitbox that carries the light, label and prompt; the
	-- sack itself is dressing parented under it, so Debris/Destroy take the lot.
	local bag = Instance.new("Part")
	bag.Name = `DroppedBag_{player.Name}`
	bag.Size = Vector3.new(2.2, 2.4, 2.2) * scale
	bag.Position = restOnGround(position, player.Character, scale)
	bag.Anchored = true
	bag.CanCollide = false
	bag.Transparency = 1
	bag.Parent = Workspace
	buildSack(bag, scale)

	-- Matte since the de-neon pass; a low locator light stays, because this is a
	-- recoverable stash sitting out in the world, not decoration -- you need to be able
	-- to spot it to go back for it. Kept dim (was 2.2) so it marks the bag without
	-- lighting the ground around it.
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("8FE04A")
	light.Range = 14
	light.Brightness = 0.8
	light.Parent = bag

	-- No label here: each client draws its own (DroppedBagController) off the
	-- attributes set below, so it can reach the owner from anywhere and everyone else
	-- only up close. That controller also words this prompt per viewer (Recover/Steal).
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal bag"
	prompt.ObjectText = itemsText(#dropped)
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bag
	prompt.Triggered:Connect(function(taker: Player)
		giveBagTo(bag, taker)
	end)

	bagContents[bag] = dropped
	bagMeta[bag] = { droppedAt = os.clock(), holdUsed = 0 }
	bag:SetAttribute("Protected", true)
	task.delay(Tuning.BAG_STEAL_GRACE + 0.05, refreshProtected, bag)
	expireLater(bag, BAG_LIFETIME)

	-- The owner's "get it back" tracker (BagTrackerController). Sent as a position and
	-- a server-clock deadline rather than the part itself: the bag lies where you fell
	-- and you have just been sent to camp, so the part may not be streamed in on your
	-- client at all. Emptied or timed out, it goes the same way -- Destroying.
	local expiresAt = Workspace:GetServerTimeNow() + BAG_LIFETIME
	bag:SetAttribute("OwnerId", player.UserId)
	bag:SetAttribute("OwnerName", player.DisplayName)
	bag:SetAttribute("Items", #dropped)
	bag:SetAttribute("ExpiresAt", expiresAt)
	bag:SetAttribute("BagId", HttpService:GenerateGUID(false))
	CollectionService:AddTag(bag, "DroppedBag")
	tellOwner(bag, {
		position = bag.Position,
		expiresAt = expiresAt,
		items = #dropped,
	})
	bag.Destroying:Connect(function()
		bagContents[bag] = nil
		bagThieves[bag] = nil
		bagMeta[bag] = nil
		for who, pending in pendingRecover do
			if pending == bag then
				pendingRecover[who] = nil
			end
		end
		tellOwner(bag, { gone = true })
	end)

	return #dropped
end

-- ── Recover Bag (Robux) ────────────────────────────────────────────────

--- The owner pressed Recover on the bag with this BagId: hold it, then open the
--- purchase prompt (header, "RECOVER BAG").
local function requestRecover(player: Player, bagId: any)
	if type(bagId) ~= "string" or Tuning.BAG_RECOVER_PRODUCT_ID == 0 then
		return
	end
	local bag: Instance? = nil
	for candidate, contents in bagContents do
		if candidate:GetAttribute("BagId") == bagId and #contents > 0 then
			bag = candidate
			break
		end
	end
	if bag == nil or bag:GetAttribute("OwnerId") ~= player.UserId then
		return
	end

	-- One open purchase per player: switching to another bag lets the first one go.
	local previous = pendingRecover[player]
	if previous and previous ~= bag then
		releaseHold(previous)
	end
	pendingRecover[player] = bag

	local meta = bagMeta[bag]
	if meta and meta.holdStart == nil and meta.holdUsed < Tuning.BAG_RECOVER_HOLD_MAX then
		meta.holdStart = os.clock()
		refreshProtected(bag)
		-- Run out of hold with the dialog still up: thieves are let back in.
		task.delay(Tuning.BAG_RECOVER_HOLD_MAX - meta.holdUsed + 0.05, refreshProtected, bag)
	end
	MarketplaceService:PromptProductPurchase(player, Tuning.BAG_RECOVER_PRODUCT_ID)
end

--- ProductService grant: every item left in the player's bag goes back into their carry,
--- past capacity if need be (they paid for all of it). Mutates and destroys only, never
--- yields, so no steal can land between taking the items and recording the receipt.
local function grantRecover(player: Player, data: any)
	local bag = pendingRecover[player]
	pendingRecover[player] = nil
	if bag == nil or bagContents[bag] == nil or #bagContents[bag] == 0 then
		-- Bought from a bag that has since gone: the owner's newest one still lying out.
		bag = nil
		local newestAt = -math.huge
		for candidate, contents in bagContents do
			local expiresAt = candidate:GetAttribute("ExpiresAt")
			if candidate:GetAttribute("OwnerId") == player.UserId and #contents > 0
				and type(expiresAt) == "number" and expiresAt > newestAt then
				bag, newestAt = candidate, expiresAt
			end
		end
	end

	if bag == nil then
		warn(`[bag] {player.Name} bought Recover Bag with no bag left to recover`)
		task.defer(function()
			if player.Parent then
				noticeRemote:FireClient(player, "your bag was already gone", "info")
			end
		end)
		return
	end

	local contents = bagContents[bag] :: { any }
	-- Out of the table before anything else can see it: this IS the anti-dupe.
	bagContents[bag] = nil
	for _, item in contents do
		table.insert(data.carry, item)
	end
	local count = #contents
	table.clear(contents)
	print(`[bag] {player.Name} recovered {count} item(s) with Robux`)
	bag:Destroy()
	task.defer(function()
		if player.Parent then
			noticeRemote:FireClient(player, `bag recovered: {itemsText(count)} back in your pack`, "success")
		end
	end)
end

-- ── Blackout ───────────────────────────────────────────────────────────

--- Where a blacked-out player wakes up — and, since the top-of-screen warp bar,
--- where "SHOPS" drops you too (WarpService). It is the one shared answer to "where
--- do you land when you leave the field": the RespawnAnchor in the middle of the plaza,
--- or rather a point on the ring round it (the Trader kiosk stands on the anchor itself).
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
		-- A ring anchor (Hub's, round the Trader kiosk that stands on it): land at one
		-- of its points, picked at random, facing the middle.
		local radius = anchor:GetAttribute("RingRadius")
		if type(radius) == "number" and radius > 0 then
			local points = anchor:GetAttribute("RingPoints")
			local count = if type(points) == "number" and points >= 1 then math.floor(points) else 4
			local angle = math.random(0, count - 1) * (2 * math.pi / count)
			local centre = anchor.Position + Vector3.new(0, 4, 0)
			local at = centre + Vector3.new(math.sin(angle), 0, math.cos(angle)) * radius
			return CFrame.lookAt(at, centre)
		end
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
	noteDeath(player)

	local data = DataService.data(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	-- Any death drops the whole bag for anyone to steal (header).
	local lost = 0
	if data and root and root:IsA("BasePart") then
		lost = dropBag(player, data, root.Position)
	end

	state.exposure = 0
	state.health = maxHealthOf(player)
	state.survivableRatchet = nil

	-- Wake up at your own base (its PlotSpawn); the plaza only if you have no plot.
	if root and root:IsA("BasePart") then
		local spawn = ExhibitService.plotSpawn(player)
		root.CFrame = if spawn then spawn.CFrame + Vector3.new(0, 4, 0) else ExposureService.baseCampCFrame()
	end

	blackoutRemote:FireClient(player, {
		cause = cause,
		itemsDropped = lost,
		looted = true,
		stageName = where.stageName,
		depth = where.depth,
	})
	print(`[rads] {player.Name} blacked out ({cause}) — dropped {lost} item(s)`)

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
			-- The pin is the BASE speed: the worn aura's bonus still rides on top of it, the
			-- same as it does on trained speed, so /speed 40 in a +6% aura walks at 42.4.
			humanoid.WalkSpeed = if override then override * StatResolver.walkBonus(stats) else StatResolver.effectiveWalkSpeed(stats, #data.carry, false, data.walkCap)

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

	-- BAG RADIATION IS RETIRED: what you carry no longer adds rads. Only the stage
	-- does. Decay still ticks above (conditions/fuses are their own mechanic); the bag
	-- just stops feeding the exposure meter. Radiation.resolve keeps its `carried`
	-- input as pure math, so passing 0 here is the whole switch.
	-- The aura's damage comes off the zone survival curve (Radiation.zoneSurvival):
	-- where you stand in the stage against what your aura is rated for. Camps have no
	-- zone and take none.
	local zone: Radiation.Zone? = if stageId
		then {
			stageId = stageId,
			depthFrac = StageService.depthFracFor(player),
			auraTier = data.gear and data.gear.aura or 1,
			maxHealth = maxHealthOf(player),
		}
		else nil
	local reading = Radiation.resolve(ambient, 0, stats, zone)
	-- The Deep Diver mastery (Config/Masteries): less health off the aura wearing and
	-- failing. Scaled here, on the reading itself, so the HUD's burn colour and the
	-- SURVIVABLE countdown read the health that is really lost.
	reading.healthBurn *= stats.radDamageMult
	reading.drain *= stats.radDamageMult
	-- /immunity: the reading still names the ambient and the bag (the HUD keeps its
	-- numbers), but none of it lands -- nothing accrues, nothing burns, the aura holds.
	if immune[player] then
		reading.net = 0
		reading.excess = 0
		reading.healthBurn = 0
		reading.drain = 0
		reading.over = 0
		reading.failing = false
	end

	-- A DETONATED NUKE'S CRATER BURNS HEALTH, and it is folded into the reading rather
	-- than applied beside it so that everything downstream -- regen stopping, the
	-- SURVIVABLE countdown, the threat colour, the white overlay, the "burn" blackout --
	-- treats standing in a crater exactly like aura failure. `failing` is left alone:
	-- that flag means the AURA gave out, and it has not. The aura does not shield this
	-- either; it is the air itself, a second ago, at a few thousand degrees.
	local craterBurn = HazardService.burnAt(root.Position, stageId ~= nil, player)
	reading.healthBurn += craterBurn
	-- ...and it is fallout as well as heat: the orb fills the meter fast on top of
	-- whatever the stage is doing (Tuning.CRATER_RADS_PER_BURN). Kept beside `net`
	-- rather than in it so the SURVIVABLE clock stays a stage-and-bag number; /immunity
	-- blocks it like any other radiation, the orb's health burn it does not.
	local craterRads = if immune[player]
		then 0
		else math.min(craterBurn * Tuning.CRATER_RADS_PER_BURN, Tuning.CRATER_RADS_MAX)
	-- Always taken, even while downed, so a hit that lands on a blackout is dropped
	-- rather than banked into the next life (HazardService.takeHit).
	local blastHit = HazardService.takeHit(player)

	local showering, healing = inShower(player, root.Position)
	local sickDrain = 0

	if not state.downed then
		if showering then
			state.exposure = math.max(0, state.exposure - Tuning.SHOWER_FLUSH_RATE * dt)
		else
			state.exposure = math.clamp(state.exposure + (reading.net + craterRads) * dt, 0, Tuning.EXPOSURE_CAP)
		end

		if blastHit > 0 then
			state.health = math.max(0, state.health - blastHit)
		end

		-- RADIATION SICKNESS: out in a stage, a high meter stops regen (50%), drains
		-- health (80%+), and drains it heavily when full (100%) -- a full meter is no
		-- longer an instant blackout. See Tuning's sickness block for why camps are exempt.
		local frac = Radiation.exposureFraction(state.exposure)
		local sick = stageId ~= nil and not showering and not immune[player]
		sickDrain = if sick then Radiation.sicknessDrain(frac, maxHealthOf(player)) * stats.radDamageMult else 0
		local noRegen = sick and frac >= Tuning.SICKNESS_NO_REGEN

		local hpLoss = reading.healthBurn + reading.drain + sickDrain
		if hpLoss > 0 then
			state.health = math.max(0, state.health - hpLoss * dt)
		elseif not noRegen then
			-- ...and fully at base camp (PLAN §3.5).
			-- A heal pad tops you up in a couple of seconds (Tuning.HEAL_PAD_HEAL_FRAC).
			local rate = if healing
				then maxHealthOf(player) * Tuning.HEAL_PAD_HEAL_FRAC
				elseif stageId == nil then HEALTH_REGEN_PER_SEC * 6
				else HEALTH_REGEN_PER_SEC
			state.health = math.min(maxHealthOf(player), state.health + rate * dt)
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
			-- when the health ran out -- is a "blast" death, and the whole bag drops for
			-- anyone. Aura failure alone is still "burn": radiation, owner-only drop.
			-- Sickness with the aura holding is the meter's doing: an exposure death.
			local blasted = blastHit > 0 or craterBurn > 0
			local reason = if blasted then "blast" elseif reading.failing then "burn" else "exposure"
			blackout(player, state, reason, where())
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
	-- Sickness counts toward the clock (it is HP you are really losing) without being
	-- folded into reading.healthBurn, which the HUD reads as "your aura is failing".
	local liveSurvivable = Radiation.survivableSeconds(reading, state.exposure, state.health)
	if sickDrain > 0 then
		liveSurvivable = math.min(liveSurvivable, state.health / (reading.healthBurn + reading.drain + sickDrain))
	end
	-- In a camp the sickness never lands, so a filling meter is no clock there: only
	-- a burn (a crater's orb) can count you down.
	if stageId == nil then
		liveSurvivable = if reading.healthBurn > 1e-6 then state.health / reading.healthBurn else math.huge
	end
	local trulySafe = showering or (reading.net <= 0 and reading.healthBurn <= 0 and reading.drain <= 0 and sickDrain <= 0)
	-- The ratchet only holds within ONE kind of clock. A burn clock (seconds of HP) and
	-- an exposure clock (seconds of meter) are different numbers: stepping out of the
	-- burn left the old burn ratchet ticking down to a SURVIVABLE 0:00 that never killed
	-- anyone. Burn starting or stopping restarts the clock from the live value.
	local burningNow = reading.healthBurn > 0
	local survivable: number
	if trulySafe or burningNow ~= state.survivableBurning then
		state.survivableRatchet = if trulySafe then nil else liveSurvivable
		state.survivableBurning = burningNow
		survivable = liveSurvivable
	elseif state.survivableRatchet == nil or liveSurvivable < state.survivableRatchet then
		state.survivableRatchet = liveSurvivable
		survivable = liveSurvivable
	else
		state.survivableRatchet = math.max(0, state.survivableRatchet - dt)
		-- Run out while still standing means the clock was wrong, not that you are
		-- dead: fall back to the honest live number instead of sitting on 0:00.
		if state.survivableRatchet <= 0 then
			state.survivableRatchet = liveSurvivable
		end
		survivable = state.survivableRatchet
	end

	-- Outside every stage you are in a camp: a site camp's own name if you are standing
	-- in one (Config/Camps), Base Camp everywhere else -- the name the HUD always used.
	local camp = if stageId then nil else CampService.campOf(player)

	-- THE OVERHEAD HP BAR (NameTagController): health is server state sent only to its
	-- owner, so publish a whole-number copy on the Player for every other client to
	-- read. Rounded so regen's fractions don't replicate every tick.
	player:SetAttribute("Health", math.ceil(state.health))
	player:SetAttribute("MaxHealth", maxHealthOf(player))

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
		maxHealth = maxHealthOf(player),
		downed = state.downed,

		-- The meter's fill rate as the HUD's ▲ arrows read it, a crater's fallout included.
		net = reading.net + craterRads,
		carried = reading.carried,
		excess = reading.excess,
		healthBurn = reading.healthBurn,
		-- The failing aura's HP/sec alone (the crater is folded into healthBurn).
		auraBurn = reading.healthBurn - craterBurn,
		-- HP/sec of rated-aura wear: the aura holding, but wearing down (green).
		zoneDrain = reading.drain,
		-- 0..1, how far out of its depth the aura is (Radiation.resolve).
		over = reading.over,
		failing = reading.failing,
		-- Owed the one-time "upgrade your aura" popup (client/AuraTipController)?
		auraTip = auraTipOwed(player),
		-- Standing in a detonated nuke's crater (HazardService). Its burn is already in
		-- healthBurn; this only lets the HUD name the right cause -- "AURA FAILING" and
		-- its white are the aura's alone (PLAN's one colour rule).
		inCrater = craterBurn > 0,
		-- HP/sec lost to radiation sickness right now (0 below 80%, or in camp).
		sickness = sickDrain,

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
	state.health = maxHealthOf(player)
	state.downed = false
	state.survivableRatchet = nil
end

--- Buying an aura: health straight to the new aura's max (rads untouched). A downed
--- player stays downed.
function ExposureService.healFull(player: Player)
	local state = stateFor(player)
	if not state.downed then
		state.health = maxHealthOf(player)
	end
end

--- Debug console (/speed). A number pins the player's WalkSpeed there until cleared;
--- nil clears it and hands movement back to their trained speed. The dig/wash root still
--- wins over this -- an override does not let you walk while locked to a signal.
function ExposureService.setSpeedOverride(player: Player, walkSpeed: number?)
	speedOverrides[player] = walkSpeed
	-- The Walk Speed badge shows the override, so resend it now rather than at the next
	-- training tick. Lazy: TreadmillService is not otherwise a dependency of this file.
	require(script.Parent.TreadmillService).refresh(player)
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
	noticeRemote = Net.get("Notice")
	-- In init, not start, so no receipt can land before this is registered.
	ProductService.register(Tuning.BAG_RECOVER_PRODUCT_ID, grantRecover)
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
		lastKillOf[player] = nil
		local pending = pendingRecover[player]
		pendingRecover[player] = nil
		if pending then
			releaseHold(pending)
		end
		for _, thieves in bagThieves do
			thieves[player] = nil
		end
	end)

	-- Resetting (or any real character death) in a stage drops the bag too. Blackout
	-- never kills the character, so this only fires for deaths it did not already handle.
	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid == nil or not humanoid:IsA("Humanoid") then
			return
		end
		humanoid.Died:Connect(function()
			local data = DataService.data(player)
			local root = character:FindFirstChild("HumanoidRootPart")
			noteDeath(player)
			if data and root and root:IsA("BasePart") and StageService.stageOf(player) ~= nil then
				local lost = dropBag(player, data, root.Position)
				print(`[rads] {player.Name} died in a stage — dropped {lost} item(s)`)
			end
		end)
	end
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	Net.get("RecoverBag").OnServerEvent:Connect(requestRecover)
	-- Dialog closed without buying: let the bag go. Bought: keep holding until the
	-- receipt's grant takes it (it may land either side of this).
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if productId ~= Tuning.BAG_RECOVER_PRODUCT_ID or purchased then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		local bag = player and pendingRecover[player]
		if player and bag then
			pendingRecover[player] = nil
			releaseHold(bag)
		end
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
