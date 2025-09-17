--!strict
--!optimize 2

if game:GetService("RunService"):IsClient() then
	error("Can't require server module from client.")
end

local Server = {}

-- // Modules
local Packets = require(script.Parent.Shared.Packets)
local Config = require(script.Parent.Shared.Config)
local ProxyTable = require(script.ProxyTable)
local RemoteTable = require(script.RemoteTable)
local Timer = require(script.Timer)
local HashTable = require(script.Parent.Shared.HashTable)

-- // Globals
local TokenCount = 0
local Tokens = {} :: {[string]: number}
local UpdateTimer = Timer.new(1 / Config.UpdatesPerSecond)
local UpdateTasks = {} :: {[number]: {[number]: any}}
local RemoteTables = {} :: {[number]: RemoteTable.RemoteTable<any>}
local ReverseTokenLookup = {} :: {[any]: number}
local PathHashes = {} :: {[any]: {[Config.ValidKey]: number}}
local PathHashTable = HashTable.new(Config.HashtableSize)
local GetFullPathString = Config.GetFullPathString
local SanitizeForAttributeName = Config.SanitizeForAttributeName

local function ProtectedWarn(msg: string)
	if Config.IsStudio then warn(msg) end
end

local function PushUpdateTask(token: number, path_hash: number, value: any)
	local table_tasks = UpdateTasks[token]
	if not table_tasks then
		table_tasks = {}
		UpdateTasks[token] = table_tasks
	end
	table_tasks[path_hash] = value
end

local function DispatchUpdateTasks()
	if not UpdateTasks then return end
	
	for token, table_tasks in UpdateTasks do
		local remote_table = RemoteTables[token]
		for client,_ in remote_table.ReadyClients do
			for path_hash, value in table_tasks do
				Packets.Update:FireClient(client, token, path_hash, value)
			end
		end
		table.clear(UpdateTasks[token])
	end
end

local function CancelTask(token: number, path_hash: number)
	local table_tasks = UpdateTasks[token]
	if not table_tasks then return end

	table_tasks[path_hash] = nil
end

local function NewToken(token_alias: string): number
	assert(TokenCount < 255, "Can't create more than 255 remote tables. Consider releasing unused tokens.")
	assert(not Tokens[token_alias], "Token already registered to another table. Use a different token.")
	if string.find(token_alias, "[^%w]") then
		warn(`Illegal character detected for the token name "{token_alias}". Valid characters: (a-z, A-Z, 0-9, _)`)
	end
	local token_id = TokenCount + 1
	Tokens[token_alias] = token_id
	TokenCount += 1
	script.Parent:SetAttribute(SanitizeForAttributeName(token_alias), token_id)
	return token_id
end

local function ProxyOnChanged(root, protected, index, value)
	local token = ReverseTokenLookup[root]
	assert(token, "Token can't be found")

	local path_hash = PathHashes[protected][index]
	if type(value) == "table" then
		-- Dispatch immediately
		local remote_table = RemoteTables[token]
		for client,_ in remote_table.ReadyClients do
			Packets.Update:FireClient(client, token, path_hash, value)
		end
	else
		if value == nil then
			ProxyTable.OnPathRemoved(root, protected, ProxyTable.GetPathList(protected), index)
		else
			PushUpdateTask(token, path_hash, value)
		end
	end
end

local function OnPathAdded(root, protected, path_list: {Config.ValidKey}, key: Config.ValidKey, value)
	if not PathHashes[protected] then
		PathHashes[protected] = {}
	end
	
	local full_path_string = GetFullPathString(path_list, key)
	local path_hash = PathHashTable:Insert(full_path_string, true)
	PathHashes[protected][key] = path_hash
	
	local token = ReverseTokenLookup[root]
	if not token then return end

	local remote_table = RemoteTables[token]
	local start_value = if type(value) == "table" then {} else value
	for client,_ in remote_table.ReadyClients do
		Packets.HashOperation:FireClient(client, token, "I", path_hash, path_list, key, start_value)
	end
end

local function OnPathReplicate(root, protected, path_list: {Config.ValidKey}, key: Config.ValidKey, value, player: Player)
	local full_path_string = GetFullPathString(path_list, key)
	
	local path_hash = PathHashTable:GetProbe(full_path_string)
	if not path_hash then warn("Hash doesn't exist for the path. Report to the developer.") return end
	
	local token = ReverseTokenLookup[root]
	local remote_table = RemoteTables[token]
	local start_value = if type(value) == "table" then {} else value
	
	Packets.HashOperation:FireClient(player, token, "I", path_hash, path_list, key, start_value)
