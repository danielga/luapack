function require(module)
	local time = SysTime()

	local modulepath = "includes/modules/" .. module .. ".lua"
	local obj = luapack.RootDirectory:GetSingle(modulepath)
	if obj ~= nil and obj:IsFile() then
		if package.loaded[module] then
			luapack.DebugMsg("Module already loaded '%s'\n", module)
			return
		end

		local ret = CompileString(obj:GetContents(), modulepath)()

		if not package.loaded[module] then
			local pkg = {
				_NAME = module,
				_PACKAGE = "",
				_LUAPACK = true
			}

			pkg._M = pkg

			local gmodule = _G[module]
			if gmodule then
				for k, v in pairs(gmodule) do
					pkg[k] = v
				end
			end

			package.loaded[module] = pkg
		end

		luapack.AddTime(SysTime() - time)

		return ret
	end

	luapack.DebugMsg("Couldn't require Lua module (%s) from luapack, proceeding with normal require\n", module)

	local ret = luapack.require(module)

	luapack.AddTime(SysTime() - time)

	return ret
end

local function GetFileFromPathStack(filepath)
	luapack.DebugMsg("%s\n", filepath)

	local i = 3
	local dbg = debug.getinfo(i, "S")
	while dbg do
		if dbg.what ~= "C" then
			local path = string.match(dbg.source, "^@?(.*)[/\\][^/\\]-$") or string.match(dbg.source, "^@?(.*)$")
			if #path == 0 then
				path = filepath
			else
				path = path .. "/" .. filepath
			end

			local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(path))
			luapack.DebugMsg("\t%s - %s - %s - %s\n", dbg.source, path, luapack.CanonicalizePath(path), tostring(obj))
			if obj ~= nil and obj:IsFile() then
				return obj
			end
		end

		i = i + 1
		dbg = debug.getinfo(i, "S")
	end

	local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath))
	luapack.DebugMsg("\t%s - %s - %s\n", filepath, luapack.CanonicalizePath(filepath), tostring(obj))
	if obj ~= nil and obj:IsFile() then
		return obj
	end
end

function include(filepath)
	local time = SysTime()

	local obj = GetFileFromPathStack(filepath)
	if obj ~= nil then
		local a, b, c, d, e, f, g, h, i, j = CompileString(obj:GetContents(), obj:GetFullPath())()

		luapack.AddTime(SysTime() - time)

		-- 10 return values... my dude, if you return more than 10 values...
		return a, b, c, d, e, f, g, h, i, j
	end

	luapack.DebugMsg("Couldn't include Lua file (%s) from luapack, proceeding with normal include\n", filepath)

	luapack.include(filepath)

	luapack.AddTime(SysTime() - time)
end

function CompileFile(filepath)
	local time = SysTime()

	local obj = GetFileFromPathStack(filepath)
	if obj ~= nil then
		local ret = CompileString(obj:GetContents(), obj:GetFullPath())

		luapack.AddTime(SysTime() - time)

		return ret
	end

	luapack.DebugMsg("Couldn't CompileFile Lua file (%s) from luapack, proceeding with normal CompileFile\n", filepath)

	local ret = luapack.CompileFile(filepath)

	luapack.AddTime(SysTime() - time)

	return ret
end

local function namedesc(a, b)
	return a > b
end

function file.Find(filepath, filelist, sorting)
	if filelist ~= "LUA" then
		return luapack.fileFind(filepath, filelist, sorting)
	end

	sorting = sorting or "nameasc"

	local files, folders = luapack.RootDirectory:Get(luapack.CanonicalizePath(filepath))
	local simplefiles, simplefolders = luapack.fileFind(filepath, filelist, sorting)

	for i = 1, #files do
		table.insert(simplefiles, files[i]:GetPath())
	end

	for i = 1, #folders do
		table.insert(simplefolders, folders[i]:GetPath())
	end

	if sorting == "namedesc" then
		table.sort(simplefiles, namedesc)
		table.sort(simplefolders, namedesc)
	else
		table.sort(simplefiles)
		table.sort(simplefolders)
	end

	return simplefiles, simplefolders
end

function file.Exists(filepath, filelist)
	if filelist ~= "LUA" then
		return luapack.fileExists(filepath, filelist)
	end

	return luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath)) ~= nil
end

function file.IsDir(filepath, filelist)
	if filelist ~= "LUA" then
		return luapack.fileIsDir(filepath, filelist)
	end

	local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath))
	return obj ~= nil and obj:IsDirectory()
end
