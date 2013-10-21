# # Karma Browserify

# This plugin adds a `browserify` framework and preprocessor to the Karma test
# runner.

crypto = require 'crypto'
path = require 'path'
os = require 'os'
fs = require 'fs'
browserify = require 'browserify'
through = require 'through'
chokidar = require 'chokidar'
bundleConfig = null

# The dependency cache stores all browserify dependencies.
depsCache = []

# The temporary `karma-browserify.js` file path.
tmp = null

# The safe configuration keys to apply to the browserify bundles.
configs = ['extension', 'transform', 'ignore']

# Create a MD5 hash for browserify export names.
hash = (what) -> crypto.createHash('md5').update(what).digest('base64').slice 0, 6

# Apply select keys from a configuration object to a browserify bundle.
applyConfig = (b, cfg) ->
  (b[c] v for v in [].concat cfg[c] if cfg?[c]? and b?[c]?) for c in configs

refreshDeps = (files, callback) ->
  newFiles = false

  # add dependencies if they're not already in the cache
  for d in files when d not in depsCache
    depsCache.push d
    newFiles = true

  if newFiles
    # there are new dependencies so rebuild the dependency bundle
    writeDeps callback
  else
    # there are no new dependencies so no need to rebuild the dependency bundle
    callback() if callback?


# Write the dependency bundle out to the temporary file.
writeDeps = (callback) ->
  depsBundle = browserify()
  applyConfig depsBundle, bundleConfig

  for d in depsCache
    depsBundle.require d, expose: d
    # watch the dependency in case it changes
    watch d if bundleConfig.watch

  depsBundle.bundle (err, depsContent) ->
    return err if err
    fs.writeFile tmp, depsContent, (err) ->
      return err if err
      callback() if callback?

# Watch the dependency files for changes.
watcher = null
watch = (file) ->
  return watcher.add file if watcher?
  watcher = chokidar.watch file
  watcher.on 'change', -> writeDeps()

# ## Framework

# The karma-browserify framework creates a global bundle for all browserify
# dependencies that are not top-level Karma files.
framework = (files, config) ->
  # Create an empty temp file for the global dependency bundle and add it to the
  # Karma files list.
  tmp = path.join (if os.tmpdir then os.tmpdir() else os.tmpDir()), 'karma-browerify.js'
  fs.writeFileSync tmp, ''
  files.unshift pattern: tmp, included: true, served: true, watched: true

  bundleConfig = config

# ## Preprocessor
preprocessor = (logger, config) ->
  # Create a logger.
  log = logger.create 'preprocessor.browserify'

  # The preprocessor callback is called for each file that matches its pattern.
  (content, file, done) ->
    log.debug 'Processing "%s".', file.originalPath

    # Create a file-specific browserify bundle and apply the configuration.
    fileBundle = browserify path.normalize file.originalPath
    applyConfig fileBundle, config

    # Override the bundle's default dependency handling, adding all dependencies
    # to the dependency cache and excluding them from the file bundle by passing
    # a proxy module which requires the absolute dependency reference.
    newDeps = []
    deps = (opts) ->
      fileBundle.deps(opts).pipe through (row) ->
        if row.id isnt file.originalPath
          newDeps.push row.id unless row.id in newDeps
          row.source = "module.exports=require('#{hash row.id}');"
        @queue row

    # Build the file bundle.
    fileBundle.bundle deps: deps, (err, fileContent) ->
      # refresh the dependency bundle if there are new dependencies
      refreshDeps newDeps, -> done fileContent

framework.$inject = ['config.files', 'config.browserify']
preprocessor.$inject = ['logger', 'config.browserify']
module.exports =
  'preprocessor:browserify': ['factory', preprocessor]
  'framework:browserify': ['factory', framework]
