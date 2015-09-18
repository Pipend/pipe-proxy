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
{http-port, sleep-container-after} = require \./config
{exec} = require \shelljs

err, machine-ip <- exec 'docker-machine ip default'
return console.error err if !!err
machine-ip := machine-ip.trim!


do ->
    # handling proxy errors
    retries = {}

    proxy.on \error, (e, req, res) ->
        console.error e

        username = req.cookies["username"]

        if !retries[username]
            retries[username] = 1
            set-timeout do 
                ->
                    delete retries[username]
                20000 # 20 seconds
        else
            retries[username] += 1

        if retries[username] > 2
            res.status 500 .end "Maximum number of retries exhausted in proxying to #{username} (#{retries[username]})"
        else
            if 'ECONNREFUSED' == e.code
                <- set-timeout _, 500
                do-proxy username, (controller.restart username), req, res
            else
                res.status 500 .end e.to-string!


proxy.on \proxyReq (proxyReq, req, res, options) ->
    proxyReq.set-header 'host', "#{machine-ip}"

accessed = do ->
    containers = {}

    cleanup = ->
        old = new Date!.value-of! - sleep-container-after
        [stopper! for username, {last-access, stopper} of containers when last-access < old]
        |> map (p) ->
            p.then ->
                console.log it
            p.catch ->
                console.error it
        set-timeout cleanup, 5000

    cleanup!

    (username, stopper) ->
        containers[username] = {
            last-access: new Date!.value-of!
            stopper: ->
                delete containers[username]
                console.log "stopping #{username}"
                stopper!
        }


# do-proxy :: Promise ContainerData -> Request -> Response -> ()
do-proxy = (username, promise, req, res) ->
    err, {state, container, container-info, port, stopper}? <- to-callback promise
    if err 
        console.error err
        res.end err.to-string!
    else
        accessed username, stopper
        proxy.web do 
            req
            res
            {target: "http://#{machine-ip}:#{port}/"}

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
            do-proxy username, (controller.start username), req, res

app.listen http-port

console.log "listening for connections on port: #{http-port}"