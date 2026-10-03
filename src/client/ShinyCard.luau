--!strict
--[[
	ShinyCard.luau — makes a gift card look like the "OP PET!" card: pastel rainbow
	background, spinning sunburst rays, an animated rainbow border, a light sweep, a soft
	pulse, a bobbing icon and an optional corner ribbon. Used on the big last card of the
	Free Gifts panel (PlaytimeGiftController).

	  local stop = ShinyCard.apply(card, {
	      icon = card.Icon,        -- ImageLabel that bobs (optional)
	      title = someLabel,       -- TextLabel that goes rainbow (optional)
	      timer = timerPill,       -- gets a white outline (optional)
	      badgeText = "BEST!",     -- little corner ribbon (optional)
	  })
	  stop()  -- removes every effect and gives the card its own look back

	It turns the card's own UIStrokes off while it runs (the rainbow border replaces them)
	and `stop` turns exactly those back on. It sets the card's fill to white so the pastel
	gradient shows true: a caller that colours the card (PlaytimeGiftController) must not
	repaint the fill while the effect is on.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ShinyCard = {}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 110, 225)), -- pink
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(110, 225, 255)), -- cyan
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(120, 255, 180)), -- mint
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 240, 110)), -- yellow
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 110, 225)), -- pink (loops)
})

local PASTEL_BG = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(105, 235, 225)),
	ColorSequenceKeypoint.new(0.45, Color3.fromRGB(205, 250, 150)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 240, 115)),
})

local function clearGradients(obj: Instance)
	for _, child in obj:GetChildren() do
		if child:IsA("UIGradient") then
			child:Destroy()
		end
	end
end

local function loopTween(obj: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

function ShinyCard.apply(card: GuiObject, opts: { [string]: any }?): () -> ()
	local o = opts or {}
	local created: { Instance } = {}
	local tweens: { Tween } = {}
	local conns: { RBXScriptConnection } = {}
	local silenced: { UIStroke } = {}
	local alive = true

	local function make(className: string, props: { [string]: any }, parent: Instance): any
		local inst = Instance.new(className)
		for k, v in props do
			(inst :: any)[k] = v
		end
		inst.Parent = parent
		table.insert(created, inst)
		return inst
	end

	-- 1. Pastel rainbow background --------------------------------------
	clearGradients(card)
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.BackgroundTransparency = 0
	make("UIGradient", { Color = PASTEL_BG, Rotation = 35 }, card)

	-- Match the card's rounded corners for the clipped effects layer
	local cardCorner = card:FindFirstChildOfClass("UICorner")
	local cornerRadius = cardCorner and cardCorner.CornerRadius or UDim.new(0, 12)

	-- 2. Effects layer (CanvasGroup clips to rounded corners) -----------
	local fx = make("CanvasGroup", {
		Name = "ShineFX",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0, -- sits behind the card's content (ZIndexBehavior = Sibling)
	}, card)
	make("UICorner", { CornerRadius = cornerRadius }, fx)

	-- Sunburst rays
	local spinner = make("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(2.2, 2.2),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundTransparency = 1,
	}, fx)

	local RAY_COUNT = 8 -- each frame makes 2 rays, so 16 total
	for i = 1, RAY_COUNT do
		local ray = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.09, 1),
			Rotation = (i - 1) * (180 / RAY_COUNT),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, spinner)
		-- fade toward the center and the tips so rays look soft
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.0, 1),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(0.5, 0.75),
				NumberSequenceKeypoint.new(0.7, 0.45),
				NumberSequenceKeypoint.new(1.0, 1),
			}),
		}, ray)
	end

	-- Light sweep that passes across the card
	local shine = make("Frame", {
		Name = "Sweep",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.4, 0.5),
		Size = UDim2.fromScale(0.25, 2),
		Rotation = 20,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, fx)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1.0, 1),
		}),
	}, shine)

	-- 3. Animated rainbow border ----------------------------------------
	for _, child in card:GetChildren() do
		if child:IsA("UIStroke") and child.Enabled then
			child.Enabled = false
			table.insert(silenced, child)
		end
	end
	local stroke = make("UIStroke", {
		Thickness = 5,
		Color = Color3.new(1, 1, 1),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, card)
	local strokeGrad = make("UIGradient", { Color = RAINBOW }, stroke)

	-- 4. Rainbow outlined text -----------------------------------------
	local title = o.title :: TextLabel?
	if title then
		clearGradients(title)
		title.TextColor3 = Color3.new(1, 1, 1)
		title.BackgroundTransparency = 1
		make("UIGradient", { Color = RAINBOW }, title)
		make("UIStroke", {
			Thickness = 2,
			Color = Color3.fromRGB(60, 25, 90),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}, title)
	end

	-- 5. Glossy timer pill ---------------------------------------------
	local timer = o.timer :: GuiObject?
	if timer then
		make("UIStroke", {
			Thickness = 3,
			Color = Color3.new(1, 1, 1),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, timer)
	end

	-- 6. Corner ribbon ("MEGA!", "BEST!", etc.) ------------------------
	if o.badgeText then
		local badge = make("TextLabel", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -18, 0, 14),
			Size = UDim2.fromOffset(78, 26),
			Rotation = 12,
			ZIndex = 20, -- over the card's own content (ZIndex 12-13)
			BackgroundColor3 = Color3.fromRGB(255, 70, 120),
			Text = o.badgeText,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
		}, card)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
		make("UIStroke", {
			Thickness = 2,
			Color = Color3.new(1, 1, 1),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, badge)
		table.insert(
			tweens,
			loopTween(
				badge,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Rotation = 4 }
			)
		)
	end

	-- 7. Motion --------------------------------------------------------
	-- spin rays + rotate border gradient
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function(dt)
			spinner.Rotation = (spinner.Rotation + dt * 10) % 360
			strokeGrad.Rotation = (strokeGrad.Rotation + dt * 90) % 360
		end)
	)

	-- light sweep every ~2.5s
	task.spawn(function()
		while alive and shine.Parent do
			shine.Position = UDim2.fromScale(-0.4, 0.5)
			local t = TweenService:Create(
				shine,
				TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ Position = UDim2.fromScale(1.4, 0.5) }
			)
			t:Play()
			t.Completed:Wait()
			task.wait(1.6)
		end
	end)

	-- soft pulse on the whole card
	local scale = card:FindFirstChildOfClass("UIScale") or make("UIScale", {}, card)
	local baseScale = scale.Scale
	table.insert(
		tweens,
		loopTween(
			scale,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = baseScale * 1.035 }
		)
	)

	-- bobbing icon
	local icon = o.icon :: GuiObject?
	local iconHome = if icon then icon.Position else nil
	if icon and iconHome then
		table.insert(
			tweens,
			loopTween(
				icon,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = iconHome - UDim2.fromOffset(0, 5), Rotation = 4 }
			)
		)
	end

	-- cleanup: every effect goes, and the card gets its own strokes, scale and icon back
	return function()
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		for _, t in tweens do
			t:Cancel()
		end
		for _, inst in created do
			if inst.Parent then
				inst:Destroy()
			end
		end
		for _, s in silenced do
			s.Enabled = true
		end
		scale.Scale = baseScale
		if icon and iconHome then
			icon.Position = iconHome
			icon.Rotation = 0
		end
	end
end

return ShinyCard
