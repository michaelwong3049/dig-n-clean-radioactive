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

	THE HOSE IS AN OBJECT, NOT AN EFFECT. It is built with the station
	(build/Plots.buildHoseRig): a pump, a reel of green hose, and a brass-tipped
	nozzle parked on the cap. Starting a wash hands the player a CLONE of that nozzle,
	welded into their right hand exactly the way ToolService welds a tool, stashes the
	parked original, and re-points the reel's Beam at the copy — so the green line
	runs from the drum to whatever the player is holding, on every client, with no
	per-frame code anywhere. Ending a wash puts all three back.

	The ordinary Cleaner tool steps aside for the duration (ToolService.wanted), or the
	player would be holding a sponge and a fire hose in the same hand.
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

--- How the nozzle sits in the hand. `-Y` is down the arm on both rigs, so rotating
--- the nozzle's own forward axis (`-Z`, the axis CFrame.lookAt aims down) onto it is
--- what puts the brass end pointing away from the body rather than into the player's
--- own elbow. Only the first frame and other people's screens ever see this pose --
--- WashController re-aims it at whatever the player is pointing at from then on.
local HOSE_HOLD = CFrame.new(0, -0.7, 0) * CFrame.Angles(math.rad(-90), 0, 0)

type Session = {
	uid: string,
	stand: BasePart,
	station: Instance?,
	prompt: ProximityPrompt?,
	returnTo: CFrame?,
	model: Instance?,
	-- The hose, in three pieces: the copy in the player's hand, the station's own
	-- nozzle parked out of the tree for the duration, and the reel's Beam whose far
	-- end swings between the two. All three move together; see takeHose/stowHose.
	hose: Model?,
	parked: Model?,
	line: Beam?,
	-- The line's CurveSize pair as it was PARKED, packed into a Vector2 (X = 0, Y = 1)
	-- so it is one field rather than two. Restored on the way out.
	parkedCurve: Vector2?,
	spraying: boolean,
	patchIndex: number?,
	elapsed: number,
	target: number,
	hardness: number,
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

--- SERVER-SIDE, so everyone on the base sees the thing being washed. The spray VFX
--- is client-local (see WashController) because it is per-viewer motion, but the
--- OBJECT is the storytelling — a stranger walking onto your plot should see a Gold
--- Ring sitting in your tub, not an empty bath and someone miming.
---
--- Same rarity-coloured-block fallback as ToolService's off hand, DigService's haul
--- and ExhibitService's pedestals: only five items in the catalogue have real art.
local function placeOnStand(stand: BasePart, item: any): Instance?
	local def = Items.get(item.itemId)
	local model = ItemModels.create(def.model)

	if model == nil then
		local block = Instance.new("Part")
		block.Name = "WashItem"
		block.Size = Vector3.new(1.4, 1.4, 1.4)
		block.Color = Rarity.get(item.rarity).color
		block.Material = Enum.Material.SmoothPlastic
		block.Anchored = true
		block.CanCollide = false
		block.CFrame = stand.CFrame
		block.Parent = stand
		return block
	end

	model.Name = "WashItem"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	model.Parent = stand
	model:PivotTo(stand.CFrame * ItemModels.rotation(model, "Wash"))
	return model
end

-- ── Picking up the hose ────────────────────────────────────────────────

--- Put a copy of the station's nozzle in the player's right hand and run the reel's
--- line to it. Silently does nothing if the station has no hose — every plot built
--- since build/Plots.buildHoseRig landed has one, but a place file saved before it
--- did will not, and a missing hose must degrade to "washing works, it just looks
--- like the old version" rather than to a refused wash.
local function takeHose(player: Player, session: Session)
	local station = session.station
	local parked = if station then station:FindFirstChild("Hose") else nil
	if parked == nil or not parked:IsA("Model") or parked.PrimaryPart == nil then
		return
	end

	local character = player.Character
	-- R15 first, then R6 — the same fallback ToolService's handOf uses.
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if hand == nil or not hand:IsA("BasePart") then
		return
	end

	local clone = parked:Clone()
	clone.Name = "WashHose"
	-- Re-checked on the copy rather than inherited from the check on `parked` above:
	-- PrimaryPart survives a Clone, but nothing in the type system says so, and every
	-- line after this one welds to it or hangs an attachment off it.
	local core = clone.PrimaryPart
	if core == nil then
		clone:Destroy()
		return
	end
	-- UNANCHORED, MASSLESS, NON-COLLIDING, and all three matter. Anchored would bolt
	-- the character to the world through the aim joint WashController adds (see
	-- build/Plots.buildHoseRig's own note); mass would let the player shove themselves
	-- around holding a nozzle; collision would wedge them in the tub.
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end
	clone.Parent = character
	clone:PivotTo(hand.CFrame * HOSE_HOLD)

	local weld = Instance.new("WeldConstraint")
	-- Named HoldWeld to match ToolService's, because WashController's aim rig looks
	-- for exactly that name to disable while it points the nozzle, and re-enables it
	-- on the way out. One name, one convention, one code path on the client.
	weld.Name = "HoldWeld"
	weld.Part0 = hand
	weld.Part1 = core
	weld.Parent = core

	-- Swing the reel's line onto the copy, THEN take the original out of the tree.
	-- In that order: a Beam whose Attachment1 has just been unparented draws nothing,
	-- and a hose that blinks out for a frame on every wash is a bug people report.
	local reel = if station then station:FindFirstChild("HoseReel") else nil
	local line = if reel then reel:FindFirstChildOfClass("Beam") else nil
	local hoseEnd = core:FindFirstChild("HoseEnd")
	if line and hoseEnd and hoseEnd:IsA("Attachment") then
		-- Remember the parked sag before swapping in the held one. A Beam's CurveSize
		-- is an absolute stud distance rather than a fraction of the span, so the
		-- eight-stud run to a player's hand and the three-stud run to the pump cap
		-- need different numbers -- both of which build/Plots.buildHoseRig owns, one
		-- as the property and one as an attribute beside it.
		session.parkedCurve = Vector2.new(line.CurveSize0, line.CurveSize1)
		line.CurveSize0 = (line:GetAttribute("HeldCurve0") :: number?) or line.CurveSize0
		line.CurveSize1 = (line:GetAttribute("HeldCurve1") :: number?) or line.CurveSize1
		line.Attachment1 = hoseEnd
		session.line = line
	end

	-- STASHED, NOT DESTROYED. `Parent = nil` keeps the instance alive for as long as
	-- this session holds the reference, which is what lets stowHose put the station
	-- back exactly as it was instead of rebuilding a nozzle from scratch.
	parked.Parent = nil
	session.parked = parked
	session.hose = clone
end

--- The exact inverse, and it has to be safe to call after anything at all has been
--- destroyed underneath it: a respawn takes the clone, a World.rebuild() takes the
--- station, and both arrive here as the same "put it back" call.
local function stowHose(session: Session)
	local parked = session.parked
	if parked then
		parked.Parent = session.station
		local line = session.line
		local core = parked.PrimaryPart
		local hoseEnd = if core then core:FindFirstChild("HoseEnd") else nil
		if line and line.Parent and hoseEnd and hoseEnd:IsA("Attachment") then
			line.Attachment1 = hoseEnd
			local curve = session.parkedCurve
			if curve then
				line.CurveSize0, line.CurveSize1 = curve.X, curve.Y
			end
		end
	end
	if session.hose then
		session.hose:Destroy()
	end
	session.hose, session.parked, session.line, session.parkedCurve = nil, nil, nil, nil
end

-- ── The session ────────────────────────────────────────────────────────

--- Aim the clock at one patch. Returns false when nothing is reachable, which is the
--- wall: the item is not ruined, it is waiting on a better cleaner or a better roll.
local function aim(session: Session, item: any, stats: any): boolean
	local patches = item.patches or {}

	-- The client names WHICH patch, and this is the whole trust boundary: an index it
	-- can reach is honoured, anything else falls back to the easiest reachable one.
	-- A client picking its own order is not an exploit -- it could already do that by
	-- clicking a different row in the old panel -- but a client naming a patch its
	-- potency cannot touch would be, so `<= effectivePotency` is checked here and not
	-- taken on trust.
	local chosen: number? = nil
	local wanted = session.patchIndex
	if wanted and patches[wanted] and patches[wanted] <= stats.effectivePotency then
		chosen = wanted
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

	-- Patch hardnesses go out as-is. They are the player's own item and the whole
	-- point of the bay is to SHOW them: a crusted blob that visibly repels the stream
	-- is the Quarantine Locker taught in three dimensions instead of in a red label.
	local patches = {}
	for index, hardness in item.patches or {} do
		table.insert(patches, {
			index = index,
			hardness = hardness,
			blocked = hardness > stats.effectivePotency,
		})
	end

	stateRemote:FireClient(player, {
		uid = session.uid,
		name = def.name,
		rarity = item.rarity,
		patches = patches,
		targetIndex = session.patchIndex,
		progress = if session.target > 0 then math.clamp(session.elapsed / session.target, 0, 1) else 0,
		liquidId = stats.liquidId,
		liquidName = liquid.name,
		liquidColor = liquid.color,
		potency = stats.effectivePotency,
		stand = session.stand,
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
	stowHose(session)

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
		-- seconds; the tool is named as the permanent fix.
		local shortfall = blocked - stats.cleanPotency
		local rescue = Liquids.cheapestWithPotency(shortfall)
		if rescue then
			return false, `too tough \u{2014} roll {rescue.name} at the pad, or buy the {CarryService.cleanerNameFor(blocked)} tool`
		end
		return false, `too tough \u{2014} needs the {CarryService.cleanerNameFor(blocked)} tool; no liquid reaches this`
	end

	local stand = basin.Parent and basin.Parent:FindFirstChild("WashStand")
	if stand == nil or not stand:IsA("BasePart") then
		warn(`[wash] {basin:GetFullName()} has no WashStand sibling — rebuild the world`)
		return false, "this station is broken"
	end

	-- ONE WASH PER STATION, and it stopped being merely tidy the day the hose became a
	-- real object: there is exactly one nozzle on that pump and one stand to put an
	-- item on, so a second player starting here would take the first player's hose out
	-- of their hands and stack their item inside the other one. The prompt disable
	-- below only stops the OCCUPANT re-triggering it; this is what stops a visitor.
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
		-- World.rebuild() mid-session orphans the stand, and stowHose still needs
		-- somewhere to put the nozzle back.
		station = stand.Parent,
		prompt = if prompt and prompt:IsA("ProximityPrompt") then prompt else nil,
		returnTo = if root and root:IsA("BasePart") then root.CFrame else nil,
		model = nil,
		hose = nil,
		parked = nil,
		line = nil,
		parkedCurve = nil,
		spraying = false,
		patchIndex = nil,
		elapsed = 0,
		target = 0,
		hardness = 0,
	}
	if not aim(session, item, stats) then
		return false, "nothing you can shift here"
	end

	session.model = placeOnStand(stand, item)
	sessions[player] = session
	-- After sessions[player], so ToolService's next pass already sees isWashing() and
	-- pulls the Cleaner out of the same hand rather than racing the hose into it.
	takeHose(player, session)

	-- DISABLE THE PROMPT FOR THE DURATION. Roblox's default ProximityPrompt widget can
	-- be triggered by a MOUSE CLICK on its on-screen icon, not only the keyboard key --
	-- and the player is about to spend the whole session clicking to spray, often
	-- toward wherever this same prompt happens to render once the camera cuts to the
	-- side-on wash shot. Left enabled, aiming the hose doubles as an accidental "press
	-- E again" that ends the session out from under you. WashController's own E/Q
	-- keyboard listener is the real, deliberate exit now; re-enabled in finish().
	if session.prompt then
		session.prompt.Enabled = false
	end

	-- PLANT THEM ON THE MARK. The camera is a fixed side-on shot composed against
	-- WashSpot and WashStand (build/Plots), so the framing is only right if the player
	-- is actually standing where the geometry says. Approaching from an angle and
	-- being framed from the front is what produced "a weird view where nothing
	-- happens": the character was behind the camera and the item filled the screen.
	if spot and spot:IsA("BasePart") and root and root:IsA("BasePart") then
		root.CFrame = spot.CFrame
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
			local cleared = Contamination.clearOne(item.patches, stats.effectivePotency)
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
		session.patchIndex = if type(request.patchIndex) == "number" then request.patchIndex else nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- STRAIGHT THROUGH finish(), rather than the hand-rolled teardown that used to
		-- live here. That version destroyed the MODEL on the tub, which was the whole of
		-- the leftover state at the time — the hose is a second thing that has to be put
		-- back, and it would otherwise be left stashed out of the tree, leaving the
		-- station with no nozzle for whoever arrived next. One teardown, one place.
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
