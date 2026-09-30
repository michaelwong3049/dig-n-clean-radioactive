--[[
	AuraTipController.lua — the one-time "upgrade your aura" popup.

	The first time a player's aura fails (ExposureState `failing`), a centred card says
	what to do about it, with an OK button. OK reports "tutorialSeen" id "aura", and the
	server's `auraTip` flag stops it for good.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(script.Parent.Parent.UIKit)

local AuraTipController = {}

local MESSAGE = "To last deeper in the stages, upgrade your aura"

local shown = false

local function show()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AuraTip"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local canvas = UIKit.canvas(gui)

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(460, 190)
	card.BackgroundColor3 = Color3.fromHex("22272C")
	card.BorderSizePixel = 0
	card.Parent = canvas
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromHex("F2A93B")
	stroke.Thickness = 2
	stroke.Parent = card

	UIKit.label(card, {
		name = "Message",
		size = UDim2.new(1, -36, 0, 100),
		position = UDim2.fromOffset(18, 18),
		font = Enum.Font.FredokaOne,
		textSize = 26,
		color = Color3.new(1, 1, 1),
		wrapped = true,
		text = MESSAGE,
	})

	local ok = UIKit.button(card, {
		name = "Ok",
		size = UDim2.fromOffset(140, 44),
		position = UDim2.new(0.5, 0, 1, -18),
		anchorPoint = Vector2.new(0.5, 1),
		text = "OK",
		font = Enum.Font.LuckiestGuy,
		textSize = 24,
		color = Color3.new(1, 1, 1),
		fillColor = Color3.fromHex("3FBF5A"),
	})
	ok.Activated:Connect(function()
		gui:Destroy()
		Net.get("StationAction"):FireServer({ action = "tutorialSeen", id = "aura" })
	end)
end

function AuraTipController.start()
	Net.get("ExposureState").OnClientEvent:Connect(function(payload)
		if not shown and payload.auraTip == true and payload.failing == true and payload.downed ~= true then
			shown = true
			show()
		end
	end)
end

return AuraTipController
