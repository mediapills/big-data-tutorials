
Try it
1
Initialize the project

To get started, make a new directory anywhere you’d like for this project:

mkdir merge-streams && cd merge-streams

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

First, you’ll need to create a series of Kafka topics and streams to represent the different genres of music:

CREATE STREAM rock_songs (artist VARCHAR, title VARCHAR)
    WITH (kafka_topic='rock_songs', partitions=1, value_format='avro');

CREATE STREAM classical_songs (artist VARCHAR, title VARCHAR)
    WITH (kafka_topic='classical_songs', partitions=1, value_format='avro');

CREATE STREAM all_songs (artist VARCHAR, title VARCHAR, genre VARCHAR)
    WITH (kafka_topic='all_songs', partitions=1, value_format='avro');

Let’s produce some events for rock songs:

INSERT INTO rock_songs (artist, title) VALUES ('Metallica', 'Fade to Black');
INSERT INTO rock_songs (artist, title) VALUES ('Smashing Pumpkins', 'Today');
INSERT INTO rock_songs (artist, title) VALUES ('Pink Floyd', 'Another Brick in the Wall');
INSERT INTO rock_songs (artist, title) VALUES ('Van Halen', 'Jump');
INSERT INTO rock_songs (artist, title) VALUES ('Led Zeppelin', 'Kashmir');

And do the same classical music:

INSERT INTO classical_songs (artist, title) VALUES ('Wolfgang Amadeus Mozart', 'The Magic Flute');
INSERT INTO classical_songs (artist, title) VALUES ('Johann Pachelbel', 'Canon');
INSERT INTO classical_songs (artist, title) VALUES ('Ludwig van Beethoven', 'Symphony No. 5');
INSERT INTO classical_songs (artist, title) VALUES ('Edward Elgar', 'Pomp and Circumstance');

Now that the streams are populated with events, let’s start to merge the genres back together. The first thing to do is set the following properties to ensure that you’re reading from the beginning of the stream in your queries:

SET 'auto.offset.reset' = 'earliest';

Time to merge the individual streams into one big one. To do that, we’ll use insert into. This bit of syntax takes the contents of one stream and pours them into another. We do this with all of the declared genres. You’ll notice that we select not only the title and artist, but also a string literal representing the genre. This allows us to track the lineage of which stream each event is derived from. Note that the order of the individual streams is retained in the larger stream, but the individual elements of each stream will likely be woven together depending on timing:

INSERT INTO all_songs SELECT artist, title, 'rock' AS genre FROM rock_songs;
INSERT INTO all_songs SELECT artist, title, 'classical' AS genre FROM classical_songs;

To verify that our streams are connecting together as we hope they are, we can describe the stream that contains all the songs:

DESCRIBE EXTENDED ALL_SONGS;

This should yield roughly the following output. Notice that our insert statements appear as writers to this stream:

Name                 : ALL_SONGS
Type                 : STREAM
Timestamp field      : Not set - using <ROWTIME>
Key format           : KAFKA
Value format         : AVRO
Kafka topic          : all_songs (partitions: 1, replication: 1)
Statement            : CREATE STREAM all_songs (artist VARCHAR, title VARCHAR, genre VARCHAR)
    WITH (kafka_topic='all_songs', partitions=1, value_format='avro');

 Field  | Type

 ARTIST | VARCHAR(STRING)
 TITLE  | VARCHAR(STRING)
 GENRE  | VARCHAR(STRING)


Queries that write from this STREAM
-----------------------------------
INSERTQUERY_7 (RUNNING) : INSERT INTO all_songs SELECT artist, title, 'classical' AS genre FROM classical_songs;
INSERTQUERY_0 (RUNNING) : INSERT INTO all_songs SELECT artist, title, 'rock' AS genre FROM rock_songs;

For query topology and execution plan please run: EXPLAIN <QueryId>

Local runtime statistics
------------------------


(Statistics of the local KSQL server interaction with the Kafka topic all_songs)

Let’s quickly check the contents of the stream to see that records of all genres are present. Issue the following transient push query. This will block and continue to return results until its limit is reached or you tell it to stop.

SELECT artist, title, genre FROM all_songs EMIT CHANGES LIMIT 9;

This should yield the following output:

+------------------------------+------------------------------+------------------------------+
|ARTIST                        |TITLE                         |GENRE                         |
+------------------------------+------------------------------+------------------------------+
|Wolfgang Amadeus Mozart       |The Magic Flute               |classical                     |
|Johann Pachelbel              |Canon                         |classical                     |
|Ludwig van Beethoven          |Symphony No. 5                |classical                     |
|Edward Elgar                  |Pomp and Circumstance         |classical                     |
|Metallica                     |Fade to Black                 |rock                          |
|Smashing Pumpkins             |Today                         |rock                          |
|Pink Floyd                    |Another Brick in the Wall     |rock                          |
|Van Halen                     |Jump                          |rock                          |
|Led Zeppelin                  |Kashmir                       |rock                          |
Limit Reached
Query terminated

Finally, we can check the underlying Kafka topic by printing its contents:

PRINT all_songs FROM BEGINNING LIMIT 9;

Which should yield:

