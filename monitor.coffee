log   = require("./lib/logger").init("mc-service.monitor")
mqtt  = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis = require("redis-url").connect(process.env.REDISGREEN_URL)

mqtt.on "connect", ->
  log.start "connect", (log) ->
    mqtt.subscribe "tick", (err) ->
      if err then log.error(err) else log.success()

mqtt.on "message", (topic, body) ->
  message = JSON.parse(body)
  return unless message.id
  log.start "message", (log) ->
    switch topic
      when "tick"
        redis.incr "tick:count"
        redis.zadd "clients", (new Date()).getTime() + 5000, message.id
        log.success message
