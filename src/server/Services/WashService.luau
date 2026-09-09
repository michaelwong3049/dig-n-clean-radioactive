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
	  · THE PATCHES ARE PLACES, and now they are OBJECTS: one chunk of irradiated slag
	    per patch, wrapped around the item (`placeOnStand`, Shared/ItemCrust). They were
	    round-robin slices of the part list once, then spatial clusters of the item's own
	    geometry; they are real rock over the top of it now.

	AND TAKING IT OFF IS THE REVEAL. What goes in the tub is a "???" — an item comes out
	of the ground encased and nothing in the game will name it until the crust is gone
	(Services/IdentifyService). Every chunk that breaks off uncovers part of what is
	underneath, the last one uncovers the rest, and the bay stands there for a beat with
	the thing finally being itself before handing it back. That is why this file is now
	where the index gets written and where the banner gets fired: the wash is not a
	chore between the dig and the sale any more, it is the payoff of the dig.

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
local ItemCrust = require(Shared.ItemCrust)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local CarryService = require(script.Parent.CarryService)
local IdentifyService = require(script.Parent.IdentifyService)
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
	-- Last erosion level actually written to each zone's chunk, so `push` can skip the
	-- per-part property writes on the zones that have not moved this tick -- which,
	-- once every zone erodes independently, is nearly all of them. `walled` is the same
	-- guard for the other thing a chunk renders: whether this liquid can shift it.
	painted: { [number]: number },
	walled: { [number]: boolean },
	-- The zone the water is on RIGHT NOW and which therefore took this tick's dt: the
	-- resolved, potency-checked form of `aimZone`, recomputed every tick. Nil when the
	-- player is spraying at nothing, at a blocked patch, or not spraying at all.
	lockedZone: number?,
	-- The last patch is off and the item is standing revealed on the stand. The tick
	-- does nothing at all while this is set: the session is over in every way except
	-- that the player is still looking at it.
	revealing: boolean,
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

