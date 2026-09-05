--!strict
--[[
	WashService.lua — the hose. Hold the thing, press E at the tub, blast it clean.

	THIS IS PLAN §2 STEP 4 AS ORIGINALLY WRITTEN. The design asked for "a skill
	mini-interaction, not a progress bar", and §16 hedged that if it did not work, fall
	back to a hold-to-clean bar with the potency gate. We shipped the fallback and
	lived with it for a while: you held a button on a panel and an item you could not
	see got cleaner. This is the version that was actually asked for.

	THE MATHS DID NOT CHANGE. Not one number. `Contamination.secondsFor`,
	`Contamination.clearOne`, the effective-potency gate and one charge per cleared
	patch are lifted from DeconService's old scrub tick untouched. What changed is who
	drives the clock and what the player is looking at while it runs. That is
	deliberate: a feel change that also moves the balance is two changes wearing one
	commit, and there would be no way to tell which one broke the economy.

	THE BOUNDARY IS THE SAME ONE THE SCRUB TIMER HAD. The client reports AIM and
	INTENT — "I am spraying, at patch 3" — and never progress. The server owns the
	clock, the patch list, the charges and the XP. A client that lies about aim picks a
	different patch to work on, which it could already do by clicking a different row;
	a client that could report progress would clean an Anomaly instantly.

	PRECONDITION: YOU MUST BE HOLDING IT. `data.heldUid` (CarryService) has to name a
	carried item with contamination on it, or the prompt refuses with a toast. That is
	the user's rule verbatim — "if they dont hold anything in their hand then nothing
	would happen" — and it is why holding had to become real state instead of the
	hotbar's private selection.

	WHY THE SESSION IS SERVER-OWNED STATE AND NOT A CLIENT MODE. Three things have to
	stay true for a wash that ends badly, and all three are server facts: the item goes
	back in your bag, your walk speed comes back, and the model on the tub gets
	destroyed. A client-owned session leaves all three dangling on a disconnect.

	THE HOSE IS A MACHINE, AND THIS SERVICE NO LONGER TOUCHES IT. It is built with the
	station (build/Plots.buildHoseRig): a pump, a reel of green hose, and a monitor
	bolted to a mast at the near corner of the tub, at whatever Cleaner rung the plot's
	owner has bought. Starting a wash used to hand the player a CLONE of that nozzle,
	welded into their right hand, with the parked original stashed and the reel's Beam
	swung onto the copy — three moving pieces to put back on every exit path, and a
	whole upgrade track that lived in a fist. All of it is gone. The session simply
	NAMES the station's own nozzle in its state payload; WashController points it,
	locally, and puts it back on its `ParkedPivot` when the session ends.

	WHAT THAT DELETED, so nobody re-adds it looking for a bug: takeHose/stowHose, the
	session's `hose`/`parked`/`line`/`parkedCurve` fields, the HoldCFrame read, and the
	beam's two CurveSize states. The player's hands are empty at the tub now, and
	ToolService's decon branch is empty with them.

	YOUR STATS ARE YOURS, THE MACHINE IN FRONT OF YOU IS THE PLOT'S. `power` and
	`volume` come out of the washing player's own profile (StatResolver), exactly as
	every other track does — so washing at a neighbour's bay does not lend you their
	rung, and it does not lend them yours. On your own plot, which is where your
	RespawnLocation puts you and where all six bays therefore get used, the machine on
	the mast and the numbers in the clock are the same purchase.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Liquids = require(Shared.Config.Liquids)
local ItemModels = require(Shared.ItemModels)
local ItemGrime = require(Shared.ItemGrime)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local CarryService = require(script.Parent.CarryService)
local EconomyService = require(script.Parent.EconomyService)
local LiquidService = require(script.Parent.LiquidService)

local WashService = {}

local XP_PER_HARDNESS = 5

--- How far the player may drift from the tub before the session ends itself. Wider
--- than the prompt's own activation distance on purpose: being nudged one stud by a
--- respawning teammate should not eject you mid-wash.
local LEASH = 16

--- How far forward of WashSpot the player is actually planted, in studs. See the note
--- at the call site for why this is arithmetic here rather than a moved anchor in
--- build/Plots. The tub's near rim sits a shade under four studs in front of the mark,
--- so this stops well clear of standing inside the geometry.
local APPROACH = 1.2

type Session = {
	uid: string,
	stand: BasePart,
	station: Instance?,
	prompt: ProximityPrompt?,
	returnTo: CFrame?,
	model: Instance?,
	-- The station's own monitor, resolved once at begin() and passed to the client in
	-- every state push. NOT owned here and never modified here: this service does not
	-- move it, park it, weld it or destroy it — the field exists so the client is told
	-- which nozzle is live rather than re-deriving it from the stand's parent, and so
	-- a station rebuilt mid-session (World.rebuild from the command bar) leaves a
	-- reference this service can see has gone stale.
	hose: Model?,
	spraying: boolean,
	-- The client's raw, live requested target -- a ZONE id (stable across a patch
	-- clearing elsewhere and the array compacting), never an array index. Echoed
	-- straight back in `push` as `targetZone`; `aim` is what turns it into whichever
	-- array index is currently reachable.
	aimZone: number?,
	elapsed: number,
	target: number,
	hardness: number,
	-- Which zone `elapsed`/`target` are actually counting against, set once by `aim`
	-- when it locks a target and left alone until the next lock -- unlike `aimZone`,
	-- this does not follow the player's reticle, which is what lets `push` fade the
	-- zone actually being timed instead of whatever the player is currently glancing
	-- at.
	lockedZone: number?,
	-- One real-geometry patch, one zone: WashService.placeOnStand builds these fresh
	-- every session from the item's own model (or a stand-in cluster of blocks for
	-- the rarity-coloured fallback), one per patch. `zoneIds[i]` names which zone the
	-- patch currently at `item.patches[i]` owns; it shrinks in lockstep with
	-- `item.patches` -- same `table.remove`, same index -- every time a patch clears,
	-- so a zone's identity survives every other patch's array shifting around it.
	zones: { [number]: { BasePart } },
	zoneAnchor: { [number]: Vector3 },
	zoneIds: { number },
}

