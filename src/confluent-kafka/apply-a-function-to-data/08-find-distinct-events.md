
Try it
1
Initialize the project

To get started, make a new directory anywhere you’d like for this project:

mkdir finding-distinct && cd finding-distinct

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

  ksql-server:
    image: confluentinc/ksqldb-server:0.11.0
    hostname: ksql-server
    container_name: ksql-server
    depends_on:
      - broker
      - schema-registry
    ports:
      - "8088:8088"
    environment:
      KSQL_CONFIG_DIR: "/etc/ksqldb"
      KSQL_LOG4J_OPTS: "-Dlog4j.configuration=file:/etc/ksqldb/log4j.properties"
      KSQL_BOOTSTRAP_SERVERS: "broker:9092"
      KSQL_HOST_NAME: ksql-server
      KSQL_LISTENERS: "http://0.0.0.0:8088"
      KSQL_CACHE_MAX_BYTES_BUFFERING: 0
      KSQL_KSQL_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"

  ksql-cli:
    image: confluentinc/ksqldb-cli:0.11.0
    container_name: ksql-cli
    depends_on:
      - broker
      - ksql-server
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

To begin developing interactively, open up the KSQL CLI:

docker exec -it ksql-cli ksql http://ksql-server:8088

To start off the implementation of this scenario, we will create a stream that represents the clicks from the users. Since we will be handling time, it is important that each click contains a timestamp indicating when that click was done. The field TIMESTAMP will be used for this purpose.

CREATE STREAM CLICKS (IP_ADDRESS VARCHAR, URL VARCHAR, TIMESTAMP VARCHAR)
    WITH (KAFKA_TOPIC = 'CLICKS',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd''T''HH:mm:ssXXX',
          PARTITIONS = 1);

Now let’s produce some events that represent user clicks. Note that we are going to purposely produce duplicate events, in which each IP address will have clicked twice in the same URL.

INSERT INTO CLICKS (IP_ADDRESS, URL, TIMESTAMP) VALUES ('10.0.0.1', 'https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html', '2020-01-17T14:50:43+00:00');
INSERT INTO CLICKS (IP_ADDRESS, URL, TIMESTAMP) VALUES ('10.0.0.12', 'https://www.confluent.io/hub/confluentinc/kafka-connect-datagen', '2020-01-17T14:53:44+00:01');
INSERT INTO CLICKS (IP_ADDRESS, URL, TIMESTAMP) VALUES ('10.0.0.13', 'https://www.confluent.io/hub/confluentinc/kafka-connect-datagen', '2020-01-17T14:56:45+00:03');

INSERT INTO CLICKS (IP_ADDRESS, URL, TIMESTAMP) VALUES ('10.0.0.1', 'https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html', '2020-01-17T14:50:43+00:00');
INSERT INTO CLICKS (IP_ADDRESS, URL, TIMESTAMP) VALUES ('10.0.0.12', 'https://www.confluent.io/hub/confluentinc/kafka-connect-datagen', '2020-01-17T14:53:44+00:01');
INSERT INTO CLICKS (IP_ADDRESS, URL, TIMESTAMP) VALUES ('10.0.0.13', 'https://www.confluent.io/hub/confluentinc/kafka-connect-datagen', '2020-01-17T14:56:45+00:03');

Now that you have a stream with some events in it, let’s start to leverage them. The first thing to do is set the following properties to ensure that you’re reading from the beginning of the stream:

SET 'auto.offset.reset' = 'earliest';

Next, set cache.max.bytes.buffering to configure the frequency of output for tables. The value of 0 instructs ksqlDB to emit each matching record as soon as it is processed. Without this configuration, the queries below could appear to "miss" some records due to the default batching behavior.

SET 'cache.max.bytes.buffering' = '0';

Let’s experiment with these events. We need to create a query capable of displaying only distinct events, which means that duplicate IP addresses should be filtered out. Events are de-duped within a 2-minute window, and only unique clicks will be shown on that window.

We are going to use the LIMIT keyword to limit the amount of records shown in the output. If you want to experiment with this query and assess if it is displaying the correct results, go ahead and remove the limit keyword.

SELECT
    IP_ADDRESS,
    URL,
    TIMESTAMP
FROM CLICKS WINDOW TUMBLING (SIZE 2 MINUTES)
GROUP BY IP_ADDRESS, URL, TIMESTAMP
HAVING COUNT(IP_ADDRESS) = 1
EMIT CHANGES
LIMIT 3;

This query should produce the following output:

+-------------------------------------------------------------------------+-------------------------------------------------------------------------+-------------------------------------------------------------------------+
|IP_ADDRESS                                                               |URL                                                                      |TIMESTAMP                                                                |
+-------------------------------------------------------------------------+-------------------------------------------------------------------------+-------------------------------------------------------------------------+
|10.0.0.1                                                                 |https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/|2020-01-17T14:50:43+00:00                                                |
|                                                                         |docs/index.html                                                          |                                                                         |
|10.0.0.12                                                                |https://www.confluent.io/hub/confluentinc/kafka-connect-datagen          |2020-01-17T14:53:44+00:01                                                |
|10.0.0.13                                                                |https://www.confluent.io/hub/confluentinc/kafka-connect-datagen          |2020-01-17T14:56:45+00:03                                                |
Limit Reached
Query terminated

