--[[
	ToolMotionController.lua — the moving parts of the top magnets: gyro rings
	tumbling, halos and their balls wheeling round, diamonds circling a core, bands
	riding a wave up the poles.

	Shared/ToolFX rigs them on the server: each moving part hangs off its magnet's
	`bend` by a "ToolMotion"-tagged Weld whose C0 is the rest pose, with the motion
	stamped on it as attributes (Pivot, Axis in the bend's frame; Spin rad/s; Bob
	studs; Hz; Phase). This file is the only thing that moves them. In a hand the
	parts are unanchored and the weld's C0 carries them; on a shop rack everything
	is anchored, so the part's CFrame is set straight off the bend instead.

	Pose is a pure function of the clock, recomputed from the rest pose each frame,
	so nothing drifts and every copy of a magnet turns in step. Only welds near the
	camera animate, re-sorted twice a second, like StationMotionController.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ToolMotion = {}

--- Shared/ToolFX's MOTION_TAG.
local MOTION_TAG = "ToolMotion"

--- Studs from the camera inside which anything animates.
local NEAR = 120
local RESORT = 0.5

type Entry = {
	weld: Weld,
	rest: CFrame,
	pivot: Vector3,
	axis: Vector3,
	spin: number,
	bob: number,
	hz: number,
	phase: number,
}

local entries: { [Weld]: Entry } = {}
local active: { Entry } = {}
local sinceResort = math.huge

local function num(weld: Weld, name: string, default: number): number
	local v = weld:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function vec(weld: Weld, name: string, default: Vector3): Vector3
	local v = weld:GetAttribute(name)
	return if typeof(v) == "Vector3" then v else default
end

local function register(weld: Instance)
	if not weld:IsA("Weld") then
		return
	end
	entries[weld] = {
		weld = weld,
		rest = weld.C0,
		pivot = vec(weld, "Pivot", weld.C0.Position),
		axis = vec(weld, "Axis", Vector3.yAxis),
		spin = num(weld, "Spin", 0),
		bob = num(weld, "Bob", 0),
		hz = num(weld, "Hz", 0.5),
		phase = num(weld, "Phase", 0),
	}
	sinceResort = math.huge
end

local function unregister(weld: Instance)
	entries[weld :: Weld] = nil
	sinceResort = math.huge
end

local function resort()
	table.clear(active)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	for weld, entry in entries do
		local bend = weld.Part0
		if bend and weld.Part1 and weld:IsDescendantOf(Workspace) and (bend.Position - eye).Magnitude <= NEAR then
			table.insert(active, entry)
		end
	end
end

local moveParts: { BasePart } = {}
local moveTo: { CFrame } = {}

local function step(dt: number)
	sinceResort += dt
	if sinceResort >= RESORT then
		sinceResort = 0
		resort()
	end

	local now = os.clock()
	table.clear(moveParts)
	table.clear(moveTo)
	for _, e in active do
		local weld = e.weld
		local bend, part = weld.Part0, weld.Part1
		if bend == nil or part == nil then
			continue
		end
		local pose = e.rest
		if e.spin ~= 0 then
			pose = CFrame.new(e.pivot) * CFrame.fromAxisAngle(e.axis, (e.spin * now) % (math.pi * 2)) * CFrame.new(-e.pivot) * pose
		end
		if e.bob ~= 0 then
			pose = CFrame.new(0, e.bob * math.sin(now * e.hz * math.pi * 2 + e.phase), 0) * pose
		end
		if part.Anchored then
			table.insert(moveParts, part)
			table.insert(moveTo, bend.CFrame * pose)
		else
			weld.C0 = pose
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveTo, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function ToolMotion.start()
	for _, weld in CollectionService:GetTagged(MOTION_TAG) do
		register(weld)
	end
	CollectionService:GetInstanceAddedSignal(MOTION_TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(MOTION_TAG):Connect(unregister)
	RunService.RenderStepped:Connect(step)
end

return ToolMotion
