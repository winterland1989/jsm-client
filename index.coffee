path = require 'path'
http = require 'http'
querystring = require 'querystring'
url = require 'url'
fs = require 'fs-extra'
Promise = require 'bluebird'
webpack = require 'webpack'
MemoryFS = require "memory-fs"
packageJson = require './package.json'
express = require 'express'
tinylr = (require 'tiny-lr')()

CONFIG_FILE_NAME = '.jsm.json'
DEFAULT_REPOSITORY = 'http://jsm.winterland.me'

jsmPath = __dirname

home = process.env[ if process.platform == 'win32' then 'USERPROFILE' else 'HOME' ]
configFile = path.join home, CONFIG_FILE_NAME

extMap =
    '.ls': 'livescript'
    '.coffee': 'coffeescript'
    '.js': 'javascript'
    '.jsx': 'jsx'

commentStartMap =
    'livescript': '#'
    'coffeescript': '#'
    'javascript': '//'
    'jsx': '//'

getExt = (language) ->
    for ext, lan of extMap
        if lan == language then return ext

    return ''

parseKeywords = (content, language) ->
    keywordMark = "#{commentStartMap[language]}-jsm-keywords:"
    for line in content.split '\n'
        if (line.indexOf keywordMark) == 0
            keywords = line.substr(keywordMark.length).split ' '
            break
    keywords ?= []
    keywords.filter (word) -> word.match /\w+/g

parseIfUpdate = (content, language) ->
    updateMark = "#{commentStartMap[language]}-jsm-update:"
    for line in content.split '\n'
        if (line.indexOf updateMark) == 0
            words = line.substr(updateMark.length).split ' '
            if (words.indexOf 'false') != -1
                return false
    return true

makeWebpackConfig = (entryPaths) ->
    entryMap = {}
    for filePath in entryPaths
        {name} = path.parse filePath
        entryMap[name] = './' +  path.normalize filePath

    """
    var path = require('path');

    module.exports = {
        context: __dirname,
        entry:
            #{JSON.stringify entryMap, null, 4},
        output: {
            path: __dirname,
            filename: "[name].bundle.js"
        },
        module: {
            loaders: [
                { test: /\.coffee$/, loader: "coffee-loader" },
                { test: /\.(coffee\.md|litcoffee)$/, loader: "coffee-loader?literate" },
                { test: /\.ls/, loader: "livescript-loader" },
                { test: /\.jsx$/, loader: 'babel'}
            ]
        },
        resolve: {
            extensions: ["", ".coffee", ".js", ".ls", ".jsx"]
        },
        resolveLoader: {
            root: path.join("#{jsmPath}", "node_modules")
        }
    };
    """

makeWebpackConfigObj = (entryPaths) ->
    entry: entryPaths
    output:
        path: '/'
        filename: "temp.js"

    module:
        loaders: [
            { test: /\.coffee$/, loader: "coffee-loader" }
            { test: /\.(coffee\.md|litcoffee)$/, loader: "coffee-loader?literate" }
            { test: /\.ls/, loader: "livescript-loader" }
            { test: /\.jsx$/, loader: 'babel'}
        ]
    resolve:
        extensions:
            ["", ".json", ".js", ".coffee", ".ls", ".jsx"]
    resolveLoader:
        root: path.join(jsmPath, "node_modules")

parseRequires = (entryPaths) ->
    new Promise (resolve, reject) ->
        fsm = new MemoryFS()
        c = webpack(makeWebpackConfigObj entryPaths)
        c.outputFileSystem = fsm
        c.run (err, status) ->
            if err then reject err
            else resolve(
                existRequires: removeDuplicatedPath(
                    status.compilation.fileDependencies.filter((p) -> p not in entryPaths)
                )
                missingRequires: removeDuplicatedPath(status.compilation.missingDependencies)
                existRequiresWithExt: (
                    status.compilation.fileDependencies.filter((p) -> p not in entryPaths)
                )

            )

