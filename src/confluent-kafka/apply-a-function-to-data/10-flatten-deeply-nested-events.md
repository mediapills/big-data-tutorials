
Try it
1
Initialize the project

To get started, make a new directory anywhere you’d like for this project:

mkdir flatten-nested-data && cd flatten-nested-data

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
    tty: true
    environment:
      KSQL_CONFIG_DIR: "/etc/ksqldb"
    volumes:
      - ./src:/opt/app/src
      - ./test:/opt/app/test

And launch it by running:

docker-compose up -d

3
Create the input topic with a stream

The first thing that we’re going to do is create a input topic that will contain the orders. For this, we are going to create a stream with the definition of the order and the fields that contain nested data. To create the stream, open a session with KSQL using the following command:

docker exec -it ksqldb-cli ksql http://ksqldb-server:8088

Create the following stream with the representation of the orders. We use the STRUCT keyword to define the fields that contain nested data.

CREATE STREAM ORDERS (
    id VARCHAR,
    timestamp VARCHAR,
    amount DOUBLE,
    customer STRUCT<firstName VARCHAR,
                    lastName VARCHAR,
                    phoneNumber VARCHAR,
                    address STRUCT<street VARCHAR,
                                   number VARCHAR,
                                   zipcode VARCHAR,
                                   city VARCHAR,
                                   state VARCHAR>>,
    product STRUCT<sku VARCHAR,
                   name VARCHAR,
                   vendor STRUCT<vendorName VARCHAR,
                                 country VARCHAR>>)
    WITH (KAFKA_TOPIC = 'ORDERS',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1);

4
Produce events to the input topic

Before we move foward with the implementation, we need to produce records to the ORDERS stream. Let’s use the console producer to create some records.

docker exec -i broker /usr/bin/kafka-console-producer --broker-list broker:9092 --topic ORDERS

When the console producer starts, it will log some messages and hang, waiting for your input. Type in one line at a time and press enter to send it. Each line represents an order of one 'Highly Durable Glue' bought by each member of Confluent’s developer advocacy team. Note that each order contains the fields customer and product that in turn contains nested data. To send all orders below, click on the clipboard icon on the right, then paste the following into the prompt and press enter:

