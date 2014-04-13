luapack = luapack or {
	include = include,
	CompileFile = CompileFile,
	require = require,
	fileFind = file.Find,
	fileExists = file.Exists,
	fileIsDir = file.IsDir,
	FileList = {},
	CurrentHash = nil
}

luapack.include("hash.lua")

luapack.CurrentPackFilePath = "download/data/luapack/" .. luapack.CurrentHash .. ".dat"

luapack.include("filesystem.lua")

luapack.RootDirectory = luapack.NewRootDirectory()

local red = {r = 255, g = 0, b = 0, a = 255}
function luapack.ErrorMsg(...)
	MsgC(red, "[LuaPack] ")
	print(...)
end

local green = {r = 0, g = 255, b = 0, a = 255}
function luapack.LogMsg(...)
	MsgC(green, "[LuaPack] ")
	print(...)
end

local yellow = {r = 255, g = 255, b = 0, a = 255}
function luapack.DebugMsg(...)
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
	luapack.LogMsg("Starting Lua file list build!")

	local time = SysTime()

	local f = file.Open(luapack.CurrentPackFilePath, "rb", "GAME")
	if not f then
		luapack.ErrorMsg("Failed to open current pack file for reading", luapack.CurrentPackFilePath)
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

	luapack.LogMsg("Lua file list building took " .. SysTime() - time .. " seconds!")
end

luapack.BuildFileList()

function luapack.GetContents(filepath)
	filepath = luapack.CanonicalizePath(filepath)

	local files = luapack.RootDirectory:Get(filepath)
	local filedata = files[1]
	if not filedata then
		return
	end

	local f = file.Open(luapack.CurrentPackFilePath, "rb", "GAME")
	if not f then
		luapack.ErrorMsg("Failed to open pack file for reading", luapack.CurrentPackFilePath, filepath)
		return
	end

	f:Seek(filedata.Offset)

	local data = util.Decompress(f:Read(filedata.CompressedSize) or "") or ""

	f:Close()

	return data
end

function require(module)
	local modulepath = "includes/modules/" .. module .. ".lua"
	local contents = luapack.GetContents(modulepath)
	if contents then
		RunStringEx(contents, modulepath)
		return
	end

	luapack.DebugMsg("Couldn't require Lua module, proceeding with normal require", module)
	return luapack.require(module)
end

local function CleanPath(path)
	return path:match("lua/(.+)$") or (path:match("^gamemodes/(.+)$") or path)
end

local function GetPathFromFilename(path)
	return path:match("^(.*[/\\])[^/\\]-$") or ""
end

local function GetPathFromStack(filepath)
	local i = 3
	local dbg = debug.getinfo(i, "S")
	while dbg do
		local path = GetPathFromFilename(dbg.short_src) .. filepath
		if file.Exists(path, "LUA") then
			return path
		end

		i = i + 1
		dbg = debug.getinfo(i, "S")
	end
end

function include(filepath)
	local path = GetPathFromStack(filepath)
	if path then
		local contents = luapack.GetContents(path)
		if contents then
			return RunStringEx(contents, path)
		end
	end

	luapack.DebugMsg("Couldn't include Lua file from luapack, proceeding with normal include", filepath)
	return luapack.include(filepath)
end

function CompileFile(filepath)
	local path = GetPathFromStack(filepath)
	if path then
		local contents = luapack.GetContents(path)
		if contents then
			return CompileString(contents, path, false)
		end
	end

	luapack.DebugMsg("Couldn't CompileFile Lua file from luapack, proceeding with normal CompileFile", path)
	return luapack.CompileFile(filepath)
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

luapack.include("includes/real_init.lua")
luapack.include("autoloader.lua")