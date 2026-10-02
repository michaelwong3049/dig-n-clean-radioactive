--!strict
--[[
	BagRecover.luau — the purple RECOVER BAG button (Tuning.BAG_RECOVER_PRODUCT_ID),
	shared by the death screen and the bag tracker pill.

	Pressing it does NOT open the purchase prompt here: it tells the server which bag
	(Net.RecoverBag), and the server holds that bag against thieves first and then
	opens the prompt itself (ExposureService, "RECOVER BAG"). Which bag is your newest
	one is BagTrackerController's to know; it calls setNewest whenever that changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)

local RobuxButton = require(script.Parent.RobuxButton)

local BagRecover = {}

local newestId: string? = nil
local listeners: { (id: string?) -> () } = {}

--- Your newest dropped bag's id, or nil when you have none lying out.
function BagRecover.setNewest(id: string?)
	if id == newestId then
		return
	end
	newestId = id
	for _, listener in listeners do
		task.spawn(listener, id)
	end
end

function BagRecover.newest(): string?
	return newestId
end

--- Run `listener(id)` whenever the newest bag changes.
function BagRecover.onChanged(listener: (id: string?) -> ())
	table.insert(listeners, listener)
end

--- A Recover button under `parent`; size and position are the caller's.
function BagRecover.button(parent: Instance, caption: string?): RobuxButton.Button
	return RobuxButton.product(parent, function()
		return if newestId then Tuning.BAG_RECOVER_PRODUCT_ID else 0
	end, caption, function()
		if newestId then
			Net.get("RecoverBag"):FireServer(newestId)
		end
	end)
end

return BagRecover
