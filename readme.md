monitor.lua
===

Monitor nginx with status information


Usage
---

```nginx
http {
	lua_shared_dict store 10m; # rely on `store.lua`
	init_by_lua "monitor = require 'monitor'";
	log_by_lua "monitor.group()";

	location /status {
		content_by_lua "monitor.status()";
	}

}
```

Data Format
---

### Dashboard

Default shows dashboard (TODO), refresh by itself

### json

`/status?format=json` shows status with json

### plain

`/status?format=plain` shows status with plain string


Path param
---

You can get the one data by path param

`/status?format=plain&path=`

Advanced
---

`monitor.lua` will cache last 5 seconds data by default, you can change it by `monitor.cacheSeconds = 6` to cache 6 seconds data
