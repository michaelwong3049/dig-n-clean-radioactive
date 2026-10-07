--!strict
--[[
	FurnaceStationController.luau — the Slag Furnace doing things you can watch
	(build/SlagFurnace, Services/FurnaceService).

	THE SERVER NEVER MOVES A PART. A burn or a roll bumps `FurnaceSeq` on the furnace
	model and writes FurnaceOutcome beside it ("dump", or the rolled prize's tier); every
	client near the machine plays the same flare off those attributes:

	  flare    the mouth's embers, the hopper's melt and the slag channel turn Neon and
	           a light comes up (the only time this prop glows -- Kit's matte rule holds
	           while it idles)
	  sparks   a burst out of the hopper, bigger and gold for a Legendary-or-better roll,
	           with the rare-drop sting

	A furnace that streams out mid-flare just stops; everything is put back per machine
	when the next flare starts or the model leaves.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)

local Sfx = require(script.Parent.Parent.Sfx)

local FurnaceStation = {}

local TAG = "SlagFurnace"

local EMBER = Color3.fromHex("FF6A1A")
local SPARK = Color3.fromHex("FFB347")
local GOLD = Color3.fromHex("FFD24A")
local GLOWING = { "Embers", "HopperMouth", "ChannelGlow" }
local HOLD = 1.4

type Show = { token: number, bits: { Instance }, rest: { [BasePart]: Enum.Material } }

local shows: { [Model]: Show } = {}
local tokens = 0

local function clear(machine: Model)
	local show = shows[machine]
	if show == nil then
		return
	end
	shows[machine] = nil
	for _, bit in show.bits do
		bit:Destroy()
	end
	for part, material in show.rest do
		if part.Parent then
			part.Material = material
		end
	end
end

local function sparks(parent: BasePart, color: Color3, count: number, speed: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.4, 1)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rate = 0
	emitter.Parent = parent
	emitter:Emit(count)
	task.delay(1.4, function()
		emitter:Destroy()
	end)
end

local function play(machine: Model)
	clear(machine)
	tokens += 1
	local show: Show = { token = tokens, bits = {}, rest = {} }
	shows[machine] = show

	local outcome = machine:GetAttribute("FurnaceOutcome")
	local tier = if type(outcome) == "string" then Rarity.DEFS[outcome] else nil
	local jackpot = tier ~= nil and tier.order >= Rarity.get("Legendary").order

	for _, name in GLOWING do
		local part = machine:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			show.rest[part] = part.Material
			part.Material = Enum.Material.Neon
		end
	end
	local embers = machine:FindFirstChild("Embers")
	if embers and embers:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Color = EMBER
		light.Range = 16
		light.Brightness = 0
		light.Parent = embers
		table.insert(show.bits, light)
		TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 3 }):Play()
	end

	local point = machine:FindFirstChild("SparkPoint")
	if point and point:IsA("BasePart") then
		if outcome == "dump" then
			sparks(point, SPARK, 30, 18)
			Sfx.playAt("dig", point)
		elseif jackpot then
			sparks(point, GOLD, 80, 28)
			Sfx.playAt("rareDrop", point)
		else
			sparks(point, if tier then tier.color else SPARK, 45, 22)
			Sfx.playAt("cleaned", point)
		end
	end

	task.delay(HOLD, function()
		if shows[machine] == show then
			clear(machine)
		end
	end)
end

local function watch(machine: Instance)
	if not machine:IsA("Model") then
		return
	end
	machine:GetAttributeChangedSignal("FurnaceSeq"):Connect(function()
		local ok, err = pcall(play, machine)
		if not ok then
			warn(`[furnace] furnace show failed: {err}`)
		end
	end)
	machine.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clear(machine)
		end
	end)
end

function FurnaceStation.start()
	for _, machine in CollectionService:GetTagged(TAG) do
		watch(machine)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
end

return FurnaceStation
