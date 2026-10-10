--!strict
--[[
	ModelCacheService — the imported nuke templates, sent to each player only as needed.

	The 138 templates (Assets.ImportedNukeTemplates, ~10.5k MeshParts) used to sit in
	ReplicatedStorage, so every player downloaded all of them before they could move.
	This moves the folder into ServerStorage the moment the server boots. Studio's
	import migrations still write to ReplicatedStorage; anything they add is folded in
	here, so a place saved either way works.

	A client fires NukeModels with the item ids it is about to draw (Shared/ItemModels).
	Each id is copied once into that player's PlayerGui.NukeModels, a disabled
	ScreenGui that survives respawns. PlayerGui replicates to its owner only.

	The server's own clones (held items, the wash bay, the lockers) read ServerStorage
	directly through ItemModels.create, and replicate like any Workspace part.

	STILL COPIES (Assets.NukeStillTemplates, Shared/StandNuke) move to ServerStorage
	the same way and go out under ItemModels.stillKey(itemId). A nuke without one gets
	its full model under that name, marked ItemModels.STILL_FALLBACK.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ItemModels = require(ReplicatedStorage.Shared.ItemModels)
local Net = require(ReplicatedStorage.Shared.Net)

local MAX_PER_REQUEST = 200

local ModelCacheService = {}

local sent: { [Player]: { [string]: boolean } } = {}

--- Move (or fold) one replicated template folder into ServerStorage.
local function hideTemplates(path: { string }, serverName: string)
	local folder: Instance = ReplicatedStorage
	for _, name in path do
		local nextFolder = folder:FindFirstChild(name)
		if nextFolder == nil then
			return
		end
		folder = nextFolder
	end

	local target = ServerStorage:FindFirstChild(serverName)
	if target == nil then
		folder.Name = serverName
		folder.Parent = ServerStorage
		return
	end
	-- Both exist: a migration added templates after the place was saved with the
	-- folder in ServerStorage. The replicated copy is newer.
	for _, template in folder:GetChildren() do
		local old = target:FindFirstChild(template.Name)
		if old then
			old:Destroy()
		end
		template.Parent = target
	end
	folder:Destroy()
end

--- Nukes never cast shadows. A full server shows ~140 of them at ~76 parts each, and
--- every shadow caster is drawn a second time into the shadow map. Flipping the
--- templates once covers every clone: server copies and each player's cache.
---
--- Base machines too, the same rule Kit.swap gives the built world: the locker template
--- is covered should it ever be re-cloned onto the six bases. Set on the server, so the
--- replicated templates arrive at every client already shadowless. (The treadmill's
--- templates were here until the treadmill went, 2026-10-09.)
local BASE_TEMPLATES = { "QuarantineLocker" }

local function stripShadows()
	local folders: { Instance } = {}
	for _, name in { ItemModels.SERVER_FOLDER, ItemModels.STILL_SERVER_FOLDER } do
		local templates = ServerStorage:FindFirstChild(name)
		if templates then
			table.insert(folders, templates)
		end
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in BASE_TEMPLATES do
		local templates = assets and assets:FindFirstChild(name)
		if templates then
			table.insert(folders, templates)
		end
	end
	for _, templates in folders do
		for _, part in templates:GetDescendants() do
			if part:IsA("BasePart") then
				part.CastShadow = false
			end
		end
	end
end

-- At require time, not init(): the earlier the folder leaves ReplicatedStorage, the
-- smaller the window in which a joining client could still be sent it. ORDER lists
-- this service first.
hideTemplates(ItemModels.TEMPLATE_PATH, ItemModels.SERVER_FOLDER)
hideTemplates(ItemModels.STILL_PATH, ItemModels.STILL_SERVER_FOLDER)
stripShadows()

local function cacheFor(player: Player): Instance?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local cache = playerGui:FindFirstChild(ItemModels.CLIENT_CACHE)
	if cache == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = ItemModels.CLIENT_CACHE
		gui.Enabled = false
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
		cache = gui
	end
	return cache
end

local function onRequest(player: Player, itemIds: any)
	if type(itemIds) ~= "table" then
		return
	end
	local templates = ServerStorage:FindFirstChild(ItemModels.SERVER_FOLDER)
	local stills = ServerStorage:FindFirstChild(ItemModels.STILL_SERVER_FOLDER)
	local cache = cacheFor(player)
	if templates == nil or cache == nil then
		return
	end
	local given = sent[player]
	if given == nil then
		given = {}
		sent[player] = given
	end
	for index, itemId in itemIds do
		if index > MAX_PER_REQUEST then
			break
		end
		if type(itemId) ~= "string" or given[itemId] then
			continue
		end
		local stillOf = ItemModels.fromStillKey(itemId)
		if stillOf then
			local still = if stills then stills:FindFirstChild(stillOf) else nil
			local fallback = false
			if still == nil or not still:IsA("Model") then
				still = templates:FindFirstChild(stillOf)
				fallback = true
			end
			if still and still:IsA("Model") then
				given[itemId] = true
				local copy = still:Clone()
				copy.Name = itemId
				if fallback then
					copy:SetAttribute(ItemModels.STILL_FALLBACK, true)
				end
				copy.Parent = cache
			end
			continue
		end
		local template = templates:FindFirstChild(itemId)
		if template and template:IsA("Model") then
			given[itemId] = true
			template:Clone().Parent = cache
		end
	end
end

function ModelCacheService.start()
	Players.PlayerAdded:Connect(function(player)
		player:WaitForChild("PlayerGui", 30)
		cacheFor(player)
	end)
	for _, player in Players:GetPlayers() do
		cacheFor(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
	end)
	Net.get("NukeModels").OnServerEvent:Connect(onRequest)
end

return ModelCacheService