removeDuplicatedPath = (paths) ->
    removeExt = for filePath in paths
        {dir, name} = path.parse filePath
        path.join(dir, name)

    result = []
    for filePath in removeExt
        if (filePath not in result) and ((path.extname filePath) == '')
            result.push filePath
    result



readJsmClientConfig = ->
    if (fs.existsSync configFile)
        f = fs.readFileSync configFile, encoding: 'utf8'
        conf = JSON.parse f
        if conf.repository then conf
        else throw new Error "Parse config failed..."
    else
        repository: DEFAULT_REPOSITORY


writeJsmClientConfig = (conf) ->
    f = fs.writeFileSync configFile, (JSON.stringify conf) , encoding: 'utf8'


parseEntry = parseEntry = (filePath) ->
    filePath = path.normalize filePath
    ext = path.extname filePath
    base = path.basename filePath, ext
    dir = path.basename(path.dirname filePath)

    titleMatch = base.match /^([a-zA-Z]+)/g
    title = if titleMatch? then titleMatch[0] else throw new Error "Parse entry name failed: " + filePath

    versionMatch = base.match /([0-9]+)$/g
    version = if versionMatch? then parseInt versionMatch[0] else 0

    authorMatch = dir.match /^(\w+)$/g
    author = if authorMatch? then authorMatch[0] else undefined


    title: title
    version: version
    author: author
    language: if ext == '' then undefined else extMap[ext]


publish = (conf, entry, entryPath) ->

    entry.content = fs.readFileSync entryPath, encoding: 'utf8'

    {hostname, port} = url.parse conf.repository

    jsmKeywords = (parseKeywords entry.content, entry.language)

    transformedTitle = ''
    for c in entry.title
        if  'A' <= c <= 'Z' then transformedTitle += ',' + c.toLowerCase()
        else transformedTitle += c
    transformedTitle

    titleKeywords = (transformedTitle.split ',').filter (w) -> w != ''

    if titleKeywords.length == 1 then jsmKeywords.push entry.title.toLowerCase()
    else jsmKeywords = (jsmKeywords.concat titleKeywords).map (w) -> w.toLowerCase()

    entry.keywords = JSON.stringify jsmKeywords
    console.log "Entry keywords: #{entry.keywords}"

    parseRequires [entryPath]
    .then ({existRequires, missingRequires}) ->

        allRequires = (existRequires.concat missingRequires)
        allRequires = allRequires.filter (req) ->
            (req.indexOf 'jsm-client/node_modules/webpack/buildin/module') == -1
        console.log "Find all requirements:"
        for req in allRequires then console.log req
        Promise.all(
            for req in allRequires then do (req=req) ->
                reqObj  = parseEntry req
                reqTitle = reqObj.author + '/' +reqObj.title
                console.log "Checking #{reqTitle}..."
                getData = querystring.stringify(
                    title: reqObj.title
                    author: reqObj.author
                    version: reqObj.version
                )
                new Promise (resolve, reject) ->
                    chunks = []
                    req = http.request(
                            hostname: hostname
                            port: port
                            path: '/snippet?' + getData
                            method: 'GET'
                        ,   (res) ->
                                if res.statusCode == 200
                                    res.on 'data', (data) -> chunks.push data
                                    res.on 'end', ->
                                        snippet = JSON.parse Buffer.concat(chunks).toString('utf8')
                                        if snippet.id
                                            console.log "Checking #{reqTitle} OK..."
                                            resolve snippet.id
                                        else
                                            console.log "Checking #{reqTitle} Fail..."
                                            reject 'Module id error'
                                else
                                    console.log "Checking #{reqTitle} Fail with: " + res.statusCode
                                    reject "Checking #{reqTitle} Failed..."
                    )
                    req.on 'error', onErr = (e) -> reject e
                    req.end()
        )
    .then(
        (ids) ->
            console.log 'Check requires finish...'
            entry.requires = JSON.stringify ids
            postData = querystring.stringify entry
            chunks = []
            req = http.request(
                    hostname: hostname
                    port: port
                    path: '/snippet'
                    method: 'POST'
                    headers:
                        'Content-Type': 'application/x-www-form-urlencoded'
                        'Content-Length': postData.length
                ,   (res) ->
                        res.on 'data', (data) -> chunks.push data
                        res.on 'end',  ->
                            if res.statusCode == 200
                                console.log 'Publish finish with status: 200'
                                snippet = JSON.parse Buffer.concat(chunks).toString('utf8')
                                console.log 'Revision ' + snippet.revision + ' at ' + snippet.mtime
                            else console.log ('Publish failed with status: ' + res.statusCode)
                )
            req.on 'error', (e) -> console.log ('Network error...')
            req.write postData
            req.end()

    ,
        (e) -> console.log e
    )

