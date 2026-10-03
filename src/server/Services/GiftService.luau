--!strict
--[[
	GiftService.luau — handing the nuke in your hands to another player (Config/Gift,
	client GiftController).

	THE FLOW. Holding a nuke, you walk up to someone and hold T on the "Gift nuke"
	prompt over them (the client draws it; GiftReady/GiftUnlocked below decide when).
	That fires Gift("offer", target). The receiver gets a card with the nuke on it and
	ACCEPT / DECLINE; ACCEPT fires Gift("accept") and the nuke moves bag to bag.

	NOTHING MOVES UNTIL ACCEPT. The offer is a note -- giver, uid and a fingerprint of
	the nuke -- and the nuke stays in the giver's bag the whole time. So a lapse, a
	decline or either player leaving loses nothing, and there is no escrow to hand
	back. ACCEPT re-checks everything: the nuke is still in the giver's bag and still
	the nuke the card showed (the fingerprint, so it can't be swapped for slag or
	merged away mid-offer), the receiver still has room, both are still here.

	THE MOVE ITSELF DOES NOT YIELD: removed from one carry and inserted into the other
	in the same frame, so no other code can see the nuke in both bags or neither.
	Both profiles are then saved straight away, which shrinks -- but cannot close --
	the window where a server crash saves one side and not the other.

	The receiver must answer: nobody gets junk dropped into a full-of-good-stuff bag.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gift = require(Shared.Config.Gift)
local Bombing = require(Shared.Bombing)
local Merge = require(Shared.Config.Merge)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)
local Bag = require(Shared.Bag)

local DataService = require(script.Parent.DataService)
local CarryService = require(script.Parent.CarryService)
local DigService = require(script.Parent.DigService)
local WashService = require(script.Parent.WashService)

local GiftService = {}

--- How often the GiftReady/GiftUnlocked attributes and lapsed offers are looked at.
local TICK = 0.25
--- The least time between two messages from one client.
local REMOTE_COOLDOWN = 0.25

type Offer = {
	from: Player,
	uid: string,
	print: string,
	expiresAt: number,
}

local giftRemote: any = nil
local noticeRemote: any = nil

--- Open offers, by RECEIVER. One at a time each: a second offer to someone already
--- reading one is refused, not stacked.
local offers: { [Player]: Offer } = {}
--- Who each giver's open offer is with, so they can only have one out.
local outgoing: { [Player]: Player } = {}
local lastOfferAt: { [Player]: number } = {}
local lastMessageAt: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function distance(a: Player, b: Player): number
	local ra, rb = rootOf(a), rootOf(b)
	if ra == nil or rb == nil then
		return math.huge
	end
	return (ra.Position - rb.Position).Magnitude
end

local function unlocked(data: any): boolean
	return data ~= nil and type(data.camps) == "table" and data.camps[Gift.CAMP_KEY] == true
end

--- Everything about the nuke the card showed that would make it a different gift.
--- `elapsed` is left out on purpose: the fuse keeps burning while the card is up.
local function fingerprint(item: any): string
	return `{item.itemId}|{item.rarity}|{item.modifier}|{table.concat(item.bonus or {}, ",")}|{Merge.levelOf(item)}|{#(item.patches or {})}|{tostring(item.crateId)}`
end

--- The nuke in this player's hands and its index in `data.carry`, or nil and why not.
--- Crates in `data.crates` are not nukes and can't be held as gifts.
local function heldNuke(player: Player, data: any): (any?, number?, string?)
	if data.heldUid == "" then
		return nil, nil, "hold a nuke to gift it"
	end
	for index, item in data.carry do
		if item.uid == data.heldUid then
			if WashService.isWashing(player) then
				return nil, nil, "finish washing it first"
			end
			return item, index, nil
		end
	end
	return nil, nil, "only nukes can be gifted"
end

local function notice(player: Player, text: string)
	noticeRemote:FireClient(player, text)
end

local function clearOffer(receiver: Player)
	local offer = offers[receiver]
	offers[receiver] = nil
	if offer and outgoing[offer.from] == receiver then
		outgoing[offer.from] = nil
	end
end

--- What the receiver's card shows. Described against the RECEIVER's stats, so the
--- value and $/s are what it would be worth to them. Stars only once it is clean --
--- the stage nudge inside them is a hint at which nuke a crusted lump is.
local function cardFor(item: any, receiverData: any): any
	local described = CarryService.describe(item, StatResolver.get(receiverData))
	described.stars = if described.clean then Bombing.starsOf(item) else nil
	return described
end

local function offer(giver: Player, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players or target == giver then
		return
	end
	local receiver = target :: Player
	local giverData = DataService.data(giver)
	local receiverData = DataService.data(receiver)
	if giverData == nil or receiverData == nil then
		return
	end

	if not unlocked(giverData) then
		notice(giver, "reach Toxic Twilight to gift nukes")
		return
	end
	if not unlocked(receiverData) then
		notice(giver, `{receiver.DisplayName} hasn't reached Toxic Twilight yet`)
		return
	end
	local now = os.clock()
	if now - (lastOfferAt[giver] or -math.huge) < Gift.OFFER_COOLDOWN then
		return
	end
	if DigService.isLocked(giver) then
		return
	end
	local item, _, why = heldNuke(giver, giverData)
	if item == nil then
		notice(giver, why or "hold a nuke to gift it")
		return
	end
	-- A little slack over the prompt's reach for latency.
	if distance(giver, receiver) > Gift.OFFER_RANGE + 6 then
		notice(giver, "get closer to gift")
		return
	end
	if offers[receiver] and offers[receiver].from ~= giver then
		notice(giver, `{receiver.DisplayName} is looking at another gift`)
		return
	end
	if Bag.used(receiverData) >= StatResolver.get(receiverData).capacity then
		notice(giver, `{receiver.DisplayName}'s bag is full`)
		return
	end

	-- One offer out per giver: a new one withdraws the last.
	local previous = outgoing[giver]
	if previous and previous ~= receiver then
		clearOffer(previous)
		giftRemote:FireClient(previous, { kind = "closed", reason = "withdrawn" })
	end

	lastOfferAt[giver] = now
	offers[receiver] = {
		from = giver,
		uid = item.uid,
		print = fingerprint(item),
		expiresAt = now + Gift.OFFER_SECONDS,
	}
	outgoing[giver] = receiver

	giftRemote:FireClient(receiver, {
		kind = "offer",
		from = giver.DisplayName,
		fromUserId = giver.UserId,
		seconds = Gift.OFFER_SECONDS,
		item = cardFor(item, receiverData),
	})
	notice(giver, `gift offered to {receiver.DisplayName}`)
end

local function decline(receiver: Player)
	local open = offers[receiver]
	if open == nil then
		return
	end
	clearOffer(receiver)
	giftRemote:FireClient(receiver, { kind = "closed", reason = "declined" })
	if open.from.Parent == Players then
		notice(open.from, `{receiver.DisplayName} declined your gift`)
	end
end

local function saveBoth(a: Player, b: Player)
	for _, player in { a, b } do
		local profile = DataService.get(player)
		if profile then
			task.spawn(function()
				local ok, err = pcall(function()
					profile:Save()
				end)
				if not ok then
					warn(`[gift] save after gift failed for {player.Name}: {err}`)
				end
			end)
		end
	end
end

local function accept(receiver: Player)
	local open = offers[receiver]
	if open == nil then
		-- Lapsed or withdrawn on the way in: answer anyway, or the card waits forever.
		giftRemote:FireClient(receiver, { kind = "result", ok = false, message = "that gift isn't on offer any more" })
		return
	end
	local function fail(text: string)
		clearOffer(receiver)
		giftRemote:FireClient(receiver, { kind = "result", ok = false, message = text })
	end

	local giver = open.from
	if giver.Parent ~= Players or os.clock() > open.expiresAt then
		fail("that gift isn't on offer any more")
		return
	end
	local giverData = DataService.data(giver)
	local receiverData = DataService.data(receiver)
	if giverData == nil or receiverData == nil then
		fail("that gift isn't on offer any more")
		return
	end
	if not unlocked(giverData) or not unlocked(receiverData) then
		fail("gifting unlocks at Toxic Twilight")
		return
	end
	if distance(giver, receiver) > Gift.ACCEPT_RANGE then
		fail(`{giver.DisplayName} walked too far away`)
		return
	end
	if Bag.used(receiverData) >= StatResolver.get(receiverData).capacity then
		-- Kept open: make room and press ACCEPT again.
		giftRemote:FireClient(receiver, { kind = "result", ok = false, keep = true, message = "your bag is full \u{2014} make room first" })
		return
	end

	local index, item = nil, nil
	for i, candidate in giverData.carry do
		if candidate.uid == open.uid then
			index, item = i, candidate
			break
		end
	end
	if item == nil or index == nil or fingerprint(item) ~= open.print then
		fail(`{giver.DisplayName} doesn't have that nuke any more`)
		notice(giver, "your gift was cancelled \u{2014} the nuke changed")
		return
	end
	if giverData.heldUid == item.uid and WashService.isWashing(giver) then
		fail(`{giver.DisplayName} is washing that nuke`)
		return
	end

	-- THE MOVE. No yields from here to the insert (header).
	table.remove(giverData.carry, index)
	if giverData.heldUid == item.uid then
		giverData.heldUid = ""
	end
	table.insert(receiverData.carry, item)
	clearOffer(receiver)

	local name = CarryService.nameOf(item)
	print(`[gift] {giver.Name} ({giver.UserId}) -> {receiver.Name} ({receiver.UserId}): {item.rarity} {item.itemId} uid={item.uid}`)
	saveBoth(giver, receiver)

	giftRemote:FireClient(receiver, { kind = "result", ok = true, message = `{name} from {giver.DisplayName}` })
	notice(giver, `{receiver.DisplayName} accepted your {name}`)
end

--- Publishes GiftUnlocked / GiftReady and lapses old offers.
local function step()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local data = DataService.data(player)
		local isUnlocked = unlocked(data)
		local ready = false
		if isUnlocked and not DigService.isLocked(player) then
			ready = heldNuke(player, data) ~= nil
		end
		if player:GetAttribute(Gift.ATTR_UNLOCKED) ~= isUnlocked then
			player:SetAttribute(Gift.ATTR_UNLOCKED, isUnlocked)
		end
		if player:GetAttribute(Gift.ATTR_READY) ~= ready then
			player:SetAttribute(Gift.ATTR_READY, ready)
		end
	end

	for receiver, open in offers do
		if now > open.expiresAt or open.from.Parent ~= Players or receiver.Parent ~= Players then
			clearOffer(receiver)
			if receiver.Parent == Players then
				giftRemote:FireClient(receiver, { kind = "closed", reason = "expired" })
			end
			if open.from.Parent == Players and receiver.Parent == Players then
				notice(open.from, `{receiver.DisplayName} didn't answer your gift`)
			end
		end
	end
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

function GiftService.init()
	giftRemote = Net.get("Gift")
	noticeRemote = Net.get("Notice")
end

function GiftService.start()
	giftRemote.OnServerEvent:Connect(function(player: Player, verb: any, target: any)
		local now = os.clock()
		if now - (lastMessageAt[player] or -math.huge) < REMOTE_COOLDOWN then
			return
		end
		lastMessageAt[player] = now
		if verb == "offer" then
			offer(player, target)
		elseif verb == "accept" then
			accept(player)
		elseif verb == "decline" then
			decline(player)
		end
	end)

	Ticker.every(TICK, function()
		local ok, err = pcall(step)
		if not ok then
			warn(`[gift] tick failed: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Their own open offer and any offer they made; step() tells whoever is left.
		local target = outgoing[player]
		if target then
			clearOffer(target)
			if target.Parent == Players then
				giftRemote:FireClient(target, { kind = "closed", reason = "left" })
			end
		end
		clearOffer(player)
		lastOfferAt[player] = nil
		lastMessageAt[player] = nil
	end)
end

return GiftService
