local DataManager = {}

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Modules
local ProfileStore = require(game.ServerScriptService.ProfileStore)
local RemoteTable = require(ReplicatedStorage.RemoteTable.Server)
local Signal = require(ReplicatedStorage.RemoteTable.Shared.GoodSignal)

-- // Globals
local PROFILE_TEMPLATE = {
	Cash = 0,
	Items = {},
}

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)
local PlayerDatas = {} :: {[Player]: {
	Profile: typeof(PlayerStore:StartSessionAsync()),
	Data: typeof(PROFILE_TEMPLATE),
}}

DataManager.PlayerDatas = PlayerDatas
DataManager.DataLoaded = Signal.new()

function DataManager.GetDataFromPlayer(player: Player): any
	local remote_table = RemoteTable.GetRemoteTable("PlayerData"..player.UserId)
	if not remote_table then return nil end
	
	return remote_table.Data
end

local function PlayerAdded(player: Player)
	local data_token = "PlayerData"..player.UserId
	
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			PlayerDatas[player] = nil
			player:Kick(`[{script.Name}]: Profile session end - Please rejoin`)
			
			--Release the token
			RemoteTable.ReleaseToken(data_token)
		end)

		if player:IsDescendantOf(Players) then
			-- Connect and add client right after player data loads
			local remote_table = RemoteTable.ConnectTable(profile.Data, data_token)
			remote_table:AddClient(player)
			
			-- Override profile.Data with the tracked read-only table
			-- THIS IS READ ONLY DO NOT EDIT
			profile.Data = remote_table.ReadOnlyData
			PlayerDatas[player] = {
				Profile = profile,
				Data = remote_table.Data -- Data safe to edit
			}
			print(`[{script.Name}]: Profile loaded for {player.DisplayName}!`)
			DataManager.DataLoaded:Fire(player, remote_table.Data)
		else
			profile:EndSession()
		end
	else
		player:Kick(`[{script.Name}]: Profile load fail - Please rejoin`)
	end
end

for _, player in Players:GetPlayers() do
	task.spawn(PlayerAdded, player)
end

Players.PlayerAdded:Connect(PlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local profile = PlayerDatas[player].Profile
	if profile ~= nil then
		profile:EndSession()
	end
end)

return DataManager