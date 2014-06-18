#!/bin/bash

if [ -z $1 ]; then
        echo "Usage: forrest launch <image name>:<version>"
        echo "       forrest stop <container name>"
        exit 1
fi

if [ -z $ETCD_HOST ]; then
  ETCD_HOST="127.0.0.1:4001"
fi

if [ -z $ETCD_PREFIX ]; then
  ETCD_PREFIX="forest/servers/"
fi

if [ -z $FORREST_IP ]; then
  FORREST_IP=`ifconfig | grep "inet addr" | head -1 | cut -d : -f2 | awk '{print $1}'`
fi

function launch_container {
        echo "Launching $1 on $FORREST_IP ..."

        CONTAINER_ID=`docker run -d -P $1`
        PORT=`docker inspect $CONTAINER_ID | grep HostPort | cut -d '"' -f4 | head -1`
        NAME=`docker inspect $CONTAINER_ID | grep Name | cut -d '"' -f4 | sed "s/\///g"`

        echo "Announcing to $ETCD_HOST..."
        curl -XPUT http://$ETCD_HOST/v2/keys/$ETCD_PREFIX/$NAME -d value="$FORREST_IP:$PORT" &> /dev/null

        echo "$1 running on Port $PORT with name $NAME"
}

function stop_container {
        echo "Stopping $1..."
        CONTAINER_ID=`docker ps | grep $1 | awk '{print $1}'`
        echo "Found container $CONTAINER_ID"
        docker stop $CONTAINER_ID
        curl -XDELETE http://$ETCD_HOST/v2/keys/$ETCD_PREFIX/$1 &> /dev/null
        echo "Stopped."
}


if [ $1 = "launch" ]; then
  launch_container $2
else
  stop_container $2
fi
