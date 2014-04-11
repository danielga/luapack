local function RemoveExtension(filename)
	return filename:match("([^%.]+).lua")
end

function luapack.LoadAutorun()
	local files = file.Find("autorun/*.lua", "LUA")
	for i = 1, #files do
		include("autorun/" .. files[i])
	end

	local files = file.Find("autorun/client/*.lua", "LUA")
	for i = 1, #files do
		include("autorun/client/" .. files[i])
	end
end

function luapack.LoadVGUI()
	include("derma/init.lua")
	local files = file.Find("vgui/*.lua", "LUA")
	for i = 1, #files do
		include("vgui/" .. files[i])
	end
end

function luapack.LoadEntity(path, name)
	if scripted_ents.GetStored(name) then
		return
	end

	ENT = {
		Base = "base_entity",
		Type = "anim",
		ClassName = name
	}

	if file.IsDir(path .. "/" .. name, "LUA") then
		if not file.Exists(path .. "/" .. name .. "/cl_init.lua", "LUA") then
			include(path .. "/" .. name .. "/shared.lua")
		else
			include(path .. "/" .. name .. "/cl_init.lua")
		end
	else
		include(path .. "/" .. name .. ".lua")
	end

	if ENT.Base ~= name then
		luapack.LoadEntity(path, ENT.Base)
	end

	scripted_ents.Register(ENT, name)
end

function luapack.LoadEntities(path)
	local files, folders = file.Find(path .. "/*", "LUA")
	for i = 1, #files do
		luapack.LoadEntity(path, RemoveExtension(files[i]))
	end

	for i = 1, #folders do
		luapack.LoadEntity(path, folders[i])
	end
end

function luapack.LoadWeapon(path, name)
	if weapons.GetStored(name) then
		return
	end

	SWEP = {
		Primary = {},
		Secondary = {},
		Base = "weapon_base",
		ClassName = name
	}

	if file.IsDir(path .. "/" .. name, "LUA") then
		SWEP.Folder = path .. "/" .. name
		if not file.Exists(path .. "/" .. name .. "/cl_init.lua", "LUA") then
			include(path .. "/" .. name .. "/shared.lua")
		else
			include(path .. "/" .. name .. "/cl_init.lua")
		end
	else
		SWEP.Folder = path
		include(path .. "/" .. name .. ".lua")
	end

	if SWEP.Base ~= name and not scripted_ents.GetStored(SWEP.Base) then
		luapack.LoadWeapon(path, SWEP.Base)
	end

	weapons.Register(SWEP, name)
end

function luapack.LoadWeapons(path)
	local files, folders = file.Find(path .. "/*", "LUA")
	for i = 1, #files do
		luapack.LoadWeapon(path, RemoveExtension(files[i]))
	end

	for i = 1, #folders do
		luapack.LoadWeapon(path, folders[i])
	end
end

function luapack.LoadEffect(path, name)
	if effects.Create(name) then
		return
	end

	EFFECT = {}

	if file.IsDir(path .. "/" .. name, "LUA") then
		include(path .. "/" .. name .. "/init.lua")
	else
		include(path .. "/" .. name .. ".lua")
	end

	effects.Register(EFFECT, name)
end

function luapack.LoadEffects(path)
	local files, folders = file.Find(path .. "/*", "LUA")
	for i = 1, #files do
		luapack.LoadEffect(path, RemoveExtension(files[i]))
	end

	for i = 1, #folders do
		luapack.LoadEffect(path, folders[i])
	end
end

function luapack.LoadGamemode(name, tab)
	luapack.LoadEntities(name .. "/entities/entities")
	luapack.LoadWeapons(name .. "/entities/weapons")
	luapack.LoadEffects(name .. "/entities/effects")

	local gm = GM
	GM = tab
	include(name .. "/gamemode/cl_init.lua")
	GM = gm
end

luapack.LoadVGUI()
luapack.LoadAutorun()

luapack.gamemodeRegister = luapack.gamemodeRegister or gamemode.Register

local tt = {}
gamemode.Register = function(gm, name, base)
	if not tt[name] then
		tt[name] = true

		luapack.LoadGamemode(name, gm)

		print("gamemode.Register>", name)
	end

	return luapack.gamemodeRegister(gm, name, base)
end

hook.Add("PostGamemodeLoaded", "luapack testing", function()
	luapack.LoadEntities("entities")
	luapack.LoadWeapons("weapons")
	luapack.LoadEffects("effects")

	print("PostGamemodeLoaded>", engine.ActiveGamemode())
end)