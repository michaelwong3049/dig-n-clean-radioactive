--!strict
--[[
	PurchaseHintController.luau — the quick "You can afford a new Aura" pop-ups just
	under the HOME / SHOPS warp bar.

	ONE LINE PER GEAR TRACK (Detector, Magnet, Hose, Aura), not per tier: a track pops
	once when any tier above the best one you own on it comes within your cash, with
	the track's word in its own colour. They stack one under another (cheapest on top,
	at most MAX_ROWS on screen). Each one STAYS until the player clicks its X, or until
	it stops being true (nothing on that track affordable any more). A track that drops
	back out of reach (you spent money) is forgotten, so it pops up again later.

	SHOWN ONLY WHEN THE WARP BAR IS: standing in no stage and not downed, the same test
	WarpController makes off ExposureState. It also hides while the tutorial's banner is
	up, since that banner sits at the same height. Rows already up are kept while hidden
	and come back with the bar; anything that became affordable meanwhile pops then.

	THE NEXT BASE UPGRADE GETS A LINE TOO (on request): "You can afford a Base Upgrade"
	once your cash covers the next Upgrade Base. Your plot is read off RespawnLocation
	(its PlotSpawn carries PlotIndex) and its level off that plot's `BaseLevel`
	attribute (build/Plots.setLevel).

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
local BaseUpgrades = require(Shared.Config.BaseUpgrades)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)

local PurchaseHintController = {}

-- Design px. The warp bar spans y 10..74; this sits a little below it.
local Y = 84
local H = 30 -- text row height
local CLOSE = 24 -- the X button's square
local MAX_ROWS = 8 -- most rows on screen at once, so a big cash jump cannot fill it
-- Each line sits on a small dark band that fades out at both ends: a mini version of
-- the tutorial banner's band (TutorialController BANNER_SHADE / BANNER_FADE).
local BAND_W = 520
local BAND_H = 36
local BAND_SHADE = 0.35 -- the band's BackgroundTransparency at its middle
local BAND_FADE = 0.25 -- fraction of the width each side spends fading out
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local CLOSE_RED = Color3.fromHex("E5484D")

