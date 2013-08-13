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

app.get "/", (req, res) ->
  res.render "index.jade"

auth_required = express.basicAuth (user, pass) ->
  if process.env.HTTP_PASSWORD then pass == process.env.HTTP_PASSWORD else true

app.get "/service/mqtt", auth_required, (req, res) ->
  res.send process.env.MQTT_URL

app.get "/devices", (req, res) ->
  redis.zrange "devices", 0, -1, "WITHSCORES", (err, devices) ->
    devices = ({id:devices[idx], last:parseInt(devices[idx+1])} for idx in [0..(devices.length-1)] by 2)
    res.render "devices.jade", devices:devices

socket = new faye.NodeAdapter(mount:"/faye")

# socket.bind "handshake", (client) ->
#   redis.zadd "devices", (new Date()).getTime() + 5000, client

# socket.bind "disconnect", (client) ->
#   redis.zrem "devices", client

socket.attach app.server

dd.every 1000, ->
  log.start "tick", (log) ->
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
