fs = require 'fs'
https = require 'https'
path = require 'path'
q = require 'q'

module.exports =
class Gist

  constructor: ->
      @description = ""

  getSecretTokenPath: ->
    path.join(atom.getConfigDirPath(), "sync-settings-gist.token")

  getToken: ->
    if not @token?
      config = atom.config.get("sync-settings.personalAccessToken")
      @token = if config? and config.toString().length > 0
                 config
               else if fs.existsSync(@getSecretTokenPath())
                 fs.readFileSync(@getSecretTokenPath())
    @token

  post: (data, callback) ->
    request = https.request @options {method: 'POST'}, (res) ->
      res.setEncoding "utf8"
      body = ''
      res.on "data", (chunk) ->
        body += chunk
      res.on "end", ->
        response = JSON.parse(body)
        console.log response
        callback(response)

    request.write(JSON.stringify(@toParams(data)))

    request.end()

  toParams: (data) ->
    description: @description
    files:
      "settings.json":
        content: JSON.stringify data

  options: ({path, method}={}) ->
    path ?= '/gists'
    method ?= 'GET'

    options =
      hostname: 'api.github.com'
      path: path
      method: method
      headers:
        "User-Agent": "Atom Sync Settings"

    # Use the user's token if we have one
    if @getToken()?
      options.headers["Authorization"] = "token #{@getToken()}"

    options


  list: (filter={}) ->
    deferred = q.defer()
    https.request @options(), (res) ->
      res.setEncoding "utf8"
      body = ''
      res.on "data", (chunk) ->
        body += chunk
      res.on "end", ->
        response = JSON.parse(body)
        console.log response
        deferred.resolve response
    .end()
    deferred.promise
