local currenthash = GetConVarString("luapack_hash")
if not currenthash or #currenthash == 0 then
	error("unable to retrieve current file hash, critical luapack error")
end

LogMsg("Found the current pack file hash ('" .. currenthash .. "')!")

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

local CRC_FAIL = -1
local CRC_NOT_CHECKED = 0
local CRC_SUCCESS = 1
function FILE:GetContents()
	local f = self.__file
	f:Seek(self.__offset)
	local data = f:Read(self.__size)
	if data then
		data = util.Decompress(data)
	end

	data = data or ""

	if self.__crc_checked == CRC_NOT_CHECKED then
		self.__crc_checked = tonumber(util.CRC(data)) ~= self.__crc and CRC_FAIL or CRC_SUCCESS
	end

	if self.__crc_checked == CRC_FAIL then
		error("CRC not matching for file '" .. self:GetFullPath() .. "'")
	end

	return data
end

function FILE:AddFile(name)
	error("what the hell do you think you're doing man")
end

FILE.AddDirectory = FILE.AddFile
FILE.Get = FILE.AddFile
FILE.GetSingle = FILE.AddFile
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
		local obj = self:GetSingle(cur)
		if not obj then
			local file = setmetatable({
				__path = cur,
				__offset = offset,
				__size = size,
				__crc = crc,
				__crc_checked = CRC_NOT_CHECKED,
				__parent = self,
				__file = self.__file
			}, FILE)
			table.insert(self:GetList(), file)
			return file
		end

		return obj:IsFile() and obj or nil
	else
		local obj = self:GetSingle(cur)
		if not obj then
			obj = self:AddDirectory(cur)
		end

		return obj:IsDirectory() and obj:AddFile(rest, offset, size, crc) or nil
	end
end

function DIRECTORY:AddDirectory(path)
	local single, cur, rest = GetPathParts(path)
	if single then
		local obj = self:GetSingle(cur)
		if not obj then
			local dir = setmetatable({
				__path = cur,
				__parent = self,
				__file = self.__file,
				__list = {}
			}, DIRECTORY)
			table.insert(self:GetList(), dir)
			return dir
		end

		return obj:IsDirectory() and obj or nil
	else
		local obj = self:GetSingle(cur)
		if not obj then
			obj = self:AddDirectory(cur)
		end

		return obj:IsDirectory() and obj:AddDirectory(rest) or nil
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

function DIRECTORY:GetSingle(path, pattern)
	pattern = pattern or false

	local single, cur, rest = GetPathParts(path)

	for elem in self:GetIterator() do
		if (pattern and elem:GetPath():find(cur)) or elem:GetPath() == cur then
			if not single then
				if elem:IsDirectory() then
					return elem:GetSingle(rest, pattern)
				end
			else
				return elem
			end
		end
	end
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

local band, bor, blshift, brshift = bit.band, bit.bor, bit.lshift, bit.rshift
local function ReadULong(f)
	local b1, b2, b3, b4 = f:ReadByte(), f:ReadByte(), f:ReadByte(), f:ReadByte()
	local n = band(bor(blshift(b4, 24), blshift(b3, 16), blshift(b2, 8), b1), 0x7FFFFFFF)
	return brshift(b4, 7) == 1 and n + 0x80000000 or n
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
		error("failed to open pack file '" .. filepath .. "' for reading")
	end

	local dir = setmetatable({__file = f, __list = {}}, DIRECTORY)

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

local function GetFileFromPathStack(filepath)
	local i = 3
	local dbg = debug.getinfo(i, "S")
	while dbg do
		local path = dbg.source:match("^@?(.*)[/\\][^/\\]-$") or dbg.source:match("^@?(.*)$")
		if #path == 0 then
			path = filepath
		else
			path = path .. "/" .. filepath
		end

		local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(path))
		if obj and obj:IsFile() then
			return obj
		end

		i = i + 1
		dbg = debug.getinfo(i, "S")
	end

	local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath))
	if obj and obj:IsFile() then
		return obj
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
	local obj = luapack.RootDirectory:GetSingle(modulepath)
	if obj and obj:IsFile() then
		if package.loaded[module] then
			DebugMsg("Module already loaded '" .. module .. "'")
			return
		end

		local ret = CompileString(obj:GetContents(), modulepath)()

		if not package.loaded[module] then
			local pkg = {
				_NAME = module,
				_PACKAGE = "",
				_LUAPACK = true
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

local function namedesc(a, b)
	return a > b
end

function file.Find(filepath, filelist, sorting)
	if filelist == "LUA" then
		sorting = sorting or "nameasc"

		local files, folders = luapack.RootDirectory:Get(luapack.CanonicalizePath(filepath))
		local simplefiles, simplefolders = luapack.fileFind(filepath, filelist, sorting)

		for i = 1, #files do
			table.insert(simplefiles, files[i]:GetPath())
		end

		for i = 1, #folders do
			table.insert(simplefolders, folders[i]:GetPath())
		end

		if sorting == "namedesc" then
			table.sort(simplefiles, namedesc)
			table.sort(simplefolders, namedesc)
		else
			table.sort(simplefiles)
			table.sort(simplefolders)
		end

		return simplefiles, simplefolders
	else
		return luapack.fileFind(filepath, filelist, sorting)
	end
end

function file.Exists(filepath, filelist)
	if filelist == "LUA" then
		return luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath)) ~= nil
	else
		return luapack.fileExists(filepath, filelist)
	end
end

function file.IsDir(filepath, filelist)
	if filelist == "LUA" then
		local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath))
		return obj ~= nil and obj:IsDirectory()
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

function luapack.LoadWeapon(obj)
	local name = obj:IsDirectory() and obj:GetPath() or RemoveExtension(obj:GetPath())

	SWEP = {
		Base = "weapon_base",
		Primary = {},
		Secondary = {}
	}

	if obj:IsDirectory() then
		SWEP.Folder = obj:GetFullPath()

		local file = obj:GetSingle("cl_init.lua")
		if not file or file:IsDirectory() then
			file = obj:GetSingle("shared.lua")
		end

		if file and file:IsFile() then
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

function luapack.LoadEntity(obj)
	local name = obj:IsDirectory() and obj:GetPath() or RemoveExtension(obj:GetPath())

	ENT = {}

	if obj:IsDirectory() then
		ENT.Folder = obj:GetFullPath()

		local file = obj:GetSingle("cl_init.lua")
		if not file or file:IsDirectory() then
			file = obj:GetSingle("shared.lua")
		end

		if file and file:IsFile() then
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

function luapack.LoadEffect(obj)
	local name = obj:IsDirectory() and obj:GetPath() or RemoveExtension(obj:GetPath())

	EFFECT = {}

	if obj:IsDirectory() then
		EFFECT.Folder = obj:GetFullPath()

		local file = obj:GetSingle("init.lua")
		if file and file:IsFile() then
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