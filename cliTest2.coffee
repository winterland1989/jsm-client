commander = require 'commander'
jsm = require './index.js'
readline = require 'readline'
fs = require 'fs'
crypto = require 'crypto'

try conf = jsm.readJsmClientConfig()
catch e
    console.log e.message
    return

commander
    .version '0.0.1'
    .command 'install [entry...]'
    .alias 'i'
    .description 'install snippets for given entry files, if omit entry, look for entries from jsm.json.'
    .action (entry) ->

commander
    .command 'update [entry...]'
    .alias 'u'
    .action (entry) ->

commander
    .command 'publish [entry]'
    .alias 'p'
    .action (entryPath) ->
        if fs.existsSync entryPath
            entry = jsm.parseEntry entryPath
            if conf.username and conf.pwdHash
                console.log "upload #{entry.title} to #{conf.username}/#{entry.title}..."
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
                        console.log pwdHash
                        conf.pwdHash = pwdHash if password
                        jsm.writeJsmClientConfig conf
                        rl.close()
                    else console.log 'Configure failed, please run jsm config again...'


commander.parse process.argv
