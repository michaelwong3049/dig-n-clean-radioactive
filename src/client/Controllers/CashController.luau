--[[
	CashController.lua — the persistent cash badge. Bottom-left, stacked directly
	above the health/rads meter, always on screen.

	THERE WAS NO PERSISTENT CASH READOUT BEFORE THIS. data.cash only ever reached the
	client inside StationState's payload, which fires only while standing at a
	station -- walking around digging, a player had no live view of their own wallet.
	CashState (Shared/Net.luau) exists to fix exactly that: one snapshot on load
	(EconomyService.start()'s DataService.onLoaded hook) plus a fire on every real
	change (sell/spend/award, and DebugService's /cash), never per-tick.

	POSITION IS A FORMULA OVER Dock, NOT A FRESH NUMBER (UIKit.luau's own rule) --
	same left margin as the meter, same width, sitting directly above it with one
	Dock.GAP between them, so the two read as one stacked instrument cluster in the
	corner rather than two unrelated floating panels.

	SIZE AND BOTTOM ARE Dock.CASH_SIZE / Dock.CASH_BOTTOM NOW, NOT LOCALS HERE. They
	moved into the shared table the moment IndexController needed to stack the INDEX
	button on top of this badge — a second file computing its offset from this file's
	private numbers would be exactly the cross-file magic-number coupling Dock exists
	to prevent. This file still OWNS the values in the sense that nothing else builds
	the badge, but the numbers themselves now live in Dock so a resize here is not a
	silent breakage there.

	COLOUR IS AMBER, NOT GREEN, ON PURPOSE. The reference image this was built from
	used green for the dollar text, but HudController's ONE COLOUR RULE (PLAN §14)
	reserves green for exposure and nothing else, ever -- reusing it here would be
	exactly the kind of quiet rule violation that comment warns against. Amber is
	already this palette's "valuable/warm" accent (mid-health, Legendary rarity).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Cash = {}

-- Dock.CASH_SIZE / Dock.CASH_BOTTOM, not local numbers — see the header.
local BADGE_SIZE = Dock.CASH_SIZE
local BADGE_BOTTOM = Dock.CASH_BOTTOM

local ui = {}

--- $340 under a thousand, $5.2K into the thousands, $1.4M into the millions, $2.1B into
--- the billions -- the reference image's own "$5K" convention, and compact enough to
--- still read at a glance at the values this economy actually reaches (post-rescale an
--- Anomaly sells up to ~$13M, and a built-out exhibit's banked $/hr runs into billions).
local function formatCash(amount: number): string
	if amount >= 1_000_000_000 then
		return string.format("$%.1fB", amount / 1_000_000_000)
	elseif amount >= 1_000_000 then
		return string.format("$%.1fM", amount / 1_000_000)
	elseif amount >= 1_000 then
		return string.format("$%.1fK", amount / 1_000)
	end
	return string.format("$%d", amount)
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "CashHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local badge = UIKit.panel(gui, {
		name = "CashBadge",
		size = BADGE_SIZE,
		position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 1, -BADGE_BOTTOM),
		anchorPoint = Vector2.new(0, 1),
		color = UIKit.C.panel,
		transparency = 0.1,
		cornerRadius = UIKit.Radius.card,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 3,
	})

	ui.value = UIKit.label(badge, {
		name = "Value",
		size = UDim2.new(1, -20, 1, 0),
		position = UDim2.fromOffset(10, 0),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.title,
		color = UIKit.C.amber,
		xAlign = Enum.TextXAlignment.Center,
		strokeTransparency = 0,
		text = "$0",
		zIndex = 4,
	})

	return gui
end

function Cash.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("CashState").OnClientEvent:Connect(function(amount: number)
		ui.value.Text = formatCash(amount or 0)
	end)
end

return Cash
