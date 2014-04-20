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

		local tcrc = tonumber(util.CRC(data))
		if tcrc ~= self.__crc then
			error("CRC not matching for file '" .. self:GetFullPath() .. "'")
		end
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

function DIRECTORY:AddFile(path, offset, size, crc)
	local single, cur, rest = GetPathParts(path)
	if single then
		local files, dirs = self:Get(cur, false)
		if not files[1] and not dirs[1] then
			local file = setmetatable({
				__path = cur,
				__offset = offset,
				__size = size,
				__crc = crc,
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

		return dir:AddFile(rest, offset, size, crc)
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

local function CreateRootDirectory(f)
	return setmetatable({__file = f, __list = {}}, DIRECTORY)
end

local function BytesToULong(b1, b2, b3, b4)
	return b4 * 16777216 + b3 * 65536 + b2 * 256 + b1
end

local function ReadULong(f)
	return BytesToULong(f:ReadByte(), f:ReadByte(), f:ReadByte(), f:ReadByte())
end

local function ReadString(f)
	local tab = {}
	local n = f:ReadByte()
	local c = string.char(n)
	while n ~= 0 do
		table.insert(tab, c)

		n = f:ReadByte()
		c = string.char(n)
	end

	return table.concat(tab)
end

function luapack.BuildFileList(filepath)
	LogMsg("Starting Lua file list build of '" .. filepath .. "'!")

	local time = SysTime()

	local f = file.Open(filepath, "rb", "GAME")
	if not f then
		error("Failed to open current pack file for reading '" .. filepath .. "'")
		return
	end

	local dir = CreateRootDirectory(f)

	local fsize = f:Size()
	local offset = 0
	while offset < fsize do
		local size = ReadULong(f)
		local crc = ReadULong(f)
		local path = ReadString(f)

		dir:AddFile(path, f:Tell(), size, crc)

		offset = offset + 4 + 4 + #path + 1 + size
		
		f:Seek(offset)
	end

	LogMsg("Lua file list building of '" .. filepath .. "' took " .. SysTime() - time .. " seconds!")

	return dir
end

luapack.RootDirectory = luapack.BuildFileList("download/data/luapack/" .. luapack.CurrentHash .. ".dat")

local function GetFileFromPathStack(filepath)
	local i = 3
	local dbg = debug.getinfo(i, "S")
	while dbg do
		local path = dbg.source:match("^@?(.*)[/\\][^/\\]-$") or dbg.source:match("^@?(.*)$")
		if path == "" then
			path = filepath
		else
			path = path .. "/" .. filepath
		end
		path = luapack.CanonicalizePath(path)
		local files = luapack.RootDirectory:Get(path, false)
		if files[1] then
			return files[1]
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
		if package.loaded[module] then
			DebugMsg("Module already loaded '" .. module .. "'")
			return
		end

		local ret = CompileString(files[1]:GetContents(), modulepath)()

		if not package.loaded[module] then
			local pkg = {
				_NAME = module,
				_PACKAGE = "",
				_luapack = true
			}

			pkg._M = pkg

			local gmodule = _G[module]
			if gmodule then
				for k, v in pairs(gmodule) do
					pkg[k] = v
				end
			end

			package.loaded[module] = pkg
		end

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
		CompileString(file:GetContents(), file:GetFullPath())()

		AddTime(SysTime() - time)

		return
	end

	DebugMsg("Couldn't include Lua file from luapack, proceeding with normal include", filepath)

	luapack.include(filepath)

	AddTime(SysTime() - time)
end

function CompileFile(filepath)
	local time = SysTime()

	local file = GetFileFromPathStack(filepath)
	if file then
		local ret = CompileString(file:GetContents(), file:GetFullPath())

		AddTime(SysTime() - time)

		return ret
	end

	DebugMsg("Couldn't CompileFile Lua file from luapack, proceeding with normal CompileFile", filepath)

	local ret = luapack.CompileFile(filepath)

	AddTime(SysTime() - time)

	return ret
end

local sorting_functions = {
	nameasc = function(a, b)
		return a < b
	end,
	namedesc = function(a, b)
		return a > b
	end
}

function file.Find(filepath, filelist, sorting)
	if filelist == "LUA" then
		sorting = sorting or "nameasc"

		local files, folders = luapack.RootDirectory:Get(luapack.CanonicalizePath(filepath))
		local simplefiles, simplefolders = luapack.fileFind(filepath, "LUA")

		for i = 1, #files do
			table.insert(simplefiles, files[i]:GetPath())
		end

		for i = 1, #folders do
			table.insert(simplefolders, folders[i]:GetPath())
		end

		local sort = sorting_functions[sorting]
		if sort then
			table.sort(simplefiles, sort)
			table.sort(simplefolders, sort)
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

include("_init.lua")

---------------------------------------------------------------------

luapack.gamemodeRegister = luapack.gamemodeRegister or gamemode.Register
luapack.weaponsOnLoaded = luapack.weaponsOnLoaded or weapons.OnLoaded
luapack.scripted_entsOnLoaded = luapack.scripted_entsOnLoaded or scripted_ents.OnLoaded

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

local weapons_dir = CreateRootDirectory()
function luapack.LoadWeapon(obj)
	local name = obj:IsDirectory() and obj:GetPath() or RemoveExtension(obj:GetPath())

	SWEP = {
		Base = "weapon_base",
		Primary = {},
		Secondary = {}
	}

	if obj:IsDirectory() then
		SWEP.Folder = obj:GetFullPath()

		local files = obj:Get("cl_init.lua", false)
		local file = files[1]
		if file then
			CompileString(file:GetContents(), file:GetFullPath())()
		end

		files = obj:Get("shared.lua", false)
		file = files[1]
		if file then
			CompileString(file:GetContents(), file:GetFullPath())()
		end
	else
		SWEP.Folder = obj:GetParent():GetFullPath()

		CompileString(obj:GetContents(), obj:GetFullPath())()
	end

	weapons.Register(SWEP, name)

	SWEP = nil
end

function luapack.LoadWeapons()
	local files, folders = luapack.RootDirectory:Get("weapons/*")
	for i = 1, #files do
		luapack.LoadWeapon(files[i])
	end

	for i = 1, #folders do
		luapack.LoadWeapon(folders[i])
	end
end

local entities_dir = CreateRootDirectory()
function luapack.LoadEntity(obj)
	local name = obj:IsDirectory() and obj:GetPath() or RemoveExtension(obj:GetPath())

	ENT = {}

	if obj:IsDirectory() then
		ENT.Folder = obj:GetFullPath()

		local files = obj:Get("cl_init.lua", false)
		local file = files[1]
		if file then
			CompileString(file:GetContents(), file:GetFullPath())()
		end

		files = obj:Get("shared.lua", false)
		file = files[1]
		if file then
			CompileString(file:GetContents(), file:GetFullPath())()
		end
	else
		ENT.Folder = obj:GetParent():GetFullPath()

		CompileString(obj:GetContents(), obj:GetFullPath())()
	end

	scripted_ents.Register(ENT, name)

	ENT = nil
end

function luapack.LoadEntities()
	local files, folders = luapack.RootDirectory:Get("entities/*")
	for i = 1, #files do
		luapack.LoadEntity(files[i])
	end

	for i = 1, #folders do
		luapack.LoadEntity(folders[i])
	end
end

local effects_dir = CreateRootDirectory()
function luapack.LoadEffect(obj)
	local name = obj:IsDirectory() and obj:GetPath() or RemoveExtension(obj:GetPath())

	EFFECT = {}

	if obj:IsDirectory() then
		EFFECT.Folder = obj:GetFullPath()

		local files = obj:Get("init.lua", false)
		local file = files[1]
		if file then
			CompileString(file:GetContents(), file:GetFullPath())()
		end
	else
		EFFECT.Folder = obj:GetParent():GetFullPath()

		CompileString(obj:GetContents(), obj:GetFullPath())()
	end

	effects.Register(EFFECT, name)

	EFFECT = nil
end

function luapack.LoadEffects()
	local files, folders = luapack.RootDirectory:Get("effects/*")
	for i = 1, #files do
		luapack.LoadEffect(files[i])
	end

	for i = 1, #folders do
		luapack.LoadEffect(folders[i])
	end
end

gamemode.Register = function(gm, name, base)
	LogMsg("Registering gamemode '" .. name .. "' with base '" .. base .. "'.")

	local ret = luapack.gamemodeRegister(gm, name, base)

	if name == "base" then
		luapack.LoadAutorun()
		luapack.LoadPostProcess()
		luapack.LoadVGUI()
		luapack.LoadMatproxy()

		-- these use a very simple system, no inheritance, no nothing
		-- let's hope we can load them directly
		-- load them after base just to be safe
		luapack.LoadEffects()
	end

	return ret
end

function weapons.OnLoaded()
	luapack.LoadWeapons()
	return luapack.weaponsOnLoaded()
end

function scripted_ents.OnLoaded()
	luapack.LoadEntities()
	return luapack.scripted_entsOnLoaded()
end