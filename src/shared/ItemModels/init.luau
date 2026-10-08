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

	STILL COPIES. Assets.NukeStillTemplates holds a ~7-mesh copy of most nukes, every
	effect part merged in with its Config/ItemFx finish baked on (Shared/StandNuke says
	why). It moves to ServerStorage the same way and is fetched the same way, under the
	cache name `stillKey(itemId)`. A nuke with no still copy (its meshes belong to
	another account) gets its full model under that name instead, marked
	STILL_FALLBACK, so a caller never waits on one that will never come.

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
local STILL_PATH = { "Assets", "NukeStillTemplates" }
local STILL_SERVER_FOLDER = "NukeStillTemplates" -- ServerStorage, see Services/ModelCacheService
local STILL_SUFFIX = "@still"
--- Set by ModelCacheService on a full model it sent in place of a missing still copy.
local STILL_FALLBACK = "StillFallback"

local ItemModels = {}

ItemModels.SERVER_FOLDER = SERVER_FOLDER
ItemModels.CLIENT_CACHE = CLIENT_CACHE
ItemModels.TEMPLATE_PATH = TEMPLATE_PATH
ItemModels.STILL_PATH = STILL_PATH
ItemModels.STILL_SERVER_FOLDER = STILL_SERVER_FOLDER
ItemModels.STILL_FALLBACK = STILL_FALLBACK

--- The cache name a still copy travels under, and the item id back out of one.
function ItemModels.stillKey(itemId: string): string
	return itemId .. STILL_SUFFIX
end

function ItemModels.fromStillKey(key: string): string?
	if string.sub(key, -#STILL_SUFFIX) == STILL_SUFFIX then
		return string.sub(key, 1, -#STILL_SUFFIX - 1)
	end
	return nil
end

-- Only a running client asks the server for models. Edit mode reports IsClient()
-- true (see Shared/Net), so it is ruled out by IsRunning.
local isPlayClient = RunService:IsClient() and not RunService:IsServer() and RunService:IsRunning()

function ItemModels.has(modelKey: string?): boolean
	return modelKey == IMPORTED_NUKE_KEY
end

--- The folder the templates sit in as this place was saved: Assets in
--- ReplicatedStorage. The server moves it out at boot; Studio's edit tools still see it.
local function replicatedFolder(path: { string }?): Instance?
	local folder: Instance = ReplicatedStorage
	for _, name in path or TEMPLATE_PATH do
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

--- A still copy by its cache name: ServerStorage or the saved Assets folder (server,
--- Studio), else what this client was sent (possibly a STILL_FALLBACK full model).
local function stillTemplate(key: string): Model?
	local itemId = ItemModels.fromStillKey(key)
	if itemId == nil then
		return nil
	end
	local template = nil
	local server = ServerStorage:FindFirstChild(STILL_SERVER_FOLDER)
	if server then
		template = server:FindFirstChild(itemId)
	end
	if template == nil then
		local replicated = replicatedFolder(STILL_PATH)
		template = if replicated then replicated:FindFirstChild(itemId) else nil
	end
	if template == nil and cache then
		template = cache:FindFirstChild(key)
	end
	return if template and template:IsA("Model") then template else nil
end

--- The template behind a cache name: a still key or a plain item id.
local function templateFor(key: string): Model?
	if ItemModels.fromStillKey(key) then
		return stillTemplate(key)
	end
	return importedNukeTemplate(key)
end

--- The template a clone of `key` comes from, if it is here yet. For callers that
--- preload its meshes before showing a clone (StandNukeController).
function ItemModels.template(key: string): Model?
	return templateFor(key)
end

--- True once the model behind `key` (an item id, or a stillKey) can be built here
--- without waiting.
function ItemModels.ready(key: string): boolean
	return templateFor(key) ~= nil
end

--- Ask the server for these models (item ids or stillKeys), ahead of drawing them.
--- Each is asked for once; ids with no model are simply never sent. A no-op anywhere
--- but a running client.
function ItemModels.request(itemIds: { string })
	if not isPlayClient then
		return
	end
	watchCache()
	local wanted = {}
	for _, itemId in itemIds do
		if type(itemId) == "string" and not requested[itemId] and templateFor(itemId) == nil then
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

--- A clone of `itemId`'s still copy, or nil until it is here (asking for it, like
--- `create`). Tagged for its quality only: its finish is already baked in, and a
--- Config/ItemFx entry would aim spins and glows at parts it no longer has. A
--- STILL_FALLBACK (the full model standing in) is tagged like any full clone.
function ItemModels.createStill(itemId: string, modifier: string?): Model?
	local key = ItemModels.stillKey(itemId)
	local template = stillTemplate(key)
	if template == nil then
		ItemModels.request({ key })
		return nil
	end
	local clone = template:Clone()
	if clone:GetAttribute(STILL_FALLBACK) == true then
		ItemFx.tag(clone, itemId, modifier)
	else
		ItemFx.tag(clone, nil, modifier)
	end
	return clone
end

--- Item factories author placement rotations as attributes so a flat object such
--- as the cap can be tilted toward the player without forcing the same tilt onto a
--- future upright object. Unknown contexts and missing attributes mean identity.
function ItemModels.rotation(model: Model, context: string): CFrame
	local value = model:GetAttribute(`{context}Rotation`)
	return if typeof(value) == "CFrame" then value else CFrame.identity
end

return ItemModels
