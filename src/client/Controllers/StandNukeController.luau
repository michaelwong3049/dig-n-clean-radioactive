--!strict
--[[
	StandNukeController.luau — draws the nuke on every display stand, still or full.

	WHAT IT READS. Every `Display{slot}` part tagged Shared/StandNuke.TAG, and the
	attributes ExhibitService publishes on it: which item, its quality, its scale and
	its seated pose (Shared/StandNuke says why the server no longer clones it).

	STILL BY DEFAULT, FULL UP CLOSE. Every stand shows its item's still copy: ~7
	meshes, finish baked in, no motion of its own. A few times a second the stands are
	ranked by distance to the camera, and the nearest Config/ItemFx DETAIL fullBudget
	inside fullRange (the same numbers ItemFxController's full tier uses) swap to the
	full model, where the spins, pulses and particles run. One that drops out of that
	set keeps its full model FULL_KEEP longer, so a stand at the edge doesn't flicker
	between the two. FAST MODE keeps every stand on its still copy.

	NEVER HALF-DRAWN. A model's meshes download one by one, and an undownloaded mesh
	draws as nothing. So a copy is shown only after its template's meshes have been
	preloaded (ContentProvider), and until then the stand keeps whatever it already
	shows: a new nuke's stand is empty for a moment rather than showing half a nuke,
	and a stand waiting on its full model keeps its still copy.

	SWAPS DON'T POP. The full model is painted (Shared/ItemFx.applyLook: finish,
	Fused/Irradiated colour) before it is parented, so its glowing parts are already
	lit on the first frame, not after ItemFxController gets round to activating it.
	It takes over the still copy's exact pose and hover phase (StationMotion's
	MotionAngle / MotionSeed), so the turn carries on through the swap. The copy it
	replaces stays underneath for SWAP_OVERLAP, because a freshly cloned model can take
	a few frames to reach the screen and the stand blinked empty in between.

	BUDGETED. Building copies shares SETUP_BUDGET per frame; at least one stand is
	built per frame, so walking onto a full base fills in over a few frames instead
	of freezing one.

	ALL OF IT IS LOCAL. The models live under the Display part on this client only;
	FastModeController, ItemFxController and StationMotionController pick them up by
	the same name, tag and attributes the server's clones used to carry.
]]

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ItemFx = require(Shared.ItemFx)
local ItemFxConfig = require(Shared.Config.ItemFx)
local ItemModels = require(Shared.ItemModels)
local Items = require(Shared.Config.Items)
local StandNuke = require(Shared.StandNuke)
local Prefs = require(script.Parent.Parent.Prefs)

local StandNukeController = {}

--- How often the stands are re-ranked by distance.
local RETIER_INTERVAL = 0.25

--- A stand that drops out of the full set keeps its full model this long (matches
--- ItemFxController's FX_KEEP).
local FULL_KEEP = 5

--- How long the copy being replaced stays up under its replacement (see build).
local SWAP_OVERLAP = 0.3

--- Seconds per frame spent building copies. One stand always goes through.
local SETUP_BUDGET = 0.002

--- Kit.MOTION_TAG, spelled out like StationMotionController does.
local MOTION_TAG = "StationMotion"

type Kind = "still" | "full"

type Stand = {
	display: BasePart,
	-- What the server says stands here (nil = nothing to draw).
	itemId: string?,
	modifier: string?,
	scale: number,
	pivot: CFrame?,
	rate: number,
	amp: number,
	-- Bumped whenever the server's facts change, so a stale build is dropped.
	version: number,
	-- What we want shown and what is shown.
	want: Kind,
	fullUntil: number,
	shown: Kind?,
	shownVersion: number,
	model: Model?,
	-- The hover's bob phase, kept for the stand's life so a swap doesn't jump.
	seed: number,
	distance: number,
	connections: { RBXScriptConnection },
}

local stands: { [BasePart]: Stand } = {}
local rng = Random.new()
local retierAt = 0

-- Template keys whose meshes are downloaded, and keys being preloaded right now.
local loaded: { [string]: boolean } = {}
local loading: { [string]: boolean } = {}

local function keyOf(itemId: string, kind: Kind): string
	return if kind == "still" then ItemModels.stillKey(itemId) else itemId
end

--- True once `key`'s template is here and its meshes are downloaded. Starts both if
--- not, and asks for a retier when they finish.
local function readyToShow(key: string): boolean
	if loaded[key] then
		return true
	end
	local template = ItemModels.template(key)
	if template == nil then
		ItemModels.onArrived(key, function()
			retierAt = 0
		end)
		return false
	end
	if not loading[key] then
		loading[key] = true
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ template })
			end)
			loaded[key] = true
			loading[key] = nil
			retierAt = 0
		end)
	end
	return false
