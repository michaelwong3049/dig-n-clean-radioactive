--!strict
--[[
	WashRarityBanner.luau — the rarity of the thing on the tub, across the top of the
	wash view.

	The HUD is put away for the whole session (WashController.hideHud), so the top of
	the screen is empty, and the one thing the player already knows about a crusted
	find -- its rarity, read by the detector at the dig and tinted into the crust --
	was nowhere in the shot. It is NOT a spoiler: the name stays `???` until the last
	chunk comes off, and the WashState payload has always carried `rarity` for exactly
	this reason (the name is the thing it deliberately leaves out).

	In the rarity's own colour, Gotham Black, outlined like every other HUD word. An
	Anomaly cycles the spectrum the way its reveal pill does (`tick`). Stands down for
	the reveal, which prints the rarity itself in the lower third.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local UIKit = require(script.Parent.UIKit)

local WashRarityBanner = {}

--- Design px from the top of the (inset-ignoring) canvas. Up in the topbar strip:
--- its buttons sit in the corners, so the centre is free.
local TOP = 12
local TEXT_SIZE = 46
local OUTLINE = 4

local label: TextLabel? = nil
local rarity: string? = nil
local wanted = false

function WashRarityBanner.mount(canvas: Frame)
	label = UIKit.hudNumber(canvas, {
		name = "Rarity",
		size = UDim2.fromOffset(600, TEXT_SIZE + 8),
		position = UDim2.new(0.5, 0, 0, TOP),
		anchorPoint = Vector2.new(0.5, 0),
		font = UIKit.Font.hero,
		textSize = TEXT_SIZE,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 3,
		visible = false,
	}, OUTLINE, Vector2.new(0, 4))
end

local function refresh()
	if label == nil then
		return
	end
	local def = if rarity then Rarity.DEFS[rarity] else nil
	label.Visible = wanted and def ~= nil
	if def then
		label.Text = string.upper(rarity :: string)
		label.TextColor3 = def.color
	end
end

--- Fed every WashState push; a crate or an item with no rarity hides it.
function WashRarityBanner.set(name: string?)
	rarity = name
	refresh()
end

function WashRarityBanner.show(on: boolean)
	wanted = on
	refresh()
end

--- Per frame from WashController's render step: only an Anomaly moves.
function WashRarityBanner.tick()
	if label and label.Visible and rarity == "Anomaly" then
		label.TextColor3 = Rarity.anomalyHue(os.clock() / Rarity.ANOMALY_CYCLE)
	end
end

return WashRarityBanner
