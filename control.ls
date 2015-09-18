{find, filter, map, minimum, any, concat-map, unique, id} = require \prelude-ls
{bindP, from-error-value-callback, new-promise, returnP, rejectP, to-callback, with-cancel-and-dispose} = require \./async-ls
Docker = require \dockerode
read = (file) -> (require \fs).readFileSync "/Users/homam/.docker/machine/certs/#{file}"
docker = new Docker({host: "192.168.99.100", protocol: \https, port: 2376, ca: (read "ca.pem"), cert: (read "cert.pem"), key: (read "key.pem") })

# ContainerInfo -> Boolean
is-container-up = (container) ->
    (container.Status.index-of "Up") == 0

# ContainerInfo -> Int16
get-public-port = (.Ports.0.PublicPort)

# [ContainerInfo] -> Int16
find-a-free-port = (containers) ->
    taken-ports = containers 
        #|> filter (-> (it.Status.index-of "Up") != 0)
        |> concat-map (.Ports)
        |> map (.PublicPort)

    taken-ports := unique (taken-ports ++ (containers |> map (.Names.0.split "_p_" .1) |> filter (-> !!it) |> map (-> parse-int it)))

    f = (p) ->
        if taken-ports |> any (== p) then f (p + 1) else p

    f 10000


# docker run -d -p $(docker-machine ip default):4082:4081 --name homam -i -t homam/pipe /bin/sh ./start.sh

resume-container = (container) ->
    resolve, reject <- new-promise
    err, data <- container.start
    return reject err if !!err
    resolve container

get-containers = (options = {all: true}) ->
    (from-error-value-callback docker.listContainers, docker) options

get-container-info = (username, options = {all: true}) ->
    containers <- bindP (get-containers options)
    returnP <| find-container-info containers, username

find-container-info = (containers, username) ->
    containers |> find (-> "/#{username}" in (it.Names |> map (.split "_p_" .0)))

wait-for-stream = (container) ->

    stream <- bindP (from-error-value-callback container.attach, container) {stream: true, stdout: true, stderr: true}
        
    res, rej <- new-promise
    cleanup = do ->
        resolved = false
        ->
            return if resolved
            resolved := true
            stream.removeListener \data, shandler
    output = ""
    shandler = (d) ->
        s = d.to-string!
        output += s
        if (s.index-of 'listening for connections on port: 4081') > -1
            cleanup!
            res null
    
    stream.on \data, shandler

    <- set-timeout _, 20000 # 20 seconds
    cleanup!
    rej Error "Running a container timedout\nOutput:\n#{output}"

# String -> Promise {container :: Container, port: Int16}
start-container = (username) ->

    containers <- bindP (get-containers {all: true})

    container-info = find-container-info containers, username

    if !!container-info
        container = docker.getContainer container-info.Id
        if is-container-up container-info
            # existing running container
            console.log "> existing #{username}"
            return returnP {state: "running", container, container-info, port: get-public-port container-info}
        else
            # resume a container
            console.log "> resuming #{username}"
            container.PortBindings = "4081/tcp": [{HostPort: "#{free-port}"}]
            container <- bindP (resume-container container)
            container-info <- bindP (get-container-info username)
            _ <- bindP (wait-for-stream container)
            return returnP {state: "started", container, container-info, port: get-public-port container-info}

    else
        # run a new container from an image
        console.log "> creating #{username}"
        free-port = find-a-free-port containers

        container <- bindP (from-error-value-callback docker.createContainer, docker) {
            Image: 'homam/pipe'
            Cmd: ['/bin/sh', './start.sh']
            name: "#{username}_p_#{free-port}" 
            PortBindings: "4081/tcp": [{HostPort: "#{free-port}"}]
            Tty: true
        }

        container <- bindP resume-container container
        container-info <- bindP (get-container-info username)
        _ <- bindP (wait-for-stream container)

        returnP {state: "created", container, container-info, port: free-port}


controller = do ->

    promises = {}
    retries = {}

    restart: (username) ->
        delete promises[username]
        retries[username] = (retries[username] ? 0) + 1
        console.log "> retry #{retries[username]} #{username}"
        if retries[username] > 2
            rejectP Error "Maximum number of retries exhausted."
        else 
            @start username

    start: (username) ->

        if !!promises[username]
            return promises[username]
        else
            p = start-container username
            p
                .then (result) ->
                    promises[username] = returnP result
                    delete retries[username]
                .catch ->
                    delete promises[username]
            p



module.exports = controller
return
err, container <- to-callback (start-container-single "wow4")
if err 
    console.log err
else
    console.log "STARTED", container
