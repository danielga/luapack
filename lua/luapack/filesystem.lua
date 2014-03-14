local FILE = {}
FILE.__index = FILE

function FILE:IsFile()
	return true
end

function FILE:IsDirectory()
	return false
end

function FILE:GetName()
	return self.__name
end

function FILE:GetParent()
	return self.__parent
end

function FILE:GetFullPath()
	local names = {self:GetName()}
	local parent = self:GetParent()
	while parent do
		table.insert(names, 1, parent:GetName())
		parent = parent:GetParent()
	end

	return table.concat(names, "/")
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

function DIRECTORY:GetName()
	return self.__name
end

function DIRECTORY:GetParent()
	return self.__parent
end

function DIRECTORY:GetFullPath()
	local names = {self:GetName()}
	local parent = self:GetParent()
	while parent do
		table.insert(names, 1, parent:GetName())
		parent = parent:GetParent()
	end

	return table.concat(names, "/")
end

function DIRECTORY:AddFile(name)
	if istable(name) then
		local strname = table.remove(name, 1)
		if #name == 0 then
			return self:AddFile(strname)
		end

		local _, dirs = self:Get(strname)
		local dir = dirs[1]
		if not dir then
			dir = self:AddDirectory(strname)
		end

		return dir:AddFile(name)
	end

	local files, dirs = self:Get(name)
	if not files[1] and not dirs[1] then
		local file = setmetatable({__name = name, __parent = self}, FILE)
		table.insert(self.__list, file)
		return file
	end
end

function DIRECTORY:AddDirectory(name)
	if istable(name) then
		local strname = table.remove(name, 1)
		if #name == 0 then
			return self:AddDirectory(strname)
		end

		local _, dirs = self:Get(strname)
		local dir = dirs[1]
		if not dir then
			dir = self:AddDirectory(strname)
		end

		return dir:AddDirectory(name)
	end

	local files, dirs = self:Get(name)
	if not files[1] and not dirs[1] then
		local dir = setmetatable({__name = name, __parent = self, __list = {}}, DIRECTORY)
		table.insert(self.__list, dir)
		return dir
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

function DIRECTORY:Get(name)
	local strname = name
	local namecount = 0
	if istable(name) then
		strname = GlobToPattern(table.remove(name, 1))
		namecount = #name
	else
		strname = GlobToPattern(strname)
	end

	local files, dirs = {}, {}
	for elem in self:GetIterator() do
		if elem:GetName():find(strname) then
			if namecount > 0 then
				if elem:IsDirectory() then
					local fs, ds = elem:Get(name)
					for i = 1, #fs do
						table.insert(files, fs[i])
					end

					for i = 1, #ds do
						table.insert(dirs, ds[i])
					end
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
	local list = self.__list
	local n = #list
	return function()
		i = i + 1
		return i <= n and list[i] or nil
	end
end

function luapack.NewRootDirectory()
	return setmetatable({__name = "", __list = {}}, DIRECTORY)
end