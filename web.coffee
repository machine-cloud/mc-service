async   = require("async")
coffee  = require("coffee-script")
dd      = require("./lib/dd")
express = require("express")
faye    = require("./lib/faye-redis-url")
log     = require("./lib/logger").init("service.web")
redis   = require("redis-url").connect(process.env.REDIS_URL)
sockjs  = require("sockjs")
stdweb  = require("./lib/stdweb")
store   = require("./lib/store").init("#{process.env.COUCHDB_URL}/mc-service")

app = stdweb("mc-service")

app.use express.static("#{__dirname}/public")
app.use (req, res, next) ->
  res.locals.navigation = (name, path) ->
    klass = if req.path is path then "active" else ""
    "<li class=\"#{klass}\"><a href=\"#{path}\">#{name}</a></li>"
  res.locals.outputs = (model) ->
    dd.keys(model.outputs).join(",")
  next()
app.use app.router

app.locals.pretty = true

app.get "/", (req, res) ->
  res.redirect "/stats"

app.get "/stats", (req, res) ->
  res.render "stats/index.jade"

app.get "/devices", (req, res) ->
  store.list "model", (err, models) ->
    models.sort (a, b) -> a.name.localeCompare(b.name)
    res.render "devices/index.jade", models:models

app.get "/devices/:model.json", (req, res) ->
  redis.smembers "devices:#{req.params.model}", (err, devices) ->
    res.json devices.reduce(((ax, device) -> ax.push(id:device, model:req.params.model); ax), [])

app.get "/models", (req, res) ->
  res.render "models/index.jade"

app.get "/models/new", (req, res) ->
  res.render "models/new.jade"

app.post "/models", (req, res) ->
  store.create "model", dd.merge(JSON.parse(req.body.body), name:req.body.name), (err, model) ->
    res.redirect "/models"

app.get "/models/:id/edit", (req, res) ->
  store.fetch "model", req.params.id, (err, model) ->
    res.render "models/edit.jade", model:model

app.post "/models/:id", (req, res) ->
  store.fetch "model", req.params.id, (err, model) ->
    store.update "model", req.params.id, dd.merge(JSON.parse(req.body.body), name:req.body.name), (err, model) ->
      res.redirect "/models"

app.get "/models/:id/delete", (req, res) ->
  store.delete "model", req.params.id, (err, model) ->
    res.redirect "/models"

app.get "/models.json", (req, res) ->
  store.list "model", (err, models) ->
    console.log "models", models
    res.json models

auth_required = express.basicAuth (user, pass) ->
  if process.env.HTTP_PASSWORD then pass == process.env.HTTP_PASSWORD else true

app.get "/service/mqtt", auth_required, (req, res) ->
  res.send process.env.MQTT_URL

socket = faye.init(process.env.REDIS_URL)

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
  log.start "tick.stats", (log) ->
    async.parallel
      messages: (cb) -> redis.zcard "ticks", cb
      devices:  (cb) -> redis.zcard "devices", cb
      (err, results) ->
        stats =
          "messages": Math.round(parseInt(results.messages || "0") / 5)
          "devices": parseInt(results.devices  || "0")
        socket.getClient().publish "/stats", stats
        # log.success stats

app.start (port) ->
  console.log "listening on #{port}"
