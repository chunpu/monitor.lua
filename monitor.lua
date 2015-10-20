local _ = require 'shim'
local json = require 'cjson'
local store = require 'store'

-- http://nginx.org/en/docs/varindex.html

local monitor = {
	cacheSeconds = 5,
	key = 'monitor.lua',
	startTime = ngx.time()
}

local function newData()
	return {
		zones = {},
		upstreams = {}
	}
end

-- 1445224734 = {1xx = 0, 2xx = 100, body_size = 1000000, total = 300, request_time = xxxx}

local function newItem()
	return {
		lasts = {}, -- cache by timestamp(second)
		responses = {
			['1xx'] = 0,
			['2xx'] = 0,
			['3xx'] = 0,
			['4xx'] = 0,
			['5xx'] = 0,
			total = 0
		}
	}
end

local function newSecond()
	-- use second so we can clear old data easy
	return {
		['1xx'] = 0,
		['2xx'] = 0,
		['3xx'] = 0,
		['4xx'] = 0,
		['5xx'] = 0,
		total = 0,
		-- total
		body_bytes_sent = 0,
		request_time = 0,
		request_length = 0
	}
end

local function fillItem(zone, data)
	-- ngx.log(ngx.EMERG, tostring(111) .. tostring(data.status):sub(1, 1))
	local statusKey = tostring(data.status):sub(1, 1) .. 'xx'
	local responses = zone.responses
	responses.total = responses.total + 1
	responses[statusKey] = responses[statusKey] + 1

	local now = tostring(ngx.time()) -- avoid excessively sparse array
	local lasts = zone.lasts
	local last = lasts[now]
	if not last then
		-- a new second
		lasts[now] = newSecond()
		last = lasts[now]

		-- clear old data
		for key, val in pairs(lasts) do
			if tonumber(now) - tonumber(key) > monitor.cacheSeconds then
				lasts[key] = nil
			end
		end
	end

	last.total = last.total + 1
	last[statusKey] = last[statusKey] + 1
	last.body_bytes_sent = last.body_bytes_sent + data.body_bytes_sent
	last.request_length = last.request_length + data.request_length
	last.request_time = last.request_time + data.request_time

	-- detail status, always important
	if not last[data.status] then
		last[data.status] = 0
	end
	last[data.status] = last[data.status] + 1
end

monitor.incr = function(key)
	-- incr log
	local data = store.get(monitor.key)
	if not data then
		data = newData()
	end

	if type(data) == 'string' then
		store.remove(monitor.key)
		return monitor.incr(key)
	end

	local httpData = {
  		  status = ngx.var.status
		, body_bytes_sent = ngx.var.body_bytes_sent
		, request_length = ngx.var.request_length
		, request_time = ngx.var.request_time
	}
	ngx.log(ngx.EMERG, tostring(111) .. tostring(json.encode(httpData)))
	local zone = data.zones[key]
	if not zone then
		data.zones[key] = newItem()
		zone = data.zones[key]
	end
	fillItem(zone, httpData)

	-- ngx.log(ngx.EMERG, tostring(111) .. tostring(json.encode(data)))
	store.set(monitor.key, data)
end

local function sumLasts(lasts, key)
	-- ignore the key is now
	local now = ngx.time()
	local ret = 0
	_.forIn(lasts, function(last, time)
		if tostring(time) ~= now then
			ret = ret + last[key]
		end
	end)
	return ret
end

local function getDuration()
	local ret = monitor.cacheSeconds - 1 -- -1 means ignore now
	local min = ngx.time() - monitor.startTime
	if min < ret then
		-- just start
		return min
	end
	return ret
end

monitor.status = function()
	-- dashboard(realtime), json, string
	-- not care performance in `status`
	ngx.sleep(0.3)
	local ret = {
		  nginx_version = ngx.var.nginx_version
		, address = ngx.var.server_addr
		, timestamp = ngx.now() * 1000
		, time_iso8601 = ngx.var.time_iso8601
		, pid = ngx.worker.pid()
		, cacheSeconds = monitor.cacheSeconds
	}
	local data = store.get(monitor.key) or {}
	-- ngx.log(ngx.EMERG, tostring(111) .. tostring(json.encode(data.zones)))
	ret.zones = _.mapValues(data.zones, function(zone)
		zone = zone or {}
		local ret = _.only(zone, 'responses')
		local duration = getDuration()
		local total = sumLasts(zone.lasts, 'total')
		ret.request_per_second = total / duration
		ret.avg_response_time = sumLasts(zone.lasts, 'request_time') / total
		ret.avg_body_bytes_sent = sumLasts(zone.lasts, 'body_bytes_sent') / total
		return ret
	end)
	ngx.header['Content-Type'] = 'application/json'
	ngx.say(json.encode(ret))
end

return monitor
