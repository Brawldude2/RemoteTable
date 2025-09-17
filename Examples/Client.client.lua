local Player = game:GetService("Players").LocalPlayer
local RemoteTable = require(game.ReplicatedStorage.RemoteTable).Client

local data = RemoteTable.WaitForTable("PlayerData"..Player.UserId)

--TIP: Enable "Show Tables Expanded by Default" for a better visual feedback
while task.wait(0.2) do
	--Data changes automatically
	print(data)
end