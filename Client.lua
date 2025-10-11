--!strict
--!optimize 2

if game:GetService("RunService"):IsServer() then
	error("Can't require client module from server.")
end

local Client = {}
export type Client = typeof(Client)

-- // Modules
local Shared = script.Parent.Shared
local Signal = require(Shared.GoodSignal)
local Packets = require(Shared.Packets)
local Config = require(Shared.Config)
local PromiseLight = require(Shared.PromiseLight)

-- // Globals
local RemoteTables = {} :: {[number]: any}
local TableReadySignal = Signal.new()

local ActivePromises = {} :: {[string]: PromiseLight.PromiseLight<any>}
local Tokens = {} :: {[string]: number}
local AliasLookup = {} :: {[number]: string}

local CachedPaths = {} :: {[number]: {[number]: {Parent: any, Key: string}}}
local PathHashLookup = {} :: {[number]: {[string]: number}}

type ChildOperation = "Added" | "Removed"
type WaitingSignals<T...> = {[number]: {[string]: Signal.Signal<T...>}}
type ActiveSignals<T...> = {[number]: {[number]: Signal.Signal<T...>}}

local WaitingChildChangedSignals = {} :: WaitingSignals<ChildOperation, Config.ValidKey, any>
local ActiveChildChangedSignals = {} :: ActiveSignals<ChildOperation, Config.ValidKey, any>
local WaitingChangedSignals = {} :: WaitingSignals<any, any>
local ActiveChangedSignals = {} :: ActiveSignals<any, any>

local SignalContainers: {{[number]:{[string | number]: Signal.Signal<...any>}}} = {
	ActiveChangedSignals,
	ActiveChildChangedSignals,
	WaitingChangedSignals,
	WaitingChildChangedSignals,
} :: {any}

local GetFullPathString = Config.GetFullPathString

Packets.HashOperation.OnClientEvent:Connect(function(token, operation, path_hash, path_list, key, value)
	--Insert
	if operation == "I" then
		local remote_table = RemoteTables[token]
		local parent = remote_table
		for depth, path_ in path_list do
			parent = parent[path_]
		end
		--print(string.rep(" ", 6-string.len(tostring(path_hash)))..`{path_hash} added Parent: ({parent}) Key: {key} Value:`, value)
		CachedPaths[token][path_hash] = {Parent = parent, Key = key}
		parent[key] = value
		
		local full_path_string = GetFullPathString(path_list, key)
		PathHashLookup[token][full_path_string] = path_hash
		
		local parent_path_string = ""
		local parent_key = table.remove(path_list)
		if parent_key then
			--Parent is not root
			parent_path_string = GetFullPathString(path_list, parent_key)
		end
		
		--Table child Added
		local parent_hash = PathHashLookup[token][parent_path_string]
		local child_changed_signal = ActiveChildChangedSignals[token][parent_hash]
		if child_changed_signal then
			-- Table is empty when it's first recieved. Wait until batched update gets to completely replicate descendants
			task.defer(child_changed_signal.Fire, child_changed_signal, "Added" :: ChildOperation, key, value)
		end
		
		--Value changed
		local changed_signal = WaitingChangedSignals[token][full_path_string]
		if changed_signal then
			WaitingChangedSignals[token][full_path_string] = nil
			ActiveChangedSignals[token][path_hash] = changed_signal
		end
		
		--Child changed
		local child_changed_signal = WaitingChildChangedSignals[token][full_path_string]
		if child_changed_signal then
			WaitingChildChangedSignals[token][full_path_string] = nil
			ActiveChildChangedSignals[token][path_hash] = child_changed_signal
		end
	--Remove
	elseif operation == "R" then
		--print(string.rep(" ", 6-string.len(tostring(path_hash)))..`{path_hash} removed`)
		
		local info = CachedPaths[token][path_hash]
		info.Parent[info.Key] = nil
		CachedPaths[token][path_hash] = nil
		
		local full_path_string = GetFullPathString(path_list, key)
		PathHashLookup[token][full_path_string] = nil
		
		local parent_path_string = ""
		local parent_key = table.remove(path_list)
		if parent_key then
			--Parent is not root
			parent_path_string = GetFullPathString(path_list, parent_key)
		end

		--Table child Removed
		local parent_hash = PathHashLookup[token][parent_path_string]
		local child_changed_signal = ActiveChildChangedSignals[token][parent_hash]
		if child_changed_signal then
			task.defer(child_changed_signal.Fire, child_changed_signal, "Removed" :: ChildOperation, key, nil)
		end
		
		--Value changed
		local changed_signal = ActiveChangedSignals[token][path_hash]
		if changed_signal then
			changed_signal:DisconnectAll()
			WaitingChangedSignals[token][full_path_string] = changed_signal
			ActiveChangedSignals[token][path_hash] = nil
		end
		
		--Child changed
		local child_changed_signal = ActiveChangedSignals[token][path_hash]
		if child_changed_signal then
			child_changed_signal:DisconnectAll()
			WaitingChildChangedSignals[token][full_path_string] = child_changed_signal
			ActiveChildChangedSignals[token][path_hash] = nil
		end
	end
end)

