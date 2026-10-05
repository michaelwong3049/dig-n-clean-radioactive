--!strict
--[[
	TreadmillService.lua — the Speed grind. Stand on a belt, earn Speed, level up.

	SPEED IS A LIFETIME TOTAL (`data.speedPoints`). Every second on a belt adds that
	belt's rate; every walk-speed level has a Speed requirement (Config/Treadmill), and
	crossing one levels you up on the spot. Nothing is ever spent.

	THE BELT IS A PLACE, NOT A BUTTON. There is no "start training" action and no
	session to open: `StationService.onChanged` says the moment a player's feet land
	inside a `StationKind = "treadmill"` radius, and from then until they step off,
	the tick loop below banks Speed. That is the same arrival edge the old wash
	pad rolled on (and DeconService still docks on), minus the one-shot — the pad paid
	out once on the edge, this pays out continuously between two edges.

	NOBODY IS EVER ROOTED BY THIS, on purpose. DigService's haul lock and WashService's
	session both pin WalkSpeed to zero and both carry a written-down list of every path
	that could strand a player as a result. A treadmill has no such excuse: the player
	is meant to be able to walk away at any instant, most of them will be AFK while it
	runs, and "you cannot move" is a catastrophic state to leave someone in while they
	are not looking at the screen. So the belt never touches the character. Stepping
	off is walking off.

	YOUR OWN BELT ONLY. A base's treadmill trains, and sells rungs to, its owner alone
	(on request — it used to train anyone). StationService treats someone else's belt
	as no station at all, so stepping on it starts nothing, and onBuy only ever sells
	from the buyer's own sign. The cleansing station is gated the same way (WashService.begin).

	ACCESS IS FREE. It used to be bought (Treadmill.UNLOCK_PRICE, now 0) before any belt
	paid a player anything; on request every player now has it from the start, and
	older saves are unlocked on load (DataService.onLoaded below). The lock itself is
	kept for `/train lock`: a locked player earns on no belt, their own or anyone
	else's, and the sign's first press unlocks them (TreadmillService.buy).

	THE UPGRADE SIGN, NOT A PROMPT. A navy board beside the belt (build/Plots
	ensureUpgradeSign) with a red cash button and a purple Robux one, drawn and pressed
	on the client (TreadmillSignController), on request in place of the console's E
	prompt. The cash button is Net.TreadmillBuy, so unlike a ProximityPrompt nothing
	enforces range for us: onBuy checks the base is theirs and they are by its sign.
	The Robux button is a Developer Product per rung (Treadmill.PRODUCTS), granted
	through ProductService (grantRobuxRung).

	WHAT THE UPGRADE BUYS is `rate` — Speed per second (Config/Treadmill) — not Speed
	itself. Cash cannot buy a single level anywhere in this game; it can only buy a
	belt that converts your time into Speed faster. That is the entire
	reason the Boots track was retired — see Config/Treadmill's header — and it is the
	property to protect if anyone ever adds a gamepass here.

	THE SERVER OWNS THE CLOCK, as it does for the wash timer and the pull fuse. The
	client is told its Speed; it never reports training. There is no remote in
	this file that a client can send, which makes the whole feature unexploitable by
	construction rather than by validation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Tutorial = require(Shared.Config.Tutorial) -- the console is shut during the walkthrough
local Treadmill = require(Shared.Config.Treadmill)
local ShopProducts = require(Shared.Config.ShopProducts)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)
local ExhibitService = require(script.Parent.ExhibitService)
local ProductService = require(script.Parent.ProductService)

local TreadmillService = {}

local STATION_KIND = "treadmill"

--- How often a trainee's readout is re-sent while they run. The Speed total moves
--- every tick, but the client counts it up locally from `rate` between pushes (see
--- TreadmillController / SpeedController), so once a second is only a drift correction.
--- Edges — stepping on or off, a level-up, a new belt, loading in — always push at once.
local PUSH_INTERVAL = 1

local stateRemote: any = nil
local noticeRemote: any = nil

--- How far from its sign's board a press of the cash button still counts. The board
--- reads from across the strip, so this is generous; it only stops a press from the
--- other side of the map.
local SIGN_REACH = 30
--- One cash press per player per this many seconds: a double click buys one rung.
local BUY_COOLDOWN = 0.4
local lastBuy: { [Player]: number } = {}

--- Who is standing on a belt right now. Written only by the StationService edge, so
--- it cannot drift from what the world thinks — and read by the tick loop as its
--- entire work list, which is why an empty camp costs nothing per tick.
local training: { [Player]: boolean } = {}

--- When each trainee was last sent a readout (os.clock), for PUSH_INTERVAL.
local lastPush: { [Player]: number } = {}

-- ── The run on the spot ─────────────────────────────────────────────────────
--
-- PLAYED HERE, NOT ON THE CLIENT, so every player sees it. It used to be a local
-- track in TreadmillController, which only the runner could be relied on to see;
-- a track the server loads onto the character's Animator replicates to every
-- client, the runner included. Borrowed off the character's own `Animate` script
-- (its children exist server-side too), so it matches the rig and can't ship a
-- broken asset id. Decoration only: no rig, no animation, nothing breaks.

--- The run track per trainee, and the character it was loaded on: a respawn builds
--- a new Animator, so a track on the old one is dead and must not be reused.
local runTracks: { [Player]: { track: AnimationTrack, character: Model } } = {}

local function startRunning(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local held = runTracks[player]
	if held and held.character == character then
		held.track:Play(0.2)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animateScript = character:FindFirstChild("Animate")
	local source = animateScript and animateScript:FindFirstChild("run")
	local anim = source and source:FindFirstChildWhichIsA("Animation")
	if animator == nil or anim == nil then
		return
	end
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim :: Animation)
	end)
	if not ok or track == nil then
		return
	end
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = true
	track:Play(0.2)
	runTracks[player] = { track = track, character = character }
