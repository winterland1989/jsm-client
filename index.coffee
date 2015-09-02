path = require 'path'
fs = require 'fs'
http = require 'http'
querystring = require 'querystring'
url = require 'url'

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

    authorMatch = (path.dirname base).match /\w*/g
    author = if authorMatch then authorMatch[0] else undefined

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
    console.log 'Installing snippet: ' + entry
    entryContent = ''
    requires = []

    try
        entryContent = fs.readFileSync entry, 'utf8'
    catch
        console.log 'File doesn\'t exist: ' + entry

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

    for filePath in requires
        if (filePath.indexOf 'jsm') != -1
            entry  = parseEntry filePath
            chunks = []
            if entry.author? and entry.title? and entry.version?
                delete entry.language
                {hostname, port} = url.parse conf.repository
                req = http.request(
                    hostname: hostname
                    port: port
                    path: '/snippet?' + querystring.stringify entry
                    method: 'GET'
                ,   (res) ->
                        res.on 'data', (data) -> chunks.push data
                        res.on 'end', ->
                            try
                                snippet = JSON.parse Buffer.concat(chunks).toString('utf8')
                                fs.writeFileSync(
                                        filePath +
                                            if (path.extname filePath) == ''
                                                getExt snippet.language
                                            else ''
                                    ,   snippet.content
                                    )
                                install conf, filePath
                                console.log 'Installing snippet: ' + entry + ' succeessfully'
                            catch e
                                console.log "Write snippet failed: " + filePath
                )
                req.on 'error', (error) ->
                    console.log 'Get snippet failed:' + filePath
                    console.log error

            else
                console.log entry
                console.log "Parse entry name failed: " + filePath


        else
            if (path.extname filePath) == ''
                succ = 0
                for ext, lan of extMap when lan?
                    try
                        install conf, filePath + ext
                        succ++
                if succ == 0 then console.log 'Can\'t resolve ' + filePath
            else install conf, filePath




