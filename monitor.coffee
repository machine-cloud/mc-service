async    = require("async")
dd       = require("./lib/dd")
faye     = require("faye")
log      = require("./lib/logger").init("service.monitor")
mqtt     = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis    = require("redis-url").connect(process.env.REDIS_URL)
sf       = require("node-salesforce")
store    = require("./lib/store").init("#{process.env.COUCHDB_URL}/mc-service")
strftime = require("strftime")

socket = new faye.Client(process.env.FAYE_URL)

cached_rules = []

device_add = (device) ->
  redis.zadd "devices", dd.now(), device.id, (err, added) ->
    return unless added is 1
    log.start "device.add", device, (log) ->
      async.parallel
        sadd:    (cb) -> redis.sadd "devices:#{device.model}", device.id, cb
        set:     (cb) -> redis.set "device:#{device.id}:model", device.model, cb
        sub:     (cb) ->
          socket.subscribe "/device/#{device.id.replace('.', '-')}", (message) ->
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
  try
    message = JSON.parse(body)
    return unless message.id
    switch topic
      when "tick"
        check_rules(message)
        device_add(id:message.id, model:message.value) if message.key is "model"
        tick message if message.key
  catch err
    console.log "message parse error", err

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
  store.list "model", (err, data) ->
    models = dd.inject(data, {}, (ax, model) -> ax[model.name] = model; ax)
    cached_rules.forEach (rule) ->
      redis.get "device:#{rule.condition.device}:model", (err, model) ->
        return unless rule.condition.device is message.id
        return unless rule.condition.output is message.key
        switch models[model].outputs[rule.condition.output]
          when "string"
            matched = switch rule.condition.compare
              when "<" then message.value < rule.condition.value
              when ">" then message.value > rule.condition.value
              when "=" then message.value is rule.condition.value
              else false
            return unless matched
          when "integer", "float"
            matched = switch rule.condition.compare
              when "<" then parseFloat(message.value) < parseFloat(rule.condition.value)
              when ">" then parseFloat(message.value) > parseFloat(rule.condition.value)
              when "=" then parseFloat(message.value) is parseFloat(rule.condition.value)
              else false
            return unless matched
        matched_rule = rule
        log.start "rule.match", message, (log) ->
          redis.setnx "rule:#{matched_rule._id}", strftime("%Y-%m-%d %H:%M:%S"), (err, locked) ->
            return unless locked is 1
            redis.expire "rule:#{matched_rule._id}", parseInt(process.env.RULE_TIMEOUT || "30"), (err, foo) ->
              if matched_rule.action.device is "salesforce"
                force = new sf.Connection()
                force.login process.env.RULE_USERNAME, process.env.RULE_PASSWORD, (err, user) ->
                  console.log "err", err
                  console.log "user", user
                  switch matched_rule.action.input
                    when "case"
                      force.sobject('Case').create
                        OwnerId: process.env.OWNER_ID || "005i0000000dHa7"
                        Reason: "Device Offline"
                        ContactId: process.env.CONTACT_ID || '003i0000008BypF'
                        Device_Id__c: matched_rule.condition.device
                        (err, ret) ->
                          if err then log.error(err) else log.success case:ret.id
                    when "chatter"
                      body =
                        createdById: process.env.CHATTER_POSTER_ID,
                        messageSegments: [
                          { type: "mention", id: matched_rule.action.salesforce.userId },
                          { type: "text", text: " " },
                          { type: "text", text: matched_rule.action.value || "Testing Chatter" }
                        ]
                      force._request
                        method: "POST"
                        url: force.urls.rest.base + "/chatter/feeds/record/#{process.env.CHATTER_GROUP_ID}/feed-items"
                        body: JSON.stringify(body:body)
                        headers:
                          "Content-Type": "application/json"
                        (err, data) ->
                          if err then log.error(err) else log.success chatter:data.id
              else
                dd.delay 500, ->
                  mqtt.publish "device.#{matched_rule.action.device}", JSON.stringify(key:matched_rule.action.input, value:matched_rule.action.value)
                  log.success()

reload_rules = ->
  store.list "rule", (err, rules) ->
    cached_rules = rules

dd.every 3000, reload_rules
reload_rules()
