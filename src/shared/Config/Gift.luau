--!strict
--[[
	Gift.luau — handing the nuke in your hands to another player (Services/GiftService,
	client GiftController).

	UNLOCKED AT TOXIC TWILIGHT, FOR BOTH SIDES. A veteran handing late-stage nukes to a
	brand-new player would skip the whole early game, so the giver AND the receiver
	have to have reached Twilight on foot (`data.camps.twilight`, CampService) first.

	SAME SERVER ONLY. Each save is session-locked to the server its player is in
	(DataService), so a gift to someone elsewhere would mean writing to a save another
	server owns -- the duplicate-or-lose case that lock exists to prevent.
]]

local Gift = {}

--- The camp (Config/Camps key) both players must have reached.
Gift.CAMP_KEY = "twilight"

--- How close you have to stand to offer (the prompt's reach), in studs.
Gift.OFFER_RANGE = 10
--- How far apart the two may drift while the receiver decides. Loose on purpose:
--- the gift card is up and they are reading it, not standing still.
Gift.ACCEPT_RANGE = 60

--- How long an offer stays open before it lapses, in seconds.
Gift.OFFER_SECONDS = 20
--- The least time between two offers from one giver.
Gift.OFFER_COOLDOWN = 3

--- The prompt's keys. E is taken by half the world's prompts and G drops a bomb.
Gift.KEY = Enum.KeyCode.T
Gift.GAMEPAD_KEY = Enum.KeyCode.ButtonX
Gift.HOLD_SECONDS = 0.4

--- Player attributes GiftService publishes for the client's prompts.
--- GiftUnlocked: this player has reached Twilight (they can receive).
--- GiftReady: GiftUnlocked AND holding a nuke that could be handed over right now.
Gift.ATTR_UNLOCKED = "GiftUnlocked"
Gift.ATTR_READY = "GiftReady"

return Gift
