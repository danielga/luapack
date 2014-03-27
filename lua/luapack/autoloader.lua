local function RemoveExtension(filename)
	return filename:match("([^%.]+).lua")
end

local function LoadAutorun()
	local files = file.Find("autorun/*.lua", "LUA")
	for i = 1, #files do
		include("autorun/" .. files[i])
	end

	local files = file.Find("autorun/client/*.lua", "LUA")
	for i = 1, #files do
		include("autorun/client/" .. files[i])
	end
end

local function LoadVGUI()
	include("derma/init.lua")
	local files = file.Find("vgui/*.lua", "LUA")
	for i = 1, #files do
		include("vgui/" .. files[i])
	end
end

local function LoadEntity(path, name)
	if scripted_ents.GetStored(name) then
		return
	end

	ENT = {
		Base = "base_entity",
		Type = "anim",
		ClassName = name
	}

	if file.IsDir(path .. name, "LUA") then
		if not file.Exists(path .. name .. "/cl_init.lua", "LUA") then
			include(path .. name .. "/shared.lua")
		else
			include(path .. name .. "/cl_init.lua")
		end
	else
		include(path .. name .. ".lua")
	end

	if ENT.Base ~= name then
		LoadEntity(path, ENT.Base)
	end

	scripted_ents.Register(ENT, name)
end

local function LoadEntities(path)
	local files, folders = file.Find(path .. "*", "LUA")
	for i = 1, #files do
		LoadEntity(path, RemoveExtension(files[i]))
	end

	for i = 1, #folders do
		LoadEntity(path, folders[i])
	end
end

local function LoadWeapon(path, name)
	if weapons.GetStored(name) then
		return
	end

	SWEP = {
		Primary = {},
		Secondary = {},
		Base = "weapon_base",
		ClassName = name
	}

	if file.IsDir(path .. name, "LUA") then
		SWEP.Folder = path .. name
		if not file.Exists(path .. name .. "/cl_init.lua", "LUA") then
			include(path .. name .. "/shared.lua")
		else
			include(path .. name .. "/cl_init.lua")
		end
	else
		SWEP.Folder = path
		include(path .. name .. ".lua")
	end

	if SWEP.Base ~= name and not scripted_ents.GetStored(SWEP.Base) then
		LoadWeapon(path, SWEP.Base)
	end

	weapons.Register(SWEP, name)
end

local function LoadWeapons(path)
	local files, folders = file.Find(path .. "*", "LUA")
	for i = 1, #files do
		LoadWeapon(path, RemoveExtension(files[i]))
	end

	for i = 1, #folders do
		LoadWeapon(path, folders[i])
	end
end

local function LoadEffect(path, name)
	if effects.Create(name) then
		return
	end

	EFFECT = {}

	if file.IsDir(path .. name, "LUA") then
		include(path .. name .. "/init.lua")
	else
		include(path .. name .. ".lua")
	end

	effects.Register(EFFECT, name)
end

local function LoadEffects(path)
	local files, folders = file.Find(path .. "*", "LUA")
	for i = 1, #files do
		LoadEffect(path, RemoveExtension(files[i]))
	end

	for i = 1, #folders do
		LoadEffect(path, folders[i])
	end
end

LoadVGUI()
LoadAutorun()

local gamemode_Register = gamemode.Register
local tt = {}
gamemode.Register = function(gm, name, base)
	if not tt[name] then
		tt[name] = true

		LoadEntities(name .. "/entities/entities/")
		LoadWeapons(name .. "/entities/weapons/")
		LoadEffects(name .. "/entities/effects/")

		print("gamemode.Register>", name)
	end

	return gamemode_Register(gm, name, base)
end

hook.Add("CreateTeams", "luapack testing", function()
	print("CreateTeams>", gmod.GetGamemode(), GAMEMODE, GM, engine.ActiveGamemode())
end)

hook.Add("PreGamemodeLoaded", "luapack testing", function()
	LoadEntities("entities/")
	LoadWeapons("weapons/")
	LoadEffects("effects/")

	print("PreGamemodeLoaded>", gmod.GetGamemode(), GAMEMODE, GM, engine.ActiveGamemode())
end)