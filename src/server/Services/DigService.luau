--!strict
--[[
	DigService.lua — the buried signal field, and the two verbs on top of it.

	THE REVEAL — this is the mechanic. Read it before changing anything below.
	A detector has a RADIUS. Every buried signal inside that radius shallow enough for
	the detector's `depth` surfaces an AURA at its exact spot: a glow standing up out of
	the ground. You walk to the glow and haul it out. There is no direction hint and no
	hot/cold needle any more — the ground tells you where the thing is, and your
	detector decides how much ground is talking.

	WHAT YOU DIG UP IS A PER-PLAYER ROLL. A signal spawns with a default identity (one
	weighted pick off Config/Items, no luck) that also sets how deep it is buried. The
	first time a signal enters a given player's radar, if their detector has any luck
	(tier 2+), it is re-rolled for them — same weighted table, Rare+ weights boosted by
	Config/Items.luckBias — and cached on the signal under their UserId. So two players
	in one glow can read different rarities; that is the detector, not a bug.

	WHAT CROSSES THE BOUNDARY, AND WHY IT CHANGED (ARCHITECTURE.md, server/client).
	This file used to send an angle and a strength and nothing else, because the whole
	field had to stay secret. Under the reveal it cannot: auras are real parts in
	Workspace, so every client can already read where they are. The rule is therefore
	scoped rather than absolute —

	    positions INSIDE YOUR OWN REVEAL RADIUS may cross. The FIELD never does.

	The payload carries offsets RELATIVE TO THE PLAYER, never world coordinates, and
	never anything outside the radius. An exploiter reading it gets what an honest
	player is already looking at. The other forty-odd buried signals in the stage stay
	exactly as invisible as they were, and that is the property actually worth
	defending: a dig game that replicates the whole field has an ESP script written
	for it inside a week, and at that point the rarity economy — which is the entire
	product — is dead.

	AURAS ARE PUBLIC. Everyone sees every aura, not only whoever revealed it (see
	Config/Tuning, "the reveal", for the cost of that call). The part that matters
	here: revealing is not the same as being allowed to take it. The gates below run
	per-player against whoever is pulling, so a Bent Coil can stand in an Oracle's
	glow and be told, in as many words, that it cannot lock on.

	The client also never names what it wants to dig. It sends "I clicked" or "I want to
	lock on"; the server decides which signal that means, based on where the player
	actually is.

	EXTRACTION IS A HAUL, NOT A DIG, AND IT IS TWO BEATS, NOT ONE. You drop a magnet and
	pull the thing up through the soil.

	  1. TAP to LOCK ON. One press commits you to one buried item. The character is
	     ROOTED and a panel takes the screen: this is the moment you decide that this
	     particular signal is worth standing still for.
	  2. MASH to haul. Every click is a YANK that lurches it upward; the soil drags it
	     back down continuously in between. Click faster than the drag and it breaks the
	     surface, stop clicking and it sinks.

	What survives out here is metal and whatever the fallout soaked into, so the magnet
	is the tool.

	THE LOCK IS THE DANGEROUS PART OF THIS FILE, because it roots the player. A rooted
	player who cannot release is stuck in the world with no way out but rejoining, so
	releaseLock is called from SEVEN places and every one of them is deliberate — see
	the list on releaseLock itself. Adding a new way for a lock to become invalid means
	adding a release with it.

	THIS USED TO BE A HOLD, and the change cost something worth writing down. Under the
	hold, the client sent a boolean and the SERVER integrated it against real elapsed
	time, which made the pull exploit-proof for free -- a spoofed client could hold the
	button down, and holding the button down is what an honest player does anyway. A
	per-click verb gives that property up: the client now drives the clock. The ceiling
	has to be re-imposed by hand, and it is, in the token bucket below. Read the note
	there before touching any of it.

	THREE GATES, all from Gear.lua, all enforced here:
	  detector.radius    — how much ground reveals itself around you. This IS the
	                       search game now, which is why Gear's curve is flat.
	  detector.depth     — deeper items are rarer (at baseline), and a weak detector
	                       cannot see them. This is the only rarity-correlated gate
	                       left now that maxRarity is gone.
	  magnet.maxGrip     — you can find ground your magnet cannot rip anything out of.
	                       This one is deliberately NOT an error message: an under-rated
	                       magnet lifts the item partway and stalls, so the player watches
	                       it strain three feet down and cannot have it.

	detector.luck is NOT a gate — it bends the per-player roll toward Rare+ (see the
	note above and Config/Items). detector.clarity gates only what the PING tells you.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Stages = require(Shared.Config.Stages)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local ItemModels = require(Shared.ItemModels)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local SignalAura = require(script.Parent.Parent.build.SignalAura)

local DataService = require(script.Parent.DataService)
local StageService = require(script.Parent.StageService)

local DigService = {}


-- ── Field tuning ────────────────────────────────────────────────────────────────

-- Moved into Config/Tuning so Spec can check burial depth against the stage plate
-- thickness that has to contain it. Aliased so the call sites below are unchanged.
local SIGNALS_PER_STAGE = Tuning.SIGNALS_PER_STAGE
local DIG_RADIUS = Tuning.DIG_RADIUS
local DEPTH_BASE = Tuning.DIG_DEPTH_BASE
local DEPTH_PER_RARITY = Tuning.DIG_DEPTH_PER_RARITY
local DEPTH_JITTER = Tuning.DIG_DEPTH_JITTER
local STRAIN_CEILING = 0.25 -- how far an under-rated magnet gets before it stalls

-- The mash. All five live in Config/Tuning -- Spec asserts on the click-rate curve
-- they produce, and it cannot reach a local. SLIP_RATE went with the hold: the sink
-- is no longer a punishment for letting go, it is the constant the yanks fight.
local PULL_SECONDS_PER_STUD = Tuning.PULL_SECONDS_PER_STUD
local PULL_DRAG_RATE = Tuning.PULL_DRAG_RATE
local PULL_YANK_PER_CLICK = Tuning.PULL_YANK_PER_CLICK
local PULL_YANK_MIN_INTERVAL = Tuning.PULL_YANK_MIN_INTERVAL
local PULL_YANK_SUSTAINED_CPS = Tuning.PULL_YANK_SUSTAINED_CPS
local PULL_YANK_BURST = Tuning.PULL_YANK_BURST

-- Lock requests are cheap for the server, so this is spam control rather than exploit
-- control -- it stops a held key firing a remote every frame. It is deliberately NOT
-- a Tuning knob: nothing about the game's balance reads it, and the release path is
-- not allowed to consult it at all.
local LOCK_MIN_INTERVAL = 0.25

-- ── State ──────────────────────────────────────────────────────────────

-- One player's reading of a signal: the item they will haul up and the modifier it
-- carries. The signal's own itemId/rarity/modifier fields ARE a PlayerRoll in shape --
-- they are the default, handed to any tier-1 detector without a re-roll.
type PlayerRoll = {
	itemId: string,
	rarity: string,
	modifier: string,
}

type Signal = {
	uid: string,
	stageId: number,
	-- SERVER ONLY as an absolute. It reaches a client in exactly two shapes, both
	-- scoped to the reveal: as an aura part in Workspace, and as an offset relative
	-- to a player already standing inside its radius. Never as a world coordinate.
	position: Vector3,
	-- The default identity, rolled once at spawn with NO luck. `depth` is derived from
	-- this rarity. A tier-1 detector (luck 1.0) gets exactly this.
	itemId: string,
	rarity: string,
	modifier: string,
	depth: number,
	soil: number,
	-- Per-player luck re-rolls, keyed by UserId. Filled lazily the first time the
	-- signal enters that player's radar; goes away with the whole signal on removeSignal.
	rolls: { [number]: PlayerRoll },
}

local signalsByStage: { [number]: { Signal } } = {}

-- One aura per REVEALED signal, keyed by uid, and the set of signals somebody
-- revealed on the current tick. `revealed` is rebuilt from scratch every tick and
-- `auras` is then dragged into line with it — see reconcileAuras.
local auras: { [string]: Model } = {}
local revealed: { [string]: Signal } = {}

-- Yanks banked since the last tick, and the token bucket that decides which incoming
-- clicks were allowed to bank. `lastYankAt` feeds `pulling` (below) as well as the
-- minimum-interval check, so it is written on ACCEPTED yanks only -- a rejected click
-- must not keep the magnet in someone's hands.
local pendingYanks: { [Player]: number } = {}
local yankTokens: { [Player]: number } = {}
local yankRefilledAt: { [Player]: number } = {}
local lastYankAt: { [Player]: number } = {}

-- The signal uid each player has COMMITTED to, or nil. This is the difference between
-- standing on a glow and hauling: progress only moves while it is set.
local lockedTo: { [Player]: string? } = {}
local lastLockAt: { [Player]: number } = {}

local pulling: { [Player]: boolean } = {} -- locked on, and therefore hauling
local overSignal: { [Player]: boolean } = {} -- standing on one, hauling or not
local digProgress: { [Player]: number } = {}
local digTarget: { [Player]: string? } = {}

local sweepRemote: any = nil
local digRemote: any = nil
local lockRemote: any = nil
local unearthedRemote: any = nil
local indexRemote: any = nil

-- ── The auras ─────────────────────────────────────────────────────────

local function auraFolder(): Folder
	local existing = Workspace:FindFirstChild(SignalAura.FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = SignalAura.FOLDER
	folder.Parent = Workspace
	return folder
end

local function clearAura(uid: string)
	local model = auras[uid]
	if model then
		model:Destroy()
		auras[uid] = nil
	end
end

--- Drag the world into line with whatever the players revealed this tick.
---
--- Runs ONCE after the whole player loop, never per player. Two people standing over
--- the same signal have to produce one aura between them, and a set union computed
--- across every player is the only cheap way to say that. Doing it inside stepPlayer
--- instead would have the second player's pass destroy the first player's aura and
--- rebuild it, ten times a second, forever.
local function reconcileAuras()
	local folder = auraFolder()

	for uid, signal in revealed do
		if auras[uid] == nil then
			local model = SignalAura.create(signal.position, Tuning.AURA_RING, Tuning.AURA_DOME, Tuning.AURA_PULSE_REACH)
			model.Parent = folder
			auras[uid] = model
		end
	end

	local stale: { string } = {}
	for uid in auras do
		if revealed[uid] == nil then
			table.insert(stale, uid)
		end
	end
	for _, uid in stale do
		clearAura(uid)
	end
end

-- ── Rolling ───────────────────────────────────────────────────────────
--
-- The rarity roll and the item roll used to be two steps (a weight off Stages.loot,
-- then a uniform pick within that rarity). They are one now: Items.rollItem walks the
-- stage's whole pool weighted by 1/odds, tilted per stage, luck-boosted at the top --
-- see Config/Items.luau's "The dig roll". This file only decides WHEN to roll and for
-- WHOM.

local function rollModifier(): string
	local total = 0
	for _, def in Rarity.MODIFIERS do
		total += def.weight -- Slagged is weight 0: earned, never rolled
	end

	local pick = math.random() * total
	for name, def in Rarity.MODIFIERS do
		pick -= def.weight
		if pick <= 0 and def.weight > 0 then
			return name
		end
	end

	return "None"
end

--- A stage that stocks nothing is a content gap, not a crash. This used to be an
--- error() inside the 10 Hz tick, which — before Ticker gained per-subscriber
--- isolation — took down every service booted after this one. It should degrade to
--- "no signals here" and say so once.
local unstockedWarned: { [number]: boolean } = {}

--- What THIS player's detector reads out of a signal: the item they will haul and the
--- modifier on it. A tier-1 detector (luck <= 1) always gets the signal's default,
--- with no allocation and no cache entry. Anything above re-rolls once, the first time
--- the signal enters their radar, and the result is pinned on the signal under their
--- UserId so the ping, the haul and the unearth all agree.
local function rollFor(signal: Signal, detectorLuck: number, userId: number): (string, string, string)
	if detectorLuck <= 1 then
		return signal.itemId, signal.rarity, signal.modifier
	end

	local cached = signal.rolls[userId]
	if cached then
		return cached.itemId, cached.rarity, cached.modifier
	end

	local tilt = Stages.get(signal.stageId).rarityTilt
	local itemId = Items.rollItem(signal.stageId, tilt, detectorLuck) or signal.itemId
	local roll: PlayerRoll = {
		itemId = itemId,
		rarity = Items.get(itemId).rarity,
		modifier = rollModifier(),
	}
	signal.rolls[userId] = roll
	return roll.itemId, roll.rarity, roll.modifier
end

-- ── The signal field ────────────────────────────────────────────────────

local function stagePart(stageId: number): BasePart?
	local folder = Workspace:FindFirstChild("Stages")
	if folder == nil then
		return nil
	end
	local part = folder:FindFirstChild(`Stage{stageId}`)
	return if part and part:IsA("BasePart") then part else nil
end

local function randomPointOn(part: BasePart): Vector3
	local size = part.Size
	local x = (math.random() - 0.5) * size.X
	local z = (math.random() - 0.5) * size.Z
	return part.CFrame:PointToWorldSpace(Vector3.new(x, size.Y / 2, z))
end

local function spawnSignal(stageId: number)
	local part = stagePart(stageId)
	if part == nil then
		return
	end

	local position = randomPointOn(part)
	local stage = Stages.get(stageId)

	-- The default identity, rolled with NO luck. Everything downstream (burial depth
	-- here, a tier-1 detector's reading in rollFor) hangs off this.
	local itemId = Items.rollItem(stageId, stage.rarityTilt, 1)
	if itemId == nil then
		if not unstockedWarned[stageId] then
			unstockedWarned[stageId] = true
			warn(`[dig] stage {stageId} stocks no items — Config/Items.luau. No signals will spawn there.`)
		end
		return
	end

	local rarity = Items.get(itemId).rarity
	local order = Rarity.get(rarity).order

	local signal: Signal = {
		uid = HttpService:GenerateGUID(false),
		stageId = stageId,
		position = position,
		itemId = itemId,
		rarity = rarity,
		modifier = rollModifier(),
		depth = DEPTH_BASE + (order - 1) * DEPTH_PER_RARITY + math.random() * DEPTH_JITTER,
		soil = stage.soilHardness,
		rolls = {},
	}

	table.insert(signalsByStage[stageId], signal)
end

local function removeSignal(stageId: number, uid: string)
	-- The glow goes with it, this tick, not next. A stale aura is worse than a missing
	-- one: it stands over ground with nothing left in it, and somebody will walk all
	-- the way to it and mash E at nothing.
	clearAura(uid)
	revealed[uid] = nil

	local list = signalsByStage[stageId]
	for index, signal in list do
		if signal.uid == uid then
			table.remove(list, index)
			return
		end
	end
end

local function topUpField()
	for stageId, list in signalsByStage do
		while #list < SIGNALS_PER_STAGE do
			local before = #list
			spawnSignal(stageId)
			if #list == before then
				break -- no stage part in the world yet; try again next tick
			end
		end
	end
end

-- ── The sweep ─────────────────────────────────────────────────────────

type Contact = { signal: Signal, distance: number }

--- A maxed detector standing on a dense patch could otherwise put twenty entries on a
--- 10 Hz remote to feed a radar that shows a handful. The list is sorted by distance,
--- so what falls off the end is always the furthest thing — which is also the thing
--- least likely to be what the player is walking towards.
local MAX_CONTACTS = 12

--- Every signal this player's detector actually registers, nearest first. The depth
--- gate is ABSOLUTE: a signal buried past your detector is invisible, not faint. Rarity
--- no longer gates the reveal at all -- it only bends the per-player roll (see rollFor).
local function registeredFor(stageId: number, position: Vector3, stats: any): { Contact }
	local found: { Contact } = {}

	local list = signalsByStage[stageId]
	if list == nil then
		return found
	end

	local radius = stats.detectorRadius

	for _, signal in list do
		if signal.depth > stats.detectorDepth then
			continue
		end

		local delta = signal.position - position
		local distance = math.sqrt(delta.X * delta.X + delta.Z * delta.Z) -- XZ only
		if distance <= radius then
			table.insert(found, { signal = signal, distance = distance })
		end
	end

	table.sort(found, function(a: Contact, b: Contact): boolean
		return a.distance < b.distance
	end)

	while #found > MAX_CONTACTS do
		table.remove(found)
	end

	return found
end

--- Is the player standing on a glow they personally cannot lock onto? Auras are
--- public but the depth gate is not, so without this state a Bent Coil standing in a
--- deep signal's reveal gets a pillar of light and a blank detector HUD — which looks
--- like the game is broken rather than like the detector is too cheap.
---
--- Only ever consulted when the player has no contact of their own in range, so the
--- scan cost lands on the frames where nothing else is happening.
local function standingOnUnregistered(stageId: number, position: Vector3, stats: any): boolean
	local list = signalsByStage[stageId]
	if list == nil then
		return false
	end

	for _, signal in list do
		if auras[signal.uid] == nil then
			continue -- nobody revealed it, so there is nothing to be confused by
		end

		local delta = signal.position - position
		if delta.X * delta.X + delta.Z * delta.Z > DIG_RADIUS * DIG_RADIUS then
			continue
		end

		if signal.depth > stats.detectorDepth then
			return true
		end
	end

	return false
end


--- What the ping is allowed to reveal before you dig. PLAN §2 step 1: high-tier
--- detectors show rarity on the ping so you stop wasting time digging Scrap. Takes the
--- roll already resolved for this player (rollFor) -- rarity/modifier/itemId -- so the
--- ping matches what will actually come out of the ground.
--- The odds ride the SAME clarity gate as the modifier (>= 3): they pin down which
--- item this is more than the bare rarity does, so a cheap detector should not read
--- them off someone else's aura. `odds` is the collectible headline (Config/Items.luau).
local function hintFor(rarity: string, modifier: string, itemId: string, clarity: number): (string?, string?, number?)
	if clarity <= 0 then
		return nil, nil, nil
	end
	if clarity >= 3 then
		return rarity, modifier, Items.get(itemId).odds
	end
	return rarity, nil, nil
end

--- Player-relative XZ offsets, plus whatever detectorClarity lets THIS player know
--- about each contact. Relative, not absolute: a radar only ever needs "where is it
--- from me", and world coordinates on the wire is exactly what the boundary rule in
--- the header is about.
---
--- Rarity rides here rather than on the aura on purpose. The aura is one shared
--- instance and both clarity AND the per-player roll are per-player, so a shared
--- instance physically cannot express it — put the colour on the aura and every Bent
--- Coil in the server reads Legendary off someone else's detector for free.
---
--- This is also where a signal's per-player roll gets pinned: the first time it lands
--- in someone's radar, rollFor caches their reading of it.
local function contactPayload(
	contacts: { Contact },
	position: Vector3,
	clarity: number,
	detectorLuck: number,
	userId: number
): { any }
	local out = {}

	for _, entry in contacts do
		local itemId, rarity, modifier = rollFor(entry.signal, detectorLuck, userId)
		local rarityHint = hintFor(rarity, modifier, itemId, clarity)
		table.insert(out, {
			dx = entry.signal.position.X - position.X,
			dz = entry.signal.position.Z - position.Z,
			rarity = rarityHint,
		})
	end

	return out
end

--- Mark every contact as revealed on this tick. reconcileAuras turns the accumulated
--- set into actual parts once the whole player loop has had its say.
local function markRevealed(contacts: { Contact })
	for _, entry in contacts do
		revealed[entry.signal.uid] = entry.signal
	end
end

-- What each player could see last tick, so the server can tell the client how many
-- contacts are NEW and it can chirp for them. This is a server decision like every
-- other one: the client is never given uids — deliberately — so it has nothing to
-- diff and could only guess from the count, which miscounts every time one signal
-- leaves the radius as another enters.
local lastContacts: { [Player]: { [string]: boolean } } = {}

local function noteContacts(player: Player, contacts: { Contact }): number
	local previous = lastContacts[player]
	local current: { [string]: boolean } = {}
	local fresh = 0

	for _, entry in contacts do
		local uid = entry.signal.uid
		current[uid] = true
		if previous == nil or not previous[uid] then
			fresh += 1
		end
	end

	lastContacts[player] = current
	return fresh
end

-- ── The dig ──────────────────────────────────────────────────────────

-- The item, physically rising. This is the only place a signal's position reaches
-- the world, and it is safe to: the player is already standing within DIG_RADIUS of
-- it and has committed to the pull. The FIELD stays invisible — only the one thing
-- you are actively hauling shows itself.
type Haul = {
	itemId: string,
	model: Model,
	placeholder: BasePart?,
}

local hauled: { [Player]: Haul } = {}

local function clearHaul(player: Player)
	local haul = hauled[player]
	if haul then
		haul.model:Destroy()
		hauled[player] = nil
	end
end

--- Drop the lock, whatever the reason. ROOTING IS THE STAKE HERE: while a player is
--- locked, ExposureService holds their WalkSpeed at zero, so failing to release does
--- not merely leave a stale flag — it leaves a person standing in a field unable to
--- move, with no in-game way out. Every path that can invalidate a lock therefore ends
--- up here:
---
---   1. the player presses Q                    (DigLock handler)
---   2. the item breaks the surface             (unearth)
---   3. their bag fills up                      (stepPlayer, blocked == "full")
---   4. the signal is gone from under them      (stepPlayer, uid lookup fails)
---   5. they walk out of the stage              (stepPlayer, stageId == nil)
---   6. they BLACK OUT                          (via 5 — see the note there)
---   7. they leave the game                     (PlayerRemoving)
---
--- Cheap and idempotent on purpose, so callers never have to check first.
local function releaseLock(player: Player)
	lockedTo[player] = nil
end

local function createHaul(player: Player, itemId: string): Haul
	local item = Items.get(itemId)
	local model = ItemModels.create(item.model)
	local placeholder: BasePart? = nil

	if model == nil then
		model = Instance.new("Model")
		placeholder = Instance.new("Part")
		placeholder.Name = "Placeholder"
		placeholder.Size = Vector3.new(1.4, 1.4, 1.4)
		placeholder.Material = Enum.Material.Metal
		placeholder.Anchored = true
		placeholder.CanCollide = false
		placeholder.CanQuery = false
		placeholder.CanTouch = false
		placeholder.Parent = model
	end

	model.Name = `Haul_{player.Name}`
	model:SetAttribute("ItemId", itemId)
	model.Parent = Workspace

	return {
		itemId = itemId,
		model = model,
		placeholder = placeholder,
	}
end

local function updateHaul(player: Player, signal: Signal, itemId: string, progress: number, rarityHint: string?)
	if progress <= 0.01 then
		clearHaul(player)
		return
	end

	local haul = hauled[player]
	if haul == nil or haul.model.Parent == nil or haul.itemId ~= itemId then
		clearHaul(player)
		haul = createHaul(player, itemId)
		hauled[player] = haul
	end

	-- Only wear a rarity colour if the detector was good enough to reveal it. A Bent
	-- Coil user hauls up an anonymous lump and finds out when it breaks the surface.
	-- Authored models keep their real materials; only not-yet-modelled placeholders
	-- need this colour channel.
	if haul.placeholder then
		haul.placeholder.Color = if rarityHint then Rarity.get(rarityHint).color else Color3.fromHex("6E6A62")
	end

	haul.model:PivotTo(
		CFrame.new(signal.position - Vector3.new(0, signal.depth * (1 - progress), 0))
			* CFrame.Angles(0, progress * 8, 0)
			* ItemModels.rotation(haul.model, "Haul")
	)
end

--- `itemId`/`rarity`/`modifier` are THIS player's resolved roll (rollFor), not the
--- signal's default — a lucky detector hauls up its own reading.
local function unearth(player: Player, data: any, signal: Signal, itemId: string, rarity: string, modifier: string)
	clearHaul(player)
	local item = Items.get(itemId)

	table.insert(data.carry, {
		uid = signal.uid,
		itemId = itemId,
		rarity = rarity,
		modifier = modifier,
		elapsed = 0, -- the decay clock starts HERE (PLAN §3.6). Phase 3 ticks it.
		frozen = false,
		-- Contamination is rolled the moment it leaves the ground, not at the station,
		-- because that is when it picked the dirt up. Extends ARCHITECTURE's CarriedItem.
		patches = Contamination.rollPatches(rarity, modifier),
	})

	data.discovered[itemId] = true

	removeSignal(signal.stageId, signal.uid)
	spawnSignal(signal.stageId) -- keep the field populated

	unearthedRemote:FireClient(player, {
		itemId = item.id,
		name = item.name,
		flavor = item.flavor,
		rarity = rarity,
		modifier = modifier,
		baseValue = item.baseValue,
		carrying = #data.carry,
	})

	print(`[dig] {player.Name} unearthed {modifier} {rarity} — {item.name}`)
end

-- ── Tick ────────────────────────────────────────────────────────────

local function stepPlayer(player: Player, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local data = DataService.data(player)
	if data == nil then
		return
	end

	local stats = StatResolver.get(data)
	local position = root.Position
	local stageId = StageService.stageOf(player)

	if stageId == nil then
		digProgress[player] = 0
		digTarget[player] = nil
		-- RELEASE 5, AND THE ONE THAT CATCHES BLACKOUTS (release 6). ExposureService's
		-- blackout teleports the player to base camp but deliberately does NOT kill the
		-- character, so nothing character-related fires to clean up after it -- no Died,
		-- no CharacterAdded, no respawn. This branch is the only thing between "blacked
		-- out while hauling" and "rooted at base camp forever". Do not make it
		-- conditional on anything.
		releaseLock(player)
		pulling[player] = false
		overSignal[player] = false
		clearHaul(player)
		noteContacts(player, {}) -- so walking back in chirps for the field again
		-- carrying/capacity ride along on EVERY payload: the bag counter should be
		-- true all the time, not only while something is pinging.
		sweepRemote:FireClient(player, {
			inStage = false,
			locked = false,
			carrying = #data.carry,
			capacity = stats.capacity,
		})
		return
	end

	local contacts = registeredFor(stageId, position, stats)
	markRevealed(contacts)

	local nearest = contacts[1]

	if nearest == nil then
		digProgress[player] = 0
		digTarget[player] = nil
		-- Nothing registerable left within reach, so whatever they locked onto is not
		-- theirs to hold any more.
		releaseLock(player)
		pulling[player] = false
		overSignal[player] = false
		clearHaul(player)
		sweepRemote:FireClient(player, {
			inStage = true,
			stageId = stageId,
			radius = stats.detectorRadius,
			hasSignal = false,
			contacts = {},
			newContacts = noteContacts(player, contacts),
			-- Standing in a glow somebody else revealed. Nothing to pull, but the
			-- player deserves to be told which of the two "nothing here" states
			-- they are in.
			blocked = if standingOnUnregistered(stageId, position, stats) then "unregistered" else nil,
			locked = false,
			carrying = #data.carry,
			capacity = stats.capacity,
		})
		return
	end

	-- WHICH SIGNAL THIS TICK IS ABOUT. Normally the nearest one -- but a LOCKED player
	-- is committed to a specific uid, and that commitment outranks proximity. Rooting
	-- means the locked signal is almost always still the nearest anyway; what this
	-- guards is the case that is not about the player moving at all, which is somebody
	-- ELSE hauling the same signal out from under them (auras are public, and two
	-- people can stand in one glow).
	local held: Contact? = nil
	if lockedTo[player] ~= nil then
		for _, entry in contacts do
			if entry.signal.uid == lockedTo[player] then
				held = entry
				break
			end
		end

		if held == nil then
			-- RELEASE 4: the thing they committed to is not in reach any more, so the
			-- commitment cannot survive either. Progress goes with it -- there is
			-- nothing left to be partway out of the ground.
			releaseLock(player)
			digProgress[player] = 0
		end
	end

	local working = held or nearest
	local signal = working.signal
	local distance = working.distance
	local strength = math.clamp(1 - (distance / stats.detectorRadius), 0, 1)
	-- This player's reading of the working signal, resolved once and threaded through
	-- the ping, the haul model and the unearth below so all three agree.
	local itemId, rarity, modifier = rollFor(signal, stats.detectorLuck, player.UserId)
	local rarityHint, modifierHint, oddsHint = hintFor(rarity, modifier, itemId, stats.detectorClarity)

	-- Reset progress if they wandered off this signal onto another one. While locked
	-- this never fires, which is the point: the target cannot drift mid-haul.
	if digTarget[player] ~= signal.uid then
		digTarget[player] = signal.uid
		digProgress[player] = 0
	end

	local inRange = distance <= DIG_RADIUS
	local strongEnough = signal.soil <= stats.maxGrip
	local hasRoom = #data.carry < stats.capacity

	local blocked: string? = nil
	if not strongEnough then
		blocked = "weak"
	elseif not hasRoom then
		blocked = "full"
	end

	-- RELEASE 3: a full bag is the one thing that makes a lock pointless rather than
	-- merely hard, and a rooted player staring at a panel they cannot finish is the
	-- worst version of this feature. Let them go immediately.
	if blocked == "full" then
		releaseLock(player)
	end

	-- "How much rope is on this item", in pull-seconds. Depth ONLY -- pullSpeed lives
	-- entirely on the yank now (see Tuning's note: counting it in both places would make
	-- the magnet track scale quadratically).
	local required = PULL_SECONDS_PER_STUD * signal.depth
	local progress = digProgress[player] or 0

	-- Yanks banked since the last tick, taken whether or not they land, so a player
	-- mashing at a full bag is not silently storing up clicks to spend the moment they
	-- sell something.
	local yanks = pendingYanks[player] or 0
	pendingYanks[player] = 0

	-- PROGRESS ONLY MOVES WHILE LOCKED. This is the whole two-beat change in one line:
	-- standing on a glow does nothing at all until you have committed to it.
	local isLocked = lockedTo[player] ~= nil
	local canPull = isLocked and inRange and blocked ~= "full"

	-- Drives which tool is visible in the player's hands (ToolService). The lock is a
	-- much better signal for this than the old "yanked in the last half second" was:
	-- it is true for the entire haul, so the magnet stops flickering in and out
	-- between clicks and simply stays in their hands until they are done.
	pulling[player] = isLocked
	overSignal[player] = inRange and blocked ~= "full"

	-- THE MASH, in two halves. The soil pulls DOWN every tick no matter what, and each
	-- yank is an impulse UP. Whether the item rises is just which of the two is winning,
	-- which is why there is no "are they digging" branch here any more -- the drag is
	-- unconditional and a slow clicker loses ground without the code having to decide
	-- that they stopped.
	--
	-- `draw` is the magnet's passive lift, in the drag's own units, so (draw - drag) is
	-- the net idle rate: strongly negative at tier 1, near zero at the top. That single
	-- subtraction is the entire comfort curve the magnet track sells.
	--
	-- A full bag is the one hard stop — there is nowhere to put it. An under-rated
	-- magnet still gets to try, and that trying is the whole teaching moment.
	if canPull then
		progress += (stats.draw - PULL_DRAG_RATE) * dt / required
		progress += yanks * PULL_YANK_PER_CLICK * stats.pullSpeed / required
		progress = math.max(progress, 0)
		if not strongEnough then
			progress = math.min(progress, STRAIN_CEILING)
		end

		if progress >= 1 then
			digProgress[player] = 0
			digTarget[player] = nil
			-- RELEASE 2: it is out of the ground. Nothing left to hold on to, and the
			-- player gets their feet back the instant the banner fires.
			releaseLock(player)
			unearth(player, data, signal, itemId, rarity, modifier)

			-- Everything ELSE in range is still in range; only the thing that came out
			-- of the ground is gone. Sending an empty payload here and waiting for the
			-- next tick to repopulate makes the radar blink, and — because the server
			-- diffs contacts to decide when to chirp — fires a fresh-contact chirp for
			-- signals the player has been walking towards for twenty seconds.
			local surviving: { Contact } = {}
			for _, entry in contacts do
				if entry.signal.uid ~= signal.uid then
					table.insert(surviving, entry)
				end
			end

			local following = surviving[1]
			local followRarityHint: string? = nil
			if following then
				local fId, fRarity, fMod = rollFor(following.signal, stats.detectorLuck, player.UserId)
				followRarityHint = hintFor(fRarity, fMod, fId, stats.detectorClarity)
			end
			sweepRemote:FireClient(player, {
				inStage = true,
				stageId = stageId,
				radius = stats.detectorRadius,
				hasSignal = following ~= nil,
				strength = if following then math.clamp(1 - (following.distance / stats.detectorRadius), 0, 1) else 0,
				rarityHint = followRarityHint,
				contacts = contactPayload(surviving, position, stats.detectorClarity, stats.detectorLuck, player.UserId),
				newContacts = noteContacts(player, surviving),
				digProgress = 0,
				locked = false,
				carrying = #data.carry,
				capacity = stats.capacity,
			})
			return
		end
	else
		-- Out of range, or nowhere to put it. The magnet is not on the item at all, so it
		-- gets the bare drag with NO draw against it -- passive lift is something a magnet
		-- does to a thing it is gripping, and walking away is not gripping. The haul is a
		-- commitment, not a checkpoint you bank.
		progress = math.max(0, progress - PULL_DRAG_RATE * dt / required)
	end

	digProgress[player] = progress
	updateHaul(player, signal, itemId, progress, rarityHint)

	-- OFFSETS INSIDE THE REVEAL RADIUS ONLY. No world coordinates, no uids, and
	-- nothing the player is not already looking at a glow for.
	sweepRemote:FireClient(player, {
		inStage = true,
		stageId = stageId,
		radius = stats.detectorRadius,
		hasSignal = true,
		strength = strength,
		contacts = contactPayload(contacts, position, stats.detectorClarity, stats.detectorLuck, player.UserId),
		newContacts = noteContacts(player, contacts),
		rarityHint = rarityHint,
		modifierHint = modifierHint,
		oddsHint = oddsHint,
		inRange = inRange,
		blocked = blocked,
		-- Recomputed rather than reusing `isLocked` from the top of the tick, because
		-- the releases above (bag full, signal gone, item surfaced) can all have fired
		-- since. The payload has to describe the world AFTER this tick settled, or the
		-- client draws a haul panel for a lock the server already dropped.
		locked = lockedTo[player] ~= nil,
		digProgress = digProgress[player] or 0,
		carrying = #data.carry,
		capacity = stats.capacity,
	})
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

--- Is this player currently hauling something up? Read by ToolService to decide
--- whether the magnet or the detector belongs in their hands.
function DigService.isPulling(player: Player): boolean
	return pulling[player] == true
end

--- Has this player committed to a signal? Read by ExposureService, which owns
--- Humanoid.WalkSpeed and holds it at zero while this is true — the lock ROOTS you,
--- and this is how the one system allowed to write WalkSpeed finds that out.
function DigService.isLocked(player: Player): boolean
	return lockedTo[player] ~= nil
end

--- Standing close enough to haul, whether or not they have started. ToolService
--- swaps to the magnet on THIS rather than on isPulling: a pull lasts a couple of
--- seconds, so keying the model to it made the magnet flicker in and out too fast
--- to register. Swapping on approach reads as "found it, now get the magnet out".
function DigService.isOverSignal(player: Player): boolean
	return overSignal[player] == true
end

--- Kept as a thin delegate so callers written during Phase 1 keep working.
--- StageService is the authority now.
function DigService.stageOf(player: Player): number?
	return StageService.stageOf(player)
end

function DigService.init()
	sweepRemote = Net.get("SweepState")
	digRemote = Net.get("DigYank")
	lockRemote = Net.get("DigLock")
	unearthedRemote = Net.get("Unearthed")
	indexRemote = Net.get("IndexState")

	-- Auras are runtime objects, but Workspace is a thing people save from Studio, so
	-- a folder full of them can absolutely end up published into the place. Those
	-- ghosts would never be reconciled away — `auras` starts empty and nothing else
	-- knows they exist — leaving permanent glows over ground with nothing under it.
	local stale = Workspace:FindFirstChild(SignalAura.FOLDER)
	if stale then
		stale:Destroy()
	end

	-- Phase 1 is one stage. The loop is written for all six.
	for _, stage in Stages.DEFS do
		signalsByStage[stage.id] = {}
	end
end

function DigService.start()
	topUpField()

	-- The index GUI's one and only snapshot. Everything discovered AFTER this fires
	-- arrives incrementally instead, via the itemId already riding along on every
	-- unearthedRemote fire below — no second remote needed to keep the client caught
	-- up, just this one at load to seed it with what a returning player already knew.
	DataService.onLoaded(function(player, data)
		indexRemote:FireClient(player, data.discovered)
	end)

	-- THE YANK LIMITER. Every accepted click is progress the client asked for, so this
	-- is the only thing standing between an autoclicker and a free economy. Two gates,
	-- doing different jobs:
	--
	--   * MIN_INTERVAL is the instantaneous floor. It throws away the "fired the remote
	--     forty times this frame" case outright, before any accounting happens.
	--   * the token bucket is the SUSTAINED cap, and it is the one that actually matters.
	--     Tokens refill at PULL_YANK_SUSTAINED_CPS and pool up to PULL_YANK_BURST, so a
	--     human opening with a fast flurry spends banked tokens and is not punished for
	--     it, while anyone trying to hold that rate forever is metered down to the refill.
	--
	-- Rejected yanks are dropped in SILENCE. No error, no remote back, no log line. Any
	-- of those would hand an exploiter a free oracle for finding the exact ceiling, and
	-- an honest player never reaches it.
	digRemote.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()

		if now - (lastYankAt[player] or -math.huge) < PULL_YANK_MIN_INTERVAL then
			return
		end

		local tokens = math.min(
			PULL_YANK_BURST,
			(yankTokens[player] or PULL_YANK_BURST) + (now - (yankRefilledAt[player] or now)) * PULL_YANK_SUSTAINED_CPS
		)
		yankRefilledAt[player] = now

		if tokens < 1 then
			yankTokens[player] = tokens
			return
		end

		yankTokens[player] = tokens - 1
		lastYankAt[player] = now
		pendingYanks[player] = (pendingYanks[player] or 0) + 1
	end)

	-- LOCK ON / RELEASE. The client sends a boolean and nothing else -- never a uid, so
	-- it cannot ask to lock onto something it is not standing over; the server resolves
	-- the target here exactly the way the tick does.
	--
	-- ONLY THE LOCK DIRECTION IS RATE LIMITED, and the asymmetry is deliberate. A
	-- debounced lock costs a player one keypress. A debounced RELEASE costs them their
	-- character: they are rooted until it goes through, so releasing has to be
	-- unconditional, instant, and impossible to throttle. If you ever add a guard to
	-- this handler, add it above the release branch, never below it.
	lockRemote.OnServerEvent:Connect(function(player: Player, wantLock: any)
		if wantLock ~= true then
			-- RELEASE 1. No checks of any kind on this path, on purpose.
			releaseLock(player)
			return
		end

		local now = os.clock()
		if now - (lastLockAt[player] or -math.huge) < LOCK_MIN_INTERVAL then
			return
		end
		lastLockAt[player] = now

		if lockedTo[player] ~= nil then
			return -- already committed; a second tap is not a re-target
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			return
		end

		local data = DataService.data(player)
		local stageId = StageService.stageOf(player)
		if data == nil or stageId == nil then
			return
		end

		-- Same resolution the tick uses, so "what you can lock onto" and "what you can
		-- haul" can never drift apart into two different answers.
		local stats = StatResolver.get(data)
		local nearest = registeredFor(stageId, root.Position, stats)[1]
		if nearest == nil or nearest.distance > DIG_RADIUS then
			return
		end

		-- A full bag is refused UP FRONT rather than locked and then released a tick
		-- later, which would root the player for a moment and flash a panel at them.
		if #data.carry >= stats.capacity then
			return
		end

		lockedTo[player] = nearest.signal.uid
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- RELEASE 7.
		releaseLock(player)
		lastLockAt[player] = nil
		pendingYanks[player] = nil
		yankTokens[player] = nil
		yankRefilledAt[player] = nil
		lastYankAt[player] = nil
		digProgress[player] = nil
		digTarget[player] = nil
		pulling[player] = nil
		overSignal[player] = nil
		lastContacts[player] = nil
		clearHaul(player)

		-- Drop this player's cached per-signal rolls. Not strictly required (a signal
		-- carries the entry only until it is pulled and respawned), but a stage that
		-- churns slowly could otherwise keep a departed player's readings around for a
		-- long time. Cheap: signals are ~75 per stage.
		local userId = player.UserId
		for _, list in signalsByStage do
			for _, signal in list do
				signal.rolls[userId] = nil
			end
		end

		-- Their auras are not cleaned up here. They are rebuilt from the surviving
		-- players on the next tick, and anything only this player could see falls out
		-- of `revealed` on its own — one shared reconcile, one place to be wrong.
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		topUpField()

		-- Rebuilt from nothing every tick rather than maintained incrementally. A
		-- reveal set that is only ever added to and subtracted from drifts the moment
		-- one stepPlayer call throws — and stepPlayer is deliberately wrapped in a
		-- pcall, so it will. Recomputing costs one table clear and leaves a dropped
		-- tick self-healing instead of permanently stranding a glow in the field.
		table.clear(revealed)

		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player, dt)
			if not ok then
				warn(`[dig] tick failed for {player.Name}: {err}`)
			end
		end

		reconcileAuras()
	end)

	local total = 0
	for _, list in signalsByStage do
		total += #list
	end
	print(`[dig] signal field seeded — {total} buried signal(s)`)
end

return DigService
