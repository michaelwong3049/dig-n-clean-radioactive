--!strict
--[[
	ToolService.lua — puts the right thing in the player's hands.

	Server-side on purpose. On a shared server (PLAN §1) what someone is holding is
	information other players should get for free: seeing a stranger out in the ash
	swinging a detector, or hunched over a magnet hauling something up, is the cheapest
	storytelling in the game. A client-only cosmetic would be invisible to everyone else.

	WHICH TOOL, in priority order:
	  committed to a signal -> Magnet   (you have locked on — now pull it up)
	  holding a dug item    -> nothing  (both hands are busy carrying the find)
	  standing in a stage   -> Detector  (sweeping is the default verb)
	  otherwise            -> nothing   (base camp, hands free)

	A DETECTOR BRACED ACROSS THE CHEST AND AN ITEM CRADLED IN BOTH HANDS ARE THE SAME
	POSTURE (see UPPER_BODY_POSE) applied to two different things at once — which is
	why they used to render TOGETHER and look wrong: the coil floating in front of an
	item that is supposedly held with both hands. `wanted` now blanks the tool the
	moment something is riding in the off hand, so the sweep only resumes once the bag
	slot empties back out (data.heldUid == "").

	THE DECON STATION USED TO BE THE FIRST RUNG OF THAT LIST and it handed you your
	Cleaner. It does not any more, because the Cleaner track stopped being something a
	player holds: it is the monitor bolted to the mast beside your tub
	(build/Plots.buildHoseRig), bought at the plaza and swapped in place by
	Plots.setHoseTier. There is nothing left for this file to put in that hand, so the
	hand stays empty at the bay — which is also what the wash branch in `stepPlayer`
	has been enforcing from the other direction the whole time.

	The magnet keys off COMMITTING to a signal (DigService.isLocked), not off merely
	standing over one. It used to swap on approach, but that took the detector out of
	your hands the instant you walked onto any glow — including one you were only
	sweeping past — so the sweep verb kept losing its tool mid-stride. Now the detector
	stays out until you hold E to lock on, and the magnet appears for exactly the pull.

	HOLD OFFSETS LIVE ON THE MODELS, not in here. Each tool carries a `HoldCFrame`
	attribute, so the position and angle in the hand can be nudged in Studio's property
	panel against a live character instead of by editing code and rebooting — which is
	the only sane way to tune something you have to look at to judge.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Gear = require(Shared.Config.Gear)
local Items = require(Shared.Config.Items)
local Payload = require(Shared.Config.Payload)
local Rarity = require(Shared.Config.Rarity)
local ItemModels = require(Shared.ItemModels)
local ItemCrust = require(Shared.ItemCrust)
local ToolModels = require(Shared.ToolModels)
local CrateModels = require(Shared.CrateModels)
local Crates = require(Shared.Config.Crates)
local Bag = require(Shared.Bag)
local ToolFX = require(Shared.ToolFX)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local DigService = require(script.Parent.DigService)
local WashService = require(script.Parent.WashService)

local ToolService = {}

local LIBRARY = ReplicatedStorage.Assets.Tools
local HELD_NAME = "HeldTool"
local HELD_ITEM_NAME = "HeldItem"

--- Longest axis a held item model is scaled to -- same normalise-to-a-target-
--- dimension trick as ExhibitService's LOCKER_ITEM_SIZE and WashService's
--- WASH_DISPLAY_SIZE, sized up a bit since this one is held close to the camera
--- rather than tucked in a cabinet. Every item's authored size is arbitrary
--- (an imported mesh's real-world proportions, not a tuned game size), so this
--- is what actually makes a held item read consistently regardless of source.
--- Bigger than a whole character (~5 studs tall) on purpose -- matches the
--- same scale-up as the exhibit stand, model yard, and wash stand.
local HELD_ITEM_SIZE = 5.94

--- Clearance between the overhead hand and a held item's own lowest point (see
--- equipItem) -- just enough that the underside reads as resting ON the hands
--- instead of poking through them.
local HELD_ITEM_LIFT = 0.15

--- A held supply crate's FOOTPRINT (width/depth, CrateModels.FOOTPRINT_OF), in studs.
--- Not scaled by Config/Payload, and measured across rather than by longest side so
--- every crate is the same box in your hands whatever sticks up off its lid.
local HELD_CRATE_SIZE = 3.8

local equipped: { [Player]: string? } = {}

-- Track name in Assets/Tools -> the key it upgrades under in profile.gear.
-- Shared with the shop, which needs all six tracks. See Config/Gear.luau.
local GEAR_KEY = Gear.PROFILE_KEY

-- ── Two-handed carry ──────────────────────────────────────────────────────
--
-- A detector is carried braced against the chest and swept from the hips, so the whole
-- upper body -- both arms AND the spine -- must hold still while the legs walk under
-- it. Driving a joint's Transform cannot achieve that: the animator re-solves every
-- frame regardless of which RenderStep priority the write happens at. Measured at three
-- priorities; the arm moved 0.01 studs.
--
-- So each joint is switched OFF and a rigid Weld holds the limb instead. The animator
-- keeps writing to a disabled joint and moves nothing.
--
-- TWO RIGS EXIST AND THIS MUST HANDLE BOTH. Classic characters join limbs with
-- Motor6D (Part0/Part1/C0/C1); newer ones use AnimationConstraint driving a pair of
-- Attachments, with a BallSocketConstraint doing the physical join. Assuming Motor6D
-- made this silently do nothing on a constraint rig — no error, just an arm that
-- carried on swinging. The ball socket is disabled alongside the joint: the Weld holds
-- the limb rigidly, so the socket has no job left and an enabled one only drags the
-- welded part around by physics.
--
-- Server-side on purpose: posing on the client would not replicate, and on a shared
-- server everyone else would watch you carry it wrong.
--
-- THE WHOLE UPPER BODY, not just the shoulders. Two earlier passes each stopped short:
--   * shoulders only -> elbows and wrists still animated; the hand slid 0.41 studs off
--     a tool that was not moving (tool grip 0.000, upper arm 0.133, hand 0.414).
--   * arms only -> the head still pitched up and back on every stride, because the
--     walk cycle's lean and bounce ride the Waist and Neck. Locking those two, with
--     UpperTorso re-anchored to the root, is what finally holds the head still.
-- `above` names the limb this joint hangs off at rest, needed to compose the weld back
-- to the root: shoulders hang off UpperTorso (the whole spine), the Waist off
-- LowerTorso (just the Root joint). Ordered so a limb's parent is locked before it.
--
-- `angle` names which entry in POSES supplies this joint's bend, and `side` flips the
-- roll for the left arm. A joint with neither is held at its rest pose in every pose,
-- which is what the spine and the wrists want.
local UPPER_BODY_POSE = {
	-- Spine. UpperTorso onto the root kills the waist sway and the vertical bounce; the
	-- Head then rides the now-rigid UpperTorso at its rest pose.
	{ limb = "UpperTorso", joint = "Waist", above = "LowerTorso", toRoot = true, socket = "WaistBallSocket" },
	{ limb = "Head", joint = "Neck" },
	-- Arms. Shoulders onto the root and posed forward onto the grip; elbows and wrists
	-- then hang off the limb above them.
	{ limb = "RightUpperArm", joint = "RightShoulder", above = "UpperTorso", angle = "shoulder", side = -1, toRoot = true, socket = "RightShoulderBallSocket" },
	{ limb = "RightLowerArm", joint = "RightElbow", angle = "elbow", side = -1 },
	{ limb = "RightHand", joint = "RightWrist" },
	{ limb = "LeftUpperArm", joint = "LeftShoulder", above = "UpperTorso", angle = "shoulder", side = 1, toRoot = true, socket = "LeftShoulderBallSocket" },
	{ limb = "LeftLowerArm", joint = "LeftElbow", angle = "elbow", side = 1 },
	{ limb = "LeftHand", joint = "LeftWrist" },
}
local LOCK_NAME = "CarryLock"

--- TWO THINGS ARE CARRIED BRACED, AND THEY ARE NOT HELD THE SAME WAY. The machinery
--- above was written for one (the detector) with its angles inlined; the fire hose
--- needs the identical rig-handling and a different posture, so the posture came out
--- into here rather than being copied into a second lockUpperBody.
---
--- `pitch` swings the limb forward, `roll` brings it in toward the body's midline.
local POSES: { [string]: { shoulder: { pitch: number, roll: number }, elbow: { pitch: number, roll: number } } } = {
	-- The detector: braced against the chest and swept from the hips. These are the
	-- numbers this file carried before there was more than one pose.
	detector = {
		shoulder = { pitch = 35, roll = 25 },
		elbow = { pitch = 0, roll = 0 },
	},
	-- The fire hose: arms up and further forward than the detector's, with a real bend
	-- at the elbow. That bend is most of the difference. A hose is heavy and pushing
	-- back at you, so it is held IN, close to the chest with the elbows folded -- arms
	-- locked out straight reads as presenting something on a tray. The lower roll
	-- brings both hands onto the one nozzle instead of onto a wide detector coil.
	--
	-- Measured off a live character rather than guessed. At the first numbers tried
	-- (pitch 58, roll 14) the hands came out 2.2 studs apart -- too wide to both be on
	-- one 1.7-stud nozzle -- and low enough that the muzzle sat BELOW the tub rim, so
	-- the water hit the rim about a stud out of the nozzle. Pitch lifts the grip to
	-- chest height and clear of the tub, roll brings the off hand in beside the other
	-- one (1.3 studs apart, which a 1.7-stud nozzle spans), and the elbow is what
	-- stops it reading as a sleepwalker: at -25 the arms were straight out, and the
	-- lower shoulder that would have fixed that on its own (62) dropped the whole grip
	-- back down toward the rim. High shoulder, folded elbow.
	hose = {
		shoulder = { pitch = 74, roll = 30 },
		elbow = { pitch = -40, roll = 0 },
	},
	-- Carrying a dug item back on foot. Nothing braces this against a fixed rig part
	-- the way the detector and hose do -- it is welded to LeftHand (see equipItem) --
	-- so the ONLY thing stopping it from swinging through the walk cycle is this same
	-- upper-body lock. BOTH ARMS GO STRAIGHT UP, hands meeting overhead -- a two-handed
	-- press, not a chest cradle -- because equipItem bottom-anchors the item on the
	-- hand (see HELD_ITEM_LIFT) and a chest-height hand put the model's midpoint
	-- through the player's own head and torso the moment a big Payload roll (up to
	-- 2.5x) grew it past a normal item's size. Anchoring off an OVERHEAD hand instead
	-- means the item's bulk grows up and away from the body at any roll, not just an
	-- oversized one, and doubles as the "presenting the find" read the old chest pose
	-- was going for in the first place.
	--
	-- Swept a shoulder-pitch range (screen_capture, a real nuke welded to LeftHand
	-- with equipItem's live math) rather than guessing: pitch traces the arm through
	-- the same vertical arc the hose pose only starts (hanging down at 0, forward-
	-- horizontal at 90), and it peaks -- this rig's arm segments cannot reach any
	-- higher no matter the angle -- around 185-190, at 5.4 studs vs. a 4.6-stud head.
	-- Past 190 the hand comes back DOWN the other side of the arc, so 190 is a
	-- ceiling, not a starting point. Roll pulled up to 30 (from the hose's 30, the
	-- highest value already proven not to cross the wrists) is what brings both hands
	-- fully together under the item instead of leaving them either side of it. The
	-- elbow keeps a light fold (-20, well short of the hose's -40) so the pose still
	-- reads as gripping something rather than a mannequin's locked-straight arms; a
	-- dead-straight elbow (0) reached no higher and looked stiffer for it.
	carry = {
		shoulder = { pitch = 188, roll = 30 },
		elbow = { pitch = -20, roll = 0 },
	},
}
--- Which pose a character is currently locked into, or nil for none. An attribute
--- rather than a table keyed by player because it belongs to the CHARACTER: a respawn
--- takes the welds with it, and it has to take the record of them too.
local POSE_ATTRIBUTE = "CarryPose"

--- The two joined parts and their rest offsets, whichever rig this character uses.
local function jointFrames(joint: Instance): (BasePart?, BasePart?, CFrame?, CFrame?)
	if joint:IsA("Motor6D") then
		return joint.Part0, joint.Part1, joint.C0, joint.C1
	elseif joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if a0 and a1 and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
			return a0.Parent, a1.Parent, a0.CFrame, a1.CFrame
		end
	end
	return nil, nil, nil, nil
end

--- Where a joint puts its child relative to its parent with NO animation applied.
--- Read from the rig's own rest data rather than sampled off a live character, so it
--- cannot pick up whatever frame of the idle cycle happened to be playing.
local function restOffset(joint: Instance?): CFrame?
	if joint == nil then
		return nil
	end
	local _, _, c0, c1 = jointFrames(joint)
	if c0 == nil or c1 == nil then
		return nil
	end
	return c0 * c1:Inverse()
end

--- UpperTorso's rest position relative to HumanoidRootPart, composed down the spine.
--- Needed because the shoulders naturally hang off UpperTorso, and we want them
--- hanging off the root instead without moving the arm.
local function torsoFromRoot(character: Model): CFrame
	local lower = character:FindFirstChild("LowerTorso")
	local upper = character:FindFirstChild("UpperTorso")
	local rootRest = lower and restOffset(lower:FindFirstChild("Root"))
	local waistRest = upper and restOffset(upper:FindFirstChild("Waist"))
	if rootRest and waistRest then
		return rootRest * waistRest
	end
	return CFrame.identity
end

--- Where a LOCKED limb sits relative to HumanoidRootPart, composed back up its chain of
--- CarryLock welds -- read off the welds' own C0/C1, never off the part's live CFrame.
--- A weld created this tick has not been solved yet, so the hand's Position is still
--- wherever the walk cycle last left it; the weld data is already the pose. nil if any
--- link in the chain is unlocked (no pose, or a rig lockUpperBody could not handle).
local function lockedFromRoot(root: BasePart, part: Instance?): CFrame?
	local frame = CFrame.identity
	for _ = 1, #UPPER_BODY_POSE + 1 do
		if part == root then
			return frame
		end
		local lock = if part then part:FindFirstChild(LOCK_NAME) else nil
		if lock == nil or not lock:IsA("Weld") then
			return nil
		end
		frame = lock.C0 * lock.C1:Inverse() * frame
		part = lock.Part0
	end
	return nil
end

local function unlockUpperBody(character: Model)
	for _, spec in UPPER_BODY_POSE do
		local limb = character:FindFirstChild(spec.limb)
		if limb then
			local existing = limb:FindFirstChild(LOCK_NAME)
			if existing then
				existing:Destroy()
			end
			local joint = limb:FindFirstChild(spec.joint)
			if joint then
				pcall(function()
					(joint :: any).Enabled = true
				end)
			end
			if spec.socket then
				local socket = limb:FindFirstChild(spec.socket)
				if socket then
					pcall(function()
						(socket :: any).Enabled = true
					end)
				end
			end
		end
	end
end

local function lockUpperBody(character: Model, kind: string)
	local angles = POSES[kind]
	if angles == nil then
		warn(`[tool] no pose named "{kind}" — leaving {character.Name} unposed`)
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local spine = torsoFromRoot(character)
	local lower = character:FindFirstChild("LowerTorso")
	local lowerRest = (lower and restOffset(lower:FindFirstChild("Root"))) or CFrame.identity

	for _, spec in UPPER_BODY_POSE do
		local limb = character:FindFirstChild(spec.limb)
		local joint = limb and limb:FindFirstChild(spec.joint)
		if joint and limb:FindFirstChild(LOCK_NAME) == nil then
			local part0, part1, c0, c1 = jointFrames(joint)
			if part0 and part1 and c0 and c1 then
				local bend = if spec.angle then angles[spec.angle] else nil
				local pitch = if bend then bend.pitch else 0
				local roll = if bend then bend.roll * (spec.side or 1) else 0

				local weld = Instance.new("Weld")
				weld.Name = LOCK_NAME
				weld.Part1 = part1
				weld.C1 = c1

				-- toRoot joints re-anchor to the root at their rest pose; `above` picks
				-- what sits between them and the root (the whole spine for a shoulder,
				-- just the Root joint for the Waist). Everything else hangs off the limb
				-- above it, which this loop has already locked.
				if spec.toRoot and root then
					local prefix = if spec.above == "LowerTorso" then lowerRest else spine
					weld.Part0 = root
					weld.C0 = prefix * c0 * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
				else
					weld.Part0 = part0
					weld.C0 = c0 * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
				end

				weld.Parent = limb
				pcall(function()
					(joint :: any).Enabled = false
				end)

				-- Disable the ball socket alongside the joint. The Weld holds the limb
				-- rigidly, so the socket has no job left -- and an enabled one only ties
				-- the welded part to the root through physics, dragging on the very
				-- stride it is meant to sit out.
				if spec.socket then
					local socket = limb:FindFirstChild(spec.socket)
					if socket then
						pcall(function()
							(socket :: any).Enabled = false
						end)
					end
				end
			else
				warn(`[tool] unrecognised joint "{joint.ClassName}" on {spec.limb} — {spec.limb} will still animate`)
			end
		end
	end
end

--- The only entry point either lock function should be called through. Cheap when
--- nothing changes, which is almost every tick, and it is what makes SWITCHING poses
--- work at all: lockUpperBody bails on any limb that already carries a CarryLock, so
--- going from the detector's posture straight to the hose's would otherwise keep the
--- detector's. Unlock first, then lock, and only when the answer actually moved.
local function setPose(character: Model, kind: string?)
	if character:GetAttribute(POSE_ATTRIBUTE) == kind then
		return
	end
	unlockUpperBody(character)
	if kind then
		lockUpperBody(character, kind)
	end
	character:SetAttribute(POSE_ATTRIBUTE, kind)
end

local function handOf(character: Model): BasePart?
	-- R15 first, then R6.
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

--- Where a tool hangs, declared per model via a HoldPart attribute.
---
--- The hand ANIMATES — every walk cycle swings the arm through its full arc — which
--- is invisible on a 1.5-stud magnet and violent on a 4-stud detector. So anything
--- carried in a fixed posture wants a body part instead.
---
--- WHICH body part matters more than it sounds, and the answer is HumanoidRootPart
--- for the tool, the arms AND the spine (see UPPER_BODY_POSE). They have to share one
--- reference frame or the hands drift off the grip, and it has to be the frame that
--- does not bob:
---
---   tool on root, arms on torso .. hands slid 0.41 studs off the grip
---   tool on torso, arms on torso .. hands perfect, but the coil dug 0.26 into the
---                                   sand every time the chest dipped
---   both on root ................. hands perfect AND the coil holds its height
---
--- The legs still walk their full cycle underneath — everything from the waist up is
--- exempt, which is what carrying something braced actually looks like.
local function attachPointOf(character: Model, template: Model): BasePart?
	local wanted = template:GetAttribute("HoldPart")
	if typeof(wanted) == "string" and wanted ~= "RightHand" then
		local part = character:FindFirstChild(wanted)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return handOf(character)
end

local function unequip(character: Model)
	local held = character:FindFirstChild(HELD_NAME)
	if held then
		held:Destroy()
	end
end

--- CODE-AUTHORED TRACKS COME FIRST. Shared/ToolModels is the intended home for tool
--- art (see its header for why the hoses left the place file) and a stale
--- `Assets/Tools/<Track>` folder must never win the lookup against it.
---
--- NO TRACK TAKES THAT BRANCH TODAY. The Cleaner track was the only one that did, and
--- it stopped being equipped at all when the hose became a machine on a mast — the two
--- tracks left with held models, Detector and Magnet, are both still hand-authored in
--- the place. The branch stays because it is the door the next one walks through, and
--- because deleting it would quietly make a code-authored track lose to a leftover
--- folder the day someone adds one.
---
--- `built` is the throwaway flag: a library template is cloned and must survive, a
--- factory model was made for this call and the clone below is a second copy of it.
--- Rather than special-case the clone, the extra one is destroyed at the end — one
--- allocation per re-equip, on a path that only runs when the tool or tier changes.
local function templateFor(track: string, tier: number): (Model?, boolean)
	if ToolModels.has(track) then
		return ToolModels.create(track, tier), true
	end
	local folder = LIBRARY:FindFirstChild(track)
	local model = if folder then folder:FindFirstChild(`T{tier}`) else nil
	if model and model:IsA("Model") and model.PrimaryPart ~= nil then
		return model, false
	end
	return nil, false
end

local function equip(character: Model, track: string, tier: number)
	local template, built = templateFor(track, tier)
	if template == nil or template.PrimaryPart == nil then
		if template and built then
			template:Destroy()
		end
		return false
	end

	local anchor = attachPointOf(character, template)
	if anchor == nil then
		if built then
			template:Destroy()
		end
		return false
	end

	unequip(character)

	-- Posing is decided once, centrally, in stepPlayer -- it has to weigh this tool
	-- against the off-hand item too, so it does not belong split across both.

	local clone = template:Clone()
	clone.Name = HELD_NAME
	clone:SetAttribute("ToolName", track)
	clone:SetAttribute("Tier", tier)

	local offset = template:GetAttribute("HoldCFrame")
	if typeof(offset) ~= "CFrame" then
		offset = CFrame.new()
	end

	-- PrimaryPart is the Handle, so the model's pivot IS the handle: place the pivot
	-- at the hand times the tuned offset and everything else follows.
	clone.Parent = character
	clone:PivotTo(anchor.CFrame * offset)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "HoldWeld"
	weld.Part0 = anchor
	weld.Part1 = clone.PrimaryPart
	weld.Parent = clone.PrimaryPart

	ToolFX.apply(clone, track, tier)

	if built then
		template:Destroy()
	end

	return true
end

-- ── The off hand: a carried item ──────────────────────────────────────

--- Rebuild the left-hand item only when the uid actually changes. Same guard the
--- tool slot uses: cloning is the most expensive thing in this file, and a bag that
--- is not moving must not pay for it ten times a second.
local function equipItem(character: Model, item: any?): boolean
	local current = character:FindFirstChild(HELD_ITEM_NAME)
	local currentUid = if current then current:GetAttribute("Uid") else nil
	local wantedUid = if item then item.uid else nil

	-- HOW MUCH CRUST IS LEFT IS PART OF THE GUARD, because it is the one thing about a
	-- held item that changes while the uid does not: you walk away from the tub with
	-- three of six patches gone and the lump in your hand has to have three chunks off
	-- it. Counted rather than compared as a level, since the crust is built one chunk
	-- per REMAINING patch and the count IS the shape.
	local wantedChunks = if item then #(item.patches or {}) else 0

	if currentUid == wantedUid then
		if current == nil or current:GetAttribute("Crust") == wantedChunks then
			return true
		end
		-- Same object, different amount of rock on it. Rebuild: chunks are geometry, and
		-- there is nothing to repaint the way the old green film could be.
		current:Destroy()
	elseif current then
		current:Destroy()
	end
	if item == nil then
		return true
	end

	-- R15 first, then R6, mirroring handOf's own fallback. Left hand, so it never
	-- fights the tool slot for the same attachment.
	local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if hand == nil or not hand:IsA("BasePart") then
		return false
	end

	-- A SUPPLY CRATE (Config/Crates) has its own model. A CLEAN one (in `data.crates`)
	-- is the crate itself: no catalogue entry, no Payload roll, no crust. A DIRTY one is
	-- still in `data.carry` passing for a nuke (DigService.unearth), so it is the crate
	-- with its effects and CrateId stripped, sized like a nuke and crusted like one.
	local model: Model? = nil
	local openCrate = item.crateId ~= nil and wantedChunks == 0
	if item.crateId then
		model = if openCrate then CrateModels.create(item.crateId) else CrateModels.createHidden(item.crateId)
	else
		local def = Items.get(item.itemId)
		model = ItemModels.create(def.model, item.itemId)
	end

	if model == nil then
		-- THE SAME RARITY-COLOURED BLOCK the registry documents for unmodelled keys,
		-- and the same one ExhibitService's pedestals fall back to. Only a handful of
		-- the catalogue's items have real art; a nil here has to be a visible object,
		-- not an empty hand, or "you are holding something" stops being true for most
		-- of the game. (The haul no longer shares it -- what comes out of the ground is
		-- a crust either way, see DigService.createHaul.)
		local block = Instance.new("Part")
		block.Name = "Placeholder"
		block.Size = Vector3.new(0.9, 0.9, 0.9)
		block.Color = Rarity.get(item.rarity).color
		block.Material = Enum.Material.SmoothPlastic
		block.CanCollide = false
		block.Massless = true
		block.Anchored = false

		local wrapper = Instance.new("Model")
		wrapper.Name = "Fallback"
		block.Parent = wrapper
		wrapper.PrimaryPart = block
		model = wrapper
	end

	local held = model :: Model
	held.Name = HELD_ITEM_NAME
	held:SetAttribute("Uid", item.uid)

	local primary = held.PrimaryPart or held:FindFirstChildWhichIsA("BasePart")
	if primary == nil then
		held:Destroy()
		return false
	end
	held.PrimaryPart = primary

	-- NORMALISED TO HELD_ITEM_SIZE before the crust goes on, same ordering
	-- WashService uses -- the crust should wrap the size the player actually sees.
	-- `GetScale()` multiplier: see WashService.placeOnStand's identical fix -- a
	-- model already pre-scaled (every imported-mesh template) would otherwise get
	-- HELD_ITEM_SIZE divided by its prior scale a second time.
	-- Config/Payload's per-dig roll applies at full range here -- nothing physically
	-- encloses a held item the way GantryBeam does at the wash stand.
	do
		local _, extents = held:GetBoundingBox()
		local longest = if openCrate then CrateModels.FOOTPRINT_OF(extents) else math.max(extents.X, extents.Y, extents.Z)
		if longest > 0 then
			local target = if openCrate
				then HELD_CRATE_SIZE * (Crates.get(item.crateId).sizeMult or 1)
				else HELD_ITEM_SIZE * Payload.forUid(item.uid)
			held:ScaleTo(held:GetScale() * (target / longest))
		end
	end

	-- ONE CHUNK OF SLAG PER PATCH STILL ON IT, wrapped round the real model before
	-- anything else touches it — the crust has to exist before the weld loop below, or
	-- the rock stays anchored in mid-air while the item walks off inside your hand.
	--
	-- WHY THE ITEM IS UNDER THERE AT ALL rather than a solid lump like the haul's: this
	-- is where a half-finished wash shows. Six chunks hides it completely; two chunks is
	-- an object mostly out of its shell that you can nearly, not quite, name; none at
	-- all is the thing itself, which is the walk back from the tub the whole loop is
	-- pointed at.
	held:SetAttribute("Crust", wantedChunks)
	if wantedChunks > 0 then
		ItemCrust.encase(held, wantedChunks, item.rarity, item.uid)
	end

	held.Parent = character

	-- WELD THE MODEL INTO ONE BODY BEFORE IT GOES DYNAMIC. The ItemModels factories
	-- (Shared/ItemModels) author every part Anchored and with NO joints between them --
	-- they are built to be moved whole with PivotTo and never simulated, which is how
	-- the haul and the pedestals use them. The hand is the one place that has to let go
	-- of the anchor, and un-anchoring a jointless pile while welding only the primary to
	-- the hand drops the other twenty parts on the floor -- "the item falls out of your
	-- hand". Join them to the primary first, while they are still in authored positions.
	for _, part in held:GetDescendants() do
		if part:IsA("BasePart") and part ~= primary then
			local join = Instance.new("WeldConstraint")
			join.Name = "ItemWeld"
			join.Part0 = primary
			join.Part1 = part
			join.Parent = primary
		end
	end

	-- Now the whole assembly can go dynamic together. Nothing in the hand may collide or
	-- weigh anything, or the character shoves itself around holding a tin can.
	for _, part in held:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless = true
			part.Anchored = false
		end
	end
	-- POSITION is centred over the head at the height of BOTH hands, not pinned to
	-- LeftHand alone -- the "carry" pose (see POSES) brings both up overhead but not
	-- onto the same point, and a model pivoted straight onto LeftHand reads as visibly
	-- off-centre, biased to that side, instead of gripped in the middle with two hands.
	--
	-- What sits at that point is the model's BOTTOM, not its centre (see
	-- HELD_ITEM_LIFT below): an overhead press holds the underside of the thing, and
	-- the object rises away from the body from there regardless of how big a Payload
	-- roll (up to 2.5x, see the scale step above) made it -- unlike a chest cradle,
	-- there is no "normal" size an overhead hand can centre on without either burying
	-- the player's own head in it or leaving a floating gap above the hand.
	--
	-- ROTATION DOES NOT COME FROM THE HAND, though, and that split is load-bearing.
	-- LeftHand's ORIENTATION under the carry/detector locks is whatever the shoulder
	-- and elbow angles in POSES happen to compose to, which is nowhere near a hand's
	-- natural resting orientation -- it is bent through most of a right angle to get
	-- the hand up there at all. An item pivoted onto that full CFrame inherits the
	-- bend too, and anything longer than a stub (checked live with the Steel Rod, 3.25
	-- studs) swings its far end out to the side or up past the head chasing whatever
	-- axis that rotation happened to point along, instead of lying across the two
	-- hands. Root's rotation has none of that -- it only yaws with which way the
	-- player is facing -- so an item held upright overhead STAYS upright overhead no
	-- matter how the elbow got it there.
	--
	-- `Hold` joins Display / Haul / Gallery as an ItemModels rotation context, so a
	-- flat object like the bottle cap can still be tilted toward the camera in the
	-- hand without forcing that tilt on an upright one. Missing attribute = identity.
	--
	-- EVERYTHING BELOW IS WORKED OUT IN ROOT SPACE, NEVER FROM THE HANDS' LIVE POSITION.
	-- It used to read hand.Position and weld with a WeldConstraint, which freezes
	-- whatever offset the hand had at that instant -- and on the tick an item first
	-- goes into your hands the carry pose is not on yet (or is, but its welds have not
	-- been solved), so the hands were still down at the hips. The item got glued on
	-- down there, then the arms swung up through 188 degrees and carried it over the
	-- top and down BEHIND the head. Only sometimes, because switching items while
	-- already posed read the right hands. Now the grip comes from the pose welds' own
	-- data (lockedFromRoot) and the item is welded to the root at an explicit C0, so
	-- where it sits does not depend on what the physics has caught up with.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		held:Destroy()
		return false
	end
	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local head = character:FindFirstChild("Head")

	-- Height: on the two overhead hands, and never lower than the top of the head.
	-- Across: centred over the HEAD, not the hands -- the carry pose's hands sit a
	-- touch past vertical, and "above the head" is the whole read.
	local headFrame = if head and head:IsA("BasePart")
		then lockedFromRoot(root, head) or root.CFrame:ToObjectSpace(head.CFrame)
		else CFrame.new(0, 1.5, 0)
	local headTop = headFrame.Position.Y + (if head and head:IsA("BasePart") then head.Size.Y / 2 else 0.6)
	local leftGrip = lockedFromRoot(root, hand)
	local rightGrip = if rightHand then lockedFromRoot(root, rightHand) else nil
	local gripY = headTop
	if leftGrip and rightGrip then
		gripY = math.max(gripY, (leftGrip.Position.Y + rightGrip.Position.Y) / 2)
	end
	local grip = Vector3.new(headFrame.Position.X, gripY + HELD_ITEM_LIFT, headFrame.Position.Z)

	-- Seat the model's real BOUNDING BOX on that point, not its pivot: an imported
	-- mesh's pivot is wherever its author left it, and the crust grows lopsided, so a
	-- pivot on the grip can still leave the bulk of the thing hanging off one side. The
	-- box is measured along the root's axes (a rotated primary part's extents are not).
	local rotation = ItemModels.rotation(held, "Hold")
	held:PivotTo(root.CFrame * CFrame.new(grip) * rotation)
	local box, extents = held:GetBoundingBox()
	local boxLocal = root.CFrame:ToObjectSpace(box)
	local half = (boxLocal.XVector * extents.X / 2):Abs()
		+ (boxLocal.YVector * extents.Y / 2):Abs()
		+ (boxLocal.ZVector * extents.Z / 2):Abs()
	local bottomCentre = boxLocal.Position - Vector3.new(0, half.Y, 0)
	local seat = CFrame.new(grip - bottomCentre) * root.CFrame:ToObjectSpace(held:GetPivot())
	held:PivotTo(root.CFrame * seat)

	local weld = Instance.new("Weld")
	weld.Name = "HoldWeld"
	weld.Part0 = root
	weld.Part1 = primary
	weld.C0 = root.CFrame:ToObjectSpace(primary.CFrame)
	weld.Parent = primary

	return true
end

local function wanted(player: Player, data: any): string?
	-- Washing is handled by its own branch in stepPlayer, which returns before this
	-- answer is ever used -- it has a pose to set as well as a tool to clear, and
	-- splitting those across two places is how one of them gets forgotten.
	--
	-- NOTHING FOR THE DECON STATION. Standing at a cleansing station used to return
	-- "Cleaner" and put the tier's hose in your hand; the track is a machine on a mast
	-- now (see the header) and there is nothing to hand over. Two tracks have held
	-- models left, and this list is both of them.
	if DigService.isLocked(player) then
		return "Magnet"
	end
	-- BOTH HANDS ARE ON THE FIND. Checked ahead of the detector, not after it: a
	-- player can walk back into a stage still carrying what they just dug up, and the
	-- detector must stay off their chest until that item is racked or sold, not just
	-- while it is first picked up.
	if data and data.heldUid ~= "" then
		return nil
	end
	if DigService.stageOf(player) ~= nil then
		return "Detector"
	end
	return nil
end

--- The single source of truth for which upper-body pose (if any) a character should
--- be locked into this tick, weighing the tool in the right hand against whatever is
--- riding in the left. The two no longer compete: `wanted` blanks the detector the
--- moment an item is held (see its comment), so `target` is never "Detector" at the
--- same time `hasItem` is true and this can pick one pose per tick without a tie.
local function poseFor(target: string?, hasItem: boolean): string?
	if target == "Detector" then
		return "detector"
	end
	if hasItem then
		return "carry"
	end
	return nil
end

local function stepPlayer(player: Player)
	local character = player.Character
	if character == nil or handOf(character) == nil then
		equipped[player] = nil
		return
	end

	local data = DataService.data(player)
	local target = wanted(player, data)

	-- ── The off hand ──────────────────────────────────────────────
	-- Resolved BEFORE the early-out below, because the tool slot and the item slot
	-- change for completely unrelated reasons: standing still at a base with nothing
	-- in hand is exactly when a player cycles through their bag, and an early return
	-- on the tool would freeze the item in their hand.
	--
	-- Suppressed while a wash is running: the item is sitting on the tub then, not in
	-- your hand, and WashService owns rendering it there.
	local heldItem: any = nil
	if data and data.heldUid ~= "" and not WashService.isWashing(player) then
		for _, item in data.carry do
			if item.uid == data.heldUid then
				heldItem = item
				break
			end
		end
		if heldItem == nil then
			heldItem = Bag.findCrate(data, data.heldUid)
		end
	end

	-- POSE FIRST, THEN THE ITEM. equipItem seats the item on the carry pose's hands,
	-- read off the pose welds, so on the tick something first goes into your hands
	-- those welds have to exist already. Decided every tick, unlike the tool slot
	-- below: an item can start or stop being held without the tool track changing at
	-- all, and setPose() is cheap to call redundantly (it bails the moment the pose
	-- attribute already matches). A wash sets its own pose in the branch below.
	if not WashService.isWashing(player) then
		setPose(character, poseFor(target, heldItem ~= nil))
	end
	equipItem(character, heldItem)

	-- ── Washing ───────────────────────────────────────────────────
	-- HANDS EMPTY, ARMS UP. The wash bay used to weld a copy of the station's hose into
	-- the right hand for the session, so this branch existed to make room for it; the
	-- nozzle is bolted to its mast now and nothing is handed over at all. Two things
	-- still belong here rather than in WashService, because this file owns the tool
	-- slot and it owns posing, and it already reads isWashing for the off hand above:
	--
	--   * the slot is cleared. `wanted` returns nil at a station anyway now, but a
	--     player can walk into a wash straight off a stage with a detector still up.
	--   * the upper body braces, the same way it does for the detector. The pose is
	--     WHY it still reads as operating something: both hands come up onto the
	--     controls and the arms stop swinging through their idle cycle. Left out, a
	--     player at the mark stands slack while a machine two studs away sprays on its
	--     own, which is the same "it looks awkward" the brace was added for.
	--
	-- Returning here also keeps the tool-slot bookkeeping below from running at all --
	-- it would otherwise see `wanted` already answering nil for a station and clear a
	-- tool slot that unequip() just cleared anyway.
	if WashService.isWashing(player) then
		unequip(character)
		setPose(character, "hose")
		equipped[player] = nil
		return
	end

	-- Tier comes from the profile, so buying an upgrade changes what is in your hands
	-- the moment it lands — no reconnect, no re-equip step.
	local tier = 1
	if target and data then
		tier = data.gear[GEAR_KEY[target]] or 1
	end

	local current = character:FindFirstChild(HELD_NAME)
	local currentName = if current then current:GetAttribute("ToolName") else nil
	local currentTier = if current then current:GetAttribute("Tier") else nil

	if target == currentName and tier == currentTier then
		return
	end

	if target == nil then
		unequip(character)
		equipped[player] = nil
	elseif equip(character, target, tier) then
		equipped[player] = target
	end
end

function ToolService.init() end

function ToolService.start()
	Players.PlayerRemoving:Connect(function(player)
		equipped[player] = nil
	end)

	-- A quarter of the tick rate: swapping a held model is not something anyone can
	-- perceive at 10 Hz, and cloning is the most expensive thing in this file.
	local counter = 0
	Ticker.every(Tuning.TICK_RATE, function()
		counter += 1
		if counter % 3 ~= 0 then
			return
		end
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player)
			if not ok then
				warn(`[tool] failed for {player.Name}: {err}`)
			end
		end
	end)
end

return ToolService
