--!strict
local function DeepCopy<T>(target: T): T
	if type(target) == "table" then
		local copy = {}
		for key, value in target do
			copy[DeepCopy(key)] = DeepCopy(value)
		end
		return copy :: any
	else
		return target
	end
end return DeepCopy