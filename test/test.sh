cd lua_modules &&
wget --no-check-certificate -N https://raw.githubusercontent.com/chunpu/Shim/master/shim.lua &&
wget --no-check-certificate -N https://raw.githubusercontent.com/chunpu/store.lua/master/store.lua &&
cd .. &&
cp lua_modules/*.lua /tmp
cp monitor.lua /tmp
/usr/local/openresty/nginx/sbin/nginx -c `pwd`/test/nginx.conf && tail -f /usr/local/openresty/nginx/logs/error.log
