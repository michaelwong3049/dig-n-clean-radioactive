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

	The server's own clones (held items, stands, the wash bay) read ServerStorage
	directly through ItemModels.create, and replicate like any Workspace part.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ItemModels = require(ReplicatedStorage.Shared.ItemModels)
local Net = require(ReplicatedStorage.Shared.Net)

local MAX_PER_REQUEST = 200

local ModelCacheService = {}

local sent: { [Player]: { [string]: boolean } } = {}

--- Move (or fold) the replicated templates into ServerStorage.
local function hideTemplates()
	local folder: Instance = ReplicatedStorage
	for _, name in ItemModels.TEMPLATE_PATH do
		local nextFolder = folder:FindFirstChild(name)
		if nextFolder == nil then
			return
		end
		folder = nextFolder
	end

	local target = ServerStorage:FindFirstChild(ItemModels.SERVER_FOLDER)
	if target == nil then
		folder.Name = ItemModels.SERVER_FOLDER
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
local function stripShadows()
	local templates = ServerStorage:FindFirstChild(ItemModels.SERVER_FOLDER)
	if templates == nil then
		return
	end
	for _, part in templates:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = false
		end
	end
end

-- At require time, not init(): the earlier the folder leaves ReplicatedStorage, the
-- smaller the window in which a joining client could still be sent it. ORDER lists
-- this service first.
hideTemplates()
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