Note that only three records containing unique IP addresses are returned. This means that our query is working properly. Now let’s create some continuous queries to implement this scenario.

CREATE TABLE DETECTED_CLICKS AS
    SELECT
        IP_ADDRESS AS KEY1,
        URL AS KEY2,
        TIMESTAMP AS KEY3,
        AS_VALUE(IP_ADDRESS) AS IP_ADDRESS,
        AS_VALUE(URL) AS URL,
        AS_VALUE(TIMESTAMP) AS TIMESTAMP
    FROM CLICKS WINDOW TUMBLING (SIZE 2 MINUTES)
    GROUP BY IP_ADDRESS, URL, TIMESTAMP
    HAVING COUNT(IP_ADDRESS) = 1;

CREATE STREAM RAW_DISTINCT_CLICKS (IP_ADDRESS VARCHAR, URL VARCHAR, TIMESTAMP VARCHAR)
    WITH (KAFKA_TOPIC = 'DETECTED_CLICKS',
    VALUE_FORMAT = 'JSON');

CREATE STREAM DISTINCT_CLICKS AS
    SELECT
        IP_ADDRESS,
        URL,
        TIMESTAMP
    FROM RAW_DISTINCT_CLICKS
    WHERE IP_ADDRESS IS NOT NULL
    PARTITION BY IP_ADDRESS;

In the first statement above, we created the query that finds only distinct events, naming it DETECTED_CLICKS. We modeled it as a table since the query performs aggregations.

As we’re grouping by ip-address, url and timestamp, these columns will become part of the primary key of the table. Primary key columns are stored in the Kafka message’s key. As we’ll need them in the value later, we use AS_VALUE to copy the columns into the value and set their name. To avoid the value column names clashing with the key columns, we add aliases to rename the key columns.

As it stands, the key of the DETECTED_CLICKS table contains the ip-address, url, timestamp columns, and as the table is windowed, the window start time. Wouldn’t it be nice if the key was just the IP address? That’s what the next two statements do! The second statement declares a stream on top of the DETECTED_CLICKS changelog topic, defining only the value columns we’re interested in. This allows the third statement to set the key of the DISTINCT_CLICKS stream to just the IP address. It contains a filter to remove any rows where the ip-address is null to filter out any tombstones from the source topic. Tombstones are sent to the changelog to indicate a row has been deleted from the table; they have a null value, meaning ip-address will be null.

To verify everything is working as expected, run the following query:

SELECT
    IP_ADDRESS,
    URL,
    TIMESTAMP
FROM DISTINCT_CLICKS
EMIT CHANGES
LIMIT 3;

The output should look similar to:

+-------------------------------------------------------------------------+-------------------------------------------------------------------------+-------------------------------------------------------------------------+
|IP_ADDRESS                                                               |URL                                                                      |TIMESTAMP                                                                |
+-------------------------------------------------------------------------+-------------------------------------------------------------------------+-------------------------------------------------------------------------+
|10.0.0.1                                                                 |https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/|2020-01-17T14:50:43+00:00                                                |
|                                                                         |docs/index.html                                                          |                                                                         |
|10.0.0.12                                                                |https://www.confluent.io/hub/confluentinc/kafka-connect-datagen          |2020-01-17T14:53:44+00:01                                                |
|10.0.0.13                                                                |https://www.confluent.io/hub/confluentinc/kafka-connect-datagen          |2020-01-17T14:56:45+00:03                                                |
Limit Reached
Query terminated

Finally, let’s see what’s available on the underlying Kafka topic for the table. We can print that out easily.

PRINT DISTINCT_CLICKS FROM BEGINNING LIMIT 3;

The output should look similar to:

