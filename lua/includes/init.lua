--[[---------------------------------------------------------
	Custom clientside Lua files sender/receiver
-----------------------------------------------------------]]

if SERVER then

	AddCSLuaFile()
	include("sv_luapack.lua")

else

	include("cl_luapack.lua")

end