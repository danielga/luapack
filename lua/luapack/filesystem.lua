local FILE = {}
FILE.__index = FILE

function FILE:IsFile()
	return true
end

function FILE:IsDirectory()
	return false
end

function FILE:IsRootDirectory()
	return false
end

function FILE:GetPath()
	return self.__path
end

function FILE:GetParent()
	return self.__parent
end

function FILE:GetFullPath()
	local paths = {self:GetPath()}
	local parent = self:GetParent()
	while parent and not parent:IsRootDirectory() do
		table.insert(paths, 1, parent:GetPath())
		parent = parent:GetParent()
	end

	return table.concat(paths, "/")
end

function FILE:AddFile(name)
	error("what the hell do you think you're doing man")
end

FILE.AddDirectory = FILE.AddFile
FILE.Get = FILE.AddFile
FILE.GetList = FILE.AddFile
FILE.GetIterator = FILE.AddFile

local DIRECTORY = {}
DIRECTORY.__index = DIRECTORY

function DIRECTORY:IsFile()
	return false
end

function DIRECTORY:IsDirectory()
	return true
end

function DIRECTORY:IsRootDirectory()
	return self:GetParent() == nil
end

DIRECTORY.GetPath = FILE.GetPath
DIRECTORY.GetParent = FILE.GetParent
DIRECTORY.GetFullPath = FILE.GetFullPath

local function GetPathParts(path)
	local curdir, rest = path:match("^([^/]+)/(.+)$")
	if curdir and rest then
		return false, curdir, rest
	else
		return true, path
	end
end

function DIRECTORY:AddFile(path)
	local single, cur, rest = GetPathParts(path)
	if single then
		local files, dirs = self:Get(cur, false)
		if not files[1] and not dirs[1] then
			local file = setmetatable({__path = cur, __parent = self}, FILE)
			table.insert(self:GetList(), file)
			return file
		end
	else
		local _, dirs = self:Get(cur, false)
		local dir = dirs[1]
		if not dir then
			dir = self:AddDirectory(cur)
		end

		return dir:AddFile(rest)
	end
end

function DIRECTORY:AddDirectory(path)
	local single, cur, rest = GetPathParts(path)
	if single then
		local files, dirs = self:Get(cur, false)
		if not files[1] and not dirs[1] then
			local dir = setmetatable({__path = cur, __parent = self, __list = {}}, DIRECTORY)
			table.insert(self:GetList(), dir)
			return dir
		end
	else
		local _, dirs = self:Get(cur, false)
		local dir = dirs[1]
		if not dir then
			dir = self:AddDirectory(cur)
		end

		return dir:AddDirectory(rest)
	end
end

local function GlobToPattern(glob)
	local pattern = {"^"}

	for i = 1, #glob do
		local ch = glob:sub(i, i)

		if ch == "*" then
			ch = ".*"
		else
			ch = ch:find("^%w$") and ch or "%" .. ch
		end

		table.insert(pattern, ch)
	end

	table.insert(pattern, "$")
	return table.concat(pattern)
end

function DIRECTORY:Get(path, pattern, files, dirs)
	pattern = pattern or true
	files = files or {}
	dirs = dirs or {}

	local single, cur, rest = GetPathParts(path)
	if pattern then
		cur = GlobToPattern(cur)
	end

	for elem in self:GetIterator() do
		if (pattern and elem:GetPath():find(cur)) or elem:GetPath() == cur then
			if not single then
				if elem:IsDirectory() then
					elem:Get(rest, pattern, files, dirs)
				end
			else
				table.insert(elem:IsFile() and files or dirs, elem)
			end
		end
	end

	return files, dirs
end

-- not recommended
function DIRECTORY:GetList()
	return self.__list
end

function DIRECTORY:GetIterator()
	local i = 0
	local list = self:GetList()
	local n = #list
	return function()
		i = i + 1
		return i <= n and list[i] or nil
	end
end

function luapack.NewRootDirectory()
	return setmetatable({__list = {}}, DIRECTORY)
end