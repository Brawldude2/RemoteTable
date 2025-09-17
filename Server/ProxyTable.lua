--!strict
--!optimize 2

-- Proxy Table implementation by @5uphi
-- Converted to module and refactor by @23sinek345

-- // Modules
local DeepCopy = require(script.Parent.Parent.Shared.DeepCopy)
local Config = require(script.Parent.Parent.Shared.Config)

-- // Types
type OnPathAdded = (root: any, protected: any, path_list: {Config.ValidKey}, key: string | number, value: any, ...any) -> ()
type OnPathRemoved = (root: any, protected: any, path_list: {Config.ValidKey}, key: string | number) -> ()

-- // Globals
local ProxyTable = {}
ProxyTable.Changed = function(root: any, protected: any, key: string, value: any) return end
ProxyTable.OnPathAdded = function() end :: OnPathAdded
ProxyTable.OnPathRemoved = function() end :: OnPathRemoved

local Metatable = {}
local ProxyTables = {}
local ProtectedTables = {}
local ProtectedParents = {}
local ProtectedIndices = {}
local RootLinks = {}

-- Gets the protected read-only data to be used as rvalue
-- WARNING: THIS VALUE SHOULD NOT BE EDITED AND IS READ-ONLY
local function GetProtectedValue<V>(value: V): V
	if ProtectedTables[value] then
		return ProtectedTables[value]
	else
		return value
	end
end

-- Same as table.insert
local function Insert<V>(tbl: {V}, value: V)
	assert(not ProtectedTables[value], "Inserting a proxy table as a value is not allowed.")
	tbl[#tbl+1] = value
end

--Same as table.remove
--WARNING: Very expensive to execute and replicate to the client
local function Remove<V>(tbl: {V}, pos: number?)
	if #tbl == 0 or pos > #tbl then return end
	if pos then
		for i=pos+1, #tbl do
			tbl[i-1] = GetProtectedValue(tbl[i])
		end
	end
	tbl[#tbl] = nil
end

--Removes an element from the array and replaces it with the last one
--NOTE: Recommended when order of elements doesn't matter
local function FastRemove<V>(tbl: {V}, pos: number?)
	if #tbl == 0 or pos > #tbl then return end
	if pos then
		tbl[pos] = GetProtectedValue(tbl[#tbl])
	end
	tbl[#tbl] = nil
end

local function GetPathList(protected): {Config.ValidKey}
	local path_list = {}
	local current = protected
	while ProtectedIndices[current] ~= nil do
		table.insert(path_list, 1, ProtectedIndices[current])
		current = ProtectedParents[current]
	end
	return path_list
end

local function Iterator(proxy, index)
	local index, value = next(proxy, index)
	if type(value) == "table" then
		return index, ProxyTables[value]
	else
		return index, value
	end
end

local function RecursiveMapPathAdded(protected: any, func: OnPathAdded, ...: any)
	local root = RootLinks[protected]
	assert(root, "Root can not be found")
	local path_list = GetPathList(protected)
	for key, value in protected do
		func(root, protected, path_list, key, value, ...)
		if type(value) == "table" then
			RecursiveMapPathAdded(value, func, ...)
		end
	end
end

local function RecursiveMapPathRemoved(protected: any, func: OnPathRemoved)
	local root = RootLinks[protected]
	local path_list = GetPathList(protected)
	for key, value in protected do
		if type(value) == "table" then
			RecursiveMapPathRemoved(value, func)
		end
		func(root, protected, path_list, key)
	end
end

local function Track(proxy, parent, index: Config.ValidKey?, root)
	local protected = {}

	-- Set the top-most table to root
	if not root then
		proxy = DeepCopy(proxy)
		root = protected
	end
	local path_list = GetPathList(protected)

	ProxyTables[protected] = proxy
	ProtectedTables[proxy] = protected
	ProtectedParents[protected] = parent
	ProtectedIndices[protected] = index
	RootLinks[protected] = root

	for key, value in proxy do
		if type(value) == "table" then
			protected[key] = Track(value, protected, key, root)
		else
			protected[key] = value
		end
		proxy[key] = nil
	end

	proxy = setmetatable(proxy, Metatable)
	return protected
end

local function Untrack(proxy, root: any)
	proxy = setmetatable(proxy, nil)
	local protected = ProtectedTables[proxy]

	-- Find the root table for the first entry
	if not root then
		root = protected
		while ProtectedIndices[root] ~= nil do
			root = ProtectedParents[root]
		end
	end

	for index, value in protected do
		ProxyTable.OnPathRemoved(root, protected, GetPathList(protected), index)

		if type(value) == "table" then
			proxy[index] = Untrack(ProxyTables[value], root)
		else
			proxy[index] = value
		end
	end

	ProxyTables[protected] = nil
	ProtectedTables[proxy] = nil
	ProtectedParents[protected] = nil
	ProtectedIndices[protected] = nil
	RootLinks[protected] = nil

	return proxy
end

Metatable.__tostring = function(proxy) return game.HttpService:JSONEncode(ProtectedTables[proxy]) end
Metatable.__iter = function(proxy) return Iterator, ProtectedTables[proxy] end
Metatable.__len = function(proxy) return #ProtectedTables[proxy] end
Metatable.__newindex = function(proxy, index: any, value)
	local protected = ProtectedTables[proxy]
	local prev_value = protected[index]
	if prev_value == value then return end

	local root = RootLinks[protected]

	if type(prev_value) == "table" then
		Untrack(ProxyTables[prev_value])
	end

	local cached_value = DeepCopy(value)

	if type(value) == "table" then
		protected[index] = Track(value, protected, index, root)
	else
		protected[index] = value
	end

	-- New key
	if prev_value == nil then
		ProxyTable.OnPathAdded(root, protected, GetPathList(protected), index, cached_value)
	end

	-- If it's a table add paths recursively
	if type(cached_value) == "table" then
		RecursiveMapPathAdded(protected[index], ProxyTable.OnPathAdded)
	end

	-- non-table value changed
	if prev_value ~= nil and type(cached_value) ~= "table" then
		ProxyTable.Changed(root, protected, index, cached_value)
	end
end
Metatable.__index = function(proxy, index)
	local value = ProtectedTables[proxy][index]
	if type(value) == "table" then
		return ProxyTables[value]
	else
		return value
	end
end

ProxyTable.GetProxy = function(protected: any)
	return ProxyTables[protected]
end

ProxyTable.GetPathList = GetPathList

ProxyTable.Track = Track
ProxyTable.Untrack = Untrack
ProxyTable.Iterator = Iterator
ProxyTable.RecursiveMapPathAdded = RecursiveMapPathAdded
ProxyTable.RecursiveMapPathRemoved = RecursiveMapPathRemoved

ProxyTable.GetProtectedValue = GetProtectedValue
ProxyTable.Insert = Insert
ProxyTable.Remove = Remove
ProxyTable.FastRemove = FastRemove

return ProxyTable