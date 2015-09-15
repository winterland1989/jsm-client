webpack = require 'webpack'
express = require 'express'
path = require 'path'
MemoryFS = require "memory-fs"
tinylr = (require 'tiny-lr')()

module.exports = (entryPath, port) ->
    {name} = path.parse entryPath
    c = webpack(
        entry: entryPath
        output:
            path: '/'
            filename: "temp.js"

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
                        console.log jsonStats.errors
                    else
                        if started == false
                            if(jsonStats.warnings.length > 0)
                                console.log "Warning during packing: "
                                console.log jsonStats.warnings

                            app = express()

                            app.get '/', (req, res) ->
                                res.send(
                                    """
                                    <!DOCTYPE html>
                                        <html><head>
                                            <script src='/#{name}.js'></script></head>
                                            <script>
                                                document.write('<script src="http://' + (location.host || 'localhost').split(':')[0] + ':35729/livereload.js?snipver=1"></' + 'script>')
                                            </script>
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
