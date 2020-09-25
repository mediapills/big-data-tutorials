
Try it

## 1 Initialize the project

To get started, make a new directory anywhere you’d like for this project:

```
mkdir change-topic-partitions-replicas && cd change-topic-partitions-replicas
```

Then make the following directories to set up its structure:

```
mkdir src test
```

## 2 Get Confluent Platform

Next, create the following docker-compose.yml file to obtain Confluent Platform:

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
      KAFKA_BROKER_ID: 101
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:9092,PLAINTEXT_HOST://localhost:29092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 2
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 2
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0

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
```

And launch it by running:

```
docker-compose up -d
```

## 3 Create the original topic

Your first step is to create the original Kafka topic. Use the following command to create the topic topic1 with 1 partition and 1 replica:

```
docker-compose exec broker kafka-topics --bootstrap-server broker:9092 --topic topic1 --create \
  --replication-factor 1 \
  --partitions 1
```

## 4 Describe the original topic

Describe the properties of the topic that you just created.

```
docker-compose exec broker kafka-topics --bootstrap-server broker:9092 --topic topic1 --describe
```

The output should be the following. Notice that the topic has 1 partition numbered 0, and 1 replica on a broker with an id of 101 (or 102).

```
Topic: topic1	PartitionCount: 1	ReplicationFactor: 1	Configs:
	Topic: topic1	Partition: 0	Leader: 101	Replicas: 101	Isr: 101
```

## 5 Write the program interactively using the CLI

To begin developing interactively, open up the ksqlDB CLI:

```
docker exec -it ksqldb-cli ksql http://ksqldb-server:8088
```

First, you’ll need to create a ksqlDB stream for the original topic topic1—let’s call the stream s1. The statement below specifies the message value serialization format is JSON but in your environment, VALUE_FORMAT should be set to match the serialization format of your original topic.

```
CREATE STREAM S1 (COLUMN0 VARCHAR KEY, COLUMN1 VARCHAR) WITH (KAFKA_TOPIC = 'topic1', VALUE_FORMAT = 'JSON');
```

Next, create a new ksqlDB stream—let’s call it s2—that will be backed by a new target Kafka topic topic2 with the desired number of partitions and replicas. Using the WITH clause, you can specify the partitions and replicas of the underlying Kafka topic.

The result of `SELECT * FROM S1 causes` every record from Kafka topic topic1 (with 1 partition and 1 replica) to be produced to Kafka topic topic2 (with 2 partitions and 2 replicas).

```
CREATE STREAM S2 WITH (KAFKA_TOPIC = 'topic2', VALUE_FORMAT = 'JSON', PARTITIONS = 2, REPLICAS = 2) AS SELECT * FROM S1;
```

Exit ksqlDB by typing exit;

## 6 Describe the new topic

Describe the properties of the new topic, topic2, underlying the ksqlDB stream you just created.

```
docker-compose exec broker kafka-topics --bootstrap-server broker:9092 --topic topic2 --describe
```

The output should be the following. Notice that the topic has 2 partitions, numbered 0 and 1, and 2 replicas on brokers with ids of 101 and 102.

```
Topic: topic2	PartitionCount: 2	ReplicationFactor: 2	Configs:
	Topic: topic2	Partition: 0	Leader: 102	Replicas: 102,101	Isr: 102,101
	Topic: topic2	Partition: 1	Leader: 101	Replicas: 101,102	Isr: 101,102
```

## 7 Write your statements to a file

Now that you have a series of statements that’s doing the right thing, the last step is to put them into a file so that they can be used outside the CLI session. Create a file at src/statements.sql with the following content:

```
CREATE STREAM S1 (COLUMN0 VARCHAR KEY, COLUMN1 VARCHAR) WITH (KAFKA_TOPIC = 'topic1', VALUE_FORMAT = 'JSON');

CREATE STREAM S2 WITH (KAFKA_TOPIC = 'topic2', VALUE_FORMAT = 'JSON', PARTITIONS = 2, REPLICAS = 2) AS SELECT * FROM S1;
```

Test it

## 1 Run the console Kafka producer

To produce data into the original Kafka topic topic1, open another terminal window and run the following command to open a second shell on the broker container:

```
docker-compose exec broker kafka-console-producer \
  --bootstrap-server localhost:9092 \
  --topic topic1 \
  --property parse.key=true \
  --property key.separator=,
```

The producer will start and wait for you to enter input in the next step.

## 2 Produce data to the original Kafka topic

The following text represents records to be written to the original topic topic1. Each line has the format 
<key>,<value>, whereby the , is the special delimiter character that separates the record key from the record value. 
Copy these records and paste them into the kafka-console-producer prompt that you started in the previous step.

```
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
```

Stop the producer by entering CTRL+C.

## 3 View the data in the original topic (partition 0)

Consume data from the original Kafka topic, specifying only to read from partition 0. Notice that all the data is read 
because all the data resides in the topic’s single partition.

```
docker-compose exec broker kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic topic1 \
  --property print.key=true \
  --property key.separator=, \
  --partition 0 \
  --from-beginning
```

You should see all the records in this partition.

```
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
Processed a total of 12 messages
```

Close the consumer by entering CTRL+C.

## 4 View the data in the new topic (partition 0)

Now consume data from the new Kafka topic topic2. First look at the data in partition 0.

```
docker-compose exec broker kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic topic2 \
  --property print.key=true \
  --property key.separator=, \
  --partition 0 \
  --from-beginning
```

You should see some of the records in this partition. In this example, the partitioner put all records with a key value of a, b, or c into partition 0.

```
a,{"COLUMN1":"1"}
b,{"COLUMN1":"1"}
c,{"COLUMN1":"1"}
a,{"COLUMN1":"2"}
b,{"COLUMN1":"2"}
c,{"COLUMN1":"2"}
a,{"COLUMN1":"3"}
b,{"COLUMN1":"3"}
c,{"COLUMN1":"3"}
Processed a total of 9 messages
```

Notice that the ordering of the data is still maintained per key.

Close the consumer by entering CTRL+C.

## 5 View the data in the new topic (partition 1)

Next look at the data in partition 1.

```
docker-compose exec broker kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic topic2 \
  --property print.key=true \
  --property key.separator=, \
  --partition 1 \
  --from-beginning
```

You should see the rest of the records in this partition. In this example, the partitioner put all records with a key value of d into partition 1.

```
d,{"COLUMN1":"1"}
d,{"COLUMN1":"2"}
d,{"COLUMN1":"3"}
Processed a total of 3 messages
```

Close the consumer by entering CTRL+C.

Take it to production

## 1 Send the statements to the REST API

Launch your statements into production by sending them to the REST API with the following command:

```
tr '\n' ' ' < src/statements.sql | \
sed 's/;/;\'$'\n''/g' | \
while read stmt; do
    echo '{"ksql":"'$stmt'", "streamsProperties": {}}' | \
        curl -s -X "POST" "http://localhost:8088/ksql" \
             -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
             -d @- | \
        jq
done
```

## 2 Clean up Docker containers

Shut down the stack by running:

```
docker-compose down
```