end

local function OnPathRemoved(root, protected, path_list: {Config.ValidKey}, key: Config.ValidKey)
	local token = ReverseTokenLookup[root]
	local path_hash = PathHashes[protected][key]
	local remote_table = RemoteTables[token]
	CancelTask(token, path_hash)
	for client,_ in remote_table.ReadyClients do
		Packets.HashOperation:FireClient(client, token, "R", path_hash, path_list, key, nil)
	end
end

local function OnClientRequest(player: Player, token_alias: string): boolean
	local token = Tokens[token_alias]
	if not token then
		ProtectedWarn(`Token="{token_alias}" is not registered yet`)
		return false
	end

	local remote_table = RemoteTables[token]
	if not remote_table:IsClientAuthorized(player) then
		ProtectedWarn(`{player} is not authorized.`)
		return false
	end
	
	if remote_table:IsClientReady(player) then
		ProtectedWarn(`{player} is already ready.`)
		return false
	end
	
	Packets.Token:FireClient(player, "A", token_alias, token)
	Packets.Set:FireClient(player, token, remote_table.ReadOnlyData)
	remote_table:ReadyClient(player)
	ProxyTable.RecursiveMapPathAdded(remote_table.ReadOnlyData, OnPathReplicate, player)
	
	return true
end

--[[
	Gets the remote table from token alias
	--@param token_alias: String alias of the token
	--@return RemoteTable<T>?: returns nil if remote table doesn't exist
]]
function Server.GetRemoteTable<T>(token_alias: string): RemoteTable.RemoteTable<T>?
	local token = Tokens[token_alias]
	if not token then return nil end
	
	return RemoteTables[token]
end

--[[
	Creates a new remote table and initializes it
	--@param tbl: Table to be tracked
	--@param token_alias: String token_alias for the token
	--@param players: A player or a player array to be added to the remote table
	--@return RemoteTable<T>: Newly created remote table object
]]
function Server.ConnectTable<T>(tbl: T, token_alias: string, players: (Player | {Player})?): RemoteTable.RemoteTable<T>
	assert(type(token_alias) == "string", "token_alias must be a string!")

	local token = NewToken(token_alias)
	local remote_table = RemoteTable.new(tbl, token, token_alias)
	ReverseTokenLookup[remote_table.ReadOnlyData] = remote_table.Token
	RemoteTables[token] = remote_table

	Packets.Token:Fire("A", token_alias, token)
	ProxyTable.RecursiveMapPathAdded(remote_table.ReadOnlyData, OnPathAdded)
	
	if players then
		if type(players) == "table" then
			for _, player in players do
				remote_table:AddClient(player)
			end
		else
			remote_table:AddClient(players)
		end
	end

	return remote_table
end

--[[
	Authorizes a client to listen to a token
	--@param player: Client to be added
	--@param token_alias: String token_alias for the token
]]
function Server.AddClient(player: Player, token_alias: string)
	local token = Tokens[token_alias]
	assert(token, `RemoteTable with Token="{token}" haven't been created.`)
	
	local remote_table = RemoteTables[token]
	remote_table:AddClient(player)
end

--[[
	Disconnects a client and removes permissions to listen for changes
	--@param player: Client to be added
	--@param token_alias: String token_alias for the token
]]
function Server.RemoveClient(player: Player, token_alias: string)
	local token = Tokens[token_alias]
	assert(token, `RemoteTable with Token="{token}" haven't been created.`)
	
	local remote_table = RemoteTables[token]
	remote_table:_RemoveClient(player)
end

--[[
	Releases the token and disconnects the remote table associated with the token
	--@param token_alias: String token_alias for the token
]]
function Server.ReleaseToken<T>(token_alias: string)
	local token = Tokens[token_alias]
	if not token then return end
	
	script.Parent:SetAttribute(SanitizeForAttributeName(token_alias), nil)
	Tokens[token_alias] = nil
	
	local remote_table = RemoteTables[token]
	if not remote_table then return end
	
	remote_table:_Disconnect()
end

Server.GetProtectedValue = ProxyTable.GetProtectedValue
Server.Insert = ProxyTable.Insert
Server.Remove = ProxyTable.Remove
Server.FastRemove = ProxyTable.FastRemove

Packets.Request.OnServerEvent:Connect(OnClientRequest)

ProxyTable.Changed = ProxyOnChanged
ProxyTable.OnPathAdded = OnPathAdded
ProxyTable.OnPathRemoved = OnPathRemoved

UpdateTimer.Tick:Connect(DispatchUpdateTasks)
UpdateTimer:Start()

return Server