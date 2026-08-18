local M = {}

M.ServerInfo = {}
M.ServerInfo.__index = M.ServerInfo

function M.ServerInfo.new(id, name, baseUrl, realmId, isFromServer)
    local self = setmetatable({}, M.ServerInfo)
    self.id = id or ""
    self.name = name or ""
    self.baseUrl = baseUrl or ""
    self.realmId = realmId or ""
    self.isFromServer = isFromServer or false
    return self
end

M.ServerList = {}
M.ServerList.__index = M.ServerList

function M.ServerList.new()
    local self = setmetatable({}, M.ServerList)
    self.servers = {}
    self.loaded = false
    self.error = ""
    return self
end

return M

