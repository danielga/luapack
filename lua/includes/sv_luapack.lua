AddCSLuaFile("_init.lua")

if not file.IsDir("luapack", "DATA") then
	file.CreateDir("luapack")
end

-- for the hook module, no need to include util.lua and all the trash it brings
function IsValid(object)
	return object and object.IsValid and object:IsValid()
end

require("hook")
require("addcs")
require("crypt")
require("luaiox")

luapack = luapack or {Bypass = false, FileList = {}, FinishedAdding = false}

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

function luapack.AddCSLuaFile(path)
	luapack.Bypass = true
	AddCSLuaFile(path)
	luapack.Bypass = false
end

function luapack.IsBlacklistedFile(filepath)
	return	filepath == "derma/init.lua" or
			filepath == "skins/default.lua" or
			filepath:match("^([^/]*)/gamemode/cl_init.lua")
end

function luapack.AddFile(filepath)
	if luapack.FinishedAdding then
		ErrorMsg("luapack.AddFile called after InitPostEntity was called '" .. filepath .. "'")
		return false
	end

	filepath = luapack.CanonicalizePath(filepath)
	if not file.Exists(filepath, "LUA") then
		ErrorMsg("File doesn't exist (unable to add it to file list) '" .. filepath .. "'.")
		return false
	end

	if luapack.IsBlacklistedFile(filepath) then
		DebugMsg("Adding file through normal AddCSLuaFile '" .. filepath .. "'.")
		luapack.AddCSLuaFile(filepath)
		return true
	end

	table.insert(luapack.FileList, filepath)
	return true
end

hook.Add("AddOrUpdateCSLuaFile", "luapack addcsluafile detour", function(path, reload)
	return (not reload and not luapack.Bypass and luapack.AddFile(path)) and true or nil
end)

local function ReadFile(filepath, pathlist)
	local f = file.Open(filepath, "rb", pathlist)
	if f then
		local data = f:Read(f:Size()) or ""
		f:Close()
		return data
	else
		ErrorMsg("ReadFile failed", filepath, pathlist)
	end
end

local send = ReadFile("_send.txt", "LUA")
for line in send:gmatch("([^\r\n]+)\r?\n") do
	if line:sub(1, 1) == "#" then
		continue
	end

	luapack.AddFile(line)
end

local function StringToHex(str)
	local byte = string.byte
	local strfmt = "%02X"
	local parts = {}
	for i = 1, #str do
		table.insert(parts, strfmt:format(byte(str:sub(i, i))))
	end

	return table.concat(parts)
end

hook.Add("InitPostEntity", "luapack resource creation", function()
	hook.Remove("InitPostEntity", "luapack resource creation")

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
		io.rename("garrysmod/data/" .. luapacktemp, "garrysmod/" .. fullcurrentpath)
	else
		DebugMsg("Deleting obsolete temporary file")
		file.Delete(luapacktemp)
	end

	resource.AddFile(fullcurrentpath)

	local path = debug.getinfo(1, "S").short_src:match("^(.*[/\\])[^/\\]-$")
	if path then
		local f = io.open("garrysmod/" .. path .. "cl_luapack.lua", "r+")
		if f then
			-- the size of the string is always the same as long as we keep using SHA-1, 62 bytes
			f:write("local currenthash = \"" .. luapack.CurrentHash .. "\"")
			f:close()
		end
	end

	luapack.AddCSLuaFile("includes/cl_luapack.lua")

	luapack.FinishedAdding = true

	LogMsg("Pack building took " .. SysTime() - time .. " seconds!")
end)

include("_init.lua")