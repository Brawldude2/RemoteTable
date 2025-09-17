--!strict
--!optimize 2

local XXH32 = require(script.Parent.XXH32)

local HashTable = {}
HashTable.__index = HashTable

-- Constants
local DEFAULT_TABLE_SIZE = 2048

type self<T> = {
	size: number,
	count: number,
	keys: {[number]: string},
	values: {[number]: T},
}

export type HashTable<T> = typeof(setmetatable({} :: self<T>, HashTable))

local function Hash(str: string): number
	return XXH32(buffer.fromstring(str))
end

function HashTable.new<T>(size: number?): HashTable<T>
	local self = setmetatable({} :: self<T>, HashTable)
	self.size = size or DEFAULT_TABLE_SIZE
	self.count = 0
	self.values = table.create(self.size)
	self.keys = table.create(self.size)
	return self
end

function HashTable.GetLoadFactor<T>(self: HashTable<T>)
	return self.count / self.size
end

--[[
	Inserts a new element to the hash table
	Returns the probe if successful
	Throws an error if table is full
]]
function HashTable.Insert<T>(self: HashTable<T>, key: string, value: T): number
	local index = Hash(key) % self.size
	for i = 0, self.size - 1 do
		local probe = (index + i) % self.size + 1
		local entry = self.keys[probe]
		if not entry or entry == key then
			self.keys[probe] = key
			self.values[probe] = value
			self.count += 1
			if self:GetLoadFactor() > 0.7 then
				warn("Load factor over %70. Clustering may drop performance for searches. Consider increasing hash table size.")
			end
			return probe
		end
	end
	error("Hash table is full!")
end

--Returns nil if hash string does not exist
function HashTable.GetProbe<T>(self: HashTable<T>, key: string): number?
	local index = Hash(key) % self.size
	for i = 0, self.size - 1 do
		local probe = (index + i) % self.size + 1
		local entry = self.keys[probe]
		if not entry then return nil end

		if entry == key then
			return probe
		end
	end
	return nil
end

--Returns nil if value could not be found
function HashTable.GetValue<T>(self: HashTable<T>, key: string): T?
	local index = Hash(key) % self.size
	for i = 0, self.size - 1 do
		local probe = (index + i) % self.size + 1
		local entry = self.keys[probe]
		if not entry then return nil end
		
		if entry == key then
			return self.values[probe]
		end
	end
	return nil
end


--Tries to remove and returns if key was successfully removed
function HashTable.Remove<T>(self: HashTable<T>, key: string): boolean
	local index = Hash(key) % self.size
	for i = 0, self.size - 1 do
		local probe = (index + i) % self.size + 1
		local entry = self.keys[probe]
		if not entry then 
			return false
		end
		if entry == key then
			self.keys[probe] = nil
			self.values[probe] = nil
			self.count -= 1
			return true
		end
	end
	return false
end

return HashTable