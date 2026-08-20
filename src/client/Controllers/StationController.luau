--[[
	StationController.lua — the base camp panel.

	Appears when you are standing at the decon station or the trader, and lists what is
	in your bag. Select a row, then act on it. Placeholder art, real information: the
	point of Phase 1 is finding out whether the verbs feel good, and the verbs here are
	SCRUB, SELL and RACK.

	The panel deliberately shows the SAME list at both stations but offers different
	verbs, because that is the design's actual shape — the decon station is where the
	clock stops and dirt comes off, the trader is only a till.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)

local Station = {}

local COLOR = {
	panel = Color3.fromHex("0C0F0A"),
	stroke = Color3.fromHex("2A3324"),
	selected = Color3.fromHex("3E5A2E"),
	text = Color3.fromHex("E4E9DE"),
	dim = Color3.fromHex("7C8874"),
	green = Color3.fromHex("8FE04A"),
	amber = Color3.fromHex("F59E0B"),
	red = Color3.fromHex("EF4444"),
	blue = Color3.fromHex("6FA8C7"),
}

local ROWS = 9
local LOCKER_ROWS = 3

local ui = {}
local state = { station = nil, items = {}, locker = {} }
local selected: string? = nil
local actionRemote: any = nil
local toastToken = 0

local function rarityColor(name: string): Color3
	local def = Rarity.DEFS[name]
	return if def then def.color else COLOR.text
end

-- ── Build ───────────────────────────────────────────────────────────

local function makeRow(parent: Instance, order: number): TextButton
	local row = Instance.new("TextButton")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3 = COLOR.panel
	row.BackgroundTransparency = 1
	row.AutoButtonColor = false
	row.Font = Enum.Font.Code
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = COLOR.text
	row.Text = ""
	row.Visible = false
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = row

	-- scrub progress, drawn behind the label
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLOR.blue
	fill.BackgroundTransparency = 0.6
	fill.BorderSizePixel = 0
	fill.ZIndex = 0
	fill.Parent = row

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.Parent = row

	return row
end

local function makeButton(parent: Instance, order: number, text: string, colour: Color3): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.new(0.32, 0, 0, 38)
	button.BackgroundColor3 = COLOR.panel
	button.BackgroundTransparency = 0.1
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = colour
	button.Text = text
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR.stroke
	stroke.Thickness = 2
	stroke.Parent = button
	button:SetAttribute("HasStroke", true)

	return button
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "StationHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 16, 0.5, 0)
	panel.Size = UDim2.fromOffset(470, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = COLOR.panel
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	ui.panel = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	-- ── Shop mode ────────────────────────────────────────────────────
	-- A shop IS a station, so it reuses this panel and the StationState /
	-- StationAction / StationResult triad rather than inventing a parallel one.
	-- The panel already "shows the same list at both stations but offers different
	-- verbs"; the shop is a third verb set on the same surface.
	local shop = Instance.new("Frame")
	shop.Name = "Shop"
	shop.LayoutOrder = 25
	shop.Size = UDim2.fromScale(1, 0)
	shop.AutomaticSize = Enum.AutomaticSize.Y
	shop.BackgroundTransparency = 1
	shop.Visible = false
	shop.Parent = panel
	ui.shop = shop

	local shopLayout = Instance.new("UIListLayout")
	shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
	shopLayout.Padding = UDim.new(0, 6)
	shopLayout.Parent = shop

	ui.shopUpgrade = Instance.new("TextLabel")
	ui.shopUpgrade.LayoutOrder = 1
	ui.shopUpgrade.Size = UDim2.new(1, 0, 0, 24)
	ui.shopUpgrade.BackgroundTransparency = 1
	ui.shopUpgrade.Font = Enum.Font.GothamBold
	ui.shopUpgrade.TextSize = 16
	ui.shopUpgrade.TextXAlignment = Enum.TextXAlignment.Left
	ui.shopUpgrade.TextColor3 = COLOR.amber
	ui.shopUpgrade.Text = ""
	ui.shopUpgrade.Parent = shop

	ui.shopDeltas = Instance.new("TextLabel")
	ui.shopDeltas.LayoutOrder = 2
	ui.shopDeltas.Size = UDim2.fromScale(1, 0)
	ui.shopDeltas.AutomaticSize = Enum.AutomaticSize.Y
	ui.shopDeltas.BackgroundTransparency = 1
	ui.shopDeltas.Font = Enum.Font.Code
	ui.shopDeltas.TextSize = 13
	ui.shopDeltas.TextXAlignment = Enum.TextXAlignment.Left
	ui.shopDeltas.TextYAlignment = Enum.TextYAlignment.Top
	ui.shopDeltas.TextColor3 = COLOR.green
	ui.shopDeltas.Text = ""
	ui.shopDeltas.Parent = shop

	ui.buyButton = Instance.new("TextButton")
	ui.buyButton.Name = "Buy"
	ui.buyButton.LayoutOrder = 3
	ui.buyButton.Size = UDim2.new(1, 0, 0, 38)
	ui.buyButton.BackgroundColor3 = COLOR.panel
	ui.buyButton.BackgroundTransparency = 0.25
	ui.buyButton.BorderSizePixel = 0
	ui.buyButton.AutoButtonColor = true
	ui.buyButton.Font = Enum.Font.GothamBold
	ui.buyButton.TextSize = 15
	ui.buyButton.TextColor3 = COLOR.amber
	ui.buyButton.Text = "BUY"
	ui.buyButton.Parent = shop

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = ui.buyButton

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR.stroke
	stroke.Thickness = 2
	stroke.Parent = panel
	ui.panelStroke = stroke

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = panel

	ui.title = Instance.new("TextLabel")
	ui.title.LayoutOrder = 1
	ui.title.Size = UDim2.new(1, 0, 0, 24)
	ui.title.BackgroundTransparency = 1
	ui.title.Font = Enum.Font.GothamBold
	ui.title.TextSize = 19
	ui.title.TextXAlignment = Enum.TextXAlignment.Left
	ui.title.TextColor3 = COLOR.text
	ui.title.Text = ""
	ui.title.Parent = panel

	ui.subtitle = Instance.new("TextLabel")
	ui.subtitle.LayoutOrder = 2
	ui.subtitle.Size = UDim2.new(1, 0, 0, 18)
	ui.subtitle.BackgroundTransparency = 1
	ui.subtitle.Font = Enum.Font.Code
	ui.subtitle.TextSize = 13
	ui.subtitle.TextXAlignment = Enum.TextXAlignment.Left
	ui.subtitle.TextColor3 = COLOR.dim
	ui.subtitle.Text = ""
	ui.subtitle.Parent = panel

	ui.rows = {}
	for index = 1, ROWS do
		table.insert(ui.rows, makeRow(panel, 10 + index))
	end

	ui.lockerTitle = Instance.new("TextLabel")
	ui.lockerTitle.LayoutOrder = 40
	ui.lockerTitle.Size = UDim2.new(1, 0, 0, 20)
	ui.lockerTitle.BackgroundTransparency = 1
	ui.lockerTitle.Font = Enum.Font.GothamBold
	ui.lockerTitle.TextSize = 13
	ui.lockerTitle.TextXAlignment = Enum.TextXAlignment.Left
	ui.lockerTitle.TextColor3 = COLOR.red
	ui.lockerTitle.Text = ""
	ui.lockerTitle.Visible = false
	ui.lockerTitle.Parent = panel

	ui.lockerRows = {}
	for index = 1, LOCKER_ROWS do
		table.insert(ui.lockerRows, makeRow(panel, 40 + index))
	end

	local actions = Instance.new("Frame")
	actions.LayoutOrder = 60
	actions.Size = UDim2.new(1, 0, 0, 44)
	actions.BackgroundTransparency = 1
	actions.Parent = panel

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.Parent = actions

	ui.scrubButton = makeButton(actions, 1, "HOLD TO SCRUB", COLOR.blue)
	ui.sellButton = makeButton(actions, 2, "SELL", COLOR.amber)
	ui.rackButton = makeButton(actions, 3, "RACK", COLOR.dim)

	ui.toast = Instance.new("TextLabel")
	ui.toast.LayoutOrder = 70
	ui.toast.Size = UDim2.new(1, 0, 0, 20)
	ui.toast.BackgroundTransparency = 1
	ui.toast.Font = Enum.Font.GothamMedium
	ui.toast.TextSize = 14
	ui.toast.TextXAlignment = Enum.TextXAlignment.Left
	ui.toast.TextColor3 = COLOR.green
	ui.toast.Text = ""
	ui.toast.Parent = panel

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function patchPips(item): string
	if item.clean then
		return "clean"
	end
	local pips = string.rep("\u{25CF}", math.min(#item.patches, 6))
	return pips
end

local function paintRow(row: TextButton, item, isSelected: boolean, scrubUid: string?, scrubProgress: number)
	row.Visible = true
	row.Text = string.format(
		"%-22s %-7s %-7s $%d",
		string.sub(item.name, 1, 22),
		string.lower(item.stage),
		patchPips(item),
		item.value
	)
	row.TextColor3 = rarityColor(item.rarity)
	row.BackgroundTransparency = if isSelected then 0.55 else 1
	row.BackgroundColor3 = COLOR.selected
	row.Fill.Size = if scrubUid == item.uid then UDim2.fromScale(scrubProgress, 1) else UDim2.fromScale(0, 1)
	row:SetAttribute("Uid", item.uid)
end

local function render()
	if state.station == nil then
		ui.panel.Visible = false
		return
	end

	ui.panel.Visible = true

	-- Shop mode replaces the item list entirely: you are not carrying anything
	-- relevant to this transaction, so showing your backpack is noise.
	local atShop = state.station == "shop"
	ui.shop.Visible = atShop
	if atShop then
		local offer = state.offer
		ui.title.Text = `{string.upper(state.stationId or "SHOP")} SHOP`
		ui.title.TextColor3 = COLOR.amber
		ui.panelStroke.Color = COLOR.amber
		ui.subtitle.Text = string.format("$%d", state.cash or 0)

		if offer == nil then
			ui.shopUpgrade.Text = "nothing for sale here"
			ui.shopDeltas.Text = ""
			ui.buyButton.Visible = false
		elseif offer.maxed then
			ui.shopUpgrade.Text = `{offer.currentName} \u{2014} best there is`
			ui.shopUpgrade.TextColor3 = COLOR.green
			ui.shopDeltas.Text = ""
			ui.buyButton.Visible = false
		else
			ui.shopUpgrade.Text = `{offer.currentName}  \u{2192}  {offer.nextName}`
			ui.shopUpgrade.TextColor3 = COLOR.amber
			-- The deltas are the whole pitch. "radius 21 -> 27" sells the upgrade;
			-- the tier's NAME means nothing to someone who has not memorised the list.
			ui.shopDeltas.Text = table.concat(offer.deltas, "\n")
			ui.buyButton.Visible = true
			ui.buyButton.Text = `BUY  $${offer.price}`
			ui.buyButton.TextColor3 = if offer.affordable then COLOR.amber else COLOR.red
		end

		for _, row in ui.rows do
			row.Visible = false
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	local atDecon = state.station == "decon"
	ui.title.Text = if atDecon then "DECON STATION" else "TRADER"
	ui.title.TextColor3 = if atDecon then COLOR.blue else COLOR.amber
	ui.panelStroke.Color = if atDecon then COLOR.blue else COLOR.amber

	ui.subtitle.Text = if atDecon
		then string.format("$%d    %s (potency %d)    clocks stopped", state.cash or 0, state.cleanerName or "", state.potency or 1)
		else string.format("$%d    dirty items sell at 20%%", state.cash or 0)

	-- keep the selection valid
	local stillThere = false
	for _, item in state.items do
		if item.uid == selected then stillThere = true break end
	end
	for _, item in state.locker do
		if item.uid == selected then stillThere = true break end
	end
	if not stillThere then
		selected = if #state.items > 0 then state.items[1].uid else nil
	end

	for index, row in ui.rows do
		local item = state.items[index]
		if item then
			paintRow(row, item, item.uid == selected, state.scrubUid, state.scrubProgress or 0)
		else
			row.Visible = false
		end
	end

	ui.lockerTitle.Visible = #state.locker > 0
	ui.lockerTitle.Text = `QUARANTINE LOCKER \u{2014} {#state.locker} waiting on a better cleaner`
	for index, row in ui.lockerRows do
		local item = state.locker[index]
		if item then
			paintRow(row, item, item.uid == selected, nil, 0)
		else
			row.Visible = false
		end
	end

	-- Find the selected item to label the buttons honestly.
	local chosen = nil
	for _, item in state.items do
		if item.uid == selected then chosen = item break end
	end
	if chosen == nil then
		for _, item in state.locker do
			if item.uid == selected then chosen = item break end
		end
	end

	ui.scrubButton.Visible = atDecon
	ui.rackButton.Visible = atDecon
	ui.sellButton.Visible = not atDecon

	if chosen and chosen.blockedBy then
		ui.scrubButton.Text = `NEEDS {string.upper(chosen.needs or "")}`
		ui.scrubButton.TextColor3 = COLOR.red
	elseif chosen and chosen.clean then
		ui.scrubButton.Text = "CLEAN"
		ui.scrubButton.TextColor3 = COLOR.green
	else
		ui.scrubButton.Text = "HOLD TO SCRUB"
		ui.scrubButton.TextColor3 = COLOR.blue
	end

	ui.sellButton.Text = if chosen then `SELL  $${chosen.value}` else "SELL"
end

local function toast(message: string)
	ui.toast.Text = message
	toastToken += 1
	local token = toastToken
	task.delay(3.5, function()
		if token == toastToken then
			ui.toast.Text = ""
		end
	end)
end

-- ── Lifecycle ────────────────────────────────────────────────────────

function Station.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	actionRemote = Net.get("StationAction")

	local function bindRow(row: TextButton)
		row.MouseButton1Click:Connect(function()
			selected = row:GetAttribute("Uid")
			render()
		end)
	end
	for _, row in ui.rows do
		bindRow(row)
	end
	for _, row in ui.lockerRows do
		bindRow(row)
	end

	ui.scrubButton.MouseButton1Down:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "scrub", uid = selected, holding = true })
		end
	end)
	ui.scrubButton.MouseButton1Up:Connect(function()
		actionRemote:FireServer({ action = "scrub", holding = false })
	end)
	ui.scrubButton.MouseLeave:Connect(function()
		actionRemote:FireServer({ action = "scrub", holding = false })
	end)

	ui.sellButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "sell", uid = selected })
		end
	end)

	ui.buyButton.MouseButton1Click:Connect(function()
		-- Track only. The server re-derives which shop this is from where the
		-- player is standing, so a crafted payload buys nothing.
		if state.stationId then
			actionRemote:FireServer({ action = "buy", track = state.stationId })
		end
	end)

	ui.rackButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "rack", uid = selected })
		end
	end)

	Net.get("StationState").OnClientEvent:Connect(function(payload)
		state = payload
		state.items = payload.items or {}
		state.locker = payload.locker or {}
		local ok, err = pcall(render)
		if not ok then
			warn(`[station] render failed: {err}`)
		end
	end)

	Net.get("StationResult").OnClientEvent:Connect(function(message)
		toast(tostring(message))
	end)
end

return Station
