--[[---------------------------------------------------------
	Custom clientside Lua files sender/receiver
-----------------------------------------------------------]]

if SERVER then

	AddCSLuaFile()
	include("luapack/sv_core.lua")

else

	include("luapack/cl_core.lua")

end