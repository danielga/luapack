luapack.directory = {
	__metatable = false,
	__index = {}
}

local DIRECTORY = luapack.directory.__index

function DIRECTORY:__tostring()
	return self:GetFullPath()
end

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
	return self.path
end

function DIRECTORY:GetParent()
	return self.parent
end

function DIRECTORY:GetFullPath()
	local paths = {self:GetPath()}
	local parent = self:GetParent()
	while parent ~= nil and not parent:IsRootDirectory() do
		table.insert(paths, 1, parent:GetPath())
		parent = parent:GetParent()
	end

	return table.concat(paths, "/")
end

local function GetPathParts(path)
	local curdir, rest = string.match(path, "^([^/]+)/(.+)$")
	if curdir ~= nil and rest ~= nil then
		return false, curdir, rest
	end

	return true, path
end

function DIRECTORY:AddFile(path, offset, size, crc)
	local single, cur, rest = GetPathParts(path)
	if single then
		local obj = self:GetSingle(cur)
		if obj == nil then
			local file = setmetatable({
				path = cur,
				offset = offset,
				size = size,
				crc = crc,
				crc_checked = 0, -- CRC_NOT_CHECKED
				parent = self,
				file = self.file
			}, luapack.file)
			table.insert(self:GetList(), file)
			return file
		end

		return obj:IsFile() and obj or nil
	end

	local obj = self:GetSingle(cur)
	if obj == nil then
		obj = self:AddDirectory(cur)
	end

	return obj:IsDirectory() and obj:AddFile(rest, offset, size, crc) or nil
end

function DIRECTORY:AddDirectory(path)
	local single, cur, rest = GetPathParts(path)
	if single then
		local obj = self:GetSingle(cur)
		if obj == nil then
			local dir = setmetatable({
				path = cur,
				parent = self,
				file = self.file,
				list = {}
			}, luapack.directory)
			table.insert(self:GetList(), dir)
			return dir
		end

		return obj:IsDirectory() and obj or nil
	end

	local obj = self:GetSingle(cur)
	if obj == nil then
		obj = self:AddDirectory(cur)
	end

	return obj:IsDirectory() and obj:AddDirectory(rest) or nil
end

local function GlobToPattern(glob)
	local pattern = {"^"}

	for i = 1, #glob do
		local ch = string.sub(glob, i, i)

		if ch == "*" then
			ch = ".*"
		else
			ch = string.find(ch, "^%w$") and ch or "%" .. ch
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
		if (pattern and string.find(elem:GetPath(), cur)) or elem:GetPath() == cur then
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
		if (pattern and string.find(elem:GetPath(), cur)) or elem:GetPath() == cur then
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
	return self.list
end

function DIRECTORY:GetIterator()
	local i = 0
	local list = self:GetList()
	local n = #list
	return function()
		i = i + 1
		if i <= n then
			return list[i]
		end
	end
end

function DIRECTORY:GetContents()
	error("not implemented")
end

function DIRECTORY:Destroy()
	if not self:IsRootDirectory() then
		error("not implemented on directories that aren't the root")
	end

	self.file:Close()
	self.file = nil
	self.list = {}
end
