luapack.FILE = {}
luapack.FILE.__index = luapack.FILE

local FILE = luapack.FILE

function FILE:__tostring()
	return self:GetFullPath()
end

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

local CRC_FAIL = -1
local CRC_NOT_CHECKED = 0
local CRC_SUCCESS = 1
function FILE:GetContents()
	local f = self.__file
	f:Seek(self.__offset)
	local data = f:Read(self.__size)
	if data then
		data = util.Decompress(data)
	end

	data = data or ""

	if self.__crc_checked == CRC_NOT_CHECKED then
		self.__crc_checked = tonumber(util.CRC(data)) ~= self.__crc and CRC_FAIL or CRC_SUCCESS
	end

	if self.__crc_checked == CRC_FAIL then
		error("CRC not matching for file '" .. self:GetFullPath() .. "'")
	end

	return data
end

function FILE:AddFile(name)
	error("what the hell do you think you're doing man")
end

FILE.AddDirectory = FILE.AddFile
FILE.Get = FILE.AddFile
FILE.GetSingle = FILE.AddFile
FILE.GetList = FILE.AddFile
FILE.GetIterator = FILE.AddFile
FILE.Destroy = FILE.AddFile