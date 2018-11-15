-- Copyright (C) Outman

local json = require "cjson"
local resty_post = require "resty.post"
local tmp_storage_path = "storage/"
local redis_host = "127.0.0.1"
local redis_port = 6379

----------------------
-- access token check
----------------------

local access_token = ngx.req.get_headers()['AppAccessToken']
if not access_token then
    ngx.log(ngx.ERR, "access token missing")
    ngx.say(json.encode({code = ngx.HTTP_BAD_REQUEST, data = "access token invalid"}))
    return ngx.exit(ngx.HTTP_BAD_REQUEST)
end

--------------------------------------------
-- random file name prefix
--------------------------------------------
local resty_random = require "resty.random"
local str = require "resty.string"
local strong_random = resty_random.bytes(16, true)
while strong_random == nil do
    strong_random = resty_random.bytes(16, true)
end

local prefix_file_name = str.to_hex(strong_random)

----------------------
-- upload post form
----------------------
local post = resty_post:new({
    path = tmp_storage_path,
    chunk_size = 8192,
    no_tmp = true,
    name = function (name, field )
        return prefix_file_name .. name
    end
})
local form = post:read()

--------------------------------------------
-- validate form values
--------------------------------------------
local id = tonumber(form["id"])
if not id then
    ngx.log(ngx.ERR, "id invalid")
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say(json.encode({code = ngx.HTTP_BAD_REQUEST, data = "id invalid"}))
    return ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local step_id = tonumber(form["stepId"])
if not step_id then
    ngx.log(ngx.ERR, "step id invalid")
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say(json.encode({code = ngx.HTTP_BAD_REQUEST, data = "step id invalid"}))
    return ngx.exit(ngx.HTTP_BAD_REQUEST)
end

form["accessToken"] = access_token
form["ip"] = ngx.var.remote_addr
--------------------------------
-- push info to redis
--------------------------------
local redis = require "resty.redis"
local red = redis:new()

red:set_timeout(1000) -- 1seconds

local ok, err = red:connect(redis_host, redis_port)
if not ok then
    ngx.log(ngx.ERR, "failed to connect to redis: ", err)
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local ok, err = red:lpush("LUA_FS_UPLOAD", json.encode(form))
if ok then
    red:close()
    ngx.say(json.encode({code = ngx.HTTP_OK, data = "success"}))
    return ngx.exit(ngx.HTTP_OK)
end

red:close()

------------------------------------
-- END, Error
------------------------------------
ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
ngx.say(json.encode({code = ngx.ERROR, data = "failed to saved"}))
return ngx.exit(ngx.ERROR)