-- What each track is called in the line, and the colour its word is drawn in.
local TRACK_LABEL: { [string]: string } = {
	Detector = "Detector",
	Magnet = "Magnet",
	Cleaner = "Hose",
	Aura = "Aura",
}
local TRACK_COLOR: { [string]: Color3 } = {
	Detector = Color3.fromHex("4DA6FF"), -- blue
	Magnet = Color3.fromHex("FF5A5A"), -- red
	Cleaner = Color3.fromHex("4DE3E0"), -- cyan
	Aura = Color3.fromHex("B77BFF"), -- purple
}
-- The base-upgrade line's key, beside the gear tracks, and its word's colour (the
-- Upgrade Base sign's own price green, build/Plots UPGRADE_SIGN_PRICE_COLOR).
local FLOOR_KEY = "Floor"
local FLOOR_COLOR = Color3.fromHex("8FE36B")

local cash: number? = nil
-- Best tier owned per track. Every stat climbs with the tier (see Config/Gear), so
-- "a higher tier than this" is exactly "better than anything you have".
local bestOwned: { [string]: number }? = nil
-- A spend can be a gear purchase, so after one `bestOwned` may be stale until the new
-- GearList lands. Nothing pops or closes while this is set; it holds the send time.
local listPendingSince: number? = nil
local atCamp = false
local ui: Frame? = nil -- the stack the rows go in
local tutorialBanner: GuiObject? = nil

-- Tracks already queued or shown while something on them is affordable.
local announced: { [string]: boolean } = {}
type Rung = { track: string, price: number, floor: number? }
local queue: { Rung } = {} -- tracks waiting to pop
local orderSeq = 0
type Row = { rung: Rung, frame: Frame }
local rows: { [string]: Row } = {} -- track -> the row on screen
local rowCount = 0

--- The upgrade level your base would buy next and its price, or nil (no plot, or maxed).
local function nextFloor(): (number?, number?)
	local spawn = Players.LocalPlayer.RespawnLocation
	local index = spawn and spawn:GetAttribute("PlotIndex")
	local row = workspace:FindFirstChild("Plots")
	local plot = type(index) == "number" and row and row:FindFirstChild(`Plot{index}`)
	if not plot then
		return nil, nil
	end
	local owned = BaseUpgrades.clamp(plot:GetAttribute("BaseLevel"))
	local price = BaseUpgrades.nextPrice(owned)
	if price == nil then
		return nil, nil
	end
	return owned + 1, price
end

--- Cheapest price of any tier above the best owned on this track, if within cash.
--- For FLOOR_KEY: the next upgrade's price, if within cash.
local function cheapestAffordable(track: string): number?
	if cash == nil or bestOwned == nil then
		return nil
	end
	if track == FLOOR_KEY then
		local _, price = nextFloor()
		return if price ~= nil and price <= cash then price else nil
	end
	local best: number? = nil
	for tier = (bestOwned[track] or 1) + 1, Gear.maxTier(track) do
		local price = Gear.tier(track, tier).price
		if price <= cash and (best == nil or price < best) then
			best = price
		end
	end
	return best
end

--- Queue every track that newly has something affordable (cheapest first); forget
--- tracks with nothing affordable left.
local function scan()
	if cash == nil or bestOwned == nil then
		return
	end
	local fresh: { Rung } = {}
	local tracks = table.clone(Gear.TRACKS)
	table.insert(tracks, FLOOR_KEY)
	for _, track in tracks do
		local price = cheapestAffordable(track)
		-- Each upgrade is announced once on its own, so the next still pops after one is bought.
		local floor = if track == FLOOR_KEY then (nextFloor()) else nil
		local key = if floor ~= nil then `{FLOOR_KEY}{floor}` else track
		if price ~= nil then
			if not announced[key] then
				announced[key] = true
				table.insert(fresh, { track = track, price = price, floor = floor })
			end
		else
			announced[key] = nil
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
	if rung.floor ~= nil and (nextFloor()) ~= rung.floor then
		return false -- that upgrade was bought; the next one pops on its own
	end
	return cheapestAffordable(rung.track) ~= nil
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

--- One pop-up row on its dark band: springs in and stays until its X is clicked.
local function popRow(list: Frame, key: string, rung: Rung, order: number)
	-- The band: dark in the middle, see-through at both ends. A UIGradient only
	-- touches its own frame's background, so the words and X on top stay solid.
	local band = Instance.new("Frame")
	band.Name = "Hint"
	band.LayoutOrder = order
	band.Size = UDim2.fromOffset(BAND_W, BAND_H)
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = BAND_SHADE
	band.BorderSizePixel = 0
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(BAND_FADE, 0),
		NumberSequenceKeypoint.new(1 - BAND_FADE, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = band
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = band

	local row = Instance.new("Frame")
	row.Name = "Content"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromOffset(0, H)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.Parent = band

	-- Chunky outlined text, like a Roblox game title, over the band.
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.RichText = true
	if rung.floor ~= nil then
		label.Text = `You can afford a <font color="#{FLOOR_COLOR:ToHex()}">Base Upgrade</font>`
	else
		local word = TRACK_LABEL[rung.track] or rung.track
		local color = TRACK_COLOR[rung.track] or Color3.new(1, 1, 1)
		label.Text = `You can afford a new <font color="#{color:ToHex()}">{word}</font>`
	end
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

	rows[key] = { rung = rung, frame = band }
	rowCount += 1
	band.Parent = list
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
		local key = rung.track
		if rows[key] then
			continue
		end
		if rowCount >= MAX_ROWS then
			table.insert(waiting, rung) -- pops once a row is closed
			continue
		end
		orderSeq += 1
		popRow(list, key, rung, orderSeq)
	end
	queue = waiting
end

local function refresh()
	if listPendingSince ~= nil then
		return
	end
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
			local best = math.max(1, entry.equipped or 1)
			for _, row in entry.owned do
				best = math.max(best, row.tier)
			end
			owned[entry.track] = best
		end
		bestOwned = owned
		listPendingSince = nil
		refresh()
	end)

	Net.get("CashState").OnClientEvent:Connect(function(amount: number)
		local spent = cash ~= nil and amount < cash
		cash = amount
		if spent or bestOwned == nil then
			if spent then
				listPendingSince = os.clock()
			end
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
			-- A lost GearList reply must not freeze the hints: ask again.
			if listPendingSince ~= nil and os.clock() - listPendingSince > 3 then
				listPendingSince = os.clock()
				actionRemote:FireServer("list")
			end
			refresh()
		end
	end)

	actionRemote:FireServer("list")
end

return PurchaseHintController
