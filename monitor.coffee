log   = require("./lib/logger").init("mc-service.monitor")
mqtt  = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis = require("redis-url").connect(process.env.REDISGREEN_URL)

mqtt.on "connect", ->
  mqtt.subscribe "tick"

mqtt.on "message", (topic, body) ->
  message = JSON.parse(body)
  log.start "message", (log) ->
    switch topic
      when "tick"
        redis.incr "tick:count"
        redis.zadd "clients", (new Date()).getTime() + 10000, message.id
        #log.success message
