#!/bin/sh

pwd

TEST_DIR="./console-consumer-produer-basic"

# 1 Initialize the project
mkdir $TEST_DIR && cd $TEST_DIR || exit
mkdir tmp

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
      - ./tmp:/opt/app/tmp
EOF

docker-compose up -d

sleep 10

# 3 Create a topic
docker-compose exec broker kafka-topics --create --topic example-topic --bootstrap-server broker:9092 \
  --replication-factor 1 \
  --partitions 1

docker-compose exec broker kafka-topics --describe --topic example-topic --bootstrap-server broker:9092

# TODO enable step
# 4 Start a console consumer (disabled)
#
# Step disabled because of: ERROR Error processing message, terminating consumer process:  (kafka.tools.ConsoleConsumer$)
#org.apache.kafka.common.errors.TimeoutException

#docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
#  --from-beginning \
#  --timeout-ms 1000

# 5 Produce your first records

cat <<EOF >>tmp/messages.5
the
lazy
fox
jumped over the brown cow
EOF

docker-compose exec broker sh -c \
  'cat /opt/app/tmp/messages.5 | kafka-console-producer --topic example-topic --broker-list broker:9092'

# 6 Read all records

docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
  --from-beginning \
  --timeout-ms 2000

cat <<EOF >>tmp/messages.6
how now
brown cow
all streams lead
to Kafka!
EOF

docker-compose exec broker sh -c \
  'cat /opt/app/tmp/messages.6 | kafka-console-producer --topic example-topic --broker-list broker:9092'

# 7 Start a new consumer to read all records

docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
  --from-beginning \
  --timeout-ms 2000

# 8 Produce records with full key-value pairs

cat <<EOF >>tmp/messages.8
key1:what a lovely
key1:bunch of coconuts
foo:bar
fun:not quarantine
EOF

docker-compose exec broker sh -c \
  'cat /opt/app/tmp/messages.8 | kafka-console-producer --topic example-topic --broker-list broker:9092 --property parse.key=true --property key.separator=":"'

# 9 Start a consumer to show full key-value pairs

docker-compose exec broker kafka-console-consumer --topic example-topic --bootstrap-server broker:9092 \
  --from-beginning \
  --property print.key=true \
  --property key.separator="-" \
  --timeout-ms 2000

# 10 Clean Up

docker-compose down

cd - && rm -rf $TEST_DIR
