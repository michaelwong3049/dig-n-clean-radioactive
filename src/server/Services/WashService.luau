--!strict
--[[
	WashService.lua — the hose. Hold the thing, press E at the tub, blast it clean.

	THIS IS PLAN §2 STEP 4 AS ORIGINALLY WRITTEN. The design asked for "a skill
	mini-interaction, not a progress bar", and §16 hedged that if it did not work, fall
	back to a hold-to-clean bar with the potency gate. We shipped the fallback and
	lived with it for a while: you held a button on a panel and an item you could not
	see got cleaner. This is the version that was actually asked for.

	THE MATHS DID NOT CHANGE. Not one number. `Contamination.secondsFor`, the
	effective-potency gate and one charge per cleared patch are lifted from
	DeconService's old scrub tick untouched. What changed is who drives the clock and
	what the player is looking at while it runs. That is deliberate: a feel change that
	also moves the balance is two changes wearing one commit, and there would be no way
	to tell which one broke the economy.

	AIM IS THE GAME, AND FOR A WHILE IT WAS NOT. The first version of this file shipped
	with a clock that ran on a held trigger: `aim` picked the easiest reachable patch
	whenever the client named none, the tick added dt on `spraying` alone, and the lock
	only moved when a patch popped. Point the hose at the sky, hold the button, and the
	item cleaned itself — the stream was decoration over a progress bar with extra
	steps. Three things fix it and they only work together:

	  · WHAT THE WATER IS ON is resolved every tick (`workedIndex`), and there is no
	    fallback. Nothing under the stream means no second is banked anywhere.
	  · THE BANK IS PER ZONE (`session.soaked`), so the clock follows the reticle
	    instead of holding one target hostage until it finishes. Sweeping is allowed;
	    the seconds still have to go in somewhere.
	  · THE PATCHES ARE PLACES (`zonesFromModel`). They used to be round-robin slices
	    of the part list, so every zone's centroid was the middle of the model and there
	    was no "that corner" to point at. They are spatial clusters now.

	THE BOUNDARY IS THE SAME ONE THE SCRUB TIMER HAD. The client reports AIM and
	INTENT — "I am spraying, and the water is landing on zone 3" — and never progress.
	The server owns the clock, the patch list, the charges and the XP. A client that
	lies about aim picks a different patch to work on, which it could already do by
	clicking a different row in the panel this replaced; a client that could report
	progress would clean an Anomaly instantly. The zone id the client sends is read off
	a `WashZone` attribute this service stamped on the real geometry, and it is still
	re-checked against the potency gate here before a single tick counts.

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
	-- clearing elsewhere and the array compacting), never an array index. This is WHERE
	-- THE WATER IS LANDING, reported by WashController from the jet's own impact
	-- raycast, and nil whenever the stream is not on a dirty area at all. Echoed
	-- straight back in `push` as `targetZone`; `workedIndex` is what turns it into the
	-- array index the clock is allowed to run against.
	aimZone: number?,
	-- SECONDS OF WATER EACH ZONE HAS TAKEN, banked by zone id so it survives both the
	-- player looking away and every other patch clearing out from under the array.
	-- There is no single `elapsed`/`target` pair any more: the old one belonged to a
	-- lock that only moved when a patch popped, which is exactly why aim did not
	-- matter. A zone's entry is cleared when its patch comes off.
	soaked: { [number]: number },
	-- Last grime level actually written to each zone's parts, so `push` can skip the
	-- per-part property writes on the zones that have not moved this tick -- which,
	-- once every zone is faded independently, is nearly all of them.
	painted: { [number]: number },
	-- The zone the water is on RIGHT NOW and which therefore took this tick's dt: the
	-- resolved, potency-checked form of `aimZone`, recomputed every tick. Nil when the
	-- player is spraying at nothing, at a blocked patch, or not spraying at all.
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

--- `count` seed points spread through a bounding box, on the golden-angle spiral —
--- the same construction `zoneAnchor` falls back to, kept identical so a zone with no
--- geometry at all still lands somewhere sensible relative to the ones that have some.
local function spiralSeeds(pivot: CFrame, size: Vector3, count: number): { Vector3 }
	local golden = 2.39996323
	local seeds = {}
	for index = 1, count do
		local t = (index - 0.5) / math.max(count, 1)
		local y = 1 - 2 * math.min(t, 1)
		local radius = math.sqrt(math.max(0, 1 - y * y))
		local theta = golden * index
		local dir = Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
		-- 0.6 rather than 0.5: pulled in off the surface so the seeds sit inside the
		-- object's own material rather than out on the shell, which is where the parts
		-- they have to claim actually are.
		seeds[index] = (pivot * CFrame.new(dir * size * 0.6)).Position
	end
	return seeds
end

--- Bucket a sculpted model's real paintable parts into `count` zones BY WHERE THEY ARE
--- — one per patch, each a contiguous region of the actual object.
---
--- IT USED TO BE ROUND-ROBIN, and that was a defensible call for as long as a patch
--- was a number on a panel: scattering each zone across the whole part list made every
--- clear read as the WHOLE item getting a little cleaner, which is what the old
--- aggregate fade looked like and so was the change nobody had to relearn. GoldRing's
--- forty near-identical band segments were the case it was chosen for — a contiguous
--- chunk of those clearing reads as a bite taken out of the band.
---
--- IT IS ALSO WHY AIMING NEVER MATTERED. Round-robin makes every zone's centroid the
--- same point — the middle of the model — so the balls all stacked in one place, any
--- ray that touched the item was within reach of all of them, and "point at the dirty
--- bit" had no dirty bit to point at. A bite out of the band is the price of the hose
--- being a hose. You are meant to be able to see which corner you have not done yet.
---
--- LLOYD, TWICE. Nearest-seed alone against a fixed spiral leaves lopsided zones on a
--- model whose parts are not evenly spread (a ring is a hoop of geometry around a lot
--- of nothing); two relaxation passes move each seed onto its own claim's centroid and
--- re-deal, which is enough to even them out without turning this into a real solver.
--- `rescueEmpty` then guarantees the postcondition the rest of the file assumes: every
--- zone owns at least one part, so every patch has somewhere to be sprayed.
local function zonesFromModel(model: Model, count: number): { [number]: { BasePart } }
	local zones: { [number]: { BasePart } } = {}
	for zone = 1, count do
		zones[zone] = {}
	end

	local parts: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and isPaintable(part) then
			table.insert(parts, part)
		end
	end
	if #parts == 0 then
		return zones
	end

	local pivot, size = model:GetBoundingBox()
	local seeds = spiralSeeds(pivot, size, count)

	local owner: { number } = table.create(#parts, 1)
	for pass = 1, 3 do
		for i, part in parts do
			local best, bestDistance = 1, math.huge
			for zone = 1, count do
				local distance = (seeds[zone] - part.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = zone, distance
				end
			end
			owner[i] = best
		end

		if pass == 3 then
			break
		end

		-- Re-seed onto each claim's own centre of mass. A zone nobody picked keeps the
		-- seed it had, so it is still in the running next pass rather than collapsing
		-- onto whatever the last one was.
		local sums = table.create(count, Vector3.zero)
		local counts = table.create(count, 0)
		for i, part in parts do
			local zone = owner[i]
			sums[zone] += part.Position
			counts[zone] += 1
		end
		for zone = 1, count do
			if counts[zone] > 0 then
				seeds[zone] = sums[zone] / counts[zone]
			end
		end
	end

	for i, part in parts do
		table.insert(zones[owner[i]], part)
	end

	-- EVERY ZONE OWNS SOMETHING, or a patch exists with no geometry to spray. Each
	-- empty zone takes the part FURTHEST from its own zone's seed out of the biggest
	-- zone: the piece that fits worst where it is, which is also the piece whose
	-- leaving disturbs the shape of the donor least. Bounded by `count` and only
	-- reachable on models with fewer paintable parts than patches, which is the case
	-- the fallback in `zoneAnchor` was written for.
	for zone = 1, count do
		if #zones[zone] == 0 then
			local donor, donorCount = nil, 1
			for other = 1, count do
				if #zones[other] > donorCount then
					donor, donorCount = other, #zones[other]
				end
			end
			if donor == nil then
				break
			end
			local worst, worstDistance = 1, -1
			for index, part in zones[donor] do
				local distance = (seeds[donor] - part.Position).Magnitude
				if distance > worstDistance then
					worst, worstDistance = index, distance
				end
			end
			local taken = table.remove(zones[donor], worst)
			if taken then
				table.insert(zones[zone], taken)
				seeds[zone] = taken.Position
			end
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
		-- WHICH DIRTY AREA THIS PIECE OF THE OBJECT BELONGS TO, written onto the real
		-- geometry so the client can answer "what did the water just hit" by reading the
		-- part its own impact ray returned, instead of guessing from proximity to a ball.
		-- An attribute rather than a remote because it is per-part, static for the life of
		-- the session, and replicates for free; and it is authoritative only as a LABEL --
		-- the client reports the zone it read, and `workedIndex` still checks that zone
		-- against the potency gate before a single tick counts.
		for _, part in zones[zone] do
			part:SetAttribute("WashZone", zone)
		end
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

--- How long one patch takes under this player's current machine and canister. Pulled
--- out because `stepPlayer` needs it for the zone taking water and `push` needs it for
--- every other zone's banked fraction, and the two disagreeing by so much as a
--- rounding is a fade that stops at 0.98 of clean.
local function soakTarget(hardness: number, stats: any): number
	return Contamination.secondsFor(hardness, stats.scrubRate * stats.liquidRate)
end

--- Which patch the water is ACTUALLY ON, as an index into `item.patches`, or nil.
---
--- THE OLD `aim` FELL BACK TO THE EASIEST REACHABLE PATCH when the client named
--- nothing, and that one clause is the whole reason an item cleaned itself while you
--- sprayed at the sky: no aim meant "pick something for them", and the tick then
--- charged the clock for it regardless. There is no fallback now. Nothing under the
--- stream is a real and meaningful answer — you are watering the tub — and the caller
--- banks nothing for it.
---
--- THE TRUST BOUNDARY IS UNCHANGED, and is why this lives on the server. The client
--- names WHICH zone, which it could always do; it may not name a patch its potency
--- cannot shift, so `<= effectivePotency` is checked here rather than taken on faith.
--- A blocked patch under the stream is the crusted one visibly repelling the water,
--- and it banks nothing either.
local function workedIndex(session: Session, item: any, stats: any): number?
	if session.aimZone == nil then
		return nil
	end
	local index = table.find(session.zoneIds, session.aimZone)
	if index == nil then
		return nil
	end
	local hardness = (item.patches or {})[index]
	if hardness == nil or hardness > stats.effectivePotency then
		return nil
	end
	return index
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
	-- them, the world point that zone's ball belongs at, and HOW WET IT ALREADY IS.
	-- They are the player's own item and the whole point of the bay is to SHOW them: a
	-- crusted blob that visibly repels the stream is the Quarantine Locker taught in
	-- three dimensions instead of in a red label.
	--
	-- `soak` IS PER PATCH NOW, AND IT IS THE FEATURE. One shared `progress` belonged to
	-- a single lock that only moved when a patch popped; with the clock following the
	-- water, every area carries its own bank, and sending all of them is what lets the
	-- player look around the object and see which corners they have half-done and which
	-- they have not touched.
	local patches = {}
	for index, hardness in item.patches or {} do
		local zoneId = session.zoneIds[index]
		local target = soakTarget(hardness, stats)
		local soak = if target > 0 then math.clamp((session.soaked[zoneId] or 0) / target, 0, 1) else 0
		table.insert(patches, {
			zone = zoneId,
			hardness = hardness,
			blocked = hardness > stats.effectivePotency,
			anchor = session.zoneAnchor[zoneId],
			soak = soak,
		})

		-- EVERY ZONE FADES ON ITS OWN BANK, not just the one under the stream. Guarded on
		-- a real change because this is now a loop over every patch on every tick, and
		-- ItemGrime.applyParts writes two properties per part: at ten hertz across a
		-- forty-segment ring that is a lot of writes to set values that already hold.
		local level = 1 - soak
		if math.abs((session.painted[zoneId] or -1) - level) > 0.01 then
			session.painted[zoneId] = level
			ItemGrime.applyParts(session.zones[zoneId] or {}, level)
		end
	end

	stateRemote:FireClient(player, {
		uid = session.uid,
		name = def.name,
		rarity = item.rarity,
		patches = patches,
		-- NEITHER `targetZone` NOR A WORKED-ZONE ECHO IS SENT ANY MORE. Both were the
		-- client's own aim coming back to it a tick late, and the client had it exactly
		-- right sixty times a second: `patchAt` resolves the zone from the impact ray, and
		-- `blocked` on each patch below is everything else needed to decide whether that
		-- zone is one the water can actually shift. A ten-hertz echo driving a reticle
		-- that renders at sixty is a reticle that lags the crosshair it is drawn on.
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
		soaked = {},
		painted = {},
		lockedZone = nil,
		zones = {},
		zoneAnchor = {},
		zoneIds = {},
	}

	-- `reachable` was already confirmed above, so this is not spent building geometry
	-- for a session that is about to refuse anyway.
	--
	-- THERE IS NO OPENING `aim` ANY MORE, and its refusal ("nothing you can shift
	-- here") went with it. That call was the belt to `reachable`'s braces — the same
	-- potency question asked twice, once through a function whose real job was to start
	-- a clock. Nothing is timed until the player points the hose at something, so there
	-- is nothing left to prime here.
	session.model, session.zones, session.zoneAnchor = placeOnStand(stand, item)
	for i = 1, #patches do
		session.zoneIds[i] = i
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

	-- WHAT THE WATER IS ON, RESOLVED FRESH EVERY TICK. This is the change the whole
	-- rework turns on. It used to be a lock set once and left alone until a patch
	-- popped, with a fallback that picked a patch for you when you were aiming at
	-- nothing — so the clock ran on a held trigger alone, an item cleaned itself while
	-- you sprayed at the tub, and moving the reticle mid-patch did nothing at all.
	-- Now: no water on a dirty area, no time spent.
	session.lockedZone = nil
	if session.spraying then
		local index = workedIndex(session, item, stats)
		if index then
			local zoneId = session.zoneIds[index]
			local hardness = item.patches[index]
			session.lockedZone = zoneId

			-- BANKED, NOT RESET. Sweeping the stream across the object is how anyone
			-- actually washes something, and a bank that emptied the moment you looked
			-- away would make the only viable technique "stare at one spot and never
			-- move". You still have to put the seconds into every area — the total work is
			-- identical — you just get to put them in in whatever order you like.
			local soaked = (session.soaked[zoneId] or 0) + dt
			session.soaked[zoneId] = soaked

			if soaked >= soakTarget(hardness, stats) then
				-- THE PATCH THAT COMES OFF IS THE ONE THE WATER WAS ON, named by index.
				-- `clearOne` used to pick the easiest patch itself, which was invisible
				-- while there was one shared clock and plainly wrong once there are six
				-- independent ones: you would finish eight seconds of work on a crusted
				-- corner and watch an easy patch on the far side pop instead.
				local cleared, removedIndex = Contamination.clearAt(item.patches, index, stats.effectivePotency)
				if cleared and removedIndex then
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
					-- the payoff the whole feature exists for: the real area of the real
					-- object you were pointing at turns clean, live, under the stream.
					table.remove(session.zoneIds, removedIndex)
					if session.zones[zoneId] then
						ItemGrime.clearParts(session.zones[zoneId])
					end
					-- The bank and the paint cache go with the patch. Nothing re-uses a zone
					-- id within a session, but a stale entry would keep `push` skipping the
					-- writes for a zone that no longer exists, which is the kind of thing that
					-- only bites once someone adds re-contamination.
					session.soaked[zoneId] = nil
					session.painted[zoneId] = nil
					session.lockedZone = nil
					-- The stream is now standing on bare metal. The client's next report is
					-- what re-aims it, and until then nothing accrues anywhere.
					session.aimZone = nil
				end

				if #item.patches == 0 then
					data.stats.itemsCleaned += 1
					finish(player, `{Items.get(item.itemId).name} is clean`)
					return
				end
				-- THE WALL, asked as its own question now rather than inferred from `aim`
				-- failing to find a target. It has to stay decoupled from where the player
				-- happens to be pointing: aiming at nothing is an ordinary thing to be doing
				-- for a second, and it must not read as "this liquid is finished".
				if not Contamination.anyReachable(item.patches, stats.effectivePotency) then
					finish(player, "that's as far as this liquid goes")
					return
				end
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
