--[[
	DebugHudController.lua — the numbers, on screen, all of them.

	BUILD-ORDER Phase 0: "Build the debug HUD before any real UI. You are about to
	spend weeks tuning invisible rates. Being able to see them is worth more than any
	art." So this is deliberately ugly and deliberately complete — monospaced, dense,
	no animation, every number the design argues about visible at once.

	It renders whatever DebugService sends and computes nothing itself. When the real
	HudController lands in Phase 2 this can stay exactly as it is, as the thing you
	turn on when a number looks wrong.

	F3 toggles it.

	One colour rule, borrowed from PLAN §14 and worth honouring even here: exposure is
	GREEN, suit failure is WHITE. They are different categories of dying, so they never
	share a colour.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)

local DebugHud = {}

local COLOR = {
	panel = Color3.fromHex("0C0F0A"),
	stroke = Color3.fromHex("2A3324"),
	text = Color3.fromHex("C8D0BE"),
	dim = Color3.fromHex("6E7A66"),
	track = Color3.fromHex("1E241A"),
	green = Color3.fromHex("8FE04A"), -- exposure
	white = Color3.fromHex("FFFFFF"), -- burn, and nothing else
	amber = Color3.fromHex("F59E0B"),
	red = Color3.fromHex("EF4444"),
}

local MAX_ITEM_ROWS = 12

-- ── formatting ──────────────────────────────────────────────────────────

-- DebugService sends -1 for "never" rather than inf, which does not survive the
-- trip legibly.
local function clock(seconds: number): string
	if seconds < 0 then
		return "never"
	end
	if seconds >= 3600 then
		return "1h+"
	end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

local function rate(n: number): string
	return string.format("%.2f", n)
end

local function pct(fraction: number): string
	return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

-- ── widgets ─────────────────────────────────────────────────────────────

local function label(parent: Instance, order: number, size: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.LayoutOrder = order
	t.Size = UDim2.new(1, 0, 0, size or 16)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Code
	t.TextSize = 14
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = COLOR.text
	t.Text = ""
	t.Parent = parent
	return t
end

--- A labelled bar: "EXPOSURE  [=====     ]  38%". Returns setters.
local function bar(parent: Instance, order: number, name: string)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 16)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(0, 78, 1, 0)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Code
	caption.TextSize = 14
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = COLOR.dim
	caption.Text = name
	caption.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 80, 0.5, -4)
	track.Size = UDim2.new(1, -172, 0, 8)
	track.BackgroundColor3 = COLOR.track
	track.BorderSizePixel = 0
	track.Parent = row

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = COLOR.green
	fill.BorderSizePixel = 0
	fill.Parent = track

	local readout = Instance.new("TextLabel")
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.new(1, 0, 0, 0)
	readout.Size = UDim2.new(0, 88, 1, 0)
	readout.BackgroundTransparency = 1
	readout.Font = Enum.Font.Code
	readout.TextSize = 14
	readout.TextXAlignment = Enum.TextXAlignment.Right
	readout.TextColor3 = COLOR.text
	readout.Text = ""
	readout.Parent = row

	return {
		set = function(fraction: number, text: string, color: Color3)
			fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
			fill.BackgroundColor3 = color
			readout.Text = text
			readout.TextColor3 = color
		end,
	}
end

local function divider(parent: Instance, order: number)
	local line = Instance.new("Frame")
	line.LayoutOrder = order
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = COLOR.stroke
	line.BorderSizePixel = 0
	line.Parent = parent
end

-- ── build ───────────────────────────────────────────────────────────────

