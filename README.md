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