end

local function stopRunning(player: Player)
	local held = runTracks[player]
	if held then
		held.track:Stop(0.2)
	end
end

-- ── The readout ───────────────────────────────────────────────────────────

--- This player's Speed, as the client renders it: the HUD counter reads `points` and
--- `level`, the treadmill card reads the rest.
---
--- `rate` is what they would earn per second ON A BELT — reported even when they are
--- not standing on one, because what the card wants to show is "this is what going
--- back to the treadmill is worth". `training` says whether it is being paid now.
local function snapshot(player: Player, data: any)
	local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
	local points = data.speedPoints or 0
	local level, progress = Treadmill.levelFor(points)
	local nextTier = Treadmill.TIERS[tier + 1]
	-- The Runner mastery (Config/Masteries) speeds every belt, so the card's rates are
	-- the ones step() really pays.
	local stats = StatResolver.get(data)
	local trainingMult = stats.trainingMult
	return {
		points = points,
		level = level,
		walk = Treadmill.walkSpeedFor(level),
		-- The walk-speed picker's cap (0 = full speed). The HUD shows chosenWalk(walk, walkCap).
		walkCap = if type(data.walkCap) == "number" then data.walkCap else 0,
		-- Every walk-speed bonus as one fraction: the worn aura's and the Speed Potion's
		-- (StatResolver.walkBonus). The badge shows the chosen walk times (1 + this),
		-- which is what ExposureService really walks you at.
		auraSpeed = StatResolver.walkBonus(stats) - 1,
		-- The debug /speed pin, when set: the badge shows it in place of the chosen walk, with
		-- the aura bonus on top as for any speed (Lazy require: ExposureService reaches back here).
		override = require(script.Parent.ExposureService).speedOverrideOf(player),
		progress = progress,
		current = Treadmill.requirementFor(level),
		nextReq = Treadmill.requirementFor(level + 1),
		rate = Treadmill.rateFor(tier) * trainingMult,
		training = training[player] == true,
		tier = tier,
		tierName = Treadmill.tier(tier).name,
		nextCost = if nextTier then nextTier.price else nil,
		nextName = if nextTier then nextTier.name else nil,
		nextRate = if nextTier then nextTier.rate * trainingMult else nil,
		unlocked = data.treadmillUnlocked == true,
		unlockPrice = Treadmill.UNLOCK_PRICE,
		-- Owed the post-unlock walkthrough (TreadmillController)? Marked seen through
		-- DeconService's "tutorialSeen" allowlist, the same as the locker's.
		tutorial = data.treadmillUnlocked == true and table.find(data.tutorialsSeen or {}, "treadmill") == nil,
		-- Which base is theirs this session, so the walkthrough can find their machine.
		plot = ExhibitService.plotOf(player),
	}
end

local function push(player: Player)
	local data = DataService.data(player)
	if data == nil or stateRemote == nil then
		return
	end
	lastPush[player] = os.clock()
	stateRemote:FireClient(player, snapshot(player, data))
end

-- ── Training ──────────────────────────────────────────────────────────────

