
Try it
1
Initialize the project

To get started, make a new directory anywhere you’d like for this project:

mkdir deserialization-errors && cd deserialization-errors

Then make the following directories to set up its structure:

mkdir log4j src test

2
Create a log4J configuration

In order to implement a stream that will contain any deserialization errors that occurs in KSQL, we will enable the KSQL Processing Log feature. This feature allows us to capture any errors from KSQL and send to a topic that we will designate. The first step to enable this feature is to create a custom Log4J configuration file that contains an appender capable of sending events with the errors to a Kafka topic. Create a file named log4j.properties within the log4j folder with the content below.

log4j.rootLogger=INFO, main

# appenders
log4j.appender.main=org.apache.log4j.RollingFileAppender
log4j.appender.main.File=/etc/ksql/ksql.log
log4j.appender.main.layout=org.apache.log4j.PatternLayout
log4j.appender.main.layout.ConversionPattern=[%d] %p %m (%c:%L)%n
log4j.appender.main.MaxFileSize=10MB
log4j.appender.main.MaxBackupIndex=5
log4j.appender.main.append=true

log4j.appender.streams=org.apache.log4j.RollingFileAppender
log4j.appender.streams.File=/etc/ksql/ksql-streams.log
log4j.appender.streams.layout=org.apache.log4j.PatternLayout
log4j.appender.streams.layout.ConversionPattern=[%d] %p %m (%c:%L)%n

log4j.appender.kafka=org.apache.log4j.RollingFileAppender
log4j.appender.kafka.File=/etc/ksql/ksql-kafka.log
log4j.appender.kafka.layout=org.apache.log4j.PatternLayout
log4j.appender.kafka.layout.ConversionPattern=[%d] %p %m (%c:%L)%n
log4j.appender.kafka.MaxFileSize=10MB
log4j.appender.kafka.MaxBackupIndex=5
log4j.appender.kafka.append=true

log4j.appender.kafka_appender=org.apache.kafka.log4jappender.KafkaLog4jAppender
log4j.appender.kafka_appender.layout=io.confluent.common.logging.log4j.StructuredJsonLayout
log4j.appender.kafka_appender.BrokerList=broker:9092
log4j.appender.kafka_appender.Topic=ksql_processing_log
log4j.logger.processing=ERROR, kafka_appender

# loggers
log4j.logger.org.apache.kafka.streams=INFO, streams
log4j.additivity.org.apache.kafka.streams=false

log4j.logger.kafka=ERROR, kafka
log4j.additivity.kafka=false

log4j.logger.org.apache.zookeeper=ERROR, kafka
log4j.additivity.org.apache.zookeeper=false

log4j.logger.org.apache.kafka=ERROR, kafka
log4j.additivity.org.apache.kafka=false

log4j.logger.org.I0Itec.zkclient=ERROR, kafka
log4j.additivity.org.I0Itec.zkclient=false

log4j.logger.processing=ERROR, kafka_appender
log4j.additivity.processing=false

Note that we declared an appender with the org.apache.kafka.log4jappender.KafkaLog4jAppender implementation. This appender is able to produce records to a Kafka topic containing any event from the log. The Kafka cluster and topic being used are specified via the properties 'BrokerList' and 'Topic', respectively. Also note that the appender has been configured to send events using the JSON format, in the property 'layout'.
3
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
        KSQL_LOG4J_OPTS: "-Dlog4j.configuration=file:/opt/app/log4j/log4j.properties"
        KSQL_BOOTSTRAP_SERVERS: "broker:9092"
        KSQL_HOST_NAME: ksqldb-server
        KSQL_LISTENERS: "http://0.0.0.0:8088"
        KSQL_CACHE_MAX_BYTES_BUFFERING: 0
        KSQL_KSQL_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
        KSQL_KSQL_LOGGING_PROCESSING_TOPIC_AUTO_CREATE: 'true'
        KSQL_KSQL_LOGGING_PROCESSING_TOPIC_NAME: 'ksql_processing_log'
        KSQL_KSQL_LOGGING_PROCESSING_STREAM_AUTO_CREATE: 'true'
        KSQL_KSQL_LOGGING_PROCESSING_ROWS_INCLUDE: 'true'
      volumes:
        - ./log4j:/opt/app/log4j

    ksqldb-cli:
      image: confluentinc/ksqldb-cli:0.11.0
      container_name: ksqldb-cli
      depends_on:
        - broker
        - ksqldb-server
      entrypoint: /bin/sh
      tty: true
      environment:
        KSQL_CONFIG_DIR: "/etc/ksqldb"
      volumes:
        - ./src:/opt/app/src
        - ./test:/opt/app/test