local sessions: { [Player]: Session? } = {}

-- Forward-declared: `begin` ends an existing session (pressing E again is how you
-- leave) and is defined above `finish` in reading order, because starting a wash is
-- the interesting half.
local finish: (player: Player, reason: string?) -> ()

local stateRemote: any = nil
local inputRemote: any = nil
local resultRemote: any = nil

--- Read by ToolService (the item is on the tub, not in your hand) and by
--- ExposureService (you do not walk while washing). Both are one-line reads of a
--- fact this service already has, rather than new machinery in either.
function WashService.isWashing(player: Player): boolean
	return sessions[player] ~= nil
end

-- ── Rendering the item on the tub ──────────────────────────────────────

--- Gems and glass are not grime -- the ring's diamond stays a diamond no matter how
--- dirty the band around it gets, same "the object still has to be readable" rule
--- ItemGrime paints the rest of the model by.
local function isPaintable(part: BasePart): boolean
	return part.Material ~= Enum.Material.Glass
end

--- Bucket a sculpted model's real paintable parts round-robin into `count` zones —
--- one per patch. Round-robin rather than a contiguous slice on purpose: GoldRing's
--- forty band segments are one long ring of near-identical pieces, and a contiguous
--- chunk of them clearing would read as a bite taken out of the band. Scattering the
--- same zone across the whole part list instead makes every clear read as the WHOLE
--- item getting a little cleaner, same as the aggregate fade used to, just now with
--- real geography under it.
local function zonesFromModel(model: Model, count: number): { [number]: { BasePart } }
	local zones: { [number]: { BasePart } } = {}
	for zone = 1, count do
		zones[zone] = {}
	end

	local i = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and isPaintable(part) then
			i += 1
			local zone = ((i - 1) % count) + 1
			table.insert(zones[zone], part)
		end
	end
	return zones
end

