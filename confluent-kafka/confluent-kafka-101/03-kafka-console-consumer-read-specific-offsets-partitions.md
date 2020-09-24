
## **Context**
- [1 Initialize the project](#1-initialize-the-project)
- [2 Get Confluent Platform](#2-get-confluent-platform)
- [3 Create a topic with multiple partitions](#3-create-a-topic-with-multiple-partitions)
- [4 Produce records with keys and values](#4-produce-records-with-keys-and-values)
- [5 Start a console consumer to read from the first partition](#5-start-a-console-consumer-to-read-from-the-first-partition)
- [6 Start a console consumer to read from the second partition](#6-іtart-a-console-consumer-to-read-from-the-second-partition)
- [7 Read records starting from a specific offset](#7-read-records-starting-from-a-specific-offset)
- [8 Clean Up](#8-clean-up)

## 1 Initialize the project

To get started, make a new directory anywhere you’d like for this project:

```
mkdir console-consumer-read-specific-offsets-partitions && cd console-consumer-read-specific-offsets-partitions
```

## 2 Get Confluent Platform

Next, create the following `docker-compose.yml` file to obtain Confluent Platform.

```
---
version: '2'

services:
  zookeeper:
    image: confluentinc/cp-zookeeper:5.5.0
    hostname: zookeeper
    container_name: zookeeper
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000

  broker:
    image: confluentinc/cp-kafka:5.5.0
    hostname: broker
    container_name: broker
    depends_on:
      - zookeeper
    ports:
      - "29092:29092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:9092,PLAINTEXT_HOST://localhost:29092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      
```

Currently, the console producer only writes strings into Kafka, but we want to work with non-string primitives and the 
console consumer. So in this tutorial, your `docker-compose.yml` file will also create a source connector embedded in 
`ksqldb-server` to populate a topic with keys of type `long` and values of type `double`.

And launch it by running:

```
docker-compose up -d
```

## 3 Create a topic with multiple partitions

Your first step is to create a topic to produce to and consume from. This time you’ll add more than one partition so 
you can see how the keys end up on different partitions.

Then use the following command to create the topic on the broker container:

```
docker-compose exec broker kafka-topics --create --topic example-topic \
  --bootstrap-server broker:9092 \
  --replication-factor 1 --partitions 2
```

Keep the container shell you just started open, as you’ll use it in the next step.


## 4 Produce records with keys and values

To get started, lets produce some records to your new topic.

Since you’ve created a topic with more than one partition, you’ll send full key-value pairs so you’ll be able to see 
how different keys end up on different partitions. To send full key-value pairs you’ll specify the `parse.keys` and 
`key.separtor` options to the console producer command.

Let’s run the following command in the broker container shell from the previous step to start a new console producer:

```
docker-compose exec broker kafka-console-producer --topic example-topic --broker-list broker:9092 \
  --property parse.key=true \
  --property key.separator=":"
```

Then enter these records either one at time or copy-paste all of them into the terminal and hit enter:

```
key1:the lazy
key2:fox jumped
key3:over the
key4:brown cow
key1:All
key2:streams
key3:lead
key4:to
key1:Kafka
key2:Go to
key3:Kafka
key4:summit
```

After you’ve sent the records, you can close the producer with a `CTRL+C` command, but keep the broker container shell 
open as you’ll still need it for the next few steps.

## 5 Start a console consumer to read from the first partition

Next let’s open up a console consumer to read records sent to the topic in the previous step, but you’ll only read from 
the first partition. Kafka partitions are zero based so your two partitions are numbered `0`, and `1` respectively.

Using the broker container shell, lets start a console consumer to read only records from the first partition, `0`

```
docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
 --from-beginning \
 --property print.key=true \
 --property key.separator="-" \
 --partition 0
```

After a few seconds you should see something like this

```
key1-the lazy
key1-All
key1-Kafka
```

You’ll notice you sent 12 records, but only 3 went to the first partition. The reason for this is the way Kafka 
calculates the partition assigment for a given record. Kafka calculates the partition by taking the hash of the key 
modulo the number of partitions. So, even though you have 2 partitions, depending on what the key hash value is, you 
aren’t guaranteed an even distribution of records across partitions.

Go ahead and shut down the current consumer with a `CTRL+C`

## 6 Start a console consumer to read from the second partition

In the previous step, you consumed records from the first partition of your topic. In this step you’ll consume the rest 
of your records from the second partition `1`.

If you haven’t done so already, close the previous console consumer with a `CTRL+C`.

Then start a new console consumer to read only records from the second partition:

```
docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
 --from-beginning \
 --property print.key=true \
 --property key.separator="-" \
 --partition 1
```

After a few seconds you should see something like this

```
key2-fox jumped
key3-over the
key4-brown cow
key2-streams
key3-lead
key4-to
key2-Go to
key3-Kafka
key4-summit
```

As you’d expect the remaining 9 records are on the second partition.

Go ahead and shut down the current consumer with a `CTRL+C`

## 7 Read records starting from a specific offset

So far you’ve learned how to consume records from a specific partition. When you specify the partition, you can 
optionally specify the offest to start conuming from. Specifying a specific offset can be helpful when debugging an 
issue, in that you can skip consuming records that you know aren’t a potential problem.

If you haven’t done so already, close the previous console consumer with a `CTRL+C`.

From the previous step you know there are 9 records in the second partition. In this step you’ll only consume records 
starting from offset 6, so you should only see the last 3 records on the screen. The changes in this command include 
removing the `--from-begining` propery and adding an `--offset` flag

Here’s the command to read records from the second partition starting at offset 6:

```
docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
 --property print.key=true \
 --property key.separator="-" \
 --partition 1 \
 --offset 6
```

After a few seconds you should see something like this

```
key2-Go to
key3-Kafka
key4-summit
```

So you can see here, you’ve consumed records starting from offset 6 to the end, which includes record with offsets of 
`6`, `7`, and `8` the last three records.

Go ahead and shut down the current consumer with a `CTRL+C`

## 8 Clean Up

You’re all down now!

Go back to your open windows and stop any console producers and consumers with a `CTRL+C` then close the containter 
shells with a `CTRL+D` command.

Then you can shut down the stack by running:

```
docker-compose down
```
