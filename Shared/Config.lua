--!strict
export type ValidKey = string | number
return {
	-- Path to your packet
	Packet = require(script.Parent.Packet),
	
	-- Rate limiting for quick data changes
	UpdatesPerSecond = 20,
	
	--[[
		Size of the hashtable that handles hash collisions
		Enter a value around %40 biger than needed keys
	]]
	HashtableSize = 2000,
	
	-- DO NOT TOUCH
	IsStudio = game:GetService("RunService"):IsStudio(),
	SanitizeForAttributeName = function(str)
		return (str:gsub("[^%w]", "_"))
	end,
	GetFullPathString = function(path_list: {ValidKey}, key: ValidKey): string
		local full_path_string = table.concat(path_list, string.char(31))
		full_path_string ..= if #path_list > 0 then string.char(31)..key else key
		return full_path_string
	end
}
