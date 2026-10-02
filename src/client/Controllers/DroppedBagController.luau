--!strict
--[[
	DroppedBagController.luau — the card over every dropped bag in the world, drawn
	here rather than by the server so each viewer gets their own.

	Any death drops the whole bag for anyone to steal (ExposureService.dropBag). The
	server's sack carries no label, only attributes (OwnerId, OwnerName, Items,
	ExpiresAt) and the "DroppedBag" tag. From those:
	  - SOMEBODY ELSE'S BAG: a BagCard ("Sam's bag", items, countdown) seen only
	    within LABEL_REACH studs. It used to be an AlwaysOnTop server billboard with no
	    distance limit, so every bag on the map was visible from everywhere.
	  - YOUR OWN BAG: no card here. BagTrackerController already draws yours over its
	    light column from any distance, and two cards on one bag would just stack.
	The prompt's action is worded per viewer too: "Recover bag" for you, "Steal bag"
	for anyone else. ProximityPrompt text set on a client stays on that client.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UIKit = require(script.Parent.Parent.UIKit)
local BagCard = require(script.Parent.Parent.BagCard)

local DroppedBagController = {}

local TAG = "DroppedBag"
local LABEL_REACH = 40 -- studs: close enough that you have to go looking for it
local LOW_SECONDS = 20 -- the countdown goes red under this (BagTrackerController's)
local REFRESH = 0.25 -- seconds between countdown redraws

type Entry = {
	bag: BasePart,
	gui: BillboardGui?,
	card: BagCard.Card?,
	connections: { RBXScriptConnection },
}

local entries: { [Instance]: Entry } = {}

local function isMine(bag: Instance): boolean
	return bag:GetAttribute("OwnerId") == Players.LocalPlayer.UserId
end

local function wordPrompt(bag: Instance, prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.ActionText = if isMine(bag) then "Recover bag" else "Steal bag"
	end
end

local function redraw(entry: Entry)
	local card = entry.card
	if card == nil then
		return
	end
	local items = entry.bag:GetAttribute("Items")
	local expiresAt = entry.bag:GetAttribute("ExpiresAt")
	local left = if typeof(expiresAt) == "number" then expiresAt - Workspace:GetServerTimeNow() else 0
	card.detail.Text = BagCard.detailText(if typeof(items) == "number" then items else 0, left, LOW_SECONDS)
end

local function addCard(entry: Entry)
	local bag = entry.bag
	local gui = Instance.new("BillboardGui")
	gui.Name = "DroppedBagCard"
	gui.Adornee = bag
	gui.AlwaysOnTop = true
	gui.MaxDistance = LABEL_REACH
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.StudsOffsetWorldSpace = Vector3.new(0, bag.Size.Y / 2 + 1.8, 0)
	-- Under PlayerGui with an Adornee rather than inside the part, so the wash bay's
	-- hideHud (which stows every LayerCollector under PlayerGui) takes it too.
	gui.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")

	local canvas = UIKit.billboardCanvas(gui, BagCard.SIZE)
	local card = BagCard.build(canvas, BagCard.GREEN)
	local owner = bag:GetAttribute("OwnerName")
	card.title.Text = `{if typeof(owner) == "string" then owner else "Someone"}'s bag`

	entry.gui = gui
	entry.card = card
	redraw(entry)
end

local function remove(bag: Instance)
	local entry = entries[bag]
	if entry == nil then
		return
	end
	entries[bag] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	if entry.gui then
		entry.gui:Destroy()
	end
end

local function add(bag: Instance)
	if entries[bag] or not bag:IsA("BasePart") then
		return
	end
	local entry: Entry = { bag = bag, connections = {} }
	entries[bag] = entry

	-- The prompt can stream in after the tag does.
	for _, child in bag:GetChildren() do
		wordPrompt(bag, child)
	end
	table.insert(entry.connections, bag.ChildAdded:Connect(function(child)
		wordPrompt(bag, child)
	end))
	table.insert(entry.connections, bag:GetAttributeChangedSignal("Items"):Connect(function()
		redraw(entry)
	end))
	table.insert(entry.connections, bag.Destroying:Connect(function()
		remove(bag)
	end))

	if not isMine(bag) then
		addCard(entry)
	end
end

function DroppedBagController.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
	for _, bag in CollectionService:GetTagged(TAG) do
		add(bag)
	end

	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < REFRESH then
			return
		end
		since = 0
		for _, entry in entries do
			redraw(entry)
		end
	end)
end

return DroppedBagController
