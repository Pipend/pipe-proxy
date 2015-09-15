{find, filter, map, minimum, any, concat-map, unique, id} = require \prelude-ls
{bindP, from-error-value-callback, new-promise, returnP, rejectP, to-callback, with-cancel-and-dispose} = require \./async-ls
{http-port} = require \./config

http = require \http
proxy = require \http-proxy .createProxyServer!

proxy.on \error, (e) ->
    console.log \error, e

proxy.on \proxyReq (proxyReq, req, res, options) ->
    proxyReq.set-header 'host', '192.168.99.100'

{
    promises: {
        parallel-map, parallel-limited-filter, from-error-value-callback, bindP, returnP
        to-callback
    },
    monads: {
        filterM, liftM
    }
} = require \async-ls




{start-container-single} = require \./control.ls

express = require \express
app = express!
    ..use (require \cookie-parser)!
    ..use (req, res, next) ->
        if "/login" == req.path
            username = req.query["username"]
            if !username
                res.end "Enter a username"
            else
                res.cookie "username", username
                res.redirect "/"
        else
            next!
    ..use (req, res, next) ->
        username = req.cookies["username"]
        if !username
            res.redirect "/login"
        else

            err, {state, container, container-info, port}? <- to-callback (start-container-single username)
            if err 
                console.log err
                res.end err.to-string!
            else
                console.log "STARTED", container-info, port

                timeout = match state
                    | "running" => 0
                    | "created" => 18000
                    | "started" => 12000

                <- set-timeout _, timeout

                console.log "prxying..."

                proxy.web do 
                    req
                    res
                    {target: "http://192.168.99.100:#{port}/"}
            # next!

app.listen http-port

console.log "listening for connections on port: #{http-port}"

return



http.createServer (req, res) ->

    console.log req.headers
    #req.headers.host = 'pages.mli.me'

    proxy.web do 
        req
        res
        {target: "http://192.168.99.100:4082/"}


.listen 8000