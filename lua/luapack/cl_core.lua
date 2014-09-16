local currenthash = GetConVarString("luapack_hash")
if not currenthash or #currenthash == 0 then
	error("unable to retrieve current file hash, critical luapack error")
end

include("sh_core.lua")

luapack.LogMsg("Found the current pack file hash ('" .. currenthash .. "')!")

luapack.include = include,
luapack.CompileFile = CompileFile,
luapack.require = require,
luapack.fileFind = file.Find,
luapack.fileExists = file.Exists,
luapack.fileIsDir = file.IsDir,
luapack.FileList = {},
luapack.CurrentHash = currenthash

include("cl_file.lua")
include("cl_directory.lua")

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
	luapack.LogMsg("Starting Lua file list build of '" .. filepath .. "'!")

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
include("_init.lua")
include("cl_entities.lua")