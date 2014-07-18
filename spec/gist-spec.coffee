Gist = require '../lib/gist'
nock = require 'nock'

# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "SyncSettings", ->
  gist = null
  github = null

  beforeEach ->
    gist = new Gist()
    github = nock 'https://api.github.com'

  describe "when gist list is asked", ->
    it "calls github", ->
      request = github
      .get '/gists'
      .reply 200, []

      gist.list()

      expect(request.isDone()).toBe true
