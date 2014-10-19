AddCSLuaFile("sh_core.lua")
AddCSLuaFile("cl_core.lua")
AddCSLuaFile("cl_file.lua")
AddCSLuaFile("cl_directory.lua")
AddCSLuaFile("cl_overrides.lua")
AddCSLuaFile("cl_entities.lua")
AddCSLuaFile("includes/_init.lua")

if not file.IsDir("luapack", "DATA") then
	file.CreateDir("luapack")
end

include("sh_core.lua")

luapack.Bypass = false
luapack.FileList = {}
luapack.FinishedAdding = false

require("luapack_internal")

-- for the hook module, no need to include util.lua and all the trash it brings
function IsValid(object)
	return object and object.IsValid and object:IsValid()
end

require("hook")

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
		luapack.DebugMsg("luapack.AddFile called after InitPostEntity was called '" .. filepath .. "'")
		return false
	end

	filepath = luapack.CanonicalizePath(filepath)
	if not file.Exists(filepath, "LUA") then
		luapack.DebugMsg("File doesn't exist (unable to add it to file list) '" .. filepath .. "'.")
		return false
	end

	if luapack.IsBlacklistedFile(filepath) then
		luapack.DebugMsg("Adding file through normal AddCSLuaFile '" .. filepath .. "'.")
		luapack.AddCSLuaFile(filepath)
		return true
	end

	for i = 1, #luapack.FileList do
		if luapack.FileList[i] == filepath then
			return true
		end
	end

	table.insert(luapack.FileList, filepath)

	return true
end

hook.Add("AddOrUpdateCSLuaFile", "luapack addcsluafile detour", function(path, reload)
	return (not reload and not luapack.Bypass and luapack.AddFile(path)) and true or nil
end)

local function ReadFile(filepath)
	local f = file.Open(filepath, "rb", "LUA")
	if f then
		local data = f:Read(f:Size()) or ""
		f:Close()
		return data
	else
		error("ReadFile failed '" .. filepath .. "' - '" .. pathlist .. "'")
	end
end

local send = ReadFile("_send.txt")
for line in send:gmatch("([^\r\n]+)\r?\n") do
	if line:sub(1, 1) ~= "#" then
		luapack.AddFile(line)
	end
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

local gamemode_priority
local function GetPriority(path1, path2)
	if not gamemode_priority then
		gamemode_priority = {}

		local gm = GAMEMODE
		while gm do
			table.insert(gamemode_priority, gm.FolderName)
			gm = gm.BaseClass
		end
	end

	local gm1, rpath1, gm1p = path1:match("^([^/]+)/entities/(.+)$")
	if not gm1 then
		return 0
	end

	local gm2, rpath2, gm2p = path2:match("^([^/]+)/entities/(.+)$")
	if not gm2 then
		return 0
	end

	if rpath1 ~= rpath2 then
		return 0
	end

	for i = 1, #gamemode_priority do
		if not gm1p and gamemode_priority[i] == gm1 then
			gm1p = i
		end

		if not gm2p and gamemode_priority[i] == gm2 then
			gm2p = i
		end

		if gm1p and gm2p then
			break
		end
	end

	if not gm1p or not gm2p then
		error("OY VEY, WE GOT A BAD GAMEMODE? " .. gm1 .. " - " .. gm2)
	end

	if gm1p > gm2p then
		return 1
	elseif gm1p < gm2p then
		return -1
	end

	error("gamemode 1 priority is the same as gamemode 2 priority? OY VEY! " .. gm1 .. " - " .. gm2 .. " - " .. rpath1 .. " - " .. rpath2)
end

local function CleanFileList(list)
	local listsize = #list
	local i = 1
	while i <= listsize do
		local k = i + 1
		while k <= listsize do
			if list[i] == list[k] then
				print(i, k, list[i], list[k])
			end

			local pri = GetPriority(list[i], list[k])
			if pri == 1 then
				listsize = listsize - 1
				table.remove(list, i)
				i = i - 1
				break
			elseif pri == -1 then
				listsize = listsize - 1
				table.remove(list, k)
			else
				k = k + 1
			end
		end

		i = i + 1
	end
end

local function CleanPath(path)
	--[[local gm, rpath = path:match("^([^/]+)/gamemode/(.+)$")
	if gm and rpath then
		return rpath
	end]]

	local rpath = path:match("^[^/]+/entities/(.+)$")
	if rpath then
		return rpath
	end

	return path
end

local band, brshift = bit.band, bit.rshift
local function WriteULong(f, n)
	f:WriteByte(brshift(n, 24))
	f:WriteByte(band(brshift(n, 16), 0xFF))
	f:WriteByte(band(brshift(n, 8), 0xFF))
	f:WriteByte(band(n, 0xFF))
end

hook.Add("InitPostEntity", "luapack resource creation", function()
	hook.Remove("InitPostEntity", "luapack resource creation")

	luapack.LogMsg("Building pack...")
	
	local time = SysTime()

	local luapacktemp = "luapack/temp.dat"

	local f = file.Open(luapacktemp, "wb", "DATA")
	if not f then
		error("failed to open '" .. luapacktemp .. "' for writing")
	end

	local h = luapack.SHA1()
	if not h then
		error("failed to create SHA-1 hasher object")
	end

	CleanFileList(luapack.FileList)

	for i = 1, #luapack.FileList do
		local filepath = luapack.FileList[i]
		local data = ReadFile(filepath)
		local datalen = #data
		local crc = tonumber(util.CRC(data))
		filepath = CleanPath(filepath)

		h:Update(data)

		if datalen > 0 then
			data = util.Compress(data)
			datalen = #data
		end

		WriteULong(f, datalen)
		WriteULong(f, crc)
		f:Write(filepath)
		f:WriteByte(0)

		if datalen > 0 then
			f:Write(data)
		end
	end

	f:Close()

	luapack.CurrentHash = StringToHex(h:Final())

	local currentpath = "luapack/" .. luapack.CurrentHash .. ".dat"
	if not file.Exists(currentpath, "DATA") then
		if not luapack.Rename("data/" .. luapacktemp, "data/" .. currentpath) then
			luapack.DebugMsg("Pack file renaming not successful")
		end
	else
		luapack.DebugMsg("Deleting obsolete temporary file")
		file.Delete(luapacktemp)
	end

	resource.AddFile("data/" .. currentpath)

    util.AddNetworkString("luapackhash_" .. luapack.CurrentHash)

	luapack.FinishedAdding = true

	luapack.LogMsg("Pack building took " .. SysTime() - time .. " seconds!")
end)

include("includes/_init.lua")