Key format: ¯\_(ツ)_/¯ - no data processed
Value format: AVRO or KAFKA_STRING
rowtime: 2020/05/04 22:36:27.150 Z, key: <null>, value: {"ARTIST": "Metallica", "TITLE": "Fade to Black", "GENRE": "rock"}
rowtime: 2020/05/04 22:36:27.705 Z, key: <null>, value: {"ARTIST": "Wolfgang Amadeus Mozart", "TITLE": "The Magic Flute", "GENRE": "classical"}
rowtime: 2020/05/04 22:36:27.789 Z, key: <null>, value: {"ARTIST": "Johann Pachelbel", "TITLE": "Canon", "GENRE": "classical"}
rowtime: 2020/05/04 22:36:27.912 Z, key: <null>, value: {"ARTIST": "Ludwig van Beethoven", "TITLE": "Symphony No. 5", "GENRE": "classical"}
rowtime: 2020/05/04 22:36:28.139 Z, key: <null>, value: {"ARTIST": "Edward Elgar", "TITLE": "Pomp and Circumstance", "GENRE": "classical"}
rowtime: 2020/05/04 22:36:27.263 Z, key: <null>, value: {"ARTIST": "Smashing Pumpkins", "TITLE": "Today", "GENRE": "rock"}
rowtime: 2020/05/04 22:36:27.370 Z, key: <null>, value: {"ARTIST": "Pink Floyd", "TITLE": "Another Brick in the Wall", "GENRE": "rock"}
rowtime: 2020/05/04 22:36:27.488 Z, key: <null>, value: {"ARTIST": "Van Halen", "TITLE": "Jump", "GENRE": "rock"}
rowtime: 2020/05/04 22:36:27.601 Z, key: <null>, value: {"ARTIST": "Led Zeppelin", "TITLE": "Kashmir", "GENRE": "rock"}
Topic printing ceased

4
Write your statements to a file

Now that you have a series of statements that’s doing the right thing, the last step is to put them into a file so that they can be used outside the CLI session. Create a file at src/statements.sql with the following content:

CREATE STREAM rock_songs (artist VARCHAR, title VARCHAR)
    WITH (kafka_topic='rock_songs', partitions=1, value_format='avro');

CREATE STREAM classical_songs (artist VARCHAR, title VARCHAR)
    WITH (kafka_topic='classical_songs', partitions=1, value_format='avro');

CREATE STREAM all_songs (artist VARCHAR, title VARCHAR, genre VARCHAR)
    WITH (kafka_topic='all_songs', partitions=1, value_format='avro');

INSERT INTO all_songs SELECT artist, title, 'rock' AS genre FROM rock_songs;

INSERT INTO all_songs SELECT artist, title, 'classical' AS genre FROM classical_songs;

Test it
1
Create the test data

Create a file at test/input.json with the inputs for testing:

{
  "inputs": [
    {
      "topic": "rock_songs",
      "value": {
        "artist": "Metallica",
        "title": "Fade to Black"
      }
    },
    {
      "topic": "rock_songs",
      "value": {
        "artist": "Smashing Pumpkins",
        "title": "Today"
      }
    },
    {
      "topic": "rock_songs",
      "value": {
        "artist": "Pink Floyd",
        "title": "Another Brick in the Wall"
      }
    },
    {
      "topic": "rock_songs",
      "value": {
        "artist": "Van Halen",
        "title": "Jump"
      }
    },
    {
      "topic": "rock_songs",
      "value": {
        "artist": "Led Zeppelin",
        "title": "Kashmir"
      }
    },
    {
      "topic": "classical_songs",
      "value": {
        "artist": "Wolfgang Amadeus Mozart",
        "title": "The Magic Flute"
      }
    },
    {
      "topic": "classical_songs",
      "value": {
        "artist": "Johann Pachelbel",
        "title": "Canon"
      }
    },
    {
      "topic": "classical_songs",
      "value": {
        "artist": "Ludwig van Beethoven",
        "title": "Symphony No. 5"
      }
    },
    {
      "topic": "classical_songs",
      "value": {
        "artist": "Edward Elgar",
        "title": "Pomp and Circumstance"
      }
    }
  ]
}

Similarly, create a file at test/output.json with the expected outputs. Note that we’re expecting events in the order that we issued the insert statements. The test runner will determine its output order based on the order of the statements.

{
  "outputs": [
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Metallica",
        "TITLE": "Fade to Black",
        "GENRE": "rock"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Smashing Pumpkins",
        "TITLE": "Today",
        "GENRE": "rock"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Pink Floyd",
        "TITLE": "Another Brick in the Wall",
        "GENRE": "rock"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Van Halen",
        "TITLE": "Jump",
        "GENRE": "rock"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Led Zeppelin",
        "TITLE": "Kashmir",
        "GENRE": "rock"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Wolfgang Amadeus Mozart",
        "TITLE": "The Magic Flute",
        "GENRE": "classical"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Johann Pachelbel",
        "TITLE": "Canon",
        "GENRE": "classical"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Ludwig van Beethoven",
        "TITLE": "Symphony No. 5",
        "GENRE": "classical"
      }
    },
    {
      "topic": "all_songs",
      "value": {
        "ARTIST": "Edward Elgar",
        "TITLE": "Pomp and Circumstance",
        "GENRE": "classical"
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