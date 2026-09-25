--!strict
--[[
	AwayEarningsService.luau — holds what your stands earned while you were offline
	until you COLLECT it (or buy DOUBLE IT) on the "While you were away" card
	(Config/AwayEarnings, client AwayEarningsController).

	ExhibitService still does the sum (bankOffline, on load) and calls offer() here
	with the result. The amount lives on the SAVE as `data.awayPending`, not in this
	file, so a player who leaves with the card up keeps it: the next login adds its
	own earnings on top and shows the card again. What the card says ABOUT the time
	away (how long, the $/s, whether it hit the cap) is only for this session and
	lives in `offers`.

	TWO WAYS THE PUSH CAN REACH THE CLIENT. offer() fires the moment the profile
	loads, which can be before the client's controller has connected (a remote with
	no listener yet is queued, but only for the first one to connect), and the
	client also fires AwayEarnings "ask" when its controller starts, in case the
	profile loaded first. The client ignores a second push while its card is up.

	THE DOUBLE IS A ROBUX PRODUCT, granted through ProductService like the Lucky
	Clover, so the grant must only mutate `data` and must not yield. It pays
	DOUBLE_MULT x the pending amount, instead of the COLLECT it replaces. A receipt
	that arrives after the card is gone (Roblox re-sends one on a later join if the
	first try failed) pays the extra on the last amount shown, `data.awayLast`,
	which is what was bought.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)
local AwayEarnings = require(Shared.Config.AwayEarnings)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ProductService = require(script.Parent.ProductService)

local AwayEarningsService = {}

type Offer = {
	away: number, -- seconds offline, uncapped
	counted: number, -- the part of `away` that paid (at most the bank cap)
	rate: number, -- offline $/s
	capped: boolean, -- `away` ran past the bank cap
}

local offers: { [Player]: Offer } = {}
local remote: any = nil

--- Show the card: the pending amount and what this session knows about the time away.
local function push(player: Player, data: any)
	local offer = offers[player]
	if offer == nil or data.awayPending < 1 then
		return
	end
	remote:FireClient(player, {
		amount = data.awayPending,
		away = offer.away,
		counted = offer.counted,
		rate = offer.rate,
		capped = offer.capped,
	})
end

--- ExhibitService.bankOffline hands over what the stands earned while the player was
--- gone: `credit` dollars over `away` seconds offline, at `rate` offline $/s.
function AwayEarningsService.offer(player: Player, data: any, credit: number, away: number, rate: number)
	local whole = math.floor(credit + 0.5)
	if away < AwayEarnings.MIN_AWAY_SECONDS and data.awayPending < 1 then
		if whole >= 1 then
			EconomyService.award(player, whole, "exhibit")
		end
		return
	end

	data.awayPending += whole
	if data.awayPending < 1 then
		return
	end
	data.awayLast = data.awayPending

	local cap = Tuning.EXHIBIT_OFFLINE_BANK_HOURS * 3600
	offers[player] = {
		away = away,
		counted = math.min(away, cap),
		rate = rate,
		capped = away > cap,
	}
	push(player, data)
end

local function collect(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	offers[player] = nil
	local amount = data.awayPending
	if amount < 1 then
		return
	end
	data.awayPending = 0
	EconomyService.award(player, amount, "away")
	remote:FireClient(player, { collected = amount })
end

--- The DOUBLE IT receipt. Mutates `data` and never yields (ProductService's contract).
local function grantDouble(player: Player, data: any)
	local pending = data.awayPending
	local amount = if pending >= 1
		then pending * AwayEarnings.DOUBLE_MULT
		else data.awayLast * (AwayEarnings.DOUBLE_MULT - 1)
	data.awayPending = 0
	offers[player] = nil
	if amount >= 1 then
		EconomyService.award(player, amount, "away")
	end
	remote:FireClient(player, { collected = amount, doubled = true })
end

function AwayEarningsService.init()
	remote = Net.get("AwayEarnings")
	-- In init, not start: ProductService.start() switches ProcessReceipt on, and a
	-- receipt landing before this was registered would be bounced.
	ProductService.register(AwayEarnings.PRODUCT_ID, grantDouble)
end

function AwayEarningsService.start()
	remote.OnServerEvent:Connect(function(player: Player, verb: any)
		if verb == "ask" then
			local data = DataService.data(player)
			if data then
				push(player, data)
			end
		elseif verb == "collect" then
			collect(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
	end)
end

return AwayEarningsService
