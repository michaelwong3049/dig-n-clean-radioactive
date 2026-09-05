--!strict
--[[
	ExhibitService.lua — the second exit for an item, and the one that keeps paying.

	AN ITEM YOU SELL IS GONE. AN ITEM YOU DISPLAY KEEPS PAYING (PLAN §8). Everything
	this file needs was already sitting in the codebase waiting for a service to
	read it: the profile schema (`data.exhibit`), every tuning number
	(`Tuning.EXHIBIT_*`), the world contract (`Plots.luau`'s Stand
	attributes), and even the multiplier hook (`StatResolver.yieldMultiplier`,
	wired to the Curator perk before this file existed to use it). This is the
	service that plugs all of that together.

	PLOTS ARE ASSIGNED, NOT OWNED. Per-session only, exactly as `Plots.luau`'s own
	header promised: "a player's plot contents persist; their plot number is
	meaningless across servers." `data.exhibit.pedestals` is the persistent part;
	`plotOf` here is a runtime map that gets rebuilt every time someone joins. A
	returning player may land on a different physical plot and see their own
	collection re-rendered onto it.

	THE SLOT ARRAY MUST STAY DENSE. ProfileStore forbids gaps in numeric arrays
	(DataService's own comment), so `pedestals` is `{ {slot=1,...}, {slot=3,...} }`
	with a `slot` field on each entry, not a sparse table indexed BY slot. Undisplay
	removes the entry (`table.remove`); it never sets one to nil.

	THE HOURLY CAP IS APPROXIMATED, NOT TRACKED. PLAN §8.7 wants income "capped per
	real-time hour" so an early lucky Legendary cannot fund the whole midgame while
	AFK. A true rolling-window tracker is more bookkeeping than the number is worth
	right now, so the cap is applied by clamping the RATE itself
	(`Tuning.EXHIBIT_HOURLY_CAP_PER_LEVEL * level` per hour, converted to per
	second) — cheaper, and the player-facing result is identical: money never
	arrives faster than the cap allows, online or offline.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)
local Gear = require(Shared.Config.Gear) -- renderLuck: the plot's luck-button billboard
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Weight = require(Shared.Config.Weight)
local ItemModels = require(Shared.ItemModels)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

-- THE ONE build/ REQUIRE IN THIS FILE, and it is the same shape as DigService's
-- require of build/SignalAura: a service that has to change world geometry asks the
-- module that built that geometry to change it, rather than learning the geometry's
-- shape for itself. `PLOT_COUNT` below is deliberately NOT taken from here — a
-- constant is worth copying to avoid a dependency; a builder is not worth
-- reimplementing to avoid one.
local Plots = require(script.Parent.Parent.build.Plots)

local ExhibitService = {}

local PLOT_COUNT = 6 -- matches build/Plots.Plots.COUNT; not required so Services never depend on build/
local LOCKER_VISIBLE = 3 -- matches build/Plots.Plots.LOCKER_SLOTS; overflow racked items just aren't shown
local LOCKER_ITEM_SIZE = 1.2 -- longest axis a racked item model is scaled to; the cabinet bays are cramped

-- Who is sitting on which physical plot this session. Never persisted — see header.
local plotOf: { [Player]: number } = {}
local plotOwner: { [number]: Player? } = {}

local resultRemote: any = nil

-- ── Rendering ─────────────────────────────────────────────────────────────────
-- The only place this file touches Workspace directly. Kept small and separate so
-- the rest of the service can be reasoned about as pure data manipulation.

local function plotModel(index: number): Model?
	local row = Workspace:FindFirstChild("Plots")
	if row == nil then
		return nil
	end
	return row:FindFirstChild(`Plot{index}`) :: Model?
end

--- Repaint one plot's name sign. Empty name clears it back to "UNCLAIMED".
local function renderName(index: number, displayName: string?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local sign = plot:FindFirstChild("NameSign", true)
	local gui = sign and sign:FindFirstChildWhichIsA("SurfaceGui")
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
	if label then
		(label :: TextLabel).Text = if displayName and displayName ~= "" then string.upper(displayName) else "UNCLAIMED"
	end
end

--- Repaint one plot's luck button to the given profile's current multiplier and the
--- price of the NEXT purchase, or to the starting values when `data` is nil (an
--- unclaimed plot). The Sign/Title/Subtitle names match build/Plots.buildLuckButton
--- exactly, the same convention LiquidService.announce uses to name a roll on the
--- wash pad. Title carries the multiplier, Subtitle the price — Luck has no tier
--- name left to put in Title's place now that a purchase is a flat +0.1x.
local function renderLuck(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local luckButton = plot:FindFirstChild("LuckButton", true)
	local button = luckButton and luckButton:FindFirstChild("Button")
	local sign = button and button:FindFirstChild("Sign")
	local title = sign and sign:FindFirstChild("Title")
	local subtitle = sign and sign:FindFirstChild("Subtitle")
	local level = if data then (data.gear.luck or 1) else 1
	if title then
		(title :: TextLabel).Text = string.format("LUCK %.1fx", Gear.luckMultiplier(level))
	end
	if subtitle then
		(subtitle :: TextLabel).Text = string.format("+0.1x for $%d", Gear.luckPrice(level))
	end
end

--- Put the Cleaner rung this profile owns on the plot's wash machine, or the
--- unclaimed-plot default when `data` is nil.
---
--- THIS IS THE WHOLE POINT OF THE CLEANER TRACK BEING A MACHINE. You buy a hose at the
--- plaza's HOSES stall like every other track, and this is what makes that purchase
--- something you can walk up to and look at: the monitor on your own mast is the rung
--- you paid for, and it changes the moment the money leaves (ShopService calls
--- refreshHose) rather than at the next rebuild.
---
--- SAME SHAPE AS renderLuck, and for the same reason it lives here rather than in
--- ShopService: this file owns what a plot LOOKS like for its owner, and the buy path
--- should not have to know that a plot has a cleansing station in it, let alone that
--- the station has a mast.
local function renderHose(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	-- Recursive: the station is a Model inside the plot, and its own name is the only
	-- thing this file knows about it. Everything past that name — where the mast is,
	-- which Beam runs to which attachment — is build/Plots' business.
	local station = plot:FindFirstChild("CleansingStation", true)
	Plots.setHoseTier(station, if data then data.gear.cleaner else nil)
end

--- The world half of "hold the item, hold E on the stand": a plain default-styled
--- ProximityPrompt (small white ActionText, same as the wash tub's own "Wash"
--- prompt — see WashService/build/Plots' `buildCleansingStation`), built once per
--- stand and reused after that, same lazy-build-then-toggle shape `setStandTag`
--- already uses below for the yield tag. There is no panel any more for either
--- verb — placing and taking an item back are both a prompt on the stand itself.
---
--- WHICH STAND IS ACTUALLY TARGETED IS NEVER A PROMPT'S IDENTITY. `Triggered` only
--- means "this player pressed a key near a stand right now" — `action` (`display`
--- or `undisplay`) re-derives the real stand itself, so a prompt is never wrong
--- even if two stands' prompts are close enough to both be in range.
---
--- PLACE AND TAKE CAN BOTH BE ENABLED AT ONCE (a swap: something is already on
--- the stand and you are holding something else), which is exactly the case a
--- shared keyboard key cannot resolve — two enabled ProximityPrompts on the same
--- part with the same KeyboardKeyCode silently pick ONE of them and the other
--- keypress goes nowhere, confirmed live (pressing E fired only the wrong one of
--- the pair; giving Take its own key fixed it instantly). Hence `keyCode`.
local function ensurePrompt(stand: BasePart, name: string, actionText: string, keyCode: Enum.KeyCode, action: (Player) -> (boolean, string)): ProximityPrompt
	local existing = stand:FindFirstChild(name)
	if existing and existing:IsA("ProximityPrompt") then
		return existing
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = keyCode
	prompt.HoldDuration = Tuning.EXHIBIT_STAND_HOLD_SECONDS
	prompt.MaxActivationDistance = (stand:GetAttribute("Radius") :: number?) or 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	prompt.Triggered:Connect(function(player: Player)
		local ok, message = action(player)
		if resultRemote then
			resultRemote:FireClient(player, message)
		end
		if ok then
			print(`[exhibit] {player.Name}: {message}`)
		end
	end)

	return prompt
end

--- Repaint one stand with real item art when it exists, or the old rarity-coloured
--- block while that catalogue entry is still waiting for a model.
local function renderStand(index: number, slot: number, itemId: string?, rarity: string?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end

	-- PLACE STAYS ENABLED EVEN WHEN OCCUPIED, ON PURPOSE — that is what makes a
	-- swap reachable at all (hold something, press E on an occupied stand, `display`
	-- pulls the old item into your bag and puts the held one up in its place). If
	-- you press it with nothing held, `display` refuses with "hold something
	-- first" exactly like it always has; there is no swap-specific gate to add.
	--
	-- TAKE only makes sense at all once something is here, unlike ownership (which
	-- neither prompt attempts to gate: a non-owner who presses one gets refused by
	-- `display`/`undisplay` itself, same as pressing Wash on someone else's tub
	-- costs nothing to attempt and fails cleanly).
	local stand = plot:FindFirstChild(`Stand{slot}`, true) :: BasePart?
	if stand then
		ensurePrompt(stand, "Place", "Place", Enum.KeyCode.E, ExhibitService.display).Enabled = true
		ensurePrompt(stand, "Take", "Take", Enum.KeyCode.F, ExhibitService.undisplay).Enabled = itemId ~= nil
	end

	local display = plot:FindFirstChild(`Display{slot}`, true) :: BasePart?
	if display == nil then
		return
	end

	local previous = display:FindFirstChild("ItemModel")
	if previous then
		previous:Destroy()
	end

	local model: Model? = nil
	if itemId then
		local item = Items.get(itemId)
		model = ItemModels.create(item.model)
	end

	if model then
		display.Transparency = 1
		model.Name = "ItemModel"
		model:SetAttribute("ItemId", itemId)
		model.Parent = display
		model:PivotTo(
			display.CFrame
				* CFrame.new(0, -0.72, 0)
				* ItemModels.rotation(model, "Display")
		)
	elseif rarity then
		display.Color = Rarity.get(rarity).color
		display.Transparency = 0
	else
		display.Transparency = 1
	end
end

-- ── The playful "name / rarity / $-per-second" card over a displayed item ─────
-- A world billboard on each occupied stand: the item's NAME, its RARITY above it in
-- the rarity colour, and what the piece PAYS PER SECOND in a rounded pill. Built at
-- runtime rather than in build/Plots for the same reason renderName and renderLuck
-- rewrite their build-time shells instead of the geometry carrying the text -- it is
-- all per-player content (the item, its roll modifier, the owner's Curator perk, and
-- how many copies share the plot all move the number).

local YIELD_TAG = "YieldTag"
-- Chunky and rounded, the toy-shop voice PLAN §14 asks for. The world's fixed
-- signage (Kit.FONT -- cleansing station, wash pad, shop marquees, nameplates) is
-- kept on this same face on purpose; re-voicing means changing both.
local TAG_FONT = Enum.Font.FredokaOne
local RATE_COLOR = Color3.fromHex("F59E0B") -- the cash badge's amber (UIKit.C.amber)
local PILL_COLOR = Color3.fromRGB(24, 20, 32)

--- One displayed item's contribution to the plot's per-second yield. `damping` comes
--- from the caller because it depends on how many EARLIER pedestals share the item id
--- (Tuning.EXHIBIT_DUPLICATE_YIELD). Per-minute in the design doc, per-second here
--- like everything else in this codebase. Shared by rawRatePerSecond (which sums it,
--- then the hourly cap clamps the total) and refreshYieldTags (which prints it on the
--- plinth), so a plinth's label can never disagree with what it pays into the wallet.
local function entryYieldPerSecond(entry: any, damping: number, stats: any): number
	local def = Items.get(entry.itemId)
	local rarity = Rarity.get(entry.rarity)
	local mod = Rarity.MODIFIERS[entry.modifier] or Rarity.MODIFIERS.None
	-- Weight.valueMult layers in here exactly as it does in EconomyService.valueOf, so
	-- a heavy piece pays more per second AND sells for more, off one factor.
	return def.baseValue
		* mod.valueMult
		* Weight.valueMult(def.weight)
		* rarity.displayYield
		* damping
		* stats.yieldMultiplier
		/ 60
end

--- "$2.00/s", "$51.3/s", "$173/s", "$2.5K/s" -- same abbreviation ladder the cash
--- badge uses (CashController.formatCash), so a rate and a balance read as one currency.
local function formatRate(perSecond: number): string
	if perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("$%.1f/s", perSecond)
	end
	return string.format("$%.2f/s", perSecond)
end

--- Lay the card out once on a Display part. Everything item-specific (the text, the
--- rarity colour) is filled in by setStandTag afterwards; this only builds the pieces.
---
--- FIXED TextSize on every label, never TextScaled -- exactly the Kit.billboard
--- convention every other sign in the world follows. TextScaled sized each card's
--- name by its own length (a short name ballooned, a long one shrank), and on an
--- offset BillboardGui -- whose AbsoluteSize is a constant pixel size at ANY camera
--- distance -- that read as the label resizing itself as you moved the camera. A flat
--- TextSize is the same on every card and at every zoom; TextWrapped still lets a
--- long name run onto a second line without changing the glyph size.
local function buildTag(display: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = YIELD_TAG
	gui.Size = UDim2.fromOffset(280, 116)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0 -- same wash-to-white bug Kit.billboard documents
	-- MaxDistance is CAMERA-to-adornee, not character-to-adornee, and a third-person
	-- camera sits ~28 studs back -- 120 covers every stand on your own ~66x52 pad from
	-- any standing spot while stopping short of the next plot on the 180-radius ring.
	gui.MaxDistance = 120

	local rarity = Instance.new("TextLabel")
	rarity.Name = "Rarity"
	rarity.Size = UDim2.new(1, 0, 0, 20)
	rarity.BackgroundTransparency = 1
	rarity.Font = TAG_FONT
	rarity.TextSize = 16
	rarity.TextStrokeColor3 = Color3.new(0, 0, 0)
	rarity.TextStrokeTransparency = 0
	rarity.Parent = gui

	local name = Instance.new("TextLabel")
	name.Name = "ItemName"
	name.Position = UDim2.fromOffset(0, 20)
	name.Size = UDim2.new(1, 0, 0, 52)
	name.BackgroundTransparency = 1
	name.Font = TAG_FONT
	name.TextSize = 23
	name.TextWrapped = true
	name.TextStrokeColor3 = Color3.new(0, 0, 0)
	name.TextStrokeTransparency = 0
	name.Parent = gui

	local pill = Instance.new("Frame")
	pill.Name = "RatePill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 80)
	pill.Size = UDim2.fromOffset(132, 28)
	pill.BackgroundColor3 = PILL_COLOR
	pill.BackgroundTransparency = 0.2
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill

	local rate = Instance.new("TextLabel")
	rate.Name = "Rate"
	rate.Size = UDim2.fromScale(1, 1)
	rate.BackgroundTransparency = 1
	rate.Font = TAG_FONT
	rate.TextSize = 17
	rate.TextColor3 = RATE_COLOR
	rate.Parent = pill

	gui.Parent = display
	return gui
end

--- Point the card at one item, or hide it (`info == nil`: an empty stand, or a
--- released plot). The gui persists on the part once built and is just toggled --
--- cheaper than churning an instance every display/undisplay, and it can't be left
--- orphaned on a cleared slot.
local function setStandTag(display: BasePart, info: { name: string, rarity: string, rate: number }?)
	local gui = display:FindFirstChild(YIELD_TAG) :: BillboardGui?
	if info == nil then
		if gui then
			gui.Enabled = false
		end
		return
	end
	gui = gui or buildTag(display)
	gui.Enabled = true

	local rarityColor = Rarity.get(info.rarity).color

	local rarityLabel = gui:FindFirstChild("Rarity") :: TextLabel
	rarityLabel.Text = string.upper(info.rarity)
	rarityLabel.TextColor3 = rarityColor

	local nameLabel = gui:FindFirstChild("ItemName") :: TextLabel
	nameLabel.Text = info.name
	-- Mostly white, washed toward the rarity colour, so the card reads as "this tier"
	-- from further out than the word above it is legible.
	nameLabel.TextColor3 = rarityColor:Lerp(Color3.new(1, 1, 1), 0.72)

	local pill = gui:FindFirstChild("RatePill") :: Frame
	;(pill:FindFirstChild("Rate") :: TextLabel).Text = formatRate(info.rate)
end

--- Redraw every stand's "$X/s" tag on one plot from the profile: hide them all, then
--- light the occupied ones -- the same shape as renderAll. It walks `pedestals` in the
--- same order rawRatePerSecond does, so the damping baked into each tag matches the
--- damping that entry is actually paid at (a wall of one repeated Legendary visibly
--- shows its 4th copy paying almost nothing). `data == nil` hides all of them.
local function refreshYieldTags(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end

	for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
		local display = plot:FindFirstChild(`Display{slot}`, true) :: BasePart?
		if display then
			setStandTag(display, nil)
		end
	end
	if data == nil then
		return
	end

	local stats = StatResolver.get(data)
	local seen: { [string]: number } = {}
	for _, entry in data.exhibit.pedestals do
		local copyIndex = (seen[entry.itemId] or 0) + 1
		seen[entry.itemId] = copyIndex
		local damping = Tuning.EXHIBIT_DUPLICATE_YIELD[math.min(copyIndex, #Tuning.EXHIBIT_DUPLICATE_YIELD)]

		local display = plot:FindFirstChild(`Display{entry.slot}`, true) :: BasePart?
		if display then
			setStandTag(display, {
				name = Items.get(entry.itemId).name,
				rarity = entry.rarity,
				rate = entryYieldPerSecond(entry, damping, stats),
			})
		end
	end
end

--- Fill one plot's Quarantine Locker (build/Plots.buildQuarantineLocker) from
--- `data.locker`, and swing its door: open the moment anything is racked, shut
--- when the last item leaves. `data == nil` clears it — used on release.
---
--- The locker has no station of its own; racking still happens at the cleansing
--- station. This only mirrors the profile's `locker` array onto the cabinet the
--- same way renderStand mirrors `exhibit.pedestals` onto the plinths.
local function renderLocker(index: number, data: any)
	local plot = plotModel(index)
	if plot == nil then
		return
	end

	local locker = if data ~= nil then data.locker else {}

	local door = plot:FindFirstChild("LockerDoor", true) :: Model?
	if door then
		local pivot = door:GetAttribute(if #locker > 0 then "OpenPivot" else "ClosedPivot")
		if typeof(pivot) == "CFrame" then
			door:PivotTo(pivot)
		end
	end

	for i = 1, LOCKER_VISIBLE do
		local anchor = plot:FindFirstChild(`LockerSlot{i}`, true) :: BasePart?
		if anchor then
			local previous = anchor:FindFirstChild("ItemModel")
			if previous then
				previous:Destroy()
			end

			local entry = locker[i]
			if entry == nil then
				anchor.Transparency = 1
			else
				local model = ItemModels.create(Items.get(entry.itemId).model)
				if model then
					anchor.Transparency = 1
					model.Name = "ItemModel"
					model:SetAttribute("ItemId", entry.itemId)
					model.Parent = anchor

					-- The bays are ~1.5 studs tall; normalise every model to a common
					-- longest-axis size (unlike the pedestals, which show items life-ish
					-- size on an open plinth) and seat it on the bay floor.
					model:PivotTo(CFrame.identity)
					local extents = model:GetExtentsSize()
					local longest = math.max(extents.X, extents.Y, extents.Z)
					if longest > 0 then
						model:ScaleTo(LOCKER_ITEM_SIZE / longest)
					end
					model:PivotTo(anchor.CFrame * ItemModels.rotation(model, "Display"))
					local bounds, size = model:GetBoundingBox()
					local floorY = anchor.Position.Y - anchor.Size.Y / 2
					model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (bounds.Position.Y - size.Y / 2) + 0.03, 0))
				else
					anchor.Color = Rarity.get(entry.rarity).color
					anchor.Transparency = 0
				end
			end
		end
	end
end

--- Redraw everything on a plot from the profile — called once on assignment so a
--- returning player's collection shows up on whichever physical plot they land on.
local function renderAll(index: number, data: any)
	local owner = plotOwner[index]
	renderName(index, if owner then owner.DisplayName else nil)
	renderLuck(index, data)
	for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
		renderStand(index, slot, nil, nil)
	end
	for _, entry in data.exhibit.pedestals do
		renderStand(index, entry.slot, entry.itemId, entry.rarity)
	end
	renderLocker(index, data)
	renderHose(index, data)
	refreshYieldTags(index, data)
end

-- ── Spawning ──────────────────────────────────────────────────────────────────
--
-- BaseCamp no longer carries a spawn of its own (see BaseCamp.luau) — every
-- player's character has to land on their own assigned PlotSpawn instead, and
-- setting player.RespawnLocation alone is not enough for that: it only takes
-- effect on the player's NEXT respawn, and by the time assign() runs (after
-- DataService's async load) the player's character has usually already spawned
-- once, at Roblox's undefined "no enabled SpawnLocation yet" fallback position.
-- This moves that already-existing character over explicitly, the one time it
-- matters — every respawn after this one is already correctly routed by
-- RespawnLocation on its own.

--- Move `player`'s current character onto `spawn`, waiting for the character to
--- exist first if this somehow runs before it does (should not happen in
--- practice — CharacterAutoLoads fires immediately on join, well before a
--- profile finishes loading — but a spawn point silently doing nothing is a
--- much worse failure than a few seconds of extra caution here).
local function teleportToSpawn(player: Player, spawn: SpawnLocation)
	local character = player.Character
	if character == nil then
		local connection
		connection = player.CharacterAdded:Connect(function(newCharacter)
			connection:Disconnect()
			local root = newCharacter:WaitForChild("HumanoidRootPart", 5)
			if root then
				root.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
			end
		end)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
	end
end

-- ── Plot assignment ──────────────────────────────────────────────────────────

function ExhibitService.plotOf(player: Player): number?
	return plotOf[player]
end

--- Repaint a player's own luck button to their current multiplier. Called by
--- ShopService right after a Luck purchase lands, since the button's billboard is
--- world state ExhibitService already owns (the same object `assign` repaints for a
--- brand-new owner) rather than something ShopService should learn to poke into.
function ExhibitService.refreshLuck(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	renderLuck(index, DataService.data(player))
end

--- Swap this player's own wash machine to the Cleaner rung they now own. Called by
--- ShopService the moment a purchase on that track lands, for exactly the reason
--- refreshLuck exists: the world state a purchase changes belongs to the service that
--- owns plot rendering, not to the one that took the money. No-op if they have no plot
--- this session (all six taken — see assign()'s trailing warn).
function ExhibitService.refreshHose(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	renderHose(index, DataService.data(player))
end

--- This player's assigned plot's spawn pad, or nil if they never got a plot this
--- session (all six taken — see assign()'s trailing warn). assign() and release()
--- already resolve this exact part this exact way; the top-of-screen warp bar's
--- "BASE" button (WarpService) is the fourth reader, so the lookup lives here in the
--- service that owns plot assignment rather than being reached for by string path
--- from outside.
function ExhibitService.plotSpawn(player: Player): SpawnLocation?
	local index = plotOf[player]
	if index == nil then
		return nil
	end
	local plot = plotModel(index)
	if plot == nil then
		return nil
	end
	return plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
end

--- Re-mirror `data.locker` onto this player's plot cabinet. Called by DeconService
--- after a rack or a (dirty-)sell, since those are the only two things that move
--- an item in or out of the locker. No-op if the player has no plot this session.
function ExhibitService.refreshLocker(player: Player)
	local index = plotOf[player]
	local data = DataService.data(player)
	if index ~= nil and data ~= nil then
		renderLocker(index, data)
	end
end

local function assign(player: Player)
	for index = 1, PLOT_COUNT do
		if plotOwner[index] == nil then
			plotOwner[index] = player
			plotOf[player] = index

			local plot = plotModel(index)
			if plot then
				local spawn = plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
				if spawn then
					spawn.Enabled = true
					player.RespawnLocation = spawn
					teleportToSpawn(player, spawn)
				end
			end

			local data = DataService.data(player)
			if data then
				renderAll(index, data)
			end
			return
		end
	end
	-- All 6 plots taken (should not happen with MaxPlayers = 6, but a place
	-- setting is not something this code can enforce). Used to mean only "nowhere
	-- to display"; now that BaseCamp carries no fallback spawn, it also means this
	-- player never gets a RespawnLocation or a teleport, and is stuck wherever
	-- their character's initial undefined-position spawn happened to land. Selling
	-- and upgrading still work regardless.
	warn(`[exhibit] no free plot for {player.Name} — all {PLOT_COUNT} are taken, and they have nowhere to spawn`)
end

local function release(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	plotOf[player] = nil
	plotOwner[index] = nil

	local plot = plotModel(index)
	if plot then
		local spawn = plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
		if spawn then
			spawn.Enabled = false
		end
		renderName(index, nil)
		renderLuck(index, nil)
		renderHose(index, nil)
		for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
			renderStand(index, slot, nil, nil)
		end
		renderLocker(index, nil)
		refreshYieldTags(index, nil)
	end
end

-- ── Yield ─────────────────────────────────────────────────────────────────────

--- Dollars per second this profile's exhibit is currently worth, BEFORE the
--- hourly cap. Duplicate damping (Tuning.EXHIBIT_DUPLICATE_YIELD) keys off how
--- many other displayed pieces share the same item id, so breadth beats depth —
--- one of everything outperforms four of a single Legendary. Per-entry math is
--- entryYieldPerSecond (also what the plinth billboards print), so the two agree.
local function rawRatePerSecond(data: any, stats: any): number
	local seen: { [string]: number } = {}
	local total = 0

	for _, entry in data.exhibit.pedestals do
		local copyIndex = (seen[entry.itemId] or 0) + 1
		seen[entry.itemId] = copyIndex
		local damping = Tuning.EXHIBIT_DUPLICATE_YIELD[math.min(copyIndex, #Tuning.EXHIBIT_DUPLICATE_YIELD)]
		total += entryYieldPerSecond(entry, damping, stats)
	end

	return total
end

--- The rate, WITH the hourly cap applied. See the header for why this is a clamp
--- on the rate rather than a tracked rolling window.
local function cappedRatePerSecond(data: any, stats: any): number
	local raw = rawRatePerSecond(data, stats)
	local cap = (Tuning.EXHIBIT_HOURLY_CAP_PER_LEVEL * math.max(1, data.level)) / 3600
	return math.min(raw, cap)
end

--- Called once, right after a profile loads. Credits time spent offline into
--- bankedCash; start()'s loaded hook then calls deposit() straight away, so the
--- offline haul just lands in the wallet on login rather than waiting to be
--- collected. Still capped at EXHIBIT_OFFLINE_BANK_HOURS.
local function bankOffline(data: any)
	local now = os.time()
	if data.exhibit.bankedAt <= 0 then
		data.exhibit.bankedAt = now
		return
	end

	local elapsed = math.clamp(now - data.exhibit.bankedAt, 0, Tuning.EXHIBIT_OFFLINE_BANK_HOURS * 3600)
	if elapsed <= 0 then
		data.exhibit.bankedAt = now
		return
	end

	local stats = StatResolver.get(data)
	local rate = cappedRatePerSecond(data, stats)
	local credit = rate * elapsed * Tuning.EXHIBIT_OFFLINE_RATE
	if credit > 0 then
		data.exhibit.bankedCash += math.floor(credit + 0.5)
	end
	data.exhibit.bankedAt = now
end

--- Whole dollars are swept from bankedCash into spendable cash on a slow cadence,
--- not every tick: CashController documents that CashState must never fire per-tick,
--- and passive income trickles slowly enough that a DEPOSIT_INTERVAL batch is
--- invisible to the player — the badge just counts up on its own.
local DEPOSIT_INTERVAL = 5
local sinceDeposit = 0

--- Move the whole-dollar part of this profile's accrued exhibit income into
--- spendable cash, leaving the sub-dollar remainder in bankedCash so nothing is
--- lost to flooring each deposit. EconomyService.award fires CashState itself.
local function deposit(player: Player, data: any)
	local whole = math.floor(data.exhibit.bankedCash)
	if whole >= 1 then
		data.exhibit.bankedCash -= whole
		EconomyService.award(player, whole)
	end
end

local function tickPlayer(player: Player, dt: number, flush: boolean)
	local data = DataService.data(player)
	if data == nil or #data.exhibit.pedestals == 0 then
		return
	end

	local stats = StatResolver.get(data)
	local rate = cappedRatePerSecond(data, stats)
	data.exhibit.bankedCash += rate * dt
	data.exhibit.bankedAt = os.time()

	if flush then
		deposit(player, data)
	end
end

-- ── Actions ───────────────────────────────────────────────────────────────────

--- Move the currently HELD item from the backpack onto the stand the player is
--- FACING. Both are derived server-side (facing exactly like ShopService derives
--- the track from where the player is standing) — never taken from the request.
---
--- IF SOMETHING IS ALREADY THERE, THIS SWAPS THEM: the occupant comes off into the
--- bag (exactly like `undisplay`, crating delay respected and all) and the held
--- item goes up in its place, in one step. There is no separate "swap" entry point
--- — pressing Place on an occupied stand while holding something IS the swap; the
--- "Place" ProximityPrompt stays enabled even when occupied for exactly this.
function ExhibitService.display(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local stationId = StationService.facedStation(player, "pedestal", Tuning.EXHIBIT_PLACE_FACING_ANGLE)
	if stationId == nil then
		return false, "you need to be facing one of your stands"
	end

	local plotIndex, slotStr = string.match(stationId, "^(%d+):(%d+)$")
	if plotIndex == nil then
		return false, "that stand didn't resolve"
	end
	local plot, slot = tonumber(plotIndex) :: number, tonumber(slotStr) :: number

	if plotOf[player] ~= plot then
		return false, "that isn't your plot"
	end
	if slot < 1 or slot > data.exhibit.slots then
		return false, "that stand doesn't exist"
	end

	if data.heldUid == "" then
		return false, "hold something first \u{2014} pick it from your bag"
	end
	local item, list, index = EconomyService.find(data, data.heldUid)
	if item == nil or list ~= data.carry or index == nil then
		return false, "you aren't carrying that"
	end
	if not Contamination.isClean(item.patches or {}) then
		return false, "clean it first"
	end
	if item.modifier == "Slagged" then
		return false, "slag can't be displayed"
	end

	-- Everything above is "is the thing in your HAND allowed up there at all" —
	-- unconditional. Everything below is "what, if anything, is already up there",
	-- which only changes what comes off, never whether the new item can go on.
	local occupiedIndex = nil
	for i, entry in data.exhibit.pedestals do
		if entry.slot == slot then
			occupiedIndex = i
			break
		end
	end

	local displaced: any = nil
	if occupiedIndex then
		local entry = data.exhibit.pedestals[occupiedIndex]
		local elapsed = os.time() - entry.placedAt
		if elapsed < Tuning.EXHIBIT_UNCRATE_SECONDS then
			return false, `still crating \u{2014} {Tuning.EXHIBIT_UNCRATE_SECONDS - elapsed}s left`
		end
		table.remove(data.exhibit.pedestals, occupiedIndex)
		displaced = entry
	end

	table.remove(data.carry, index)
	if displaced then
		-- Same shape `undisplay` gives a retrieved item: frozen, no patches, clock
		-- reset. It was already docked; coming off must not restart the decay clock.
		table.insert(data.carry, {
			uid = displaced.uid,
			itemId = displaced.itemId,
			rarity = displaced.rarity,
			modifier = displaced.modifier,
			elapsed = 0,
			frozen = true,
			patches = {},
		})
	end

	table.insert(data.exhibit.pedestals, {
		slot = slot,
		uid = item.uid,
		itemId = item.itemId,
		rarity = item.rarity,
		modifier = item.modifier,
		placedAt = os.time(),
	})

	renderStand(plot, slot, item.itemId, item.rarity)
	refreshYieldTags(plot, data)

	if displaced then
		return true, `swapped in {Items.get(item.itemId).name} \u{2014} {Items.get(displaced.itemId).name} back in your bag`
	end
	return true, `{Items.get(item.itemId).name} is on display`
end

--- Pull an item back off a stand into the backpack, frozen (it was already docked
--- — pulling it off must not restart the decay clock). Respects the crating delay.
function ExhibitService.undisplay(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local kind = StationService.kindOf(player)
	local stationId = StationService.idOf(player)
	if kind ~= "pedestal" or stationId == nil then
		return false, "you need to be at the stand"
	end

	local plotIndex, slotStr = string.match(stationId, "^(%d+):(%d+)$")
	if plotIndex == nil then
		return false, "that stand didn't resolve"
	end
	local plot, slot = tonumber(plotIndex) :: number, tonumber(slotStr) :: number

	if plotOf[player] ~= plot then
		return false, "that isn't your plot"
	end

	local entryIndex = nil
	for i, entry in data.exhibit.pedestals do
		if entry.slot == slot then
			entryIndex = i
			break
		end
	end
	if entryIndex == nil then
		return false, "nothing here"
	end

	local entry = data.exhibit.pedestals[entryIndex]
	local elapsed = os.time() - entry.placedAt
	if elapsed < Tuning.EXHIBIT_UNCRATE_SECONDS then
		return false, `still crating \u{2014} {Tuning.EXHIBIT_UNCRATE_SECONDS - elapsed}s left`
	end

	table.remove(data.exhibit.pedestals, entryIndex)
	table.insert(data.carry, {
		uid = entry.uid,
		itemId = entry.itemId,
		rarity = entry.rarity,
		modifier = entry.modifier,
		elapsed = 0,
		frozen = true,
		patches = {},
	})

	renderStand(plot, slot, nil, nil)
	refreshYieldTags(plot, data)
	return true, `{Items.get(entry.itemId).name} back in your bag`
end

-- ── Bootstrap ─────────────────────────────────────────────────────────────────

function ExhibitService.init()
	resultRemote = Net.get("StationResult")
end

function ExhibitService.start()
	DataService.onLoaded(function(player, data)
		-- Saves made before every stand was free stored a lower slot count (the old
		-- EXHIBIT_STARTING_SLOTS was 3, upgraded with cash). Bring anyone below the
		-- current count up to it; Reconcile can't, since the key already exists.
		if data.exhibit.slots < Tuning.EXHIBIT_MAX_SLOTS then
			data.exhibit.slots = Tuning.EXHIBIT_MAX_SLOTS
		end
		bankOffline(data)
		deposit(player, data)
		assign(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		release(player)
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		sinceDeposit += dt
		local flush = sinceDeposit >= DEPOSIT_INTERVAL
		if flush then
			sinceDeposit = 0
		end
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(tickPlayer, player, dt, flush)
			if not ok then
				warn(`[exhibit] tick failed for {player.Name}: {err}`)
			end
		end
	end, "ExhibitService")
end

return ExhibitService
