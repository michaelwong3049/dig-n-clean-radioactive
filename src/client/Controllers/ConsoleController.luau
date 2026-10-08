--!strict
--[[
	ConsoleController.luau — lists DebugService's tuning-console commands in the chat
	autocomplete, for console users only.

	The server builds every command with AutocompleteVisible = false, so an ordinary
	player never sees /cash, /give and the rest suggested as they type. A player
	allowed the console (Studio, or rank 254+ in the owning group — see
	DebugService.mayUseConsole) gets the ConsoleAccess attribute, and this flips
	the property back on HERE. A property set on the client does not replicate, so
	it lists the commands for this player alone.

	Display only. The commands themselves are gated on the server, so a client
	forcing this on gets a list of commands that do nothing for it.
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer

local ConsoleController = {}

local PREFIX = "Debug_" -- DebugService names each TextChatCommand Debug_<alias>

local function show(child: Instance)
	if child:IsA("TextChatCommand") and string.sub(child.Name, 1, #PREFIX) == PREFIX then
		child.AutocompleteVisible = true
	end
end

local function enable()
	for _, child in TextChatService:GetChildren() do
		show(child)
	end
	TextChatService.ChildAdded:Connect(show)
end

function ConsoleController.start()
	if LocalPlayer:GetAttribute("ConsoleAccess") then
		enable()
		return
	end
	local connection: RBXScriptConnection
	connection = LocalPlayer:GetAttributeChangedSignal("ConsoleAccess"):Connect(function()
		if LocalPlayer:GetAttribute("ConsoleAccess") then
			connection:Disconnect()
			enable()
		end
	end)
end

return ConsoleController
