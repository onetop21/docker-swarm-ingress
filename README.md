# Ingress Service for Docker Swarm

[![docker swarm ingress CI](https://github.com/garutilorenzo/docker-swarm-ingress/actions/workflows/ci.yml/badge.svg)](https://github.com/garutilorenzo/docker-swarm-ingress/actions/workflows/ci.yml)
[![GitHub issues](https://img.shields.io/github/issues/garutilorenzo/docker-swarm-ingress)](https://github.com/garutilorenzo/docker-swarm-ingress/issues)
![GitHub](https://img.shields.io/github/license/garutilorenzo/docker-swarm-ingress)
[![GitHub forks](https://img.shields.io/github/forks/garutilorenzo/docker-swarm-ingress)](https://github.com/garutilorenzo/docker-swarm-ingress/network)
[![GitHub stars](https://img.shields.io/github/stars/garutilorenzo/docker-swarm-ingress)](https://github.com/garutilorenzo/docker-swarm-ingress/stargazers)
[![Docker Stars](https://img.shields.io/docker/stars/garutilorenzo/docker-swarm-ingress?style=flat-square)](https://hub.docker.com/r/garutilorenzo/docker-swarm-ingress) [![Docker Pulls](https://img.shields.io/docker/pulls/garutilorenzo/docker-swarm-ingress?style=flat-square)](https://hub.docker.com/r/garutilorenzo/docker-swarm-ingress)

![nginx-ingress-controller-small](https://garutilorenzo.github.io/images/nginx-ingress-controller-small.png)

This is a minimalistic approach to allow a routing of external requests into a
Docker Swarm while routing based on the public hostname.

Each service which should be routed has so enable the routing using labels.


## The Ingress Service

The ingress service consists of a nginx server and a python script which periodically
updates the nginx configuration. The service communicates with the docker daemon
to retrieve the latest service configuration.

A detailed guide with some examples is available [here](https://garutilorenzo.github.io/nginx-ingress-controller/)

### Run the Service

The Ingress service acts as a reverse proxy in your cluster. It exposes port 80
to the public an redirects all requests to the correct service in background.
It is important that the ingress service can reach other services via the Swarm
network (that means they must share a network).

```
docker service create --name ingress \
  --network ingress-routing \
  -p 80:80 \
  -p 443:443 \
  --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock \
  --constraint node.role==manager \
  garutilorenzo/docker-swarm-ingress
```

It is important to mount the docker socket, otherwise the service can't update
the configuration of nginx.

The ingress service should be scaled to multiple nodes to prevent short outages
when the node with the ingress servic becomes unresponsive (use `--replicas X` when starting the service).

To deploy the service you can use the .yml file in the example directory:

```
docker stack deploy -c exaples/docker-ingress-stack.yml ingress
```

check the stack status:

```
docker stack ps ingress


ID             NAME                    IMAGE                                    NODE      DESIRED STATE   CURRENT STATE              ERROR     PORTS
i28vwvmua0b3   ingress_nginx.1   garutilorenzo/docker-swarm-ingress:dev   node-2    Running         Preparing 11 seconds ago
```

check the service logs:

```
docker service  logs -f ingress_nginx


ingress_nginx.1.i28vwvmua0b3@node-2    | Generating a RSA private key
ingress_nginx.1.i28vwvmua0b3@node-2    | ........................................................++++
ingress_nginx.1.i28vwvmua0b3@node-2    | ................................................++++
ingress_nginx.1.i28vwvmua0b3@node-2    | writing new private key to '/etc/nginx/default.key'
ingress_nginx.1.i28vwvmua0b3@node-2    | -----
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: using the "epoll" event method
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: nginx/1.21.3
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: built by gcc 10.3.1 20210424 (Alpine 10.3.1_git20210424) 
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: OS: Linux 5.4.0-88-generic
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 1048576:1048576
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: start worker processes
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: start worker process 8
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:51:59 [notice] 1#1: start worker process 9
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 10#10: signal process started
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 1#1: signal 1 (SIGHUP) received from 10, reconfiguring
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 1#1: reconfiguring
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 9#9: gracefully shutting down
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 9#9: exiting
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 9#9: exit
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 8#8: gracefully shutting down
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 8#8: exiting
ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:52:01 [notice] 8#8: exit

```

### Register a Service for Ingress

A service can easily be configured using ingress. You must simply provide a label
`ingress.host` which determines the hostname under wich the service should be
publicly available.

## Configuration Labels

Additionally to the hostname you can also map another port and path of your service.
By default a request would be redirected to `http://service-name:80/`.

| Label   | Required | Default | Description |
| ------- | -------- | ------- | ----------- |
| `ingress.host` | `yes` | `-`      | When configured ingress is enabled. The hostname which should be mapped to the service. Wildcards `*` and regular expressions are allowed. |
| `ingress.port` | `no`  | `80`    | The port which serves the service in the cluster. |
| `ingress.virtual_proto` | `no`  | `http`     | The protocol used to connect to the backends |
| `ingress.certificate_name` | `no`  | ``     | Custom name of ssl certificate used instead of domain name |
| `ingress.path` | `no`  | `/`    | **New** The path which serves the service in the cluster. |


### Run a Service with Enabled Ingress

It is important to run the service which should be used for ingress that it
shares a network. A good way to do so is to create a common network `ingress-routing`
(`docker network create --driver overlay ingress-routing`).

To start a service with ingress simply pass the required labels on creation.

```
docker service create --name my-service \
  --network ingress-routing \
  --label ingress.host=my-service.company.tld \
  nginx
```

It is also possible to later add a service to ingress using `service update`.

```
docker service update \
  --label-add ingress.host=my-service.company.tld \
  --label-add ingress.port=8080 \
  my-service
```

You can also use the example provided in the examples dir for a test:

```
docker stack deploy -c examples/example-service.yml service-test
```

The service use the *my-service.company.tld* hostname.

Wait for nginx reload, check the logs of the nginx service:

```
docker service  logs -f ingress_nginx

...
...

nginx-ingress_nginx.1.i28vwvmua0b3@node-2    | 2021/10/18 13:53:31 [notice] 94#94: signal process started
```

### SSL

By default the container is configured in "SSL Passthrough" mode. It's also possible to use SSL Termination and SSL Bridging mode.
SSL Passthrough and SSL Termination/Bridging exclude each others so the nginx ingress controller can work in SSL termination mode **OR** in SSL Termination/Bridging mode.

To set the mode use the environment variable PROXY_MODE, default ssl-passthrough.

To set the container in Termination/Bridging set the variable PROXY_MODE to any value not equal to "ssl-passthrough" (Example. ssl-term-bridg)
A complete stack example is available here examples/docker-ingress-stack-ssl_term_bridg.yml

To use Termination/Bridging mode we need to create the certificates used to expose our site in https, to do this we need to create two secrets for each domain we need to expose.

The certificates name are very important, for example if our domain is my-service.company.tld the secrets must be named:

* my-service.company.tld.crt
* my-service.company.tld.key

To create the secrets you can use this command:

```
docker secret create my-service.company.tld.key my-service.key
docker secret create my-service.company.tld.crt my-service.crt
```

Where my-service.key and  my-service.crt are your ssl key and certificate (self-signed, letsencrypt, purchased and so on..)

This secrets then must be attached to our ingress container

```
docker service create --name ingress \
  --network ingress-routing \
  -p 80:80 \
  -p 443:443 \
  --secret my-service.company.tld.crt \
  --secret my-service.company.tld.key \
  --mount type=bind,source=/var/run/docker.sock,destination=/var/run/docker.sock \
  --constraint node.role==manager \
  garutilorenzo/docker-swarm-ingress
```

#### Use custom certificate name

Create the secrets with a custom name in this case is `wildcard-name.tld`:

```
docker secret create wildcard-name.tld.key my-service.key
docker secret create wildcard-name.tld.crt my-service.crt
```

then use the label `ingress.certificate_name` to specify the custom certificate name:

```
docker service create --name my-service \
  --network ingress-routing \
  --label ingress.host=my-service.company.tld \
  --label ingress.certificate_name=wildcard-name.tld \
  nginx
```

#### SSL Passthrough

It's possible to enable SSL Passthrough using the following labels:

* --label-add ingress.ssl=enable
* --label-add ingress.ssl_redirect=enable

with the ingress.ssl=enable we enalble the SSL Passthrough to our backend:

Client --> Nginx-Ingress (No SSL) --> Backend (SSL)

with ingress.ssl_redirect=enable nignx redirect all http traffic to https.
For a detailed example see examples/example-ssl-service.yml

#### SSL Termination

To use SSL termination mode on our backend container we need to add the following labels:

* --label-add ingress.ssl=enable
* --label-add ingress.ssl_redirect=enable
* --label-add ingress.virtual_proto=http
* --label-add ingress.port=80

Client --> Nginx-Ingress (SSL) --> Backend (No SSL)
For a detailed example see examples/example-service-ssl-termination.yml

#### SSL Bridging

To use SSL bridging mode on our backend container we need to add the following labels:

* --label-add ingress.ssl=enable
* --label-add ingress.ssl_redirect=enable
* --label-add ingress.virtual_proto=https
* --label-add ingress.port=443

Client --> Nginx-Ingress (SSL) --> Backend (SSL)
For a detailed example see examples/example-service-ssl-bridging.yml
