local currenthash = "0000000000000000000000000000000000000000"

---------------------------------------------------------------------

local FILE = {}
FILE.__index = FILE

function FILE:IsFile()
	return true
end

function FILE:IsDirectory()
	return false
end

function FILE:IsRootDirectory()
	return false
end

function FILE:GetPath()
	return self.__path
end

function FILE:GetParent()
	return self.__parent
end

function FILE:GetFullPath()
	local paths = {self:GetPath()}
	local parent = self:GetParent()
	while parent and not parent:IsRootDirectory() do
		table.insert(paths, 1, parent:GetPath())
		parent = parent:GetParent()
	end

	return table.concat(paths, "/")
end

function FILE:GetContents()
	local f = self.__file
	f:Seek(self.__offset)
	local data = f:Read(self.__size)
	if data then
		data = util.Decompress(data)
	end

	return data or ""
end

function FILE:AddFile(name)
	error("what the hell do you think you're doing man")
end

FILE.AddDirectory = FILE.AddFile
FILE.Get = FILE.AddFile
FILE.GetList = FILE.AddFile
FILE.GetIterator = FILE.AddFile
FILE.Destroy = FILE.AddFile

local DIRECTORY = {}
DIRECTORY.__index = DIRECTORY

function DIRECTORY:IsFile()
	return false
end

function DIRECTORY:IsDirectory()
	return true
end

function DIRECTORY:IsRootDirectory()
	return self:GetParent() == nil
end

DIRECTORY.GetPath = FILE.GetPath
DIRECTORY.GetParent = FILE.GetParent
DIRECTORY.GetFullPath = FILE.GetFullPath

local function GetPathParts(path)
	local curdir, rest = path:match("^([^/]+)/(.+)$")
	if curdir and rest then
		return false, curdir, rest
	else
		return true, path
	end
end

function DIRECTORY:AddFile(path, offset, size)
	local single, cur, rest = GetPathParts(path)
	if single then
		local files, dirs = self:Get(cur, false)
		if not files[1] and not dirs[1] then
			local file = setmetatable({
				__path = cur,
				__offset = offset,
				__size = size,
				__parent = self,
				__file = self.__file
			}, FILE)
			table.insert(self:GetList(), file)
			return file
		end

		return files[1]
	else
		local _, dirs = self:Get(cur, false)
		local dir = dirs[1]
		if not dir then
			dir = self:AddDirectory(cur)
		end

		return dir:AddFile(rest, offset, size)
	end
end

function DIRECTORY:AddDirectory(path)
	local single, cur, rest = GetPathParts(path)
	if single then
		local files, dirs = self:Get(cur, false)
		if not files[1] and not dirs[1] then
			local dir = setmetatable({
				__path = cur,
				__parent = self,
				__file = self.__file,
				__list = {}
			}, DIRECTORY)
			table.insert(self:GetList(), dir)
			return dir
		end

		return dirs[1]
	else
		local _, dirs = self:Get(cur, false)
		local dir = dirs[1]
		if not dir then
			dir = self:AddDirectory(cur)
		end

		return dir:AddDirectory(rest)
	end
end

local function GlobToPattern(glob)
	local pattern = {"^"}

	for i = 1, #glob do
		local ch = glob:sub(i, i)

		if ch == "*" then
			ch = ".*"
		else
			ch = ch:find("^%w$") and ch or "%" .. ch
		end

		table.insert(pattern, ch)
	end

	table.insert(pattern, "$")
	return table.concat(pattern)
end

function DIRECTORY:Get(path, pattern, files, dirs)
	pattern = pattern or true
	files = files or {}
	dirs = dirs or {}

	local single, cur, rest = GetPathParts(path)
	if pattern then
		cur = GlobToPattern(cur)
	end

	for elem in self:GetIterator() do
		if (pattern and elem:GetPath():find(cur)) or elem:GetPath() == cur then
			if not single then
				if elem:IsDirectory() then
					elem:Get(rest, pattern, files, dirs)
				end
			else
				table.insert(elem:IsFile() and files or dirs, elem)
			end
		end
	end

	return files, dirs
end

