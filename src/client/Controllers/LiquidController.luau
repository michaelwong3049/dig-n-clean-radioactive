--[[
	LiquidController.lua — one badge, bottom-left: what is in the hose, and how much
	of it is left.

	THIS FILE USED TO BE TWICE THIS SIZE AND THE DELETION IS THE FEATURE. It also drew
	a roll reveal: a centred card that spun through liquid names for ~0.9s and landed
	on the result. It looked good and it was the wrong place for it. Stepping on a big
	lit button in the world and having a card appear over your screen is a menu wearing
	a button's clothes — and the pad is a physical object that can simply answer for
	itself. It does now: LiquidService flashes the plate in the rolled liquid's colour
	and names it on the pad's own billboard, which every player standing on that base
	can see rather than only the one who stepped on it.

	WHAT SURVIVED, AND WHY IT IS NOT A CONTRADICTION. The user's rule was "no UI that
	pops up when you press the button". This badge never pops up — it is always on
	screen, in the bottom-left instrument column with the meter, the cash and the index
	button, and it only ever changes what it says. "What am I holding right now" is a
	question the player asks away from the pad, standing at the tub, which is exactly
	when no world object is in front of them to answer it.

	COLOUR COMES FROM THE LIQUID, NOT FROM THE PALETTE, and this is the one place in
	the client allowed to do that. Config/Liquids owns a hex per liquid so the canister
	on the pad's shelf, the stream out of the hose and this badge are provably the same
	colour; picking a UIKit.C entry here would put the badge permanently out of step
	with the world geometry. The one rule it still obeys: no liquid may be the ooze
	green, because that green is the field and nothing else (PLAN §14) — enforced in
	Config/Liquids' own palette, not here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Liquids = require(Shared.Config.Liquids)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Liquid = {}

local ui = {}

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "LiquidHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above the cash badge (80) and the index button (90), below HudController's
	-- vignette and blackout curtain (100) — a blackout has to cover this.
	gui.DisplayOrder = 95
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local badge, badgeStroke = UIKit.panel(gui, {
		name = "LiquidBadge",
		size = Dock.LIQUID_SIZE,
		position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 1, -Dock.LIQUID_BOTTOM),
		anchorPoint = Vector2.new(0, 1),
		color = UIKit.C.panel,
		transparency = 0.1,
		cornerRadius = UIKit.Radius.card,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 3,
	})
	ui.badge = badge
	ui.badgeStroke = badgeStroke

	-- A solid chip of the liquid's own colour, so the badge is identifiable without
	-- being read — the same "navigate by colour, not by sign" trick the shop stalls
	-- use (build/Shops.luau).
	ui.chip = UIKit.panel(badge, {
		name = "Chip",
		size = UDim2.fromOffset(14, 14),
		position = UDim2.new(0, 12, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
		color = UIKit.C.text,
		transparency = 0,
		cornerRadius = UIKit.Radius.pill,
		strokeThickness = UIKit.Stroke.thin,
		zIndex = 4,
	})

	ui.badgeName = UIKit.label(badge, {
		name = "NameLabel",
		size = UDim2.new(1, -100, 1, 0),
		position = UDim2.fromOffset(34, 0),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.text,
		strokeTransparency = 0,
		text = "Plain Water",
		zIndex = 4,
	})

	ui.badgeCharges = UIKit.label(badge, {
		name = "Charges",
		size = UDim2.new(0, 60, 1, 0),
		position = UDim2.new(1, -72, 0, 0),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Right,
		strokeTransparency = 0,
		text = "\u{221E}",
		zIndex = 4,
	})

	return gui
end

local function paint(view)
	local def = Liquids.get(view.equipped)
	local colour = Color3.fromHex(def.color)

	ui.chip.BackgroundColor3 = colour
	ui.badgeName.Text = def.name
	ui.badgeStroke.Color = colour

	-- The infinity sign is the whole point of Plain Water, so it gets the symbol
	-- rather than a number. A badge reading "0 left" over the one liquid that can
	-- never run out would teach exactly the wrong thing.
	if view.equipped == Liquids.WATER then
		ui.badgeCharges.Text = "\u{221E}"
		ui.badgeCharges.TextColor3 = UIKit.C.dim
	else
		local left = view.liquidCharges or 0
		ui.badgeCharges.Text = `{left} left`
		ui.badgeCharges.TextColor3 = if left <= 3 then UIKit.C.amber else UIKit.C.dim
	end
end

function Liquid.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("LiquidState").OnClientEvent:Connect(function(view)
		if type(view) ~= "table" then
			return
		end
		-- The badge wants the charge count of the LOADED liquid specifically, which
		-- the payload carries per-entry across the whole shelf. Flattened here rather
		-- than added to the payload, because LiquidService.viewFor is also what the
		-- debug console reads and it wants the whole shelf.
		local charges = 0
		for _, entry in view.liquids or {} do
			if entry.id == view.equipped then
				charges = entry.held
				break
			end
		end
		view.liquidCharges = charges
		paint(view)
	end)
end

return Liquid
