--[[

# 1.0
- Initial Release.
- Added XXH32 as the main hashing algorithm. Thanks to @XoifailTheGod.

# 1.1
- Fixed simple typo which allowed everyone to listen to any table.
- Simplified netcode and client/server communication.
- Added universal WaitForTable. Can be used from anywhere to get a remote table.
- Fixed re-hashing for each connected client.
- Fixed client not being able to listen to same path from different tokens.

# 1.2
- Fixed release token trying to release the non-existent token with id 0.
- Added ValueChanged and ChildChanged signals to listen to.

# 1.2a
- Removed dependency to promise (custom timeout function).
- .Changed events now .WaitForTable by default.

# 1.3
- Fixed Remove, FastRemove and Insert to function properly with nested proxy tables.
- Added .GetProtectedValue which allows users to get the protected value that RemoteTable works with under the hood.
- Small fix to license. Same GPLv3 applies.

]]