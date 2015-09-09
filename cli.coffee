commander = require 'commander'
jsm = require './index.coffee'
readline = require 'readline'
fs = require 'fs'
crypto = require 'crypto'
path = require 'path'

conf = jsm.readJsmClientConfig()

commander
    .command 'install [entries...]'
    .alias 'i'
    .description 'Install snippets for given entry files, omit entries default to search jsm.json.'
    .action (entries) ->
        for entry in entries
            jsm.install conf, path.resolve(process.cwd(), entry)

commander
    .command 'publish [entry]'
    .alias 'p'
    .description 'Publish snippet, version default to 0 if entry doesn\'t end with version numbers.'
    .action (entryPath) ->
        if fs.existsSync entryPath

            entry = jsm.parseEntry entryPath

            rl = readline.createInterface
                input: process.stdin
                output: process.stdout

            rl.question "Username#{if entry.author? then "(default: #{entry.author}):" else ':'}", (author) ->
                entry.author = author if author

                rl.question "Password:", (password) ->
                    rl.close()
                    if password != ""
                        entry.password = password
                        console.log "Pulish #{entry.title + entry.version}
                            to #{entry.author}/#{entry.title + entry.version}..."

                        entry.content = fs.readFileSync entryPath, encoding: 'utf8'
                        jsm.publish conf, entry

                    else
                        console.log "Empty password..."
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
        rl.question "Repository Address(default: #{conf.repository}):", (repository) ->
            conf.repository = repository if repository
            jsm.writeJsmClientConfig conf
            console.log "Configure succeessful!"
            rl.close()

commander.version '0.0.4'

if process.argv.slice(2).length
    commander.parse process.argv
else
    commander.outputHelp()