{"id": "1", "timestamp": "2020-01-18 01:12:05", "amount": 84.02, "customer": {"firstName": "Ricardo", "lastName": "Ferreira", "phoneNumber": "1234567899", "address": {"street": "Street SDF", "number": "8602", "zipcode": "27640", "city": "Raleigh", "state": "NC"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}
{"id": "2", "timestamp": "2020-01-18 01:35:12", "amount": 84.02, "customer": {"firstName": "Tim", "lastName": "Berglund", "phoneNumber": "9987654321", "address": {"street": "Street UOI", "number": "1124", "zipcode": "85756", "city": "Littletown", "state": "CO"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}
{"id": "3", "timestamp": "2020-01-18 01:58:55", "amount": 84.02, "customer": {"firstName": "Robin", "lastName": "Moffatt", "phoneNumber": "4412356789", "address": {"street": "Street YUP", "number": "9066", "zipcode": "BD111NE", "city": "Leeds", "state": "YS"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}
{"id": "4", "timestamp": "2020-01-18 02:31:43", "amount": 84.02, "customer": {"firstName": "Viktor", "lastName": "Gamov", "phoneNumber": "9874563210", "address": {"street": "Street SHT", "number": "12450", "zipcode": "07003", "city": "New Jersey", "state": "NJ"}}, "product": {"sku": "P12345", "name": "Highly Durable Glue", "vendor": {"vendorName": "Acme Corp", "country": "US"}}}

5
Write the program interactively using the CLI

To begin developing interactively, open up the KSQL CLI again:

docker exec -it ksqldb-cli ksql http://ksqldb-server:8088

Now that you have a stream with some events in it, let’s start to leverage them. The first thing to do is set the following properties to ensure that you’re reading from the beginning of the stream:

SET 'auto.offset.reset' = 'earliest';

We need to create a query capable of flattening the records sent to the ORDER stream. Since we modeled each field containing a nested data using a struct, we can write the query using the operator → operator to retrieve the data from specific nested fields.

SELECT
    ID AS ORDER_ID,
    TIMESTAMP AS ORDER_TS,
    AMOUNT AS ORDER_AMOUNT,
    CUSTOMER->FIRSTNAME AS CUST_FIRST_NAME,
    CUSTOMER->LASTNAME AS CUST_LAST_NAME,
    CUSTOMER->PHONENUMBER AS CUST_PHONE_NUMBER,
    CUSTOMER->ADDRESS->STREET AS CUST_ADDR_STREET,
    CUSTOMER->ADDRESS->NUMBER AS CUST_ADDR_NUMBER,
    CUSTOMER->ADDRESS->ZIPCODE AS CUST_ADDR_ZIPCODE,
    CUSTOMER->ADDRESS->CITY AS CUST_ADDR_CITY,
    CUSTOMER->ADDRESS->STATE AS CUST_ADDR_STATE,
    PRODUCT->SKU AS PROD_SKU,
    PRODUCT->NAME AS PROD_NAME,
    PRODUCT->VENDOR->VENDORNAME AS PROD_VENDOR_NAME,
    PRODUCT->VENDOR->COUNTRY AS PROD_VENDOR_COUNTRY
FROM
    ORDERS
EMIT CHANGES
LIMIT 4;

This query should produce the following output:

+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+
|ORDER_ID            |ORDER_TS            |ORDER_AMOUNT        |CUST_FIRST_NAME     |CUST_LAST_NAME      |CUST_PHONE_NUMBER   |CUST_ADDR_STREET    |CUST_ADDR_NUMBER    |CUST_ADDR_ZIPCODE   |CUST_ADDR_CITY      |CUST_ADDR_STATE     |PROD_SKU            |PROD_NAME           |PROD_VENDOR_NAME    |PROD_VENDOR_COUNTRY |
+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+
|1                   |2020-01-18 01:12:05 |84.02               |Ricardo             |Ferreira            |1234567899          |Street SDF          |8602                |27640               |Raleigh             |NC                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
|2                   |2020-01-18 01:35:12 |84.02               |Tim                 |Berglund            |9987654321          |Street UOI          |1124                |85756               |Littletown          |CO                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
|3                   |2020-01-18 01:58:55 |84.02               |Robin               |Moffatt             |4412356789          |Street YUP          |9066                |BD111NE             |Leeds               |YS                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
|4                   |2020-01-18 02:31:43 |84.02               |Viktor              |Gamov               |9874563210          |Street SHT          |12450               |07003               |New Jersey          |NJ                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
Limit Reached
Query terminated

Note that now each field is being shown in a flat structure. This means that our query is working properly. Now let’s create a continuous query to implement this scenario.

CREATE STREAM FLATTENED_ORDERS AS
    SELECT
        ID AS ORDER_ID,
        TIMESTAMP AS ORDER_TS,
        AMOUNT AS ORDER_AMOUNT,
        CUSTOMER->FIRSTNAME AS CUST_FIRST_NAME,
        CUSTOMER->LASTNAME AS CUST_LAST_NAME,
        CUSTOMER->PHONENUMBER AS CUST_PHONE_NUMBER,
        CUSTOMER->ADDRESS->STREET AS CUST_ADDR_STREET,
        CUSTOMER->ADDRESS->NUMBER AS CUST_ADDR_NUMBER,
        CUSTOMER->ADDRESS->ZIPCODE AS CUST_ADDR_ZIPCODE,
        CUSTOMER->ADDRESS->CITY AS CUST_ADDR_CITY,
        CUSTOMER->ADDRESS->STATE AS CUST_ADDR_STATE,
        PRODUCT->SKU AS PROD_SKU,
        PRODUCT->NAME AS PROD_NAME,
        PRODUCT->VENDOR->VENDORNAME AS PROD_VENDOR_NAME,
        PRODUCT->VENDOR->COUNTRY AS PROD_VENDOR_COUNTRY
    FROM
        ORDERS;

We can query the new result stream called FLATTENED_ORDERS with a much simpler query that doesn’t need to handle nested data.

SELECT
    ORDER_ID,
    ORDER_TS,
    ORDER_AMOUNT,
    CUST_FIRST_NAME,
    CUST_LAST_NAME,
    CUST_PHONE_NUMBER,
    CUST_ADDR_STREET,
    CUST_ADDR_NUMBER,
    CUST_ADDR_ZIPCODE,
    CUST_ADDR_CITY,
    CUST_ADDR_STATE,
    PROD_SKU,
    PROD_NAME,
    PROD_VENDOR_NAME,
    PROD_VENDOR_COUNTRY
FROM FLATTENED_ORDERS
EMIT CHANGES
LIMIT 4;

The output should look similar to:

+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+
|ORDER_ID            |ORDER_TS            |ORDER_AMOUNT        |CUST_FIRST_NAME     |CUST_LAST_NAME      |CUST_PHONE_NUMBER   |CUST_ADDR_STREET    |CUST_ADDR_NUMBER    |CUST_ADDR_ZIPCODE   |CUST_ADDR_CITY      |CUST_ADDR_STATE     |PROD_SKU            |PROD_NAME           |PROD_VENDOR_NAME    |PROD_VENDOR_COUNTRY |
+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+
|1                   |2020-01-18 01:12:05 |84.02               |Ricardo             |Ferreira            |1234567899          |Street SDF          |8602                |27640               |Raleigh             |NC                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
|2                   |2020-01-18 01:35:12 |84.02               |Tim                 |Berglund            |9987654321          |Street UOI          |1124                |85756               |Littletown          |CO                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
|3                   |2020-01-18 01:58:55 |84.02               |Robin               |Moffatt             |4412356789          |Street YUP          |9066                |BD111NE             |Leeds               |YS                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
|4                   |2020-01-18 02:31:43 |84.02               |Viktor              |Gamov               |9874563210          |Street SHT          |12450               |07003               |New Jersey          |NJ                  |P12345              |Highly Durable Glue |Acme Corp           |US                  |
Limit Reached
Query terminated

Finally, let’s see what’s available on the underlying Kafka topic for the table. We can print that out easily.

PRINT FLATTENED_ORDERS FROM BEGINNING LIMIT 4;

The output should look similar to:

Key format: JSON or KAFKA_STRING
Value format: JSON or KAFKA_STRING
rowtime: 2020/01/18 01:12:05.000 Z, key: <null>, value: {"ORDER_ID":"1","ORDER_TS":"2020-01-18 01:12:05","ORDER_AMOUNT":84.02,"CUST_FIRST_NAME":"Ricardo","CUST_LAST_NAME":"Ferreira","CUST_PHONE_NUMBER":"1234567899","CUST_ADDR_STREET":"Street SDF","CUST_ADDR_NUMBER":"8602","CUST_ADDR_ZIPCODE":"27640","CUST_ADDR_CITY":"Raleigh","CUST_ADDR_STATE":"NC","PROD_SKU":"P12345","PROD_NAME":"Highly Durable Glue","PROD_VENDOR_NAME":"Acme Corp","PROD_VENDOR_COUNTRY":"US"}
rowtime: 2020/01/18 01:35:12.000 Z, key: <null>, value: {"ORDER_ID":"2","ORDER_TS":"2020-01-18 01:35:12","ORDER_AMOUNT":84.02,"CUST_FIRST_NAME":"Tim","CUST_LAST_NAME":"Berglund","CUST_PHONE_NUMBER":"9987654321","CUST_ADDR_STREET":"Street UOI","CUST_ADDR_NUMBER":"1124","CUST_ADDR_ZIPCODE":"85756","CUST_ADDR_CITY":"Littletown","CUST_ADDR_STATE":"CO","PROD_SKU":"P12345","PROD_NAME":"Highly Durable Glue","PROD_VENDOR_NAME":"Acme Corp","PROD_VENDOR_COUNTRY":"US"}
rowtime: 2020/01/18 01:58:55.000 Z, key: <null>, value: {"ORDER_ID":"3","ORDER_TS":"2020-01-18 01:58:55","ORDER_AMOUNT":84.02,"CUST_FIRST_NAME":"Robin","CUST_LAST_NAME":"Moffatt","CUST_PHONE_NUMBER":"4412356789","CUST_ADDR_STREET":"Street YUP","CUST_ADDR_NUMBER":"9066","CUST_ADDR_ZIPCODE":"BD111NE","CUST_ADDR_CITY":"Leeds","CUST_ADDR_STATE":"YS","PROD_SKU":"P12345","PROD_NAME":"Highly Durable Glue","PROD_VENDOR_NAME":"Acme Corp","PROD_VENDOR_COUNTRY":"US"}
rowtime: 2020/01/18 02:31:43.000 Z, key: <null>, value: {"ORDER_ID":"4","ORDER_TS":"2020-01-18 02:31:43","ORDER_AMOUNT":84.02,"CUST_FIRST_NAME":"Viktor","CUST_LAST_NAME":"Gamov","CUST_PHONE_NUMBER":"9874563210","CUST_ADDR_STREET":"Street SHT","CUST_ADDR_NUMBER":"12450","CUST_ADDR_ZIPCODE":"07003","CUST_ADDR_CITY":"New Jersey","CUST_ADDR_STATE":"NJ","PROD_SKU":"P12345","PROD_NAME":"Highly Durable Glue","PROD_VENDOR_NAME":"Acme Corp","PROD_VENDOR_COUNTRY":"US"}
Topic printing ceased

6
Write your statements to a file

Now that you have a series of statements that’s doing the right thing, the last step is to put them into a file so that they can be used outside the CLI session. Create a file at src/statements.sql with the following content:

CREATE STREAM ORDERS (
    id VARCHAR,
    timestamp VARCHAR,
    amount DOUBLE,
    customer STRUCT<firstName VARCHAR,
                    lastName VARCHAR,
                    phoneNumber VARCHAR,
                    address STRUCT<street VARCHAR,
                                   number VARCHAR,
                                   zipcode VARCHAR,
                                   city VARCHAR,
                                   state VARCHAR>>,
    product STRUCT<sku VARCHAR,
                   name VARCHAR,
                   vendor STRUCT<vendorName VARCHAR,
                                 country VARCHAR>>)
    WITH (KAFKA_TOPIC = 'ORDERS',
          VALUE_FORMAT = 'JSON',
          TIMESTAMP = 'TIMESTAMP',
          TIMESTAMP_FORMAT = 'yyyy-MM-dd HH:mm:ss',
          PARTITIONS = 1);

CREATE STREAM FLATTENED_ORDERS AS
    SELECT
        ID AS ORDER_ID,
        TIMESTAMP AS ORDER_TS,
        AMOUNT AS ORDER_AMOUNT,
        CUSTOMER->FIRSTNAME AS CUST_FIRST_NAME,
        CUSTOMER->LASTNAME AS CUST_LAST_NAME,
        CUSTOMER->PHONENUMBER AS CUST_PHONE_NUMBER,
        CUSTOMER->ADDRESS->STREET AS CUST_ADDR_STREET,
        CUSTOMER->ADDRESS->NUMBER AS CUST_ADDR_NUMBER,
        CUSTOMER->ADDRESS->ZIPCODE AS CUST_ADDR_ZIPCODE,
        CUSTOMER->ADDRESS->CITY AS CUST_ADDR_CITY,
        CUSTOMER->ADDRESS->STATE AS CUST_ADDR_STATE,
        PRODUCT->SKU AS PROD_SKU,
        PRODUCT->NAME AS PROD_NAME,
        PRODUCT->VENDOR->VENDORNAME AS PROD_VENDOR_NAME,
        PRODUCT->VENDOR->COUNTRY AS PROD_VENDOR_COUNTRY
    FROM
        ORDERS;

Test it
1
Create the test data

Create a file at test/input.json with the inputs for testing:

{
  "inputs": [
    {
      "topic": "ORDERS",
      "value": {
        "id": "1",
        "timestamp": "2020-01-18 01:12:05",
        "amount": 84.02,
        "customer": {
          "firstName": "Ricardo",
          "lastName": "Ferreira",
          "phoneNumber": "1234567899",
          "address": {
            "street": "Street SDF",
            "number": "8602",
            "zipcode": "27640",
            "city": "Raleigh",
            "state": "NC"
          }
        },
        "product": {
          "sku": "P12345",
          "name": "Highly Durable Glue",
          "vendor": {
            "vendorName": "Acme Corp",
            "country": "US"
          }
        }
      }
    },
    {
      "topic": "ORDERS",
      "value": {
        "id": "2",
        "timestamp": "2020-01-18 01:35:12",
        "amount": 84.02,
        "customer": {
          "firstName": "Tim",
          "lastName": "Berglund",
          "phoneNumber": "9987654321",
          "address": {
            "street": "Street UOI",
            "number": "1124",
            "zipcode": "85756",
            "city": "Littletown",
            "state": "CO"
          }
        },
        "product": {
          "sku": "P12345",
          "name": "Highly Durable Glue",
          "vendor": {
            "vendorName": "Acme Corp",
            "country": "US"
          }
        }
      }
    },
    {
      "topic": "ORDERS",
      "value": {
        "id": "3",
        "timestamp": "2020-01-18 01:58:55",
        "amount": 84.02,
        "customer": {
          "firstName": "Robin",
          "lastName": "Moffatt",
          "phoneNumber": "4412356789",
          "address": {
            "street": "Street YUP",
            "number": "9066",
            "zipcode": "BD111NE",
            "city": "Leeds",
            "state": "YS"
          }
        },
        "product": {
          "sku": "P12345",
          "name": "Highly Durable Glue",
          "vendor": {
            "vendorName": "Acme Corp",
            "country": "US"
          }
        }
      }
    },
    {
      "topic": "ORDERS",
      "value": {
        "id": "4",
        "timestamp": "2020-01-18 02:31:43",
        "amount": 84.02,
        "customer": {
          "firstName": "Viktor",
          "lastName": "Gamov",
          "phoneNumber": "9874563210",
          "address": {
            "street": "Street SHT",
            "number": "12450",
            "zipcode": "07003",
            "city": "New Jersey",
            "state": "NJ"
          }
        },
        "product": {
          "sku": "P12345",
          "name": "Highly Durable Glue",
          "vendor": {
            "vendorName": "Acme Corp",
            "country": "US"
          }
        }
      }
    }
  ]
}

Similarly, create a file at test/output.json with the expected outputs.

{
  "outputs": [
    {
      "topic": "FLATTENED_ORDERS",
      "value": {
        "ORDER_ID": "1",
        "ORDER_TS": "2020-01-18 01:12:05",
        "ORDER_AMOUNT": 84.02,
        "CUST_FIRST_NAME": "Ricardo",
        "CUST_LAST_NAME": "Ferreira",
        "CUST_PHONE_NUMBER": "1234567899",
        "CUST_ADDR_STREET": "Street SDF",
        "CUST_ADDR_NUMBER": "8602",
        "CUST_ADDR_ZIPCODE": "27640",
        "CUST_ADDR_CITY": "Raleigh",
        "CUST_ADDR_STATE": "NC",
        "PROD_SKU": "P12345",
        "PROD_NAME": "Highly Durable Glue",
        "PROD_VENDOR_NAME": "Acme Corp",
        "PROD_VENDOR_COUNTRY": "US"
      },
      "timestamp": 1579309925000
    },
    {
      "topic": "FLATTENED_ORDERS",
      "value": {
        "ORDER_ID": "2",
        "ORDER_TS": "2020-01-18 01:35:12",
        "ORDER_AMOUNT": 84.02,
        "CUST_FIRST_NAME": "Tim",
        "CUST_LAST_NAME": "Berglund",
        "CUST_PHONE_NUMBER": "9987654321",
        "CUST_ADDR_STREET": "Street UOI",
        "CUST_ADDR_NUMBER": "1124",
        "CUST_ADDR_ZIPCODE": "85756",
        "CUST_ADDR_CITY": "Littletown",
        "CUST_ADDR_STATE": "CO",
        "PROD_SKU": "P12345",
        "PROD_NAME": "Highly Durable Glue",
        "PROD_VENDOR_NAME": "Acme Corp",
        "PROD_VENDOR_COUNTRY": "US"
      },
      "timestamp": 1579311312000
    },
    {
      "topic": "FLATTENED_ORDERS",
      "value": {
        "ORDER_ID": "3",
        "ORDER_TS": "2020-01-18 01:58:55",
        "ORDER_AMOUNT": 84.02,
        "CUST_FIRST_NAME": "Robin",
        "CUST_LAST_NAME": "Moffatt",
        "CUST_PHONE_NUMBER": "4412356789",
        "CUST_ADDR_STREET": "Street YUP",
        "CUST_ADDR_NUMBER": "9066",
        "CUST_ADDR_ZIPCODE": "BD111NE",
        "CUST_ADDR_CITY": "Leeds",
        "CUST_ADDR_STATE": "YS",
        "PROD_SKU": "P12345",
        "PROD_NAME": "Highly Durable Glue",
        "PROD_VENDOR_NAME": "Acme Corp",
        "PROD_VENDOR_COUNTRY": "US"
      },
      "timestamp": 1579312735000
    },
    {
      "topic": "FLATTENED_ORDERS",
      "value": {
        "ORDER_ID": "4",
        "ORDER_TS": "2020-01-18 02:31:43",
        "ORDER_AMOUNT": 84.02,
        "CUST_FIRST_NAME": "Viktor",
        "CUST_LAST_NAME": "Gamov",
        "CUST_PHONE_NUMBER": "9874563210",
        "CUST_ADDR_STREET": "Street SHT",
        "CUST_ADDR_NUMBER": "12450",
        "CUST_ADDR_ZIPCODE": "07003",
        "CUST_ADDR_CITY": "New Jersey",
        "CUST_ADDR_STATE": "NJ",
        "PROD_SKU": "P12345",
        "PROD_NAME": "Highly Durable Glue",
        "PROD_VENDOR_NAME": "Acme Corp",
        "PROD_VENDOR_COUNTRY": "US"
      },
      "timestamp": 1579314703000
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