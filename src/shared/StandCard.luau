--!strict
--[[
	StandCard.luau — what ExhibitService tells every client about each display stand,
	so the client's StandCardController can draw the trophy-ribbon card over it.

	WHY THE SERVER ONLY PUBLISHES. The card used to be a BillboardGui ExhibitService
	built and filled itself. The ribbon animates -- the rarity word shimmers from
	Legendary up, the card pops when a nuke goes up, the crating lock counts down --
	and on the server every one of those frames would be a property write replicated
	to every player. So the server writes a handful of attributes on the stand's
	`Display{slot}` part, once per change, and each client does the drawing. Same split
	ItemFx makes for the nuke effects themselves.

	THE TAG IS ADDED AT RUNTIME, by the server, the first time it writes a stand. The
	Display parts are built in Studio (build/Plots) and saved into the place; tagging
	them there would need a rebuild + Publish for a change that is otherwise code-only.
	A runtime tag replicates like one baked into the place, and it follows the part in
	and out of streaming, so the client never has to go looking for stands by name.
]]

local StandCard = {}

StandCard.TAG = "StandCard"

-- One attribute per fact. `item == ""` is an empty stand; every other attribute is
-- cleared to nil with it and is meaningless until the next write.
StandCard.ATTR = {
	item = "CardItem", -- itemId on display
	rarity = "CardRarity",
	modifier = "CardModifier", -- Rarity.MODIFIERS key; "None" draws no sticker
	rate = "CardRate", -- $/s this one piece pays (ExhibitService.entryYieldPerSecond)
	copy = "CardCopy", -- 1 = the first of its item id on the plot; 2+ earn a damped share
	payload = "CardPayload", -- this dig's Config/Payload roll
	top = "CardTop", -- studs from the Display part's centre up to the top of what sits on it
	placedAt = "CardPlacedAt", -- os.time() it went up; the crating lock counts down from it
	owner = "CardOwner", -- the plot owner's UserId; only they see the crating lock
}

return StandCard
