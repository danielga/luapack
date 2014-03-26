AddCSLuaFile("cl_core.lua")
AddCSLuaFile("filesystem.lua")
AddCSLuaFile("autoloader.lua")
AddCSLuaFile("hash.lua")

-- for the hook module, no need to include util.lua and all the trash it brings
function IsValid(object)
	return object and object.IsValid and object:IsValid()
end

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

require("hook")
require("addcs")
require("crypt")
require("luaiox")

luapack = luapack or {AddCSLuaFile = AddCSLuaFile, FileList = {}, FinishedAdding = false}

if not file.IsDir("luapack", "DATA") then
	file.CreateDir("luapack")
end

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

function luapack.AddFile(filepath)
	if luapack.FinishedAdding then
		ErrorMsg("luapack.AddFile called after InitPostEntity was called '" .. filepath .. "'")
		return false
	end

	filepath = luapack.CanonicalizePath(filepath)

	local initial = filepath:match("^([^/]+)/")
	filepath = filepath:sub(#initial + 2)
	if initial == "addons" then
		local _, fin = filepath:find("/lua/")
		filepath = filepath:sub(fin + 1)
	end

	if not file.Exists(filepath, "LUA") then
		return false
	end

	table.insert(luapack.FileList, filepath)

	return true
end

hook.Add("AddOrUpdateCSLuaFile", "luapack addcsluafile detour", function(path, reload)
	return (not reload and luapack.AddFile(path)) and true or nil
end)

local function ReadFile(filepath, pathlist)
	local f = file.Open(filepath, "rb", pathlist)
	if f then
		--DebugMsg("ReadFile", filepath, pathlist)

		local data = f:Read(f:Size()) or ""
		f:Close()
		return data
	else
		ErrorMsg("ReadFile failed", filepath, pathlist)
	end
end

-- relative to lua folder, gamemodes are relative to lua as well
function luapack.ParseSendFile(filepath)
	local send = ReadFile(filepath, "LUA")
	if send then
		for line in send:gmatch("([^\r\n]+)\r?\n") do
			if line:sub(1, 1) == "#" then
				continue
			end

			luapack.AddFile(line)
		end
	end
end

luapack.ParseSendFile("_send.txt")

local function StringToHex(str)
	local byte = string.byte
	local strfmt = "%02X"
	local parts = {}
	for i = 1, #str do
		table.insert(parts, strfmt:format(byte(str:sub(i, i))))
	end

	return table.concat(parts)
end

local function WriteFile(filepath, str)
	local f = io.open(filepath, "wb")
	if f then
		DebugMsg("WriteFile", filepath)

		f:write(str)
		f:close()
	else
		ErrorMsg("WriteFile failed", filepath)
	end
end

local function RenameFile(from, to)
	local ok = io.rename(from, to)

	if ok then
		DebugMsg("RenameFile", from, to)
	else
		ErrorMsg("RenameFile failed", from, to)
	end

	return ok
end

function luapack.Build()
	LogMsg("Building pack...")
	
	local time = SysTime()

	local luapacktemp = "luapack/temp.dat"

	local f = file.Open(luapacktemp, "wb", "DATA")
	if not f then
		ErrorMsg("Failed to open '" .. luapacktemp .. "' for writing")
		return
	end

	local h = crypt.sha1()
	if not h then
		ErrorMsg("Failed to create SHA-1 hasher object")
		return
	end

	local headersize = 0
	for i = 1, #luapack.FileList do
		headersize = headersize + 4 + 4 + #luapack.FileList[i] + 1
	end

	f:WriteLong(headersize)

	local offset = 4 + headersize
	for i = 1, #luapack.FileList do
		local filepath = luapack.FileList[i]

		local data = ReadFile(filepath, "LUA")
		local datalen = #data
		if datalen > 0 then
			h:Update(data)
			data = util.Compress(data)
			datalen = #data
		end

		f:WriteLong(offset)
		f:WriteLong(datalen)
		f:Write(filepath)
		f:WriteByte(0)

		if datalen > 0 then
			local getback = f:Tell()
			f:Seek(offset)
			f:Write(data)
			f:Seek(getback)
		end

		offset = offset + datalen
	end

	f:Close()

	luapack.CurrentHash = StringToHex(h:Final())

	local currentpath = "luapack/" .. luapack.CurrentHash .. ".dat"
	local fullcurrentpath = "data/" .. currentpath
	if not file.Exists(currentpath, "DATA") then
		RenameFile("garrysmod/data/" .. luapacktemp, "garrysmod/" .. fullcurrentpath)

		-- hash.lua will be written on the same folder as the other luapack Lua files
		local hashpath = "garrysmod/" .. string.GetPathFromFilename(debug.getinfo(1, "S").short_src)
		WriteFile(hashpath .. "hash.lua", "luapack.CurrentHash = \"" .. luapack.CurrentHash .. "\"")
	else
		DebugMsg("Deleting obsolete temporary file")
		file.Delete(luapacktemp)
	end

	resource.AddFile(fullcurrentpath)

	luapack.FinishedAdding = true

	LogMsg("Pack building took " .. SysTime() - time .. " seconds!")
end

hook.Add("InitPostEntity", "luapack resource creation", function()
	hook.Remove("InitPostEntity", "luapack resource creation")
	luapack.Build()
end)

AddCSLuaFile("includes/real_init.lua")
include("includes/real_init.lua")