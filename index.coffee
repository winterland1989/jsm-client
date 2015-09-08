path = require 'path'
http = require 'http'
querystring = require 'querystring'
url = require 'url'
fs = require 'fs-extra'
Promise = require 'bluebird'

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

parseRequires = (content, language) ->
    requires = []
    switch language
        when 'javascript'
            content.replace /\brequire\s*\(\s*(["'])([^"'\s\)]+)\1\s*\)/g, (match, quote, path) ->
                requires.push path
                match
        when 'coffeescript'
            content.replace /\brequire\s*(["'])([^"'\s\)]+)\1\s*/g, (match, quote, path) ->
                requires.push path
                match
        when 'livescript'
            content.replace /\brequire[!?]\s*(["'])([^"'\s\)]+)\1\s*/g, (match, quote, path) ->
                requires.push path
                match
    requires

module.exports =

readJsmClientConfig: ->
    if (fs.existsSync configFile)
        f = fs.readFileSync configFile, encoding: 'utf8'
        conf = JSON.parse f
        if conf.repository then conf
        else throw new Error "Parse config failed..."
    else
        repository: DEFAULT_REPOSITORY


writeJsmClientConfig: (conf) ->
    f = fs.writeFileSync configFile, (JSON.stringify conf) , encoding: 'utf8'


parseEntry: parseEntry = (filePath) ->
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


publish: (conf, entry) ->
    {hostname, port} = url.parse conf.repository
    entry.keywords = JSON.stringify (parseKeywords entry.content, entry.language)
    console.log "Entry keywords: #{entry.keywords}"

    checkRequires = Promise.all do ->
        ps = []
        for req in (parseRequires entry.content, entry.language)
            if (index = req.indexOf 'jsm') != -1
                reqObj  = parseEntry (req.substr(index + 3))
                console.log "Checking #{reqObj.author}/#{reqObj.title}..."

                getData = querystring.stringify(
                    title: reqObj.title
                    author: reqObj.author
                    version: reqObj.version
                )
                ps.push new Promise (resolve, reject) ->
                    chunks = []
                    req = http.request(
                            hostname: hostname
                            port: port
                            path: '/snippet?' + getData
                            method: 'GET'
                        ,   (res) ->
                                res.on 'data', (data) -> chunks.push data
                                res.on 'end', ->
                                    snippet = JSON.parse Buffer.concat(chunks).toString('utf8')
                                    resolve snippet.id
                        )
                    req.on 'error', (error) ->
                        reject error
                        console.log 'Check failed with status: ' + res.statusCode
                    req.end()
        ps

    checkRequires
    .catch (e) ->
        console.log 'Check requires failed...'
    .then (ids) ->
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
        req.on 'error', (error) -> console.log ('Publish failed with status: ' + res.statusCode)
        req.write postData
        req.end()


install: install = (conf, target) ->
    entryDir = path.dirname target

    entryContent = fs.readFileSync target, 'utf8'
    requires = []

    for language of commentStartMap
        requires = parseRequires entryContent, language
        if requires.length >0 then break

    for filePath in requires then do (filePath = filePath) ->
        if (index = filePath.indexOf 'jsm') != -1
            entryObj  = parseEntry (path.resolve entryDir, filePath.substr 3)
            filePath = (path.resolve entryDir, filePath)
            chunks = []
            if entryObj.author? and entryObj.title? and entryObj.version?
                delete entryObj.language
                {hostname, port} = url.parse conf.repository
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
                                    mtime = new Date(snippet.mtime)
                                    fs.utimesSync filePath, mtime, mtime
                                    install conf, filePath
                                    console.log "Installing snippet: #{filePath} succeessfully"
                                catch e
                                    console.log "Write snippet failed(#{e.message}): #{filePath}"
                            else
                                console.log "Download snippet failed(status#{res.statusCode}): #{filePath}"
                )
                req.on 'error', (e) ->
                    console.log "Get snippet failed(#{e.message}): #{filePath}"
                    console.log error
                req.end()

            else console.log "Parse entry failed: " + filePath

        else
            filePath = (path.resolve entryDir, filePath)
            if (path.extname filePath) == ''
                succ = 0
                for ext, lan of extMap when lan?
                    try
                        if fs.existsSync filePath + ext
                            install conf, filePath + ext
                    catch e
                        console.log e
            else
                install conf, filePath
