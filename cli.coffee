commander = require 'commander'
jsm = require './index.coffee'
server = require './server'
readline = require 'readline'
fs = require 'fs-extra'
crypto = require 'crypto'
path = require 'path'
packageJson = require './package.json'

conf = jsm.readJsmClientConfig()

commander
    .command 'install [entries...]'
    .alias 'i'
    .description 'Install snippets for given entry files.'
    .action (entries) ->
        entryPaths = for entryPath in entries
            path.resolve(process.cwd(), entryPath)
        jsm.install conf, entryPaths

commander
    .command 'update [entries...]'
    .alias 'u'
    .description 'Update snippets for given entry files.'
    .action (entries) ->
        entryPaths = for entryPath in entries
            path.resolve(process.cwd(), entryPath)
        jsm.update conf, entryPaths

commander
    .command 'webpack [entries...]'
    .alias 'w'
    .description 'Write sample jsm webpack config file for given entry files.'
    .action (entries) ->
        newConfig = jsm.makeWebpackConfig entries
        fs.writeFileSync './webpack.config.js', newConfig, encoding: 'utf8'

commander
    .command 'server [entry] [port]'
    .alias 's'
    .description 'Bundle and server entry file with a empty html page.'
    .action (entryPath, port = 8080) ->
        if fs.existsSync entryPath
            console.log "Starting server with #{entryPath} @#{port}..."
            server(path.resolve(process.cwd(),entryPath), port)
        else
            console.log "#{entryPath} doesn't exist..."

commander
    .command 'publish [entry]'
    .alias 'p'
    .description 'Publish given snippet.'
    .action (entryPath) ->
        if (fs.existsSync entryPath) and (fs.statSync entryPath).isFile()
            entry = jsm.parseEntry entryPath

            rl = readline.createInterface
                input: process.stdin
                output: process.stdout

            rl.question "Version(default:#{entry.version})", (version) ->
                v = parseInt version
                entry.version = version if v >= 0 and typeof v == 'number'
                rl.question "Username#{if entry.author? then "(default: #{entry.author}):" else ':'}", (author) ->
                    entry.author = author if author

                    rl.question "Password:", (password) ->
                        rl.close()
                        if password != ""
                            entry.password = password
                            console.log "Pulish #{entry.title + entry.version}
                                to #{entry.author}/#{entry.title + entry.version}..."

                            jsm.publish conf, entry, path.resolve(process.cwd(), entryPath)

                        else
                            console.log "Empty password..."
        else
            console.log "Entry doesn't exist, is it a directory?..."


commander
    .command 'deprecate [entry]'
    .alias 'd'
    .description 'Mark given snippet deprecated.'
    .action (entryPath) ->
        if (fs.existsSync entryPath) and (fs.statSync entryPath).isFile()
            entry = jsm.parseEntry entryPath
            rl = readline.createInterface
                input: process.stdin
                output: process.stdout

            rl.question "Version(default:#{entry.version})", (version) ->
                v = parseInt version
                entry.version = version if v >= 0 and typeof v == 'number'
                rl.question "Username#{if entry.author? then "(default: #{entry.author}):" else ':'}", (author) ->
                    entry.author = author if author

                    rl.question "Password:", (password) ->
                        rl.close()
                        if password != ""
                            entry.password = password
                            console.log "Mark #{entry.author}/#{entry.title + entry.version} deprecated..."

                            jsm.deprecate conf, entry
                        else
                            console.log "Empty password..."
        else
            console.log "Entry doesn't exist, is it a directory?..."

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

commander.version packageJson.version

args = process.argv.slice(2)

if args.length > 1 or args[0] == 'config' or args[0] == 'c'
    commander.parse process.argv
else
    commander.outputHelp()
