#!/bin/sh

pwd

TEST_DIR="./console-consumer-read-specific-offsets-partitions"

# 1 Initialize the project
mkdir $TEST_DIR && cd $TEST_DIR || exit
mkdir assets

# 2 Get Confluent Platform
/bin/cat <<EOF >docker-compose.yml

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
    volumes:
      - ./assets:/assets
EOF

docker-compose up -d

sleep 10

# 3 Create a topic with multiple partitions

docker-compose exec broker kafka-topics --create --topic example-topic \
  --bootstrap-server broker:9092 \
  --replication-factor 1 --partitions 2

# 4 Produce records with keys and values

cat <<EOF >>assets/messages.4
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
EOF

docker-compose exec broker sh -c \
  'cat /assets/messages.4 | kafka-console-producer --topic example-topic --broker-list broker:9092 --property parse.key=true --property key.separator=":"'

# 5 Start a console consumer to read from the first partition

docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
 --from-beginning \
 --property print.key=true \
 --property key.separator="-" \
 --partition 0 \
 --timeout-ms 2000

# 6 Start a console consumer to read from the second partition

docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
 --from-beginning \
 --property print.key=true \
 --property key.separator="-" \
 --partition 1 \
 --timeout-ms 2000

# 7 Read records starting from a specific offset

docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
 --property print.key=true \
 --property key.separator="-" \
 --partition 1 \
 --offset 6 \
 --timeout-ms 2000

# 8 Clean Up

docker-compose down

cd - && rm -rf $TEST_DIR
