luapack.include = luapack.include or include
luapack.CompileFile = luapack.CompileFile or CompileFile
luapack.require = luapack.require or require
luapack.fileFind = luapack.fileFind or file.Find
luapack.fileExists = luapack.fileExists or file.Exists
luapack.fileIsDir = luapack.fileIsDir or file.IsDir

function require(module)
	local time = SysTime()

	local modulepath = "includes/modules/" .. module .. ".lua"
	local obj = luapack.RootDirectory:GetSingle(modulepath)
	if obj and obj:IsFile() then
		if package.loaded[module] then
			luapack.DebugMsg("Module already loaded '" .. module .. "'")
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

	luapack.DebugMsg("Couldn't require Lua module from luapack, proceeding with normal require", module)

	local ret = luapack.require(module)
	
	luapack.AddTime(SysTime() - time)

	return ret
end

local function GetFileFromPathStack(filepath)
	local i = 3
	local dbg = debug.getinfo(i, "S")
	while dbg do
		local path = dbg.source:match("^@?(.*)[/\\][^/\\]-$") or dbg.source:match("^@?(.*)$")
		if #path == 0 then
			path = filepath
		else
			path = path .. "/" .. filepath
		end

		local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(path))
		if obj and obj:IsFile() then
			return obj
		end

		i = i + 1
		dbg = debug.getinfo(i, "S")
	end

	local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath))
	if obj and obj:IsFile() then
		return obj
	end
end

function include(filepath)
	local time = SysTime()

	local file = GetFileFromPathStack(filepath)
	if file then
		CompileString(file:GetContents(), file:GetFullPath())()

		luapack.AddTime(SysTime() - time)

		return
	end

	luapack.DebugMsg("Couldn't include Lua file from luapack, proceeding with normal include", filepath)

	luapack.include(filepath)

	luapack.AddTime(SysTime() - time)
end

function CompileFile(filepath)
	local time = SysTime()

	local file = GetFileFromPathStack(filepath)
	if file then
		local ret = CompileString(file:GetContents(), file:GetFullPath())

		luapack.AddTime(SysTime() - time)

		return ret
	end

	luapack.DebugMsg("Couldn't CompileFile Lua file from luapack, proceeding with normal CompileFile", filepath)

	local ret = luapack.CompileFile(filepath)

	luapack.AddTime(SysTime() - time)

	return ret
end

local function namedesc(a, b)
	return a > b
end

function file.Find(filepath, filelist, sorting)
	if filelist == "LUA" then
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
	else
		return luapack.fileFind(filepath, filelist, sorting)
	end
end

function file.Exists(filepath, filelist)
	if filelist == "LUA" then
		return luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath)) ~= nil
	else
		return luapack.fileExists(filepath, filelist)
	end
end

function file.IsDir(filepath, filelist)
	if filelist == "LUA" then
		local obj = luapack.RootDirectory:GetSingle(luapack.CanonicalizePath(filepath))
		return obj ~= nil and obj:IsDirectory()
	else
		return luapack.fileIsDir(filepath, filelist)
	end
end