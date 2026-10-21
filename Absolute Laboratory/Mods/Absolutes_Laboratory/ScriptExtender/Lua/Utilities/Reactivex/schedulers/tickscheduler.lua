--- A scheduler that uses Ext.Timer to schedule events on delay, optionally every X milliseconds
--- @class TickScheduler
--- @field tasks table
--- @field count number
--- @field handle number?
local TickScheduler = {}
TickScheduler.__index = TickScheduler
TickScheduler.__tostring = ReactiveXUtil.constant('TickScheduler')

--- Creates a new TimeoutScheduler.
--- @return TickScheduler
function TickScheduler.create()
    return setmetatable({
        tasks = {}
    }, TickScheduler)
end

--- Schedules an action to run at a future point in time.
--- @param action function - The action to run.
--- @param ticks number? 1 - The number of ticks to wait
--- @return Subscription, number
function TickScheduler:schedule(action, ticks)
    ticks = ticks or 1

    self.count = self.count or 0

    local taskIndex = #self.tasks + 1
    local task = {
        action = action,
        ticks = ticks,
        startTick = self.count,
        completed = false,
        index = taskIndex
    }
    self.tasks[taskIndex] = task

    Logger:BasicTrace("[RX %s] Registered new task at index #%d", tostring(self), taskIndex)

    if not self.handle then
        Logger:BasicTrace("[RX %s] Creating new Tick Subscription", tostring(self))

        self.handle = Ext.Events.Tick:Subscribe(function(e)
            self.count = self.count + 1

            for i, task in TableUtils:OrderedPairs(self.tasks) do
                Logger:BasicTrace("[RX %s] Ticks Passed: %d | Desired Ticks: %d", tostring(self), (self.count - task.startTick), task.ticks)
                if (self.count - task.startTick) == task.ticks then
                    Logger:BasicTrace("[RX %s] Subscription %d completed", tostring(self), i)
                    task.action()
                    task.completed = true
                    self.tasks[i] = nil
                end
            end

            if not next(self.tasks) then
                Logger:BasicTrace("[RX %s] No tasks left, unsubscribing", tostring(self))
                Ext.Events.Tick:Unsubscribe(self.handle)
                self.handle = nil
                self.count = 0
            end
        end, { Priority = 999 })
    end

    return Subscription.create(function()
        if not task.completed then
            Logger:BasicTrace("[RX %s] Subscription %d cancelled", tostring(self), task.index)
            self.tasks[task.index] = nil
        end
    end), taskIndex
end

return TickScheduler
