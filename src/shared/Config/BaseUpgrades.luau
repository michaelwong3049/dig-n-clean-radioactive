--!strict
--[[
	BaseUpgrades.luau — how many nukes a base holds, and how big its open floor is.

	A BASE IS ONE OPEN FLOOR, NOT A GRID OF STANDS. It replaced Config/Floors (a
	12-stand ground grid plus two bought storeys of 12 more). A player places each nuke
	wherever it fits on their own plot (Shared/Placement says what "fits" means); the
	only limit is how many they may have out at once, and that is what this file sells.

	A base starts at START nukes. The Upgrade Base sign sells MAX_LEVEL upgrades, one at
	a time, each adding PER_LEVEL more nukes AND pushing the plot's back edge out by
	DEPTH_PER_LEVEL studs, so the extra nukes have somewhere to go. `data.exhibit.level`
	(0..MAX_LEVEL) is the only saved state; the cap is always derived from it
	(`capFor`), never stored on its own.

	PRICES ARE ONE UPGRADE A STAGE, Stage 2 to Stage 9: level L is part of Stage L+1's
	bill, the way floor 2 was Stage 5's and floor 3 Stage 9's. Fitted by the pacing sim
	(Config/Gear's header; same simulator, gear prices untouched) so every stage takes as
	long as it did with 12 stands and two floors: each level's price bisected against
	that stage's old median, then smoothed into a rising curve (the raw fit zigzagged,
	since in most stages the upgrade is a small slice of the bill and barely moves the
	time). Result: 27.9 h to reach Stage 12 against 27.5 h before, every stage within
	~5% except Stage 11 (+4%, 515 vs 495 min: no upgrade left to buy there, and a full
	base holds 26 nukes where the floors held 36). The first three are near-free on
	purpose: fewer nukes at the start made Stages 1-3 slower, and cheap early upgrades
	win that back.
]]

local BaseUpgrades = {}

BaseUpgrades.START = 10
BaseUpgrades.PER_LEVEL = 2
BaseUpgrades.MAX_LEVEL = 8

--- Studs the back fence moves out per upgrade. 8 x 4 = 32 at the top level; the plot
--- camp's outer wall (build/Plots.CAMP) is sized to clear that.
BaseUpgrades.DEPTH_PER_LEVEL = 4

--- Cash price of each upgrade, by the level it buys.
BaseUpgrades.PRICES = {
	[1] = 500,
	[2] = 6000,
	[3] = 9000,
	[4] = 9000000,
	[5] = 10000000,
	[6] = 15000000,
	[7] = 25000000,
	[8] = 1900000000,
}

--- Every nuke a fully upgraded base can hold. Loops that scan "all placed nukes" use it.
BaseUpgrades.MAX_NUKES = BaseUpgrades.START + BaseUpgrades.MAX_LEVEL * BaseUpgrades.PER_LEVEL

--- A saved level clamped to a real one (a save carries a number, and a number can be
--- anything).
function BaseUpgrades.clamp(level: number?): number
	local n = if type(level) == "number" and level == level then level else 0
	return math.clamp(math.floor(n), 0, BaseUpgrades.MAX_LEVEL)
end

--- How many nukes a base at `level` may have placed at once.
function BaseUpgrades.capFor(level: number?): number
	return BaseUpgrades.START + BaseUpgrades.clamp(level) * BaseUpgrades.PER_LEVEL
end

--- How far past its level-0 back edge a base at `level` reaches, in studs.
function BaseUpgrades.extraDepth(level: number?): number
	return BaseUpgrades.clamp(level) * BaseUpgrades.DEPTH_PER_LEVEL
end

--- The price of the upgrade AFTER `level`, or nil when the base is already maxed.
function BaseUpgrades.nextPrice(level: number?): number?
	return BaseUpgrades.PRICES[BaseUpgrades.clamp(level) + 1]
end

return BaseUpgrades
