luapack = luapack or {include = include, CompileFile=CompileFile,require = require, fileFind = file.Find, FileList = {}, CurrentHash = nil}

include("hash.lua")

luapack.CurrentPackFilePath = "download/data/luapack/" .. luapack.CurrentHash .. ".dat"

include("filesystem.lua")

luapack.RootDirectory = luapack.NewRootDirectory()


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

function luapack.CanonicalizePath(path, curpath)
	curpath = curpath or ""
	path = path:lower():gsub("\\", "/"):gsub("/+", "/")
	curpath = curpath:lower():gsub("\\", "/"):gsub("/+", "/")

	local t = {}
	for str in curpath:gmatch("([^/]+)") do
		if str == ".." then
			table.remove(t)
		elseif str ~= "." and str ~= "" then
			table.insert(t, str)
		end
	end

	for str in path:gmatch("([^/]+)") do
		if str == ".." then
			table.remove(t)
		elseif str ~= "." and str ~= "" then
			table.insert(t, str)
		end
	end

	return table.concat(t, "/")
end

function luapack.BuildFileList()
	LogMsg("Starting Lua file list build!")

	local time = SysTime()

	local f = file.Open(luapack.CurrentPackFilePath, "rb", "GAME")
	if not f then
		ErrorMsg("Failed to open '" .. luapack.CurrentPackFilePath .. "' for reading")
		return
	end

	local header = f:Read(f:ReadLong())

	f:Close()

	for offset, size, filepath in header:gmatch("(....)(....)([^%z]+)") do
		local f = luapack.RootDirectory:AddFile(filepath)
		if f then
			local b1, b2, b3, b4 = string.byte(offset, 1, 4)
			f.Offset = b4 * 16777216 + b3 * 65536 + b2 * 256 + b1

			b1, b2, b3, b4 = string.byte(size, 1, 4)
			f.CompressedSize = b4 * 16777216 + b3 * 65536 + b2 * 256 + b1
		end
	end

	LogMsg("Lua file list building took " .. SysTime() - time .. " seconds!")
end

luapack.BuildFileList()

function luapack.GetContents(filepath)
	filepath = luapack.CanonicalizePath(filepath)

	local files = luapack.RootDirectory:Get(filepath)
	local filedata = files[1]
	if not filedata then
		--ErrorMsg("File doesn't exist or path canonicalization failed", filepath)
		return
	end

	local f = file.Open(luapack.CurrentPackFilePath, "rb", "GAME")
	if not f then
		ErrorMsg("Failed to open pack file for reading", luapack.CurrentPackFilePath, filepath)
		return
	end

	f:Seek(filedata.Offset)

	local data = util.Decompress(f:Read(filedata.CompressedSize) or "") or ""

	f:Close()

	return data
end

function require(module)
	-- this comes from C++ by default
	if module == "timer" then
		return luapack.require(module)
	end
	
	local modulepath = "includes/modules/" .. module .. ".lua"
	local contents = luapack.GetContents(modulepath)
	if contents then
		--DebugMsg("Successfully required module", module)
		RunStringEx(contents, modulepath)
		return
	end

	DebugMsg("Couldn't require Lua module, proceeding with normal require", path)

	return luapack.require(module)
end

local function CleanPath(path)
	return path:match("lua/(.+)$") or (path:match("^gamemodes/(.+)$") or path)
end

local function GetPathFromFilename(path)
	return path:match("^(.*[/\\])[^/\\]-$") or ""
end

function include(filepath)
	local short_src = CleanPath(debug.getinfo(2, "S").short_src)
	if short_src == "includes/util.lua" then
		short_src = CleanPath(debug.getinfo(3, "S").short_src)
	end

	local path = GetPathFromFilename(short_src) .. filepath
	local contents = luapack.GetContents(path)
	if not contents then
		path = filepath
		contents = luapack.GetContents(path)
	end

	if contents then
		--DebugMsg("Successfully included file", path)
		RunStringEx(contents, path)
		return
	end

	DebugMsg("Couldn't include Lua file, proceeding with normal include", path)

	luapack.include(filepath)
end

function CompileFile(filepath)
	local short_src = CleanPath(debug.getinfo(2, "S").short_src)
	if short_src == "includes/util.lua" then
		short_src = CleanPath(debug.getinfo(3, "S").short_src)
	end

	local path = GetPathFromFilename(short_src) .. filepath
	local contents = luapack.GetContents(path)
	if not contents then
		path = filepath
		contents = luapack.GetContents(path)
	end

	local f
	if contents then
		--DebugMsg("Successfully compiled file", path)
		f = CompileString(contents, path, false)
		if isfunction(f) then
			return f
		end
	end

	DebugMsg("Couldn't CompileString Lua file, proceeding with normal include", path)

	return luapack.CompileFile(filepath)
end

function file.Find(filepath, filelist, sorting)
	if filelist == "LUA" then
		local files, folders = luapack.RootDirectory:Get(luapack.CanonicalizePath(filepath))
		local simplefiles, simplefolders = {}, {}

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

include	"includes/real_init.lua"
include "luapack/autoloader.lua"