Note that there is some special configuration for the container ksql-server. We have enabled the support for the KSQL Processing Log feature by specifying that we want to have both the topic and the stream that will hold deserialization errors automatically. We also specified that the topic name should be ksql_processing_log and that we want that each event produced to the topic also include a copy of the row that caused the deserialization error. This is very important if you want to have all the tools needed to figure out what went wrong.

Now that you have everything properly set up, you can start the containers by running:

docker-compose up -d

4
Create the input topic with a stream

Create a new client session for KSQL using the following command:

docker exec -it ksqldb-cli ksql http://ksqldb-server:8088

To start off the implementation of this scenario, you need to create a stream that represent sensors. This stream will contain a timestamp field called TIMESTAMP to indicate when the sensor was enabled. Each sensor will also have a field called ENABLED to indicate the status of the sensor. While this stream acts upon data stored in a topic called SENSORS_RAW, we will create derived stream called SENSORS to actually handle the sensors. This stream simply copies the data from the previous stream, ensuring that the ID field is used as the key.

CREATE STREAM SENSORS_RAW (id VARCHAR, timestamp VARCHAR, enabled BOOLEAN)
    WITH (KAFKA_TOPIC = 'SENSORS_RAW',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1);

CREATE STREAM SENSORS AS
    SELECT
        ID, TIMESTAMP, ENABLED
    FROM SENSORS_RAW
    PARTITION BY ID;

5
Produce events to the input topic

Before we move foward with the implementation, we need to produce records to the SENSORS_RAW topic, that as explained earlier, is the underlying topic behind the SENSORS stream. Let’s use the console producer to create some records.

docker exec -i broker /usr/bin/kafka-console-producer --broker-list broker:9092 --topic SENSORS_RAW

When the console producer starts, it will log some messages and hang, waiting for your input. Type in one line at a time and press enter to send it. Each line represents an sensor with the required data. Note that for testing purposes, we are providing two records with data in the right format (notably the first two records) and one record with an error. The record with the error contains the field ENABLED specified as string instead of a boolean. To send all sensors below, paste the following into the prompt and press enter:

{"id": "e7f45046-ad13-404c-995e-1eca16742801", "timestamp": "2020-01-15 02:20:30", "enabled": true}
{"id": "835226cf-caf6-4c91-a046-359f1d3a6e2e", "timestamp": "2020-01-15 02:25:30", "enabled": true}
{"id": "1a076a64-4a84-40cb-a2e8-2190f3b37465", "timestamp": "2020-01-15 02:30:30", "enabled": "true"}

6
Checking for deserialization errors

Create a new client session for KSQL using the following command:

docker exec -it ksqldb-cli ksql http://ksqldb-server:8088

Now that you have stream with some events in it, let’s start to leverage them. The first thing to do is set the following properties to ensure that you’re reading from the beginning of the stream:

SET 'auto.offset.reset' = 'earliest';

We know that we produced three records to the stream but only two of them were actually correct. In order to check if these two records were properly written into the stream, run the query below:

SELECT
    ID,
    TIMESTAMP,
    ENABLED
FROM SENSORS EMIT CHANGES LIMIT 2;

The output should look similar to:

+-------------------------------------------+-------------------------------------------+-------------------------------------------+
|ID                                         |TIMESTAMP                                  |ENABLED                                    |
+-------------------------------------------+-------------------------------------------+-------------------------------------------+
|e7f45046-ad13-404c-995e-1eca16742801       |2020-01-15 02:20:30                        |true                                       |
|835226cf-caf6-4c91-a046-359f1d3a6e2e       |2020-01-15 02:25:30                        |true                                       |
Limit Reached
Query terminated

For testing purposes, you can omit the limit clause to check if indeed there is only two records in the stream. Do it if you feel the urge to double-check this.

Now here comes the fun part. We know that at least one of the records produced had an error, because we specified the field ENABLED as a string instead of a boolean. This should yield one deserialization error because we can’t write a string into a boolean. Therefore, this one error needs to show up somewhere. With the KSQL Processing Log feature enabled, you can query a stream called KSQL_PROCESSING_LOG to check for deserialization errors.

The query below is extracting some of the data available in the processing log. As we configured the processing log to include the payload of the message, we can also use the encode method to convert the record from base64 encoded into a human readable utf8 encoding:

SELECT
    message->deserializationError->errorMessage,
    encode(message->deserializationError->RECORDB64, 'base64', 'utf8') AS MSG,
    message->deserializationError->cause
  FROM KSQL_PROCESSING_LOG
  EMIT CHANGES
  LIMIT 1;

Notice we needed to quote the topic field in the WHERE clause, as it’s a reserved word.

While the ERRORMESSAGE is a little cryptic in this instance, the CAUSE and MSG columns would be enough to diagnose the issue here.

