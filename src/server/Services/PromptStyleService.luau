--!strict
--[[
	PromptStyleService.luau — every world ProximityPrompt leaves the server already
	`Style = Custom`, so Roblox's own grey prompt can never draw.

	WHY HERE AND NOT ONLY ON THE CLIENT: PromptController used to flip Default prompts
	to Custom locally, once the client's controllers had loaded. On a live server that
	is seconds after the world has streamed in, and Roblox's built-in prompt UI had
	often already shown the treadmill/wash prompt by then. Flipping Style afterwards
	does not take that native billboard down, so the player saw TWO prompts -- the
	glass card and the grey one behind it. Studio loads fast enough that it rarely
	happened there.

	Doing it on the server means the prompt replicates as Custom from its very first
	frame on every client; there is no window where it is Default. Each one is tagged
	GLASS_CARD so PromptController knows the face is its to draw (a prompt that is
	Custom for its own reasons, like the dig pick-up keycap, carries no tag and is left
	alone).
]]

local Workspace = game:GetService("Workspace")

local PromptStyleService = {}

--- Attribute PromptController keys off. Keep in sync with PromptController.GLASS_CARD.
local GLASS_CARD = "GlassCard"

local function adopt(inst: Instance)
	if not inst:IsA("ProximityPrompt") then
		return
	end
	if inst.Style ~= Enum.ProximityPromptStyle.Default and inst:GetAttribute(GLASS_CARD) ~= true then
		return
	end
	inst:SetAttribute(GLASS_CARD, true)
	inst.Style = Enum.ProximityPromptStyle.Custom
end

function PromptStyleService.init()
	-- In init, not start: the place file's prompts are flipped before any other
	-- service runs and before a client can have replicated them.
	for _, d in Workspace:GetDescendants() do
		adopt(d)
	end
	Workspace.DescendantAdded:Connect(adopt)
end

return PromptStyleService
