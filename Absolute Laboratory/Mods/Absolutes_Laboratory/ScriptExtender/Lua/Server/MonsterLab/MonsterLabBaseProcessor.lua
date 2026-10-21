---@class MonsterLab_BaseProcessor
MonsterLab_BaseProcessor = {
    ---@type QueuedLog[]
    queuedLogs = {}
}

---@class QueuedLog
---@field logFun fun(logger: Logger, params: any[])
---@field params any[]

---@generic P : MonsterLab_EntityProcessor
---@param instance table?
---@return P
function MonsterLab_BaseProcessor:new(instance)
    instance = instance or {}

    setmetatable(instance, self)
    self.__index = self

    instance.queuedLogs = {}

    return instance
end

---@param logFunc fun(logger: Logger, ...)
---@param ... any
function MonsterLab_BaseProcessor:queueLog(logFunc, ...)
    local params = { ... }
    table.insert(self.queuedLogs, {
        logFun = logFunc,
        params = params
    } --[[@as QueuedLog]])
end

function MonsterLab_BaseProcessor:flushLogs()
    for _, queuedLog in ipairs(self.queuedLogs) do
        local success, error = xpcall(function(...)
            queuedLog.logFun(Logger, table.unpack(queuedLog.params))
        end, debug.traceback)

        if not success then
            Logger:BasicWarning("Could not log entry %s due to %s", queuedLog, error)
        end
    end
end

function MonsterLab_BaseProcessor:complete() end

Ext.Require("Server/MonsterLab/EncounterProcessor.lua")
Ext.Require("Server/MonsterLab/MonsterLabEntityProcessor.lua")
