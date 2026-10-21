---@alias Scheduler CooperativeScheduler|ImmediateScheduler|TimerScheduler|DripScheduler|TickScheduler

---@module "util"
ReactiveXUtil = Ext.Require("Utilities/Reactivex/util.lua")
---@module "subscription"
Subscription = Ext.Require("Utilities/Reactivex/subscription.lua")
---@module "observer"
Observer = Ext.Require("Utilities/Reactivex/observer.lua")
---@module "observable"
Observable = Ext.Require("Utilities/Reactivex/observable.lua")
---@module "immediatescheduler"
ImmediateScheduler = Ext.Require("Utilities/Reactivex/schedulers/immediatescheduler.lua")
---@module "cooperativescheduler"
CooperativeScheduler = Ext.Require("Utilities/Reactivex/schedulers/cooperativescheduler.lua")
---@module "timeoutscheduler"
TimerScheduler = Ext.Require("Utilities/Reactivex/schedulers/timerscheduler.lua")
---@module "dripscheduler"
DripScheduler = Ext.Require("Utilities/Reactivex/schedulers/dripscheduler.lua")
---@module "tickscheduler"
TickScheduler = Ext.Require("Utilities/Reactivex/schedulers/tickscheduler.lua")
---@module "subject"
Subject = Ext.Require("Utilities/Reactivex/subjects/subject.lua")
---@module "asyncsubject"
AsyncSubject = Ext.Require("Utilities/Reactivex/subjects/asyncsubject.lua")
---@module "behaviorsubject"
BehaviorSubject = Ext.Require("Utilities/Reactivex/subjects/behaviorsubject.lua")
---@module "replaysubject"
ReplaySubject = Ext.Require("Utilities/Reactivex/subjects/replaysubject.lua")

---@class RX
---@field Subscription Subscription
---@field Observer Observer
---@field Observable Observable
---@field ImmediateScheduler ImmediateScheduler
---@field CooperativeScheduler CooperativeScheduler
---@field TimerScheduler TimerScheduler
---@field DripScheduler DripScheduler
---@field TickScheduler TickScheduler
---@field Subject Subject
---@field AsyncSubject AsyncSubject
---@field BehaviorSubject BehaviorSubject
---@field ReplaySubject ReplaySubject
---@field util table Internal utilities
return {
    util = ReactiveXUtil,
    Subscription = Subscription,
    Observer = Observer,
    Observable = Observable,
    ImmediateScheduler = ImmediateScheduler,
    CooperativeScheduler = CooperativeScheduler,
    TimerScheduler = TimerScheduler,
    DripScheduler = DripScheduler,
    TickScheduler = TickScheduler,
    Subject = Subject,
    AsyncSubject = AsyncSubject,
    BehaviorSubject = BehaviorSubject,
    ReplaySubject = ReplaySubject
}
