--!strict
--[[
	PurchaseHintController.luau — the quick "You can purchase ...!" pop-ups just under
	the HOME / SHOPS warp bar.

	EVERY gear rung that becomes affordable gets its own pop-up, once. They all pop at
	the same time, stacked one under another (cheapest on top, at most MAX_ROWS on
	screen; the rest wait for room). Each one STAYS until the player clicks its X, or
	until it stops being true (bought, or cash fell back under the price). "A rung"
	here is any tier above the best one you own on its track (Detector, Magnet, Hose,
	Aura) whose price is at or under your cash. A rung you drop back below (you spent
	money) is forgotten, so it pops up again when you can afford it again.

	SHOWN ONLY WHEN THE WARP BAR IS: standing in no stage and not downed, the same test
	WarpController makes off ExposureState. It also hides while the tutorial's banner is
	up, since that banner sits at the same height. Rows already up are kept while hidden
	and come back with the bar; anything that became affordable meanwhile pops then.

	READS CashState (the balance) and GearList (what you own). GearList only answers a
	GearAction "list", so this asks once on start and again whenever cash goes DOWN —
	a spend is the only way ownership changes. Pure presentation; nothing is bought
	from here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Gear = require(Shared.Config.Gear)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)

local PurchaseHintController = {}

-- Design px. The warp bar spans y 10..74; this sits a little below it.
local Y = 84
local H = 30 -- text row height
local CLOSE = 24 -- the X button's square
local MAX_ROWS = 8 -- most rows on screen at once, so a big cash jump cannot fill it
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ACCENT = Color3.fromHex("FFE36B")
local CLOSE_RED = Color3.fromHex("E5484D")

local cash: number? = nil
local bestOwned: { [string]: number }? = nil
local atCamp = false
local ui: Frame? = nil -- the stack the rows go in
local tutorialBanner: GuiObject? = nil

-- "Track:tier" keys already queued or shown while affordable.
local announced: { [string]: boolean } = {}
type Rung = { track: string, tier: number, price: number }
local queue: { Rung } = {} -- rungs waiting to pop
local orderSeq = 0
type Row = { rung: Rung, frame: Frame }
local rows: { [string]: Row } = {} -- "Track:tier" -> the row on screen
local rowCount = 0

--- Queue every newly affordable rung (cheapest first); forget ones no longer affordable.
local function scan()
	if cash == nil or bestOwned == nil then
		return
	end
	local fresh: { Rung } = {}
	for _, track in Gear.TRACKS do
		for tier = (bestOwned[track] or 1) + 1, Gear.maxTier(track) do
			local def = Gear.tier(track, tier)
			local key = `{track}:{tier}`
			if def.price <= cash then
				if not announced[key] then
					announced[key] = true
					table.insert(fresh, { track = track, tier = tier, price = def.price })
				end
			else
				announced[key] = nil
			end
		end
	end
	table.sort(fresh, function(a, b)
		return a.price < b.price
	end)
	for _, item in fresh do
		table.insert(queue, item)
	end
end

local function stillTrue(rung: Rung): boolean
	local owned = (bestOwned :: any)[rung.track] or 1
	return rung.tier > owned and cash ~= nil and rung.price <= cash
end

--- Take a row off screen: shrinks away, then is gone. The rung stays announced, so a
--- dismissed row does not come back until it drops out of reach and returns.
local function closeRow(key: string)
	local entry = rows[key]
	if entry == nil then
		return
	end
	rows[key] = nil
	rowCount -= 1
	local frame = entry.frame
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		local tween = TweenService:Create(scale, FADE, { Scale = 0 })
		tween:Play()
		tween.Completed:Wait()
	end
	frame:Destroy()
end

local function tutorialUp(): boolean
	if tutorialBanner == nil or tutorialBanner.Parent == nil then
		local hud = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local tutorial = hud and hud:FindFirstChild("TutorialHud")
		local found = tutorial and tutorial:FindFirstChild("Banner", true)
		tutorialBanner = if found and found:IsA("GuiObject") then found else nil
	end
	return tutorialBanner ~= nil and tutorialBanner.Visible
end

--- One pop-up row: springs in and stays until its X is clicked.
local function popRow(list: Frame, key: string, rung: Rung, name: string, order: number)
	local row = Instance.new("Frame")
	row.Name = "Hint"
	row.LayoutOrder = order
	row.Size = UDim2.fromOffset(0, H)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = row

	-- No box: just chunky outlined text, like a Roblox game title.
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.RichText = true
	label.Text = `You can purchase <font color="#{ACCENT:ToHex()}">{name}</font>!`
	label.Parent = row
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row
	label.LayoutOrder = 1

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.LayoutOrder = 2
	close.Size = UDim2.fromOffset(CLOSE, CLOSE)
	close.BackgroundColor3 = CLOSE_RED
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = row
	local closeStroke = Instance.new("UIStroke")
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Color = Color3.new(0, 0, 0)
	closeStroke.Thickness = 2
	closeStroke.Parent = close
	close.Activated:Connect(function()
		Sfx.play("click")
		closeRow(key)
	end)

	rows[key] = { rung = rung, frame = row }
	rowCount += 1
	row.Parent = list
	TweenService:Create(scale, POP, { Scale = 1 }):Play()
end

--- Pop every queued rung at once, stacked under each other, cheapest on top.
local function pump()
	local list = ui
	if list == nil or bestOwned == nil then
		return
	end
	-- Rows that stopped being true (bought, or out of reach again) close themselves.
	for key, entry in rows do
		if not stillTrue(entry.rung) then
			task.spawn(closeRow, key)
		end
	end
	local visible = atCamp and not tutorialUp()
	list.Visible = visible
	if not visible or #queue == 0 then
		return
	end
	local waiting: { Rung } = {}
	for _, rung in queue do
		-- Skip anything bought or no longer affordable since it was queued.
		if not stillTrue(rung) then
			continue
		end
		local key = `{rung.track}:{rung.tier}`
		if rows[key] then
			continue
		end
		if rowCount >= MAX_ROWS then
			table.insert(waiting, rung) -- pops once a row is closed
			continue
		end
		orderSeq += 1
		popRow(list, key, rung, Gear.tier(rung.track, rung.tier).name, orderSeq)
		Sfx.play("hint") -- one ding per burst: the cue's cooldown folds a stack of rows
	end
	queue = waiting
end

local function refresh()
	scan()
	pump()
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PurchaseHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 89 -- just under the warp bar (90)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)
	local list = Instance.new("Frame")
	list.Name = "Stack"
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.new(0.5, 0, 0, Y)
	list.Size = UDim2.fromOffset(600, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = canvas
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = list

	ui = list
	return gui
end

function PurchaseHintController.start()
	local player = Players.LocalPlayer
	build().Parent = player:WaitForChild("PlayerGui")

	local actionRemote = Net.get("GearAction")
	Net.get("GearList").OnClientEvent:Connect(function(list)
		if list == nil or list.tracks == nil then
			return
		end
		local owned = {}
		for _, entry in list.tracks do
			local best = 1
			for _, row in entry.owned do
				best = math.max(best, row.tier)
			end
			owned[entry.track] = best
		end
		bestOwned = owned
		refresh()
	end)

	Net.get("CashState").OnClientEvent:Connect(function(amount: number)
		local spent = cash ~= nil and amount < cash
		cash = amount
		if spent or bestOwned == nil then
			actionRemote:FireServer("list")
		end
		refresh()
	end)

	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		local next = state.stageId == nil and state.downed ~= true
		if next ~= atCamp then
			atCamp = next
			refresh()
		end
	end)

	-- The tutorial banner comes and goes on its own schedule; a slow check keeps up.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.5 then
			elapsed = 0
			refresh()
		end
	end)

	actionRemote:FireServer("list")
end

return PurchaseHintController
