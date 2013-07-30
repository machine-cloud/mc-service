async   = require("async")
coffee  = require("coffee-script")
dd      = require("./lib/dd")
express = require("express")
faye    = require("faye")
log     = require("./lib/logger").init("mc-service.web")
redis   = require("redis-url").connect(process.env.REDISGREEN_URL)
sockjs  = require("sockjs")
stdweb  = require("./lib/stdweb")

app = stdweb("mc-service")

app.use express.static("#{__dirname}/public")

app.get "/", (req, res) ->
  res.render "index.jade"

socket = new faye.NodeAdapter(mount:"/faye")

# socket.bind "handshake", (client) ->
#   redis.zadd "clients", (new Date()).getTime() + 5000, client

# socket.bind "disconnect", (client) ->
#   redis.zrem "clients", client

socket.attach app.server

dd.every 1000, ->
  log.start "tick", (log) ->
    async.parallel
      messages: (cb) -> redis.get "tick:count", cb
      clients:  (cb) -> redis.zcard "clients", cb
      (err, results) ->
        redis.del "tick:count"
        redis.zremrangebyscore "clients", 0, (new Date()).getTime()
        stats =
          "message.rate": parseInt(results.messages || "0")
          "client.count": parseInt(results.clients  || "0")
        socket.getClient().publish "/stats", stats
        log.success stats

app.start (port) ->
  console.log "listening on #{port}"
