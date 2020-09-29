
# How to transform a stream of events

## **Context**
- [1 Initialize the project](#1-initialize-the-project)
- [2 Get Confluent Platform](#2-get-confluent-platform)
- [3 Write the program interactively using the CLI](#3-write-the-program-interactively-using-the-cli)
- [4 Write your statements to a file](#4-write-your-statements-to-a-file)
- [5 Create the test data](#5-create-the-test-data)
- [6 Invoke the tests](#6-invoke-the-tests)
- [7 Send the statements to the REST API](#7-send-the-statements-to-the-rest-api)
- [8 Clean Up](#8-clean-up)

## 1 Initialize the project

To get started, make a new directory anywhere you’d like for this project:

```
mkdir transform-stream && cd transform-stream
```

Then make the following directories to set up its structure:
```
mkdir src test
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
    image: confluentinc/cp-enterprise-kafka:5.5.0
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
      KAFKA_METRIC_REPORTERS: io.confluent.metrics.reporter.ConfluentMetricsReporter
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      CONFLUENT_METRICS_REPORTER_BOOTSTRAP_SERVERS: broker:9092
      CONFLUENT_METRICS_REPORTER_ZOOKEEPER_CONNECT: zookeeper:2181
      CONFLUENT_METRICS_REPORTER_TOPIC_REPLICAS: 1
      CONFLUENT_METRICS_ENABLE: 'true'
      CONFLUENT_SUPPORT_CUSTOMER_ID: 'anonymous'

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

Now launch Confluent Platform by running:

```
docker-compose up -d
```

## 3 Write the program interactively using the CLI

To begin developing interactively, open up the ksqlDB CLI:
```
docker exec -it ksqldb-cli ksql http://ksqldb-server:8088
```

First, you’ll need to create a Kafka topic and stream to represent the publications. The following creates both in one
shot:
```
CREATE STREAM raw_movies (ID INT KEY, title VARCHAR, genre VARCHAR)
    WITH (kafka_topic='movies', partitions=1, value_format = 'avro');
```

Then produce the following events to the stream:

```
INSERT INTO raw_movies (id, title, genre) VALUES (294, 'Die Hard::1988', 'action');
INSERT INTO raw_movies (id, title, genre) VALUES (354, 'Tree of Life::2011', 'drama');
INSERT INTO raw_movies (id, title, genre) VALUES (782, 'A Walk in the Clouds::1995', 'romance');
INSERT INTO raw_movies (id, title, genre) VALUES (128, 'The Big Lebowski::1998', 'comedy');
```

Now that you have stream with some events in it, let’s read them out. The first thing to do is set the following
properties to ensure that you’re reading from the beginning of the stream:

```
SET 'auto.offset.reset' = 'earliest';
```

Let’s break apart the `title` field and extract the year that the movie was published into its own column. Issue the
following transient push query. This will block and continue to return results until its limit is reached or you tell
it to stop.

```
SELECT id, split(title, '::')[1] as title, split(title, '::')[2] AS year, genre FROM raw_movies EMIT CHANGES LIMIT 4;
```

This should yield the following output:

```
+---------------------+---------------------+---------------------+---------------------+
|ID                   |TITLE                |YEAR                 |GENRE                |
+---------------------+---------------------+---------------------+---------------------+
|294                  |Die Hard             |1988                 |action               |
|354                  |Tree of Life         |2011                 |drama                |
|782                  |A Walk in the Clouds |1995                 |romance              |
|128                  |The Big Lebowski     |1998                 |comedy               |
Limit Reached
Query terminated
```

Since the output looks right, the next step is to make the query continuous. Issue the following to create a new stream
that is continously populated by its query:

```
CREATE STREAM movies WITH (kafka_topic = 'parsed_movies', partitions = 1) AS
    SELECT id,
           split(title, '::')[1] as title,
           CAST(split(title, '::')[2] AS INT) AS year,
           genre
    FROM raw_movies;
```

To check that it’s working, print out the contents of the output stream’s underlying topic:

```
PRINT parsed_movies FROM BEGINNING LIMIT 4;
```

This should yield the following output:

```
Key format: KAFKA_INT
Value format: AVRO
rowtime: 2020/05/04 22:09:54.713 Z, key: 294, value: {"TITLE": "Die Hard", "YEAR": 1988, "GENRE": "action"}
rowtime: 2020/05/04 22:09:55.012 Z, key: 354, value: {"TITLE": "Tree of Life", "YEAR": 2011, "GENRE": "drama"}
rowtime: 2020/05/04 22:09:55.217 Z, key: 782, value: {"TITLE": "A Walk in the Clouds", "YEAR": 1995, "GENRE": "romance"}
rowtime: 2020/05/04 22:09:55.379 Z, key: 128, value: {"TITLE": "The Big Lebowski", "YEAR": 1998, "GENRE": "comedy"}
Topic printing ceased
```

## 4 Write your statements to a file

Now that you have a series of statements that’s doing the right thing, the last step is to put them into a file so that
they can be used outside the CLI session. Create a file at `src/statements.sql` with the following content:

```
CREATE STREAM raw_movies (ID INT KEY, title VARCHAR, genre VARCHAR)
    WITH (kafka_topic='movies', partitions=1, value_format = 'avro');

CREATE STREAM movies WITH (kafka_topic = 'parsed_movies', partitions = 1) AS
    SELECT id,
           split(title, '::')[1] as title,
           CAST(split(title, '::')[2] AS INT) AS year,
           genre
    FROM raw_movies;
```

## 5 Create the test data

Create a file at `test/input.json` with the inputs for testing:

```
{
  "inputs": [
    {
      "topic": "movies",
      "key": 294,
      "value": {
        "title": "Die Hard::1988",
        "genre": "action"
      }
    },
    {
      "topic": "movies",
      "key": 354,
      "value": {
        "title": "Tree of Life::2011",
        "genre": "drama"
      }
    },
    {
      "topic": "movies",
      "key": 782,
      "value": {
        "title": "A Walk in the Clouds::1995",
        "genre": "romance"
      }
    },
    {
      "topic": "movies",
      "key": 128,
      "value": {
        "title": "The Big Lebowski::1998",
        "genre": "comedy"
      }
    }
  ]
}
```

Similarly, create a file at `test/output.json` with the expected outputs:

```
{
  "outputs": [
    {
      "topic": "parsed_movies",
      "key": 294,
      "value": {
        "TITLE": "Die Hard",
        "YEAR": 1988,
        "GENRE": "action"
      }
    },
    {
      "topic": "parsed_movies",
      "key": 354,
      "value": {
        "TITLE": "Tree of Life",
        "YEAR": 2011,
        "GENRE": "drama"
      }
    },
    {
      "topic": "parsed_movies",
      "key": 782,
      "value": {
        "TITLE": "A Walk in the Clouds",
        "YEAR": 1995,
        "GENRE": "romance"
      }
    },
    {
      "topic": "parsed_movies",
      "key": 128,
      "value": {
        "TITLE": "The Big Lebowski",
        "YEAR": 1998,
        "GENRE": "comedy"
      }
    }
  ]
}
```

## 6 Invoke the tests

Lastly, invoke the tests using the test runner and the statements file that you created earlier:

```
docker exec ksqldb-cli ksql-test-runner -i /opt/app/test/input.json -s /opt/app/src/statements.sql -o /opt/app/test/output.json
```

Which should pass:

```
	 >>> Test passed!
```

## 7 Send the statements to the REST API

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

## 8 Clean Up

You’re all down now!

Go back to your open windows and stop any console producers and consumers with a `CTRL+C` then close the containter 
shells with a `CTRL+D` command.

Then you can shut down the stack by running:

```
docker-compose down
```
