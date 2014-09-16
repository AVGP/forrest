forrest
=======

Simple script to launch and stop docker containers and register them with etcd

# What can I do with forrest?
Deploy docker containers and have them automatically register themselves in etcd. 

Together with confd and a load balancer (e.g. HAProxy) this allows automated add/remove of containers to the load balancer.

If you're hunting for some keywords: elastic scaling, rolling updates, zero downtime deployments

# Requirements: The full ingredient list
1. An [etcd](https://github.com/coreos/etcd) instance somewhere on the network
2. A [confd](https://github.com/kelseyhightower/confd) template for your gateway. Confd is neReded to reload the gateway server with new configuration when instances join or leave
3. A docker host on the network that will run your application images

# Walkthrough

Say we have three servers:

name | private IP | packages
--- | --- | ---
gw1 | 10.10.10.1 | haproxy, confd
docker1 | 10.10.10.10 | docker, forrest
etcd1 | 10.10.10.20 | etcd

## etcd

[etcd](https://github.com/coreos/etcd) is a key/value store, basically.
It allows easy storage of configuration values in a central place, using a simple REST-API.

For example we could store our servers with a name and an IP like this:

    $ curl -XPUT http://10.10.10.20:4001/v2/keys/app/servers/web1 -d value="10.10.10.10:45679"

and then get the value with

    $ curl http://10.10.10.20:4001/v2/keys/app/servers/web1

We will use this to store exactly this: Our docker container IPs plus their name, so we can find them automatically as they become available to add them to our reverse proxy as well as remove them from there when they go down.

Let's start etcd:

    nohup etcd/bin/etcd -bind-addr=10.10.10.20 > /var/log/etcd.log &

## confd

confd is insanely useful, yet surprisingly simple to use.
Basically all it does is watch a config server ([etcd](https://github.com/coreos/etcd) or [Consul](https://consul.io)) for changes. 

If it detects a change, it uses a template to create a new version of a config file with these new values and run a command to reload the configuration (in our case, for instance, ``service haproxy reload``).

This way it allows "live" configuration changes.

For that to work we need two files: The template and the configuration.
Here is the configuration:

### /etc/confd/conf.d/helloworld.toml

    [template]
    src = "haproxy.cfg.tmpl"
    dest = "/etc/haproxy/haproxy.cfg"
    keys = [
      "/app/servers",
    ]
    reload_cmd = "/usr/sbin/service haproxy reload"

This defines where the file will be written to ("/etc/haproxy/haproxy.cfg"), what the template will be ("haproxy.cfg.tmpl"), what's the root key on where to find the configuration values and the command to run if the config has been rewritten.

A template for HAProxy could look like this:

### /etc/confd/templates/haproxy.cfg.tmpl

    defaults
      log     global
      mode    http
    
    listen frontend 0.0.0.0:8080
      mode http
      stats enable
      stats uri /haproxy?stats
      balance roundrobin
      option httpclose
      option forwardfor
      {{range $server := .app_servers}}
      server {{Base $server.Key}} {{$server.Value}} check
      {{end}}

That's a very simple HAProxy config that listens on port 8080, gathers and exposes some stats (nice for playing around with it), does a simple roundrobin load balancing.

The last three lines are interesting, as confd comes into play here...

The ``{{range $server := .app_servers}}`` iterates over each key within etcd at the ``/app/servers`` path and writes a config line containing ``server`` followed by the key name itself and its value.

So if etcd has the following values:

    /app/servers/web1      = "10.10.10.10:1234"
    /app/servers/web2      = "10.10.10.10:1337"
    /app/servers/test_web1 = "10.10.10.10:4242"

then we would get this config file lines:

    server web1 10.10.10.10:1234 check
    server web2 10.10.10.10:1337 check
    server test_web1 10.10.10.10:4242 check

which means that HAProxy will balance requests between these 3 servers and performs a health check on each of them.

This way we can now use etcd and confd to dynamically configure our HAProxy via changes in the values stored in the etcd. Neat!

Let's start confd then:

### Starting confd

    nohup confd -verbose -interval 10 -node '10.10.10.20:4001' -confdir /etc/confd > /var/log/confd.log &

## Docker

For an in-depth introduction to Docker, check out [the incredibly fantastic interactive tutorial on their site](http://www.docker.com/tryit/).

For this scenario, I will pretend you have a working Docker host and a docker image for your application. I will call that image 'demo/myapp' for now.

The image should only expose a single port.

## Start & Stop with Forrest

All forrest does is launch (or stop) a container from an image and announce the newly started container, including the Port it exposes, to the etcd.

Thus, it allows us to pick up the ``address:port`` combination from the etcd and put it into the configuration of our HAProxy... which effectively means we're able to automatically add or remove containers from the load balancing as they go up or down.

Now this is how this would look like:

    user@docker1: $ export ETCD_HOST="10.10.10.20:4001"
    user@docker1: $ export ETCD_PREFIX="app/servers"
    user@docker1: $ export FORREST_IP="10.10.10.10" # possibly optional
    user@docker1: $ forrest launch demo/myapp
      Launching demo/myapp on 10.10.10.10 ...
      Announcing to 10.10.10.20:4001 ...
      demo/myapp running on Port 49731 with name sharp_mccarthy
    user@docker1: $

And you should now be able to reach this application through the HAProxy on your public IP or domain name.

If you want to stop a running container and remove it from etcd (and thus from the HAProxy) you do

    user@docker1: $ forrest stop sharp_mccarthy
      Stopping sharp_mccarthy ...
      Found container 8d3299a3427b ...
      Stopped.
    user@docker1: $

Tada!