--- Items with no sculpted model (most of the catalogue — see ItemModels) wash as a
--- small cluster of blocks instead of one solid one, ONLY here on the stand: the
--- single rarity-coloured block DigService's haul and ToolService's off hand show is
--- untouched, so splitting this one costs nothing outside the wash bay. It exists so
--- a Steel Rod gets the same real per-patch areas to clean that a Gold Ring does,
--- instead of one block fading as a whole.
local function buildBlockCluster(stand: BasePart, item: any, count: number): (Model, { [number]: { BasePart } })
	local model = Instance.new("Model")
	model.Name = "WashItem"

	local columns = math.ceil(math.sqrt(count))
	local rows = math.ceil(count / columns)
	local cellSize = 1.4 / math.max(columns, rows)
	local cubeSize = cellSize * 0.82

	local zones: { [number]: { BasePart } } = {}
	for index = 1, count do
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local x = (column - (columns - 1) / 2) * cellSize
		local y = (row - (rows - 1) / 2) * cellSize

		local cube = Instance.new("Part")
		cube.Name = `Zone{index}`
		cube.Size = Vector3.new(cubeSize, cubeSize, cubeSize)
		cube.Color = Rarity.get(item.rarity).color
		cube.Material = Enum.Material.SmoothPlastic
		cube.Anchored = true
		cube.CanCollide = false
		cube.CFrame = stand.CFrame * CFrame.new(x, y, 0)
		cube.Parent = model
		zones[index] = { cube }
	end

	model:PivotTo(stand.CFrame)
	model.Parent = stand
	return model, zones
end

--- A world point for a zone's ball: the average position of the real parts it owns,
--- or — for a zone a sculpted model didn't have enough paintable parts to fill —
--- a point on the model's own bounding sphere, the same golden-angle spiral the
--- decorative blobs used to use everywhere, kept only as this one fallback so a zone
--- with nothing physical in it still has somewhere to put its ball.
local function zoneAnchor(zone: { BasePart }, pivot: CFrame, size: Vector3, index: number, count: number): Vector3
	if #zone > 0 then
		local sum = Vector3.zero
		for _, part in zone do
			sum += part.Position
		end
		return sum / #zone
	end

	local golden = 2.39996323
	local t = (index - 0.5) / math.max(count, 1)
	local y = 1 - 2 * math.min(t, 1)
	local radius = math.sqrt(math.max(0, 1 - y * y))
	local theta = golden * index
	local dir = Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
	local extent = (size * 0.5) + Vector3.new(0.12, 0.12, 0.12)
	return (pivot * CFrame.new(dir * extent)).Position
end

