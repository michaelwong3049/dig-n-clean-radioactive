--[[
	WashController.lua — the wash bay, rendered. Camera, blobs, and the stream.

	THE SERVER OWNS EVERYTHING THAT COUNTS. This file reports aim and intent — "I am
	spraying, at patch 3" — and draws whatever WashState comes back. It never decides
	that a patch came off. That is the same boundary the old scrub timer had
	(ARCHITECTURE.md, "Server/client boundary"), and it is why a modified client can
	pick a different patch to work on (which it could always do by clicking a different
	row) but cannot clean an Anomaly instantly.

	THE CAMERA MUST COME BACK ON EVERY PATH, and this is the one thing in here that is
	genuinely dangerous. A player stuck in a Scriptable camera has no way out short of
	rejoining, and there are five ways a session ends: finishing, walking out of the
	leash, the item leaving the bag, a dead profile, and a respawn. All five arrive
	here as the same thing — a nil WashState — and `stop()` is idempotent so it does
	not matter how many times or in what order they land. CharacterAdded also calls it
	blind, because a respawn mid-wash is the one case where no remote fires at all.

	PATCH BLOBS ARE PLACED DETERMINISTICALLY, from the patch's index through a
	golden-angle spiral. They have to be: WashState arrives at 10 Hz, and blobs placed
	with math.random would swarm over the item like flies. Same index in, same point
	on the item out, every tick.

	GREEN, AND YES, DELIBERATELY. Kit.C's palette header says nothing outside a stage
	may use Neon in the hazard greens, so that "glowing green" only ever means the
	ooze. A contamination patch is the SAME SUBSTANCE — PLAN §2 step 4 calls them
	"glowing hotspots" and they are literally the fallout you are hosing off — so
	painting them any other colour would be the actual dilution of that rule, not the
	respect of it. The exception is narrow and stays narrow: client-local, only ever
	visible during a session you opted into, and never on world geometry.

	THE SPRAY IS CLIENT-LOCAL, which is against ToolService's "what you hold is public
	storytelling" rule. Defensible only because every cleansing station sits on its
	owner's own base, so there is no bystander to tell the story to — and the ITEM on
	the tub is server-side (WashService) precisely so the part that IS worth seeing
	from outside is seen. Written down so nobody re-derives it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local Wash = {}

-- Kit.C.oozeBright. Duplicated rather than required because build/ lives in
-- ServerScriptService and a client cannot reach it — the same reason Tuning.AURA_TAG
-- exists as a shared constant. If the ooze is ever retuned, this follows it.
local PATCH_GREEN = Color3.fromHex("6BEE2E")
local PATCH_CRUSTED = Color3.fromHex("3A3128")

local SPRAY_RANGE = 40

local state: any = nil
local blobs: { [number]: BasePart } = {}
local folder: Instance? = nil
local beam: Beam? = nil
local originAttach: Attachment? = nil
local hitAttach: Attachment? = nil
local spraying = false
local aimedIndex: number? = nil
local renderBound = false

local inputRemote: any = nil

-- ── Geometry helpers ────────────────────────────────────────────────

local function itemPivot(): (CFrame?, Vector3?)
	local stand = state and state.stand
	if stand == nil or not stand:IsA("BasePart") then
		return nil, nil
	end
	local item = stand:FindFirstChild("WashItem")
	if item == nil then
		-- The server places it; on the very first tick it may not have replicated yet.
		return stand.CFrame, Vector3.new(1.4, 1.4, 1.4)
	end
	if item:IsA("BasePart") then
		return item.CFrame, item.Size
	end
	if item:IsA("Model") then
		local cf, size = item:GetBoundingBox()
		return cf, size
	end
	return stand.CFrame, Vector3.new(1.4, 1.4, 1.4)
end

--- A stable point on the item's surface for patch `index`. Golden-angle spiral over
--- a sphere, scaled to the item's own bounding box, so patches spread evenly and
--- land in the same place every tick regardless of how many are left.
local function patchPoint(index: number, pivot: CFrame, size: Vector3): Vector3
	local golden = 2.39996323
	local t = (index - 0.5) / 8 -- 8, not #patches: removing one must not move the rest
	local y = 1 - 2 * math.min(t, 1)
	local radius = math.sqrt(math.max(0, 1 - y * y))
	local theta = golden * index
	local dir = Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
	local extent = (size * 0.5) + Vector3.new(0.12, 0.12, 0.12)
	return (pivot * CFrame.new(dir * extent)).Position
end

-- ── Build / tear down ───────────────────────────────────────────────

local function clearBlobs()
	for _, blob in blobs do
		blob:Destroy()
	end
	table.clear(blobs)
end

local function ensureFolder(): Instance
	if folder == nil or folder.Parent == nil then
		local made = Instance.new("Folder")
		made.Name = "WashBayFX"
		made.Parent = Workspace
		folder = made
	end
	return folder :: Instance
end

local function ensureBeam()
	if beam and beam.Parent then
		return
	end
	local parent = ensureFolder()

	local originPart = Instance.new("Part")
	originPart.Name = "SprayOrigin"
	originPart.Size = Vector3.new(0.1, 0.1, 0.1)
	originPart.Transparency = 1
	originPart.Anchored = true
	originPart.CanCollide = false
	originPart.Parent = parent
	originAttach = Instance.new("Attachment")
	originAttach.Parent = originPart

	local hitPart = Instance.new("Part")
	hitPart.Name = "SprayHit"
	hitPart.Size = Vector3.new(0.1, 0.1, 0.1)
	hitPart.Transparency = 1
	hitPart.Anchored = true
	hitPart.CanCollide = false
	hitPart.Parent = parent
	hitAttach = Instance.new("Attachment")
	hitAttach.Parent = hitPart

	local made = Instance.new("Beam")
	made.Attachment0 = originAttach
	made.Attachment1 = hitAttach
	made.Width0 = 0.25
	made.Width1 = 0.55
	made.LightEmission = 1
	made.Transparency = NumberSequence.new(0.25)
	made.FaceCamera = true
	made.Enabled = false
	made.Parent = parent
	beam = made
end

--- Idempotent on purpose — see the header. Every exit path calls this, sometimes
--- more than once, sometimes when no session was ever running.
local function stop()
	state = nil
	spraying = false
	aimedIndex = nil

	clearBlobs()
	if folder then
		folder:Destroy()
		folder = nil
	end
	beam, originAttach, hitAttach = nil, nil, nil

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

-- ── Render ──────────────────────────────────────────────────────────

local function paintBlobs()
	if state == nil then
		return
	end
	local pivot, size = itemPivot()
	if pivot == nil or size == nil then
		return
	end

	local live: { [number]: boolean } = {}
	for _, patch in state.patches do
		live[patch.index] = true

		local blob = blobs[patch.index]
		if blob == nil or blob.Parent == nil then
			blob = Instance.new("Part")
			blob.Name = `Patch{patch.index}`
			blob.Shape = Enum.PartType.Ball
			blob.Anchored = true
			blob.CanCollide = false
			blob.CanQuery = false
			blob.Material = Enum.Material.Neon
			blob.Parent = ensureFolder()
			blobs[patch.index] = blob
		end

		-- Harder patches are bigger, so "which one is the wall" is legible before you
		-- ever aim at it. A blocked patch is crusted and matte — the stream visibly
		-- does nothing to it, which is the Quarantine Locker taught in 3D.
		local base = 0.30 + patch.hardness * 0.07
		local scale = base
		if patch.index == state.targetIndex and (state.progress or 0) > 0 then
			scale = base * (1 - 0.65 * state.progress)
		end

		blob.Size = Vector3.new(scale, scale, scale) * 2
		blob.Position = patchPoint(patch.index, pivot, size)
		blob.Color = if patch.blocked then PATCH_CRUSTED else PATCH_GREEN
		blob.Material = if patch.blocked then Enum.Material.Slate else Enum.Material.Neon
		blob.Transparency = if patch.blocked then 0.1 else 0.15
	end

	for index, blob in blobs do
		if not live[index] then
			blob:Destroy()
			blobs[index] = nil
		end
	end
end

--- The hose muzzle. The Cleaner models are hand-authored and gitignored
--- (ARCHITECTURE.md's "remaining gap"), so they have a PrimaryPart but almost
--- certainly no muzzle point. Prefer a `Nozzle` attachment if one is ever added in
--- Studio; fall back to the front face of the model's own primary part, then to the
--- hand. No code change needed the day the attachment appears.
local function nozzleCFrame(): CFrame?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end
	local tool = character:FindFirstChild("HeldTool")
	if tool and tool:IsA("Model") and tool.PrimaryPart then
		local nozzle = tool.PrimaryPart:FindFirstChild("Nozzle")
		if nozzle and nozzle:IsA("Attachment") then
			return nozzle.WorldCFrame
		end
		return tool.PrimaryPart.CFrame * CFrame.new(0, 0, -tool.PrimaryPart.Size.Z * 0.5)
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand.CFrame
	end
	return nil
end

--- Which patch the player is pointing at: the reachable blob whose centre sits
--- closest to the aim ray. Nearest-to-ray rather than a raycast, because a 0.5-stud
--- ball at eight studs is a cruel thing to ask anyone to hit exactly.
local function aimAt(ray: Ray): number?
	local best: number? = nil
	local bestDistance = math.huge
	for index, blob in blobs do
		local toBlob = blob.Position - ray.Origin
		local along = toBlob:Dot(ray.Direction.Unit)
		if along > 0 and along < SPRAY_RANGE then
			local perpendicular = (toBlob - ray.Direction.Unit * along).Magnitude
			if perpendicular < bestDistance and perpendicular < 2.2 then
				best, bestDistance = index, perpendicular
			end
		end
	end
	return best
end

local function onRender()
	if state == nil then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	-- The camera anchor is a part in the station, so framing is tuned in Studio
	-- against live geometry rather than by editing numbers here.
	local stand = state.stand
	local anchor = if stand and stand.Parent then stand.Parent:FindFirstChild("WashCam") else nil
	if anchor and anchor:IsA("BasePart") then
		camera.CFrame = anchor.CFrame
	end

	paintBlobs()

	-- ScreenPointToRay, NOT ViewportPointToRay. GetMouseLocation() returns a point
	-- that INCLUDES the topbar inset, and ViewportPointToRay expects one that does
	-- not — pairing those two puts the aim ray ~36px above the cursor, which reads as
	-- the hose being subtly, maddeningly miscalibrated.
	local mouse = UserInputService:GetMouseLocation()
	local aimRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local target = aimAt(aimRay)

	if target ~= aimedIndex then
		aimedIndex = target
		if inputRemote then
			inputRemote:FireServer({ spraying = spraying, patchIndex = aimedIndex })
		end
	end

	if beam and originAttach and hitAttach then
		local nozzle = nozzleCFrame()
		local show = spraying and nozzle ~= nil
		beam.Enabled = show
		if show and nozzle then
			local blob = if aimedIndex then blobs[aimedIndex] else nil
			local hitPoint = if blob
				then blob.Position
				else aimRay.Origin + aimRay.Direction.Unit * 12
			originAttach.WorldCFrame = nozzle
			hitAttach.WorldPosition = hitPoint
		end
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────

local function beginSession()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	ensureBeam()

	if beam then
		local colour = Color3.fromHex(state.liquidColor or "6FD5E8")
		beam.Color = ColorSequence.new(colour)
	end

	if not renderBound then
		RunService:BindToRenderStep("WashBay", Enum.RenderPriority.Camera.Value + 1, onRender)
		renderBound = true
	end
end

function Wash.start()
	inputRemote = Net.get("WashInput")

	Net.get("WashState").OnClientEvent:Connect(function(payload)
		if payload == nil then
			if renderBound then
				RunService:UnbindFromRenderStep("WashBay")
				renderBound = false
			end
			stop()
			return
		end

		local fresh = state == nil
		state = payload
		if fresh then
			beginSession()
		elseif beam then
			-- The loaded liquid can change mid-wash: run a canister dry and you drop
			-- back to Plain Water, and the stream has to say so.
			beam.Color = ColorSequence.new(Color3.fromHex(payload.liquidColor or "6FD5E8"))
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or state == nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			spraying = true
			inputRemote:FireServer({ spraying = true, patchIndex = aimedIndex })
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			spraying = false
			if state ~= nil then
				inputRemote:FireServer({ spraying = false, patchIndex = aimedIndex })
			end
		end
	end)

	-- A respawn mid-wash fires no remote at all: the server's leash check sees a
	-- character with no root and ends the session silently. This is the only thing
	-- standing between that and a player left in a Scriptable camera.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if renderBound then
			RunService:UnbindFromRenderStep("WashBay")
			renderBound = false
		end
		stop()
	end)
end

return Wash
