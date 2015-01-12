# imports
_ = require 'underscore-plus'
fs = require 'fs'
GitHubApi = require 'github'
PackageManager = require './package-manager'

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

  activate: ->

    atom.workspaceView.command "sync-settings:upload", => @upload()
    atom.workspaceView.command "sync-settings:download", => @download()

    @periodicSync()

  periodicSync: ->
    @upload()
    setTimeout @periodicSync.bind(this), atom.config.get('sync-settings.autoUpdateFrequency') * 1000

  deactivate: ->

  serialize: ->

  upload: (cb=null) ->
    files =
      "settings.json":
        content: JSON.stringify(atom.config.settings, @filterSettings, '\t')
      "packages.json":
        content: JSON.stringify(@getPackages(), null, '\t')
      "keymap.cson":
        content: @fileContent atom.keymap.getUserKeymapPath()
      "styles.less":
        content: @fileContent atom.themes.getUserStylesheetPath()
      "init.coffee":
        content: @fileContent atom.config.configDirPath + "/init.coffee"
      "snippets.cson":
        content: @fileContent atom.config.configDirPath + "/snippets.cson"

    @createClient().gists.edit
      id: atom.config.get 'sync-settings.gistId'
      description: "automatic update by http://atom.io/packages/sync-settings"
      files: files
    , (err, res) =>
      console.error "error uploading data: "+err.message, err if err
      cb?(err, res)

  getPackages: ->
    for name,info of atom.packages.getLoadedPackages()
      {name, version, theme} = info.metadata
      {name, version, theme}

  download: (cb=null) ->
    @createClient().gists.get
      id: atom.config.get 'sync-settings.gistId'
    , (err, res) =>
      if err
        console.error("error while retrieving the gist. does it exists?", err)
        return

      settings = JSON.parse(res.files["settings.json"].content)
      console.debug "settings: ", settings
      @applySettings "", settings

      packages = JSON.parse(res.files["packages.json"].content)
      console.debug "packages: ", packages
      @installMissingPackages packages, cb

      keymap = res.files['keymap.cson']?.content
      console.debug "keymap.cson = ", res.files['keymap.cson']?.content
      fs.writeFileSync(atom.keymap.getUserKeymapPath(), res.files['keymap.cson'].content) if keymap

      styles = res.files['styles.less']?.content
      console.debug "styles.less = ", res.files['styles.less']?.content
      fs.writeFileSync(atom.themes.getUserStylesheetPath(), res.files['styles.less'].content) if styles

      initCoffee = res.files['init.coffee']?.content
      console.debug "init.coffee = ", initCoffee
      fs.writeFileSync(atom.config.configDirPath + "/init.coffee", initCoffee) if initCoffee

      snippetsCson = res.files['snippets.cson']?.content
      console.debug "snippets.cson = ", snippetsCson
      fs.writeFileSync(atom.config.configDirPath + "/snippets.cson", snippetsCson) if snippetsCson

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

  filterSettings: (key, value) ->
    return value if key == ""
    return undefined if ~REMOVE_KEYS.indexOf(key)
    value

  applySettings: (pref, settings) ->
    for key, value of settings
      keyPath = "#{pref}.#{key}"
      if _.isObject(value) and not _.isArray(value)
        @applySettings keyPath, value
      else
        console.debug "config.set #{keyPath[1...]}=#{value}"
        atom.config.set keyPath[1...], value

  installMissingPackages: (packages, cb) ->
    pending=0
    for pkg in packages
      continue if atom.packages.isPackageLoaded(pkg.name)
      pending++
      @installPackage pkg, ->
        pending--
        cb?() if pending is 0
    cb?() if pending is 0

  installPackage: (pack, cb) ->
    type = if pack.theme then 'theme' else 'package'
    console.info("Installing #{type} #{pack.name}...")
    packageManager = new PackageManager()
    packageManager.install pack, (error) =>
      if error?
        console.error("Installing #{type} #{pack.name} failed", error.stack ? error, error.stderr)
      else
        console.info("Installed #{type} #{pack.name}")
      cb?(error)

  fileContent: (filePath) ->
    DEFAULT_CONTENT = '# keymap file'
    try
      return fs.readFileSync(filePath, {encoding: 'utf8'}) || DEFAULT_CONTENT
    catch e
      console.error "Error reading file #{filePath}. Probably doesn't exists.", e
      DEFAULT_CONTENT
