--!strict
--[[
	PlayerCollisionService.luau — players phase through each other.

	Every part under a character (body, accessories, held nukes, aura bits welded on
	later) goes into the "Players" collision group, and that group is set not to
	collide with itself. Players still collide with the world (Default) as normal —
	only player-vs-player contact is switched off, so nobody can body-block a shop
	counter, a stand or a narrow stair.

	DescendantAdded rather than a one-off pass, because parts are welded onto the
	character long after spawn (held models, accessories that load late).
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local PlayerCollisionService = {}

local GROUP = "Players"

local function tag(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = GROUP
	end
end

local function onCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		tag(descendant)
	end
	character.DescendantAdded:Connect(tag)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

function PlayerCollisionService.init()
	if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
		PhysicsService:RegisterCollisionGroup(GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end

function PlayerCollisionService.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return PlayerCollisionService
