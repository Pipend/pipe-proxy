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

# String -> Promise {container :: Container, port: Int16}
start-container = (username) ->

    containers <- bindP (get-containers {all: true})

    container-info = find-container-info containers, username

    if !!container-info
        container = docker.getContainer container-info.Id
        if is-container-up container-info
            # existing running container
            return returnP {state: "running", container, container-info, port: get-public-port container-info}
        else
            container.PortBindings = "4081/tcp": [{HostPort: "#{free-port}"}]
            container <- bindP (resume-container container)
            container-info <- bindP (get-container-info username)
            return returnP {state: "started", container, container-info, port: get-public-port container-info}

    else
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
        returnP {state: "created", container, container-info, port: free-port}


    # err, stream <- container.attach {stream: true, stdout: true, stderr: true}

    # return reject err if !!err

    # stream.pipe process.stdout


    # <- set-timeout _, 6000
    # container.stop ->
    #     console.log ...

start-container-single = do ->

    locked = {}

    username <- id

    if !!locked[username]
        return locked[username]
    else
        p = start-container username
        p
            .then ->
                <- set-timeout _, 500
                delete locked[username]
            .catch ->
                <- set-timeout _, 500
                delete locked[username]
        p



module.exports = {
    start-container-single
}
return
err, container <- to-callback (start-container-single "wow4")
if err 
    console.log err
else
    console.log "STARTED", container
