--!strict
--!optimize 2

local Signal = require(script.Parent.Parent.Shared.GoodSignal)

local Timer = {}
Timer.__index = Timer

type self = {
	CountdownMode: boolean,
	Destroyed: boolean,
	CountdownFirstTick: boolean,
	
	ID: number,
	Interval: number,
	TicksLeft: number,
	Rate: number,
	
	Tick: Signal.Signal<number>,
	Ended: Signal.Signal<>,
	
	_Accumulator: number,
	_TickCount: number,
	_Step: number,
	_i: number,
}

export type Timer = typeof(setmetatable({} :: self, Timer))

local HeartbeatConnection: RBXScriptConnection = nil
local ActiveTimers = {} :: {Timer}

local function IsTimerActive(self: Timer)
	return ActiveTimers[self.ID]
end

local function Heartbeat(delta: number)
	local self: Timer
	for _,self in ActiveTimers do
		local fire_value = if self.CountdownMode then self._i else self._TickCount

		self._Accumulator += delta * self.Rate
		while self._Accumulator >= self.Interval do
			self._Accumulator -= self.Interval

			self.Tick:Fire(fire_value)
			self._TickCount += 1
			fire_value += 1

			if self.CountdownMode then		
				if self.TicksLeft <= 0 then
					self.CountdownMode = false
					task.defer(self.Ended.Fire, self.Ended)
					task.defer(self.Stop, self)
					break
				end
				self.TicksLeft -= 1
				self._i += self._Step
				fire_value = self._i
			end
		end
	end
end

function Timer.new(interval_seconds: number): Timer
	local self = setmetatable({} :: self, Timer)
	self.ID = 0
	self.Rate = 1
	self.CountdownMode = false
	self.Interval = interval_seconds
	self.Tick = Signal.new()
	self.Ended = Signal.new()
	self.TicksLeft = 0
	self._Accumulator = 0
	self._TickCount = 0
	self.Destroyed = false
	return self
end

function Timer.Start(self: Timer, tick_instantly: boolean?): Timer
	assert(not self.Destroyed, "Destroyed timer can't be started.")
	if IsTimerActive(self) then
		return self
	end
	table.insert(ActiveTimers, self)
	self.ID = #ActiveTimers
	if #ActiveTimers == 1 then
		HeartbeatConnection = game:GetService("RunService").Heartbeat:Connect(Heartbeat)
	end
	if self.CountdownMode then
		if self.CountdownFirstTick then
			self.CountdownFirstTick = false
			self.Tick:Fire(self._i)
			self.TicksLeft -= 1
			self._i += self._Step
		end
	elseif tick_instantly then
		self.Tick:Fire(0)
	end
	return self
end

function Timer.Stop(self: Timer): Timer
	if not IsTimerActive(self) then
		return self
	end
	local prev = table.remove(ActiveTimers)
	if prev ~= self and prev then
		ActiveTimers[self.ID] = prev
		prev.ID = self.ID
	end
	if #ActiveTimers == 0 then
		HeartbeatConnection:Disconnect()
	end
	return self
end

function Timer.SetCountdown(self: Timer, start: number, end_: number?, step: number?): Timer
	assert(step~=0, "Step can not be 0")
	local end_ = end_ or 0
	self._Step = step or -1
	self._i = start
	self.TicksLeft = math.floor((end_ - start) / self._Step)
	assert(self.TicksLeft >= 0, "Invalid arguments to start a timer.")
	if self.TicksLeft == 0 then
		self.CountdownMode = false
		self.Ended:Fire()
		self:Stop()
		return self
	end
	self.CountdownMode = true
	self._Accumulator = 0
	if IsTimerActive(self) then
		self.Tick:Fire(self._i)
		self.TicksLeft -= 1
		self._i += self._Step
	else
		self.CountdownFirstTick = true
	end
	return self
end

function Timer.StartCountdown(self: Timer, start: number, end_: number?, step: number?): Timer
	self:Start()
	return self:SetCountdown(start, end_, step)
end

function Timer.Destroy(self: Timer)
	if ActiveTimers[self.ID] then
		self:Stop()
	end
	self.Tick:DisconnectAll()
	self.Ended:DisconnectAll()
end

return Timer