This query should produce the following output:

+-------------------------------------------+-------------------------------------------+-------------------------------------------+
|ERRORMESSAGE                               |MSG                                        |CAUSE                                      |
+-------------------------------------------+-------------------------------------------+-------------------------------------------+
|mvn value from topic: SENSORS_RAW          |{"id": "1a076a64-4a84-40cb-a2e8-2190f3b3746|[Can't convert type. sourceType: TextNode, |
|                                           |5", "timestamp": "2020-01-15 02:30:30", "en|requiredType: BOOLEAN, path: $.ENABLED, Can|
|                                           |abled": "true"}                            |'t convert type. sourceType: TextNode, requ|
|                                           |                                           |iredType: BOOLEAN, path: .ENABLED, Can't co|
|                                           |                                           |nvert type. sourceType: TextNode, requiredT|
|                                           |                                           |ype: BOOLEAN]                              |
Limit Reached
Query terminated

We purposely selected only some fields to prove the point about showing deserialization errors with the KSQL_PROCESSING_LOG stream, but each event produced to this stream carries much more useful data. Print the contents of its underlying topic to see some more.

PRINT ksql_processing_log FROM BEGINNING LIMIT 1;

The output should look similar to:

Key format: ¯\_(ツ)_/¯ - no data processed
Value format: JSON or KAFKA_STRING
rowtime: 2020/06/05 11:25:21.181 Z, key: <null>, value: {"level":"ERROR","logger":"processing.CSAS_SENSORS_0.KsqlTopic.Source.deserializer","time":1591356321152,"message":{"type":0,"deserializationError":{"errorMessage":"mvn value from topic: SENSORS_RAW","recordB64":"eyJpZCI6ICIxYTA3NmE2NC00YTg0LTQwY2ItYTJlOC0yMTkwZjNiMzc0NjUiLCAidGltZXN0YW1wIjogIjIwMjAtMDEtMTUgMDI6MzA6MzAiLCAiZW5hYmxlZCI6ICJ0cnVlIn0=","cause":["Can't convert type. sourceType: TextNode, requiredType: BOOLEAN, path: $.ENABLED","Can't convert type. sourceType: TextNode, requiredType: BOOLEAN, path: .ENABLED","Can't convert type. sourceType: TextNode, requiredType: BOOLEAN"],"topic":"SENSORS_RAW"},"recordProcessingError":null,"productionError":null}}
Topic printing ceased

7
Write your statements to a file

Now that you have a series of statements that’s doing the right thing, the last step is to put them into a file so that they can be used outside the CLI session. Create a file at src/statements.sql with the following content:

CREATE STREAM SENSORS_RAW (id VARCHAR, timestamp VARCHAR, enabled BOOLEAN)
    WITH (KAFKA_TOPIC = 'SENSORS_RAW',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1);

CREATE STREAM SENSORS AS
    SELECT
        ID, TIMESTAMP, ENABLED
    FROM SENSORS_RAW
    PARTITION BY ID;

Test it
1
Create the test data

Create a file at test/input.json with the inputs for testing:

{
  "inputs": [
    {
      "topic": "SENSORS_RAW",
      "value": {
        "ID": "e7f45046-ad13-404c-995e-1eca16742801",
        "TIMESTAMP": "2020-01-15 02:20:30",
        "ENABLED": true
      }
    },
    {
      "topic": "SENSORS_RAW",
      "value": {
        "ID": "835226cf-caf6-4c91-a046-359f1d3a6e2e",
        "TIMESTAMP": "2020-01-15 02:25:30",
        "ENABLED": true
      }
    },
    {
      "topic": "SENSORS_RAW",
      "value": {
        "ID": "1a076a64-4a84-40cb-a2e8-2190f3b37465",
        "TIMESTAMP": "2020-01-15 02:30:30",
        "ENABLED": "true"
      }
    }
  ]
}

Similarly, create a file at test/output.json with the expected outputs.

{
  "outputs": [
    {
      "topic": "SENSORS",
      "key": "e7f45046-ad13-404c-995e-1eca16742801",
      "value": {
        "TIMESTAMP": "2020-01-15 02:20:30",
        "ENABLED": true
      },
      "timestamp": 1579054830000
    },
    {
      "topic": "SENSORS",
      "key": "835226cf-caf6-4c91-a046-359f1d3a6e2e",
      "value": {
        "TIMESTAMP": "2020-01-15 02:25:30",
        "ENABLED": true
      },
      "timestamp": 1579055130000
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

statements=$(< src/statements.sql) && \
    echo '{"ksql":"'$statements'", "streamsProperties": {}}' | \
        curl -X "POST" "http://localhost:8088/ksql" \
             -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
             -d @- | \
        jq