-- not recommended
function DIRECTORY:GetList()
	return self.__list
end

function DIRECTORY:GetIterator()
	local i = 0
	local list = self:GetList()
	local n = #list
	return function()
		i = i + 1
		return i <= n and list[i] or nil
	end
end

function DIRECTORY:GetContents()
	error("what the hell do you think you're doing man")
end

function DIRECTORY:Destroy()
	if not self:IsRootDirectory() then
		error("what the hell do you think you're doing man")
	end

	self.__file:Close()
	self.__file = nil
	self.__list = {}
end

---------------------------------------------------------------------

luapack = luapack or {
	include = include,
	CompileFile = CompileFile,
	require = require,
	fileFind = file.Find,
	fileExists = file.Exists,
	fileIsDir = file.IsDir,
	FileList = {},
	CurrentHash = currenthash
}

local red = {r = 255, g = 0, b = 0, a = 255}
local function ErrorMsg(...)
	MsgC(red, "[LuaPack] ")
	print(...)
end

local green = {r = 0, g = 255, b = 0, a = 255}
local function LogMsg(...)
	MsgC(green, "[LuaPack] ")
	print(...)
end

local yellow = {r = 255, g = 255, b = 0, a = 255}
local function DebugMsg(...)
	MsgC(yellow, "[LuaPack] ")
	print(...)
end

function luapack.CanonicalizePath(path)
	path = path:lower():gsub("\\", "/"):gsub("/+", "/")

	local t = {}
	for str in path:gmatch("([^/]+)") do
		if str == ".." then
			table.remove(t)
		elseif str ~= "." and str ~= "" then
			table.insert(t, str)
		end
	end

	path = table.concat(t, "/")
	return path:match("lua/(.+)$") or (path:match("^gamemodes/(.+)$") or path)
end

function luapack.BuildFileList(filepath)
	LogMsg("Starting Lua file list build of '" .. filepath .. "'!")

	local time = SysTime()

	local f = file.Open(filepath, "rb", "GAME")
	if not f then
		ErrorMsg("Failed to open current pack file for reading", filepath)
		return
	end

	local header = f:Read(f:ReadLong())

	local dir = setmetatable({__file = f, __list = {}}, DIRECTORY)

	for offset, size, path in header:gmatch("(....)(....)([^%z]+)") do
		local o1, o2, o3, o4 = string.byte(offset, 1, 4)
		offset = o4 * 16777216 + o3 * 65536 + o2 * 256 + o1
		local s1, s2, s3, s4 = string.byte(size, 1, 4)
		size = s4 * 16777216 + s3 * 65536 + s2 * 256 + s1
		dir:AddFile(path, offset, size)
	end

	LogMsg("Lua file list building of '" .. filepath .. "' took " .. SysTime() - time .. " seconds!")

	return dir
end

luapack.RootDirectory = luapack.BuildFileList("download/data/luapack/" .. luapack.CurrentHash .. ".dat")

local function GetFileFromPathStack(filepath)
	local i = 3
	local dbg = debug.getinfo(i, "S")
	while dbg do
		local path = dbg.short_src:match("^(.*[/\\])[^/\\]-$")
		if path then
			path = luapack.CanonicalizePath(path .. filepath)
			local files = luapack.RootDirectory:Get(path, false)
			if files[1] then
				return files[1]
			end
		end

		i = i + 1
		dbg = debug.getinfo(i, "S")
	end

	local files = luapack.RootDirectory:Get(luapack.CanonicalizePath(filepath), false)
	if files[1] then
		return files[1]
	end
end

local totaltime = 0

local function AddTime(time)
	totaltime = totaltime + time
end

function luapack.GetTimeSpentLoading()
	return totaltime
end

function require(module)
	local time = SysTime()

	local modulepath = "includes/modules/" .. module .. ".lua"
	local files = luapack.RootDirectory:Get(modulepath)
	if files[1] then
		local ret = RunStringEx(files[1]:GetContents(), modulepath)

		AddTime(SysTime() - time)

		return ret
	end

	DebugMsg("Couldn't require Lua module from luapack, proceeding with normal require", module)
	local ret = luapack.require(module)
	
	AddTime(SysTime() - time)

	return ret
