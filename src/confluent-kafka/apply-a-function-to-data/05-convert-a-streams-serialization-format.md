
Try it
1
Initialize the project

To get started, make a new directory anywhere you’d like for this project:

mkdir ksql-serialization && cd ksql-serialization

Then make the following directories to set up its structure:

mkdir src test

2
Get Confluent Platform

Next, create the following docker-compose.yml file to obtain Confluent Platform:

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

And launch it by running:

docker-compose up -d

3
Write the program interactively using the CLI

To begin developing interactively, open up the ksqlDB CLI:

docker exec -it ksqldb-cli ksql http://ksqldb-server:8088

The first thing we’ll need is to create a Kafka topic and stream to represent the movie data. We declare the VALUE_FORMAT of the stream to be avro to denote the format of the events.

CREATE STREAM movies_avro (MOVIE_ID BIGINT KEY, title VARCHAR, release_year INT)
    WITH (KAFKA_TOPIC='avro-movies',
          PARTITIONS=1,
          VALUE_FORMAT='avro');

Then produce the following events to the stream. This will automatically format the data that goes onto the topic in Avro since the stream’s value format is declared as such.

INSERT INTO movies_avro (MOVIE_ID, title, release_year) VALUES (1, 'Lethal Weapon', 1992);
INSERT INTO movies_avro (MOVIE_ID, title, release_year) VALUES (2, 'Die Hard', 1988);
INSERT INTO movies_avro (MOVIE_ID, title, release_year) VALUES (3, 'Predator', 1997);

Now that you have a stream of JSON events, let’s convert them to Avro. Set the following properties to ensure that you’re reading from the beginning of the stream:

SET 'auto.offset.reset' = 'earliest';

To convert the events to Protobuf, we’re going to create a derived stream. All that is needed is to specify the VALUE_FORMAT as protobuf, and the conversion will happen automatically. You can also optionally specify the topic name as we’ve done here. Omitting this parameter will cause the underlying topic to be named the same as the stream name.

CREATE STREAM movies_proto
    WITH (KAFKA_TOPIC='proto-movies', VALUE_FORMAT='protobuf') AS
    SELECT * FROM movies_avro;

Because this is a continuous query, any new records arriving on the source in Avro (avro-movies) will be automatically converted to Protobuf on the derived topic (proto-movies).

To check that it’s working, print out the contents of the output stream’s underlying topic:

PRINT 'proto-movies' FROM BEGINNING LIMIT 3;

Note: the topic name needs to be quoted as it contains invalid characters, namely the '-'.

This should yield the following output:

Key format: KAFKA_BIGINT or KAFKA_DOUBLE or KAFKA_STRING
Value format: PROTOBUF
rowtime: 2020/05/29 22:21:08.375 Z, key: 1, value: TITLE: "Lethal Weapon" RELEASE_YEAR: 1992
rowtime: 2020/05/29 22:21:08.569 Z, key: 2, value: TITLE: "Die Hard" RELEASE_YEAR: 1988
rowtime: 2020/05/29 22:21:08.709 Z, key: 3, value: TITLE: "Predator" RELEASE_YEAR: 1997
Topic printing ceased

Notice the 'Value format' is reported as PROTOBUF.

Congrats! You’ve taken a topic formatted with Avro and created a continuously updating copy on a new topic in Protobuf.
4
Write your statements to a file

Now that you have a series of statements that’s doing the right thing, the last step is to put them into a file so that they can be used outside the CLI session. Create a file at src/statements.sql with the following content:

CREATE STREAM movies_avro (MOVIE_ID BIGINT KEY, title VARCHAR, release_year INT)
    WITH (KAFKA_TOPIC='avro-movies',
          PARTITIONS=1,
          VALUE_FORMAT='avro');

CREATE STREAM movies_proto
    WITH (KAFKA_TOPIC='proto-movies',
          PARTITIONS=1,
          VALUE_FORMAT='protobuf') AS
    SELECT * FROM movies_avro;

Test it
1
Create the test data

Create a file at test/input.json with the inputs for testing:

{
  "inputs": [
    {
      "topic": "avro-movies",
      "key": 1,
      "value": {
        "TITLE": "Lethal Weapon",
        "release_year": 1992
      }
    },
    {
      "topic": "avro-movies",
      "key": 2,
      "value": {
        "TITLE": "Die Hard",
        "release_year": 1988
      }
    },
    {
      "topic": "avro-movies",
      "key": 3,
      "value": {
        "TITLE": "Predator",
        "release_year": 1997
      }
    }
  ]
}

Similarly, create a file at test/output.json with the expected outputs:

{
  "outputs": [
    {
      "topic": "proto-movies",
      "key": 1,
      "value": {
        "TITLE": "Lethal Weapon",
        "RELEASE_YEAR": 1992
      }
    },
    {
      "topic": "proto-movies",
      "key": 2,
      "value": {
        "TITLE": "Die Hard",
        "RELEASE_YEAR": 1988
      }
    },
    {
      "topic": "proto-movies",
      "key": 3,
      "value": {
        "TITLE": "Predator",
        "RELEASE_YEAR": 1997
      }
    }
  ]
}

2
Invoke the tests

Lastly, invoke the tests using the test runner and the statements file that you created earlier:

docker exec ksqldb-cli ksql-test-runner -i /opt/app/test/input.json -s /opt/app/src/statements.sql -o /opt/app/test/output.json

Which should pass:

	 >>> Test passed!

Take it to production
1
Send the statements to the REST API

Launch your statements into production by sending them to the REST API with the following command:

tr '\n' ' ' < src/statements.sql | \
sed 's/;/;\'$'\n''/g' | \
while read stmt; do
    echo '{"ksql":"'$stmt'", "streamsProperties": {}}' | \
        curl -s -X "POST" "http://localhost:8088/ksql" \
             -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
             -d @- | \
        jq
done