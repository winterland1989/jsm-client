path = require 'path'
http = require 'http'
querystring = require 'querystring'
url = require 'url'
fs = require 'fs-extra'
Promise = require 'bluebird'
webpack = require 'webpack'
MemoryFS = require "memory-fs"

CONFIG_FILE_NAME = '.jsm.json'
DEFAULT_REPOSITORY = 'http://jsm.winterland.me'


home = process.env[ if process.platform == 'win32' then 'USERPROFILE' else 'HOME' ]
configFile = path.join home, CONFIG_FILE_NAME

extMap =
    '.ls': 'livescript'
    '.coffee': 'coffeescript'
    '.js': 'javascript'

commentStartMap =
    'livescript': '#'
    'coffeescript': '#'
    'javascript': '//'

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

parseRequires = (entryPaths) ->
    new Promise (resolve, reject) ->
        fsm = new MemoryFS()
        c = webpack(
            entry: entryPaths
            output:
                path: '/dev/null'
                filename: "null.js"

            module:
                loaders: [
                    { test: /\.coffee$/, loader: "coffee-loader" },
                    { test: /\.(coffee\.md|litcoffee)$/, loader: "coffee-loader?literate" }
                    { test: /\.ls/, loader: "livescript-loader" },
                ]
            resolve:
                extensions:
                    ["", ".json", ".js", ".coffee", ".ls"]

        )
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

                                                mtime = new Date(snippet.mtime)

                                                fs.writeFileSync filePath, snippet.content
                                                fs.utimesSync filePath, mtime, mtime

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

                                        oldMtime = (fs.statSync filePath).mtime

                                        {dir, name, ext: oldExtname} = path.parse filePath
                                        newExtname = (getExt snippet.language)

                                        if oldExtname != newExtname
                                            console.log 'Language change found:'
                                            console.log filePath
                                            fs.removeSync filePath
                                            console.log 'Remove old snippet done'
                                            filePath = path.join(dir, name) + (getExt snippet.language)

                                        newMtime = new Date(snippet.mtime)

                                        if Math.abs(Number(newMtime) - Number(oldMtime)) > 1000

                                            fs.writeFileSync filePath, snippet.content
                                            fs.utimesSync filePath, newMtime, newMtime

                                            console.log "Update snippet: #{filePath} succeessfully @ revision#{snippet.revision}"
                                        else
                                            console.log "No update found, skip snippet: #{filePath}"

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

module.exports = {
    readJsmClientConfig
    writeJsmClientConfig
    parseEntry
    publish
    deprecate
    install
    update
}

