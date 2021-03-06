async   = require("async")
coffee  = require("coffee-script")
crypto  = require("crypto")
dd      = require("./lib/dd")
express = require("express")
faye    = require("./lib/faye-redis-url")
force   = require("node-salesforce")
log     = require("./lib/logger").init("service.web")
mqtt    = require("./lib/mqtt-url").connect(process.env.MQTT_URL)
redis   = require("redis-url").connect(process.env.REDIS_URL)
sockjs  = require("sockjs")
stdweb  = require("./lib/stdweb")
store   = require("./lib/store").init("#{process.env.COUCHDB_URL}/mc-service")

app = stdweb("mc-service")

app.use express.cookieSession(secret:process.env.SESSION_SECRET)

app.use express.static("#{__dirname}/public")
app.use (req, res, next) ->
  res.locals.navigation = (name, path) ->
    klass = if req.path is path then "active" else ""
    "<li class=\"#{klass}\"><a href=\"#{path}\">#{name}</a></li>"
  res.locals.outputs = (model) -> dd.keys(model.outputs).join(",")
  res.locals.inputs = (model) -> dd.keys(model.inputs).join(",")
  res.locals.salesforce = req.session.salesforce
  next()
app.use app.router

app.locals.pretty = true

app.get "/", (req, res) ->
  res.redirect "/dashboard"

app.get "/dashboard", (req, res) ->
  res.render "dashboard/index.jade"

app.get "/devices", (req, res) ->
  store.list "model", (err, models) ->
    models.sort (a, b) -> a.name.localeCompare(b.name)
    res.render "devices/index.jade", models:models

app.get "/devices/:model.json", (req, res) ->
  redis.smembers "devices:#{req.params.model}", (err, devices) ->
    res.json devices.reduce(((ax, device) -> ax.push(id:device, model:req.params.model); ax), [])

app.get "/devices.json", (req, res) ->
  store.list "model", (err, models) ->
    models_by_name = {}
    models_by_name[model.name] = { name:model.name, inputs:model.inputs, outputs:model.outputs } for model in models
    redis.zrange "devices", 0, -1, (err, devices) ->
      async.map devices, ((device, cb) ->
        redis.get "device:#{device}:model", (err, model) ->
          cb null, id:device, model:models_by_name[model]),
        (err, devices) ->
          res.json devices

app.post "/message/:id", (req, res) ->
  mqtt.publish "device.#{req.params.id}", JSON.stringify(dd.merge(req.body, id:process.env.ID)), (err) ->
    res.send "ok"

app.get "/message/:id/:key/:value", (req, res) ->
  res.setHeader "Access-Control-Allow-Origin", "*"
  mqtt.publish "device.#{req.params.id}", JSON.stringify(key:req.params.key, value:req.params.value), (err) ->
    res.send "ok"

app.get "/rules", (req, res) ->
  res.render "rules/index.jade"

app.get "/rules/new", (req, res) ->
  res.render "rules/new.jade"

app.post "/rules", (req, res) ->
  rule =
    condition:
      device: req.body["condition.device"]
      output: req.body["condition.output"]
      compare: req.body["condition.compare"]
      value: req.body["condition.value"]
    action:
      device: req.body["action.device"]
      input: req.body["action.input"]
      value: req.body["action.value"]
  if rule.action.device is "salesforce"
    rule.action.salesforce = req.session.salesforce
  store.create "rule", rule, (err) ->
    res.redirect "/rules"

app.get "/rules/:id/delete", (req, res) ->
  store.delete "rule", req.params.id, (err, rule) ->
    res.redirect "/rules"

app.get "/rules.json", (req, res) ->
  store.list "rule", (err, rules) ->
    res.json rules

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
    res.json models

app.post "/canvas", (req, res) ->
  log.start "canvas.login", (log) ->
    [signature, encoded_envelope] = req.body.signed_request.split(".")
    check = crypto.createHmac("sha256", process.env.CANVAS_SECRET).update(encoded_envelope).digest("base64")
    if check is signature
      envelope = JSON.parse(new Buffer(encoded_envelope, "base64").toString("ascii"))
      req.session.salesforce = envelope
      res.redirect "/"
      log.success user:envelope.context.user.userName
    else
      res.send "invalid", 403
      log.failure()

auth_required = express.basicAuth (user, pass) ->
  if process.env.HTTP_PASSWORD then pass == process.env.HTTP_PASSWORD else true

app.get "/reset", auth_required, (req, res) ->
  sf = new force.Connection()
  sf.login process.env.CRM_USERNAME, process.env.CRM_PASSWORD, (err, user) ->
    async.parallel
      case: (aacb) ->
        sf.query "SELECT Id FROM Case", (err, result) ->
          async.parallel (result.records.map (record) ->
            (acb) ->
              sf.sobject("Case").destroy record.Id, acb),
            aacb
      chatter: (aacb) ->
        sf.query "SELECT Id FROM FeedItem", (err, result) ->
          async.parallel (result.records.map (record) ->
            (acb) ->
              sf.sobject("FeedItem").destroy record.Id, acb),
          aacb
      (err, results) ->
        console.log "err", err
        console.log "results", results
        res.send "ok"

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

log.start "listen", (log) ->
  app.start (port) ->
    log.success port:port
