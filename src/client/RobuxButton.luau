--!strict
--[[
	RobuxButton.luau — the small purple "buy it with Robux" button that sits beside a
	HUD bar or on a world sign, outside the Shop panel.

	  pass(parent, key, caption)    a game pass (Config/GamePasses) by key: caption over
	                                "R$ 99". Owning it turns the button grey and reads
	                                OWNED (on request), off the Player attribute
	                                GamePassService mirrors ownership to.
	  product(parent, getId)        a developer product. `getId()` is re-read on every
	                                refresh() and press, for a button whose product
	                                changes (the treadmill sign's next rung). An optional
	                                `prompt(id)` replaces opening the prompt here, for a
	                                product the SERVER prompts (Recover Bag).

	Both read the price off the product itself, so a dashboard price change needs no
	code change; an id of 0 (not set up yet) shows a grey SOON and does nothing. Same
	purple as every other Robux button (ShopController's PANEL.buy).

	THE WASH VIEW LOCKS THE POINTER, so a purchase prompt opened from it would come up
	with no cursor to press Buy with. `prompting()` says one of these opened a prompt
	that hasn't closed yet, and WashController lets go of the pointer while it is true.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GamePasses = require(ReplicatedStorage.Shared.Config.GamePasses)

local RobuxButton = {}

local ROBUX = utf8.char(0xE002)
local PURPLE = Color3.fromHex("7B3FE4")
local PURPLE_HOVER = Color3.fromHex("9257F5")
local GREY = Color3.fromHex("4A4F55")
local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Button = {
	button: TextButton,
	caption: TextLabel?,
	price: TextLabel,
	refresh: () -> (),
	press: () -> (),
}

-- ── The prompt in flight ──────────────────────────────────────────────────

local openSince: number? = nil
--- A prompt that never reports closing (a dropped event) stops counting after this.
local PROMPT_TIMEOUT = 60

function RobuxButton.prompting(): boolean
	return openSince ~= nil and os.clock() - openSince < PROMPT_TIMEOUT
end

local function closed()
	openSince = nil
end
MarketplaceService.PromptGamePassPurchaseFinished:Connect(closed)
MarketplaceService.PromptProductPurchaseFinished:Connect(closed)

-- ── Prices ────────────────────────────────────────────────────────────────

local prices: { [string]: number | false } = {}
-- Everyone waiting on a price still loading. Six treadmill signs ask for the same
-- product at once; each must hear when it lands, not just the first to ask.
local waiting: { [string]: { () -> () } } = {}

--- "R$ 99" once the price has loaded (`onLoaded` runs then), the bare glyph until.
local function priceText(id: number, isPass: boolean, onLoaded: () -> ()): string
	local key = `{if isPass then "pass" else "product"}:{id}`
	local known = prices[key]
	if known then
		return `{ROBUX} {known}`
	end
	local list = waiting[key]
	if list == nil then
		list = {}
		waiting[key] = list
	end
	if not table.find(list, onLoaded) then
		table.insert(list, onLoaded)
	end
	if known == nil then
		prices[key] = false
		task.spawn(function()
			local info
			-- A couple of tries: the first call can fail while the game is still loading.
			for attempt = 1, 3 do
				local ok, result = pcall(function()
					return MarketplaceService:GetProductInfo(id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
				end)
				if ok and result and type(result.PriceInRobux) == "number" then
					info = result
					break
				end
				task.wait(2 * attempt)
			end
			if info == nil then
				prices[key] = nil -- try again on the next refresh
				return
			end
			prices[key] = info.PriceInRobux
			local listeners = waiting[key] or {}
			waiting[key] = nil
			for _, listener in listeners do
				task.spawn(listener)
			end
		end)
	end
	return ROBUX
end

-- ── The button ────────────────────────────────────────────────────────────

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Text = ""
	label.ZIndex = 3
	label.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = textSize
	limit.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = label
	return label
end

--- The bare button: purple, ink-outlined, a caption line over a price line (or the
--- price alone when `caption` is nil). Size and position are the caller's.
local function shell(parent: Instance, caption: string?): (TextButton, TextLabel?, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = "RobuxButton"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = PURPLE
	button.ZIndex = 2
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = button
	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200))
	gloss.Parent = button
	local scale = Instance.new("UIScale")
	scale.Name = "Press"
	scale.Parent = button

	local captionLabel: TextLabel? = nil
	local price: TextLabel
	if caption then
		captionLabel = text(button, "Caption", UDim2.new(1, -10, 0.42, 0), UDim2.new(0, 5, 0.08, 0), 18)
		;(captionLabel :: TextLabel).Text = caption
		price = text(button, "Price", UDim2.new(1, -10, 0.46, 0), UDim2.new(0, 5, 0.48, 0), 24)
	else
		price = text(button, "Price", UDim2.new(1, -12, 0.7, 0), UDim2.new(0, 6, 0.15, 0), 40)
	end
	return button, captionLabel, price
end

local function wire(button: TextButton, live: () -> boolean, press: () -> ())
	local scale = button:FindFirstChild("Press") :: UIScale
	button.MouseEnter:Connect(function()
		if live() then
			TweenService:Create(button, HOVER, { BackgroundColor3 = PURPLE_HOVER }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		if live() then
			TweenService:Create(button, HOVER, { BackgroundColor3 = PURPLE }):Play()
		end
	end)
	button.Activated:Connect(function()
		if not live() then
			return
		end
		scale.Scale = 0.9
		TweenService:Create(scale, PRESS, { Scale = 1 }):Play()
		press()
	end)
end

--- A game pass by Config/GamePasses key.
function RobuxButton.pass(parent: Instance, key: string, caption: string?): Button
	local player = Players.LocalPlayer
	local pass = GamePasses.byKey(key)
	local id = if pass then pass.id else 0
	local button, captionLabel, price = shell(parent, caption)
	local attr = GamePasses.attr(key)

	local function owned(): boolean
		return player:GetAttribute(attr) == true
	end
	local function live(): boolean
		return id ~= 0 and not owned()
	end

	local refresh: () -> ()
	function refresh()
		if owned() then
			button.BackgroundColor3 = GREY
			price.Text = "OWNED"
		elseif id == 0 then
			button.BackgroundColor3 = GREY
			price.Text = "SOON"
		else
			button.BackgroundColor3 = PURPLE
			price.Text = priceText(id, true, refresh)
		end
	end

	local function press()
		if not live() then
			return
		end
		openSince = os.clock()
		MarketplaceService:PromptGamePassPurchase(player, id)
	end

	wire(button, live, press)
	player:GetAttributeChangedSignal(attr):Connect(refresh)
	refresh()
	return { button = button, caption = captionLabel, price = price, refresh = refresh, press = press }
end

--- A developer product whose id `getId()` returns (0 = none). Call `refresh()` when
--- the id may have changed. `prompt(id)`, if given, opens the purchase instead.
function RobuxButton.product(parent: Instance, getId: () -> number, caption: string?, prompt: ((id: number) -> ())?): Button
	local button, captionLabel, price = shell(parent, caption)

	local function live(): boolean
		return getId() ~= 0
	end

	local refresh: () -> ()
	function refresh()
		local id = getId()
		if id == 0 then
			button.BackgroundColor3 = GREY
			price.Text = "SOON"
		else
			button.BackgroundColor3 = PURPLE
			price.Text = priceText(id, false, refresh)
		end
	end

	local function press()
		local id = getId()
		if id == 0 then
			return
		end
		openSince = os.clock()
		if prompt then
			prompt(id)
		else
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
		end
	end

	wire(button, live, press)
	refresh()
	return { button = button, caption = captionLabel, price = price, refresh = refresh, press = press }
end

return RobuxButton
