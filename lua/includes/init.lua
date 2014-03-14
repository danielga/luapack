--[[---------------------------------------------------------
	Custom clientside Lua files sender/receiver
-----------------------------------------------------------]]

if ( SERVER ) then

	AddCSLuaFile	"real_init.lua"
	include			"real_init.lua"
	AddCSLuaFile()
	include ( "luapack/sv_core.lua" )
else

	include ( "luapack/cl_core.lua" )

end