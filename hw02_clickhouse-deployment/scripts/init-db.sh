#!/bin/bash
set -e

ENV_FILE="$(dirname "$0")/../env/clickhouse.env"

# !!! Укажи имя основного контейнера ClickHouse !!!
CH_CONTAINER="clickhouse-01"

# Загрузка переменных
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
  rm -f "$ENV_FILE"   # Удаляем файл сразу после загрузки переменных
fi

if [ -z "$CH_PASSWORD" ]; then
  echo "Введите plain пароль для пользователя $CH_USER:"
  read -rs CH_PASSWORD
  echo
fi
if [ -z "$BI_PASSWORD" ]; then
  echo "Введите plain пароль для пользователя $BI_USER:"
  read -rs BI_PASSWORD
  echo
fi

MAX_ATTEMPTS=30
ATTEMPT=0
until docker exec -i "$CH_CONTAINER" clickhouse-client --user "$CH_USER" --password "$CH_PASSWORD" --query "SELECT 1"; do
  ATTEMPT=$((ATTEMPT+1))
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "ClickHouse не стартовал за $((MAX_ATTEMPTS*5)) секунд, abort"
    exit 1
  fi
  echo "Ожидание запуска ClickHouse... (попытка $ATTEMPT/$MAX_ATTEMPTS)"
  sleep 5
done

# Создание БД
docker exec -i "$CH_CONTAINER" clickhouse-client --user "$CH_USER" --password "$CH_PASSWORD" --query "
CREATE DATABASE IF NOT EXISTS nyc_taxi ON CLUSTER dwh_test;
"

# Создание реплицируемой local-таблицы
docker exec -i "$CH_CONTAINER" clickhouse-client --user "$CH_USER" --password "$CH_PASSWORD" --query "
CREATE TABLE IF NOT EXISTS nyc_taxi.trips_small_local ON CLUSTER dwh_test
(
    trip_id             UInt32,
    pickup_datetime     DateTime,
    dropoff_datetime    DateTime,
    pickup_longitude    Nullable(Float64),
    pickup_latitude     Nullable(Float64),
    dropoff_longitude   Nullable(Float64),
    dropoff_latitude    Nullable(Float64),
    passenger_count     UInt8,
    trip_distance       Float32,
    fare_amount         Float32,
    extra               Float32,
    tip_amount          Float32,
    tolls_amount        Float32,
    total_amount        Float32,
    payment_type        Enum('CSH' = 1, 'CRE' = 2, 'NOC' = 3, 'DIS' = 4, 'UNK' = 5),
    pickup_ntaname      LowCardinality(String),
    dropoff_ntaname     LowCardinality(String)
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/trips_small', '{replica}')
PRIMARY KEY (pickup_datetime, dropoff_datetime);
"

# Создание Distributed-таблицы
docker exec -i "$CH_CONTAINER" clickhouse-client --user "$CH_USER" --password "$CH_PASSWORD" --query "
CREATE TABLE IF NOT EXISTS nyc_taxi.trips_small ON CLUSTER dwh_test
AS nyc_taxi.trips_small_local
ENGINE = Distributed(dwh_test, nyc_taxi, trips_small_local, intHash64(toYYYYMM(pickup_datetime)));
"

# Загрузка данных
docker exec -i "$CH_CONTAINER" clickhouse-client --user "$CH_USER" --password "$CH_PASSWORD" --query "
INSERT INTO nyc_taxi.trips_small
SELECT
    trip_id,
    pickup_datetime,
    dropoff_datetime,
    pickup_longitude,
    pickup_latitude,
    dropoff_longitude,
    dropoff_latitude,
    passenger_count,
    trip_distance,
    fare_amount,
    extra,
    tip_amount,
    tolls_amount,
    total_amount,
    payment_type,
    pickup_ntaname,
    dropoff_ntaname
FROM s3(
    'https://datasets-documentation.s3.eu-west-3.amazonaws.com/nyc-taxi/trips_{0..2}.gz',
    'TabSeparatedWithNames'
);
"

# Проверка
docker exec -i "$CH_CONTAINER" clickhouse-client --user "$CH_USER" --password "$CH_PASSWORD" --query "
SELECT count() FROM nyc_taxi.trips_small WHERE payment_type = 1;
"