async  = require("async")
dd     = require("./lib/dd")
faye   = require("faye")
log    = require("./lib/logger").init("service.monitor")
mqtt   = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis  = require("redis-url").connect(process.env.REDIS_URL)

socket = new faye.Client(process.env.FAYE_URL)

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
        redis.multi()
          .zadd("devices", dd.now(), message.id)
          .sadd("devices:#{message.model}", message.id)
          .set("device:#{message.id}:model", message.model)
          .exec (err, res) ->
            socket.publish "/device/add", id:message.id, model:message.model if res[0] is 1
            log.success()
      when "disconnect"
        redis.zrem "devices", message.id, (err, removed) ->
          socket.publish "/device/remove", id:message.id if removed is 1
          log.success()
      when "tick"
        redis.zadd "ticks", dd.now(), "#{message.id}.#{dd.random(8)}"
        redis.zadd "devices", dd.now(), message.id, (err, added) ->
          redis.get "device:#{message.id}:model", (err, model) ->
            socket.publish "/device/add", id:message.id, model:model if added is 1
            log.success()
        redis.set "metric:#{message.id}:#{message.key}", message.value if message.key
        socket.publish "/tick/#{message.id.replace(".", "-")}", message
        log.success message

dd.every 1000, ->
  log.start "purge", (log) ->
    async.parallel
      devices: (cb) -> redis.zrangebyscore "devices", 0, dd.now() - 4000, (err, devices) ->
        for device in devices
          redis.zrem "devices", device
          redis.get "device:#{device}:model", (err, model) ->
            redis.srem "devices:#{model}", device
          socket.publish "/device/remove", id:device
        cb err, devices
        log.success(devices:devices.join(",")) if devices.length > 0
      ticks:   (cb) -> redis.zremrangebyscore "ticks",   0, dd.now() - 5000, cb
      (err, res)    -> if err then log.error(err)
