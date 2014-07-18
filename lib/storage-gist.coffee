gist = require './gist'

module.exports =
class StorageGist

  GIST_DESCRIPTION = 'Atom Settings by sync-settings'

  constructor: ->
    @gist = new gist()

  backupGist: ->
    list = @gist.list
      description: GIST_DESCRIPTION
      files:
        '.sync-settings': ->
          true
    list[0]

  hasBackup: ->
    @backupGist()?