--- One tick of Speed for every player currently standing on a belt. The belt is
--- re-read every tick, so an upgrade bought mid-run pays from the next tick on.
---
--- There is no top level (Config/Treadmill): every level just costs more than the last.
local function step(dt: number)
	local now = os.clock()
	for player in training do
		local data = DataService.data(player)
		if data == nil or not data.treadmillUnlocked then
			continue
		end

		local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
		local banked = data.speedPoints or 0
		local before = Treadmill.levelFor(banked)
		data.speedPoints = banked + Treadmill.rateFor(tier) * StatResolver.get(data).trainingMult * dt
		local after = Treadmill.levelFor(data.speedPoints)

		if after > before then
			-- The only moment in this feature where walk speed changes. Pushed at once
			-- so the level-up lands on screen the same tick StatResolver starts
			-- reporting the faster walk.
			print(`[treadmill] {player.Name}: level {before} -> {after} (walk {Treadmill.walkSpeedFor(after)})`)
			push(player)
		elseif now - (lastPush[player] or 0) >= PUSH_INTERVAL then
			push(player)
		end
	end
end

--- Re-send this player's readout now. For DebugService's /train, which pokes
--- `speedPoints` directly and would otherwise leave the HUD a second stale.
function TreadmillService.refresh(player: Player)
	push(player)
end

-- ── Buying a rung ─────────────────────────────────────────────────────────