local function InitializeTables(token)
	CachedPaths[token] = {}
	PathHashLookup[token] = {}
	
	for _, container in SignalContainers do
		container[token] = {}
	end
end

local function AddToken(token_alias: string, token: number)
	Tokens[token_alias] = token
	AliasLookup[token] = token_alias
end

local function RemoveToken(token_alias: string, token: number)
	for _, container in SignalContainers do
		if container[token] then
			for __, signal in container[token] do
				signal:DisconnectAll()
			end
			container[token] = nil
		end
	end
	
	local promise = ActivePromises[token_alias]
	if promise and not promise.Resolved then
		promise:Cancel()
	end
	
	Tokens[token_alias] = nil
	AliasLookup[token] = nil
end

Packets.Token.OnClientEvent:Connect(function(operation: string, token_alias: string, token: number)
	if operation == "A" then AddToken(token_alias, token) end
	if operation == "R" then RemoveToken(token_alias, token) end
end)

Packets.Set.OnClientEvent:Connect(function(token: number, data: any)
	InitializeTables(token)

	--Root table always gets 0 index
	PathHashLookup[token][""] = 0
	CachedPaths[token][0] = data
	
	local token_alias = AliasLookup[token]
	RemoteTables[token] = data
	TableReadySignal:Fire(token_alias)
	
	local promise = ActivePromises[token_alias]
	if promise then
		promise:Resolve("Success", data)
	end
end)

Packets.Update.OnClientEvent:Connect(function(token: number, path_hash: number, data: any)
	local info = CachedPaths[token][path_hash]
	local signal = ActiveChangedSignals[token][path_hash]
	if signal then
		local old_value = info.Parent[info.Key]
		task.defer(signal.Fire, signal, data, old_value)
	end
	info.Parent[info.Key] = data
end)

Packets.TableOperation.OnClientEvent:Connect(function(token: number, path_hash: number, operation: string, index, value)
	local info = CachedPaths[token][path_hash]
	local tbl = info.Parent[info.Key]
	if operation == "I" then
		--Insert
		if index then
			table.insert(tbl, index, value)
		else
			table.insert(tbl, value)
		end
	elseif operation == "R" then
		--Remove
		if index then
			table.remove(tbl, index)
		else
			table.remove(tbl)
		end
		
	elseif operation == "F" then
		--Fast Remove a.k.a swap back
		local last = table.remove(tbl)
		if index then
			tbl[index] = last
		end
	end
end)


--[[
	Checks if a remote table with a specific token is ready
	--@param token_alias: String alias of the token
	--@return boolean: IsReady
]]
function Client.IsRemoteTableReady(token_alias: string): boolean
	local token = Tokens[token_alias]
	return token and RemoteTables[token]
end


--[[
	Returns the table if available, waits for it if not.
	@param token_alias: String alias of the token
	@param timeout: Timeout in seconds. Returns nil after timing out
	@return data: Ready-only replicated table.
]]
function Client.WaitForTable(token_alias: string, timeout: number?): any
	if Client.IsRemoteTableReady(token_alias) then
		return RemoteTables[Tokens[token_alias]]
	end
	
	local promise = ActivePromises[token_alias]
	if promise then return select(2, promise:Await()) end
	
	local promise = PromiseLight.new(timeout)
	ActivePromises[token_alias] = promise
	
	local token_register_signal: RBXScriptConnection?
	promise.PreResolve = function()
		ActivePromises[token_alias] = nil
	end
	promise:OnResolve(function(status: "Cancel" | "Success" | "Timeout", data)
		if token_register_signal and token_register_signal.Connected then
			token_register_signal:Disconnect()
			token_register_signal = nil
		end
		promise:Destroy()
	end)
	
	local sanitized_alias = Config.SanitizeForAttributeName(token_alias)
	if not script.Parent:GetAttribute(sanitized_alias) then
		token_register_signal = script.Parent:GetAttributeChangedSignal(sanitized_alias):Once(function()
			Packets.Request:Fire(token_alias)
		end)
	else
		Packets.Request:Fire(token_alias)
	end
	
	return select(2, promise:Await())
