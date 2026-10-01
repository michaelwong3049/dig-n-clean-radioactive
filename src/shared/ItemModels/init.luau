--!strict
--[[
	ItemModels — the catalogue's versioned visual-asset registry.

	Config.Items stores only a small string key. This module owns the model
	resolution, so gameplay services never need a growing chain of item-specific
	requires. Missing keys return nil and deliberately fall back to the rarity-
	coloured placeholder block (see WashService/ToolService/ExhibitService's own
	`model == nil` branches) while the rest of the catalogue is modelled.

	feat/imported-nuke-gameplay RETIRES THE PROCEDURAL CAPSULE SYSTEM. It used to
	be that every item resolved through one of 7 rarity-tier factories
	(NukeCommon..NukeAnomaly, NukeBase.luau), optionally bolting on a per-item
	`signature` prop from NukeSignatures.luau (7/68 items ever got one). Both are
	gone now, on request: an item either has real hand-imported mesh art or it
	has no model at all and falls back to the placeholder cube everywhere --
	there is no procedural middle tier any more. `modelKey` is now just a flag
	(only "ImportedNuke" is meaningful); which mesh to build is resolved by
	`itemId`.

	IMPORTED MESH TEMPLATES LIVE IN ReplicatedStorage.Assets.ImportedNukeTemplates,
	NOT Shared -- same convention Assets.Tools.Detector already uses, and for
	the same reason (see Shared/ToolModels/init.luau's header): that geometry
	is built once, elevated-only (tools/studio-migrations/import-nuke-models.luau,
	run from Studio's Command Bar, since MeshPart.MeshId cannot be written by an
	ordinary Instance.new in this place), and Assets is NOT Rojo-managed the way
	Shared is, so a runtime-installed folder there survives every sync instead
	of being deleted as an "unknown instance." `create` just Clones whatever
	template is already parked there; a place that predates the migration (or
	whose migration hasn't been re-run since a fresh Studio session) has no
	template yet, and this returns nil -- the same graceful degrade as any
	other unmodelled item.

	THE TEMPLATES DO NOT REACH CLIENTS AT JOIN. Services/ModelCacheService moves the
	folder to ServerStorage as the server boots (10.5k parts every player used to
	download before they could move). A client asks for the ids it is about to draw
	(`request`, or `create` asks by itself) and gets copies in its own
	PlayerGui.NukeModels. Until one lands, `create` returns nil -- the placeholder path
	every caller already has -- and `onArrived` lets a caller repaint when it does.

	EVERY CLONE IS TAGGED FOR ITS EFFECTS HERE (Shared/ItemFx), because this is the
	one door every display context comes through. The glow, light and motion itself
	is client-side (ItemFxController) and waits for the crust to come off.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ItemFx = require(script.Parent.ItemFx)

local IMPORTED_NUKE_KEY = "ImportedNuke"
local TEMPLATE_PATH = { "Assets", "ImportedNukeTemplates" }
local SERVER_FOLDER = "ImportedNukeTemplates" -- ServerStorage, see Services/ModelCacheService
local CLIENT_CACHE = "NukeModels" -- PlayerGui, one per player

local ItemModels = {}

ItemModels.SERVER_FOLDER = SERVER_FOLDER
ItemModels.CLIENT_CACHE = CLIENT_CACHE
ItemModels.TEMPLATE_PATH = TEMPLATE_PATH

-- Only a running client asks the server for models. Edit mode reports IsClient()
-- true (see Shared/Net), so it is ruled out by IsRunning.
local isPlayClient = RunService:IsClient() and not RunService:IsServer() and RunService:IsRunning()

function ItemModels.has(modelKey: string?): boolean
	return modelKey == IMPORTED_NUKE_KEY
end

--- The folder the templates sit in as this place was saved: Assets in
--- ReplicatedStorage. The server moves it out at boot; Studio's edit tools still see it.
local function replicatedFolder(): Instance?
	local folder: Instance = ReplicatedStorage
	for _, name in TEMPLATE_PATH do
		local next_ = folder:FindFirstChild(name)
		if next_ == nil then
			return nil
		end
		folder = next_
	end
	return folder
end

local cache: Instance? = nil
local requested: { [string]: boolean } = {}
local waiters: { [string]: { () -> () } } = {}
local watching = false

local function flush(itemId: string)
	local list = waiters[itemId]
	if list == nil then
		return
	end
	waiters[itemId] = nil
	for _, callback in list do
		task.spawn(callback)
	end
end

--- Find this player's cache once the server has made it, and wake anyone waiting on
--- a model when its copy lands.
local function watchCache()
	if watching or not isPlayClient then
		return
	end
	watching = true
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local found = playerGui:WaitForChild(CLIENT_CACHE)
		cache = found
		found.ChildAdded:Connect(function(child)
			flush(child.Name)
		end)
		for _, child in found:GetChildren() do
			flush(child.Name)
		end
	end)
end

local function importedNukeTemplate(itemId: string): Model?
	local template = nil
	local server = ServerStorage:FindFirstChild(SERVER_FOLDER)
	if server then
		template = server:FindFirstChild(itemId)
	end
	if template == nil then
		local replicated = replicatedFolder()
		template = if replicated then replicated:FindFirstChild(itemId) else nil
	end
	if template == nil and cache then
		template = cache:FindFirstChild(itemId)
	end
	return if template and template:IsA("Model") then template else nil
end

--- True once `itemId`'s model can be built here without waiting.
function ItemModels.ready(itemId: string): boolean
	return importedNukeTemplate(itemId) ~= nil
end

--- Ask the server for these models, ahead of drawing them. Each id is asked for once;
--- ids with no model are simply never sent. A no-op anywhere but a running client.
function ItemModels.request(itemIds: { string })
	if not isPlayClient then
		return
	end
	watchCache()
	local wanted = {}
	for _, itemId in itemIds do
		if type(itemId) == "string" and not requested[itemId] and importedNukeTemplate(itemId) == nil then
			requested[itemId] = true
			table.insert(wanted, itemId)
		end
	end
	if #wanted > 0 then
		-- Required here, not at the top: the server and Studio's command bar require
		-- this module too, and Net on a client waits for the server's remotes.
		local Net = require(script.Parent.Net)
		Net.get("NukeModels"):FireServer(wanted)
	end
end

--- Call `callback` once `itemId`'s model is ready (right away if it already is).
--- Asks for it too. For callers that drew a placeholder and want to repaint.
function ItemModels.onArrived(itemId: string, callback: () -> ())
	if ItemModels.ready(itemId) then
		task.spawn(callback)
		return
	end
	if not isPlayClient then
		return
	end
	local list = waiters[itemId]
	if list == nil then
		list = {}
		waiters[itemId] = list
	end
	table.insert(list, callback)
	ItemModels.request({ itemId })
end

--- Yield until `itemId`'s model is ready or `timeout` seconds pass. True if it is.
function ItemModels.await(itemId: string, timeout: number): boolean
	if ItemModels.ready(itemId) then
		return true
	end
	if not isPlayClient then
		return false
	end
	local thread = coroutine.running()
	local done = false
	ItemModels.onArrived(itemId, function()
		if not done then
			done = true
			task.spawn(thread, true)
		end
	end)
	task.delay(timeout, function()
		if not done then
			done = true
			task.spawn(thread, false)
		end
	end)
	return coroutine.yield()
end

--- `modifier` is the dig's Rarity.MODIFIERS roll; a Pristine one gets its own shine.
function ItemModels.create(modelKey: string?, itemId: string?, modifier: string?): Model?
	if modelKey == nil then
		return nil
	end

	if modelKey == IMPORTED_NUKE_KEY then
		local template = if itemId then importedNukeTemplate(itemId) else nil
		if template == nil then
			if itemId then
				ItemModels.request({ itemId })
			end
			return nil
		end
		local clone = template:Clone()
		ItemFx.tag(clone, itemId, modifier)
		return clone
	end

	warn(`[items] unknown model key "{modelKey}"`)
	return nil
end

--- Item factories author placement rotations as attributes so a flat object such
--- as the cap can be tilted toward the player without forcing the same tilt onto a
--- future upright object. Unknown contexts and missing attributes mean identity.
function ItemModels.rotation(model: Model, context: string): CFrame
	local value = model:GetAttribute(`{context}Rotation`)
	return if typeof(value) == "CFrame" then value else CFrame.identity
end

return ItemModels
