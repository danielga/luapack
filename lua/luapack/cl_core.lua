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

local band, blshift = bit.band, bit.lshift
local function ReadULong(f)
	if f:Tell() + 4 > f:Size() then
		return
	end

	local b1, b2, b3, b4 = f:Read(4):byte(1, 4)
	local res = blshift(band(b1, 0x7F), 24) + blshift(b2, 16) + blshift(b3, 8) + b4
	if band(b1, 0x80) ~= 0 then
		res = res + 0x80000000
	end

	return res
end

local function ReadString(f)
	local data = {}
	local tell = f:Tell()
	local text = f:Read(128)
	local offset = nil
	while text do
		offset = text:find("\0")
		if offset then
			table.insert(data, text:sub(1, offset - 1))
			break
		end

		table.insert(data, text)

		text = f:Read(128)
	end

	local ret = table.concat(data)
	f:Seek(tell + #ret + 1)
	return ret
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