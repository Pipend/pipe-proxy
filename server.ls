{find, filter, map, minimum, any, concat-map, unique, id} = require \prelude-ls
{bindP, from-error-value-callback, new-promise, returnP, rejectP, to-callback, with-cancel-and-dispose} = require \./async-ls
{
    promises: {
        parallel-map, parallel-limited-filter, from-error-value-callback, bindP, returnP
        to-callback
    },
    monads: {
        filterM, liftM
    }
} = require \async-ls
http = require \http
proxy = require \http-proxy .createProxyServer!
controller = require \./control.ls
{http-port} = require \./config


proxy.on \error, (e, req, res) ->
    console.log \error, e, e.code
    username = req.cookies["username"]
    if 'ECONNREFUSED' == e.code
        do-proxy (controller.restart username), req, res
    else
        res.end e.to-string!

proxy.on \proxyReq (proxyReq, req, res, options) ->
    proxyReq.set-header 'host', '192.168.99.100'


# do-proxy :: Promise ContainerData -> Request -> Response -> ()
do-proxy = (promise, req, res) ->
    err, {state, container, container-info, port}? <- to-callback promise
    if err 
        console.log err
        res.end err.to-string!
    else
        proxy.web do 
            req
            res
            {target: "http://192.168.99.100:#{port}/"}

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
            do-proxy (controller.start username), req, res

app.listen http-port

console.log "listening for connections on port: #{http-port}"