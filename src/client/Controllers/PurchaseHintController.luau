--!strict
--[[
	PurchaseHintController.luau — the quick "You can purchase ...!" pop-ups just under
	the HOME / SHOPS warp bar.

	EVERY gear rung that becomes affordable gets its own pop-up, once: each one springs
	in, holds for HOLD seconds, shrinks away, and the next queued rung follows. "A rung"
	here is any tier above the best one you own on its track (Detector, Magnet, Hose,
	Aura) whose price is at or under your cash. A rung you drop back below (you spent
	money) is forgotten, so it pops up again when you can afford it again.

	SHOWN ONLY WHEN THE WARP BAR IS: standing in no stage and not downed, the same test
	WarpController makes off ExposureState. It also waits while the tutorial's banner is
	up, since that banner sits at the same height. The queue just pauses meanwhile.

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

local PurchaseHintController = {}

-- Design px. The warp bar spans y 10..74; this sits a little below it.
local Y = 84
local H = 30 -- text row height
local HOLD = 3.5 -- seconds each pop-up stays up
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ACCENT = Color3.fromHex("FFE36B")

local cash: number? = nil
local bestOwned: { [string]: number }? = nil
local atCamp = false
local ui: { pill: Frame, scale: UIScale, label: TextLabel }? = nil
local tutorialBanner: GuiObject? = nil

-- "Track:tier" keys already queued or shown while affordable.
local announced: { [string]: boolean } = {}
type Rung = { track: string, tier: number, price: number }
local queue: { Rung } = {} -- rungs waiting their turn
local busy = false

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

local function tutorialUp(): boolean
	if tutorialBanner == nil or tutorialBanner.Parent == nil then
		local hud = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local tutorial = hud and hud:FindFirstChild("TutorialHud")
		local found = tutorial and tutorial:FindFirstChild("Banner", true)
		tutorialBanner = if found and found:IsA("GuiObject") then found else nil
	end
	return tutorialBanner ~= nil and tutorialBanner.Visible
end

--- Show the next queued pop-up, if one is waiting and the spot is free.
local pump: () -> ()
function pump()
	local parts = ui
	if parts == nil or busy or #queue == 0 or not atCamp or tutorialUp() then
		return
	end
	-- Skip anything bought or no longer affordable since it was queued.
	local rung = table.remove(queue, 1)
	local owned = (bestOwned :: any)[rung.track] or 1
	if rung.tier <= owned or cash == nil or rung.price > cash then
		pump()
		return
	end
	busy = true
	local name = Gear.tier(rung.track, rung.tier).name
	parts.label.Text = `You can purchase <font color="#{ACCENT:ToHex()}">{name}</font>!`
	parts.pill.Visible = true
	parts.scale.Scale = 0.6
	TweenService:Create(parts.scale, POP, { Scale = 1 }):Play()
	task.delay(HOLD, function()
		local tween = TweenService:Create(parts.scale, FADE, { Scale = 0 })
		tween:Play()
		tween.Completed:Wait()
		parts.pill.Visible = false
		busy = false
		pump()
	end)
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
	-- No box: just chunky outlined text, like a Roblox game title.
	local pill = Instance.new("Frame")
	pill.Name = "Hint"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, Y)
	pill.Size = UDim2.fromOffset(0, H)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundTransparency = 1
	pill.Visible = false
	pill.Parent = canvas
	local scale = Instance.new("UIScale")
	scale.Parent = pill

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.RichText = true
	label.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	ui = { pill = pill, scale = scale, label = label }
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
