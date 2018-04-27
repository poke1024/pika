-- a library for tweening and animating things.
-- v0.8, (C) 2018 Bernhard Liebl, MIT license

local pika = {defaultEasing = nil}
local unpaused = {}
local unpack = unpack or table.unpack
local deg2rad = math.pi / 180


local defaultclone = function(target, name)
	return target[name]
end

local _defaultmixers = {
	number = {
		animate = function(target, name, v0, v1, t, dt)
			target[name] = v0 * (1 - t) + v1 * t
		end,
		clone = defaultclone
	}
}

local function defaultmixer(value)
	if type(value) == "string" then
		value = tonumber(value)
	end
	local mixer = _defaultmixers[type(value)]
	if mixer == nil then
		error("no mixer available for type " .. type(value) .. ": " .. value)
	end
	return mixer
end

local function lastchain(target, name, v1)
	return defaultmixer(v1)
end


local plugins = {}

pika.addPlugins = function(...)
	for _, plugin in ipairs({...}) do
		table.insert(plugins, {init = plugin.init,
			prio = plugin.prio, name = plugin.name, chain = nil})
	end
	table.sort(plugins, function(a, b)
		return a.prio > b.prio
	end)
	local n = #plugins
	for i = 1, n do
		plugins[i].chain = (function(j)
			return function(target, name, v1)
				local chain = j + 1 <= n and plugins[j + 1].chain or lastchain
				local mixer = plugins[j].init(target, name, v1, chain) 
				return mixer or chain(target, name, v1)
			end
		end)(i)
	end
end

pika.removePlugins = function()
	plugins = {}
end

pika.relative = {
	prio = 1,
	name = "relative",
	init = function(target, name, v1, chain)
		if type(v1) == "string" and string.match(v1, "^[%+%-]=") ~= nil then
			local number = string.gsub(v1:sub(1, 1) .. v1:sub(3), "%s+", "")
			local chained = chain(target, name, number)
			local scratch = {}
			return {
				animate = function(target, name, v0, _, t, dt)
					chained.animate(scratch, "delta", 0, number, t, dt)
					target[name] = v0 + scratch.delta
				end,
				clone = chained.clone
			}
		end
	end
}

pika.degree = {
	prio = 0,
	name = "degree",
	init = function(target, name, v1, chain)
		if type(v1) == "string" and string.match(v1, "deg$") ~= nil then
			local number = tonumber(v1:sub(1, string.len(v1) - 3)) * deg2rad
			local chained = chain(target, name, number)
			return {
				animate = function(target, name, v0, _, t, dt)
					chained.animate(target, name, v0, number, t, dt)
				end,
				clone = chained.clone
			}
		end
	end
}

