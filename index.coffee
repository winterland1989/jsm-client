path = require 'path'
fs = require 'fs'
http = require 'http'
querystring = require 'querystring'
url = require 'url'

CONFIG_FILE_NAME = '.jsm.json'
DEFAULT_REPOSITORY = 'http://jsm.winterland.me'

LANGUAGE_EXT =
    '.ls': 'livescript'
    '.coffee': 'coffeescript'
    '.js': 'javascript'


home = process.env[ if process.platform == 'win32' then 'USERPROFILE' else 'HOME' ]
configFile = path.join home, CONFIG_FILE_NAME

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


parseEntry: (filePath) ->
    filePath = path.normalize filePath
    ext = path.extname filePath
    base = path.basename filePath, ext
    author = path.dirname base
    if (author.match /\w*/)[0].length == 0
        author = undefined
    title = (base.match /^([a-zA-Z]*)/)[0]
    version = (base.match /([0-9]*)$/)[0]
    version = if version.length then parseInt version else 0
    title: title
    version: version
    author: author
    language: LANGUAGE_EXT[ext]


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
    ,   (res)->
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