deprecate = (conf, entryObj) ->
    {hostname, port} = url.parse conf.repository
    delete entryObj.language
    req = http.request(
        hostname: hostname
        port: port
        path: '/snippet?' + querystring.stringify entryObj
        method: 'DELETE'
    ,   (res) ->

            res.on 'data', (data) ->

            res.on 'end', ->
                if res.statusCode == 200
                    console.log "#{entryObj.author}/#{entryObj.title}#{entryObj.version} DEPRECATED"
                else
                    console.log "DEPRECATED Failed with status: #{res.statusCode}"
    )
    req.on 'error', -> console.log "Network failed"
    req.end()


failedPath = []
underJsm = (filePath) -> 'jsm' in (filePath.split path.sep)

install = (conf, entryPaths) ->
    parseRequires(entryPaths)
    .then ({existRequires, missingRequires}) ->
        Promise.all(
            for filePath in missingRequires then do (filePath = filePath) ->
                if filePath in failedPath then Promise.resolve filePath
                else new Promise (resolve, reject) ->
                    if underJsm filePath
                        entryObj  = parseEntry filePath
                        chunks = []
                        if entryObj.author? and entryObj.title? and entryObj.version?
                            {hostname, port} = url.parse conf.repository
                            delete entryObj.language

                            req = http.request(
                                hostname: hostname
                                port: port
                                path: '/snippet?' + querystring.stringify entryObj
                                method: 'GET'
                            ,   (res) ->
                                    res.on 'data', (data) ->
                                        chunks.push data
                                    res.on 'end', ->
                                        if res.statusCode == 200
                                            try
                                                snippet = JSON.parse Buffer.concat(chunks).toString('utf8')
                                                if (path.extname filePath) == ''
                                                    filePath += getExt snippet.language

                                                fs.ensureFileSync filePath
                                                fs.writeFileSync filePath, snippet.content

                                                console.log "Installing snippet: #{filePath} succeessfully"
                                                resolve filePath

                                            catch e
                                                console.log "Install snippet failed(#{e.message}): #{filePath}"
                                                resolve filePath
                                        else
                                            console.log "Download snippet failed(status#{res.statusCode}): #{filePath}"
                                            failedPath.push filePath
                                            resolve filePath
                            )
                            req.on 'error', (e) ->
                                console.log "Get snippet failed(#{e.message}): #{filePath}"
                                console.log ('Network error...')
                                resolve filePath

                            req.end()

                        else console.log "Parse entry failed: " + filePath
        )
        .then (allPaths) ->
            missingRequires = missingRequires.filter (p) -> p not in allPaths
            if missingRequires.length > 0
                install(conf, entryPaths)

