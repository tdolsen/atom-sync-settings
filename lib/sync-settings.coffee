# imports
{BufferedProcess} = require 'atom'
GitHubApi = require 'github'
_ = require 'underscore-plus'
PackageManager = require './package-manager'
fs = require 'fs'
glob = require 'glob'
CSON = require 'cson-safe'
semver = require 'semver'

# constants
DESCRIPTION = 'Atom configuration store operated by http://atom.io/packages/sync-settings'
REMOVE_KEYS = ["sync-settings"]

module.exports =
  configDefaults:
    personalAccessToken: "<Your personal GitHub access token>"
    gistId: "<Id of gist to use for configuration store>"

  manager: new PackageManager()

  activate: ->
    # for debug
    atom.workspaceView.command "sync-settings:upload", => @upload()
    atom.workspaceView.command "sync-settings:download", => @download()

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

        files["packages.cson"] = { content: CSON.stringify(atom.packages.getAvailablePackageMetadata(), ['name', 'version', 'theme'], 2) }

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
        return

      for file, data of res.files
        continue if file == "packages.cson"
        fs.writeFileSync atom.config.configDirPath + '/' + file, data.content

      atom.config.load
      @syncPackages CSON.parse(res.files["packages.cson"].content)
      cs?(err, res)

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

  filterSettings: (key, value) ->
    return value if key == ""
    return undefined if ~REMOVE_KEYS.indexOf(key)
    value
