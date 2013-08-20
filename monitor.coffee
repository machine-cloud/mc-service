async  = require("async")
dd     = require("./lib/dd")
faye   = require("faye")
log    = require("./lib/logger").init("service.monitor")
mqtt   = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis  = require("redis-url").connect(process.env.REDIS_URL)
store  = require("./lib/store").init("#{process.env.COUCHDB_URL}/mc-service")

socket = new faye.Client(process.env.FAYE_URL)

cached_rules = {}

device_add = (device) ->
  redis.zadd "devices", dd.now(), device.id, (err, added) ->
    return unless added is 1
    log.start "device.add", device, (log) ->
      async.parallel
        sadd:    (cb) -> redis.sadd "devices:#{device.model}", device.id, cb
        set:     (cb) -> redis.set "device:#{device.id}:model", device.model, cb
        sub:     (cb) ->
          socket.subscribe "/device/#{device.id.replace('.', '-')}", (message) ->
            console.log "MESSAGE", device.id, JSON.stringify(message)
            mqtt.publish "device.#{device.id}", JSON.stringify(message)
          cb()
        publish: (cb) -> socket.publish "/device/add", device, cb
        (err) -> if err then log.error(err) else log.success()

device_remove = (device) ->
  log.start "device.remove", device, (log) ->
    async.parallel
      zrem: (cb) -> redis.zrem "devices", device.id, cb
      srem: (cb) ->
        redis.get "device:#{device.id}:model", (err, model) ->
          redis.srem "devices:#{model}", device.id, cb
      publish: (cb) -> socket.publish "/device/remove", device, cb
      (err) -> if err then log.error(err) else log.success()

tick = (message) ->
  log.start "tick", key:message.key, value:message.value, (log) ->
    async.parallel
      set:     (cb) -> redis.set "metric:#{message.id}:#{message.key}", message.value, cb
      zadd:    (cb) -> redis.zadd "ticks", dd.now(), "#{message.id}.#{dd.random(8)}", cb
      publish: (cb) -> socket.publish "/tick/#{message.id.replace(".", "-")}", message, cb
      (err, res) -> if err then log.error(err) else log.success()

mqtt.on "connect", ->
  log.start "connect", (log) ->
    async.parallel
      tick: (cb) -> mqtt.subscribe "tick", cb
      (err)      -> if err then log.error(err) else log.success()

mqtt.on "message", (topic, body) ->
  message = JSON.parse(body)
  return unless message.id
  switch topic
    when "tick"
      check_rules(message)
      device_add(id:message.id, model:message.value) if message.key is "model"
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

check_rules = (message) ->
  for rule in cached_rules
    continue unless rule.condition.device is message.id
    continue unless rule.condition.output is message.key
    matched = switch rule.condition.compare
      when "<" then parseFloat(message.value) < parseFloat(rule.condition.value)
      when ">" then parseFloat(message.value) > parseFloat(rule.condition.value)
      when "=" then parseFloat(message.value) is parseFloat(rule.condition.value)
      else true
    continue unless matched
    matched_rule = rule
    log.start "rule.match", message, (log) ->
      dd.delay 500, ->
        mqtt.publish "device.sensor.20481", JSON.stringify(key:matched_rule.action.input, value:matched_rule.action.value)
        log.success()

reload_rules = ->
  store.list "rule", (err, rules) ->
    cached_rules = rules

dd.every 3000, reload_rules
reload_rules()