--- WHAT SITS ON THE TUB IS THE ITEM, WRAPPED IN ROCK. Server-side, so everyone on the
--- base sees it: the spray VFX is client-local (see WashController) because it is
--- per-viewer motion, but the OBJECT is the storytelling — a stranger walking onto your
--- plot should see something being washed, not an empty bath and someone miming.
---
--- ONE CHUNK OF CRUST PER PATCH (Shared/ItemCrust). Those chunks ARE the zones: the
--- thing you point the hose at is a lump of slag on a real side of a real object, it
--- erodes while the water is on it, and when its patch finally pops it comes off and
--- the item shows through the gap. Six patches is six chunks and six stages of reveal.
---
--- THIS REPLACED A SPATIAL CLUSTERING OF THE ITEM'S OWN PARTS, and the reason is worth
--- keeping. Zones used to be k-means buckets of the model's real geometry, tinted green
--- and faded back to the authored colour as they soaked — which was a genuinely better
--- picture than the round-robin slices before it, and still could not do the one thing
--- now being asked of it: hide what the item IS. Colour cannot, because shape is
--- identity. Real geometry over the top can, and it brings its own aiming targets with
--- it, so the clustering, the Lloyd relaxation, the empty-zone rescue and the
--- stand-in block cluster for unmodelled items all went with it.
---
--- Returns the display model, one zone per patch, and each zone's world anchor.
local function placeOnStand(stand: BasePart, item: any): (Model, { [number]: { BasePart } }, { [number]: Vector3 })
	local count = math.max(#(item.patches or {}), 1)
	local def = Items.get(item.itemId)
	local model = ItemModels.create(def.model)

	if model == nil then
		-- The same rarity-coloured block ToolService's off hand and ExhibitService's
		-- pedestals fall back to for an item with no authored art. It is under the crust
		-- like anything else, so the reveal still lands — it just reveals a cube.
		model = Instance.new("Model")
		local block = Instance.new("Part")
		block.Name = "Placeholder"
		block.Size = Vector3.new(1.1, 1.1, 1.1)
		block.Color = Rarity.get(item.rarity).color
		block.Material = Enum.Material.SmoothPlastic
		block.Parent = model
		model.PrimaryPart = block
	end

	local built = model :: Model
	built.Name = "WashItem"
	for _, part in built:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	built.Parent = stand
	built:PivotTo(stand.CFrame * ItemModels.rotation(built, "Wash"))

	-- ENCASED AFTER THE PIVOT, not before: the crust is built around the model's
	-- bounding box in world space, and wrapping it first would leave the rock behind
	-- when the item moved onto the stand.
	local zones, anchors = ItemCrust.encase(built, count, item.rarity, item.uid)

	for zone = 1, count do
		-- WHICH DIRTY AREA THIS PIECE OF SLAG BELONGS TO, written onto the real geometry
		-- so the client can answer "what did the water just hit" by reading the part its
		-- own impact ray returned, instead of guessing from proximity to a ball. An
		-- attribute rather than a remote because it is per-part, static for the life of
		-- the session, and replicates for free; and it is authoritative only as a LABEL --
		-- the client reports the zone it read, and `workedIndex` still checks that zone
		-- against the potency gate before a single tick counts.
		for _, part in zones[zone] or {} do
			part:SetAttribute("WashZone", zone)
		end
	end

	return built, zones, anchors
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
		local blocked = hardness > stats.effectivePotency
		table.insert(patches, {
			zone = zoneId,
			hardness = hardness,
			blocked = blocked,
			anchor = session.zoneAnchor[zoneId],
			soak = soak,
		})

		-- EVERY CHUNK ERODES ON ITS OWN BANK, not just the one under the stream. Guarded
		-- on a real change because this is a loop over every patch on every tick and
		-- ItemCrust.erode writes four properties per part: at ten hertz across three
		-- pieces a chunk that is a lot of writes to set values that already hold.
		--
		-- BLOCKED IS IN THE GUARD ALONGSIDE THE LEVEL, because it moves on its own: a
		-- canister running dry mid-session (LiquidService.spendCharge, below) drops the
		-- player's potency and turns chunks they were shifting into chunks they are not,
		-- with nothing about their soak having changed.
		local level = 1 - soak
		if math.abs((session.painted[zoneId] or -1) - level) > 0.01 or session.walled[zoneId] ~= blocked then
			session.painted[zoneId] = level
			session.walled[zoneId] = blocked
			ItemCrust.erode(session.zones[zoneId] or {}, level, blocked)
		end
	end

	stateRemote:FireClient(player, {
		uid = session.uid,
		-- NO NAME. It used to ride along here for a label the bay never grew, and under
		-- the crust it would be the answer to the session's own question sitting in the
		-- client's memory for the whole wash. The reveal is a remote of its own
		-- (Net.ItemIdentified), fired once, after the last chunk comes off.
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

--- How long the item stands there, clean and finally itself, before the session hands
--- the screen back. Long enough to read what came out of the rock and short enough that
--- it is a beat rather than a wait.
local REVEAL_HOLD = 1.3

--- THE LAST CHUNK IS OFF, SO THE MYSTERY IS OVER. This is the moment the whole feature
--- is built around: what went into the tub was a "???" in the bag and a lump of slag on
--- the stand, and what comes out has a name.
---
--- THE ORDER HERE IS THE POINT.
---   1. the index is written IMMEDIATELY (IdentifyService.identify). A player who
---      disconnects during the beat below must not come back holding a clean item their
---      catalogue has never heard of.
---   2. one last push with an empty patch list, so the client drops its reticle lock and
---      the player spends the beat looking at the object rather than at a target.
---   3. the light goes out. Nothing is hiding any more, so the fallout glow the crust
---      carried has nothing left to be coming off of.
---   4. THEN the beat, and only after it the banner -- WashController hides every
---      LayerCollector for the first-person view, so a reveal announced before `finish`
---      is a reveal announced onto a hidden screen.
local function revealAndFinish(player: Player, session: Session, data: any, item: any)
	session.revealing = true
	session.spraying = false
	session.lockedZone = nil
	session.aimZone = nil

	local first = IdentifyService.identify(player, item)
	push(player, session, data)
	if session.model then
		ItemCrust.clear(session.model)
	end

	local def = Items.get(item.itemId)
	task.delay(REVEAL_HOLD, function()
		-- The session this beat belongs to, not merely "a session": a player who left and
		-- came back inside 1.3 seconds would otherwise have someone else's reveal end
		-- their new wash.
		if sessions[player] ~= session then
			return
		end
		finish(player, `{def.name} is clean`)
		IdentifyService.announce(player, item, first)
	end)
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
		walled = {},
		lockedZone = nil,
		revealing = false,
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

	-- NAMES THE LIQUID, NOT THE ITEM. Whatever is under the crust is exactly what this
	-- session exists to find out, and the toast that opens it must not answer it.
	return true, `washing with {Liquids.get(stats.liquidId).name}`
end

-- ── Tick ───────────────────────────────────────────────────────────────

local function stepPlayer(player: Player, dt: number)
	local session = sessions[player]
	if session == nil then
		return
	end

	-- The reveal beat owns the last second and a half of a session (revealAndFinish):
	-- the item is clean, the crust is gone and the only thing left to happen is the
	-- player looking at it. Nothing here has anything to add, and the leash check below
	-- would happily end the session out from under the beat.
	if session.revealing then
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

					-- THE CRUST COMES OFF WHERE IT WAS SPRAYED, and a piece of the item
					-- underneath is uncovered with it. `removedIndex` is where `item.patches`
					-- just shrank; `zoneIds` shrinks at the exact same index in the exact same
					-- call, so this is still the zone that patch owned no matter how many
					-- earlier clears have already shifted the array. This is the payoff the
					-- whole feature exists for: the chunk of slag you were pointing at breaks
					-- off, live, under the stream, and the thing inside starts to be a thing.
					table.remove(session.zoneIds, removedIndex)
					if session.zones[zoneId] then
						ItemCrust.strip(session.zones[zoneId])
						session.zones[zoneId] = nil
					end
					-- The bank and the paint cache go with the patch. Nothing re-uses a zone
					-- id within a session, but a stale entry would keep `push` skipping the
					-- writes for a zone that no longer exists, which is the kind of thing that
					-- only bites once someone adds re-contamination.
					session.soaked[zoneId] = nil
					session.painted[zoneId] = nil
					session.walled[zoneId] = nil
					session.lockedZone = nil
					-- The stream is now standing on bare metal. The client's next report is
					-- what re-aims it, and until then nothing accrues anywhere.
					session.aimZone = nil
				end

				if #item.patches == 0 then
					data.stats.itemsCleaned += 1
					revealAndFinish(player, session, data, item)
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
