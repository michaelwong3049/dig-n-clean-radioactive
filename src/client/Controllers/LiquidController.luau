--[[
	LiquidController.lua — what is loaded in the hose, and how much of it is left,
	shown ON THE WASH PAD in the world rather than in a screen badge.

	THIS USED TO BE A SCREEN BADGE, bottom-left in the instrument column, always on.
	The rule it was written to obey was "no UI that pops up when you press the button",
	and it obeyed it — but a permanent rectangle in the corner for a fact that only
	matters at two spots on the base (the pad you roll at, the tub you spray at) is
	still a HUD panel for a world object that can answer for itself. It does now: this
	is a BillboardGui floating over the player's own wash pad, so "what have I got
	loaded" is read by looking at the thing you loaded it at.

	PER-VIEWER, PARENTED TO PlayerGui WITH AN Adornee. The loaded liquid is private
	profile state, so a server-built billboard on the shared pad part would show one
	player's canister to everyone standing there. A BillboardGui under PlayerGui with
	`Adornee` set renders in the world for this client alone — the same trick
	BaseMarkerController uses for the "YOUR BASE" beacon.

	IT SITS BELOW THE PAD'S OWN SIGN, on purpose. LiquidService flashes the pad's
	`Sign` billboard (~5 studs up) with the RESULT of a roll for four seconds; this
	readout sits lower, near the disc, and never moves — the roll announcement is an
	event, this is a resting state, and stacking them keeps both legible.

	COLOUR COMES FROM THE LIQUID, NOT FROM THE PALETTE, and this is the one place in
	the client allowed to do that. Config/Liquids owns a hex per liquid so the canister
	on the pad's shelf, the stream out of the hose and this readout are provably the
	same colour. The one rule it still obeys: no liquid may be the ooze green, because
	that green is the field and nothing else (PLAN §14) — enforced in Config/Liquids'
	own palette, not here.

	WashController draws its own bottom-right fluid label for the first-person wash —
	this readout is hidden with the rest of the HUD for the duration of a session.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Liquids = require(Shared.Config.Liquids)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local Liquid = {}

local ui = {}
-- The last LiquidState we were handed. Kept so the readout can be painted the moment
-- the pad resolves, even if that happens after the first state has already arrived.
local lastView: any = nil

--- Build the billboard once. Returns nil until the local player's plot — and the
--- wash pad on it — exists in the world.
local function build(): BillboardGui?
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end

	local plot = ui.plotModel
	if plot == nil or plot.Parent == nil then
		return nil
	end
	local plate = plot:FindFirstChild("WashPad")
	plate = plate and plate:FindFirstChild("Plate")
	if plate == nil or not plate:IsA("BasePart") then
		return nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "LiquidReadout"
	gui.Adornee = plate
	-- Low, near the lit disc — well under the pad's own Sign, which LiquidService
	-- flashes ~5 studs up with the result of a roll.
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	-- Defaults to 1, which washes the sign toward white next to the disc's PointLight
	-- — the exact bug Kit.billboard documents. This should read the same lit or not.
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	-- 190x44 design pixels, scaled with the rest of the HUD (UIKit.billboardCanvas).
	local canvas = UIKit.billboardCanvas(gui, Vector2.new(190, 44))

	local panel, stroke = UIKit.panel(canvas, {
		name = "Card",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromScale(0, 0),
		color = UIKit.C.panel,
		transparency = 0.15,
		cornerRadius = UIKit.Radius.card,
		strokeThickness = UIKit.Stroke.normal,
	})
	panel.AnchorPoint = Vector2.zero
	ui.stroke = stroke

	-- A solid chip of the liquid's own colour, so the readout is identifiable without
	-- being read — the same "navigate by colour, not by sign" trick the shop stalls
	-- and the old badge used.
	ui.chip = UIKit.panel(panel, {
		name = "Chip",
		size = UDim2.fromOffset(14, 14),
		position = UDim2.new(0, 12, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
		color = UIKit.C.text,
		transparency = 0,
		cornerRadius = UIKit.Radius.pill,
		strokeThickness = UIKit.Stroke.thin,
	})

	ui.nameLabel = UIKit.label(panel, {
		name = "NameLabel",
		size = UDim2.new(1, -90, 1, 0),
		position = UDim2.fromOffset(34, 0),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.text,
		strokeTransparency = 0,
		text = "Plain Water",
	})

	ui.chargesLabel = UIKit.label(panel, {
		name = "Charges",
		size = UDim2.new(0, 54, 1, 0),
		position = UDim2.new(1, -66, 0, 0),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Right,
		strokeTransparency = 0,
		text = "\u{221E}",
	})

	return gui
end

local function paint(view)
	if ui.gui == nil or ui.gui.Parent == nil then
		return
	end

	local def = Liquids.get(view.equipped)
	local colour = Color3.fromHex(def.color)

	ui.chip.BackgroundColor3 = colour
	ui.nameLabel.Text = def.name
	ui.stroke.Color = colour

	-- The infinity sign is the whole point of Plain Water, so it gets the symbol
	-- rather than a number. A readout saying "0 left" over the one liquid that can
	-- never run out would teach exactly the wrong thing.
	if view.equipped == Liquids.WATER then
		ui.chargesLabel.Text = "\u{221E}"
		ui.chargesLabel.TextColor3 = UIKit.C.dim
	else
		local left = view.liquidCharges or 0
		ui.chargesLabel.Text = `{left} left`
		ui.chargesLabel.TextColor3 = if left <= 3 then UIKit.C.amber else UIKit.C.dim
	end
end

--- Try to stand the billboard up. Safe to call repeatedly — it is a no-op once the
--- billboard exists, and a retry while the plot is still replicating.
local function ensure()
	if ui.gui and ui.gui.Parent then
		return
	end
	ui.gui = build()
	if ui.gui and lastView then
		paint(lastView)
	end
end

--- Resolve `Workspace.Plots.Plot{index}` and remember it, then (re)build. Mirrors
--- BaseMarkerController.onPlot — PlotState is fired once, well after this controller
--- has connected.
local function onPlot(index: number?)
	if index == nil then
		return
	end
	task.spawn(function()
		local plots = Workspace:WaitForChild("Plots", 10)
		local plot = plots and plots:WaitForChild(`Plot{index}`, 10)
		if plot == nil then
			warn(`[liquid] plot {index} never appeared; readout has nowhere to hang`)
			return
		end
		ui.plotModel = plot
		ensure()
	end)
end

function Liquid.start()
	Net.get("PlotState").OnClientEvent:Connect(onPlot)

	Net.get("LiquidState").OnClientEvent:Connect(function(view)
		if type(view) ~= "table" then
			return
		end
		-- The readout wants the charge count of the LOADED liquid specifically, which
		-- the payload carries per-entry across the whole shelf. Flattened here rather
		-- than added to the payload, because LiquidService.viewFor is also what the
		-- debug console reads and it wants the whole shelf.
		local charges = 0
		for _, entry in view.liquids or {} do
			if entry.id == view.equipped then
				charges = entry.held
				break
			end
		end
		view.liquidCharges = charges
		lastView = view

		ensure()
		if ui.gui then
			paint(view)
		end
	end)
end

return Liquid
