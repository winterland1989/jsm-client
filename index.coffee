path = require 'path'
http = require 'http'
querystring = require 'querystring'
url = require 'url'
fs = require 'fs-extra'

CONFIG_FILE_NAME = '.jsm.json'
DEFAULT_REPOSITORY = 'http://jsm.winterland.me'


home = process.env[ if process.platform == 'win32' then 'USERPROFILE' else 'HOME' ]
configFile = path.join home, CONFIG_FILE_NAME

extMap =
    '.ls': 'livescript'
    '.coffee': 'coffeescript'
    '.js': 'javascript'
    '': undefined

getExt = (language) ->
    for ext, lan of extMap
        if lan == language then return ext

    return ''

module.exports =

readJsmClientConfig: ->
    if (fs.existsSync configFile)
        f = fs.readFileSync configFile, encoding: 'utf8'
        conf = JSON.parse f
        if conf.repository and conf.username and conf.password then conf
        else throw new Error "remove #{configFile} and restart..."

    else
        repository: DEFAULT_REPOSITORY
        username: ''
        pwdHash: ''


writeJsmClientConfig: (conf) ->
    f = fs.writeFileSync configFile, (JSON.stringify conf) , encoding: 'utf8'


parseEntry: parseEntry = (filePath) ->
    filePath = path.normalize filePath
    ext = path.extname filePath
    base = path.basename filePath, ext

    author = (path.basename(path.dirname filePath))

    titleMatch = base.match /^([a-zA-Z]+)/g
    title = if titleMatch? then titleMatch[0] else throw new Error "Parse entry name failed: " + filePath

    versionMatch = base.match /([0-9]+)$/g
    version = if versionMatch? then parseInt versionMatch[0] else 0
    title: title
    version: version
    author: author
    language: extMap[ext]


publish: (conf, entry) ->
    entry.pwdHash = conf.pwdHash
    postData = querystring.stringify entry
    {hostname, port} = url.parse conf.repository
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
            res.on 'end', ->
                try
                    snippet = JSON.parse Buffer.concat(chunks).toString('utf8')
                    console.log "#{snippet.author}/#{snippet.title + snippet.version}
                        (revision#{snippet.revision}) published succeessful!"
                catch e
                    console.log "publish failed!"
    )
    req.on 'error', (error) ->
        console.log 'Publish failed!:'
        console.log error
    req.write postData
    req.end()


install: install = (conf, entry) ->
    entryDir = path.dirname entry
    entryContent = ''
    requires = []

    try entryContent = fs.readFileSync entry, 'utf8'

    switch extMap[path.extname entry]
        when 'javascript'
            entryContent.replace /\brequire\s*\(\s*(["'])([^"'\s\)]+)\1\s*\)/g, (match, quote, path) ->
                requires.push path
                match
        when 'coffeescript'
            entryContent.replace /\brequire\s*(["'])([^"'\s\)]+)\1\s*/g, (match, quote, path) ->
                requires.push path
                match
        when 'livescript'
            entryContent.replace /\brequire[!?]\s*(["'])([^"'\s\)]+)\1\s*/g, (match, quote, path) ->
                requires.push path
                match

    for filePath in requires then do (filePath = filePath) ->
        if (index = filePath.indexOf 'jsm') != -1
            entryObj  = parseEntry (path.resolve entryDir, filePath[(index+4)..])
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
                                    console.log 'Installing snippet: ' + filePath + ' succeessfully'
                                catch e
                                    console.log "Write snippet failed: " + filePath
                            else
                                console.log res.statusCode
                                console.log "Download snippet failed: " + filePath

                )
                req.on 'error', (error) ->
                    console.log 'Get snippet failed:' + filePath
                    console.log error
                req.end()

            else
                console.log entry
                console.log "Parse entry name failed: " + filePath


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




