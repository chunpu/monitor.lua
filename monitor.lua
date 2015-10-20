local _ = require 'shim'
local json = require 'cjson'
local store = require 'store'

local monitor = {
	cacheSeconds = 5,
	key = 'monitor.lua',
	startTime = ngx.time()
}

local function log(...)
	ngx.log(ngx.EMERG, _.dump(...))
end

local function newData()
	return {
		zones = {},
		upstreams = {}
	}
end

local function newItem()
	-- use in zone or upstream
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
	-- save data by second so we can clear old data easy
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

local function clearOutdatedLasts(lasts, now)
	now = now or tostring(ngx.time())
	for key, val in pairs(lasts) do
		if tonumber(now) - tonumber(key) > monitor.cacheSeconds then
			lasts[key] = nil
		end
	end
end

local function fillItem(zone, data)
	local statusKey = tostring(data.status):sub(1, 1) .. 'xx'
	local responses = zone.responses
	responses.total = responses.total + 1
	responses[statusKey] = responses[statusKey] + 1

	local now = tostring(ngx.time()) -- avoid excessively sparse array
	local lasts = zone.lasts

	if not lasts[now] then
		clearOutdatedLasts(lasts, now)
		lasts[now] = newSecond()
	end
	local last = lasts[now]

	last.total = last.total + 1
	last[statusKey] = last[statusKey] + 1
	last.body_bytes_sent = last.body_bytes_sent + data.body_bytes_sent
	last.request_length = last.request_length + data.request_length
	last.request_time = last.request_time + data.request_time

	-- detail status, always important, e.g. 204, 499
	if not last[data.status] then
		last[data.status] = 0
	end
	last[data.status] = last[data.status] + 1
end

monitor.group_by_path = function(count)
	local key = ngx.var.uri
	if count then
		key = _.split(key, '/', true)
		key = key[count + 1] -- first is ''
	end
	return monitor.group(key)
end

monitor.group_by_host = function()
	local key = ngx.var.host .. ':' .. ngx.var.server_port
	return monitor.group(key)
end

monitor.group = function(key)
	-- incr data
	key = tostring(key)
	local data = store.get(monitor.key)
	if not data then
		data = newData()
	end

	-- http://nginx.org/en/docs/varindex.html
	local httpData = {
  		  status = ngx.var.status
		, body_bytes_sent = ngx.var.body_bytes_sent
		, request_length = ngx.var.request_length
		, request_time = ngx.var.request_time
		, upstream_addr = ngx.var.upstream_addr
		, upstream_response_time = ngx.var.upstream_response_time
		, upstream_status = ngx.var.upstream_status
		, upstream_response_length = ngx.var.upstream_response_length
	}

	-- TODO handle upstream

	-- log(httpData)

	if not data.zones[key] then
		data.zones[key] = newItem()
	end
	local zone = data.zones[key]

	fillItem(zone, httpData)

	store.set(monitor.key, data)
end

local function prettyNumber(num)
	-- keep 3
	num = math.floor(num * 1000)
	return num / 1000
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

local function outputStatus(status)
	local output
	local mime
	local query = ngx.req.get_uri_args()

	if 'clear' == query.method then
		store.remove(monitor.key)
		return ngx.say('clear success')
	end

	local format = query.format
	local path = query.path
	if not _.empty(path) then
		path = _.split(path, '.', true)
		status = _.get(status, path)
	end

	if 'json' == format then
		mime = 'text/application'
		output = json.encode(status)
	elseif 'plain' == format then
		mime = 'text/plain'
		output = tostring(status)
	else
		-- TODO
		-- default is human readable dashboard
		mime = 'text/html'
		output = 'coming soon'
	end
	ngx.header['Content-Type'] = mime
	ngx.say(output)

end

monitor.status = function()
	-- not care performance in `status`
	local ret = {
		  nginx_version = ngx.var.nginx_version
		, address = ngx.var.server_addr
		, timestamp = ngx.now() * 1000
		, time_iso8601 = ngx.var.time_iso8601
		, pid = ngx.worker.pid()
		, cacheSeconds = monitor.cacheSeconds
	}
	local data = store.get(monitor.key) or {}

	ret.zones = _.mapValues(data.zones, function(zone)
		clearOutdatedLasts(zone.lasts) -- always clear outdated when get status
		zone = zone or {}
		local ret = _.only(zone, 'responses')
		local duration = getDuration()
		local total = sumLasts(zone.lasts, 'total')

		if 0 == duration or 0 == total then
			-- care zero
			ret.request_per_second = 0
			ret.avg_response_time = 0
			ret.avg_body_bytes_sent = 0
			ret['2xx_percent'] = 0
		else
			-- TODO pretty number
			ret.request_per_second = prettyNumber(total / duration)
			ret.avg_response_time = prettyNumber(sumLasts(zone.lasts, 'request_time') / total)
			ret.avg_body_bytes_sent = prettyNumber(sumLasts(zone.lasts, 'body_bytes_sent') / total)
			ret['2xx_percent'] = prettyNumber(sumLasts(zone.lasts, '2xx') / total)
		end
		return ret
	end)

	outputStatus(ret)
end

return monitor