end

--- The hover angle a model is at, relative to the stand's published pose.
local function angleOf(model: Model, home: CFrame): number
	local turn = model:GetPivot().Rotation * home.Rotation:Inverse()
	local _, y, _ = turn:ToEulerAnglesYXZ()
	return y
end

local function clear(stand: Stand)
	if stand.model then
		stand.model:Destroy()
		stand.model = nil
	end
	stand.shown = nil
end

--- Build `kind` for `stand` and put it in place of whatever it shows.
local function build(stand: Stand, kind: Kind)
	local itemId = stand.itemId :: string
	local pivot = stand.pivot :: CFrame
	local model = if kind == "still"
		then ItemModels.createStill(itemId, stand.modifier)
		else ItemModels.create(Items.get(itemId).model, itemId, stand.modifier)
	if model == nil then
		return
	end
	ItemFx.applyLook(model)
	model.Name = StandNuke.MODEL_NAME
	model:SetAttribute("ItemId", itemId)
	if stand.scale ~= 1 then
		model:ScaleTo(model:GetScale() * stand.scale)
	end
	model:PivotTo(pivot)

	local old = stand.model
	local current = if old and stand.shownVersion == stand.version then old:GetPivot() else nil
	model:SetAttribute("Motion", "hover")
	model:SetAttribute("MotionRate", stand.rate)
	model:SetAttribute("MotionAmp", stand.amp)
	model:SetAttribute("MotionSeed", stand.seed)
	if old and current then
		model:SetAttribute("MotionAngle", angleOf(old, pivot))
	end
	CollectionService:AddTag(model, MOTION_TAG)
	model.Parent = stand.display
	-- StationMotion took the published pose as home when the tag landed; start from
	-- the old copy's exact pose so a stand that isn't hovering right now doesn't snap.
	if current then
		model:PivotTo(current)
	end
	if old and current then
		-- The same nuke swapping copies: a fresh model can take a few frames to reach
		-- the screen, and dropping the old one at once left the stand blank for
		-- those frames. Both sit in the same pose with the same look, so the old one
		-- just stays underneath for SWAP_OVERLAP.
		task.delay(SWAP_OVERLAP, function()
			old:Destroy()
		end)
	elseif old then
		old:Destroy()
	end
	stand.model = model
	stand.shown = kind
	stand.shownVersion = stand.version
end

--- Read the server's facts off the Display part.
local function refresh(stand: Stand)
	local display = stand.display
	local N = StandNuke.ATTR
	local item = display:GetAttribute(N.item)
	local pivot = display:GetAttribute(N.pivot)
	stand.itemId = if type(item) == "string" and typeof(pivot) == "CFrame" then item else nil
	stand.modifier = display:GetAttribute(N.modifier) :: string?
	stand.scale = (display:GetAttribute(N.scale) :: number?) or 1
	stand.pivot = if typeof(pivot) == "CFrame" then pivot else nil
	stand.rate = (display:GetAttribute(N.rate) :: number?) or 0.25
	stand.amp = (display:GetAttribute(N.amp) :: number?) or 0.12
	stand.version += 1
	if stand.itemId == nil then
		clear(stand)
	end
	retierAt = 0
end

