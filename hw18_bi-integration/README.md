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

### Источник данных: COVID-19 Open-Data

Для создания дашборда используются данные из **COVID-19 Open-Data датасета**, который был интегрирован в [Homework #17: Интеграция с Apache Kafka](../hw17_kafka-integration/README.md) через потоковую обработку Apache Kafka.

**Описание датасета:**
- **Источник**: Google Cloud Storage (COVID-19 Open-Data)
- **Содержание**: Глобальные данные о пандемии COVID-19 по странам и датам
- **Обновление**: Данные поступают через Kafka топики с периодичностью 1 и 5 минут
- **Назначение**: Анализ эпидемиологических данных в реальном времени

### Архитектура данных в ClickHouse

Данные организованы в трёхуровневой архитектуре DWH:

#### **1. Уровень Kafka Integration (`otus_kafka` schema)**
- **`otus_kafka.covid_new_cases_kafka`** — Kafka Engine таблица для топика `covid_new_cases_1min`
- **`otus_kafka.covid_cumulative_kafka`** — Kafka Engine таблица для топика `covid_cumulative_data_5min`

#### **2. Уровень Raw Data (`raw` schema)**
- **`raw.covid_new_cases_local`** — ReplicatedMergeTree таблица (локальная)
- **`raw.covid_new_cases`** — Distributed таблица 
- **`raw.covid_new_cases_mv`** — Materialized View (Kafka → Local)

**Структура данных новых случаев:**
```sql
date            Date        -- Дата в формате YYYY-MM-DD
location_key    String      -- Код страны/региона  
new_confirmed   Int64       -- Новые подтвержденные случаи
new_deceased    Int64       -- Новые случаи смерти
country_name    String      -- Полное название страны
```

#### **3. Уровень ODS - Operational Data Store (`ods` schema)**
- **`ods.covid_cumulative_local`** — ReplicatedMergeTree таблица (локальная)
- **`ods.covid_cumulative`** — Distributed таблица
- **`ods.covid_cumulative_mv`** — Materialized View (Kafka → Local)

**Структура кумулятивных данных:**
```sql
date                   Date     -- Дата в формате YYYY-MM-DD
location_key           String   -- Код страны/региона
cumulative_confirmed   Int64    -- Общее количество подтвержденных случаев
cumulative_deceased    Int64    -- Общее количество смертей
cumulative_recovered   Int64    -- Общее количество выздоровевших
country_name           String   -- Полное название страны
```

### Используемые таблицы в дашборде

Для визуализаций используются **Distributed таблицы**, обеспечивающие доступ ко всем данным кластера:

1. **`raw.covid_new_cases`** — для анализа новых случаев в реальном времени
2. **`ods.covid_cumulative`** — для анализа накопительной статистики и трендов

### Потоковая обработка данных

- **Периодичность поступления**: 
  - Новые случаи: каждую минуту (8 сообщений за батч)
  - Кумулятивные данные: каждые 5 минут (5 сообщений за батч)
- **Real-time обновление**: Данные в дашборде обновляются в режиме реального времени через Materialized Views
- **Географический охват**: Глобальные данные по всем странам с фильтрацией по регионам

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
        S --> U[covid_new_cases_1min_distributed]
        S --> V[covid_cumulative_data_5min_distributed]
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

---

## Этап 2: Подключение к ClickHouse

### 2.1 Настройка драйверов ClickHouse

В модуле автоматически устанавливаются необходимые драйверы:
```bash
docker exec superset pip install "clickhouse-connect>=0.6.8" "clickhouse-driver"
```

### 2.2 Настройка подключения

Подключение к ClickHouse настраивается через Superset UI:
- **Database**: `ClickHouse`
- **SQLAlchemy URI**: `clickhousedb://bi_user:password@clickhouse-01:8123/default`
- **Test Connection**: Проверка доступности ClickHouse

![Настройка подключения к ClickHouse](../screenshots/hw18_bi-integration/clickhouse_connection_setup.png)
*Конфигурация подключения к ClickHouse в Superset*

![Тестирование подключения](../screenshots/hw18_bi-integration/clickhouse_connection_test.png)
*Успешное тестирование подключения к ClickHouse*

---

## Этап 3: Создание дашборда с 5 визуализациями

### 3.1 Структура дашборда

Создан дашборд **"COVID-19 Analytics Dashboard"** с пятью различными типами визуализаций:

#### 1. **Global Daily New Cases Trend** (Line Chart)
- **Тип**: Линейный график
- **Источник**: `covid_new_cases_1min_distributed`
- **Метрики**: `sum_new_cases`
- **Период**: Last 30 days
- **Описание**: Глобальный тренд ежедневных новых случаев COVID-19 на основе 1-минутных агрегаций

#### 2. **Top 10 Countries by Cumulative Cases** (Bar Chart)
- **Тип**: Столбчатая диаграмма
- **Источник**: `covid_cumulative_data_5min_distributed`
- **Метрики**: `sum_cumulative_cases`
- **Группировка**: `country_name`
- **Описание**: Топ 10 стран по общему количеству случаев COVID-19

#### 3. **Real-time Cases by Region (Last 24h)** (Pie Chart)
- **Тип**: Круговая диаграмма
- **Источник**: `covid_new_cases_1min_distributed`
- **Метрики**: `sum_new_cases`
- **Период**: Last 24 hours
- **Описание**: Распределение новых случаев по регионам за последние 24 часа

#### 4. **Weekly Moving Average - Deaths vs Recoveries** (Line Chart)
- **Тип**: Многосерийный линейный график
- **Источник**: `covid_cumulative_data_5min_distributed`
- **Метрики**: `sum_deaths`, `sum_recovered`
- **Сглаживание**: 7-дневное скользящее среднее
- **Описание**: Сравнение недельных скользящих средних смертей и выздоровлений

#### 5. **Heatmap: Cases Intensity by Country and Month** (Heatmap)
- **Тип**: Тепловая карта
- **Источник**: `covid_cumulative_data_5min_distributed`
- **Метрики**: `avg_new_cases`
- **Оси**: `country_code` × `date` (по месяцам)
- **Описание**: Интенсивность случаев COVID-19 по странам и месяцам

### 3.2 Возможности Near Real Time (NRT)

Благодаря использованию поминутных данных из Kafka, дашборд поддерживает:
- **Real-time обновления**: автообновление каждые 5 минут
- **Time grain фильтры**: от минут до месяцев
- **Фильтры по странам**: интерактивная фильтрация по регионам
- **Cross-filtering**: взаимосвязанная фильтрация между чартами

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

#### Шаг 2.1: Датасет для новых случаев (1-минутные данные)

1. Перейдите в **Data** → **Datasets**
2. Нажмите **+ Dataset**
3. Выберите созданную ClickHouse базу данных
4. Выберите схему `raw`
5. Выберите таблицу `covid_new_cases`

![Создание датасета новых случаев](../screenshots/hw18_bi-integration/03_dataset_new_cases_creation.png)
*Создание датасета для анализа новых случаев COVID-19*

#### Шаг 2.2: Датасет для кумулятивных данных (5-минутные данные)

1. Повторите процедуру для второго датасета
2. Выберите схему `ods`
3. Выберите таблицу `covid_cumulative`

![Создание датасета кумулятивных данных](../screenshots/hw18_bi-integration/04_dataset_cumulative_creation.png)
*Создание датасета для кумулятивной статистики COVID-19*

#### Шаг 2.3: Virtual Dataset с расширенной временной логикой

Создадим Virtual Dataset, который добавляет timestamp-поле для более точной фильтрации:

1. Перейдите в **Data** → **Datasets** 
2. Нажмите **+ Dataset**
3. Выберите **Write a custom SQL query instead**
4. Введите SQL-запрос с Jinja-шаблонизацией:

```sql
SELECT 
    date,
    location_key,
    country_name,
    new_confirmed,
    new_deceased,
    -- Создаем синтетический timestamp для Time grain фильтрации
    toDateTime64(
        toString(date) || ' ' || 
        formatDateTime(now(), '%H:%M:%S'),
        3
    ) as synthetic_timestamp,
    -- Добавляем временные агрегации
    toStartOfHour(synthetic_timestamp) as hour_bucket,
    toStartOfDay(synthetic_timestamp) as day_bucket,
    toStartOfWeek(synthetic_timestamp) as week_bucket,
    toStartOfMonth(synthetic_timestamp) as month_bucket,
    -- Метрики с окном
    sum(new_confirmed) OVER (
        PARTITION BY country_name 
        ORDER BY date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as rolling_7day_cases
FROM raw.covid_new_cases
WHERE date >= {{ "'" + from_dttm + "'" | dateadd(days=-30) }}
  AND date <= {{ "'" + to_dttm + "'" }}
{% if filter_values('country_name') %}
  AND country_name IN {{ filter_values('country_name') | where_in }}
{% endif %}
ORDER BY date DESC, new_confirmed DESC
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

**Пример использования Jinja:**
```sql
-- Динамический фильтр по датам из UI
WHERE date >= {{ "'" + from_dttm + "'" | dateadd(days=-30) }}
  AND date <= {{ "'" + to_dttm + "'" }}

-- Условный фильтр по странам (только если выбраны в UI)
{% if filter_values('country_name') %}
  AND country_name IN {{ filter_values('country_name') | where_in }}
{% endif %}
```

![Virtual Dataset с Jinja](../screenshots/hw18_bi-integration/20_virtual_dataset_jinja.png)
*Использование Jinja-шаблонов в Virtual Dataset*

#### Преимущества Virtual Dataset подхода:

1. **Time Grain Support**: полноценная поддержка временных фильтров
2. **Dynamic Filtering**: автоматическая параметризация запросов
3. **Performance**: предварительная агрегация данных  
4. **Flexibility**: легкое изменение логики без пересоздания физических таблиц

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

![COVID-19 Analytics Dashboard - общий вид](../screenshots/hw18_bi-integration/dashboard_overview.png)
*Общий вид дашборда COVID-19 Analytics с 5 визуализациями*

![Линейный график - тренд новых случаев](../screenshots/hw18_bi-integration/chart_line_trend.png)
*График глобального тренда новых случаев COVID-19 по дням*

![Столбчатая диаграмма - топ стран](../screenshots/hw18_bi-integration/chart_bar_countries.png)
*Топ-10 стран по кумулятивным случаям COVID-19*

![Круговая диаграмма - регионы](../screenshots/hw18_bi-integration/chart_pie_regions.png)
*Распределение новых случаев по регионам*

![Многолинейный график - смерти vs выздоровления](../screenshots/hw18_bi-integration/chart_multiline_deaths_recovered.png)
*Сравнение недельных трендов смертей и выздоровлений*

![Тепловая карта - интенсивность по месяцам](../screenshots/hw18_bi-integration/chart_heatmap_intensity.png)
*Тепловая карта интенсивности случаев по странам и месяцам*

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