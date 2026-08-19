--!strict
--[[
	ToolService.lua — puts the right thing in the player's hands.

	Server-side on purpose. On a shared server (PLAN §1) what someone is holding is
	information other players should get for free: seeing a stranger out in the ash
	swinging a detector, or hunched over a magnet hauling something up, is the cheapest
	storytelling in the game. A client-only cosmetic would be invisible to everyone else.

	WHICH TOOL, in priority order:
	  at the decon station -> Cleaner   (you are here to scrub)
	  standing on a signal -> Magnet    (found it — now get the magnet out)
	  standing in a zone   -> Detector  (sweeping is the default verb)
	  otherwise            -> nothing   (base camp, hands free)

	The magnet keys off STANDING ON a signal, not off actively hauling. Hauling lasts
	a couple of seconds, so keying it to that made the model flicker in and out faster
	than anyone could register it.

	HOLD OFFSETS LIVE ON THE MODELS, not in here. Each tool carries a `HoldCFrame`
	attribute, so the position and angle in the hand can be nudged in Studio's property
	panel against a live character instead of by editing code and rebooting — which is
	the only sane way to tune something you have to look at to judge.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local DigService = require(script.Parent.DigService)
local DeconService = require(script.Parent.DeconService)

local ToolService = {}

local LIBRARY = ReplicatedStorage.Assets.Tools
local HELD_NAME = "HeldTool"

local equipped: { [Player]: string? } = {}

-- Track name in Assets/Tools -> the key it upgrades under in profile.gear.
local GEAR_KEY = { Detector = "detector", Magnet = "magnet", Cleaner = "cleaner" }

-- ── Two-handed carry ──────────────────────────────────────────────────────
--
-- A detector is carried in both hands, and those hands must not swing with the walk
-- cycle. Driving the joint's Transform cannot achieve that: the animator re-solves
-- every frame regardless of which RenderStep priority the write happens at. Measured
-- at three priorities; the arm moved 0.01 studs.
--
-- So the shoulder joint is switched OFF and a rigid Weld holds the limb instead. The
-- animator keeps writing to a disabled joint and moves nothing.
--
-- TWO RIGS EXIST AND THIS MUST HANDLE BOTH. Classic characters join limbs with
-- Motor6D (Part0/Part1/C0/C1); newer ones use AnimationConstraint driving a pair of
-- Attachments, with a BallSocketConstraint doing the physical join. Assuming Motor6D
-- made this silently do nothing on a constraint rig — no error, just an arm that
-- carried on swinging.
--
-- LEAVE THE BALL SOCKET ENABLED. Measured stride spread of the hand:
--     animated (baseline) .... 0.879 studs
--     weld, ball socket ON ... 0.319   <-- steadiest
--     weld, ball socket OFF .. 0.639   limb goes half-limp without it
-- The remaining 0.319 is the UpperTorso swaying and carrying the arm with it, which
-- is what a carried tool should do.
--
-- Server-side on purpose: arm posing on the client would not replicate, and on a
-- shared server everyone else would watch you carry it one-handed.
-- THE WHOLE ARM CHAIN, not just the shoulders. Locking shoulders alone left the
-- elbows and wrists still animating, and measurement showed exactly where the
-- jiggle entered:
--     tool grip ....... 0.000 studs   welded to the root, rock steady
--     upper arm ....... 0.133         shoulder locked, drifts with the torso
--     hand ............ 0.414         +0.28 added below the shoulder
-- The hands were sliding off a tool that was not moving.
local ARM_POSE = {
	{ limb = "RightUpperArm", joint = "RightShoulder", pitch = 35, roll = -25, toRoot = true, socket = "RightShoulderBallSocket" },
	{ limb = "RightLowerArm", joint = "RightElbow", pitch = 0, roll = 0 },
	{ limb = "RightHand", joint = "RightWrist", pitch = 0, roll = 0 },
	{ limb = "LeftUpperArm", joint = "LeftShoulder", pitch = 35, roll = 25, toRoot = true, socket = "LeftShoulderBallSocket" },
	{ limb = "LeftLowerArm", joint = "LeftElbow", pitch = 0, roll = 0 },
	{ limb = "LeftHand", joint = "LeftWrist", pitch = 0, roll = 0 },
}
local LOCK_NAME = "ArmLock"

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

local function unlockArms(character: Model)
	for _, spec in ARM_POSE do
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

local function lockArms(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local spine = torsoFromRoot(character)

	for _, spec in ARM_POSE do
		local limb = character:FindFirstChild(spec.limb)
		local joint = limb and limb:FindFirstChild(spec.joint)
		if joint and limb:FindFirstChild(LOCK_NAME) == nil then
			local part0, part1, c0, c1 = jointFrames(joint)
			if part0 and part1 and c0 and c1 then
				local weld = Instance.new("Weld")
				weld.Name = LOCK_NAME
				weld.Part1 = part1
				weld.C1 = c1

				-- Shoulders re-anchor to the root; the rest of the chain hangs off
				-- the limb above it, which is already root-locked by then.
				if spec.toRoot and root then
					weld.Part0 = root
					weld.C0 = spine * c0 * CFrame.Angles(math.rad(spec.pitch), 0, math.rad(spec.roll))
				else
					weld.Part0 = part0
					weld.C0 = c0 * CFrame.Angles(math.rad(spec.pitch), 0, math.rad(spec.roll))
				end

				weld.Parent = limb
				pcall(function()
					(joint :: any).Enabled = false
				end)

				-- With the shoulder welded to the ROOT, the shoulder ball socket stops
				-- being harmless and starts tying the torso to the root through the
				-- arm — which flattens the walk cycle. Measured head bob: 0.139 with it
				-- on, 0.240 with it off, against a 0.33 free-walking baseline. The weld
				-- already holds the limb rigidly, so the socket has no job left to do.
				if spec.socket then
					local socket = limb:FindFirstChild(spec.socket)
					if socket then
						pcall(function()
							(socket :: any).Enabled = false
						end)
					end
				end
			else
				warn(`[tool] unrecognised joint "{joint.ClassName}" on {spec.limb} — arm will still swing`)
			end
		end
	end
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
--- for both the tool AND the arms. They have to share one reference frame or the
--- hands drift off the grip, and it has to be the frame that does not bob:
---
---   tool on root, arms on torso .. hands slid 0.41 studs off the grip
---   tool on torso, arms on torso .. hands perfect, but the coil dug 0.26 into the
---                                   sand every time the chest dipped
---   both on root ................. hands perfect AND the coil holds its height
---
--- The torso still bobs through its full walk cycle underneath — only the carried
--- assembly is exempt, which is what carrying something steady actually looks like.
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

local function equip(character: Model, track: string, tier: number)
	local folder = LIBRARY:FindFirstChild(track)
	local template = if folder then folder:FindFirstChild(`T{tier}`) else nil
	if template == nil or not template:IsA("Model") or template.PrimaryPart == nil then
		return false
	end

	local anchor = attachPointOf(character, template)
	if anchor == nil then
		return false
	end

	unequip(character)

	-- Only the detector is carried two-handed; everything else swings naturally.
	if track == "Detector" then
		lockArms(character)
	else
		unlockArms(character)
	end

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

	return true
end

local function wanted(player: Player): string?
	if DeconService.stationOf(player) == "decon" then
		return "Cleaner"
	end
	if DigService.isOverSignal(player) then
		return "Magnet"
	end
	if DigService.zoneOf(player) ~= nil then
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

	-- Tier comes from the profile, so buying an upgrade changes what is in your hands
	-- the moment it lands — no reconnect, no re-equip step.
	local tier = 1
	if target then
		local data = DataService.data(player)
		if data then
			tier = data.gear[GEAR_KEY[target]] or 1
		end
	end

	local current = character:FindFirstChild(HELD_NAME)
	local currentName = if current then current:GetAttribute("ToolName") else nil
	local currentTier = if current then current:GetAttribute("Tier") else nil

	if target == currentName and tier == currentTier then
		return
	end

	if target == nil then
		unequip(character)
		unlockArms(character)
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
