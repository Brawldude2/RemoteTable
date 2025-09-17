local RemoteTable = require(game.ReplicatedStorage.RemoteTable).Server

local ExampleTable = {
	Key1 = 1,
	Table = {
		Key2 = 2,
	},
	Array = {"A","B","C"}
}

game.Players.PlayerRemoving:Connect(function(player: Player)
	RemoteTable.ReleaseToken("PlayerData"..player.UserId)
end)

game.Players.PlayerAdded:Connect(function(player: Player)
	local remote_table = RemoteTable.ConnectTable(ExampleTable, "PlayerData"..player.UserId)
	remote_table:AddClient(player)

	--or alternatively this
	--RemoteTable.AddClient(player, "PlayerDataToken"..player.UserId)

	--[[
		Give client a small delay to connect
		This is only for demonstration purposes
		In production it doesn't matter when client connects
		as long as server does .AddClient() for the client
	]]
	task.wait(2)

	remote_table.Data.DynamicTable = {DynamicKey = 1}
	task.wait(1)

	remote_table.Data.DynamicTable.DynamicKey += player.UserId
	task.wait(1)

	remote_table.Data.Key1 = 3
	task.wait(1)

	remote_table.Data.Table.Key2 = 4
	task.wait(1)

	-- ["A","B","C","D"]
	RemoteTable.Insert(remote_table.Data.Array, "D")
	task.wait(1)

	-- ["B","C","D"]
	RemoteTable.Remove(remote_table.Data.Array, 1)
	task.wait(1)

	-- ["D", "C"]
	RemoteTable.FastRemove(remote_table.Data.Array, 1)
end)