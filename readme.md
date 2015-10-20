monitor.lua
===

Open source and fast nginx monitor


Usage
---

```nginx
http {
	lua_shared_dict store 10m; # rely on store.lua
	init_by_lua "monitor = require 'monitor'";
	log_by_lua "monitor.incr()";

	location /status {
		content_by_lua "monitor.status()";
	}

}
```

Advanced
---

`monitor.lua` will cache last 5 seconds data by default, you can change it by `monitor.cacheSeconds = 6` to cache 6 seconds data