local function untrack(display: Instance)
	local stand = stands[display :: BasePart]
	if stand == nil then
		return
	end
	stands[display :: BasePart] = nil
	for _, connection in stand.connections do
		connection:Disconnect()
	end
	clear(stand)
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or stands[instance] then
		return
	end
	local display = instance :: BasePart
	local stand: Stand = {
		display = display,
		itemId = nil,
		modifier = nil,
		scale = 1,
		pivot = nil,
		rate = 0.25,
		amp = 0.12,
		version = 0,
		want = "still",
		fullUntil = 0,
		shown = nil,
		shownVersion = -1,
		model = nil,
		seed = rng:NextNumber(0, 1000),
		distance = math.huge,
		connections = {},
	}
	stands[display] = stand
	for _, name in StandNuke.ATTR do
		table.insert(
			stand.connections,
			display:GetAttributeChangedSignal(name):Connect(function()
				-- Several attributes land together; read them once, next frame.
				task.defer(function()
					if stands[display] == stand then
						refresh(stand)
					end
				end)
			end)
		)
	end
	table.insert(
		stand.connections,
		display.AncestryChanged:Connect(function()
			if not display:IsDescendantOf(Workspace) then
				untrack(display)
			end
		end)
	)
	refresh(stand)
end

local ranked: { Stand } = {}

--- Rank the stands by distance and decide which ones want their full model.
local function retier(eye: Vector3, now: number)
	table.clear(ranked)
	for _, stand in stands do
		if stand.itemId then
			stand.distance = (stand.display.Position - eye).Magnitude
			table.insert(ranked, stand)
		end
	end
	table.sort(ranked, function(a, b)
		return a.distance < b.distance
	end)
	local detail = ItemFxConfig.DETAIL[Prefs.get("graphics")] or ItemFxConfig.DETAIL.high
	local fast = Prefs.get("fastMode") == true
	local fullLeft = detail.fullBudget
	for _, stand in ranked do
		if not fast and fullLeft > 0 and stand.distance <= detail.fullRange then
			fullLeft -= 1
			stand.fullUntil = now + FULL_KEEP
		elseif fast then
			stand.fullUntil = 0
		end
		stand.want = if now < stand.fullUntil then "full" else "still"
	end
end

--- Bring one stand closer to what it wants. Returns true if it built something.
local function settle(stand: Stand): boolean
	local itemId = stand.itemId
	-- `ranked` is from the last retier; a stand that streamed out since is gone.
	if itemId == nil or stand.pivot == nil or stands[stand.display] ~= stand then
		return false
	end
	local current = stand.shownVersion == stand.version
	if current and stand.shown == stand.want then
		return false
	end
	if readyToShow(keyOf(itemId, stand.want)) then
		build(stand, stand.want)
		return true
	end
	-- Waiting on the full model: keep the still copy, or put it up if nothing
	-- current is showing yet.
	if stand.want == "full" and not (current and stand.shown == "still") and readyToShow(keyOf(itemId, "still")) then
		build(stand, "still")
		return true
	end
	-- Nothing ready for the new item yet: don't leave the old item standing there.
	if not current and stand.model then
		clear(stand)
	end
	return false
end

function StandNukeController.start()
	for _, instance in CollectionService:GetTagged(StandNuke.TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(StandNuke.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(StandNuke.TAG):Connect(untrack)
	Prefs.observe("fastMode", function()
		retierAt = 0
	end)
	Prefs.observe("graphics", function()
		retierAt = 0
	end)

	RunService.Heartbeat:Connect(function()
		if next(stands) == nil then
			return
		end
		local now = os.clock()
		if now >= retierAt then
			retierAt = now + RETIER_INTERVAL
			local camera = Workspace.CurrentCamera
			retier(if camera then camera.CFrame.Position else Vector3.zero, now)
		end
		local deadline = now + SETUP_BUDGET
		local built = false
		-- Nearest first, so the stands in front of you fill in first.
		for _, stand in ranked do
			if built and os.clock() >= deadline then
				break
			end
			if settle(stand) then
				built = true
			end
		end
	end)
end

return StandNukeController
