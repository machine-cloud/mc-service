async  = require("async")
dd     = require("./lib/dd")
log    = require("./lib/logger").init("service.monitor")
mqtt   = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis  = require("redis-url").connect(process.env.REDISGREEN_URL)

faye = require("faye")
socket = new faye.Client(process.env.FAYE_URL)

#socket = require("./lib/faye-redis-url").init(process.env.REDISGREEN_URL)

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
        console.log "connect"
        redis.zadd "devices", dd.now(), message.id, (err, added) ->
          if added is 1
            console.log "adding", message
            socket.publish "/device/add", id:message.id, (foo, bar) ->
              console.log "foo", foo
              console.log "bar", bar
          log.success()
      when "disconnect"
        redis.zrem "devices", message.id, (err, removed) ->
          socket.publish "/device/remove", id:message.id if removed is 1
          log.success()
      when "tick"
        redis.zadd "ticks", dd.now(), "#{message.id}.#{dd.random(8)}"
        redis.zadd "devices", dd.now(), message.id, (err, added) ->
          socket.publish "/device/add", id:message.id if added is 1
          log.success()
        socket.publish "/tick/#{message.id.replace(".", "-")}", message
        log.success message

dd.every 1000, ->
  log.start "purge", (log) ->
    async.parallel
      devices: (cb) -> redis.zrangebyscore "devices", 0, dd.now() - 2000, (err, devices) ->
        for device in devices
          console.log "removing", device
          redis.zrem "devices", device
          socket.publish "/device/remove", id:device
        cb err, devices
      ticks:   (cb) -> redis.zremrangebyscore "ticks",   0, dd.now() - 5000, cb
      (err, res)    -> if err then log.error(err) # else log.success(res)
