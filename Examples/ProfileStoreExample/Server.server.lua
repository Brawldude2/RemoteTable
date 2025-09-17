-- // Services
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- // Modules
local DataManager = require(ServerScriptService.DataManager)
local RemoteTable = require(ReplicatedStorage.RemoteTable.Server)

DataManager.DataLoaded:Once(function(player: Player, data)
	-- Add 100 cash each join
	data.Cash += 100
	
	-- Grant a ticket to player everytime they join
	RemoteTable.Insert(data.Items, {Name = "Ticket", Value = 10})
end)