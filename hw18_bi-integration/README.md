# Homework #18: Интеграция с BI-инструментами

## Оглавление
- [Цель](#цель)
- [Описание/Пошаговая инструкция выполнения](#описаниепошаговая-инструкция-выполнения)
- [Предисловие](#предисловие)
- [Используемые данные](#используемые-данные)
- [Архитектура решения](#архитектура-решения)
- [Этап 1: Реализация модуля bi-tools](#этап-1-реализация-модуля-bi-tools)
- [Этап 2: Подключение к ClickHouse](#этап-2-подключение-к-clickhouse)
- [Этап 3: Создание дашборда с 5 визуализациями](#этап-3-создание-дашборда-с-5-визуализациями)
- [Этап 4: Экспорт дашборда для импорта](#этап-4-экспорт-дашборда-для-импорта)
- [Проверка результатов](#проверка-результатов)
- [Компетенции](#компетенции)
- [Результат](#результат)

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

По заданию нам нужно сделать дашборд в Apache Superset, поэтому, хотя по желанию автора был развернут также Metabase, всё выполнение будет проводиться в Superset в соответствии с заданием.

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
- **Обновление**: Данные поступают через Kafka топики с периодичностью 1 и 5 минут
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

Данные Environmental Sensors организованы в оптимизированной архитектуре для работы с посекундными временными рядами:

#### **Структура исходных данных Environmental Sensors**
```sql
sensor_id UInt16,           -- ID сенсора (1-65535)
sensor_type Enum(...),      -- Тип сенсора (BME280, SDS011, DHT22, PMS5003, etc.)
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

#### **1. Уровень Kafka Integration (`kafka` schema)**

**Разделение на два оптимизированных топика:**

Учитывая специфику Environmental Sensors данных, было принято решение разделить поток на два топика с разной частотой обновлений:

- **`kafka.sensors_measurements_kafka`** — Kafka Engine для топика `sensors_measurements_1min`
  - Высокочастотные данные измерений (температура, влажность, качество воздуха)
  - Обновляются каждую минуту для near real-time мониторинга
  
- **`kafka.sensors_locations_kafka`** — Kafka Engine для топика `sensors_locations_5min`  
  - Метаданные сенсоров (координаты, типы), изменяющиеся редко
  - Обновляются каждые 5 минут для экономии ресурсов

Такая архитектура позволяет оптимизировать использование сети и хранилища, при этом сохраняя возможность джойнов по `sensor_id` и `timestamp`.

#### **2. Уровень Raw Data (`raw` schema)**

**Таблица измерений (высокочастотные данные):**
- **`raw.sensors_measurements_local`** — ReplicatedMergeTree таблица (локальная)
- **`raw.sensors_measurements`** — Distributed таблица
- **`raw.sensors_measurements_mv`** — Materialized View (Kafka → Local)

**Структура измерений:**
```sql
timestamp DateTime,         -- Время измерения (YYYY-MM-DD HH:MM:SS)
sensor_id UInt16,           -- ID сенсора для джойна
temperature Float32,        -- Температура воздуха (°C)
humidity Float32,           -- Влажность (%)
pressure Float32,           -- Давление (гПа)
P1 Float32,                 -- PM1.0 (мкг/м³)
P2 Float32                  -- PM2.5 (мкг/м³)
```

#### **3. Уровень ODS - Operational Data Store (`ods` schema)**

**Таблица метаданных сенсоров (низкочастотные данные):**
- **`ods.sensors_locations_local`** — ReplicatedMergeTree таблица (локальная)  
- **`ods.sensors_locations`** — Distributed таблица
- **`ods.sensors_locations_mv`** — Materialized View (Kafka → Local)

**Структура метаданных:**
```sql
timestamp DateTime,         -- Время обновления метаданных
sensor_id UInt16,           -- ID сенсора для джойна
sensor_type String,         -- Тип сенсора (BME280, SDS011, etc.)
location UInt32,            -- ID локации
lat Float32,                -- Широта (WGS84)
lon Float32                 -- Долгота (WGS84)
```

### Используемые таблицы в дашборде

Для визуализаций используются **Distributed таблицы** с возможностью джойнов по `sensor_id` и `timestamp`:

1. **`raw.sensors_measurements`** — для анализа измерений в реальном времени (температура, влажность, качество воздуха)
2. **`ods.sensors_locations`** — для геопространственного анализа и фильтрации по типам сенсоров

**Пример джойна для полноценного анализа:**
```sql
SELECT 
    m.timestamp,
    l.sensor_type,
    l.lat, l.lon,
    m.temperature,
    m.P2 as pm25_concentration
FROM raw.sensors_measurements m
JOIN ods.sensors_locations l ON (
    m.sensor_id = l.sensor_id 
    AND m.timestamp BETWEEN l.timestamp - INTERVAL 5 MINUTE 
                         AND l.timestamp + INTERVAL 5 MINUTE
)
WHERE m.timestamp >= now() - INTERVAL 1 HOUR
ORDER BY m.timestamp DESC
```

### Потоковая обработка данных

- **Периодичность поступления**: 
  - Измерения: каждую минуту (10 сообщений за батч)
  - Метаданные сенсоров: каждые 5 минут (5 сообщений за батч)
- **Real-time обновление**: Данные в дашборде обновляются в режиме реального времени через Materialized Views
- **Географический охват**: Глобальная сеть сенсоров с фильтрацией по регионам и типам сенсоров
- **Временная точность**: Посекундные измерения для near real-time мониторинга
- **Оптимизированная производительность**: Polars обеспечивает обработку до 232 записей/сек

---

## Архитектура решения

### Схема архитектуры модуля bi-tools

```mermaid
graph TB
    subgraph "Terraform Main Pipeline"
        A[main.tf] --> B[module.postgres]
        A --> C[module.bi_tools]
        A --> D[module.clickhouse_cluster]
    end
    
    subgraph "BI Tools Module"
        C --> E[PostgreSQL Integration]
        C --> F[Metabase Container]
        C --> G[Superset Container]
        C --> H[Configuration Generation]
    end
    
    subgraph "PostgreSQL Layer"
        B --> I[postgres container]
        E --> J[metabase_db]
        E --> K[superset_db] 
        E --> L[airflow_db]
        I --> J
        I --> K
        I --> L
    end
    
    subgraph "Configuration & Secrets"
        H --> M[superset_config.py.tmpl]
        H --> N[Secret Key Generation]
        H --> O[User Management]
    end
    
    subgraph "ClickHouse Integration"
        G --> P[ClickHouse Drivers]
        P --> Q[clickhouse-connect]
        P --> R[clickhouse-driver]
        D --> S[ClickHouse Cluster]
        Q --> S
        R --> S
    end
    
    subgraph "Network & Service Discovery"
        T[Docker Network] --> F
        T --> G
        T --> I
        T --> S
    end
    
    subgraph "Data Sources"
        S --> U[sensors_measurements_1min_distributed]
        S --> V[sensors_locations_5min_distributed]
        U --> W[Dashboard Visualizations]
        V --> W
    end
```

### Последовательность развертывания

#### 1. **Инициализация инфраструктуры**
```mermaid
sequenceDiagram
    participant TF as Terraform
    participant PG as PostgreSQL Module  
    participant BI as BI-Tools Module
    participant CH as ClickHouse Module
    
    TF->>+PG: Deploy PostgreSQL container
    PG->>PG: Create docker network
    PG->>PG: Initialize postgres databases
    PG-->>-TF: PostgreSQL ready
    
    TF->>+CH: Deploy ClickHouse cluster
    CH->>CH: Create ClickHouse containers
    CH->>CH: Configure cluster settings
    CH-->>-TF: ClickHouse cluster ready
    
    TF->>+BI: Deploy BI tools (depends_on: postgres)
    BI->>BI: Check service enable flags
    BI-->>-TF: BI module initialization ready
```

#### 2. **Настройка баз данных**
```mermaid
sequenceDiagram
    participant BI as BI-Tools Module
    participant PG as PostgreSQL Container
    participant MB as Metabase
    participant SS as Superset
    
    BI->>+PG: Check PostgreSQL readiness
    PG-->>-BI: pg_isready confirmed
    
    BI->>+PG: Create metabase user & database
    PG->>PG: CREATE USER metabase
    PG->>PG: CREATE DATABASE metabaseappdb
    PG->>PG: GRANT permissions
    PG-->>-BI: Metabase DB ready
    
    BI->>+PG: Create superset user & database  
    PG->>PG: CREATE USER superset
    PG->>PG: CREATE DATABASE superset
    PG->>PG: GRANT permissions
    PG-->>-BI: Superset DB ready
```

#### 3. **Генерация конфигураций**
```mermaid
sequenceDiagram
    participant BI as BI-Tools Module
    participant TF as Terraform
    participant FS as File System
    
    BI->>+TF: Process superset_config.py.tmpl
    TF->>TF: templatefile() with secret_key
    TF->>+FS: Write env/superset_config.py
    FS-->>-TF: Configuration file created
    TF-->>-BI: Configuration ready
    
    BI->>BI: Generate user lists from locals
    BI->>BI: Apply fallback logic for credentials
```

#### 4. **Развертывание контейнеров**
```mermaid
sequenceDiagram
    participant BI as BI-Tools Module
    participant Docker as Docker Engine
    participant MB as Metabase Container
    participant SS as Superset Container
    
    BI->>+Docker: Pull metabase image
    Docker-->>-BI: Image ready
    
    BI->>+Docker: Deploy Metabase container
    Docker->>MB: Start container with PG connection
    MB->>MB: Health check (curl /api/health)
    MB-->>-BI: Metabase healthy
    
    BI->>+Docker: Pull superset image  
    Docker-->>-BI: Image ready
    
    BI->>+Docker: Deploy Superset container
    Docker->>SS: Start with config volume mount
    SS->>SS: Health check (curl /health)
    SS-->>-BI: Superset healthy
```

#### 5. **Установка драйверов и инициализация**
```mermaid
sequenceDiagram
    participant BI as BI-Tools Module
    participant SS as Superset Container
    participant CH as ClickHouse
    
    BI->>+SS: Install ClickHouse drivers
    SS->>SS: pip install clickhouse-connect
    SS->>SS: pip install clickhouse-driver
    SS-->>-BI: Drivers installed
    
    BI->>+SS: Restart container
    SS->>SS: Reload with new libraries
    SS-->>-BI: Container restarted
    
    BI->>+SS: Initialize Superset
    SS->>SS: superset db upgrade
    SS->>SS: superset init
    SS->>SS: superset fab create-admin
    SS-->>-BI: Admin user created
    
    BI->>+SS: Test ClickHouse connection
    SS->>+CH: SELECT 1
    CH-->>-SS: Connection OK
    SS-->>-BI: ClickHouse integration ready
```

#### 6. **API автоматизация пользователей**
```mermaid
sequenceDiagram
    participant BI as BI-Tools Module
    participant MB as Metabase
    participant SS as Superset
    
    BI->>+MB: Wait for API readiness
    MB-->>-BI: /api/health status=ok
    
    BI->>+MB: Setup or login via API
    MB->>MB: Create session token
    MB-->>-BI: Session established
    
    BI->>+MB: Create additional users
    MB->>MB: POST /api/user for each user
    MB-->>-BI: Users created
    
    BI->>+SS: Create regular users via CLI
    SS->>SS: superset fab create-user
    SS-->>-BI: Users created
```

### Ключевые особенности архитектуры

#### **Модульность и переиспользование**
- Модуль `bi-tools` переиспользует существующий PostgreSQL из модуля `postgres`
- Общая Docker-сеть обеспечивает связность между сервисами
- Конфигурации генерируются динамически через Terraform templates

#### **Безопасность**
- Секретные ключи передаются через переменные Terraform
- Пароли БД управляются централизованно через fallback-логику
- Конфигурационные файлы монтируются в контейнеры как read-only

#### **Автоматизация**
- Полная автоматизация через `null_resource` provisioners
- API-инициализация пользователей без ручного вмешательства
- Health checks обеспечивают корректный порядок запуска

#### **Расширяемость**
- Поддержка нескольких BI-инструментов через feature flags
- Легкое добавление новых пользователей через переменные
- Модульная архитектура позволяет независимое масштабирование

---

## Этап 1: Реализация модуля bi-tools

### 1.1 Создание модульной архитектуры

Создан модуль `bi-tools` в структуре:
```
base-infra/ch_with_storage/modules/bi-tools/
├── main.tf
├── variables.tf
├── locals.tf
├── outputs.tf
└── samples/
    └── superset_config.py.tmpl
```

### 1.2 Ключевые особенности модуля

- **Переиспользование PostgreSQL**: Модуль использует существующий модуль [`postgres`](../base-infra/ch_with_storage/modules/postgres/), что обеспечивает согласованность с другими сервисами (Airflow)
- **Двухуровневая система флагов**: 
  - `enable_bi_tools` — master switch для всего модуля
  - `enable_metabase/enable_superset` — тонкая настройка отдельных сервисов внутри модуля
- **Поддержка обоих BI-инструментов**: Superset и Metabase развертываются опционально через флаги
- **Автоматическая инициализация**: Создание пользователей и настройка через API
- **Интеграция с ClickHouse**: Автоматическая установка драйверов ClickHouse в Superset

### 1.3 Интеграция в основной пайплайн

Модуль `bi-tools` интегрирован в основную инфраструктуру через стандартные механизмы Terraform:

- **Конфигурационные переменные**: Добавлены в [`variables.tf`](../base-infra/ch_with_storage/variables.tf#L400-L411) для управления флагами и секретными ключами
- **Модульная интеграция**: Подключен в [`main.tf`](../base-infra/ch_with_storage/main.tf#L294-L325) с зависимостью от модуля PostgreSQL
- **Условное развертывание**: Использует `count` для активации только при `enable_bi_tools = true`
- **Передача параметров**: Наследует учетные данные и сетевые настройки от родительского модуля

Полная реализация модуля доступна по ссылке: [`modules/bi-tools/`](../base-infra/ch_with_storage/modules/bi-tools/)

**Результат деплоя модуля bi-tools:**
<img src="../screenshots/hw18_bi-integration/01_bi_tools_module_integration.png" width="600" alt="Деплой bi-tools">

---

## Этап 2: Создание Kafka топиков и ClickHouse таблиц

### 2.1 Создание Kafka топика через DAG

Используем автоматизированный DAG `kafka_topic_create` для создания единого топика `sensors` с полной схемой.

1. Открываем Airflow UI: `http://localhost:8080`
2. Находим DAG `kafka_topic_create` и нажимаем "Trigger DAG"
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

**Результат создания топика sensors:**
<img src="../screenshots/hw18_bi-integration/03_kafka_topic_locations_creation.png" width="1000" alt="Создание топика sensors">

### 2.2 Создание ClickHouse таблиц через DAG

Используем DAG `kafka_to_ch_table_create` для автоматического создания полной архитектуры таблиц.

#### Таблица измерений (ReplicatedMergeTree)
1. Запускаем DAG `kafka_to_ch_table_create`
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
    "timestamp": "DateTime",
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

**Результат создания таблицы sensors:**
<img src="../screenshots/hw18_bi-integration/05_ch_table_sensors_creation.png" width="1000" alt="Создание таблиц sensors">

DAG автоматически создаст:
- **Kafka Engine таблицы** для чтения из топиков
- **ReplicatedMergeTree локальные таблицы** для хранения данных  
- **Materialized View** для перекачки данных из Kafka в локальные таблицы
- **Distributed таблицы** для доступа ко всему кластеру
- **Проекции и индексы** для оптимизации запросов

### 2.3 Проверка структуры таблиц

**Команды для проверки:**
```sql
-- Описание ReplicatedMergeTree таблиц
DESCRIBE TABLE raw.sensors_measurements_local;
DESCRIBE TABLE ods.sensors_locations_local;
```

**Структура ReplicatedMergeTree таблиц:**
<img src="../screenshots/hw18_bi-integration/06_ch_table_structure_replicated.png" width="800" alt="Структура ReplicatedMergeTree таблиц">

```sql
-- Описание Distributed таблиц  
DESCRIBE TABLE raw.sensors_measurements;
DESCRIBE TABLE ods.sensors_locations;
```

**Структура Distributed таблиц:**
<img src="../screenshots/hw18_bi-integration/07_ch_table_structure_distributed.png" width="800" alt="Структура Distributed таблиц">

### 2.4 Запуск продьюсера данных

После создания таблиц необходимо запустить DAG для заполнения Kafka топика данными из S3.

#### Запуск пайплайна sensors_pipeline

1. Откройте Airflow UI: `http://localhost:8080`
2. Найдите DAG `sensors_pipeline`
3. Включите DAG, переключив toggle в позицию ON
4. Нажмите "Trigger DAG" для первого запуска. Вы можете указать параметры в "Configuration JSON", например:

```json
{
  "use_real_data": true,
  "batch_size": 5000,
  "max_files_per_run": 5
}
```

**Результат запуска продьюсера `sensors_pipeline`:**
<img src="../screenshots/hw18_bi-integration/10_producers_monitoring.png" width="1000" alt="Мониторинг продьюсера">

DAG `sensors_pipeline` будет выполняться каждый час, инкрементально загружая новые данные из S3, используя watermark, хранящийся в Airflow Variables. Параметр `max_files_per_run` ограничивает количество обрабатываемых файлов за один запуск для предотвращения чрезмерного потребления ресурсов.

### 2.5 Проверка данных

#### Данные в Kafka топиках
```bash
# Проверяем доступные топики
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Проверяем измерения
docker exec kafka kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic sensors_measurements_1min \
  --from-beginning --max-messages 5

# Проверяем метаданные
docker exec kafka kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic sensors_locations_5min \
  --from-beginning --max-messages 5
```

**Данные измерений в Kafka:**
<img src="../screenshots/hw18_bi-integration/11_kafka_data_measurements.png" width="800" alt="Данные measurements в Kafka">

**Данные метаданных в Kafka:**
<img src="../screenshots/hw18_bi-integration/12_kafka_data_locations.png" width="800" alt="Данные locations в Kafka">

#### Данные в ClickHouse Distributed таблицах
```sql
-- Проверка измерений
SELECT 
    timestamp,
    sensor_id,
    temperature, 
    humidity,
    P2 as pm25
FROM raw.sensors_measurements
ORDER BY timestamp DESC
LIMIT 10;

-- Проверка метаданных
SELECT 
    timestamp,
    sensor_id,
    sensor_type,
    lat, lon
FROM ods.sensors_locations  
ORDER BY timestamp DESC
LIMIT 10;

-- Джойн для полной картины
SELECT 
    m.timestamp,
    l.sensor_type,
    l.lat, l.lon,
    m.temperature,
    m.P2 as pm25_concentration
FROM raw.sensors_measurements m
JOIN ods.sensors_locations l ON (
    m.sensor_id = l.sensor_id
    AND m.timestamp BETWEEN l.timestamp - INTERVAL 5 MINUTE 
                         AND l.timestamp + INTERVAL 5 MINUTE
)
ORDER BY m.timestamp DESC
LIMIT 10;
```

**Сравнение данных Kafka vs ClickHouse:**
<img src="../screenshots/hw18_bi-integration/13_kafka_vs_clickhouse_data.png" width="800" alt="Сравнение данных Kafka vs ClickHouse">

---

## Этап 3: Подключение к ClickHouse

### 3.1 Настройка драйверов ClickHouse

В модуле автоматически устанавливаются необходимые драйверы:
```bash
docker exec superset pip install "clickhouse-connect>=0.6.8" "clickhouse-driver"
```

### 3.2 Настройка подключения

Подключение к ClickHouse настраивается через Superset UI:
- **Database**: `ClickHouse`
- **SQLAlchemy URI**: `clickhousedb://bi_user:password@clickhouse-01:8123/default`
- **Test Connection**: Проверка доступности ClickHouse

![Настройка подключения к ClickHouse](../screenshots/hw18_bi-integration/clickhouse_connection_setup.png)
*Конфигурация подключения к ClickHouse в Superset*

![Тестирование подключения](../screenshots/hw18_bi-integration/clickhouse_connection_test.png)
*Успешное тестирование подключения к ClickHouse*

---

## Этап 4: Создание дашборда с 5 визуализациями

### 4.1 Структура дашборда

Создан дашборд **"Environmental Sensors Real-Time Analytics"** с пятью различными типами визуализаций, задействующими посекундные данные:

#### 1. **Real-Time Temperature & Humidity Trends** (Mixed Time Series)
- **Тип**: Двухосевой линейный график с Time Grain
- **Источник**: `raw.sensors_measurements` + `ods.sensors_locations` (Virtual Dataset)
- **Метрики**: `AVG(temperature)`, `AVG(humidity)`
- **Time Grain**: `PT1M` (1 minute) для near real-time
- **Описание**: Real-time тренды температуры и влажности с минутной агрегацией

#### 2. **Geographic Air Quality Map** (Deck.gl Scatterplot)
- **Тип**: Географическая точечная карта
- **Источник**: Virtual Dataset с джойном таблиц
- **Координаты**: `lat`, `lon`
- **Размер точек**: `AVG(P2)` (концентрация PM2.5)
- **Цвет**: `AVG(P1)` (концентрация PM1.0)
- **Описание**: Геопространственное отображение качества воздуха в реальном времени

#### 3. **Sensor Types Distribution** (Pie Chart)
- **Тип**: Круговая диаграмма
- **Источник**: `ods.sensors_locations`
- **Метрики**: `COUNT(DISTINCT sensor_id)`
- **Группировка**: `sensor_type`
- **Описание**: Распределение активных сенсоров по типам (BME280, SDS011, DHT22, etc.)

#### 4. **Hourly Air Quality Index Heatmap** (Heatmap)
- **Тип**: Тепловая карта с Time Grain
- **Источник**: Virtual Dataset с синтетическим timestamp
- **Оси**: `sensor_type` × `hour_bucket`
- **Time Grain**: `PT1H` (1 hour)
- **Метрики**: `AVG(P2)` (Air Quality Index на основе PM2.5)
- **Описание**: Интенсивность загрязнения воздуха по типам сенсоров и часам суток

#### 5. **Pressure vs Temperature Correlation** (Scatter Plot)
- **Тип**: Точечная диаграмма с корреляцией
- **Источник**: `raw.sensors_measurements` (последние 24 часа)
- **Оси**: `temperature` (X) vs `pressure` (Y)
- **Размер точек**: `humidity`
- **Цвет**: `sensor_type`
- **Описание**: Корреляция между температурой и давлением для разных типов сенсоров

### 4.2 Возможности Near Real Time (NRT)

Благодаря использованию **посекундных данных** из Environmental Sensors, дашборд поддерживает:
- **Real-time обновления**: автообновление каждую минуту
- **Time grain фильтры**: от секунд (`PT1S`) до месяцев (`P1M`)
- **Геопространственные фильтры**: по координатам, регионам и типам сенсоров
- **Cross-filtering**: взаимосвязанная фильтрация между географическими и временными чартами
- **Environmental alerts**: автоматические алерты при превышении порогов качества воздуха

---

## Этап 4: Пошаговая инструкция создания дашборда

### 4.1 Подготовка: Подключение к ClickHouse

#### Шаг 1: Создание подключения к базе данных

1. Откройте Superset UI по адресу http://localhost:8088
2. Войдите с учетными данными администратора (super_user_name/password)
3. Перейдите в меню **Settings** → **Database Connections**
4. Нажмите **+ Database** для создания нового подключения

**Параметры подключения:**
- **Database**: `ClickHouse`
- **Display Name**: `ClickHouse COVID-19 Data`
- **SQLAlchemy URI**: `clickhousedb://bi_user:password@clickhouse-01:8123/default`
  
  ![Создание подключения к ClickHouse](../screenshots/hw18_bi-integration/01_database_connection_setup.png)
  *Настройка подключения к ClickHouse в Superset*

5. Нажмите **Test Connection** для проверки
6. При успешном тестировании нажмите **Connect**

![Тестирование подключения](../screenshots/hw18_bi-integration/02_database_connection_test.png)
*Успешное тестирование подключения к ClickHouse*

### 4.2 Создание датасетов

#### Шаг 2.1: Датасет для измерений сенсоров (1-минутные данные)

1. Перейдите в **Data** → **Datasets**
2. Нажмите **+ Dataset**
3. Выберите созданную ClickHouse базу данных
4. Выберите схему `raw`
5. Выберите таблицу `sensors_measurements`

![Создание датасета измерений](../screenshots/hw18_bi-integration/03_dataset_measurements_creation.png)
*Создание датасета для анализа измерений Environmental Sensors*

#### Шаг 2.2: Датасет для метаданных сенсоров (5-минутные данные)

1. Повторите процедуру для второго датасета
2. Выберите схему `ods`
3. Выберите таблицу `sensors_locations`

![Создание датасета метаданных](../screenshots/hw18_bi-integration/04_dataset_locations_creation.png)
*Создание датасета для метаданных сенсоров Environmental Sensors*

#### Шаг 2.3: Virtual Dataset с расширенной временной логикой

Создадим Virtual Dataset, который добавляет timestamp-поле для более точной фильтрации:

1. Перейдите в **Data** → **Datasets** 
2. Нажмите **+ Dataset**
3. Выберите **Write a custom SQL query instead**
4. Введите SQL-запрос с Jinja-шаблонизацией:

```sql
SELECT 
    m.timestamp,
    l.sensor_id,
    l.sensor_type,
    l.lat,
    l.lon,
    l.location,
    m.temperature,
    m.humidity, 
    m.pressure,
    m.P1,
    m.P2,
    -- Создаем временные bucket'ы для различных Time Grain
    toStartOfMinute(m.timestamp) as minute_bucket,
    toStartOfHour(m.timestamp) as hour_bucket,
    toStartOfDay(m.timestamp) as day_bucket,
    toStartOfWeek(m.timestamp) as week_bucket,
    toStartOfMonth(m.timestamp) as month_bucket,
    -- Вычисляем Air Quality Index на основе PM2.5
    CASE 
        WHEN m.P2 <= 12 THEN 'Good'
        WHEN m.P2 <= 35 THEN 'Moderate'
        WHEN m.P2 <= 55 THEN 'Unhealthy for Sensitive Groups'
        WHEN m.P2 <= 150 THEN 'Unhealthy'
        WHEN m.P2 <= 250 THEN 'Very Unhealthy'
        ELSE 'Hazardous'
    END as aqi_category,
    -- Скользящие средние для сглаживания
    avg(m.temperature) OVER (
        PARTITION BY l.sensor_id
        ORDER BY m.timestamp
        ROWS BETWEEN 59 PRECEDING AND CURRENT ROW
    ) as temp_1hour_avg,
    avg(m.P2) OVER (
        PARTITION BY l.sensor_id
        ORDER BY m.timestamp
        ROWS BETWEEN 59 PRECEDING AND CURRENT ROW  
    ) as pm25_1hour_avg
FROM raw.sensors_measurements m
JOIN ods.sensors_locations l ON (
    m.sensor_id = l.sensor_id
    AND m.timestamp BETWEEN l.timestamp - INTERVAL 5 MINUTE 
                         AND l.timestamp + INTERVAL 5 MINUTE
)
WHERE m.timestamp >= {{ "'" + from_dttm + "'" }}
  AND m.timestamp <= {{ "'" + to_dttm + "'" }}
{% if filter_values('sensor_type') %}
  AND l.sensor_type IN {{ filter_values('sensor_type') | where_in }}
{% endif %}
{% if filter_values('location') %}
  AND l.location IN {{ filter_values('location') | where_in }}
{% endif %}
ORDER BY m.timestamp DESC, m.P2 DESC
```

![Virtual Dataset с временной логикой](../screenshots/hw18_bi-integration/05_virtual_dataset_timestamp.png)
*Создание Virtual Dataset с синтетическим timestamp для Time grain фильтрации*

### 4.3 Создание чартов

#### Шаг 3.1: Global Daily New Cases Trend (Line Chart)

1. Перейдите в **Charts** → **+ Chart**
2. Выберите датасет `raw.covid_new_cases`
3. Выберите тип визуализации **Line Chart**

**Настройки:**
- **Metrics**: 
  - `SUM(new_confirmed)` → Label: `Total New Cases`
- **Time Column**: `date`
- **Time Grain**: `P1D` (1 day)
- **Time Range**: `Last 30 days`

![Создание линейного графика](../screenshots/hw18_bi-integration/06_chart_line_creation.png)
*Настройка линейного графика глобального тренда новых случаев*

**Дополнительные настройки (вкладка Customize):**
- **Chart Title**: `Global Daily New Cases Trend`
- **Y Axis Title**: `New Cases`
- **X Axis Title**: `Date`
- **Line Style**: Smooth

![Результат линейного графика](../screenshots/hw18_bi-integration/07_chart_line_result.png)
*Готовый линейный график с трендом новых случаев COVID-19*

#### Шаг 3.2: Top 10 Countries by Cumulative Cases (Bar Chart)

1. Создайте новый чарт с типом **Bar Chart**
2. Выберите датасет `ods.covid_cumulative`

**Настройки:**
- **Metrics**: `MAX(cumulative_confirmed)` → Label: `Total Cases`
- **Columns**: `country_name`
- **Row Limit**: `10`
- **Sort By**: `Total Cases DESC`

![Создание столбчатой диаграммы](../screenshots/hw18_bi-integration/08_chart_bar_creation.png)
*Настройка столбчатой диаграммы для топ-10 стран*

**Настройки цвета (Customize → Color Scheme):**
- Выберите палитру `supersetColors`
- Enable **Custom Color Palette**

![Результат столбчатой диаграммы](../screenshots/hw18_bi-integration/09_chart_bar_result.png)
*Топ-10 стран по кумулятивным случаям COVID-19*

#### Шаг 3.3: Real-time Cases by Region (Pie Chart)

1. Создайте чарт типа **Pie Chart**
2. Используйте датасет `raw.covid_new_cases`

**Настройки:**
- **Metrics**: `SUM(new_confirmed)` → Label: `New Cases (24h)`
- **Columns**: `country_name` 
- **Time Range**: `Last 24 hours`
- **Row Limit**: `15`

![Создание круговой диаграммы](../screenshots/hw18_bi-integration/10_chart_pie_creation.png)
*Настройка круговой диаграммы для распределения по регионам*

**Настройки отображения:**
- **Show Labels**: Yes
- **Show Legend**: Yes
- **Number Format**: `,d` (comma separated)

![Результат круговой диаграммы](../screenshots/hw18_bi-integration/11_chart_pie_result.png)
*Распределение новых случаев по регионам за последние 24 часа*

#### Шаг 3.4: Weekly Moving Average - Deaths vs Recoveries (Mixed Chart)

1. Создайте чарт типа **Mixed Time Series**
2. Используйте датасет `ods.covid_cumulative`

**Настройки для левой оси (Deaths):**
- **Metrics**: `AVG(cumulative_deceased)` → Label: `Weekly Avg Deaths`
- **Time Column**: `date`
- **Time Grain**: `P7D` (7 days)
- **Chart Type**: Line
- **Color**: `#FF4136` (красный)

**Настройки для правой оси (Recoveries):**
- **Metrics**: `AVG(cumulative_recovered)` → Label: `Weekly Avg Recoveries`  
- **Chart Type**: Line
- **Color**: `#2ECC40` (зеленый)
- **Y Axis**: `Right Axis`

![Создание смешанного графика](../screenshots/hw18_bi-integration/12_chart_mixed_creation.png)
*Настройка смешанного графика для сравнения трендов*

![Результат смешанного графика](../screenshots/hw18_bi-integration/13_chart_mixed_result.png)
*Сравнение недельных скользящих средних смертей и выздоровлений*

#### Шаг 3.5: Cases Intensity Heatmap (Heatmap)

1. Создайте чарт типа **Heatmap**
2. Используйте Virtual Dataset с timestamp

**Настройки:**
- **Metrics**: `AVG(new_confirmed)` → Label: `Avg Daily Cases`
- **Rows**: `country_name` (ограничить до 20 стран)
- **Columns**: `month_bucket` (из Virtual Dataset)
- **Time Range**: `Last 6 months`

![Создание тепловой карты](../screenshots/hw18_bi-integration/14_chart_heatmap_creation.png)
*Настройка тепловой карты интенсивности случаев*

**Настройки цвета:**
- **Color Scheme**: `Reds`
- **Normalize Across**: `heatmap`
- **Number Format**: `.1f`

![Результат тепловой карты](../screenshots/hw18_bi-integration/15_chart_heatmap_result.png)
*Тепловая карта интенсивности случаев по странам и месяцам*

### 4.4 Сборка дашборда

#### Шаг 4.1: Создание дашборда

1. Перейдите в **Dashboards** → **+ Dashboard**
2. Введите название: `COVID-19 Analytics Dashboard`
3. Нажмите **Save**

![Создание дашборда](../screenshots/hw18_bi-integration/16_dashboard_creation.png)
*Создание нового дашборда COVID-19 Analytics*

#### Шаг 4.2: Добавление чартов

1. Нажмите **Edit Dashboard**
2. Перейдите на вкладку **Charts** в правой панели
3. Перетащите созданные чарты на дашборд в следующем порядке:

**Макет дашборда:**
```
┌─────────────────────────────────────────────────────────────┐
│ [Global Daily New Cases Trend - полная ширина]             │
├─────────────────────────────────────────────────────────────┤
│ [Top 10 Countries] │ [Real-time Cases by Region]            │
├─────────────────────────────────────────────────────────────┤
│ [Weekly Moving Average - полная ширина]                     │
├─────────────────────────────────────────────────────────────┤
│ [Cases Intensity Heatmap - полная ширина]                   │
└─────────────────────────────────────────────────────────────┘
```

![Добавление чартов в дашборд](../screenshots/hw18_bi-integration/17_dashboard_chart_addition.png)
*Процесс добавления чартов в дашборд*

#### Шаг 4.3: Настройка фильтров

1. В режиме редактирования добавьте **Filter Box**
2. Настройте общие фильтры:

**Time Range Filter:**
- **Filter Type**: `Time Range`
- **Default**: `Last 7 days`

**Country Filter:**  
- **Filter Type**: `Filter Select`
- **Column**: `country_name`
- **Multiple Selection**: Yes

![Настройка фильтров](../screenshots/hw18_bi-integration/18_dashboard_filters_setup.png)
*Добавление интерактивных фильтров в дашборд*

#### Шаг 4.4: Финализация дашборда

1. Нажмите **Save** для сохранения дашборда
2. Выйдите из режима редактирования
3. Протестируйте интерактивность фильтров

![Финальный дашборд](../screenshots/hw18_bi-integration/19_dashboard_final_result.png)
*Финальный вид дашборда COVID-19 Analytics с 5 визуализациями*

### 4.5 Демонстрация Virtual Dataset и Jinja

#### Virtual Dataset: расширенные возможности

Созданный Virtual Dataset демонстрирует:

1. **Синтетический timestamp**: преобразование date в datetime для Time grain
2. **Временные окна**: агрегации по часам, дням, неделям, месяцам  
3. **Скользящие окна**: 7-дневные скользящие суммы
4. **Jinja-шаблонизация**: динамические фильтры по датам и странам

**Пример использования Jinja для Environmental Sensors:**
```sql
-- Динамический фильтр по timestamp из UI с посекундной точностью
WHERE m.timestamp >= {{ "'" + from_dttm + "'" }}
  AND m.timestamp <= {{ "'" + to_dttm + "'" }}

-- Условный фильтр по типам сенсоров (только если выбраны в UI)
{% if filter_values('sensor_type') %}
  AND l.sensor_type IN {{ filter_values('sensor_type') | where_in }}
{% endif %}

-- Условный фильтр по географическим локациям
{% if filter_values('location') %}
  AND l.location IN {{ filter_values('location') | where_in }}
{% endif %}

-- Динамический лимит на основе UI параметров
LIMIT {{ row_limit or 1000 }}
```

![Virtual Dataset с Jinja](../screenshots/hw18_bi-integration/20_virtual_dataset_jinja.png)
*Использование Jinja-шаблонов в Virtual Dataset*

#### Преимущества Virtual Dataset для Environmental Sensors:

1. **Посекундная точность**: поддержка Time Grain от секунд до месяцев
2. **Геопространственные джойны**: автоматическое объединение измерений с координатами
3. **Real-time агрегация**: скользящие средние и Air Quality Index в реальном времени
4. **Polars оптимизация**: pushdown фильтры ускоряют выполнение запросов
5. **Flexible параметризация**: динамические фильтры по сенсорам, локациям и времени

![Time Grain фильтрация](../screenshots/hw18_bi-integration/21_time_grain_filtering.png)  
*Демонстрация Time Grain фильтрации в дашборде*

---

## Проверка результатов

### 4.1 Подготовка к развертыванию

#### Генерация секретного ключа для Superset

Перед развертыванием необходимо сгенерировать секретный ключ для Superset:

```bash
# Генерация секретного ключа
openssl rand -base64 32
```

#### Настройка переменных

**Способ 1: Через terraform.tfvars**

Добавьте в файл `terraform.tfvars`:
```hcl
enable_bi_tools = true
enable_superset = true
enable_metabase = true  # опционально
superset_secret_key = "YOUR_GENERATED_KEY_HERE"
```

**Способ 2: Через переменные окружения**

```bash
export TF_VAR_enable_bi_tools=true
export TF_VAR_enable_superset=true
export TF_VAR_superset_secret_key="YOUR_GENERATED_KEY_HERE"
```

### 4.2 Развертывание

```bash
cd base-infra/ch_with_storage
terraform apply
```

### 4.3 Доступ к сервисам

- **Superset**: http://localhost:8088
- **Metabase**: http://localhost:3000 (опционально)
- **Учетные данные**: используются из super_user_name/password

### 4.4 Валидация дашборда

1. **Подключение к ClickHouse**: тестируется автоматически при развертывании
2. **Актуальность данных**: визуализации отображают свежие данные из Kafka
3. **Интерактивность**: работают фильтры по времени и регионам
4. **Производительность**: запросы выполняются быстро благоря distributed-таблицам

![Environmental Sensors Dashboard - общий вид](../screenshots/hw18_bi-integration/dashboard_overview.png)
*Общий вид дашборда Environmental Sensors Real-Time Analytics с 5 визуализациями*

![Time Series - температура и влажность](../screenshots/hw18_bi-integration/chart_timeseries_temp_humidity.png)
*Real-time тренды температуры и влажности с минутной точностью*

![Geographic Map - качество воздуха](../screenshots/hw18_bi-integration/chart_geographic_air_quality.png)
*Географическая карта качества воздуха с концентрацией PM1.0 и PM2.5*

![Pie Chart - типы сенсоров](../screenshots/hw18_bi-integration/chart_pie_sensor_types.png)
*Распределение активных сенсоров по типам (BME280, SDS011, DHT22, etc.)*

![Heatmap - качество воздуха по часам](../screenshots/hw18_bi-integration/chart_heatmap_hourly_aqi.png)
*Тепловая карта качества воздуха по типам сенсоров и часам суток*

![Scatter Plot - корреляция температуры и давления](../screenshots/hw18_bi-integration/chart_scatter_temp_pressure.png)
*Корреляция между температурой и атмосферным давлением для разных типов сенсоров*

![Интерактивность дашборда](../screenshots/hw18_bi-integration/dashboard_interactivity.png)
*Демонстрация интерактивных фильтров и cross-filtering между чартами*

---

## Компетенции

В результате выполнения задания продемонстрированы следующие компетенции:

- [x] **Развертывание Apache Superset** с автоматической конфигурацией
- [x] **Интеграция с ClickHouse** через специализированные драйверы
- [x] **Создание разнообразных визуализаций** (line, bar, pie, heatmap)
- [x] **Работа с real-time данными** из Kafka streams
- [x] **Модульная архитектура Terraform** для BI-инструментов
- [x] **Экспорт/импорт дашбордов** в стандартном формате Superset

---

## Результат

✅ **Успешно развернут и настроен Apache Superset**  
✅ **Подключен Superset к ClickHouse с тестированием соединения**  
✅ **Создан дашборд с 5 различными типами визуализаций**  
✅ **Все визуализации корректно отображают актуальные данные**  
✅ **Дашборд готов для импорта в другие инстансы Superset**  

Модуль bi-tools может быть легко переиспользован в других проектах благодаря модульной архитектуре и интеграции с существующей инфраструктурой PostgreSQL.
