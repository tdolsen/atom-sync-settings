# imports
_ = require 'underscore-plus'
fs = require 'fs'
GitHubApi = require 'github'
PackageManager = require './package-manager'
glob = require 'glob'
CSON = require 'cson-safe'
semver = require 'semver'

# constants
DESCRIPTION = 'Atom configuration store operated by http://atom.io/packages/sync-settings'
REMOVE_KEYS = ["sync-settings"]

module.exports = new class SyncSettings
  # Public attributes
  config:
    personalAccessToken:
        type: "string"
        description: "Your personal GitHub access token"
        default: ""
    gistId:
        type: "string"
        description: "Id of gist to use for configuration store"
        default: ""
    autoUpdateFrequency:
        default: 10*60*10
        type: 'number'
        min: 1000
        description: "Number of seconds between automatic updates. Default: 10 minutes."

  manager: new PackageManager()

  activate: ->

    atom.workspaceView.command "sync-settings:upload", => @upload()
    atom.workspaceView.command "sync-settings:download", => @download()

    #@periodicSync()

  periodicSync: ->
    @upload()
    setTimeout @periodicSync.bind(this), atom.config.get('sync-settings.autoUpdateFrequency') * 1000

  deactivate: ->

  serialize: ->

  createClient: ->
    token = atom.config.get 'sync-settings.personalAccessToken'
    console.debug "Creating GitHubApi client with token = #{token}"
    github = new GitHubApi
      version: '3.0.0'
      debug: true
      protocol: 'https'
    github.authenticate
      type: 'oauth'
      token: token
    github

  upload: (cb=null) ->
    # Get all files in `.atom` folder
    files = {}
    glob '*', {
        cwd: atom.config.configDirPath
        dot: true
        nodir: true
    }
    , (err, matches) =>
        console.log "error reading config path", err if err

        matches.forEach (file, i) =>
            files[file] = { content: @fileContent file }

        files["packages.cson"] = { content: @getPackages }

        @createClient().gists.edit
          id: atom.config.get 'sync-settings.gistId'
          description: "automatic update by http://atom.io/packages/sync-settings"
          files: files
        , (err, res) =>
          console.error "error uploading data: "+err.message, err if err
          cb?(err, res)

  fileContent: (file) ->
    path = atom.config.configDirPath + '/' + file
    try
      return fs.readFileSync(path, {encoding: 'utf8'})
    catch e
      console.error "Error reading file #{path}. Probably doesn't exists.", e
    false

  download: (cb=null) ->
    @createClient().gists.get
      id: atom.config.get 'sync-settings.gistId'
    , (err, res) =>
      if err
        console.error "error while retrieving the gist. does it exists?", err
        message = JSON.parse(err.message).message
        message = 'Gist ID Not Found' if message == 'Not Found'
        atom.notifications.addError "sync-settings: Error retrieving your settings. ("+message+")"
        return

      for file, data of res.files
        continue if file == "packages.cson"
        fs.writeFileSync atom.config.configDirPath + '/' + file, data.content

      atom.config.load
      @syncPackages CSON.parse(res.files["packages.cson"].content)
      cs?(err, res)

  getPackages: () ->
    packages = atom.packages.getAvailablePackageMetadata().map (pkg) ->
      p = {name: pkg.name, version: pkg.version}
      p.theme = pkg.theme if pkg.theme
      p

    console.log(packages)
    return CSON.stringify(packages, null, 2)

  syncPackages: (packages, cb) ->
    metadata = {}

    atom.packages.getAvailablePackageMetadata().forEach (pkg) ->
      metadata[pkg.name] = pkg

    packages.forEach (pkg, i) =>
      current = metadata[pkg.name]
      return @installPackage pkg, cb if !current
      console.log(pkg.name, current.version, pkg.version)
      return @updatePackage pkg, cb if semver.neq current.version || "0.0.0", pkg.version

  installPackage: (pkg, cb) ->
    type = if pkg.theme then pkg.theme else 'package'
    console.log "installing package '#{ pkg.name }', type: #{ type }, version: #{ pkg.versions }"
    @manager.install pkg, (err) =>
      if err?
        console.error "installation of package '#{ pkg.name }' failed"
      else
        console.info "installation of package '#{ pkg.name }' was successful"
      cb?(err)

  updatePackage: (pkg, cb) ->
    console.log "updating package '#{ pkg.name }' to version #{ pkg.version }"
    @manager.update pkg, pkg.version, (err) =>
      if err?
        console.error "updating of package '#{ pkg.name }' failed"
      else
        console.info "updating of package '#{ pkg.name }' was successful"
      cb?(err)
      atom.notifications.addSuccess "sync-settings: Your settings were successfully synchronized."