local ui = {}

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RadDebugHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 500
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 12) -- top-right; chat owns top-left
	-- Wide enough for the longest line, which is a carry row: rarity + modifier,
	-- condition, countdown, emission and value retained. 400 clipped the gear readout.
	panel.Size = UDim2.new(0, 560, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = COLOR.panel
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR.stroke
	stroke.Thickness = 1
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel

	ui.title = label(panel, 1)
	ui.title.TextColor3 = COLOR.dim
	ui.title.Text = "RAD DEBUG  —  F3 hides  —  /radhelp"

	divider(panel, 2)

	ui.stage = label(panel, 3)
	ui.exposure = bar(panel, 4, "EXPOSURE")
	ui.netBreakdown = label(panel, 5)
	ui.netBreakdown.TextColor3 = COLOR.dim
	ui.health = bar(panel, 6, "HEALTH")
	ui.greed = bar(panel, 7, "GREED")
	ui.survivable = label(panel, 8, 18)
	ui.suit = label(panel, 9)
	ui.suit.TextColor3 = COLOR.dim

	divider(panel, 10)

	ui.carryHeader = label(panel, 11)
	ui.carryHeader.TextColor3 = COLOR.dim

	ui.itemRows = {}
	for i = 1, MAX_ITEM_ROWS do
		local row = label(panel, 11 + i)
		row.Visible = false
		table.insert(ui.itemRows, row)
	end

	ui.overflow = label(panel, 12 + MAX_ITEM_ROWS)
	ui.overflow.TextColor3 = COLOR.dim
	ui.overflow.Visible = false

	return gui
end

-- ── render ──────────────────────────────────────────────────────────────

local function render(state)
	local pocket = if (state.hotPocket or 1) > 1 then string.format("  HOT POCKET x%.1f", state.hotPocket) else ""

	-- A nil stage is a real state, not a missing value: it means "not standing in
	-- any stage", which is exactly what base camp is. Only the wasteland has a number.
	local where = if state.stageId
		then string.format("STAGE %d  %s", state.stageId, state.stageName)
		else tostring(state.stageName)
	ui.stage.Text = string.format("%-26s %s r/s ambient%s", where, rate(state.ambient), pocket)
	ui.stage.TextColor3 = if state.failing then COLOR.white else COLOR.text

	ui.exposure.set(
		state.exposureFrac,
		string.format("%s  %s r/s", pct(state.exposureFrac), rate(state.net)),
		COLOR.green
	)

	-- Split the incoming rate into world vs bag. This one line is the greed dial
	-- made legible, and it is the number PLAN §3.3 lives or dies on.
	local fromBag = state.net * state.greed
	ui.netBreakdown.Text = string.format("          world %s  +  bag %s", rate(state.net - fromBag), rate(fromBag))

	local healthFrac = state.health / state.maxHealth
	ui.health.set(
		healthFrac,
		string.format("%d%s", math.floor(state.health), if state.healthBurn > 0 then string.format("  -%s/s", rate(state.healthBurn)) else ""),
		if state.failing then COLOR.white else COLOR.dim
	)

	ui.greed.set(state.greed, pct(state.greed), COLOR.amber)

	if state.inShower then
		ui.survivable.Text = "DECON SHOWER - flushing"
		ui.survivable.TextColor3 = COLOR.green
	elseif state.downed then
		ui.survivable.Text = "DOWNED  —  /flush to reset"
		ui.survivable.TextColor3 = COLOR.red
	elseif state.survivable < 0 then
		ui.survivable.Text = "SURVIVABLE  indefinite"
		ui.survivable.TextColor3 = COLOR.dim
	else
		-- White means the suit is failing. It is the only white in the game.
		local burning = state.threat == "burn"
		ui.survivable.Text = string.format(
			"%s  %s (%s)",
			if burning then "SUIT FAILING — SURVIVABLE" else "SURVIVABLE",
			clock(state.survivable),
			tostring(state.threat)
		)
		ui.survivable.TextColor3 = if burning then COLOR.white else COLOR.green
	end

	ui.suit.Text = string.format(
		"suit tol %s r/s   excess %s   gear D%d/Mg%d/C%d/Su%d/B%d/Sa%d",
		rate(state.suitTolerance),
		rate(state.excess),
		state.gear.detector,
		state.gear.magnet,
		state.gear.cleaner,
		state.gear.suit,
		state.gear.boots,
		state.gear.satchel
	)

	-- Per-item r/s is the item's RAW output; the `bag` figure above is what actually
	-- reaches you, after satchel shielding and level resist. They will not add up, and
	-- that is correct — but unlabelled it reads as a bug during tuning.
	ui.carryHeader.Text = string.format("CARRY %d/%d      item r/s is raw, pre-satchel", #state.items, state.capacity)

	for i, row in ui.itemRows do
		local item = state.items[i]
		if item == nil then
			row.Visible = false
			continue
		end

		row.Visible = true
		local rarityDef = Rarity.DEFS[item.rarity]
		row.TextColor3 = if rarityDef then rarityDef.color else COLOR.text

		local mod = if item.modifier == "None" then "" else " " .. item.modifier
		local next_ = if item.frozen then "docked" else clock(item.toNext)

		row.Text = string.format(
			" %-22s %-8s %6s  %s r/s  %s",
			item.rarity .. mod,
			string.upper(item.condition),
			next_,
			rate(item.emission),
			pct(item.valueRetained)
		)
	end

	local hidden = #state.items - MAX_ITEM_ROWS
	ui.overflow.Visible = hidden > 0
	if hidden > 0 then
		ui.overflow.Text = string.format(" …and %d more", hidden)
	end
end

-- ── lifecycle ─────────────────────────────────────────────────────────────

function DebugHud.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("DebugState").OnClientEvent:Connect(function(state)
		local ok, err = pcall(render, state)
		if not ok then
			warn(`[hud] render failed: {err}`)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F3 then
			gui.Enabled = not gui.Enabled
		end
	end)
end

return DebugHud
