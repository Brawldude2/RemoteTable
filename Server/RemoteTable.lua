--!strict
--!optimize 2

local ProxyTable = require(script.Parent.ProxyTable)
local Packets = require(script.Parent.Parent.Shared.Packets)

local RemoteTable = {}
RemoteTable.__index = RemoteTable

type RemoteTableFields<T> = {
	Connected: boolean,
	
	Token: number,
	TokenAlias: string,
	
	Data: T,
	ReadOnlyData: T,
	
	AuthorizedClients: {[Player]: boolean},
	ReadyClients: {[Player]: boolean},
}

export type RemoteTable<T> = typeof(setmetatable({} :: RemoteTableFields<T>, RemoteTable))

function RemoteTable.new<T>(tbl: T, token: number, token_alias: string): RemoteTable<T>
	local self = setmetatable({} :: RemoteTableFields<T>, RemoteTable)
	self.Connected = true
	self.TokenAlias = token_alias
	self.Token = token
	self.ReadOnlyData = ProxyTable.Track(tbl)
	self.Data = ProxyTable.GetProxy(self.ReadOnlyData)
	self.AuthorizedClients = {}
	self.ReadyClients = {}
	return self
end

function RemoteTable.AddClient<T>(self: RemoteTable<T>, player: Player)
	assert(self.Connected, "Can't add client after disconnecting.")
	if typeof(player) == "Instance" then
		assert(player:IsA("Player"), "Can't add non-player instances.")
		self.AuthorizedClients[player] = true
	end
end

function RemoteTable._RemoveClient<T>(self: RemoteTable<T>, player: Player)
	assert(self.Connected, "Can't remove client after disconnecting.")
	if typeof(player) == "Instance" then
		assert(player:IsA("Player"), "Can't remove non-player instances.")
		self.AuthorizedClients[player] = nil
		self.ReadyClients[player] = nil
		Packets.Token:FireClient(player, "R", self.TokenAlias, self.Token)
	end
end

function RemoteTable.IsClientAuthorized<T>(self: RemoteTable<T>, player: Player): boolean
	return self.AuthorizedClients[player] or false
end

function RemoteTable.IsClientReady<T>(self: RemoteTable<T>, player: Player): boolean
	return self.ReadyClients[player] or false
end

function RemoteTable.ReadyClient<T>(self: RemoteTable<T>, player: Player)
	self.ReadyClients[player] = true
	return self.ReadOnlyData
end

function RemoteTable._Disconnect<T>(self: RemoteTable<T>)
	if not self.Connected then return end
	for client, _ in self.AuthorizedClients do
		self:_RemoveClient(client)
	end
	self.Connected = false
	self.ReadyClients = {}
	self.AuthorizedClients = {}
	ProxyTable.Untrack(self.Data)
end

return RemoteTable