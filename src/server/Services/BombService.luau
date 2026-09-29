--!strict
--[[
	BombService.luau — dropping a clean nuke as a bomb.

	Hold a CLEANED nuke out in a stage and press G (Net.BombDrop). It leaves your bag,
	sits on the ground in front of you with its fuse lit, and goes off through
	HazardService.detonate after the nuke's own fuse time. The blast hurts everyone in
	range, you included -- the fuse is your head start. Put someone down with it and
	their WHOLE bag drops where they fell for anyone to grab (ExposureService.dropBag):
	that is the point, and the overhead star badge (NameTagController, BagStars) is
	how you pick a target worth the nuke you are spending.

	EVERY NUMBER COMES OUT OF Shared/Bombing, the same function the hotbar's hover card
	calls, so the damage, radius, fuse and cooldown a player reads before dropping are
	the ones that land. Per-nuke and deterministic per uid; nothing is stored.

	STAGES ONLY. The drop is refused in camps and bases, and the blast spares anyone
	standing in one (HazardService's `spares`), crater burn included.

	THE COOLDOWN (8-10s, Config/Bombing) is per player and is the dropped bomb's own
	cooldown stat, so a big bomb costs you a longer wait. It is session state only.

	THE BOMB IS A COPY OF THE MODEL IN YOUR HANDS (ToolService's HeldItem), anchored on
	the ground. It is tagged like a lit dig fuse (Config/Detonation.HOT_TAG, role
	"bomb") so DetonationController gives it the red glow, the ticking and the
	countdown every player can read -- a target gets the same warning a digger does.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local BombingConfig = require(Shared.Config.Bombing)
local DetonationConfig = require(Shared.Config.Detonation)
local ItemModels = require(Shared.ItemModels)
local Bombing = require(Shared.Bombing)
local Contamination = require(Shared.Contamination)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local StageService = require(script.Parent.StageService)
local HazardService = require(script.Parent.HazardService)
local DigService = require(script.Parent.DigService)

local BombService = {}

local HELD_ITEM_NAME = "HeldItem" -- ToolService's name for the model in your hands
local FOLDER_NAME = "Bombs"

local readyAt: { [Player]: number } = {}
local live: { [Player]: number } = {}

local dropRemote: any = nil
local stateRemote: any = nil

local function folder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = Workspace
	return made
end

local function refuse(player: Player, notice: string)
	stateRemote:FireClient(player, { notice = notice })
end

--- Nobody in a camp or base is touched by a bomb (header).
local function spares(player: Player): boolean
	return StageService.stageOf(player) == nil
end

--- The held model, copied and set down on the ground `DROP_AHEAD` in front of the
--- player, upright the way it was held. nil if the hands are empty.
local function placeBomb(character: Model, root: BasePart): (Model?, Vector3)
	local held = character:FindFirstChild(HELD_ITEM_NAME)
	local ahead = root.Position + root.CFrame.LookVector * BombingConfig.DROP_AHEAD

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, folder() }
	local hit = Workspace:Raycast(ahead + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	local ground = if hit then hit.Position else ahead - Vector3.new(0, 3, 0)

	if held == nil or not held:IsA("Model") then
		return nil, ground
	end

	local bomb = held:Clone()
	bomb.Name = "Bomb"
	for _, thing in bomb:GetDescendants() do
		if thing.Name == "HoldWeld" then
			thing:Destroy()
		elseif thing:IsA("BasePart") then
			thing.Anchored = true
			thing.CanCollide = false
			thing.CanQuery = false
			thing.CanTouch = false
		end
	end

	-- Face the way the player was facing, then sit the bounding box's bottom on the ground.
	local yaw = CFrame.fromOrientation(0, select(2, root.CFrame:ToOrientation()), 0)
	bomb:PivotTo(CFrame.new(ground) * yaw * ItemModels.rotation(bomb, "Hold"))
	local box, extents = bomb:GetBoundingBox()
	local lift = ground.Y - (box.Position.Y - extents.Y / 2)
	bomb:PivotTo(bomb:GetPivot() + Vector3.new(0, lift, 0))
	bomb.Parent = folder()
	return bomb, ground
end

local function drop(player: Player)
	local data = DataService.data(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if data == nil or character == nil or root == nil or not root:IsA("BasePart") then
		return
	end

	if StageService.stageOf(player) == nil then
		refuse(player, "bombs only work out in the stages")
		return
	end
	if DigService.isLocked(player) then
		return
	end

	local now = Workspace:GetServerTimeNow()
	if now < (readyAt[player] or 0) then
		refuse(player, "bomb still cooling down")
		return
	end
	if (live[player] or 0) >= BombingConfig.MAX_LIVE then
		refuse(player, "too many bombs lit")
		return
	end

	local uid = data.heldUid
	local index, item = nil, nil
	for i, candidate in data.carry do
		if candidate.uid == uid then
			index, item = i, candidate
			break
		end
	end
	if item == nil or index == nil then
		refuse(player, "hold a clean nuke to drop it")
		return
	end
	if not Bombing.canDrop(item, Contamination.isClean(item.patches or {})) then
		refuse(player, "only clean nukes can be dropped")
		return
	end

	local stats = Bombing.statsFor(item)
	local bomb, ground = placeBomb(character, root)
	-- Out of the bag. CarryService notices heldUid is gone and empties the hands.
	table.remove(data.carry, index)
	data.heldUid = ""

	readyAt[player] = now + stats.cooldown
	live[player] = (live[player] or 0) + 1
	stateRemote:FireClient(player, { readyAt = readyAt[player], cooldown = stats.cooldown })

	local blowsAt = now + stats.fuse
	if bomb then
		bomb:SetAttribute(DetonationConfig.ATTR_ROLE, "bomb")
		bomb:SetAttribute(DetonationConfig.ATTR_HEAT, 1)
		bomb:SetAttribute(DetonationConfig.ATTR_ARMED, true)
		bomb:SetAttribute(DetonationConfig.ATTR_BLOWS_AT, blowsAt)
		CollectionService:AddTag(bomb, DetonationConfig.HOT_TAG)
	end

	print(`[bomb] {player.Name} dropped a {stats.stars}-star {item.rarity} ({stats.damage} dmg, {stats.radius} studs, {stats.fuse}s fuse)`)

	task.delay(stats.fuse, function()
		if bomb then
			bomb:Destroy()
		end
		if live[player] then
			live[player] = math.max(0, live[player] - 1)
		end
		HazardService.detonate(ground, item.rarity, 1, {
			blast = {
				hit = stats.damage,
				blastRadius = stats.radius,
				orbRadius = stats.radius * BombingConfig.ORB_RADIUS,
				orbBurn = stats.damage * BombingConfig.ORB_BURN,
				orbLife = BombingConfig.ORB_LIFE,
			},
			spares = spares,
		})
	end)
end

function BombService.init()
	dropRemote = Net.get("BombDrop")
	stateRemote = Net.get("BombState")

	-- Same guard as HazardService's craters: a Bombs folder saved into the place from a
	-- Studio play session would leave lit bombs standing forever.
	local stale = Workspace:FindFirstChild(FOLDER_NAME)
	if stale then
		stale:Destroy()
	end
end

function BombService.start()
	dropRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(drop, player)
		if not ok then
			warn(`[bomb] drop failed for {player.Name}: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		live[player] = nil
	end)
end

return BombService
