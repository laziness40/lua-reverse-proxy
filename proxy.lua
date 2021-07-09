-- Load Memcached, cjson module
local cjson     = require "cjson"
local memcached = require "resty.memcached"
local memc      = memcached:new()

-- Set Memcached timeout(1 sec)
memc:set_timeout(1000)

-- Connect to Memcached daemon
local memc_ok, err  = memc:connect("127.0.0.1", 11211)
if not memc_ok then
    ngx.log(ngx.ALERT, "Failed to connect to Memcached: ", err)
end

-- Init variable
local domain     = ngx.var.host
local proxy_json = nil

if memc_ok then
    -- Query for host name in Memcached
    local _json, flags, err = memc:get(domain)

    if _json and type(_json) == 'string' then
        -- JsonString to variable
        proxy_json = _json
        ngx.log(ngx.INFO, "Loading proxy from Memcached: ", proxy_json)
    end
end


if not proxy_json then
    -- Load MySQL module
    local mysql   = require "resty.mysql"
    local db      = mysql:new()

    -- Set MySQL timeout(1 sec)
    db:set_timeout(1000)

    -- Connect to MySQL
    local ok, err, errcode, sqlstate = db:connect{
        host      = "localhost",
        port      = 3306,
        database  = "example",
        user      = "user",
        password  = "password"
    }

    if not ok then
        ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
        return ngx.exit(500)
    end

    -- Set variable and quote sql string
    local quoted_domain = ngx.quote_sql_str(domain)

    -- Execute an SQL query
    local sql = "SELECT location, host, port, internal FROM proxy WHERE domain = "..quoted_domain.." ORDER BY LENGTH(location) DESC"
    local res, err, errcode, sqlstate = db:query(sql)

    -- Save MySQL worker connection (max_idle_timeout 10 sec, pool 100)
    db:set_keepalive(10000, 100)

    if not res then
        ngx.log(ngx.ERR, "bad result #1: ", err, ": ", errcode, " ", sqlstate)
        return ngx.exit(404)
    end

    -- Set result
    proxy_json = cjson.encode(res)
    ngx.log(ngx.INFO, "Loading proxy from MySQL: ", proxy_json)

    if memc_ok then
        -- Store the result from MySQL back in to Memcached with a lifetime of 5 minutes (300 seconds)
        memc:set(domain, proxy_json, 300)
    end
end


if memc_ok then
    -- Save Memcached worker connection (max_idle_timeout 10 sec, pool 100)
    memc:set_keepalive(10000, 100)
end


-- Decide result
local proxy_host     = nil
local proxy_port     = nil
local proxy_internal = 0
local uri            = ngx.var.request_uri
for i, proxy in pairs(cjson.decode(proxy_json)) do
    ngx.log(ngx.INFO, "Finding uri: ", uri)

    proxy_host     = proxy.host
    proxy_port     = proxy.port
    proxy_internal = tonumber(proxy.internal)

    if string.match(uri, "^"..proxy.location) then
        ngx.log(ngx.INFO, "Location match: ", proxy.host, ":", proxy.port, ":", proxy.location, ":", proxy.internal)
        break
    end
end

-- Check internal
if proxy_internal == 1 then
    local remote_ip = ngx.var.remote_addr
    local ipmatcher = require("resty.ipmatcher")
    local ip = ipmatcher.new({
        "127.0.0.1",
        "192.168.0.0/16",
        "172.16.0.0/12",
        "10.0.0.0/8",
    })

    local ok, err = ip:match(remote_ip)
    if not ok then
        return ngx.exit(403)
    end
end

-- Set result
ngx.var.proxy_host = proxy_host
ngx.var.proxy_port = proxy_port