Key format: KAFKA_STRING
Value format: JSON or KAFKA_STRING
rowtime: 2020/01/17 14:50:43.000 Z, key: 10.0.0.1, value: {"URL":"https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html","TIMESTAMP":"2020-01-17T14:50:43+00:00"}
rowtime: 2020/01/17 14:52:44.000 Z, key: 10.0.0.12, value: {"URL":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","TIMESTAMP":"2020-01-17T14:53:44+00:01"}
rowtime: 2020/01/17 14:53:45.000 Z, key: 10.0.0.13, value: {"URL":"https://www.confluent.io/hub/confluentinc/kafka-connect-datagen","TIMESTAMP":"2020-01-17T14:56:45+00:03"}
Topic printing ceased

4
Write your statements to a file

Now that you have a series of statements that’s doing the right thing, the last step is to put them into a file so that they can be used outside the CLI session. Create a file at src/statements.sql with the following content:

CREATE STREAM CLICKS (IP_ADDRESS VARCHAR, URL VARCHAR, TIMESTAMP VARCHAR)
    WITH (KAFKA_TOPIC = 'CLICKS',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd''T''HH:mm:ssXXX',
          PARTITIONS = 1);

CREATE TABLE DETECTED_CLICKS AS
    SELECT
        IP_ADDRESS AS KEY1,
        URL AS KEY2,
        TIMESTAMP AS KEY3,
        AS_VALUE(IP_ADDRESS) AS IP_ADDRESS,
        AS_VALUE(URL) AS URL,
        AS_VALUE(TIMESTAMP) AS TIMESTAMP
    FROM CLICKS WINDOW TUMBLING (SIZE 2 MINUTES)
    GROUP BY IP_ADDRESS, URL, TIMESTAMP
    HAVING COUNT(IP_ADDRESS) = 1;

CREATE STREAM RAW_DISTINCT_CLICKS (IP_ADDRESS VARCHAR, URL VARCHAR, TIMESTAMP VARCHAR)
    WITH (KAFKA_TOPIC = 'DETECTED_CLICKS',
    VALUE_FORMAT = 'JSON');

CREATE STREAM DISTINCT_CLICKS AS
    SELECT
        IP_ADDRESS,
        URL,
        TIMESTAMP
    FROM RAW_DISTINCT_CLICKS
    WHERE IP_ADDRESS IS NOT NULL
    PARTITION BY IP_ADDRESS;

Test it
1
Create the test data

Create a file at test/input.json with the inputs for testing:

{
  "inputs": [
    {
      "topic": "CLICKS",
      "key": "10.0.0.1",
      "value": {
        "IP_ADDRESS": "10.0.0.1",
        "URL": "https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html",
        "TIMESTAMP": "2020-01-17T14:50:43+00:00"
      }
    },
    {
      "topic": "CLICKS",
      "key": "10.0.0.2",
      "value": {
        "IP_ADDRESS": "10.0.0.12",
        "URL": "https://www.confluent.io/hub/confluentinc/kafka-connect-datagen",
        "TIMESTAMP": "2020-01-17T14:53:44+00:01"
      }
    },
    {
      "topic": "CLICKS",
      "key": "10.0.0.3",
      "value": {
        "IP_ADDRESS": "10.0.0.13",
        "URL": "https://www.confluent.io/hub/confluentinc/kafka-connect-datagen",
        "TIMESTAMP": "2020-01-17T14:56:45+00:03"
      }
    },
    {
      "topic": "CLICKS",
      "key": "10.0.0.1",
      "value": {
        "IP_ADDRESS": "10.0.0.1",
        "URL": "https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html",
        "TIMESTAMP": "2020-01-17T14:50:43+00:00"
      }
    },
    {
      "topic": "CLICKS",
      "key": "10.0.0.2",
      "value": {
        "IP_ADDRESS": "10.0.0.12",
        "URL": "https://www.confluent.io/hub/confluentinc/kafka-connect-datagen",
        "TIMESTAMP": "2020-01-17T14:53:44+00:01"
      }
    },
    {
      "topic": "CLICKS",
      "key": "10.0.0.3",
      "value": {
        "IP_ADDRESS": "10.0.0.13",
        "URL": "https://www.confluent.io/hub/confluentinc/kafka-connect-datagen",
        "TIMESTAMP": "2020-01-17T14:56:45+00:03"
      }
    }
  ]
}

Similarly, create a file at test/output.json with the expected outputs.

{
  "outputs": [
    {
      "topic": "DISTINCT_CLICKS",
      "key": "10.0.0.1",
      "value": {
        "URL": "https://docs.confluent.io/current/tutorials/examples/kubernetes/gke-base/docs/index.html",
        "TIMESTAMP": "2020-01-17T14:50:43+00:00"
      },
      "timestamp": 1579272643000
    },
    {
      "topic": "DISTINCT_CLICKS",
      "key": "10.0.0.12",
      "value": {
        "URL": "https://www.confluent.io/hub/confluentinc/kafka-connect-datagen",
        "TIMESTAMP": "2020-01-17T14:53:44+00:01"
      },
      "timestamp": 1579272764000
    },
    {
      "topic": "DISTINCT_CLICKS",
      "key": "10.0.0.13",
      "value": {
        "URL": "https://www.confluent.io/hub/confluentinc/kafka-connect-datagen",
        "TIMESTAMP": "2020-01-17T14:56:45+00:03"
      },
      "timestamp": 1579272825000
    }
  ]
}

2
Invoke the tests

Lastly, invoke the tests using the test runner and the statements file that you created earlier:

docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s /opt/app/src/statements.sql -o /opt/app/test/output.json

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

In the steps above, we customized cache.max.bytes.buffering interactively via the CLI. Since this setting can affect overall throughput, it’s a good idea to assess its impact on disk I/O in production environments. The Kafka Streams documentation details the relevant internal mechanisms.
