local pika = require "pika"
local lu = require "luaunit"

function testNumber()
	local obj = {x = -5}
	local tween = pika.new(obj):to({x = 3}, 1)
	lu.assertEquals(tween:tick(0.25), true)
	lu.assertEquals(obj.x, -3)
	lu.assertEquals(tween:tick(0.25), true)
	lu.assertEquals(obj.x, -1)
	lu.assertEquals(tween:tick(0.25), true)
	lu.assertEquals(obj.x, 1)
	lu.assertEquals(tween:tick(0.25), false)
	lu.assertEquals(obj.x, 3)
	lu.assertEquals(tween:tick(0.25), false)
	lu.assertEquals(obj.x, 3)
end

function testMultiple()
	local obj = {x = 10, y = 20}
	local tween = pika.new(obj):to({x = 100, y = 200}, 10)
	tween:tick(5)
	lu.assertEquals(obj.x, 55)
	lu.assertEquals(obj.y, 110)
end

function testEasing()
	local obj = {x = 80}
	local tween = pika.new(obj):to({x = 100}, 2, function(t)
		return t * t
	end)
	tween:tick(1)
	lu.assertEquals(obj.x, 85)
end

function testLoop()
	local obj = {x = -5}
	local tween = pika.new(obj):to({x = 3}, 2):loop(1)
	lu.assertEquals(tween:tick(2.5), true)
	lu.assertEquals(obj.x, -3)
	lu.assertEquals(tween:tick(2.5), false)
	lu.assertEquals(obj.x, 3)
end

function testBounce()
	local obj = {x = -5}
	local tween = pika.new(obj):to({x = 3}, 2):loop(1):bounce()
	lu.assertEquals(tween:tick(2), true)
	lu.assertEquals(obj.x, 3)
	lu.assertEquals(tween:tick(0.5), true)
	lu.assertEquals(obj.x, 1)
end

function testDirection()
	local obj = {x = 20}
	local tween = pika.new(obj):to({x = 10}, 1):to({x = 0}, 2)
	lu.assertEquals(tween:tick(1.5), true)
	lu.assertEquals(obj.x, 7.5)
	tween:setDirection(-1)
	lu.assertEquals(tween:tick(0.6), true)
	lu.assertEquals(obj.x, 11)
end

function testSpeed()
	local obj = {x = 20}
	local tween = pika.new(obj):to({x = 10}, 10)
	tween:setSpeed(2)
	lu.assertEquals(tween:tick(2.5), true)
	lu.assertEquals(obj.x, 15)
end

function testWait()
	local obj = {x = 20}
	local tween = pika.new(obj):wait(5):to({x = 10}, 10)
	lu.assertEquals(tween:tick(7.5), true)
	lu.assertEquals(obj.x, 17.5)
end

function testSetter()
	local obj = {x = 123}
	local tween = pika.new(obj):wait(5):set({x = 124})
	lu.assertEquals(tween:tick(5), false)
	lu.assertEquals(obj.x, 124)
end

function testEvents()
	local obj = {x = 1, l = 0}
	local tween = pika.new(obj):to({x = 2}, 5):loop(2):on("loop", function(tween)
		tween.l = tween.l + 1
	end)
	tween:tick(1)
	lu.assertEquals(obj.l, 0)
	tween:tick(5)
	lu.assertEquals(obj.l, 1)
end	

function newCallSeq()
	local cb = {}
	local a = function() table.insert(cb, "a") end
	local b = function() table.insert(cb, "b") end
	local tween = pika.new({}):label("a"):call(a):label("b"):call(b):label("c")
	return tween, cb
end

function testLabels1()
	local tween, cb = newCallSeq()
	tween:setPosition("a")
	tween:tick(1)
	lu.assertEquals(cb, {"a", "b"})
end

function testLabels2()
	local tween, cb = newCallSeq()
	tween:setPosition("b")
	tween:tick(1)
	lu.assertEquals(cb, {"b"})
end

function testLabels3()
	local tween, cb = newCallSeq()
	tween:setPosition("c")
	tween:setDirection(-1)
	tween:tick(1)
	lu.assertEquals(cb, {"b", "a"})
end

function testTimeline()
	local a = {x = 10}
	local b = {x = 20}
	local tl = pika.newTimeline()
	local seqa = pika.new(a):to({x = 15}, 5)
	local seqb = pika.new(b):to({x = 10}, 10)
	tl:add(seqa)
	tl:add(seqb, 5)
	lu.assertEquals(tl:tick(2.5), true)
	lu.assertEquals(a.x, 12.5)
	lu.assertEquals(b.x, 20)
	lu.assertEquals(tl:tick(2.5), true)
	lu.assertEquals(a.x, 15)
	lu.assertEquals(b.x, 20)
	lu.assertEquals(tl:tick(2.5), true)
	lu.assertEquals(a.x, 15)
	lu.assertEquals(b.x, 17.5)
	lu.assertEquals(tl:tick(10), false)
	lu.assertEquals(a.x, 15)
	lu.assertEquals(b.x, 10)
end

function testRelative()
	pika.addPlugins(pika.relative)
	local a = {x = 10}
	local tween = pika.new(a):to({x = "+=5"}, 5):to({x = "-=6"}, 1)
	tween:tick(2)
	lu.assertEquals(a.x, 12)
	tween:tick(4)
	lu.assertEquals(a.x, 9)
	tween:setPosition(4)
	lu.assertEquals(a.x, 14)
	pika.removePlugins()
end

function testDegree()
	pika.addPlugins(pika.relative, pika.degree)
	local a = {x = math.pi / 4}
	local tween = pika.new(a):to({x = "+=90 deg"}, 2)
	tween:tick(1)
	lu.assertEquals(a.x, math.pi / 2)
	pika.removePlugins()
end

function testDot()
	pika.addPlugins(pika.dot)
	local a = {x = {y = 8}}
	local tween = pika.new(a):to({['.x.y'] = "10"}, 2)
	tween:tick(1)
	lu.assertEquals(a.x.y, 9)
	pika.removePlugins()
end

os.exit(lu.LuaUnit.run())