--- SERVER-SIDE, so everyone on the base sees the thing being washed. The spray VFX
--- is client-local (see WashController) because it is per-viewer motion, but the
--- OBJECT is the storytelling — a stranger walking onto your plot should see a Gold
--- Ring sitting in your tub, not an empty bath and someone miming.
---
--- Returns the display model plus one zone per patch, each wearing a full coat of
--- grime — every zone here corresponds to a patch that has not been cleared yet, so
--- "fully dirty" is true by construction and there is no fractional level to compute
--- any more. `stepPlayer` clears a zone's own parts the instant its patch pops.
local function placeOnStand(stand: BasePart, item: any): (Model, { [number]: { BasePart } }, { [number]: Vector3 })
	local count = math.max(#(item.patches or {}), 1)
	local def = Items.get(item.itemId)
	local sculpted = ItemModels.create(def.model)

	local model: Model
	local rawZones: { [number]: { BasePart } }
	if sculpted then
		sculpted.Name = "WashItem"
		for _, part in sculpted:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end
		sculpted.Parent = stand
		sculpted:PivotTo(stand.CFrame * ItemModels.rotation(sculpted, "Wash"))
		model = sculpted
		rawZones = zonesFromModel(sculpted, count)
	else
		model, rawZones = buildBlockCluster(stand, item, count)
	end

	local pivot, size = model:GetBoundingBox()
	local zones: { [number]: { BasePart } } = {}
	local anchors: { [number]: Vector3 } = {}
	for zone = 1, count do
		zones[zone] = rawZones[zone] or {}
		anchors[zone] = zoneAnchor(zones[zone], pivot, size, zone, count)
		ItemGrime.applyParts(zones[zone], 1)
	end

	return model, zones, anchors
end

-- ── The machine's nozzle ───────────────────────────────────────────────

--- The monitor on this station's mast, or nil if this place was built before the mast
--- existed (build/Plots.buildHoseRig). Resolved once per session and handed to the
--- client, which is the only thing that touches it: the nozzle is anchored world
--- geometry, and a client rewriting an anchored part's CFrame moves it for that
--- viewer alone. That is exactly the fidelity the spray already has (WashController's
--- jet is client-local too), and it is why aiming needs no remote traffic at all.
---
--- NIL IS NOT FATAL. A place file without a rig still washes — you just get no nozzle
--- swinging and the jet leaves from the fallback origin the controller picks — which
--- is the same graceful degrade the held version had for the same reason.
local function stationHose(station: Instance?): Model?
	local found = if station then station:FindFirstChild("Hose") else nil
	if found and found:IsA("Model") and found.PrimaryPart ~= nil then
		return found
	end
	return nil
end

-- ── The session ────────────────────────────────────────────────────────

--- Aim the clock at one patch. Returns false when nothing is reachable, which is the
--- wall: the item is not ruined, it is waiting on a better cleaner or a better roll.
local function aim(session: Session, item: any, stats: any): boolean
	local patches = item.patches or {}

	-- The client names WHICH patch, by zone id, and this is the whole trust boundary:
	-- a zone that resolves to a reachable patch is honoured, anything else falls back
	-- to the easiest reachable one. A client picking its own order is not an exploit
	-- -- it could already do that by clicking a different row in the old panel -- but
	-- a client naming a patch its potency cannot touch would be, so
	-- `<= effectivePotency` is checked here and not taken on trust.
	local chosen: number? = nil
	local wantedIndex = if session.aimZone then table.find(session.zoneIds, session.aimZone) else nil
	if wantedIndex and patches[wantedIndex] and patches[wantedIndex] <= stats.effectivePotency then
		chosen = wantedIndex
	else
		local easiest = math.huge
		for index, hardness in patches do
			if hardness <= stats.effectivePotency and hardness < easiest then
				chosen, easiest = index, hardness
			end
		end
	end

	if chosen == nil then
		return false
	end

	local hardness = patches[chosen]
	session.hardness = hardness
	session.elapsed = 0
	session.target = Contamination.secondsFor(hardness, stats.scrubRate * stats.liquidRate)
	-- WHAT IS ACTUALLY BEING TIMED, as a zone id rather than an index that a later
	-- clear could shift out from under it. Left alone until the next lock (the next
	-- call to this function), regardless of where `aimZone` wanders in the meantime —
	-- see the field's own note on why `push` fades this one and not the live aim.
	session.lockedZone = session.zoneIds[chosen]
	return true
end

local function push(player: Player, session: Session?, data: any)
	if session == nil then
		stateRemote:FireClient(player, nil)
		return
	end

	local item = EconomyService.find(data, session.uid)
	if item == nil then
		return
	end

	local stats = StatResolver.get(data)
	local def = Items.get(item.itemId)
	local liquid = Liquids.get(stats.liquidId)

	-- Patch hardnesses go out as-is, tagged with the stable zone WashService built for
	-- them and the world point that zone's ball belongs at. They are the player's own
	-- item and the whole point of the bay is to SHOW them: a crusted blob that
	-- visibly repels the stream is the Quarantine Locker taught in three dimensions
	-- instead of in a red label.
	local patches = {}
	for index, hardness in item.patches or {} do
		local zoneId = session.zoneIds[index]
		table.insert(patches, {
			zone = zoneId,
			hardness = hardness,
			blocked = hardness > stats.effectivePotency,
			anchor = session.zoneAnchor[zoneId],
		})
	end

	local progress = if session.target > 0 then math.clamp(session.elapsed / session.target, 0, 1) else 0

	-- THE ZONE ACTUALLY BEING TIMED FADES WITH IT, so the payoff of a completed patch
	-- is a wipe building toward zero rather than a hard cut from full green to clean.
	-- `lockedZone`, not the player's live aim: see the field's own note.
	if session.lockedZone then
		local zone = session.zones[session.lockedZone]
		if zone then
			ItemGrime.applyParts(zone, 1 - progress)
		end
	end

	stateRemote:FireClient(player, {
		uid = session.uid,
		name = def.name,
		rarity = item.rarity,
		patches = patches,
		-- The player's own live aim, echoed straight back — not necessarily what is
		-- actually being timed (`lockedZone`), just what the reticle is currently
		-- reporting, which is what decides the reticle/blob "locked" look.
		targetZone = session.aimZone,
		progress = progress,
		liquidId = stats.liquidId,
		liquidName = liquid.name,
		liquidColor = liquid.color,
		potency = stats.effectivePotency,
		stand = session.stand,
		-- WHICH NOZZLE IS LIVE, and re-read every push rather than sent once at the
		-- start: a World.rebuild() from the command bar or a Cleaner purchase landing
		-- mid-session (Plots.setHoseTier) destroys the model this session opened with
		-- and parents a new one, and a client holding the old reference would spend
		-- the rest of the wash swivelling a freed instance.
		hose = if session.hose and session.hose.Parent then session.hose else stationHose(session.station),
		-- THE MACHINE'S `volume`, FOR THE PICTURE. It is already in the clock —
		-- `aim` divides by it through Contamination.secondsFor — and this is the same
		-- number sent so the stream can be drawn as thick as the rung is expensive.
		-- Sent raw, without the liquid's rateMult folded in: what the player bought is
		-- the machine, and a stream that fattened when a canister was loaded would be
		-- advertising the wrong purchase.
		volume = stats.scrubRate,
	})
end

function finish(player: Player, reason: string?)
	local session = sessions[player]
	if session == nil then
		return
	end
	sessions[player] = nil

	if session.model then
		session.model:Destroy()
	end

	-- RE-ENABLE THE PROMPT LAST, not first -- it was disabled the moment this session
	-- began (see begin()), specifically so it could never be clicked or pressed again
	-- while occupied. Restoring it here, once there is genuinely nothing left to
	-- interrupt, is what makes the NEXT wash startable at all.
	if session.prompt then
		session.prompt.Enabled = true
	end

	-- Step back off the mark, so ending a wash does not leave you standing inside the
	-- tub's prompt re-triggering it by accident.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if session.returnTo and root and root:IsA("BasePart") then
		root.CFrame = session.returnTo
	end

	stateRemote:FireClient(player, nil)
	if reason then
		resultRemote:FireClient(player, reason)
	end
end

--- Start a wash, or say why not. Every refusal names something the player can act on.
local function begin(player: Player, basin: BasePart): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	-- Should not be reachable at all: begin() disables this basin's prompt for the
	-- whole session (below), specifically so it cannot be re-triggered while occupied
	-- -- see the header on WHY that disable exists. Kept as a defensive no-op rather
	-- than an assert, in case a prompt somehow stays enabled through a race.
	if sessions[player] then
		return false, "already washing"
	end

	if data.heldUid == "" then
		return false, "hold something first \u{2014} pick it from your bag"
	end

	local item = EconomyService.find(data, data.heldUid)
	if item == nil then
		return false, "you aren't carrying that any more"
	end

	local patches = item.patches or {}
	local def = Items.get(item.itemId)
	if #patches == 0 then
		return false, `{def.name} is already clean`
	end

	local stats = StatResolver.get(data)
	local blocked = Contamination.blockedBy(patches, stats.effectivePotency)
	local reachable = false
	for _, hardness in patches do
		if hardness <= stats.effectivePotency then
			reachable = true
			break
		end
	end

	if not reachable and blocked then
		-- TWO CLEARLY-TYPED CLAUSES, and the old one-liner is why. It read "needs Acid
		-- Sponge, or Glacier Melt in the hose" -- a cleaning TOOL and a LIQUID named in
		-- one breath with nothing to say they were different kinds of thing, which is
		-- exactly the confusion that got reported. The liquid goes first because it is
		-- the thing a player standing next to a wash pad can act on in the next thirty
		-- seconds; the hose is named as the permanent fix.
		--
		-- THE TWO ARE HARDER TO TELL APART NOW THAT THE TOOL IS A HOSE TOO, which is
		-- why neither clause calls the liquid "the hose" any more: what is loaded is
		-- named on its own ("roll Glacier Melt at the pad") and the purchase is named
		-- by its rung, with no "tool" tacked on the end that would now read as a
		-- different object from the one already in your hands.
		local shortfall = blocked - stats.cleanPotency
		local rescue = Liquids.cheapestWithPotency(shortfall)
		if rescue then
			return false, `too tough \u{2014} roll {rescue.name} at the pad, or buy the {CarryService.hoseNameFor(blocked)}`
		end
		return false, `too tough \u{2014} needs the {CarryService.hoseNameFor(blocked)}; no liquid reaches this`
	end

	local stand = basin.Parent and basin.Parent:FindFirstChild("WashStand")
	if stand == nil or not stand:IsA("BasePart") then
		warn(`[wash] {basin:GetFullName()} has no WashStand sibling — rebuild the world`)
		return false, "this station is broken"
	end

	-- ONE WASH PER STATION. There is one stand to put an item on and one monitor to
	-- point, so a second player starting here would stack their item inside the first
	-- player's and fight them for the aim. The monitor is scarce again, incidentally:
	-- when every player was handed their own copy in their own hand only the stand was,
	-- and now that the nozzle is a fixture it is back to being a thing two people
	-- cannot both use. The prompt disable below only stops the OCCUPANT re-triggering
	-- it; this is what stops a visitor.
	for other, active in sessions do
		if other ~= player and active ~= nil and active.stand == stand then
			return false, `{other.DisplayName} is using this station`
		end
	end

	local spot = basin.Parent and basin.Parent:FindFirstChild("WashSpot")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	local prompt = basin:FindFirstChild("Wash")

	local session: Session = {
		uid = item.uid,
		stand = stand,
		-- Held rather than re-derived from `stand.Parent` on the way out: a
		-- World.rebuild() mid-session orphans the stand, and `push` still has to be
		-- able to find the station's replacement nozzle to tell the client about.
		station = stand.Parent,
		prompt = if prompt and prompt:IsA("ProximityPrompt") then prompt else nil,
		returnTo = if root and root:IsA("BasePart") then root.CFrame else nil,
		model = nil,
		hose = nil,
		spraying = false,
		aimZone = nil,
		elapsed = 0,
		target = 0,
		hardness = 0,
		lockedZone = nil,
		zones = {},
		zoneAnchor = {},
		zoneIds = {},
	}

	-- BUILT BEFORE THE FIRST `aim`, not after: `aim` locks its target by translating
	-- into a zone id (`session.zoneIds[chosen]`), which only means anything once the
	-- zones themselves exist. `reachable` was already confirmed above, so this is not
	-- spent on a session that is about to refuse anyway.
	session.model, session.zones, session.zoneAnchor = placeOnStand(stand, item)
	for i = 1, #patches do
		session.zoneIds[i] = i
	end

	if not aim(session, item, stats) then
		if session.model then
			session.model:Destroy()
		end
		return false, "nothing you can shift here"
	end

	session.hose = stationHose(session.station)
	sessions[player] = session

	-- DISABLE THE PROMPT FOR THE DURATION. Roblox's default ProximityPrompt widget can
	-- be triggered by a MOUSE CLICK on its on-screen icon, not only the keyboard key --
	-- and the player is about to spend the whole session clicking to spray, often
	-- toward wherever this same prompt happens to render once the camera cuts to the
	-- first-person wash shot. Left enabled, aiming the hose doubles as an accidental "press
	-- E again" that ends the session out from under you. WashController's own E/Q
	-- keyboard listener is the real, deliberate exit now; re-enabled in finish().
	if session.prompt then
		session.prompt.Enabled = false
	end

	-- PLANT THEM ON THE MARK, FACING THE TUB. The shot is first person from the
	-- player's own head, aimed down the line from there to the item on the stand
	-- (WashController), so it is only the right picture if the player is actually
	-- standing where the geometry says and looking the way it says. Approaching from
	-- an angle and being left there is what produced "a weird view where nothing
	-- happens" back when the camera was a fixed side-on shot.
	--
	-- STEPPED FORWARD OFF THE MARK, and the offset is here rather than in the WashSpot
	-- geometry on purpose. WashSpot was placed six studs back to compose a side-on
	-- shot that had to fit BOTH the player and the item in one frame; standing in
	-- first person you want to be AT the tub, close enough that a half-stud patch is a
	-- target rather than a speck. Moving the anchor itself would only take effect on
	-- places that have been through a World.rebuild(), and a change that silently does
	-- nothing until someone runs a command is worse than a line of arithmetic. -Z is
	-- forward in WashSpot's own frame, which is already aimed at the stand.
	if spot and spot:IsA("BasePart") and root and root:IsA("BasePart") then
		root.CFrame = spot.CFrame * CFrame.new(0, 0, -APPROACH)
	end

	push(player, session, data)

	return true, `washing {def.name} with {Liquids.get(stats.liquidId).name}`
end

-- ── Tick ───────────────────────────────────────────────────────────────

local function stepPlayer(player: Player, dt: number)
	local session = sessions[player]
	if session == nil then
		return
	end

	local data = DataService.data(player)
	if data == nil then
		finish(player)
		return
	end

	local item = EconomyService.find(data, session.uid)
	if item == nil then
		finish(player, "that item left your bag")
		return
	end

	-- The leash. Walking away IS how you back out; there is no cancel button, because
	-- there is no panel left to put one on.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		finish(player)
		return
	end
	if (root.Position - session.stand.Position).Magnitude > LEASH then
		finish(player, "stepped away from the tub")
		return
	end

	local stats = StatResolver.get(data)

	if session.spraying then
		session.elapsed += dt
		if session.elapsed >= session.target then
			local cleared, removedIndex = Contamination.clearOne(item.patches, stats.effectivePotency)
			if cleared then
				-- Partial progress pays. PLAN §2: a failed clean is never wasted.
				data.xp += math.floor(cleared * XP_PER_HARDNESS * stats.liquidXp + 0.5)
				-- ONE CHARGE PER PATCH, and this is the only site that spends one.
				-- Charged for the patch that came OFF rather than for starting, which
				-- is the only version that survives someone disconnecting halfway
				-- through a Legendary.
				LiquidService.spendCharge(data)
				-- RE-RESOLVE. The line above can have just emptied the canister and
				-- dropped the player to Plain Water; `stats` was captured at the top of
				-- this tick, so the next patch would otherwise be timed at the spent
				-- liquid's rate and cleared against its potency — a free extra patch at
				-- Stardust speed, every time a canister runs dry.
				stats = StatResolver.get(data)

				-- THE GREEN COMES OFF WHERE IT WAS SPRAYED. `removedIndex` is where
				-- `item.patches` just shrank; `zoneIds` shrinks at the exact same index
				-- in the exact same call, so this is still the zone that patch owned no
				-- matter how many earlier clears have already shifted the array. This is
				-- the payoff the whole feature exists for: a real area of the real
				-- object turns clean, live, one blast at a time.
				local zoneId = if removedIndex then table.remove(session.zoneIds, removedIndex) else nil
				if zoneId and session.zones[zoneId] then
					ItemGrime.clearParts(session.zones[zoneId])
				end
			end

			if #item.patches == 0 then
				data.stats.itemsCleaned += 1
				finish(player, `{Items.get(item.itemId).name} is clean`)
				return
			end
			if not aim(session, item, stats) then
				finish(player, "that's as far as this liquid goes")
				return
			end
		end
	end

	push(player, session, data)
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

local function wireTub(basin: Instance)
	if not basin:IsA("BasePart") or basin:GetAttribute("StationKind") ~= "decon" then
		return
	end
	local prompt = basin:FindFirstChild("Wash")
	if prompt == nil or not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt.Triggered:Connect(function(player: Player)
		local ok, message = begin(player, basin)
		resultRemote:FireClient(player, message)
		if ok then
			print(`[wash] {player.Name}: {message}`)
		end
	end)
end

function WashService.init()
	stateRemote = Net.get("WashState")
	inputRemote = Net.get("WashInput")
	resultRemote = Net.get("StationResult")
end

function WashService.start()
	-- Tag-indexed like every other world scan in this codebase, and it covers tubs
	-- that appear LATER: World.rebuild() can be run from the command bar mid-session.
	for _, part in CollectionService:GetTagged("Station") do
		wireTub(part)
	end
	CollectionService:GetInstanceAddedSignal("Station"):Connect(wireTub)

	inputRemote.OnServerEvent:Connect(function(player: Player, request: any)
		local session = sessions[player]
		if session == nil or type(request) ~= "table" then
			return
		end
		if request.stop == true then
			-- The keyboard escape hatch. The prompt re-press is the discoverable exit;
			-- this is the one that works even if the prompt is somehow not showing,
			-- because "stuck in a camera with no way out" must not be reachable by any
			-- route at all.
			finish(player, "stopped washing")
			return
		end
		session.spraying = request.spraying == true
		session.aimZone = if type(request.zone) == "number" then request.zone else nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- STRAIGHT THROUGH finish(), rather than the hand-rolled teardown that used to
		-- live here. Back when the nozzle was handed over, that hand-rolled version
		-- destroyed the model on the tub and left the station's own hose stashed out of
		-- the tree — no nozzle at all for whoever arrived next. The nozzle never moves
		-- now, so there is less to get wrong, but the rule that produced the bug stands:
		-- one teardown, one place.
		--
		-- No toast: they are gone. Passing no reason is what suppresses it, and the
		-- state remote firing at a player who has left is a no-op.
		finish(player)
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player, dt)
			if not ok then
				warn(`[wash] tick failed for {player.Name}: {err}`)
			end
		end
	end)
end

return WashService
