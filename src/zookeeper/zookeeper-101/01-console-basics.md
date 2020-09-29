https://zookeeper.apache.org/doc/r3.6.0/zookeeperCLI.html

## **Context**
- [1 Initialize the project](#1-initialize-the-project)
- [2 Get Zookeeper cluster](#2-get-zookeeper-cluster)

- [10 Clean Up](#10-clean-up)

## 1 Initialize the project

To get started, make a new directory anywhere you’d like for this project:

```
mkdir zookeeper-console-basic && cd zookeeper-console-basic
```

## 2 Get Zookeeper cluster

Next, create the following `docker-compose.yml` file to obtain Zookeeper cluster.

```
---

version: '3.1'

services:
  zoo1:
    image: zookeeper
    restart: always
    hostname: zoo1
    ports:
      - 2181:2181
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: server.1=0.0.0.0:2888:3888;2181 server.2=zoo2:2888:3888;2181 server.3=zoo3:2888:3888;2181
      ZOO_SYNC_LIMIT: 20

  zoo2:
    image: zookeeper
    restart: always
    hostname: zoo2
    ports:
      - 2182:2181
    environment:
      ZOO_MY_ID: 2
      ZOO_SERVERS: server.1=zoo1:2888:3888;2181 server.2=0.0.0.0:2888:3888;2181 server.3=zoo3:2888:3888;2181
      ZOO_SYNC_LIMIT: 20

  zoo3:
    image: zookeeper
    restart: always
    hostname: zoo3
    ports:
      - 2183:2181
    environment:
      ZOO_MY_ID: 3
      ZOO_SERVERS: server.1=zoo1:2888:3888;2181 server.2=zoo2:2888:3888;2181 server.3=0.0.0.0:2888:3888;2181
      ZOO_SYNC_LIMIT: 20
```   

Now launch Zookeeper cluster by running:

```
docker-compose up -d
```

## 3 Create a ZK node

First step is to create a Znodes the main entity that a programmer access. There are several types of Znodes: 
`persistent`, `ephemeral` and `sequential`.

> A persistent node is a node that attempts to stay present in ZooKeeper, even through connection and session
interruptions.

> echo srvr | nc localhost 2181


## 10 Clean Up

You’re all down now!

Go back to your open windows and stop any console producers and consumers with a `CTRL+C` then close the containter shells with a `CTRL+D` command.

Then you can shut down the stack by running:

```
docker-compose down
```
