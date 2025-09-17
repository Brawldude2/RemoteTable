--!strict
local NS = "__REMOTE_TABLE__"
local Config = require(script.Parent.Config)
local Packet = Config.Packet
return {
	-- Operation, Alias, Token
	Token	= Packet(NS.."NewToken",Packet.String, Packet.String, Packet.NumberU8),
	
	-- Command, Alias
	Request	= Packet(NS.."Request", Packet.String),
	
	-- Token, InitialTable
	Set 	= Packet(NS.."Set", 	Packet.NumberU8, Packet.Any),
	
	-- Token, PathHash, Operation, Index, Value
	TableOperation = Packet(NS.."TableOperation", Packet.NumberU8, Packet.NumberU16, Packet.String, Packet.Any, Packet.Any),
	
	-- Token, PathHash, Value
	Update 	= Packet(NS.."Update", 	Packet.NumberU8, Packet.NumberU16, Packet.Any),
	
	-- Token, Operation, PathHash, PathList, Key, Value
	HashOperation = Packet(NS.."H", Packet.NumberU8, Packet.String, Packet.NumberU16, {Packet.Any}, Packet.Any, Packet.Any),
}