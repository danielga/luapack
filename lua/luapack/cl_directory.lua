luapack.DIRECTORY = {__index = {}}

local DIRECTORY = luapack.DIRECTORY.__index

function DIRECTORY:IsFile()
	return false
end

function DIRECTORY:IsDirectory()
	return true
end

function DIRECTORY:IsRootDirectory()
	return self:GetParent() == nil
end

function DIRECTORY:GetPath()
	return self.__path
end

function DIRECTORY:GetParent()
	return self.__parent
end

function DIRECTORY:GetFullPath()
	local paths = {self:GetPath()}
	local parent = self:GetParent()
	while parent and not parent:IsRootDirectory() do
		table.insert(paths, 1, parent:GetPath())
		parent = parent:GetParent()
	end

	return table.concat(paths, "/")
end

local function GetPathParts(path)
	local curdir, rest = path:match("^([^/]+)/(.+)$")
	if curdir and rest then
		return false, curdir, rest
	else
		return true, path
	end
end

function DIRECTORY:AddFile(path, offset, size, crc)
	local single, cur, rest = GetPathParts(path)
	if single then
		local obj = self:GetSingle(cur)
		if not obj then
			local file = setmetatable({
				__path = cur,
				__offset = offset,
				__size = size,
				__crc = crc,
				__crc_checked = CRC_NOT_CHECKED,
				__parent = self,
				__file = self.__file
			}, FILE)
			table.insert(self:GetList(), file)
			return file
		end

		return obj:IsFile() and obj or nil
	else
		local obj = self:GetSingle(cur)
		if not obj then
			obj = self:AddDirectory(cur)
		end

		return obj:IsDirectory() and obj:AddFile(rest, offset, size, crc) or nil
	end
end

function DIRECTORY:AddDirectory(path)
	local single, cur, rest = GetPathParts(path)
	if single then
		local obj = self:GetSingle(cur)
		if not obj then
			local dir = setmetatable({
				__path = cur,
				__parent = self,
				__file = self.__file,
				__list = {}
			}, DIRECTORY)
			table.insert(self:GetList(), dir)
			return dir
		end

		return obj:IsDirectory() and obj or nil
	else
		local obj = self:GetSingle(cur)
		if not obj then
			obj = self:AddDirectory(cur)
		end

		return obj:IsDirectory() and obj:AddDirectory(rest) or nil
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

function DIRECTORY:GetSingle(path, pattern)
	pattern = pattern or false

	local single, cur, rest = GetPathParts(path)

	for elem in self:GetIterator() do
		if (pattern and elem:GetPath():find(cur)) or elem:GetPath() == cur then
			if not single then
				if elem:IsDirectory() then
					return elem:GetSingle(rest, pattern)
				end
			else
				return elem
			end
		end
	end
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

function DIRECTORY:GetContents()
	error("what the hell do you think you're doing man")
end

function DIRECTORY:Destroy()
	if not self:IsRootDirectory() then
		error("what the hell do you think you're doing man")
	end

	self.__file:Close()
	self.__file = nil
	self.__list = {}
end