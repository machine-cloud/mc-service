async = require("async")
dd    = require("./lib/dd")
log   = require("./lib/logger").init("service.monitor")
mqtt  = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis = require("redis-url").connect(process.env.REDISGREEN_URL)

mqtt.on "connect", ->
  log.start "connect", (log) ->
    async.parallel
      connect: (cb)    -> mqtt.subscribe "connect", cb
      disconnect: (cb) -> mqtt.subscribe "disconnect", cb
      tick:    (cb)    -> mqtt.subscribe "tick", cb
      (err)            -> if err then log.error(err) else log.success()

mqtt.on "message", (topic, body) ->
  message = JSON.parse(body)
  return unless message.id
  log.start "message", (log) ->
    switch topic
      when "connect"
        redis.zadd "devices", dd.now(), message.id
        log.success message
      when "disconnect"
        redis.zrem "devices", message.id
      when "tick"
        redis.zadd "devices", dd.now(), message.id
        redis.zadd "ticks", dd.now(), "#{message.id}.#{dd.random(8)}"
        log.success message

dd.every 1000, ->
  log.start "purge", (log) ->
    async.parallel
      devices: (cb) -> redis.zremrangebyscore "devices", 0, dd.now() - 2000, cb
      ticks:   (cb) -> redis.zremrangebyscore "ticks",   0, dd.now() - 5000, cb
      (err, res)    -> if err then log.error(err) else log.success(res)
