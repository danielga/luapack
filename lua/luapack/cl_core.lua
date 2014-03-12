luapack = luapack or {include = include, require = require, fileFind = file.Find, FileList = {}, CurrentHash = nil}

include("hash.lua")

luapack.CurrentPackFilePath = "download/data/luapack/" .. luapack.CurrentHash .. ".dat"

function luapack.CanonicalizePath(path, curpath)
	curpath = curpath or ""
	path = path:gsub("\\", "/"):gsub("/+", "/")
	curpath = curpath:gsub("\\", "/"):gsub("/+", "/")

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

function luapack.BreakdownPath(filepath)
	local tab = {}
	for part in filepath:gmatch("([^/]+)") do
		table.insert(tab, part)
	end

	return tab
end

function luapack.BuildFileList()
	print("[luapack] Starting Lua file list build!")

	local time = SysTime()

	local f = file.Open(luapack.CurrentPackFilePath, "rb", "GAME")
	if not f then error("failed to open '" .. luapack.CurrentPackFilePath .. "' for reading") end

	local header = f:Read(f:ReadLong())

	f:Close()

	local lastoffset = 0
	for piece in header:gmatch("(....[^%z]+)%z") do
		local b1, b2, b3, b4 = string.byte(piece, 1, 4)
		local offset = b4 * 16777216 + b3 * 65536 + b2 * 256 + b1
		local filepath = piece:sub(5)

		luapack.FileList[filepath] = {Offset = offset, CompressedSize = offset - lastoffset}

		lastoffset = offset
	end

	print("[luapack] Lua file list building took " .. SysTime() - time .. " seconds!")
end

luapack.BuildFileList()

function luapack.GetContents(filepath)
	filepath = luapack.CanonicalizePath(filepath)

	local filedata = luapack.FileList[filepath]
	if not filedata then
		return
	end

	local f = file.Open(luapack.CurrentPackFilePath, "rb", "GAME")
	if not f then
		return
	end

	f:Seek(filedata.Offset)

	local data = util.Decompress(f:Read(filedata.CompressedSize) or "")

	f:Close()

	return data
end

local function GetCurrentFolder()
	local info = debug.getinfo(3, "S")
	if info.short_src == "includes/util.lua" then
		info = debug.getinfo(4, "S")
	end

	return string.GetPathFromFilename(info.short_src)
end

function include(filepath)
	local contents = luapack.GetContents(filepath)
	if contents then
		print(filepath)
		RunStringEx(contents, filepath)
		return
	end

	luapack.include(filepath)
end

function require(module)
	local modulepath = "includes/modules/" .. module .. ".lua"
	local contents = luapack.GetContents(modulepath)
	if contents then
		print(modulepath)
		RunStringEx(contents, modulepath)
		return
	end

	return luapack.require(module)
end

local function GlobToPattern(glob)
	local pattern = {"^"}

	for i = 1, #glob do
		local ch = glob:sub(i, i)

		if ch == "*" then
			ch = "[^/]*"
		else
			ch = ch:find("^%w$") and ch or "%" .. ch
		end

		table.insert(pattern, ch)
	end

	return table.concat(pattern)
end

function file.Find(filepath, filelist, sorting)
	if filelist == "LUA" then
		filepath = luapack.CanonicalizePath(filepath)

		local pattern = GlobToPattern(filepath)
		local files, folders = {}, {}

		for path, data in pairs(luapack.FileList) do
			path = path:match(pattern)
			if not path then
				continue
			end

			path = path:match("([^/]+)$")
			if path and not files[path] then
				files[path] = path
			end
		end

		return files, folders
	else
		return luapack.fileFind(filepath, filelist, sorting)
	end
end