RemoteTable is a lightweight fully automatic data replication system developed by @23sinek345.

RemoteTable can:
 - Automatically replicate changes via proxy tables
 - Hash paths to reduce network and cpu usage
 - Rate limit update rate
 - Handle and optimize dynamic indexes created at runtime
 - Be used with ProfileStore directly
 
 - Subscribe to state changes
Limitations:
 - Not very efficient for relatively large (20-30) item arrays that needs to preserve order
 - Keys for tables can only be number or string and values can only be types Packet.Any supports
 - Can not use table.insert and table.remove or other standard table library functionality
 due to table library bypassing metatables [Custom Insert, Remove and FastRemove are included with the library]
 
WARNING: Never use table.insert or table.remove to manipulate tables. IT WILL BYPASS THE METATABLE.
Instead use RemoteTable.Insert, RemoteTable.FastRemove, RemoteTable.Remove

# Server
	Requiring the module
	local RemoteTable = require(RemoteTable.Server)
					or
	local RemoteTable = require(RemoteTable).Server

	RemoteTable.ConnectTable
		- Creates a new remote table and initializes it
		@param tbl: Table to be tracked
		@param token_alias: String token_alias for the token
		@param players: A player or a player array to be added to the remote table
		@return RemoteTable<T>: Newly created remote table object
		
		RemoteTable.AddClient
			- Authorizes a client to listen to a token
			@param player: Client to be added
			@param token_alias: String token_alias for the token
			
		RemoteTable.RemoveClient
			- Disconnects a client and removes permissions to listen for changes
			@param player: Client to be added
			@param token_alias: String token_alias for the token
			
		RemoteTable.ReleaseToken
			- Releases the token and disconnects the remote table associated with the token
			@param token_alias: String token_alias for the token
			
		RemoteTable.GetRemoteTable
			- Gets the remote table from token alias
			@param token_alias: String alias of the token
			@return RemoteTable<T>?: returns nil if remote table does not exist
			
		RemoteTable.GetProtectedTable
			- Gets the protected read-only data to be used as rvalue
			@param value V: ProxyTable to be used to retrieve the protected value
			@return value V: The read-only data
			
		RemoteTable.Insert
			- Same as table.insert
			@param tbl {V}: Table to insert to
			@param value V: Value to be inserted
			
		RemoteTable.Remove
			- Same as table.remove
			@param tbl {V}: Table to insert to
			@param pos number?: Position to be removed from
			
		RemoteTable.FastRemove
			- Removes an element from the array and replaces it with the last one
			@param tbl {V}: Table to insert to
			@param pos number?: Position to be removed from
		
# Client
	# Requiring the module
	local RemoteTable = require(RemoteTable.Client)
							or
	local RemoteTable = require(RemoteTable).Client
		
	RemoteTable.WaitForTable
		- Returns the table if available, waits for it if not.
		@param token_alias: String alias of the token
		@param timeout: Timeout in seconds. Returns nil after timing out
		@return data: Ready-only replicated table.
	RemoteTable.GetValueChangedSignal
		- Gets the signal that fires when value of the path changes.
		@param token_alias: String alias of the token
		@param path_list: A string array representing the desired path
		@return Signal: Signal that fires (new, old) data
	RemoteTable.GetChildChangedSignal
		- Gets the signal that fires when a child is Added / Removed from the table.
		@param token_alias: String alias of the token
		@param path_list: A string array representing the desired path_list
		@return Signal: Signal that fires ("Added" | "Removed", key, value) data
	RemoteTable.DisconnectValueChangedSignal
		- Stops listening to value changed events for that path.
		@param token_alias: String alias of the token
		@param path_list: A string array representing the desired path_list
	RemoteTable.DisconnectChildChangedSignal
		- Stops listening to child changed events for that path.
		@param token_alias: String alias of the token
		@param path_list: A string array representing the desired path_list

Thanks to Suphi for the proxy table implementation