end

--[[
	Gets the signal that fires when value of the path changes.
	@param token_alias: String alias of the token
	@param path_list: A string array representing the desired path
	@return Signal: Signal that fires (new, old) data
]]
function Client.GetValueChangedSignal(token_alias: string, path_list: {Config.ValidKey}): Signal.Signal<any, any>
	assert(type(path_list)=="table", "Path list must be a table.")
	assert(#path_list>0, "Can not subscribe to root table value changed as it's not supported. Did you mean .GetChildChangedSignal?")
	Client.WaitForTable(token_alias)
	
	local signal = Signal.new()
	local token = Tokens[token_alias]
	local key = table.remove(path_list) :: Config.ValidKey
	local full_path_string = GetFullPathString(path_list, key)
	
	local path_hash = PathHashLookup[token][full_path_string]
	if not path_hash then
		WaitingChangedSignals[token][full_path_string] = signal
	else
		ActiveChangedSignals[token][path_hash] = signal
	end
	
	-- Revert table in case table passed in was not meant to be edited by the library
	table.insert(path_list, key)
	
	return signal
end

--[[
	Gets the signal that fires when a child is Added / Removed from the table.
	@param token_alias: String alias of the token
	@param path_list: A string array representing the desired path_list
	@return Signal: Signal that fires ("Added" | "Removed", key, value) data
]]
function Client.GetChildChangedSignal(token_alias: string, path_list: {Config.ValidKey}): Signal.Signal<ChildOperation, Config.ValidKey, any>
	assert(type(path_list)=="table", "Path list must be a table.")
	Client.WaitForTable(token_alias)

	local signal = Signal.new()
	local token = Tokens[token_alias]
	local key = table.remove(path_list) :: Config.ValidKey
	local full_path_string = ""
	if key then
		full_path_string = GetFullPathString(path_list, key)
	end
	
	local path_hash = PathHashLookup[token][full_path_string]
	if not path_hash then
		WaitingChildChangedSignals[token][full_path_string] = signal
	else
		ActiveChildChangedSignals[token][path_hash] = signal
	end

	-- Revert table in case table passed in was not meant to be edited by the library
	table.insert(path_list, key)

	return signal
end


--[[
	Stops listening to value changed events for that path.
	@param token_alias: String alias of the token
	@param path_list: A string array representing the desired path_list
]]
function Client.DisconnectValueChangedSignal(token_alias: string, path_list: {Config.ValidKey})
	local token = Tokens[token_alias]
	local key = table.remove(path_list) :: Config.ValidKey
	local full_path_string = ""
	if key then
		full_path_string = GetFullPathString(path_list, key)
	end
	local path_hash = PathHashLookup[token][full_path_string]
	
	local signal = WaitingChangedSignals[token][full_path_string]
	if signal then
		signal:DisconnectAll()
		WaitingChangedSignals[token][full_path_string] = nil
	end
	local signal = ActiveChangedSignals[token][path_hash]
	if signal then
		signal:DisconnectAll()
		ActiveChangedSignals[token][path_hash] = nil
	end
end

--[[
	Stops listening to child changed events for that path.
	@param token_alias: String alias of the token
	@param path_list: A string array representing the desired path_list
]]
function Client.DisconnectChildChangedSignal(token_alias: string, path_list: {Config.ValidKey})
	local token = Tokens[token_alias]
	local key = table.remove(path_list) :: Config.ValidKey
	local full_path_string = ""
	if key then
		full_path_string = GetFullPathString(path_list, key)
	end
	local path_hash = PathHashLookup[token][full_path_string]
	
	local signal = WaitingChildChangedSignals[token][full_path_string]
	if signal then
		signal:DisconnectAll()
		WaitingChildChangedSignals[token][full_path_string] = nil
	end
	local signal = ActiveChildChangedSignals[token][path_hash]
	if signal then
		signal:DisconnectAll()
		ActiveChildChangedSignals[token][path_hash] = nil
	end
end

return Client