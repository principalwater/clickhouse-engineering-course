# Задание со звездочкой: Система репликации логов
# Секции конфигурации и команды CREATE TABLE

## 1. Engine=Null таблица для приема логов

```sql
CREATE TABLE otus_monitoring.logs_input\n(\n    `timestamp` DateTime64(3),\n    `level` Enum8(\'ERROR\' = 1, \'WARNING\' = 2, \'INFORMATION\' = 3, \'DEBUG\' = 4),\n    `logger_name` String,\n    `message` String,\n    `thread_id` UInt64,\n    `query_id` String,\n    `replica_name` String DEFAULT hostName()\n)\nENGINE = Null
```

## 2. Реплицируемая таблица для хранения логов

```sql
CREATE TABLE otus_monitoring.logs_storage\n(\n    `timestamp` DateTime64(3),\n    `level` Enum8(\'ERROR\' = 1, \'WARNING\' = 2, \'INFORMATION\' = 3, \'DEBUG\' = 4),\n    `logger_name` String,\n    `message` String,\n    `thread_id` UInt64,\n    `query_id` String,\n    `replica_name` String,\n    `replica_shard` UInt8 DEFAULT 1,\n    `replica_num` UInt8 DEFAULT 1,\n    `ingestion_time` DateTime DEFAULT now()\n)\nENGINE = ReplicatedMergeTree(\'/clickhouse/tables/{shard}/logs_storage/{uuid}\', \'{replica}\')\nPARTITION BY toYYYYMM(timestamp)\nORDER BY (timestamp, level, logger_name)\nTTL toDateTime(timestamp) + toIntervalDay(7)\nSETTINGS index_granularity = 8192
```

## 3. Материализованное представление (MV)

```sql
CREATE MATERIALIZED VIEW otus_monitoring.logs_mv TO otus_monitoring.logs_storage\n(\n    `timestamp` DateTime64(3),\n    `level` Enum8(\'ERROR\' = 1, \'WARNING\' = 2, \'INFORMATION\' = 3, \'DEBUG\' = 4),\n    `logger_name` String,\n    `message` String,\n    `thread_id` UInt64,\n    `query_id` String,\n    `replica_name` String,\n    `replica_shard` UInt8,\n    `replica_num` UInt8,\n    `ingestion_time` DateTime\n)\nAS SELECT\n    timestamp,\n    level,\n    logger_name,\n    message,\n    thread_id,\n    query_id,\n    replica_name,\n    toUInt8(getMacro(\'shard\')) AS replica_shard,\n    toUInt8(getMacro(\'replica\')) AS replica_num,\n    now() AS ingestion_time\nFROM otus_monitoring.logs_input
```

## 4. Distributed таблица

```sql
CREATE TABLE otus_monitoring.logs_distributed\n(\n    `timestamp` DateTime64(3),\n    `level` Enum8(\'ERROR\' = 1, \'WARNING\' = 2, \'INFORMATION\' = 3, \'DEBUG\' = 4),\n    `logger_name` String,\n    `message` String,\n    `thread_id` UInt64,\n    `query_id` String,\n    `replica_name` String,\n    `replica_shard` UInt8 DEFAULT 1,\n    `replica_num` UInt8 DEFAULT 1,\n    `ingestion_time` DateTime DEFAULT now()\n)\nENGINE = Distributed(\'dwh_test\', \'otus_monitoring\', \'logs_storage\', rand())
```

## 5. Конфигурация кластера (XML секции из clickhouse-01)

### remote_servers секция:
```xml
<remote_servers>
  <dwh_test>
    <shard>
          <replica>
        <host>clickhouse-01</host>
        <port>9000</port>
        <user>MASKED_USER</user>
        <password>MASKED_PASSWORD</password>
      </replica>
          <replica>
        <host>clickhouse-03</host>
        <port>9000</port>
        <user>MASKED_USER</user>
        <password>MASKED_PASSWORD</password>
      </replica>
          <replica>
        <host>clickhouse-05</host>
        <port>9000</port>
        <user>MASKED_USER</user>
        <password>MASKED_PASSWORD</password>
      </replica>
        </shard>
    <shard>
          <replica>
        <host>clickhouse-02</host>
        <port>9000</port>
        <user>MASKED_USER</user>
        <password>MASKED_PASSWORD</password>
      </replica>
          <replica>
        <host>clickhouse-04</host>
        <port>9000</port>
        <user>MASKED_USER</user>
        <password>MASKED_PASSWORD</password>
      </replica>
          <replica>
        <host>clickhouse-06</host>
        <port>9000</port>
        <user>MASKED_USER</user>
        <password>MASKED_PASSWORD</password>
      </replica>
        </shard>
  </dwh_test>
</remote_servers>
```

### macros секция:
```xml
    <macros>
        <shard>01</shard>
        <replica>01</replica>
    </macros>
```

### keeper секция:
```xml
    <zookeeper>        <node>
            <host>clickhouse-keeper-01</host>
            <port>9181</port>
        </node>        <node>
            <host>clickhouse-keeper-02</host>
            <port>9181</port>
        </node>        <node>
            <host>clickhouse-keeper-03</host>
            <port>9181</port>
        </node>    </zookeeper>
```

## 6. Результат проверки репликации

```
9e05cff35eff	1	1	100
```
