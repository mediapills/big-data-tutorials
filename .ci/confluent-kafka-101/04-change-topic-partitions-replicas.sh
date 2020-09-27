#!/bin/sh

pwd

TEST_DIR="./change-topic-partitions-replicas"

# 1 Initialize the project
mkdir $TEST_DIR && cd $TEST_DIR || exit
mkdir tmp src test

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
      KAFKA_BROKER_ID: 101
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:9092,PLAINTEXT_HOST://localhost:29092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 2
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 2
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
    volumes:
      - ./tmp:/opt/app/tmp

  broker2:
    image: confluentinc/cp-kafka:5.5.0
    hostname: broker2
    container_name: broker2
    depends_on:
      - zookeeper
    ports:
      - "29093:29093"
    environment:
      KAFKA_BROKER_ID: 102
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker2:9093,PLAINTEXT_HOST://localhost:29093
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 2
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 2
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0

  schema-registry:
    image: confluentinc/cp-schema-registry:5.5.0
    hostname: schema-registry
    container_name: schema-registry
    depends_on:
      - zookeeper
      - broker
    ports:
      - "8081:8081"
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL: 'zookeeper:2181'

  ksqldb-server:
    image: confluentinc/ksqldb-server:0.11.0
    hostname: ksqldb-server
    container_name: ksqldb-server
    depends_on:
      - broker
      - schema-registry
    ports:
      - "8088:8088"
    environment:
      KSQL_CONFIG_DIR: "/etc/ksqldb"
      KSQL_LOG4J_OPTS: "-Dlog4j.configuration=file:/etc/ksqldb/log4j.properties"
      KSQL_BOOTSTRAP_SERVERS: "broker:9092"
      KSQL_HOST_NAME: ksqldb-server
      KSQL_LISTENERS: "http://0.0.0.0:8088"
      KSQL_CACHE_MAX_BYTES_BUFFERING: 0
      KSQL_KSQL_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"

  ksqldb-cli:
    image: confluentinc/ksqldb-cli:0.11.0
    container_name: ksqldb-cli
    depends_on:
      - broker
      - ksqldb-server
    entrypoint: /bin/sh
    environment:
      KSQL_CONFIG_DIR: "/etc/ksqldb"
    tty: true
    volumes:
      - ./src:/opt/app/src
      - ./test:/opt/app/test
EOF

docker-compose up -d

sleep 10

# 3 Create the original topic

docker-compose exec broker kafka-topics --bootstrap-server broker:9092 --topic topic1 --create \
  --replication-factor 1 \
  --partitions 1

# 4 Describe the original topic

docker-compose exec broker kafka-topics --bootstrap-server broker:9092 --topic topic1 --describe

# 5 Write the program interactively using the CLI

cat <<EOF >>src/queries.5.sql
CREATE STREAM S1 (COLUMN0 VARCHAR KEY, COLUMN1 VARCHAR) WITH (KAFKA_TOPIC = 'topic1', VALUE_FORMAT = 'JSON');
CREATE STREAM S2 WITH (KAFKA_TOPIC = 'topic2', VALUE_FORMAT = 'JSON', PARTITIONS = 2, REPLICAS = 2) AS SELECT * FROM S1;
EOF

docker exec -it ksqldb-cli ksql http://ksqldb-server:8088 --queries-file /opt/app/src/queries.5.sql

# 6 Describe the new topic

docker-compose exec broker kafka-topics --bootstrap-server broker:9092 --topic topic2 --describe

# 7 Write your statements to a file

cat <<EOF >>src/statements.sql
CREATE STREAM S1 (COLUMN0 VARCHAR KEY, COLUMN1 VARCHAR) WITH (KAFKA_TOPIC = 'topic1', VALUE_FORMAT = 'JSON');
CREATE STREAM S2 WITH (KAFKA_TOPIC = 'topic2', VALUE_FORMAT = 'JSON', PARTITIONS = 2, REPLICAS = 2) AS SELECT * FROM S1;
EOF

# 8 Run the console Kafka producer (skip)

# 9 Produce data to the original Kafka topic

cat <<EOF >>tmp/messages.8
a,{"column1": "1"}
b,{"column1": "1"}
c,{"column1": "1"}
d,{"column1": "1"}
a,{"column1": "2"}
b,{"column1": "2"}
c,{"column1": "2"}
d,{"column1": "2"}
a,{"column1": "3"}
b,{"column1": "3"}
c,{"column1": "3"}
d,{"column1": "3"}
EOF

docker-compose exec broker sh -c \
  'cat /opt/app/tmp/messages.8 | kafka-console-producer --bootstrap-server localhost:9092 --topic topic1 --property parse.key=true --property key.separator=,'

# 10 View the data in the original topic (partition 0)

docker-compose exec broker kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic topic1 \
  --property print.key=true \
  --property key.separator=, \
  --partition 0 \
  --from-beginning \
  --timeout-ms 1000

# TODO enable step
# 11 View the data in the new topic (partition 0)
#
# Step disabled because of: ERROR Error processing message, terminating consumer process:  (kafka.tools.ConsoleConsumer$)
#org.apache.kafka.common.errors.TimeoutException

#docker-compose exec broker kafka-console-consumer \
#  --bootstrap-server localhost:9092 \
#  --topic topic2 \
#  --property print.key=true \
#  --property key.separator=, \
#  --partition 0 \
#  --from-beginning \
#  --timeout-ms 1000

# TODO enable step
# 12 View the data in the new topic (partition 1)
#
# Step disabled because of: ERROR Error processing message, terminating consumer process:  (kafka.tools.ConsoleConsumer$)
#org.apache.kafka.common.errors.TimeoutException

#docker-compose exec broker kafka-console-consumer \
#  --bootstrap-server localhost:9092 \
#  --topic topic2 \
#  --property print.key=true \
#  --property key.separator=, \
#  --partition 1 \
#  --from-beginning \
#  --timeout-ms 1000

# 13 Send the statements to the REST API

tr '\n' ' ' < src/statements.sql | \
sed 's/;/;\'$'\n''/g' | \
while read stmt; do
    echo '{"ksql":"'$stmt'", "streamsProperties": {}}' | \
        curl -s -X "POST" "http://localhost:8088/ksql" \
             -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
             -d @- | \
        jq
done

# 14 Clean Up

docker-compose down

cd - && rm -rf $TEST_DIR
