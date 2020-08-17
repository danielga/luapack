luapack = luapack or {
	include = include,
	CompileFile = CompileFile,
	require = require,
	fileFind = file.Find,
	fileExists = file.Exists,
	fileIsDir = file.IsDir
}

if luapack.LogFile ~= nil then
	luapack.LogFile:Close()
	luapack.LogFile = nil
end

luapack.LogFile = file.Open("luapack.txt", "w", "DATA")

function luapack.LogMsg(...)
	local content = string.format(...)

	Msg(content)

	luapack.LogFile:Write(content)
	luapack.LogFile:Flush()
end

function luapack.DebugMsg(...)
	local content = string.format(...)

	Msg(content)

	luapack.LogFile:Write(content)
	luapack.LogFile:Flush()
end

function luapack.CanonicalizePath(path)
	path = string.lower(path)
	path = string.gsub(path, "\\", "/")
	path = string.gsub(path, "/+", "/")

	local t = {}
	for str in string.gmatch(path, "([^/]+)") do
		if str == ".." then
			table.remove(t)
		elseif str ~= "." and str ~= "" then
			table.insert(t, str)
		end
	end

	path = table.concat(t, "/")

	local match = string.match(path, "^lua/(.+)$")
	if match ~= nil then
		return match
	end

	match = string.match(path, "^addons/[^/]+/lua/(.+)$")
	if match ~= nil then
		return match
	end

	match = string.match(path, "^gamemodes/[^/]+/entities/(.+)$")
	if match ~= nil then
		return match
	end

	match = string.match(path, "^gamemodes/([^/]+/gamemode/.+)$")
	if match ~= nil then
		return match
	end

	return path
end
