--!strict
--[[
	Codes.luau — the redeemable codes in the Shop's CODES section (Services/CodeService,
	client ShopController).

	ADDING A CODE: add an entry to LIST. Every reward field is optional, so a code can
	pay whatever you want it to; leave a field out and it pays none of that.

	  cash               dollars, through EconomyService.award
	  speed              Speed points (the treadmill stat)
	  luckSeconds        seconds of 2x luck
	  cashBoostSeconds   seconds of 2x cash
	  crates             list of Config/Crates ids, e.g. { "nuke1", "liquid2" }
	  potions            list of { id = Config/Potions id, count = n }, into the potion stash,
	                     e.g. { { id = "luck", count = 1 } }
	  expires            os.time() after which the code stops working (UTC)
	  disabled           true to switch a code off without deleting it

	ONCE PER PLAYER PER CODE: the codes a save has used are on `data.redeemedCodes`.
	Matching ignores case and surrounding spaces, so "welcome " finds "WELCOME".

	GROUP ONLY: redeeming needs membership of GroupReward.GROUP_ID, checked on the server
	(CodeService). Not a member -> the client opens Roblox's join-group prompt.
]]

export type Code = {
	code: string,
	cash: number?,
	speed: number?,
	luckSeconds: number?,
	cashBoostSeconds: number?,
	crates: { string }?,
	potions: { { id: string, count: number } }?,
	expires: number?,
	disabled: boolean?,
}

local Codes = {}

Codes.MAX_LENGTH = 32

Codes.LIST = {
	-- One of each potion.
	{
		code = "POTIONS!",
		potions = {
			{ id = "luck", count = 1 },
			{ id = "cash", count = 1 },
			{ id = "speed", count = 1 },
			{ id = "strength", count = 1 },
			{ id = "clean", count = 1 },
		},
	},
	-- Release code: a Luck, a Strength and a Cash potion.
	{
		code = "RELEASE!",
		potions = {
			{ id = "luck", count = 1 },
			{ id = "strength", count = 1 },
			{ id = "cash", count = 1 },
		},
	},
	-- FAST MODE code: three Luck and three Cash potions.
	{
		code = "FAST!",
		potions = {
			{ id = "luck", count = 3 },
			{ id = "cash", count = 3 },
		},
	},
} :: { Code }

local byCode: { [string]: Code } = {}

--- "  welcome " -> "WELCOME". Anything but letters and digits is dropped.
function Codes.normalize(text: string): string
	return string.upper((string.gsub(text, "[^%w]", "")))
end

for _, entry in Codes.LIST do
	byCode[Codes.normalize(entry.code)] = entry
end

--- The live code for what a player typed, or nil if there is none (or it is off/expired).
function Codes.find(text: string): Code?
	local entry = byCode[Codes.normalize(text)]
	if entry == nil or entry.disabled then
		return nil
	end
	if entry.expires and os.time() > entry.expires then
		return nil
	end
	return entry
end

--- "$10K cash, 10 min of 2x luck" -- what the toast says a code paid.
function Codes.describe(entry: Code): string
	local parts = {}
	if entry.cash then
		table.insert(parts, `${entry.cash} cash`)
	end
	if entry.speed then
		table.insert(parts, `{entry.speed} Speed`)
	end
	if entry.luckSeconds then
		table.insert(parts, `{math.floor(entry.luckSeconds / 60)} min of 2x luck`)
	end
	if entry.cashBoostSeconds then
		table.insert(parts, `{math.floor(entry.cashBoostSeconds / 60)} min of 2x cash`)
	end
	if entry.potions then
		local total = 0
		for _, potion in entry.potions do
			total += potion.count
		end
		if total > 0 then
			table.insert(parts, `{total} potion{if total == 1 then "" else "s"}`)
		end
	end
	if entry.crates and #entry.crates > 0 then
		table.insert(parts, `{#entry.crates} crate{if #entry.crates == 1 then "" else "s"}`)
	end
	return table.concat(parts, ", ")
end

return Codes
