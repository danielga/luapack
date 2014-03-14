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

	hook.Add("CreateTeams","asd",function()
		print("CreateTeams>",gmod.GetGamemode(),GAMEMODE,GM,engine.ActiveGamemode())
	end)
	hook.Add("PreGamemodeLoaded","asd",function()
		print("PreGamemodeLoaded>",gmod.GetGamemode(),GAMEMODE,GM,engine.ActiveGamemode())
	end)
end