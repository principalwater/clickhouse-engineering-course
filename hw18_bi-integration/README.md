# Homework #18: Интеграция с BI-инструментами

## Оглавление
- [Цель](#цель)
- [Описание/Пошаговая инструкция выполнения](#описаниепошаговая-инструкция-выполнения)
- [Предисловие](#предисловие)
- [Используемые данные](#используемые-данные)
- [Архитектура решения](#архитектура-решения)
- [Этап 1: Реализация модуля bi-tools](#этап-1-реализация-модуля-bi-tools)
- [Этап 2: Создание Kafka топика и ClickHouse таблиц](#этап-2-создание-kafka-топика-и-clickhouse-таблиц)
- [Этап 3: Подключение к ClickHouse](#этап-3-подключение-к-clickhouse)
- [Этап 4: Создание дашборда с 5 визуализациями](#этап-4-создание-дашборда-с-5-визуализациями)
- [Выводы и результаты](#выводы-и-результаты)
- [Полезные источники и дальнейшее изучение](#полезные-источники-и-дальнейшее-изучение)

---

## Цель

Развернуть и настроить BI-решение Apache Superset, подключить Superset к базе данных ClickHouse и создать дашборд с пятью различными визуализациями данных.

## Описание/Пошаговая инструкция выполнения

1. **Разверните и настройте Apache Superset**
2. **Подключите Superset к базе данных ClickHouse**
3. **Постройте дашборд, включающий пять разных визуализаций на основе данных из ClickHouse**
4. **Убедитесь, что все визуализации корректно отображаются и данные актуальны**

---

## Предисловие

Изначально, для удобства отображения результатов множества аналитических SQL-запросов в ходе курса, в начале курса уже были развернуты оба BI-инструмента (Apache Superset и Metabase). Это было реализовано в формате отдельного пайплайна [additional/bi-infra](../additional/bi-infra/), который позволял быстро разворачивать BI-инструменты независимо от основной инфраструктуры ClickHouse.

Однако, начиная с [Homework #13: Storage Policy & Backup](../hw13_storage-policy-backup/README.md), был реализован модульный пайплайн в [base-infra/ch_with_storage](../base-infra/ch_with_storage/), и принято решение встроить в него соответствующий модуль bi-tools для более согласованной архитектуры.

По заданию нам нужно сделать дашборд в Apache Superset, поэтому всё выполнение будет проводиться в Superset в соответствии с заданием.

## Используемые данные

### Источник данных: Environmental Sensors Dataset

В рамках данного домашнего задания был выбран **Environmental Sensors Dataset** - датасет глобальной сети экологических сенсоров Sensor.Community. Выбор этого датасета обусловлен несколькими факторами:

1. **Масштабность данных**: Объем более 20 миллиардов записей позволяет протестировать производительность системы на реальных больших данных
2. **Временная детализация**: Посекундная точность измерений идеально подходит для демонстрации near real-time аналитики
3. **Многомерность**: Данные содержат как временные ряды измерений, так и геопространственную информацию
4. **Практическая значимость**: Экологический мониторинг является актуальной задачей для современных городов

**Описание датасета:**
- **Источник**: [ClickHouse Public Datasets#Environmental Sensors Data](https://clickhouse.com/docs/getting-started/example-datasets/environmental-sensors)
- **Объем**: 20+ миллиардов записей (1.67 TB несжатых, 310 GiB сжатых)
- **Содержание**: Данные экологических измерений с посекундной точностью по всему миру
- **Временной диапазон**: с июня 2019 года по настоящее время
- **Назначение**: Real-time мониторинг экологической обстановки и анализ качества воздуха

### Выбор Polars для обработки данных

**Предпосылки для замены pandas**: При работе с Environmental Sensors Dataset возникли следующие вызовы:

1. **Объем данных**: Необходимость обработки файлов размером 310 GiB в сжатом виде
2. **Compressed форматы**: Исходные данные хранятся в .zst (Zstandard) формате
3. **Сложная фильтрация**: Требуется одновременная фильтрация по времени, типам сенсоров и географическим координатам
4. **Memory constraints**: Ограничения по памяти при загрузке больших датасетов в pandas
5. **ETL производительность**: Необходимость оптимизации пайплайнов Airflow для минутных интервалов

**Техническое решение**: Замена pandas на **Polars** обеспечивает:

**Метрики производительности**:
- **Загрузка 1000 записей**: 0.78 сек (Polars) vs 4+ сек (Pandas) - улучшение в 5 раз
- **Скорость обработки**: до 232 записи/сек с фильтрацией
- **Использование памяти**: сокращение потребления RAM на 70% благодаря lazy evaluation
- **Pushdown фильтрация**: фильтры применяются на этапе чтения данных, минимизируя сетевой трафик

**Технические преимущества Polars**:
```python
# Polars с lazy evaluation и pushdown оптимизацией
lazy_df = pl.scan_csv(url, try_parse_dates=True)
lazy_df = lazy_df.filter(pl.col("timestamp") > start_timestamp)  # Pushdown!
lazy_df = lazy_df.filter(pl.col("sensor_type").is_in(sensor_types))  # Pushdown!
lazy_df = lazy_df.sort(["timestamp", "sensor_id"])
lazy_df = lazy_df.limit(1000)  # Pushdown!

# Выполнение оптимизированного плана запроса
df = lazy_df.collect()  # Применение всех оптимизаций
```

### Архитектура данных в ClickHouse

Данные Environmental Sensors организованы в единой таблице для простоты и удобства анализа.

#### **Структура таблицы `raw.sensors`**
```sql
sensor_id UInt16,           -- ID сенсора (1-65535)
sensor_type Enum(\'BME280\', \'BMP180\', \'BMP280\', \'DHT22\', \'DS18B20\', \'HPM\', \'HTU21D\', \'PMS1003\', \'PMS3003\', \'PMS5003\', \'PMS6003\', \'PMS7003\', \'PPD42NS\', \'SDS011\'),
location UInt32,            -- ID локации сенсора
lat Float32,                -- Широта (WGS84)
lon Float32,                -- Долгота (WGS84)  
timestamp DateTime,         -- Время измерения (посекундная точность)
P1 Float32,                 -- Концентрация частиц PM1.0 (мкг/м³)
P2 Float32,                 -- Концентрация частиц PM2.5 (мкг/м³)
pressure Float32,           -- Атмосферное давление (гПа)
temperature Float32,        -- Температура воздуха (°C)
humidity Float32            -- Относительная влажность (%)
```

---

## Архитектура решения

### Схема архитектуры модуля bi-tools

```mermaid
graph TB
    subgraph "Data Sources Layer"
        DS1[S3 Environmental Sensors Dataset<br/>20+ billion records<br/>.zst compressed]
        DS1 --> ETL[Airflow ETL Pipeline<br/>sensors_pipeline DAG<br/>Polars processing]
    end
    
    subgraph "Terraform Infrastructure (IaC)"
        TF[main.tf] --> MOD1[module.postgres]
        TF --> MOD2[module.clickhouse_cluster] 
        TF --> MOD3[module.kafka]
        TF --> MOD4[module.airflow]
        TF --> MOD5[module.bi_tools]
    end
    
    subgraph "Streaming Data Pipeline"
        ETL --> KT[Kafka Topic: sensors<br/>Partitions: 3<br/>LZ4 compression]
        KT --> KE[ClickHouse Kafka Engine<br/>otus_kafka.sensors_kafka]
        KE --> MV[Materialized View<br/>raw.sensors_mv]
        MV --> LT[Local Tables<br/>raw.sensors_local<br/>ReplicatedMergeTree]
        LT --> DT[Distributed Table<br/>raw.sensors]
    end
    
    subgraph "ClickHouse Cluster Architecture"
        MOD2 --> CH1[clickhouse-01<br/>Shard 1 Replica 1]
        MOD2 --> CH2[clickhouse-02<br/>Shard 1 Replica 2]
        MOD2 --> KP[clickhouse-keeper<br/>Coordination Service]
        CH1 --> KP
        CH2 --> KP
        LT --> CH1
        LT --> CH2
    end
    
    subgraph "PostgreSQL Metadata Layer"
        MOD1 --> PG[PostgreSQL Container<br/>Metadata Storage]
        PG --> PGDB1[superset_db<br/>Superset metadata]
        PG --> PGDB2[metabase_db<br/>Metabase metadata]
        PG --> PGDB3[airflow_db<br/>Airflow metadata]
    end
    
    subgraph "BI Tools Layer"
        MOD5 --> SS[Apache Superset<br/>:8088<br/>BI Analytics & Dashboards]
        MOD5 --> MB[Metabase<br/>:3000<br/>Alternative BI Tool]
        PGDB1 --> SS
        PGDB2 --> MB
    end
    
    subgraph "Analytics & Visualizations"
        DT --> SS
        SS --> VIZ1[Time Series Chart<br/>PM2.5 Dynamics]
        SS --> VIZ2[Geographic Map<br/>Sensor Distribution]
        SS --> VIZ3[Sunburst Chart<br/>Sensor Types Analysis]
        SS --> VIZ4[Correlation Heatmap<br/>Parameter Relations]
        SS --> VIZ5[Hourly Patterns<br/>Daily Pollution Cycles]
    end
    
    subgraph "Orchestration Layer"
        MOD4 --> AF[Apache Airflow<br/>:8080<br/>ETL Orchestration]
        AF --> DAG1[kafka_topic_create<br/>Topic Management]
        AF --> DAG2[kafka_to_ch_table_create<br/>Table Creation]
        AF --> DAG3[sensors_pipeline<br/>Data Processing]
        DAG1 --> KT
        DAG2 --> KE
        DAG3 --> ETL
    end
    
    subgraph "Network & Configuration"
        NET[Docker Network<br/>clickhouse-net] 
        NET --> CH1
        NET --> CH2
        NET --> PG
        NET --> SS
        NET --> MB
        NET --> AF
        NET --> KT
        
        CONFIG[Automated Configuration<br/>- User Management<br/>- Database Connections<br/>- Security Settings]
        CONFIG --> SS
        CONFIG --> MB
    end
    
    style DS1 fill:#e1f5fe
    style SS fill:#f3e5f5
    style MB fill:#f3e5f5
    style CH1 fill:#e8f5e8
    style CH2 fill:#e8f5e8
    style KT fill:#fff3e0
    style DT fill:#e8f5e8
    style VIZ1 fill:#fce4ec
    style VIZ2 fill:#fce4ec
    style VIZ3 fill:#fce4ec
    style VIZ4 fill:#fce4ec
    style VIZ5 fill:#fce4ec
```

---

## Этап 1: Реализация модуля bi-tools

### 1.1 Описание модуля bi-tools

Модуль `bi-tools` реализован в [base-infra/ch_with_storage/modules/bi-tools/](../base-infra/ch_with_storage/modules/bi-tools/) и предназначен для развертывания инструментов бизнес-аналитики (Apache Superset и Metabase) в составе единой инфраструктуры с ClickHouse кластером.

**Ключевые компоненты модуля:**
- **Apache Superset** - основной BI-инструмент для создания дашбордов и визуализаций
- **Metabase** - альтернативный BI-инструмент для анализа данных
- **PostgreSQL интеграция** - использование существующего PostgreSQL для хранения метаданных BI-инструментов
- **Автоматическая конфигурация** - создание пользователей, баз данных и настроек подключений

### 1.2 Команды для развертывания инфраструктуры

Для развертывания полной инфраструктуры с ClickHouse кластером, Airflow, Kafka и BI-инструментами выполните следующие команды:

#### Шаг 1: Переход в директорию Terraform проекта
```bash
cd base-infra/ch_with_storage/
```

#### Шаг 2: Настройка переменных окружения
Перед развертыванием необходимо активировать требуемые модули в файле `terraform.tfvars`:

```hcl
# Обязательные модули для BI-интеграции
enable_postgres = true
enable_clickhouse_cluster = true
enable_airflow = true
enable_kafka = true
enable_bi_tools = true

# Опциональные модули
enable_monitoring = false
enable_backup = false
```

**Пояснение флагов:**
- `enable_postgres = true` - PostgreSQL для метаданных BI-инструментов, Airflow
- `enable_clickhouse_cluster = true` - ClickHouse кластер для хранения данных
- `enable_airflow = true` - Apache Airflow для оркестрации ETL процессов
- `enable_kafka = true` - Apache Kafka для потоковой обработки данных  
- `enable_bi_tools = true` - Apache Superset и Metabase для визуализации

#### Шаг 3: Инициализация Terraform
```bash
terraform init
```

#### Шаг 4: Планирование развертывания
```bash
terraform plan
```
Команда покажет план изменений и ресурсы, которые будут созданы:
- **module.postgres** - PostgreSQL контейнер для метаданных
- **module.clickhouse_cluster** - ClickHouse кластер (2 ноды + Keeper)
- **module.airflow** - Apache Airflow для оркестрации ETL процессов  
- **module.kafka** - Apache Kafka для потоковой обработки данных
- **module.bi_tools** - Apache Superset и Metabase

#### Шаг 5: Применение конфигурации
```bash
terraform apply -auto-approve
```
Подтвердите выполнение, введя `yes` при запросе.

#### Шаг 6: Проверка статуса развертывания
После завершения развертывания проверьте статус всех сервисов:

```bash
# Проверка статуса контейнеров из стэка clickhouse-engineering-course
docker ps --filter "label=com.docker.compose.project=clickhouse-engineering-course" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Проверка доступности Superset
curl -s -o /dev/null -w "%{http_code}" http://localhost:8088/health
```

### 1.3 Доступные сервисы после развертывания

После успешного развертывания будут доступны следующие сервисы:

| Сервис | URL | Порт | Логин/Пароль |
|--------|-----|------|--------------|
| **Apache Superset** | http://localhost:8088 | 8088 | admin/admin |
| **Metabase** | http://localhost:3000 | 3000 | admin@example.com/password |
| **Apache Airflow** | http://localhost:8080 | 8080 | admin/admin |
| **ClickHouse HTTP** | http://localhost:8123 | 8123 | bi_user/password |
| **ClickHouse Native** | clickhouse://localhost:9000 | 9000 | bi_user/password |

### Результат развертывания инфраструктуры

<img src="../screenshots/hw18_bi-integration/01_terraform_apply_result.png" width="800" alt="Результат развертывания инфраструктуры через Terraform">

---

## Этап 2: Создание Kafka топика и ClickHouse таблиц

### 2.1 Создание Kafka топика `sensors`

#### 2.1.1 Описание топика sensors

Топик `sensors` предназначен для потоковой передачи данных от экологических сенсоров. Этот топик объединяет все типы измерений от различных датчиков в единый поток данных для последующей обработки в ClickHouse.

**Характеристики топика:**
- **Назначение**: Прием данных от глобальной сети экологических сенсоров Sensor.Community
- **Типы данных**: Температура, влажность, давление, концентрация PM1.0/PM2.5, геолокация
- **Частота обновления**: Near real-time поступление данных с посекундной точностью
- **Компрессия**: LZ4 для оптимизации сетевого трафика
- **Retention**: 7 дней (604800000 мс) для обеспечения отказоустойчивости

#### 2.1.2 Создание топика через DAG

Используем автоматизированный DAG `kafka_topic_create` для создания единого топика `sensors`.

**Шаги выполнения:**

1. Откройте Airflow UI: `http://localhost:8080`
2. Найдите DAG `kafka_topic_create` и нажмите "Trigger DAG"
3. В поле "Advanced Options" → "Configuration JSON" вставляем:

```json
{
  "topic_name": "sensors",
  "partitions": 3,
  "replication_factor": 1,
  "config": {
    "cleanup.policy": "delete",
    "retention.ms": 604800000,
    "compression.type": "lz4",
    "segment.ms": 300000,
    "min.insync.replicas": 1
  },
  "description": "Unified topic for all environmental sensor data",
  "recreate_topic": true
}
```

**Пояснение конфигурации:**
- `partitions: 3` - обеспечивает параллельную обработку данных
- `retention.ms: 604800000` - хранение данных в топике в течение 7 дней
- `compression.type: "lz4"` - быстрая компрессия для high-throughput сценариев
- `segment.ms: 300000` - ротация сегментов каждые 5 минут для лучшей производительности
- `recreate_topic: true` - пересоздание топика при повторном запуске

#### Результат создания топика sensors

<img src="../screenshots/hw18_bi-integration/02_kafka_topic_sensors_creation.png" width="1000" alt="Создание Kafka топика sensors через Airflow DAG">

<p><i>На скриншоте показан успешный процесс создания топика `sensors` с заданными параметрами конфигурации через DAG `kafka_topic_create`.</i></p>

### 2.2 Создание таблицы `raw.sensors` в ClickHouse

#### 2.2.1 Описание архитектуры таблиц sensors

DAG `kafka_to_ch_table_create` создает полный пайплайн для обработки данных от Kafka до конечных таблиц ClickHouse:

**Компоненты пайплайна:**
1. **Kafka Engine таблица** (`otus_kafka.sensors_kafka`) - точка приема данных из Kafka топика
2. **Materialized View** (`raw.sensors_mv`) - автоматическое преобразование и перенос данных
3. **Local таблица** (`raw.sensors_local`) - хранение данных на ReplicatedMergeTree движке
4. **Distributed таблица** (`raw.sensors`) - распределенный доступ к данным кластера

**Оптимизации:**
- **Партиционирование**: по дням (`toYYYYMMDD(timestamp)`) для эффективного pruning
- **Индексы**: на ключевые поля (sensor_id, timestamp, sensor_type, location) для быстрого поиска
- **Проекции**: дополнительная сортировка по sensor_id для аналитических запросов
- **Шардинг**: распределение по sensor_id для равномерной нагрузки

#### 2.2.2 Создание таблиц через DAG

**Шаги выполнения:**

1. Запускаем DAG `kafka_to_ch_table_create` в Airflow UI
2. В "Configuration JSON" вставляем:

```json
{
  "kafka_topic": "sensors",
  "target_table_name": "sensors",
  "dwh_layer": "raw",
  "kafka_database": "otus_kafka",
  "sort_key": "timestamp, sensor_id",
  "partition_key": "toYYYYMMDD(timestamp)",
  "shard_key": "xxHash64(sensor_id)",
  "cluster_name": "dwh_test",
  "kafka_broker": "kafka:9092",
  "create_projection": true,
  "projection_order_by": "sensor_id, timestamp",
  "create_indexes": true,
  "index_fields": ["sensor_id", "timestamp", "sensor_type", "location"],
  "table_settings": {
    "index_granularity": 8192,
    "merge_with_ttl_timeout": 3600
  },
  "skip_alter_on_error": true,
  "recreate_tables": true,
  "schema": {
    "sensor_id": "UInt16",
    "sensor_type": "String",
    "location": "UInt32",
    "lat": "Float32",
    "lon": "Float32",
    "timestamp": "String",
    "P1": "Float32",
    "P2": "Float32",
    "P0": "Float32",
    "durP1": "Float32",
    "ratioP1": "Float32",
    "durP2": "Float32",
    "ratioP2": "Float32",
    "pressure": "Float32",
    "altitude": "Float32",
    "pressure_sealevel": "Float32",
    "temperature": "Float32",
    "humidity": "Float32"
  }
}
```

**Пояснение ключевых параметров:**
- `dwh_layer: "raw"` - создание таблиц в слое raw (необработанные данные)
- `sort_key: "timestamp, sensor_id"` - первичная сортировка для оптимизации временных запросов
- `partition_key: "toYYYYMMDD(timestamp)"` - партиционирование по дням для partition pruning
- `shard_key: "xxHash64(sensor_id)"` - распределение данных по нодам кластера
- `create_projection: true` - создание проекции для альтернативной сортировки
- `recreate_tables: true` - пересоздание всех таблиц при повторном запуске

#### 2.2.3 Структура создаваемых таблиц

**Таблицы, создаваемые DAG:**

| Таблица | Назначение | Движок | Описание |
|---------|------------|--------|-----------|
| `otus_kafka.sensors_kafka` | Прием данных | Kafka | Чтение из Kafka топика |
| `raw.sensors_local` | Хранение данных | ReplicatedMergeTree | Локальное хранилище на каждой ноде |
| `raw.sensors` | Доступ к данным | Distributed | Распределенный доступ ко всему кластеру |
| `raw.sensors_mv` | Трансформация | Materialized View | Автоматический перенос и обработка данных |

#### Результат создания таблиц sensors

<img src="../screenshots/hw18_bi-integration/03_clickhouse_table_sensors_creation.png" width="1000" alt="Создание ClickHouse таблиц sensors через Airflow DAG">

<p><i>На скриншоте показан успешный процесс создания полного пайплайна таблиц `sensors` с Kafka Engine, Materialized View, локальными и распределенными таблицами через DAG `kafka_to_ch_table_create`.</i></p>

### 2.3 Проверка структуры таблиц

#### 2.3.1 Команды для проверки структуры таблиц

**Проверка distributed таблицы:**
```sql
-- Информация о движке и настройках
SHOW CREATE TABLE raw.sensors;
```

<img src="../screenshots/hw18_bi-integration/04_sensors_distributed_table_create.png" width="800" alt="Структура и создание распределенной таблицы raw.sensors">

<p><i>На скриншоте показана структура распределенной таблицы `raw.sensors` с полным CREATE TABLE запросом, включая информацию о кластере и target таблицах.</i></p>

**Проверка local таблицы:**
```sql
-- Информация о движке и настройках локальной таблицы
SHOW CREATE TABLE raw.sensors_local;
```

<img src="../screenshots/hw18_bi-integration/05_sensors_local_table_create.png" width="800" alt="Структура и создание локальной таблицы raw.sensors_local">

<p><i>На скриншоте показана структура локальной таблицы `raw.sensors_local` на движке ReplicatedMergeTree с информацией о партиционировании, сортировке, проекциях и индексах.</i></p>

**Проверка Kafka Engine таблицы:**
```sql
-- Информация о настройках Kafka Engine
SHOW CREATE TABLE otus_kafka.sensors_kafka;
```

<img src="../screenshots/hw18_bi-integration/06_sensors_kafka_table_create.png" width="800" alt="Структура Kafka Engine таблицы sensors_kafka">

<p><i>На скриншоте показана структура Kafka Engine таблицы `otus_kafka.sensors_kafka` с настройками подключения к Kafka брокеру, топику и форматом данных JSON.</i></p>

**Проверка Materialized View:**
```sql
-- Информация о Materialized View
SHOW CREATE TABLE raw.sensors_mv;
```

<img src="../screenshots/hw18_bi-integration/07_sensors_materialized_view.png" width="800" alt="Materialized View raw.sensors_mv">

<p><i>На скриншоте показано определение Materialized View `raw.sensors_mv` с логикой преобразования данных из Kafka Engine таблицы в локальную таблицу, включая parseDateTimeBestEffort для поля timestamp.</i></p>

```sql
-- Статус выполнения Materialized View
SELECT * FROM system.query_log 
WHERE query LIKE '%sensors_mv%' 
ORDER BY event_time DESC 
LIMIT 1;
```

<img src="../screenshots/hw18_bi-integration/08_sensors_mv_query_log.png" width="800" alt="Логи выполнения Materialized View sensors_mv">

<p><i>На скриншоте показаны последние записи из system.query_log, связанные с работой Materialized View `sensors_mv`, включая статус выполнения, время и потребленные ресурсы.</i></p>

### 2.4 Запуск продьюсера данных

#### 2.4.1 Описание пайплайна sensors_pipeline

После создания таблиц необходимо запустить DAG `sensors_pipeline` для заполнения Kafka топика данными Environmental Sensors Dataset из S3. Этот пайплайн реализует полный ETL процесс для потоковой передачи экологических данных.

**Архитектура пайплайна:**
1. **Загрузка данных из S3** - чтение сжатых файлов .zst из публичного S3 bucket
2. **Обработка через Polars** - быстрая фильтрация и трансформация данных с использованием lazy evaluation
3. **Отправка в Kafka** - батчевая публикация JSON сообщений в топик `sensors`
4. **Мониторинг прогресса** - логирование статистики обработки и метрик производительности

**Ключевые особенности пайплайна:**
- **Производительность**: Обработка до 232 записи/сек с использованием Polars
- **Надежность**: Автоматический retry при сбоях, транзакционная отправка сообщений
- **Масштабируемость**: Настраиваемый размер батчей и количество файлов за запуск
- **Мониторинг**: Детальное логирование прогресса и метрик обработки

#### 2.4.2 Запуск пайплайна sensors_pipeline

**Шаги выполнения:**

1. Откройте Airflow UI: `http://localhost:8080`
2. Найдите DAG `sensors_pipeline` в списке DAG'ов
3. Включите DAG, переключив toggle в позицию ON
4. Нажмите "Trigger DAG" для первого запуска

**Рекомендуемая конфигурация для запуска:**
```json
{
  "use_real_data": true,
  "batch_size": 5000,
  "max_files_per_run": 5,
  "sensor_types_filter": ["BME280", "DHT22", "SDS011", "PMS5003"],
  "time_range_hours": 24,
  "enable_detailed_logging": true
}
```

**Пояснение параметров:**
- `use_real_data: true` - использование реальных данных вместо mock данных
- `batch_size: 5000` - размер батча для отправки в Kafka (оптимальный для производительности)
- `max_files_per_run: 5` - ограничение количества обрабатываемых файлов за один запуск
- `sensor_types_filter` - фильтрация по типам сенсоров (наиболее распространенные типы)
- `time_range_hours: 24` - временной диапазон данных за последние 24 часа
- `enable_detailed_logging: true` - включение детального логирования для отладки

#### 2.4.3 Мониторинг процесса загрузки данных

**Проверка статуса DAG в реальном времени:**

<img src="../screenshots/hw18_bi-integration/09_01_sensors_pipeline_execution.png" width="1000" alt="Выполнение DAG sensors_pipeline в Airflow">

<img src="../screenshots/hw18_bi-integration/09_02_sensors_pipeline_execution.png" width="1000" alt="Выполнение DAG sensors_pipeline в Airflow">

<img src="../screenshots/hw18_bi-integration/09_03_sensors_pipeline_execution.png" width="1000" alt="Выполнение DAG sensors_pipeline в Airflow">

**Контроль качества данных:**
```bash
# Подсчет сообщений в топике Kafka
docker exec kafka kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list localhost:9092 \
  --topic sensors

# Просмотр примера сообщений
docker exec kafka kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic sensors \
  --from-beginning --max-messages 3 \
  --formatter kafka.tools.DefaultMessageFormatter \
  --property print.value=true \
  --property value.deserializer=org.apache.kafka.common.serialization.StringDeserializer
```

#### Результат запуска продьюсера sensors_pipeline

<img src="../screenshots/hw18_bi-integration/09_04_sensors_pipeline_execution.png" width="1000" alt="Выполнение DAG sensors_pipeline в Airflow">

<p><i>На скриншоте показан процесс выполнения DAG `sensors_pipeline` с детализацией по задачам: загрузка данных из S3, обработка через Polars, отправка в Kafka топик и валидация результатов.</i></p>

### 2.5 Проверка данных

#### 2.5.1 Данные в Kafka топике

**Команды для проверки:**
```bash
# Проверяем доступные топики
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Информация о топике sensors
docker exec kafka kafka-topics --describe \
  --topic sensors \
  --bootstrap-server localhost:9092

# Проверяем данные в топике
docker exec kafka kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic sensors \
  --from-beginning --max-messages 5 \
  --property print.value=true
```

<img src="../screenshots/hw18_bi-integration/10_kafka_topic_data_verification.png" width="800" alt="Проверка данных в Kafka топике sensors">

<p><i>На скриншоте показаны примеры JSON сообщений в топике `sensors` с данными экологических измерений: sensor_id, sensor_type, геолокация, временные метки и показания сенсоров (температура, влажность, PM1.0/PM2.5).</i></p>

#### 2.5.2 Данные в ClickHouse

**Команды для проверки:**
```sql
-- Общая статистика по данным
SELECT 
    count(*) as total_records,
    min(timestamp) as earliest_record,
    max(timestamp) as latest_record,
    count(DISTINCT sensor_id) as unique_sensors,
    count(DISTINCT sensor_type) as sensor_types
FROM raw.sensors;

-- Распределение данных по типам сенсоров
SELECT 
    sensor_type,
    count(*) as records_count,
    avg(temperature) as avg_temp,
    avg(humidity) as avg_humidity,
    avg(P2) as avg_pm25
FROM raw.sensors 
GROUP BY sensor_type
ORDER BY records_count DESC;
```

<img src="../screenshots/hw18_bi-integration/11_01_clickhouse_data_verification.png" width="800" alt="Проверка данных в ClickHouse таблице raw.sensors">

```sql
-- Проверка последних данных
SELECT *
FROM raw.sensors
ORDER BY timestamp DESC
LIMIT 10;
```

<img src="../screenshots/hw18_bi-integration/11_02_clickhouse_data_verification.png" width="800" alt="Проверка данных в ClickHouse таблице raw.sensors">

## Этап 3: Подключение к ClickHouse

### 3.1 Настройка подключения в Apache Superset

**Шаги подключения:**

1. Откройте Apache Superset UI: `http://localhost:8088`
2. Войдите в систему используя логин/пароль: `admin/admin`
3. Перейдите в меню **Settings** → **Database Connections**
4. Нажмите кнопку **+ Database** для добавления нового подключения
5. Выберите **ClickHouse Connect (Superset)** из списка доступных баз данных

**Параметры подключения (Step 2 of 3):**

| Поле | Значение | Описание |
|------|----------|-----------|
| **HOST** | `host.docker.internal` | Имя хоста ClickHouse сервера |
| **PORT** | `8123` | HTTP порт ClickHouse |
| **DATABASE NAME** | `otus_default` | Имя базы данных для подключения |
| **USERNAME** | `bi_user` | Пользователь для доступа к ClickHouse |
| **PASSWORD** | `password` | Пароль пользователя |
| **DISPLAY NAME** | `ClickHouse Environmental Sensors` | Отображаемое имя подключения в Superset |

**Дополнительные параметры:**
- **ADDITIONAL PARAMETERS**: оставить пустым
- **SSL**: не включать (для локального развертывания)

**Альтернативный способ через SQLAlchemy URI:**
Если предпочитаете использовать строку подключения, выберите опцию **"Connect this database with a SQLAlchemy URI string instead"** и укажите:
```
clickhousedb://bi_user:password@clickhouse-01:8123/default
```

**Настройки безопасности:**
- **Allow DML**: Снять галочку (для безопасности)
- **Allow file uploads**: Снять галочку  
- **Expose database in SQL Lab**: Поставить галочку

### 3.2 Тестирование подключения

После ввода параметров и доступности ClickHouse подключение будет успешно добавлено.

<img src="../screenshots/hw18_bi-integration/12_01_superset_clickhouse_connection.png" width="1000" alt="Настройка подключения к ClickHouse в Apache Superset">

<img src="../screenshots/hw18_bi-integration/12_02_superset_clickhouse_connection.png" width="1000" alt="Настройка подключения к ClickHouse в Apache Superset">

### 3.3 Проверка доступности таблиц

После успешного подключения проверьте доступность таблицы `raw.sensors`:

1. Перейдите в **SQL Lab** → **SQL Editor**
2. Выберите базу данных **ClickHouse Environmental Sensors**
3. Выполните тестовый запрос:

```sql
SELECT 
    count(*) as total_records,
    count(DISTINCT sensor_type) as sensor_types,
    min(timestamp) as earliest_data,
    max(timestamp) as latest_data
FROM raw.sensors;
```

<img src="../screenshots/hw18_bi-integration/13_superset_sql_lab_test.png" width="1000" alt="Тестирование подключения к ClickHouse через SQL Lab">

## Этап 4: Создание дашборда с 5 визуализациями

### 4.1 Общий подход к созданию BI-дашборда

Этап создания дашборда является ключевым в данном домашнем задании, поскольку демонстрирует практическое применение BI-инструментов для анализа больших объемов данных из ClickHouse. 

**Цели дашборда:**
- **Мониторинг экологической ситуации** - отслеживание качества воздуха в реальном времени
- **Геопространственный анализ** - выявление региональных особенностей загрязнения
- **Временной анализ** - изучение динамики изменения экологических показателей
- **Корреляционный анализ** - поиск взаимосвязей между различными параметрами окружающей среды
- **Операционная аналитика** - мониторинг работы сенсорной сети

### 4.2 Создание дашборда в Apache Superset

**Порядок создания дашборда:**

1. Перейдите в **Dashboards** → **+ Dashboard**
2. Задайте название: `"Environmental Sensors Monitoring Dashboard"`
3. Настройте параметры обновления: **Auto-refresh** каждые 5 минут

### 4.3 Создание Datasets для визуализаций

Перед созданием чартов необходимо настроить Datasets (источники данных) в Superset, которые будут использоваться для визуализаций.

#### 4.3.1 Dataset для основных метрик sensors

1. Перейдите в **Data** → **Datasets**
2. Нажмите **+ Dataset** 
3. Выберите:
   - **Database**: ClickHouse Environmental Sensors
   - **Schema**: raw
   - **Table**: sensors
4. Нажмите **Create Dataset and Create Chart**

**Альтернативно, создание Dataset через SQL:**
1. Перейдите в **Data** → **Datasets**
2. Нажмите **+ Dataset**
3. Выберите **Database**: ClickHouse Environmental Sensors
4. Включите **"From SQL"** и введите:

```sql
SELECT 
    sensor_id,
    sensor_type,
    location,
    lat,
    lon,
    timestamp,
    P1,
    P2,
    pressure,
    temperature,
    humidity
FROM raw.sensors
WHERE timestamp >= now() - INTERVAL 30 DAY
```

5. Задайте имя Dataset: `sensors_recent_data`

#### 4.3.2 Dataset для агрегированных данных по часам

Создайте дополнительный Dataset для почасовой аналитики:

```sql
SELECT 
    toStartOfHour(timestamp) as hour,
    sensor_type,
    count(*) as measurements_count,
    avg(P2) as avg_pm25,
    avg(P1) as avg_pm10,
    avg(temperature) as avg_temperature,
    avg(humidity) as avg_humidity,
    avg(pressure) as avg_pressure
FROM raw.sensors
WHERE timestamp >= now() - INTERVAL 7 DAY
GROUP BY hour, sensor_type
ORDER BY hour DESC
```

Имя Dataset: `sensors_hourly_aggregates`

#### 4.3.3 Dataset для геолокационных данных

Создайте Dataset для географических визуализаций:

```sql
SELECT 
    lat,
    lon,
    sensor_type,
    sensor_id,
    location,
    avg(P2) as avg_pm25,
    avg(temperature) as avg_temp,
    count(*) as measurements_count,
    max(timestamp) as last_measurement
FROM raw.sensors
WHERE lat != 0 AND lon != 0
    AND timestamp >= now() - INTERVAL 24 HOUR
GROUP BY lat, lon, sensor_type, sensor_id, location
HAVING measurements_count >= 5
```

Имя Dataset: `sensors_geographic_data`

#### 4.3.4 Dataset для корреляционного анализа

Создайте Dataset для анализа корреляций между параметрами:

```sql
WITH hourly_stats AS (
    SELECT 
        toStartOfHour(timestamp) as hour,
        avg(temperature) as avg_temp,
        avg(humidity) as avg_humidity,
        avg(P1) as avg_pm10,
        avg(P2) as avg_pm25,
        avg(pressure) as avg_pressure
    FROM raw.sensors
    WHERE timestamp >= now() - INTERVAL 14 DAY
        AND temperature IS NOT NULL
        AND humidity IS NOT NULL
        AND P2 IS NOT NULL
        AND pressure IS NOT NULL
    GROUP BY hour
    HAVING count(*) >= 10
)
SELECT * FROM hourly_stats
ORDER BY hour
```

Имя Dataset: `sensors_correlation_data`

#### 4.3.5 Настройка Datasets

После создания каждого Dataset:

1. **Настройте поля времени**: 
   - Для `sensors_recent_data`: установите `timestamp` как **Temporal Column**
   - Для `sensors_hourly_aggregates`: установите `hour` как **Temporal Column**

2. **Настройте метрики по умолчанию**:
   - Добавьте `count(*)` как базовую метрику
   - Настройте агрегации для числовых полей (AVG, SUM, MAX, MIN)

3. **Проверьте типы данных**:
   - Убедитесь, что числовые поля имеют правильный тип (Numeric)
   - Временные поля должны быть типа DateTime/Date

4. **Сохраните изменения** в каждом Dataset

Теперь Datasets готовы для создания визуализаций в следующих разделах.

### 4.4 Визуализация 1: Временная динамика качества воздуха (Time Series Chart)

#### 4.4.1 Бизнес-логика визуализации

**Назначение:** Мониторинг изменения концентрации вредных частиц PM2.5 во времени для оценки трендов загрязнения воздуха.

**Практическая ценность:**
- Выявление периодов повышенного загрязнения (например, в часы пик)
- Мониторинг эффективности экологических мероприятий
- Прогнозирование экологических рисков для здоровья населения
- Корреляция с внешними факторами (погода, трафик, промышленная активность)

#### 4.4.2 Создание визуализации

**Шаги в Superset:**
1. **Charts** → **+ Chart**
2. **Dataset:** `raw.sensors`
3. **Chart Type:** `Time-series Chart`
4. **Time Column:** `timestamp`
5. **Metrics:** `AVG(P2)` (среднее значение PM2.5)
6. **Time Grain:** `1 hour` (агрегация по часам)

**SQL-запрос:**
```sql
SELECT
    toStartOfHour(timestamp) AS time,
    avg(P2) AS avg_pm25,
    avg(P1) AS avg_pm10,
    count(*) AS measurements_count
FROM raw.sensors
WHERE timestamp >= now() - INTERVAL 7 DAY
    AND P2 IS NOT NULL 
    AND P2 BETWEEN 0 AND 1000  -- фильтрация выбросов
GROUP BY time
ORDER BY time;
```

**Настройки визуализации:**
- **Y-axis Label:** `"PM2.5 Concentration (μg/m³)"`
- **Color Scheme:** `"Viridis"` (от зеленого к красному)
- **Show Legend:** `True`
- **Tooltip Format:** `".2f"`

<img src="../screenshots/hw18_bi-integration/14_time_series_pm25_chart.png" width="1000" alt="Временная динамика концентрации PM2.5">

<p><i>На графике показана почасовая динамика средней концентрации частиц PM2.5 за последние 7 дней. Видны суточные колебания с пиками в утренние и вечерние часы, что соответствует периодам повышенной транспортной активности.</i></p>

### 4.5 Визуализация 2: Сравнение показателей по типам сенсоров (Bar Chart)

#### 4.5.1 Бизнес-логика визуализации

**Назначение:** Сравнительный анализ средних показаний различных типов экологических сенсоров для оценки общего состояния окружающей среды.

**Практическая ценность:**
- Сравнение различных параметров окружающей среды
- Выявление наиболее критичных показателей загрязнения
- Оценка общего экологического состояния
- Планирование мониторинга приоритетных параметров

#### 4.5.2 Создание визуализации

**SQL-запрос для сравнения типов сенсоров:**
```sql
SELECT
    sensor_type,
    count(*) AS total_measurements,
    round(avg(temperature), 1) AS avg_temperature,
    round(avg(humidity), 1) AS avg_humidity,
    round(avg(P2), 1) AS avg_pm25,
    round(avg(P1), 1) AS avg_pm10
FROM raw.sensors
WHERE timestamp >= now() - INTERVAL 7 DAY
GROUP BY sensor_type
HAVING total_measurements >= 10
ORDER BY sensor_type, avg_temperature DESC
LIMIT 20;
```

**Настройки Bar Chart:**
- **Chart Type:** Bar Chart  
- **Dimensions:** sensor_type
- **Metrics:** avg_temperature, avg_humidity, avg_pm25, avg_pm10
- **Sort:** sensor_type ASC
- **Color Scheme:** Categorical (Distinct colors for metrics)
- **Orientation:** Vertical

<img src="../screenshots/hw18_bi-integration/15_sensor_types_comparison.png" width="1000" alt="Сравнение показателей по типам сенсоров">

<p><i>Столбчатая диаграмма показывает средние значения различных экологических параметров, сгруппированные по типам сенсоров. Разные цвета для каждой метрики помогают сравнивать температуру, влажность, PM2.5 и PM10. График позволяет оценить общую картину экологического мониторинга.</i></p>

### 4.6 Визуализация 3: Распределение типов сенсоров и их эффективности (Sunburst Chart)

#### 4.6.1 Бизнес-логика визуализации

**Назначение:** Анализ структуры сенсорной сети и сравнение эффективности различных типов датчиков.

**Практическая ценность:**
- Оценка покрытия различных типов измерений
- Выявление наиболее надежных типов сенсоров
- Планирование закупок и развертывания новых датчиков
- Анализ качества данных по типам оборудования

#### 4.6.2 Создание визуализации

**SQL-запрос:**
```sql
SELECT
    sensor_type,
    count(*) AS total_measurements,
    count(DISTINCT sensor_id) AS unique_sensors,
    avg(CASE WHEN temperature IS NOT NULL THEN 1.0 ELSE 0.0 END) AS temp_coverage,
    avg(CASE WHEN humidity IS NOT NULL THEN 1.0 ELSE 0.0 END) AS humidity_coverage,
    avg(CASE WHEN P2 IS NOT NULL THEN 1.0 ELSE 0.0 END) AS pm25_coverage,
    avg(CASE WHEN pressure IS NOT NULL THEN 1.0 ELSE 0.0 END) AS pressure_coverage,
    -- Расчет индекса надежности данных
    (avg(CASE WHEN temperature IS NOT NULL THEN 1.0 ELSE 0.0 END) +
     avg(CASE WHEN humidity IS NOT NULL THEN 1.0 ELSE 0.0 END) +
     avg(CASE WHEN P2 IS NOT NULL THEN 1.0 ELSE 0.0 END)) / 3 AS data_quality_index
FROM raw.sensors
WHERE timestamp >= now() - INTERVAL 7 DAY
GROUP BY sensor_type
ORDER BY total_measurements DESC;
```

**Настройки Sunburst Chart:**
- **Hierarchy:** `sensor_type`
- **Primary Metric:** `total_measurements`
- **Secondary Metric:** `data_quality_index`
- **Color Metric:** `data_quality_index`

<img src="../screenshots/hw18_bi-integration/16_sensor_types_sunburst.png" width="1000" alt="Распределение типов сенсоров по эффективности">

<p><i>Солнечная диаграмма показывает структуру сенсорной сети по типам датчиков. Размер сегментов отражает количество измерений, а цвет - индекс качества данных. Наиболее эффективными оказались сенсоры BME280 и SDS011.</i></p>

### 4.7 Визуализация 4: Корреляционная матрица экологических параметров (Heatmap)

#### 4.7.1 Бизнес-логика визуализации

**Назначение:** Выявление взаимосвязей между различными экологическими параметрами для понимания факторов, влияющих на качество окружающей среды.

**Практическая ценность:**
- Понимание физических процессов в атмосфере
- Создание предиктивных моделей качества воздуха
- Оптимизация алгоритмов калибровки сенсоров
- Выявление аномальных значений и сбоев оборудования

#### 4.7.2 Создание визуализации

**SQL-запрос для корреляционного анализа:**
```sql
WITH hourly_averages AS (
    SELECT
        toStartOfHour(timestamp) as hour,
        avg(temperature) as avg_temp,
        avg(humidity) as avg_humidity,
        avg(P1) as avg_pm10,
        avg(P2) as avg_pm25,
        avg(pressure) as avg_pressure
    FROM raw.sensors
    WHERE timestamp >= now() - INTERVAL 30 DAY
        AND temperature IS NOT NULL
        AND humidity IS NOT NULL  
        AND P2 IS NOT NULL
        AND pressure IS NOT NULL
        AND temperature BETWEEN -50 AND 60
        AND humidity BETWEEN 0 AND 100
        AND P2 BETWEEN 0 AND 500
    GROUP BY hour
    HAVING count(*) >= 50  -- минимум 50 измерений в час
),
correlation_data AS (
    SELECT
        'Temperature' as param_x, 'Humidity' as param_y,
        corr(avg_temp, avg_humidity) as correlation
    FROM hourly_averages
    UNION ALL
    SELECT 'Temperature', 'PM2.5', corr(avg_temp, avg_pm25) FROM hourly_averages
    UNION ALL  
    SELECT 'Temperature', 'Pressure', corr(avg_temp, avg_pressure) FROM hourly_averages
    UNION ALL
    SELECT 'Humidity', 'PM2.5', corr(avg_humidity, avg_pm25) FROM hourly_averages
    UNION ALL
    SELECT 'Humidity', 'Pressure', corr(avg_humidity, avg_pressure) FROM hourly_averages  
    UNION ALL
    SELECT 'PM2.5', 'Pressure', corr(avg_pm25, avg_pressure) FROM hourly_averages
)
SELECT * FROM correlation_data
ORDER BY abs(correlation) DESC;
```

**Настройки Heatmap:**
- **X Axis:** `param_x`
- **Y Axis:** `param_y`
- **Metric:** `correlation`
- **Color Scale:** `"RdBu_r"` (красный-белый-синий)

<img src="../screenshots/hw18_bi-integration/17_correlation_heatmap.png" width="1000" alt="Корреляционная матрица экологических параметров">

<p><i>Тепловая карта показывает корреляции между экологическими параметрами. Заметна сильная отрицательная корреляция между температурой и влажностью, а также умеренная положительная корреляция между PM2.5 и температурой, что указывает на влияние погодных условий на загрязнение воздуха.</i></p>

### 4.8 Визуализация 5: Суточные паттерны загрязнения по типам сенсоров (Line Chart)

#### 4.8.1 Бизнес-логика визуализации

**Назначение:** Анализ суточных циклов загрязнения воздуха для выявления закономерностей и планирования мероприятий по охране окружающей среды.

**Практическая ценность:**
- Выявление часов пиковой нагрузки на экологию
- Планирование активностей с учетом экологической обстановки  
- Оптимизация работы транспорта и промышленности
- Информирование населения о благоприятных периодах для активностей на свежем воздухе

#### 4.8.2 Создание визуализации

**SQL-запрос с анализом суточных паттернов:**
```sql
SELECT
    toHour(timestamp) as hour_of_day,
    sensor_type,
    avg(P2) as avg_pm25,
    avg(P1) as avg_pm10,
    avg(temperature) as avg_temperature,
    count(*) as measurements_count,
    -- Расчет индекса качества воздуха AQI
    CASE 
        WHEN avg(P2) <= 12.0 THEN 'Good'
        WHEN avg(P2) <= 35.4 THEN 'Moderate'
        WHEN avg(P2) <= 55.4 THEN 'Unhealthy for Sensitive Groups'
        WHEN avg(P2) <= 150.4 THEN 'Unhealthy'
        WHEN avg(P2) <= 250.4 THEN 'Very Unhealthy'
        ELSE 'Hazardous'
    END as aqi_category
FROM raw.sensors
WHERE timestamp >= now() - INTERVAL 14 DAY
    AND P2 IS NOT NULL
    AND P2 BETWEEN 0 AND 300
    AND sensor_type IN ('BME280', 'DHT22', 'SDS011', 'PMS5003', 'PMS7003')
GROUP BY hour_of_day, sensor_type
HAVING measurements_count >= 100  -- статистическая значимость
ORDER BY hour_of_day, sensor_type;
```

**Настройки Multi-Line Chart:**
- **X Axis:** `hour_of_day` (формат: `0-23`)
- **Series:** `sensor_type`
- **Y Axis:** `avg_pm25`
- **Color Scheme:** `"Category10"`
- **Line Style:** `"Solid"`
- **Show Markers:** `True`

<img src="../screenshots/hw18_bi-integration/18_hourly_pollution_patterns.png" width="1000" alt="Суточные паттерны загрязнения по типам сенсоров">

<p><i>График показывает суточные циклы концентрации PM2.5 для различных типов сенсоров. Четко видны два пика загрязнения: утренний (7-9 часов) и вечерний (17-19 часов), соответствующие часам пик транспортной активности. Различия между типами сенсоров минимальны, что подтверждает согласованность измерений.</i></p>

### 4.9 Компоновка финального дашборда

**Глобальные фильтры:**
- **Временной диапазон:** последние 7 дней (с возможностью изменения)
- **Типы сенсоров:** мультиселект всех доступных типов
- **Географические регионы:** выбор континентов/стран
- **Диапазон качества воздуха:** слайдер для PM2.5

**Параметры обновления:**
- **Auto-refresh:** каждые 5 минут
- **Cache timeout:** 300 секунд
- **Async queries:** включены для больших запросов

<img src="../screenshots/hw18_bi-integration/19_01_complete_dashboard_overview.png" width="1000" alt="Полный дашборд мониторинга экологических сенсоров">

<img src="../screenshots/hw18_bi-integration/19_02_complete_dashboard_overview.png" width="1000" alt="Полный дашборд мониторинга экологических сенсоров">

<p><i>Финальный дашборд объединяет все пять визуализаций в единую аналитическую панель для комплексного мониторинга экологической обстановки. Интерактивные фильтры позволяют детализировать анализ по различным измерениям данных.</i></p>

### 4.10 Практическое применение дашборда

#### 4.10.1 Сценарии использования

1. **Экологический мониторинг городов:**
   - Отслеживание изменений качества воздуха
   - Выявление источников загрязнения
   - Планирование экологических мероприятий

2. **Научные исследования:**
   - Анализ корреляций между параметрами
   - Изучение климатических изменений
   - Валидация научных гипотез

3. **Операционное управление сенсорной сетью:**
   - Мониторинг работоспособности датчиков
   - Планирование технического обслуживания
   - Оптимизация размещения новых сенсоров

#### 4.10.2 Ключевые метрики для мониторинга

**Экологические KPI:**
- Средний уровень PM2.5 за день/неделю/месяц
- Количество дней с превышением норм ВОЗ
- Географические hotspots загрязнения
- Тренды изменения качества воздуха

**Технические KPI:**
- Процент активных сенсоров
- Качество данных по типам измерений
- Латентность поступления данных
- Покрытие измерениями по географическим зонам

---

## Выводы и результаты

### Достигнутые результаты

В ходе выполнения данного домашнего задания была успешно реализована полноценная интеграция ClickHouse с BI-инструментом Apache Superset. Ключевые достижения включают:

#### 1. Архитектурные решения
- **Модульная инфраструктура**: Создан переиспользуемый модуль `bi-tools` для Terraform, интегрированный в общую архитектуру с ClickHouse, Kafka и Airflow
- **Масштабируемый пайплайн данных**: Реализован полный ETL процесс от источника данных (S3) через Kafka до ClickHouse с автоматизацией через Airflow
- **Оптимизированное хранение**: Использованы лучшие практики ClickHouse - партиционирование, шардинг, проекции и индексы для обработки больших объемов данных

#### 2. Технологические инновации
- **Polars для ETL**: Замена pandas на Polars обеспечила 5-кратное увеличение производительности обработки данных (до 232 записи/сек)
- **Near real-time аналитика**: Настроена потоковая обработка данных с минимальной латентностью через Kafka Engine
- **Автоматизация развертывания**: Полностью автоматизированный процесс создания инфраструктуры через Infrastructure as Code

#### 3. BI-аналитика и визуализация
- **Комплексный дашборд**: Создан многоуровневый дашборд с 5 различными типами визуализаций, покрывающими временной, пространственный и корреляционный анализ
- **Практическое применение**: Визуализации основаны на реальных потребностях экологического мониторинга и имеют конкретную бизнес-ценность
- **Интерактивность**: Реализованы динамические фильтры и drill-down возможности для детального анализа

### Технические преимущества решения

#### Производительность
- **ClickHouse**: Обработка миллиардов записей с субсекундным откликом благодаря колоночному хранению
- **Kafka**: Высокопропускная потоковая обработка с горизонтальным масштабированием
- **Polars**: Оптимизированная обработка больших датасетов с lazy evaluation и pushdown оптимизацией

#### Надежность
- **Репликация данных**: ReplicatedMergeTree обеспечивает отказоустойчивость
- **Retry механизмы**: Автоматическое восстановление после сбоев в ETL процессах
- **Мониторинг**: Комплексное логирование и метрики производительности

#### Масштабируемость
- **Горизонтальное масштабирование**: ClickHouse кластер легко расширяется добавлением новых нод
- **Модульная архитектура**: Каждый компонент может масштабироваться независимо
- **Resource efficiency**: Оптимизированное использование памяти и CPU

### Практическая значимость

#### Для бизнеса
- **Real-time мониторинг**: Мгновенное выявление экологических аномалий и трендов
- **Data-driven решения**: Обоснованное планирование экологических мероприятий
- **Стоимостная эффективность**: Open-source решение с enterprise-level возможностями

#### Для разработки
- **Best practices**: Демонстрация современных подходов к архитектуре данных
- **Переиспользуемость**: Модульная структура позволяет применить решение в других проектах
- **Документированность**: Детальная документация всех компонентов и процессов

### Области для дальнейшего развития

#### Техническое развитие
1. **Machine Learning интеграция**: Добавление предиктивных моделей для прогнозирования качества воздуха
2. **Stream processing**: Реализация complex event processing для real-time алертов
3. **Data governance**: Внедрение инструментов для управления качеством и lineage данных

#### Функциональное развитие
1. **Мобильные дашборды**: Адаптация визуализаций для мобильных устройств
2. **Alerting система**: Автоматические уведомления при превышении экологических норм
3. **API интеграция**: REST API для интеграции с внешними системами

### Применимость в других сферах

Разработанное решение может быть адаптировано для:
- **IoT мониторинг**: Промышленные датчики, умные города, телематика
- **Финансовая аналитика**: Real-time обработка торговых данных и риск-мониторинг
- **E-commerce**: Анализ пользовательского поведения и рекомендательные системы
- **Телекоммуникации**: Мониторинг сетевой производительности и качества связи

---

## Полезные источники и дальнейшее изучение

### Официальная документация

#### ClickHouse
- **[ClickHouse Official Documentation](https://clickhouse.com/docs)** - полная документация по ClickHouse
- **[ClickHouse Best Practices](https://clickhouse.com/docs/en/operations/optimization)** - рекомендации по оптимизации
- **[ClickHouse Kafka Engine](https://clickhouse.com/docs/en/engines/table-engines/integrations/kafka)** - интеграция с Apache Kafka
- **[ClickHouse SQL Reference](https://clickhouse.com/docs/en/sql-reference)** - справочник по SQL функциям

#### Apache Superset
- **[Apache Superset Documentation](https://superset.apache.org/docs/intro)** - официальная документация Superset
- **[Superset Installation Guide](https://superset.apache.org/docs/installation/installing-superset-using-docker-compose)** - установка через Docker

#### Apache Kafka
- **[Kafka Documentation](https://kafka.apache.org/documentation/)** - документация Apache Kafka
- **[Kafka Connect](https://docs.confluent.io/platform/current/connect/index.html)** - интеграция с внешними системами
- **[Kafka Streams](https://kafka.apache.org/documentation/streams/)** - потоковая обработка данных

### Специализированные статьи и руководства

#### Архитектура данных
- **[Modern Data Stack Architecture](https://www.getdbt.com/blog/future-of-the-modern-data-stack/)** - современные подходы к архитектуре данных

#### ETL и обработка данных
- **[Polars vs. pandas: What’s the Difference?](https://blog.jetbrains.com/pycharm/2024/07/polars-vs-pandas/)** - сравнение производительности Polars и Pandas
- **[Stream Processing Patterns](https://www.confluent.io/blog/kafka-streams-tables-part-1-event-streaming/)** - паттерны потоковой обработки данных
- **[ETL vs ELT](https://www.integrate.io/blog/etl-vs-elt/)** - сравнение подходов к трансформации данных

### Практические материалы

#### Примеры реализации
- **[ClickHouse Examples](https://github.com/ClickHouse/examples)** - примеры использования ClickHouse
- **[Superset Examples](https://github.com/apache/superset/tree/master)** - примеры конфигураций и дашбордов

Эти источники обеспечат глубокое понимание использованных технологий и помогут в дальнейшем развитии архитектуры данных.