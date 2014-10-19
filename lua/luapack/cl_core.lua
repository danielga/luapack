local currenthash = nil
for i = 1, 2047 do
    local str = util.NetworkIDToString(i)
    if str and str:sub(1, 12) == "luapackhash_" then
        currenthash = str:sub(13)
        break
    end
end

if not currenthash then
    error("unable to retrieve current file hash, critical luapack error")
end

include("sh_core.lua")

luapack.LogMsg("Found the current pack file hash ('" .. currenthash .. "')!")

luapack.FileList = {}
luapack.CurrentHash = currenthash

include("cl_file.lua")
include("cl_directory.lua")

local blshift = bit.lshift
local function ReadULong(f)
	return f:ReadByte() * 16777216 + blshift(f:ReadByte(), 16) + blshift(f:ReadByte(), 8) + f:ReadByte()
end

local function ReadString(f)
	local tab = {}
	local n = f:ReadByte()
	while n ~= 0 do
		table.insert(tab, string.char(n))
		n = f:ReadByte()
	end

	return table.concat(tab)
end

function luapack.BuildFileList(filepath)
	luapack.LogMsg("Starting Lua file list build of '" .. filepath .. "'!")

	local time = SysTime()

	local f = file.Open(filepath, "rb", "GAME")
	if not f then
		error("failed to open pack file '" .. filepath .. "' for reading")
	end

	local dir = setmetatable({__file = f, __list = {}}, luapack.DIRECTORY)

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

	luapack.LogMsg("Lua file list building of '" .. filepath .. "' took " .. SysTime() - time .. " seconds!")

	return dir
end

luapack.RootDirectory = luapack.BuildFileList("download/data/luapack/" .. luapack.CurrentHash .. ".dat")

local totaltime = 0

function luapack.AddTime(time)
	totaltime = totaltime + time
end

function luapack.GetTimeSpentLoading()
	return totaltime
end

include("cl_overrides.lua")
include("includes/_init.lua")
include("cl_entities.lua")