update = (conf, entryPaths) ->
    parseRequires entryPaths
    .then ({existRequiresWithExt, missingRequires}) ->
        if missingRequires.length
            console.log "Missing requires found: "
            for p in missingRequires then console.log p
            console.log "Try run jsm i | install before update"


        for filePath in existRequiresWithExt then do (filePath = filePath) ->
            if underJsm filePath
                entryObj  = parseEntry filePath
                chunks = []
                if entryObj.author? and entryObj.title? and entryObj.version?
                    {hostname, port} = url.parse conf.repository
                    delete entryObj.language
                    req = http.request(
                        hostname: hostname
                        port: port
                        path: '/snippet?' + querystring.stringify entryObj
                        method: 'GET'
                    ,   (res) ->
                            res.on 'data', (data) ->
                                chunks.push data
                            res.on 'end', ->
                                if res.statusCode == 200
                                    try
                                        snippet = JSON.parse Buffer.concat(chunks).toString('utf8')
                                        oldContent = fs.readFileSync filePath, encoding: 'utf8'

                                        {dir, name, ext: oldExtname} = path.parse filePath
                                        newExtname = (getExt snippet.language)

                                        if oldExtname != newExtname
                                            console.log 'Language change found:'
                                            console.log filePath
                                            fs.removeSync filePath
                                            console.log 'Remove old snippet done'
                                            filePath = path.join(dir, name) + (getExt snippet.language)

                                        if parseIfUpdate(oldContent, extMap[oldExtname])
                                            if oldContent != snippet.content
                                                fs.writeFileSync filePath, snippet.content
                                                console.log "Update snippet: #{filePath} succeessfully @ revision#{snippet.revision}"
                                            else
                                                console.log "No update found, skip snippet: #{filePath}"
                                        else console.log "Force no update[-jsm-update: false], skip snippet: #{filePath}"

                                        if snippet.deprecated
                                            console.log "Snippet: #{filePath} DEPRECATED !!!"

                                    catch e
                                        console.log "Update snippet failed(#{e.message}): #{filePath}"
                                else
                                    console.log "Download snippet failed(status#{res.statusCode}): #{filePath}"
                                    failedPath.push filePath
                    )
                    req.on 'error', (e) ->
                        console.log "Get snippet failed(#{e.message}): #{filePath}"
                        console.log ('Network error...')

                    req.end()

                else
                    console.log "Can't parse path: "
                    console.log filePath

server = (entryPath, port) ->
    {name} = path.parse entryPath
    c = webpack(makeWebpackConfigObj entryPath)
    fsm = new MemoryFS()
    c.outputFileSystem = fsm
    started = false
    c.watch
            aggregateTimeout: 300
            poll: true
        ,
            (err, stats) ->
                if err then console.log err
                else
                    jsonStats = stats.toJson()
                    if(jsonStats.errors.length > 0)
                        console.log "Error during packing: "
                        for e in jsonStats.errors
                            console.log e
                    else
                        if started == false
                            if(jsonStats.warnings.length > 0)
                                console.log "Warning during packing: "
                                for w in jsonStats.warnings
                                    console.log w

                            app = express()

                            app.get '/', (req, res) ->
                                res.send(
                                    """
                                    <!DOCTYPE html>
                                        <html><head>
                                            <script>
                                                document.write('<script src="http://' + (location.host || 'localhost').split(':')[0] + ':35729/livereload.js?snipver=1"></' + 'script>')
                                            </script></head>
                                            <body><script src='/#{name}.js'></script></body>
                                        </html>
                                    """
                                )

                            app.get "/#{name}.js" , (req, res) ->
                                res.set 'Content-Type', 'application/javascript'
                                res.send fsm.readFileSync('/temp.js')

                            app.listen(port)

                            tinylr.listen 35729, ->
                              console.log 'Live-reload listening on 35729'

                            started = true
                            console.log "Server started..."
                        else
                            console.log 'Reloading...'
                            tinylr.changed
                                body:
                                  files: ["#{name}.js"]

module.exports = {
    readJsmClientConfig
    writeJsmClientConfig
    makeWebpackConfig
    parseEntry
    publish
    deprecate
    install
    update
    server
}