end

function include(filepath)
	local time = SysTime()

	local file = GetFileFromPathStack(filepath)
	if file then
		local ret = RunStringEx(file:GetContents(), file:GetFullPath())

		AddTime(SysTime() - time)

		return ret
	end

	DebugMsg("Couldn't include Lua file from luapack, proceeding with normal include", filepath)
	local ret = luapack.include(filepath)

	AddTime(SysTime() - time)

	return ret
end

function CompileFile(filepath)
	local time = SysTime()

	local file = GetFileFromPathStack(filepath)
	if file then
		local ret = CompileString(file:GetContents(), file:GetFullPath(), false)

		AddTime(SysTime() - time)

		return ret
	end

	DebugMsg("Couldn't CompileFile Lua file from luapack, proceeding with normal CompileFile", filepath)
	local ret = luapack.CompileFile(filepath)

	AddTime(SysTime() - time)

	return ret
end

function file.Find(filepath, filelist, sorting)
	if filelist == "LUA" then
		local files, folders = luapack.RootDirectory:Get(luapack.CanonicalizePath(filepath))
		local simplefiles, simplefolders = luapack.fileFind(filepath, "LUA")

		for i = 1, #files do
			table.insert(simplefiles, files[i]:GetPath())
		end

		for i = 1, #folders do
			table.insert(simplefolders, folders[i]:GetPath())
		end

		return simplefiles, simplefolders
	else
		return luapack.fileFind(filepath, filelist, sorting)
	end
end

function file.Exists(filepath, filelist)
	if filelist == "LUA" then
		local files, folders = file.Find(filepath, filelist)
		return files[1] ~= nil or folders[1] ~= nil
	else
		return luapack.fileExists(filepath, filelist)
	end
end

function file.IsDir(filepath, filelist)
	if filelist == "LUA" then
		local _, folders = file.Find(filepath, filelist)
		return folders[1] ~= nil
	else
		return luapack.fileIsDir(filepath, filelist)
	end
end

---------------------------------------------------------------------

luapack.include("_init.lua")

---------------------------------------------------------------------

luapack.gamemodeRegister = luapack.gamemodeRegister or gamemode.Register

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

function luapack.LoadPostProcess()
	local files = file.Find("postprocess/*.lua", "LUA")
	for i = 1, #files do
		include("postprocess/" .. files[i])
	end
end

function luapack.LoadVGUI()
	local files = file.Find("vgui/*.lua", "LUA")
	for i = 1, #files do
		include("vgui/" .. files[i])
	end
end

function luapack.LoadMatproxy()
	local files = file.Find("matproxy/*.lua", "LUA")
	for i = 1, #files do
		include("matproxy/" .. files[i])
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

	local ent = ENT
	ENT = nil
	if ent.Base ~= name then
		luapack.LoadEntity(path, ent.Base)
	end

	scripted_ents.Register(ent, name)
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

	local swep = SWEP
	SWEP = nil
	if swep.Base ~= name then
		luapack.LoadWeapon(path, swep.Base)
	end

	weapons.Register(swep, name)
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
	EFFECT = {}

	if file.IsDir(path .. "/" .. name, "LUA") then
		include(path .. "/" .. name .. "/init.lua")
	else
		include(path .. "/" .. name .. ".lua")
	end

	effects.Register(EFFECT, name)

	EFFECT = nil
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

gamemode.Register = function(gm, name, base)
	LogMsg("Registering gamemode '" .. name .. "' with base '" .. base .. "'.")

	luapack.LoadWeapons(name .. "/entities/weapons")
	luapack.LoadEntities(name .. "/entities/entities")
	luapack.LoadEffects(name .. "/entities/effects")

	local ret = luapack.gamemodeRegister(gm, name, base)

	if name == "base" then
		luapack.LoadWeapons("weapons")
		luapack.LoadEntities("entities")
		luapack.LoadEffects("effects")

		luapack.LoadAutorun()
		luapack.LoadPostProcess()
		luapack.LoadVGUI()
		luapack.LoadMatproxy()
	end

	return ret
end