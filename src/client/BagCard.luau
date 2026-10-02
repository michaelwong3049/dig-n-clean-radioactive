--!strict
--[[
	BagCard.luau — the small dark card that floats over a dropped bag.

	One look for both places it is drawn: over somebody else's bag (DroppedBagController,
	close up only) and over your own (BagTrackerController's column label, from
	anywhere). A dark slab with an ink edge, a coloured strip down the left, the title
	in Gotham Black and a detail line under it (items and the countdown). Replaces the
	old free-floating GothamBold text and the LuckiestGuy "YOUR BAG 1:23" pill-label.
]]

local UIKit = require(script.Parent.UIKit)

local BagCard = {}

-- Design px on the billboard canvas.
BagCard.SIZE = Vector2.new(184, 50)

BagCard.GREEN = Color3.fromHex("8FE04A") -- the dropped sack's own locator-light green
BagCard.SLATE = Color3.fromHex("1D2326")
BagCard.INK = Color3.fromHex("1A1A1A")
BagCard.GREY = Color3.fromHex("9AA6AD")
BagCard.RED = UIKit.C.red

export type Card = {
	title: TextLabel,
	detail: TextLabel,
	strip: Frame,
}

--- Build the card on a UIKit.billboardCanvas sized to BagCard.SIZE.
function BagCard.build(canvas: Frame, accent: Color3): Card
	local card = UIKit.panel(canvas, {
		name = "Card",
		size = UDim2.fromScale(1, 1),
		color = BagCard.SLATE,
		transparency = 0.05,
		strokeColor = BagCard.INK,
		strokeThickness = 3,
		cornerRadius = UDim.new(0, 10),
	})

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0, 0.5)
	strip.Position = UDim2.new(0, 7, 0.5, 0)
	strip.Size = UDim2.new(0, 5, 1, -16)
	strip.BackgroundColor3 = accent
	strip.BorderSizePixel = 0
	strip.Parent = card
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = strip

	local title = UIKit.label(card, {
		name = "Title",
		size = UDim2.new(1, -28, 0, 22),
		position = UDim2.fromOffset(20, 5),
		font = Enum.Font.GothamBlack,
		textSize = 17,
		color = Color3.new(1, 1, 1),
		shadow = false,
	})
	title.TextTruncate = Enum.TextTruncate.AtEnd

	local detail = UIKit.label(card, {
		name = "Detail",
		size = UDim2.new(1, -28, 0, 17),
		position = UDim2.fromOffset(20, 27),
		font = Enum.Font.GothamBlack,
		textSize = 13,
		color = BagCard.GREY,
		shadow = false,
	})
	detail.RichText = true

	return { title = title, detail = detail, strip = strip }
end

function BagCard.items(n: number): string
	return if n == 1 then "1 item" else `{n} items`
end

function BagCard.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

--- "3 items · 1:12", the countdown going red under `lowSeconds`.
function BagCard.detailText(items: number, secondsLeft: number, lowSeconds: number): string
	local colour = if secondsLeft <= lowSeconds then BagCard.RED else Color3.new(1, 1, 1)
	return `{BagCard.items(items)}  \u{00B7}  <font color="#{colour:ToHex()}">{BagCard.clock(secondsLeft)}</font>`
end

return BagCard
