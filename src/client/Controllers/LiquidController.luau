--[[
	LiquidController.lua — the wash pad's payout moment, and the badge that remembers it.

	TWO SURFACES, AND THEY DELIBERATELY READ FROM TWO DIFFERENT REMOTES.

	  LiquidRoll  -> the reveal. A one-shot EVENT. Fires once per roll, animates, and
	                 is gone. Nothing re-renders from it.
	  LiquidState -> the badge. Idempotent state, change-driven. Says what is loaded
	                 and how much of it is left, forever, from anywhere on the map.

	Folding the reveal into the state payload would replay the slot machine every time
	an unrelated field moved — see Shared/Net.luau, which makes the same split for
	SweepState vs Unearthed and for the same reason.

	THE REVEAL SPINS BEFORE IT LANDS, AND THE SPIN IS A LIE. The server has already
	decided; `spin()` below cycles names purely for the ~0.9s it takes for the player
	to lean in. That is not a dark pattern, it is the entire difference between "a
	number changed" and "I won something" — the same reason DetectorController's
	unearth banner exists at all rather than a toast saying "+1 item". Nothing about
	the outcome, the odds, or the cash already spent depends on it, and cutting
	SPIN_SECONDS to 0 changes nothing but the feel.

	THE BADGE LIVES IN THE BOTTOM-LEFT COLUMN with the meter, the cash and the index
	button, at Dock.LIQUID_BOTTOM. That column is now four elements tall; the badge is
	the shortest of them on purpose, because it carries one name and one number.

	COLOUR COMES FROM THE LIQUID, NOT FROM THE PALETTE, and this is the one place in
	the client that is allowed to do that. Config/Liquids owns a hex per liquid so the
	canister on the shelf, the stream out of the hose and this badge are provably the
	same colour; picking a UIKit.C entry here instead would put the badge permanently
	out of step with the world geometry. The one rule it still obeys: no liquid may be
	Neon green, because green is the ooze and nothing else (PLAN §14) — enforced in
	Config/Liquids' own palette, not here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Liquids = require(Shared.Config.Liquids)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Liquid = {}

local SPIN_SECONDS = 0.9
local SPIN_INTERVAL = 0.06
local HOLD_SECONDS = 3.2

local ui = {}
local revealToken = 0

--- Everything the pad can hand you, worst first — what the spin cycles through.
--- Derived from Liquids.ORDER rather than listed, so a catalogue change cannot leave
--- the spinner advertising something that no longer exists.
local ROLLABLE: { string } = {}
for _, id in Liquids.ORDER do
	if Liquids.isRollable(id) then
		table.insert(ROLLABLE, id)
	end
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "LiquidHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above the cash badge (80) and the index button (90), below HudController's
	-- vignette and blackout curtain (100): a blackout has to cover this, and the
	-- reveal has to cover the two badges it overlaps nothing else with.
	gui.DisplayOrder = 95
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- ── The badge ────────────────────────────────────────────────────
	local badge, badgeStroke = UIKit.panel(gui, {
		name = "LiquidBadge",
		size = Dock.LIQUID_SIZE,
		position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 1, -Dock.LIQUID_BOTTOM),
		anchorPoint = Vector2.new(0, 1),
		color = UIKit.C.panel,
		transparency = 0.1,
		cornerRadius = UIKit.Radius.card,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 3,
	})
	ui.badge = badge
	ui.badgeStroke = badgeStroke

	-- A solid chip of the liquid's own colour, so the badge is identifiable at a
	-- glance without reading it — the same "navigate by colour, not by sign" trick
	-- the shop stalls use (build/Shops.luau).
	ui.chip = UIKit.panel(badge, {
		name = "Chip",
		size = UDim2.fromOffset(14, 14),
		position = UDim2.new(0, 12, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
		color = UIKit.C.text,
		transparency = 0,
		cornerRadius = UIKit.Radius.pill,
		strokeThickness = UIKit.Stroke.thin,
		zIndex = 4,
	})

	ui.badgeName = UIKit.label(badge, {
		name = "NameLabel",
		size = UDim2.new(1, -100, 1, 0),
		position = UDim2.fromOffset(34, 0),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.text,
		strokeTransparency = 0,
		text = "Plain Water",
		zIndex = 4,
	})

	ui.badgeCharges = UIKit.label(badge, {
		name = "Charges",
		size = UDim2.new(0, 60, 1, 0),
		position = UDim2.new(1, -72, 0, 0),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Right,
		strokeTransparency = 0,
		text = "\u{221E}",
		zIndex = 4,
	})

	-- ── The reveal ───────────────────────────────────────────────────
	-- Same true-centre, upper-third placement as DetectorController's unearth
	-- banner. The two can never be on screen together (one fires at a wash pad on
	-- your own base, the other out in a stage) so sharing the spot is free, and
	-- sharing it means "something good just happened" always appears in one place.
	local card, cardStroke = UIKit.panel(gui, {
		name = "Reveal",
		size = UDim2.fromOffset(560, 176),
		position = UDim2.fromScale(0.5, 0.32),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UIKit.C.panel,
		transparency = 0.1,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		visible = false,
		zIndex = 5,
	})
	ui.reveal = card
	ui.revealStroke = cardStroke

	ui.revealKicker = UIKit.label(card, {
		name = "Kicker",
		position = UDim2.fromOffset(0, 14),
		size = UDim2.new(1, 0, 0, 20),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 6,
	})

	ui.revealName = UIKit.label(card, {
		name = "NameLabel",
		position = UDim2.fromOffset(0, 38),
		size = UDim2.new(1, 0, 0, 50),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero - 6,
		xAlign = Enum.TextXAlignment.Center,
		strokeTransparency = 0,
		zIndex = 6,
	})

	ui.revealStats = UIKit.label(card, {
		name = "Stats",
		position = UDim2.fromOffset(0, 92),
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 6,
	})

	ui.revealFlavor = UIKit.label(card, {
		name = "Flavor",
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 120),
		size = UDim2.new(1, -48, 0, 44),
		font = UIKit.Font.body,
		textSize = 16,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		zIndex = 6,
	})

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

--- "+2 potency  x3.2 speed  x1.5 XP  8 cleans" — only the parts that are actually
--- doing something. Plain Water's row would otherwise read "+0 potency x1 speed x1
--- XP", three statements of nothing, which is a worse way to say "this is the floor"
--- than saying nothing at all.
local function statLine(def): string
	local parts = {}
	if def.potency > 0 then
		table.insert(parts, `+{def.potency} potency`)
	end
	if def.rateMult ~= 1 then
		table.insert(parts, string.format("%.2gx speed", def.rateMult))
	end
	if def.xpMult ~= 1 then
		table.insert(parts, string.format("%.2gx XP", def.xpMult))
	end
	if def.charges > 0 then
		table.insert(parts, `{def.charges} cleans`)
	end
	return table.concat(parts, "   ")
end

local function paintBadge(view)
	local def = Liquids.get(view.equipped)
	local colour = Color3.fromHex(def.color)

	ui.chip.BackgroundColor3 = colour
	ui.badgeName.Text = def.name
	ui.badgeStroke.Color = colour

	-- The infinity sign is the whole point of Plain Water, so it gets the symbol
	-- rather than a number: a badge reading "0 left" over the one liquid that can
	-- never run out would teach exactly the wrong thing.
	if view.equipped == Liquids.WATER then
		ui.badgeCharges.Text = "\u{221E}"
		ui.badgeCharges.TextColor3 = UIKit.C.dim
	else
		local left = view.liquidCharges or 0
		ui.badgeCharges.Text = `{left} left`
		ui.badgeCharges.TextColor3 = if left <= 3 then UIKit.C.amber else UIKit.C.dim
	end
end

-- ── The reveal ──────────────────────────────────────────────────────

local function paintReveal(id: string, kicker: string)
	local def = Liquids.get(id)
	local colour = Color3.fromHex(def.color)

	ui.revealKicker.Text = kicker
	ui.revealName.Text = def.name
	ui.revealName.TextColor3 = colour
	ui.revealStats.Text = statLine(def)
	ui.revealStats.TextColor3 = colour
	ui.revealFlavor.Text = def.flavor
	ui.revealStroke.Color = colour
end

--- The spin. Cycles rollable names on a fixed interval, then lands on what the
--- server already decided. `token` is the cancellation: a second roll landing mid-
--- spin (possible only if Tuning.LIQUID_ROLL_COOLDOWN is ever cut below
--- SPIN_SECONDS) abandons this one rather than leaving two coroutines fighting over
--- the same labels.
local function reveal(rolled)
	revealToken += 1
	local token = revealToken

	ui.reveal.Visible = true

	task.spawn(function()
		local elapsed = 0
		local index = 0
		while elapsed < SPIN_SECONDS do
			if token ~= revealToken then
				return
			end
			index += 1
			paintReveal(ROLLABLE[(index % #ROLLABLE) + 1], "\u{2026}")
			task.wait(SPIN_INTERVAL)
			elapsed += SPIN_INTERVAL
		end

		if token ~= revealToken then
			return
		end

		local kicker = if rolled.equipped then "LOADED INTO THE HOSE" else `x{rolled.held} in the shed`
		paintReveal(rolled.id, kicker)

		task.wait(HOLD_SECONDS)
		if token == revealToken then
			ui.reveal.Visible = false
		end
	end)
end

-- ── Lifecycle ────────────────────────────────────────────────────────

function Liquid.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("LiquidState").OnClientEvent:Connect(function(view)
		if type(view) ~= "table" then
			return
		end
		-- The badge wants the charge count of the LOADED liquid specifically, which
		-- the shelf carries per-entry. Flattened here rather than added to the
		-- payload: LiquidService.viewFor is also the roll panel's data source, and
		-- that panel needs the whole shelf anyway.
		local charges = 0
		for _, entry in view.liquids or {} do
			if entry.id == view.equipped then
				charges = entry.held
				break
			end
		end
		view.liquidCharges = charges
		paintBadge(view)
	end)

	Net.get("LiquidRoll").OnClientEvent:Connect(function(rolled)
		if type(rolled) ~= "table" or type(rolled.id) ~= "string" then
			return
		end
		reveal(rolled)
	end)
end

return Liquid
