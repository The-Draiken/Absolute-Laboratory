--- A scheduler that uses Ext.Events.Tick to measure per-tick throughput against tick latency and control the rate of events to maintain near-optimal tick time
--- @class DripScheduler
local DripScheduler = {
    ---@type number
    initialPermits = nil,
    ---@type number
    maxPermits = nil,
    ---@type number
    availablePermits = nil,
    ---@type number
    checkedInPermits = nil,
    ---@type number
    totalTicks = nil,
    minimumPermits = 10,
    targetLatency = 33,
    handle = nil,
    ---@alias subKeys "action"|"completion"
    ---@type {[subKeys]: function}[]
    subs = nil,
    canComplete = false
}
DripScheduler.__index = DripScheduler
DripScheduler.__tostring = ReactiveXUtil.constant('DripScheduler')

--- Creates a new DripScheduler.
---@return DripScheduler
function DripScheduler.create()
    local config = ConfigurationStructure.config.mutations.settings.profileExecution
    local self = {
        initialPermits = config.initialPermits,
        availablePermits = config.initialPermits,
        maxPermits = config.initialPermits,
        minimumPermits = config.minimumPermits,
        targetLatency = config.targetLatency,
        checkedInPermits = 0,
        totalTicks = 0,
        tickStartTime = nil,
        subs = {}
    }

    return setmetatable(self, DripScheduler)
end

--- Schedules an action to run at a future point in time.
--- @param action function - The action to run.
--- @return Subscription
function DripScheduler:schedule(action)
    table.insert(self.subs, {
        action = action,
        completion = nil
    })

    local actionIndex = #self.subs

    if not self.handle then
        self.handle = Ext.Events.Tick:Subscribe(function(e)
            self.totalTicks = self.totalTicks + 1
            Logger:BasicTrace("[RX %s] Tick #%d", tostring(self), self.totalTicks)

            self.availablePermits = self.availablePermits + self.checkedInPermits

            if (self.maxPermits - self.availablePermits == 0) and self.checkedInPermits == 0 then
                Logger:BasicTrace("[RX %s] All permits are currently available - not performing any adjustments", tostring(self))
            elseif not self.tickStartTime then
                Logger:BasicTrace("[RX %s] First tick, skipping processing", tostring(self))
                self.tickStartTime = Ext.Timer.MonotonicTime()
                return
            else
                local currentTickLatency = self.tickStartTime

                -- Logger:BasicTrace("RX: %s New Frame: Current Attributes: %s", backpressure)

                local percentageOverTargetLatency = (self.targetLatency / currentTickLatency)
                if currentTickLatency > self.targetLatency then
                    if self.maxPermits == self.minimumPermits then
                        Logger:BasicTrace("[RX %s] Latency of %dms was %s%% over the target of %dms, but maxPermits is already at the acceptable minimum of %d - not changing",
                            tostring(self),
                            currentTickLatency,
                            100 - (percentageOverTargetLatency * 100),
                            self.targetLatency,
                            self.minimumPermits)
                    else
                        self.maxPermits = math.max(self.minimumPermits, math.floor(self.maxPermits * percentageOverTargetLatency))
                        self.availablePermits = math.min(self.maxPermits, self.availablePermits)

                        Logger:BasicTrace("[RX %s] Latency of %dms was %s%% over the target of %dms - new queue limit is %d%s",
                            tostring(self),
                            currentTickLatency,
                            100 - (percentageOverTargetLatency * 100),
                            self.targetLatency,
                            self.maxPermits,
                            self.maxPermits == self.minimumPermits and " (which is the lowest acceptable limit)" or "")
                    end
                else
                    local oldMax = self.maxPermits
                    local newMax = self.maxPermits + math.ceil(self.maxPermits * 0.2)
                    self.availablePermits = self.availablePermits + (newMax - self.maxPermits)
                    self.maxPermits = newMax

                    Logger:BasicTrace("[RX %s] Latency of %dms was less than the target (%dms) - increased maxPermits to %d from %d",
                        tostring(self),
                        currentTickLatency,
                        self.targetLatency,
                        self.maxPermits,
                        oldMax)
                end
            end

            self.checkedInPermits = 0
            self.tickStartTime = Ext.Timer.MonotonicTime()

            Logger:BasicTrace("[RX %s] %d permits available", tostring(self), self.availablePermits)
            if not self.canComplete then
                if self.availablePermits > 0 then
                    for p = 1, self.availablePermits do
                        if #self.subs == 0 then
                            break
                        end

                        local sub = self.subs[math.max(1, p % #self.subs)]
                        local acceptedTask = sub.action()
                        if type(acceptedTask) == "boolean" and acceptedTask == true then
                            self.availablePermits = self.availablePermits - 1
                        elseif type(acceptedTask) == "function" then
                            sub.completion = acceptedTask
                        end
                    end
                end
            else
                Logger:BasicTrace("[RX %s]: Missing Permits: %d | Checking In Permits: %d",
                    tostring(self),
                    self.maxPermits - self.availablePermits,
                    self.checkedInPermits
                )
                if (self.maxPermits - self.availablePermits) <= 0 and self.checkedInPermits == 0 then
                    Logger:BasicTrace("[RX %s] All permits are returned, completing subs", tostring(self))
                    for _, sub in pairs(self.subs) do
                        sub.completion()
                    end
                end
            end

            if not self.canComplete then
                for _, sub in pairs(self.subs) do
                    if sub.completion == nil then
                        self.canComplete = false
                        break
                    else
                        self.canComplete = true
                    end
                end

                if self.canComplete then
                    Logger:BasicTrace("[RX %s] Will complete when all permits are returned", tostring(self))
                end
            end

            self.tickStartTime = Ext.Timer.MonotonicTime() - self.tickStartTime
        end, { Priority = 0 })
    end

    return Subscription.create(function()
        Logger:BasicTrace("[RX %s] Subscription %d cancelled, removing", tostring(self), actionIndex)

        table.remove(self.subs, actionIndex)
        if not next(self.subs) and self.handle then
            Logger:BasicTrace("[RX %s] No more active subs, cancelling subscription", tostring(self))
            Ext.Events.Tick:Unsubscribe(self.handle)
            self.handle = nil
            self.canComplete = false
        end
    end)
end

--- Unconditionally drops the Tick subscription. Normal completion already does this, but if a permit is never
--- returned (an entity errored mid-pipeline) completion never triggers and the handler would otherwise keep
--- running every frame for the rest of the session.
function DripScheduler:dispose()
    if self.handle then
        Ext.Events.Tick:Unsubscribe(self.handle)
        self.handle = nil
    end
    self.subs = {}
    self.canComplete = false
end

function DripScheduler:checkinPermit()
    self.checkedInPermits = self.checkedInPermits + 1

    self.checkedInPermits = math.max(0, math.min(self.maxPermits, self.checkedInPermits))
    Logger:BasicTrace("[RX %s] Permit checked in, now at %d", tostring(self), self.checkedInPermits)
end

return DripScheduler
