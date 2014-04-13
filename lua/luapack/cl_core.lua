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
	local files = luapack.RootDirectory:Get(filepath)
	local filedata = files[1]
	if not filedata then
		return
	end

	local f = file.Open(luapack.CurrentPackFilePath, "rb", "GAME")
	if not f then
		luapack.ErrorMsg("Failed to open pack file for reading", luapack.CurrentPackFilePath)
		return
	end

	f:Seek(filedata.Offset)

	local data = util.Decompress(f:Read(filedata.CompressedSize) or "") or ""

	f:Close()

	return data
end

local function GetPathFromStack(filepath)
	local i = 3
	local dbg = debug.getinfo(i, "S")
	while dbg do
		local path = dbg.short_src:match("^(.*[/\\])[^/\\]-$")
		if path then
			path = luapack.CanonicalizePath(path .. filepath)
			local files = luapack.RootDirectory:Get(path, false)
			if files[1] ~= nil then
				return path
			end
		end

		i = i + 1
		dbg = debug.getinfo(i, "S")
	end

	local files = luapack.RootDirectory:Get(luapack.CanonicalizePath(filepath), false)
	if files[1] ~= nil then
		return filepath
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
	local contents = luapack.GetContents(modulepath)
	if contents then
		local ret = RunStringEx(contents, modulepath)

		AddTime(SysTime() - time)

		return ret
	end

	luapack.DebugMsg("Couldn't require Lua module from luapack, proceeding with normal require", module)
	local ret = luapack.require(module)
	
	AddTime(SysTime() - time)

	return ret
end

function include(filepath)
	local time = SysTime()

	local path = GetPathFromStack(filepath)
	if path then
		local contents = luapack.GetContents(path)
		if contents then
			local ret = RunStringEx(contents, path)

			AddTime(SysTime() - time)

			return ret
		end
	end

	luapack.DebugMsg("Couldn't include Lua file from luapack, proceeding with normal include", filepath)
	local ret = luapack.include(filepath)

	AddTime(SysTime() - time)

	return ret
end

function CompileFile(filepath)
	local time = SysTime()

	local path = GetPathFromStack(filepath)
	if path then
		local contents = luapack.GetContents(path)
		if contents then
			local ret = CompileString(contents, path, false)

			AddTime(SysTime() - time)

			return ret
		end
	end

	luapack.DebugMsg("Couldn't CompileFile Lua file from luapack, proceeding with normal CompileFile", filepath)
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

luapack.include("includes/real_init.lua")
luapack.include("autoloader.lua")