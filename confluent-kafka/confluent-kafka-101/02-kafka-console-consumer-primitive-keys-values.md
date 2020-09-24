
## **Context**
- [1 Initialize the project](#1-initialize-the-project)
- [2 Get Confluent Platform](#2-get-confluent-platform)
- [3 Start an initial console consumer](#3-start-an-initial-console-consumer)
- [4 Specify key and value deserializers](#4-specify-key-and-value-deserializers)
- [5 Clean Up](#5-clean-up)

## 1 Initialize the project

To get started, make a new directory anywhere you’d like for this project:

```
mkdir console-consumer-primitive-keys-values && cd console-consumer-primitive-keys-values
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
    image: confluentinc/ksqldb-server:0.8.1
    hostname: ksqldb
    container_name: ksqldb
    depends_on:
      - broker
    ports:
      - "8088:8088"
    environment:
      KSQL_LISTENERS: http://0.0.0.0:8088
      KSQL_BOOTSTRAP_SERVERS: broker:9092
      KSQL_KSQL_LOGGING_PROCESSING_STREAM_AUTO_CREATE: "true"
      KSQL_KSQL_LOGGING_PROCESSING_TOPIC_AUTO_CREATE: "true"
      KSQL_KSQL_SCHEMA_REGISTRY_URL: http://schema-registry:8081
      KSQL_KSQL_HIDDEN_TOPICS: '^_.*'
      # Setting KSQL_KSQL_CONNECT_WORKER_CONFIG enables embedded Kafka Connect
      KSQL_KSQL_CONNECT_WORKER_CONFIG: "/connect/connect.properties"
      # Kafka Connect config below
      KSQL_CONNECT_BOOTSTRAP_SERVERS: "broker:9092"
      KSQL_CONNECT_REST_ADVERTISED_HOST_NAME: 'ksqldb'
      KSQL_CONNECT_REST_PORT: 8083
      KSQL_CONNECT_GROUP_ID: ksqldb-kafka-connect-group-01
      KSQL_CONNECT_CONFIG_STORAGE_TOPIC: _ksqldb-kafka-connect-group-01-configs
      KSQL_CONNECT_OFFSET_STORAGE_TOPIC: _ksqldb-kafka-connect-group-01-offsets
      KSQL_CONNECT_STATUS_STORAGE_TOPIC: _ksqldb-kafka-connect-group-01-status
      KSQL_CONNECT_KEY_CONVERTER: org.apache.kafka.connect.converters.LongConverter
      KSQL_CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.converters.DoubleConverter
      KSQL_CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: '1'
      KSQL_CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: '1'
      KSQL_CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: '1'
      KSQL_CONNECT_LOG4J_APPENDER_STDOUT_LAYOUT_CONVERSIONPATTERN: "[%d] %p %X{connector.context}%m (%c:%L)%n"
      KSQL_CONNECT_PLUGIN_PATH: '/usr/share/java,/usr/share/confluent-hub-components/,/data/connect-jars'

    command:
      # In the command section, $ are replaced with $$ to avoid the error 'Invalid interpolation format for "command" option'
      - bash
      - -c
      - |
        echo "Installing connector plugins"
        mkdir -p /usr/share/confluent-hub-components/
        confluent-hub install --no-prompt --component-dir /usr/share/confluent-hub-components/ mdrogalis/voluble:0.3.0
        #
        echo "Launching ksqlDB"
        /usr/bin/docker/run &


         echo "Waiting for Kafka Connect to start listening on localhost ⏳"
        while : ; do
          curl_status=$$(curl -s -o /dev/null -w %{http_code} http://localhost:8083/connectors)
          echo -e $$(date) " Kafka Connect listener HTTP state: " $$curl_status " (waiting for 200)"
          if [ $$curl_status -eq 200 ] ; then
            break
          fi
          sleep 5
        done

        echo -e "\n--\n+> Creating Data Generator source"
        curl -X PUT http://localhost:8083/connectors/example/config \
         -i -H "Content-Type: application/json" -d'{
            "connector.class": "io.mdrogalis.voluble.VolubleSourceConnector",
            "genkp.example.with" : "#{Number.randomNumber}",
            "genvp.example.with" : "#{Address.latitude}",
            "topic.example.records.exactly" : 10,
            "transforms": "CastLong,CastDouble",
            "transforms.CastLong.type": "org.apache.kafka.connect.transforms.Cast$$Key",
            "transforms.CastLong.spec": "int64",
            "transforms.CastDouble.type": "org.apache.kafka.connect.transforms.Cast$$Value",
            "transforms.CastDouble.spec": "float64",
            "key.converter": "org.apache.kafka.connect.converters.LongConverter",
            "key.converter.schemas.enable" : "false",
            "value.converter": "org.apache.kafka.connect.converters.DoubleConverter",
            "value.converter.schemas.enable" : "false",
            "tasks.max": 1
        }'

        sleep infinity
```

Currently, the console producer only writes strings into Kafka, but we want to work with non-string primitives and the 
console consumer. So in this tutorial, your `docker-compose.yml` file will also create a source connector embedded in 
`ksqldb-server` to populate a topic with keys of type `long` and values of type `double`.

And launch it by running:

```
docker-compose up -d
```

After you’ve ran the `docker-compose up -d` command, wait 30 seconds to a 1 minute before executing the next step.

## 3 Start an initial console consumer

Now you’ll use a topic created in the previous step. Your focus here is the reading values on the command line with the 
console consumer. The records have the format of `key = Long` and `value = Double`.

Let’s start up a console consumer to read some records. Run this command in the container shell:

```
docker-compose exec broker kafka-console-consumer --topic example --bootstrap-server broker:9092 \
 --from-beginning \
 --property print.key=true \
 --property key.separator=" : "
```

After the consumer starts up, you’ll get some output, but nothing readable is on the screen. You should see something 
similar to this:

```
!? : @'?u_?mY
J? : ?(?,???
?c : @T?????
?? : @S{??ދ
?? : @F!?u??
? : ??{??%??
#f : @S??
?A
 : ?T5Ni?^?
 : ?κ?e
 : @>ֈ&???
``` 

The output looks like this because you are consuming records with a `Long` key and a `Double` value, but you haven’t 
provided the correct deserializer for longs or doubles.

Close the consumer with a `Ctrl+C` command, but keep the container shell open.

## 4 Specify key and value deserializers

Now let’s update your command to the console consumer to specify the deserializer for keys and values.

In the same window of your previous console consumer run this updated command in the container shell:
```
docker-compose exec broker kafka-console-consumer --topic example --bootstrap-server broker:9092 \
 --from-beginning \
 --property print.key=true \
 --property key.separator=" : " \
 --key-deserializer "org.apache.kafka.common.serialization.LongDeserializer" \
 --value-deserializer "org.apache.kafka.common.serialization.DoubleDeserializer"
```

After the consumer starts you should see readable numbers similar to this:

```
8666 : 11.914958
19146 : -12.034799
34659 : 83.75128
310944 : 76.023163
302796 : 44.264754
374486 : 1.0302151
69428755 : 79.296206
4 : -80.832911
4 : -2.2259418
7 : 30.838015
```

Now you know how to configure a console consumer to handle primitive types - `Double`, `Long`, `Float`, `Integer` and 
`Short`.

Strings are the default value so you don’t have to specify a deserializer for those.

## 5 Clean Up

You’re all down now!

Go back to your open windows and stop any console producers and consumers with a `CTRL+C` then close the containter 
shells with a `CTRL+D` command.

Then you can shut down the stack by running:

```
docker-compose down
```
