async  = require("async")
dd     = require("./lib/dd")
faye   = require("faye")
log    = require("./lib/logger").init("service.monitor")
mqtt   = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis  = require("redis-url").connect(process.env.REDIS_URL)

socket = new faye.Client(process.env.FAYE_URL)

device_add = (device) ->
  log.start "device.add", device, (log) ->
    async.parallel
      sadd:    (cb) -> redis.sadd "devices:#{device.model}", device.id, cb
      set:     (cb) -> redis.set "device:#{device.id}:model", device.model, cb
      publish: (cb) -> socket.publish "/device/add", device, cb
      (err, res) -> if err then log.error(err) else log.success()

device_remove = (device) ->
  log.start "device.remove", device, (log) ->
    async.parallel
      zrem: (cb) -> redis.zrem "devices", device.id, cb
      srem: (cb) ->
        redis.get "device:#{device.id}:model", (err, model) ->
          redis.srem "devices:#{model}", device.id, cb
      publish: (cb) -> socket.publish "/device/remove", device, cb
      (err, res) -> if err then log.error(err) else log.success()

tick = (message) ->
  log.start "tick", key:message.key, value:message.value, (log) ->
    redis.set "metric:#{message.id}:#{message.key}", message.value
    socket.publish "/tick/#{message.id.replace(".", "-")}", message
    log.success()

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
      when "tick"
        redis.zadd "ticks", dd.now(), "#{message.id}.#{dd.random(8)}"
        if message.key is "model"
          redis.zadd "devices", dd.now(), message.id, (err, added) ->
            if added is 1
              device_add id:message.id, model:message.value
              log.success added:message.id
        tick message if message.key

dd.every 1000, ->
  log.start "purge", (log) ->
    async.parallel
      devices: (cb) -> redis.zrangebyscore "devices", 0, dd.now() - 4000, (err, devices) ->
        device_remove(id:device) for device in devices
        cb err, devices
        log.success(devices:devices.join(",")) if devices.length > 0
      ticks:   (cb) -> redis.zremrangebyscore "ticks",   0, dd.now() - 5000, cb
      (err, res)    -> if err then log.error(err)