--- Upgrade this player's belt one rung. Same shape as ShopService.buyLuck: price the
--- rung they are on, debit FIRST, and only mutate the profile once the debit lands —
--- so a refused purchase leaves nothing half-applied to unwind.
---
--- NO PROXIMITY CHECK, and that is not an omission: this is only ever reached from a
--- ProximityPrompt.Triggered, which fires on the server with MaxActivationDistance
--- already enforced by the engine. ShopService.wireUpgrade's header sets out the same
--- reasoning at more length.
function TreadmillService.buy(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	-- THE FIRST PURCHASE IS ACCESS, not a belt. Until it is made no belt trains this
	-- player (see the StationService edge in start), so the console sells that first.
	if not data.treadmillUnlocked then
		local paid, reason = EconomyService.spend(player, Treadmill.UNLOCK_PRICE)
		if not paid then
			return false, reason
		end
		data.treadmillUnlocked = true
		ExhibitService.refreshTreadmill(player)
		-- Bought while already standing on a belt: start paying now, not on the next
		-- step-on, because the StationService edge has already fired.
		if StationService.kindOf(player) == STATION_KIND then
			training[player] = true
			startRunning(player)
		end
		push(player)
		return true, if Treadmill.UNLOCK_PRICE > 0
			then `Treadmill unlocked — step on the belt to train (paid {Treadmill.unlockPriceText()})`
			else "Treadmill unlocked — step on the belt to train"
	end

	local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
	local price = Treadmill.priceFor(tier)
	if price == nil then
		return false, `{Treadmill.tier(tier).name} is the last belt there is`
	end

	local paid, reason = EconomyService.spend(player, price)
	if not paid then
		return false, reason
	end

	data.treadmill = tier + 1
	local bought = Treadmill.tier(data.treadmill)
	ExhibitService.refreshTreadmill(player)
	push(player)
	return true, `{bought.name} installed — +{Treadmill.rateText(bought.rate)} Speed/s (paid {Treadmill.priceText(price)})`
end

--- A rung bought with Robux (Treadmill.PRODUCTS): rung `tier`, with nothing spent.
--- Runs inside ProductService's receipt step, so it only touches `data` and never
--- yields; the world and the readout follow in a deferred step. Already on that rung
--- or past it (bought for cash between the prompt and the receipt) still gets them
--- one rung up -- they paid for an upgrade -- unless there is none left.
local function grantRobuxRung(player: Player, data: any, tier: number)
	local current = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
	data.treadmillUnlocked = true
	data.treadmill = if current < tier then tier else math.min(current + 1, Treadmill.maxTier())
	local bought = Treadmill.tier(data.treadmill)
	task.defer(function()
		if player.Parent == nil then
			return
		end
		ExhibitService.refreshTreadmill(player)
		push(player)
		noticeRemote:FireClient(player, `{string.upper(bought.name)} INSTALLED`)
	end)
end

--- A Speed pack bought with Robux (ShopProducts.SPEED): raw Speed straight onto the
--- total. Same receipt rules as a rung: touch `data` only, push in a deferred step.
local function grantSpeedPack(player: Player, data: any, amount: number)
	data.speedPoints = (data.speedPoints or 0) + amount
	task.defer(function()
		if player.Parent == nil then
			return
		end
		push(player)
		noticeRemote:FireClient(player, `+{Treadmill.rateText(amount)} SPEED`)
	end)
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

--- The plot's upgrade sign board (build/Plots ensureUpgradeSign), or nil.
local function signBoard(index: number): BasePart?
	local row = Workspace:FindFirstChild("Plots")
	local plot = row and row:FindFirstChild(`Plot{index}`)
	local treadmill = plot and plot:FindFirstChild("Treadmill", true)
	local sign = treadmill and treadmill:FindFirstChild("UpgradeSign")
	local board = sign and sign:FindFirstChild("Board")
	return if board and board:IsA("BasePart") then board else nil
end

--- Net.TreadmillBuy: the sign's red cash button. Their own base only, standing by its
--- sign, not mid-tutorial (the walkthrough keeps the treadmill's purchase shut, as
--- Tutorial.promptOpen did for the old console prompt).
local function onBuy(player: Player)
	local now = os.clock()
	if now - (lastBuy[player] or 0) < BUY_COOLDOWN then
		return
	end
	lastBuy[player] = now

	if Tutorial.gated(player) then
		noticeRemote:FireClient(player, "FINISH THE TUTORIAL FIRST")
		return
	end
	local index = ExhibitService.plotOf(player)
	local board = if index then signBoard(index) else nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if board == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	if (root.Position - board.Position).Magnitude > SIGN_REACH then
		noticeRemote:FireClient(player, "WALK UP TO YOUR TREADMILL'S SIGN")
		return
	end

	local ok, message = TreadmillService.buy(player)
	noticeRemote:FireClient(player, string.upper(message))
	if ok then
		print(`[treadmill] {player.Name}: {message}`)
	end
end

--- The walk-speed picker (Net.WalkCap). A number is the walk to cap at; 0, or anything
--- at or over what they have trained, saves as 0 = "always full speed", so the next
--- level they earn is felt at once instead of being held back by an old pick. Always
--- pushes back, so a refused pick snaps the client's slider to what actually stuck.
local PICK_COOLDOWN = 0.2
local lastPick: { [Player]: number } = {}

local function onWalkCap(player: Player, picked: any)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local now = os.clock()
	if type(picked) == "number" and picked == picked and now - (lastPick[player] or 0) >= PICK_COOLDOWN then
		lastPick[player] = now
		local trained = Treadmill.walkFor(data.speedPoints or 0)
		local walk = math.floor(picked + 0.5)
		if walk <= 0 or walk >= trained then
			data.walkCap = 0
		else
			data.walkCap = math.max(walk, Treadmill.MIN_PICKED_WALK)
		end
	end
	push(player)
end

function TreadmillService.init()
	stateRemote = Net.get("SpeedState")
	-- The hotbar popup ("INVENTORY FULL"): the sign has no panel to answer in, so a
	-- bought or refused rung is said here, as is a locked player's dead belt.
	noticeRemote = Net.get("Notice")
	-- In init, not start: ProductService.start() switches ProcessReceipt on, and a
	-- receipt landing before a rung was registered would be bounced.
	for tier = 2, Treadmill.maxTier() do
		ProductService.register(Treadmill.productFor(tier), function(player, data)
			grantRobuxRung(player, data, tier)
		end)
	end
	for _, pack in ShopProducts.SPEED do
		ProductService.register(pack.id, function(player, data)
			grantSpeedPack(player, data, pack.amount)
		end)
	end
end

function TreadmillService.start()
	Net.get("TreadmillBuy").OnServerEvent:Connect(onBuy)

	StationService.onChanged(function(player, kind, _id, previousKind)
		if kind == STATION_KIND then
			local data = DataService.data(player)
			if data and not data.treadmillUnlocked then
				-- Locked: say how to fix it, once per step-on, and pay nothing.
				noticeRemote:FireClient(player, `UNLOCK THE TREADMILL AT ITS SIGN · {Treadmill.unlockPriceText()}`)
				return
			end
			training[player] = true
			startRunning(player)
			push(player)
		elseif previousKind == STATION_KIND then
			training[player] = nil
			stopRunning(player)
			-- Their plot's console shows the owner's level; bring it up to date with
			-- whatever this run earned. Once per run, not per tick.
			ExhibitService.refreshTreadmill(player)
			push(player)
		end
	end)

	Net.get("WalkCap").OnServerEvent:Connect(onWalkCap)

	DataService.onLoaded(function(player)
		-- Access is free now: a save from when it cost $1,000 and was never bought
		-- comes in `false` and is unlocked here, before the first push.
		local data = DataService.data(player)
		if data and Treadmill.UNLOCK_PRICE <= 0 then
			data.treadmillUnlocked = true
		end
		-- The belt on their own plot has to wear the rung they own, and plot assignment
		-- and data load race each other — ExhibitService.refreshTreadmill is a no-op
		-- until they have a plot, and assign() calls it again from its own side.
		ExhibitService.refreshTreadmill(player)
		push(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		training[player] = nil
		runTracks[player] = nil
		lastPush[player] = nil
		lastPick[player] = nil
		lastBuy[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, step, "treadmill")
end

return TreadmillService
