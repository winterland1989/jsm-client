commander = require 'commander'
jsm = require './index.js'
readline = require 'readline'
fs = require 'fs'
crypto = require 'crypto'
path = require 'path'

try conf = jsm.readJsmClientConfig()
catch e
    console.log e.message
    return

commander
    .command 'install [entries...]'
    .alias 'i'
    .description 'Install snippets for given entry files, omit entries default to search jsm.json.'
    .action (entries) ->
        for entry in entries
            jsm.install conf, entry

commander
    .command 'update [entries...]'
    .alias 'u'
    .description 'Update snippets for given entry files, omit entries default to search jsm.json.'
    .action (entry) ->

commander
    .command 'publish [entry]'
    .alias 'p'
    .description 'Publish snippet, version default to 0 if entry doesn\'t end with version numbers.'
    .action (entryPath) ->
        if fs.existsSync entryPath
            entry = jsm.parseEntry entryPath
            if conf.username and conf.pwdHash
                console.log "Pulish #{entry.title + entry.version}
                    to #{conf.username}/#{entry.title + entry.version}..."
                entry.author = conf.username
                entry.content = fs.readFileSync entryPath, encoding: 'utf8'
                jsm.publish conf, entry
            else
                console.log "run 'jsm config' to config user info before publish..."
        else
            console.log "Entry doesn't exist..."

commander
    .command 'config'
    .alias 'c'
    .description 'Config jsm repository and user info.'
    .action ->
        rl = readline.createInterface
            input: process.stdin
            output: process.stdout
        rl.question "Repository Address? (default: #{conf.repository})", (repository) ->
            conf.repository = repository if repository

            rl.question "Username? (default: #{conf.username})", (username) ->
                conf.username = username if username

                rl.question "Password? ", (password) ->
                    if password != ""
                        shasum = crypto.createHash 'md5'
                        shasum.update password
                        pwdHash = shasum.digest('hex')
                        pwdHash = pwdHash.toString('ascii')
                        conf.pwdHash = pwdHash if password
                        jsm.writeJsmClientConfig conf
                        console.log "Configure succeessful!"
                        rl.close()
                    else console.log 'Configure failed, please run jsm config again...'

commander.version '0.0.1'
commander.parse process.argv
