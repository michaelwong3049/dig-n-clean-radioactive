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

	PRICES ARE ONE UPGRADE A STAGE, Stage 2 to Stage 9. Each sits at roughly a third to
	a half of that stage's aura tier (Config/Gear), anchored on the two floors they
	replace: floor 2 was 8.7M for 12 stands at Stage 5 and floor 3 2.2B for 12 more at
	Stage 9. Fitted by the pacing sim (Config/Gear's header).
]]

local BaseUpgrades = {}

BaseUpgrades.START = 10
BaseUpgrades.PER_LEVEL = 2
BaseUpgrades.MAX_LEVEL = 8

--- Studs the back fence moves out per upgrade. 8 x 4 = 32 at the top level; the plot
--- ring's outer wall (build/Plots.RING_OUTER) is sized to clear that.
BaseUpgrades.DEPTH_PER_LEVEL = 4

--- Cash price of each upgrade, by the level it buys.
BaseUpgrades.PRICES = {
	[1] = 15000,
	[2] = 150000,
	[3] = 900000,
	[4] = 3500000,
	[5] = 30000000,
	[6] = 150000000,
	[7] = 600000000,
	[8] = 2500000000,
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
