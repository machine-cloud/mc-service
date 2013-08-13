async   = require("async")
coffee  = require("coffee-script")
dd      = require("./lib/dd")
express = require("express")
faye    = require("faye")
log     = require("./lib/logger").init("service.web")
redis   = require("redis-url").connect(process.env.REDISGREEN_URL)
sockjs  = require("sockjs")
stdweb  = require("./lib/stdweb")

app = stdweb("mc-service")

app.use express.static("#{__dirname}/public")
app.use (req, res, next) ->
  res.locals.navigation = (name, path) ->
    klass = if req.path is path then "active" else ""
    "<li class=\"#{klass}\"><a href=\"#{path}\">#{name}</a></li>"
  next()
app.use app.router

app.get "/", (req, res) ->
  res.redirect "/stats"

app.get "/stats", (req, res) ->
  res.render "stats.jade"

auth_required = express.basicAuth (user, pass) ->
  if process.env.HTTP_PASSWORD then pass == process.env.HTTP_PASSWORD else true

app.get "/service/mqtt", auth_required, (req, res) ->
  res.send process.env.MQTT_URL

app.get "/devices", (req, res) ->
  redis.zrange "devices", 0, -1, "WITHSCORES", (err, devices) ->
    devices = (idx for idx in [0..devices.length-1] by 2).map (idx) ->
      id: devices[idx]
      last: new Date(parseInt(devices[idx+1])).toISOString()
    res.render "devices.jade", devices:devices

socket = new faye.NodeAdapter(mount:"/faye")

# socket.bind "handshake", (client) ->
#   redis.zadd "devices", (new Date()).getTime() + 5000, client

# socket.bind "disconnect", (client) ->
#   redis.zrem "devices", client

socket.attach app.server

notifications = (key, cb) ->
  redis.multi()
    .lrange("notify:#{key}", 0, -1)
    .del("notify:#{key}")
    .exec (err, replies) ->
      cb err, replies[0]

dd.every 1000, ->
  log.start "tick.notifications", (log) ->
    async.parallel
      device_add: (cb) ->
        notifications "device:add", (err, devices) ->
          for device in devices
            socket.getClient().publish "/devices/add", id:device
          cb err
      device_remove: (cb) ->
        notifications "device:remove", (err, devices) ->
          for device in devices
            socket.getClient().publish "/devices/remove", id:device
          cb err
      tick: (cb) ->
        notifications "tick", (err, ticks) ->
          for tick in ticks
            socket.getClient().publish "/ticks", JSON.parse(tick)
      (err, res) ->
        console.log "err", err
        console.log "res", res

dd.every 1000, ->
  log.start "tick.stats", (log) ->
    async.parallel
      messages: (cb) -> redis.zcard "ticks", cb
      devices:  (cb) -> redis.zcard "devices", cb
      (err, results) ->
        stats =
          "messages": Math.round(parseInt(results.messages || "0") / 5)
          "devices": parseInt(results.devices  || "0")
        socket.getClient().publish "/stats", stats
        log.success stats

app.start (port) ->
  console.log "listening on #{port}"
