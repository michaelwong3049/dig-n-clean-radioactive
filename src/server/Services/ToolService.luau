--!strict
--[[
	ToolService.lua — puts the right thing in the player's hands.

	Server-side on purpose. On a shared server (PLAN §1) what someone is holding is
	information other players should get for free: seeing a stranger out in the ash
	swinging a detector, or hunched over a magnet hauling something up, is the cheapest
	storytelling in the game. A client-only cosmetic would be invisible to everyone else.

	WHICH TOOL, in priority order:
	  committed to a signal -> Magnet   (you have locked on — now pull it up)
	  standing in a stage   -> Detector  (sweeping is the default verb)
	  otherwise            -> nothing   (base camp, hands free)

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
local Rarity = require(Shared.Config.Rarity)
local ItemModels = require(Shared.ItemModels)
local ToolModels = require(Shared.ToolModels)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local DigService = require(script.Parent.DigService)
local WashService = require(script.Parent.WashService)

local ToolService = {}

local LIBRARY = ReplicatedStorage.Assets.Tools
local HELD_NAME = "HeldTool"
local HELD_ITEM_NAME = "HeldItem"

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

	-- Only the detector braces against the body; everything else swings naturally.
	-- (The fire hose braces too, but it is not a tool out of the library -- see the
	-- wash branch in stepPlayer.)
	setPose(character, if track == "Detector" then "detector" else nil)

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

	if currentUid == wantedUid then
		return true
	end
	if current then
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

	local def = Items.get(item.itemId)
	local model = ItemModels.create(def.model)

	if model == nil then
		-- THE SAME RARITY-COLOURED BLOCK the registry documents for unmodelled keys,
		-- and the same one DigService's haul and ExhibitService's pedestals fall back
		-- to. Only five of the catalogue's items have real art; a nil here has to be a
		-- visible object, not an empty hand, or "you are holding something" stops
		-- being true for most of the game.
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
	-- `Hold` joins Display / Haul / Gallery as an ItemModels rotation context, so a
	-- flat object like the bottle cap can be tilted toward the camera in the hand
	-- without forcing that tilt on an upright one. Missing attribute = identity.
	held:PivotTo(hand.CFrame * CFrame.new(0, -0.6, 0) * ItemModels.rotation(held, "Hold"))

	local weld = Instance.new("WeldConstraint")
	weld.Name = "HoldWeld"
	weld.Part0 = hand
	weld.Part1 = primary
	weld.Parent = primary

	return true
end

local function wanted(player: Player): string?
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
	if DigService.stageOf(player) ~= nil then
		return "Detector"
	end
	return nil
end

local function stepPlayer(player: Player)
	local character = player.Character
	if character == nil or handOf(character) == nil then
		equipped[player] = nil
		return
	end

	local target = wanted(player)
	local data = DataService.data(player)

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
	-- Returning here also keeps the tool-slot bookkeeping below from immediately
	-- undoing the pose: its `target == nil` branch calls setPose(character, nil).
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
		setPose(character, nil)
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