pika.dot = {
	prio = 2,
	name = "dot",
	init = function(target, name, v1, chain)
		if type(name) == "string" and string.sub(name, 1, 1) == "." then
			local path = {}
			for p in string.gmatch(string.sub(name, 2), "[^%.]+") do
				table.insert(path, p)
			end
			local elem = path[#path]
			table.remove(path, #path)

			local chained = chain(target, name, v1)
			return {
				animate = function(target, name, v0, v1, t, dt)
					for _, p in ipairs(path) do
						target = target[p]
					end
					chained.animate(target, elem, v0, v1, t, dt)
				end,
				clone = function(target, _)
					for _, p in ipairs(path) do
						target = target[p]
					end
					return chained.clone(target, elem)
				end
			}			
		end
	end
}

local Tweenable = {}
Tweenable.__index = Tweenable

function Tweenable:getDuration()
	return 0
end

function Tweenable:setDuration(duration)
	error("cannot set duration.")
end

function Tweenable:setEasing(easing)
	error("cannot set easing.")
end

function Tweenable:enter(t)
end

function Tweenable:leave()
end

function Tweenable:setPosition(position, inverse)
end

local Tickable = {}
Tickable.__index = Tickable
setmetatable(Tickable, {__index = Tweenable})

function Tickable:getDirection()
	return self._direction
end

function Tickable:setDirection(dir)
	self._direction = (dir > 0 or dir == "forward") and 1 or -1
end

function Tickable:reverse()
	self._direction = -self._direction
end

function Tickable:getSpeed()
	return self._speed
end

function Tickable:setSpeed(speed)
	self._direction = speed > 0 and 1 or -1
	self._speed = math.abs(speed)
end

function Tickable:setPosition(position, inverse)
	self._position = position
end

function Tickable:getPosition()
	return self._position
end

function Tickable:tick(dt)
	return self:setPosition(self._position + dt * self._direction * self._speed)
end

function Tickable:getPaused()
	return self._paused
end

function Tickable:setPaused(paused)
	if paused ~= self._paused then
		if paused then
			unpaused[self] = nil
		else
			unpaused[self] = true
		end
		self._paused = paused
	end
end

function Tickable:play()
	self:setPaused(false)
end

function Tickable:pause()
	self:setPaused(true)
end



local Animator = {}
Animator.__index = Animator
setmetatable(Animator, {__index = Tweenable})

function Animator:getDuration()
	return self._duration
end

function Animator:setDuration(duration)
	self._duration = duration
end

function Animator:setEasing(easing)
	self._easing = easing
end

function Animator:enter(t)
	if t == 0 then
		local values0 = self.values0
		local target = self.target
		local mixers = self.mixers
		for name, _ in pairs(self.properties) do
			values0[name] = mixers[name].clone(target, name)
		end
	end
	self.t = t
end

function Animator:setPosition(position, inverse)
	local t = position / self._duration
	if self._easing then
		if inverse then
			t = 1 - self._easing(1 - t)
		else
			t = self._easing(t)
		end
	end
	local values0 = self.values0
	local target = self.target
	local dt = t - self.t
	local mixers = self.mixers
	for name, value1 in pairs(self.properties) do
		mixers[name].animate(target, name, values0[name], value1, t, dt)
	end
	self.t = t
end

local function newAnimator(target, properties, easing, offset, duration)
	easing = easing or pika.defaultEasing
	local mixers = {}
	for name, value in pairs(properties) do
		local mixer = nil
		if #plugins > 0 then
			mixer = plugins[1].chain(target, name, value)
		end
		mixers[name] = mixer or defaultmixer(value)
	end
	return setmetatable({target = target, _offset = offset, _duration = duration,
		properties = properties, mixers = mixers, _easing = easing, t = 0, values0 = {}}, Animator)
end


local Callback = {}
Callback.__index = Callback
setmetatable(Callback, {__index = Tweenable})

function Callback:enter(t, jump)
	if not jump then
		self.f(self, unpack(self.args))
	end
end

local function newCallback(f, args, offset)
	return setmetatable({f = f, args = args or {}, _offset = offset}, Callback)
end


local Wait = {}
Wait.__index = Wait
setmetatable(Wait, {__index = Tweenable})

function Wait:getDuration()
	return self._duration
end

local function newWait(offset, duration)
	return setmetatable({_offset = offset, _duration = duration}, Wait)
end


local Setter = {}
Setter.__index = Setter
setmetatable(Setter, {__index = Tweenable})

function Setter:enter(t)
	for key, value in pairs(self.properties) do
		self.target[key] = value
	end
end

local function newSetter(target, offset, properties)
	return setmetatable({target = target, _offset = offset, properties = properties}, Setter)
end


local Sequence = {}
Sequence.__index = Sequence
setmetatable(Sequence, {__index = Tickable})

pika.new = function(target)
	local sequence = setmetatable({target = target, _tweens = {}, _duration = 0, index = 0,
		t = 0, iteration = 0, _position = 0, _direction = 1, _speed = 1, _loop = 0, _bounce = false,
		events = {}, labels = {}, _timeline = nil, _paused = true, _offset = 0}, Sequence)
	timeline:add(sequence)
	return sequence
end

function Sequence:add(tween)
	table.insert(self._tweens, tween)
	tween._offset = self._duration
	self._duration = self._duration + tween:getDuration()
	return self
end

function Sequence:bounce(f)
	self._bounce = f or true
	return self
end

function Sequence:loop(n)
	if n == "forever" then
		self._loop = -1
	else
		self._loop = n
	end
	return self
end

function Sequence:getCurrentLabel()
	local i = self.index
	local tweens = self._tweens
	local n = #tweens
	while i >= 1 and i <= n do
		local span = tweens[i]
		if span.label ~= nil then
			return span.label
		end
		i = i - self._direction
	end
	return nil
end

function Sequence:getDuration()
	if self._loop < 0 then
		return 1 / 0
	end
	return self._duration * (1 + self._loop)
end

function Sequence:to(properties, duration, easing)
	table.insert(self._tweens, newAnimator(self.target, properties, easing, self._duration, duration))
	self._duration = self._duration + duration
	return self
end

function Sequence:duration(duration)
	local tween = self._tweens[#self._tweens]
	self._duration = self._duration - tween:getDuration() + duration
	tween:setDuration(duration)
	return self
end

function Sequence:easing(easing)
	self._tweens[#self._tweens]:setEasing(easing)
	return self
end

function Sequence:call(f, args)
	table.insert(self._tweens, newCallback(f, args, self._duration))
	return self
end

function Sequence:wait(duration)
	table.insert(self._tweens, newWait(self._duration, duration))
	self._duration = self._duration + duration
	return self	
end

function Sequence:set(properties)
	table.insert(self._tweens, newSetter(self.target, self._duration, properties))
	return self
end

function Sequence:label(name)
	local span = newWait(self._duration, 0)
	span.label = name
	table.insert(self._tweens, span)
	self.labels[name] = {self._duration, #self._tweens}
	return self
end

function Sequence:_jump(toindex)
	if toindex < self.index then
		for i = math.min(self.index, #self._tweens), math.max(toindex, 1), -1 do
			local tween = self._tweens[i]
			tween:setPosition(0)
			self.t = tween._offset
		end
	elseif toindex > self.index then
		for i = math.max(self.index, 1), math.min(toindex, #self._tweens) do
			local tween = self._tweens[i]
			local duration = tween:getDuration()
			tween:setPosition(duration)
			self.t = tween._offset + duration
		end
	end
	self.index = toindex
end

function Sequence:_animate(t, inverse)
	local spans = self._tweens
	local index = self.index
	local n = #spans

	if n < 1 then
		return
	end

	local span = spans[index]
	local offset
	local duration
	local direction = t > self.t and 1 or -1

	if span ~= nil then
		offset = span._offset
		duration = span:getDuration()
	elseif index < 1 then
		offset = 0
		duration = 0
	else
		offset = self._duration
		duration = 0
	end

	if index < 1 and direction < 0 then
		return
	elseif index > n and direction > 0 then
		return
	end

	while index ~= toindex do
		if t > offset + duration or (t == offset + duration and direction > 0) then
			if span ~= nil then
				span:setPosition(span:getDuration())
				span:leave()
			end
			index = index + 1
			if index > n then
				index = n + 1
				break
			end
			span = spans[index]
			span:enter(0)
		elseif t < offset or (t == offset and direction < 0) then
			if span ~= nil then
				span:setPosition(0)
				span:leave()
			end
			index = index - 1
			if index < 1 then
				index = 0
				break
			end
			span = spans[index]
			span:enter(1)
		else
			span:setPosition(t - offset, inverse)
			break
		end

		offset = span._offset
		duration = span:getDuration()
	end

	self.t = t
	self.index = index
end

function Sequence:on(event, callback)
	self.events[event] = self.events[event] or {}
	table.insert(self.events[event], callback)
	return self
end

function Sequence:trigger(event)
	local callbacks = self.events[event]
	if callbacks ~= nil then
		for _, callback in ipairs(callbacks) do
			callback(self.target)
		end
	end
end

function Sequence:setPosition(position, inverse)
	inverse = inverse or false
	local duration = self._duration

	if type(position) == "string" then
		local t, toindex
		t, toindex = unpack(self.labels[position])
		self:_jump(toindex)
		self._position = self.t + self.iteration * duration
		return true
	end

	local pos = math.max(position, 0)
	local iteration = math.floor(pos / duration)
	local t = pos - iteration * duration

	if iteration ~= self.iteration then
		local forward = iteration > self.iteration

		if self._bounce and self.iteration % 2 == 1 then
			forward = not forward
		end

		if forward then
			self:_animate(duration + 1)
		else
			self:_animate(-1)
		end
	end

	if self._loop >= 0 and iteration > self._loop then
		self._position = duration * (self._loop + 1)
		self:trigger("complete")
		return false
	elseif position < 0 then
		self._position = 0
		self:trigger("complete")
		return false
	else
		self._position = position
	end

	if iteration ~= self.iteration then
		if not self._bounce then
			if iteration > self.iteration then
				self:_jump(0)
			elseif iteration < self.iteration then
				self:_jump(1 + #self._tweens)
			end
		end
		self:trigger("loop")
	end

	local cinverse = false
	if self._bounce and iteration % 2 == 1 then
		t = duration - t
		cinverse = true
	end

	self.iteration = iteration
	self:_animate(t, cinverse)
	return true
end


local Timeline = {}
Timeline.__index = Timeline
setmetatable(Timeline, {__index = Tickable})

pika.newTimeline = function(...)
	local timeline = setmetatable({_tweens = {},
		_duration = 0, _added = {}, _position = 0, _direction = 1, _speed = 1}, Timeline)
	for _, t in ipairs({...}) do
		self:add(t)
	end
	return timeline
end

function Timeline:add(tween, offset)
	self._added[tween] = offset or 0
end

function Timeline:_add(tween, offset)
	if tween._timeline ~= nil then
		tween._timeline:remove(tween)
	end
	tween:setPaused(true)
	tween._offset = offset
	tween._timeline = self
	self._tweens[tween] = true
	if self._duration ~= nil then
		self._duration = math.max(self._duration, tween:getDuration() + offset)
	end
end

function Timeline:remove(tween)
	self._tweens[tween] = nil
	tween._timeline = nil
	if self._duration ~= nil and tween:getDuration() + tween._offset >= self._duration then
		self._duration = nil
	end
end

function Timeline:getDuration()
	self:updateDuration()
	return self._duration
end

function Timeline:updateDuration()
	if self._duration ~= nil then
		return
	end
	self._duration = 0
	for tween, _ in pairs(self._tweens) do
		self._duration = math.max(self._duration, tween:getDuration() + tween._offset)
	end
end

function Timeline:setPosition(position, inverse)
	for tween, offset in pairs(self._added) do
		self:_add(tween, offset)
		self._added[tween] = nil
	end
	for tween, _ in pairs(self._tweens) do
		tween:setPosition(position - tween._offset)
	end
	self._position = position
	return position >= 0 and position <= self:getDuration()
end

timeline = pika.newTimeline()


local Group = {}
Group.__index = Group

pika.newGroup = function(...)
	local group = setmetatable({_tweens = {}}, Group)
	for _, t in ipairs({...}) do
		self:add(t)
	end
	return group
end

function Group:add(tween)
	self._tweens[tween] = true
end

function Group:remove(tween)
	self._tweens[tween] = nil
end

function Group:setPaused(paused)
	for tween, _ in pairs(self._tweens) do
		tween:setPaused(paused)
	end
end


pika.reset = function()
	for tween, _ in pairs(unpaused) do
		tween:setPaused(true)
	end
end

pika.tick = function(dt)
	for tween, _ in pairs(unpaused) do
		if not tween:tick(dt) then
			tween:setPaused(true)
		end
	end
end

return pika
