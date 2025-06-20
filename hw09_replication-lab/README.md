# Домашнее задание №9: Репликация и фоновые процессы в ClickHouse

---

## Оглавление

- [Описание задания](#описание-задания)  
- [Внесённые изменения в инфраструктурные файлы](#внесённые-изменения-в-инфраструктурные-файлы)  
- [Шаг 1. Демонстрационный датасет и описание таблицы `menu`](#шаг-1-демонстрационный-датасет-и-описание-таблицы-menu)  
  - [Подготовка данных к импорту](#подготовка-данных-к-импорту)
  - [Создание таблицы menu](#создание-таблицы-menu)
  - [Загрузка данных в ClickHouse](#загрузка-данных-в-clickhouse)
- [Шаг 2. Конвертация таблицы в реплицируемую](#шаг-2-конвертация-таблицы-в-реплицируемую)  
- [Шаг 3. Добавление реплик в кластер](#шаг-3-добавление-реплик-в-кластер)  
- [Шаг 4. Проверка состояния репликации и частей таблиц](#шаг-4-проверка-состояния-репликации-и-частей-таблиц)  
- [Шаг 5. Настройка TTL для автоматического удаления данных](#шаг-5-настройка-ttl-для-автоматического-удаления-данных)  
- [Проверка отказоустойчивости и анализ репликации](#проверка-отказоустойчивости-и-анализ-репликации)  
- [Итоговый вывод](#итоговый-вывод)  
- [Источники](#источники)  

---

## Описание задания

В данном домашнем задании изучаются возможности репликации в ClickHouse, работа с реплицируемыми таблицами и настройка фоновых процессов, таких как TTL для автоматического удаления устаревших данных.

### Цели задания

- Научиться создавать реплицируемые таблицы с использованием макросов `{shard}` и `{replica}`.  
- Мигрировать данные из существующих таблиц в реплицируемые.  
- Добавлять реплики в кластер через инфраструктурный код (Terraform).  
- Выполнять кластерные запросы для проверки состояния репликации.  
- Настраивать TTL для хранения данных только за последние 7 дней.  

### Бизнес-контекст

В современных аналитических системах важна высокая доступность и отказоустойчивость данных. Репликация в ClickHouse обеспечивает синхронизацию данных между узлами кластера, а TTL позволяет автоматически очищать устаревшие данные, освобождая место и поддерживая актуальность информации.

### Компетенции, развиваемые в задании

- Управление кластерами ClickHouse с использованием репликации.  
- Работа с движком `ReplicatedMergeTree` и макросами конфигурации.  
- Инфраструктурное управление кластерами через Terraform.  
- Настройка фоновых процессов и автоматизация очистки данных.  
- Мониторинг и диагностика состояния реплик и кластера.  

### Легенда для скриншотов

В отчёте после каждого ключевого шага приводится скриншот, отражающий результат выполнения действия: создание таблиц, миграция данных, статус реплик и т.д. Скриншоты помогают визуально подтвердить правильность выполнения операций.

---

## Внесённые изменения в инфраструктурные файлы

Все необходимые для запуска кластера файлы (main.tf, variables.tf, outputs.tf, шаблоны конфигов в samples) уже находятся в каталоге `hw09_replication-lab/terraform` — дополнительных копирований не требуется.

Для выполнения задания и масштабирования кластера были внесены следующие изменения:

- В файле `main.tf` расширен блок `clickhouse_nodes`: теперь описано 2 шарда по 3 реплики (всего 6 нод), что позволяет продемонстрировать полноценную репликацию и отказоустойчивость.
- В блоке `remote_servers` в `main.tf` добавлены новые реплики для каждого шарда, обеспечивая корректную маршрутизацию запросов и балансировку нагрузки.
- В шаблоне конфигурации `config.xml.tpl`:
  - **Добавлены параметры ограничения сетевой нагрузки на репликацию**:
    - `<max_replicated_fetches_network_bandwidth_for_server>` — лимит на объём скачивания реплицируемых данных (1 ГБ/с).
    - `<max_replicated_sends_network_bandwidth_for_server>` — лимит на отправку данных между репликами (512 МБ/с).
  - **В секции `<merge_tree>`** добавлены и скорректированы ключевые параметры для производительности и надёжности:
    - `<parts_to_throw_insert>`, `<write_ahead_log_max_bytes>`, `<enable_mixed_granularity_parts>`, `<replication_alter_partitions_sync>` — контроль количества частей, WAL и оптимизация слияний.
    - `<can_become_leader>` — теперь только первая реплика в каждом шарде может быть лидером (макрос).
  - **Секция `<compression>`** определяет разные методы сжатия для разных размеров партиций (ZSTD для крупных, LZ4 для остальных).
  - Все остальные параметры оставлены по best practice для ClickHouse 2024–2025.
  - Вся настройка находится в каталоге `hw09_replication-lab/terraform/samples/`, запуск производится **без дублирования данных** (используется общий volume из base-infra/clickhouse/volumes).

```xml
<!-- Лимиты репликации -->
<max_replicated_fetches_network_bandwidth_for_server>1073741824</max_replicated_fetches_network_bandwidth_for_server> <!-- 1 GB -->
<max_replicated_sends_network_bandwidth_for_server>536870912</max_replicated_sends_network_bandwidth_for_server> <!-- 512 MB -->

<merge_tree>
    <parts_to_throw_insert>300</parts_to_throw_insert>
    <min_rows_for_wide_part>0</min_rows_for_wide_part>
    <min_bytes_for_wide_part>0</min_bytes_for_wide_part>
    <write_ahead_log_max_bytes>1073741824</write_ahead_log_max_bytes>
    <enable_mixed_granularity_parts>1</enable_mixed_granularity_parts>
    <can_become_leader>${node.replica == 1 ? 1 : 0}</can_become_leader>
    <replication_alter_partitions_sync>2</replication_alter_partitions_sync>
</merge_tree>
```

- Переменная `clickhouse_base_path` в файле `variables.tf` по умолчанию ссылается на `"../../base-infra/clickhouse/volumes"`. Это обеспечивает использование общих данных и логов без необходимости копирования или дублирования, что упрощает запуск и поддержку кластера.

---

## Шаг 1. Демонстрационный датасет и описание таблицы `menu`

В качестве демонстрационного используется открытый датасет [NYPL "What's on the menu?"](https://clickhouse.com/docs/en/getting-started/example-datasets/menus) — коллекция исторических меню Нью-Йоркской публичной библиотеки. Для задания нужна только таблица `menu`, структура и загрузка полностью соответствуют официальной документации ClickHouse.

- **Источник:** [NYPL Menu Data](http://menus.nypl.org/data)
- **Размер:** ~1.3 млн строк, 20 атрибутов, CSV.
- **Назначение:** Отработка репликации и фоновых процессов на реальных и сложных данных.

### Подготовка данных к импорту

Датасет взят из официального sample datasets ClickHouse: https://clickhouse.com/docs/getting-started/example-datasets/menus

**Подготовка данных к импорту полностью автоматизирована с помощью скрипта:**

```sh
./scripts/import_menu_dataset.sh
```

Скрипт:
- Cкачивает и распаковывает архив в `data/menusdata_nypl/`
- Копирует `Menu.csv` в контейнер ClickHouse (в каталог `/var/lib/clickhouse/user_files/menusdata_nypl_dataset/`)
- Выставляет нужные права на файл

Если какой-то этап завершился с ошибкой — будет показано сообщение об ошибке и пошаговые логи.

Далее для импорта данных используйте SQL-команду:

```sql
INSERT INTO otus_default.menu
FORMAT CSVWithNames
INFILE '/var/lib/clickhouse/user_files/menusdata_nypl_dataset/Menu.csv'
SETTINGS input_format_csv_allow_single_quotes=0, input_format_null_as_default=0;
```

> **Важно:** Для загрузки данных через SQL-команду `INSERT ... INFILE` в новых версиях ClickHouse необходимо, чтобы файл находился именно в каталоге `/var/lib/clickhouse/user_files/`. Подробнее — см. документацию: https://clickhouse.com/docs/ru/operations/settings/settings#user_files_path

- Такой подход полностью совместим с кластерной инсталляцией и гарантирует корректную загрузку данных.
- Если будете использовать `clickhouse-client` для импорта напрямую, не забудьте про параметры `--user` и `--password`.

---

### Создание таблицы menu

Структура таблицы:

```sql
CREATE TABLE menu ON CLUSTER dwh_test
(
    id UInt32,
    name String,
    sponsor String,
    event String,
    venue String,
    place String,
    physical_description String,
    occasion String,
    notes String,
    call_number String,
    keywords String,
    language String,
    date String,
    location String,
    location_type String,
    currency String,
    currency_symbol String,
    status String,
    page_count UInt16,
    dish_count UInt16
) ENGINE = MergeTree ORDER BY id;
```

### Загрузка данных в ClickHouse

_Загрузка производится непосредственно из файла `/var/lib/clickhouse/user_files/Menu.csv`, который уже находится на сервере первой ноды._

```sql
INSERT INTO menu
FORMAT CSVWithNames
INFILE '/var/lib/clickhouse/user_files/Menu.csv';
```

- Используется формат данных CSVWithNames (заголовки из первой строки).
- Отключён `format_csv_allow_single_quotes` (одинарные кавычки допускаются только внутри значений).
- Отключён `input_format_null_as_default` (корректная работа с пустыми значениями).

> **Альтернативный способ загрузки через утилиту clickhouse-client:**
>
> Вы также можете загрузить данные через стандартную утилиту:
>
> ```bash
> clickhouse-client --user <your_user> --password <your_password> --format_csv_allow_single_quotes 0 --input_format_null_as_default 0 --query "INSERT INTO menu FORMAT CSVWithNames" < /var/lib/clickhouse/user_files/Menu.csv
> ```
>
> Если запускать с той же ноды, путь к файлу будет таким же (`/var/lib/clickhouse/user_files/Menu.csv`).

**Результат:** Таблица menu наполнена реальными историческими данными NYPL — можно переходить к работе с репликацией и фоновыми процессами.

---

## Шаг 2. Конвертация таблицы в реплицируемую

Для обеспечения отказоустойчивости сконвертируем таблицу `menu` в реплицируемую с помощью движка `ReplicatedMergeTree` и макросов `{shard}` и `{replica}`.

### 2.1 Создание реплицируемой таблицы

Создадим новую таблицу `menu_replicated` с полной структурой, аналогичной оригинальной:

```sql
CREATE TABLE otus_default.menu_replicated ON CLUSTER dwh_test
(
    id UInt32,
    name String,
    sponsor String,
    event String,
    venue String,
    place String,
    physical_description String,
    occasion String,
    notes String,
    call_number String,
    keywords String,
    language String,
    date String,
    location String,
    location_type String,
    currency String,
    currency_symbol String,
    status String,
    page_count UInt16,
    dish_count UInt16
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/menu_replicated', '{replica}')
ORDER BY id;
```

<img src="../screenshots/hw09_replication-and-background-processes/04_01_replicated_table_created.png" alt="Создана таблица menu_replicated" width="600"/>

### 2.2 Миграция данных с помощью S3

Для переноса данных используйте повторный импорт из S3 (или, если таблица menu уже заполнена, выполните вставку из неё). Основной рабочий способ для задания — локальный импорт через user_files.

```sql
INSERT INTO otus_default.menu_replicated
SELECT * FROM otus_default.menu
ON CLUSTER dwh_test;
```

Если требуется загрузить напрямую из S3:

```sql
INSERT INTO otus_default.menu_replicated
SELECT
    id,
    name,
    sponsor,
    event,
    venue,
    place,
    physical_description,
    occasion,
    notes,
    call_number,
    keywords,
    language,
    date,
    location,
    location_type,
    currency,
    currency_symbol,
    status,
    page_count,
    dish_count
FROM s3(
    'https://<ваш-s3-бакет>/menu.csv',
    'CSV',
    'id UInt32,
     name String,
     sponsor String,
     event String,
     venue String,
     place String,
     physical_description String,
     occasion String,
     notes String,
     call_number String,
     keywords String,
     language String,
     date String,
     location String,
     location_type String,
     currency String,
     currency_symbol String,
     status String,
     page_count UInt16,
     dish_count UInt16'
)
ON CLUSTER dwh_test;
```

> Подробнее о назначении и best practice использования конструкции `ON CLUSTER` для массовых операций вставки/миграции см. примечание выше и [официальную документацию ClickHouse](https://clickhouse.com/docs/en/sql-reference/statements/insert-into#insert-into-on-cluster).

<img src="../screenshots/hw09_replication-and-background-processes/04_02_attach_partitions.png" alt="Загрузка данных в menu_replicated" width="600"/>

### 2.3 Переключение на новую таблицу

После успешной миграции можно использовать `menu_replicated` как основную таблицу. Для этого (если требуется) переименуйте таблицы:

```sql
RENAME TABLE otus_default.menu TO otus_default.menu_old, 
             otus_default.menu_replicated TO otus_default.menu
ON CLUSTER dwh_test;
```

<img src="../screenshots/hw09_replication-and-background-processes/04_03_exchange_or_rename.png" alt="Переключение на новую таблицу menu" width="600"/>

---

## Шаг 3. Добавление реплик в кластер


### 3.1 Изменение конфигурации Terraform

В файле `base-infra/clickhouse/main.tf` необходимо расширить массив `local.clickhouse_nodes`, добавив новые ноды с уникальными параметрами `name`, `shard`, `replica`, а также указать порты и хосты.

Пример конфигурации с двумя шардами и тремя репликами на каждый шард:

```hcl
local.clickhouse_nodes = [
  { name = "clickhouse-01", shard = 1, replica = 1, host = "clickhouse-01", http_port = 8123, tcp_port = 9000 },
  { name = "clickhouse-02", shard = 1, replica = 2, host = "clickhouse-02", http_port = 8124, tcp_port = 9001 },
  { name = "clickhouse-03", shard = 1, replica = 3, host = "clickhouse-03", http_port = 8125, tcp_port = 9002 },
  { name = "clickhouse-04", shard = 2, replica = 1, host = "clickhouse-04", http_port = 8126, tcp_port = 9003 },
  { name = "clickhouse-05", shard = 2, replica = 2, host = "clickhouse-05", http_port = 8127, tcp_port = 9004 },
  { name = "clickhouse-06", shard = 2, replica = 3, host = "clickhouse-06", http_port = 8128, tcp_port = 9005 },
]
```

### 3.2 Запуск Terraform для применения изменений

Выполнить команду для применения изменений:

```bash
terraform apply
```

После успешного применения на всех нодах автоматически создадутся необходимые таблицы с правильными путями и макросами.

### 3.3 Роль ZooKeeper (Keeper) в отказоустойчивости

Для корректной работы репликации требуется кластер из трёх экземпляров ZooKeeper (или ClickHouse Keeper), который обеспечивает согласованное хранение метаданных и координацию реплик. Это критично для обеспечения отказоустойчивости и корректного выбора лидера.

### 3.4 Проверка статуса реплик

Подключаемся к `clickhouse-01` и выполняем запрос для просмотра статуса реплик таблицы `menu`:

```sql
SELECT *
FROM system.replicas
WHERE table = 'menu' AND database = 'otus_default'
ON CLUSTER dwh_test;
```

<img src="../screenshots/hw09_replication-and-background-processes/05_replicas_added.png" alt="Добавлены реплики в кластер для menu" width="600"/>

Теперь роль лидера в шарде чётко закреплена за первой репликой (`replica == 1`), что ускоряет failover и предотвращает split-brain.

---

## Шаг 4. Проверка состояния репликации и частей таблиц

### 4.1 Просмотр частей таблицы на всех репликах через `remote()`

Для проверки, что данные распределены по всем репликам, выполняем запрос:

```sql
SELECT *
FROM remote(
    ['clickhouse-01','clickhouse-02','clickhouse-03','clickhouse-04','clickhouse-05','clickhouse-06'],
    'system.parts'
)
WHERE table = 'menu' AND database = 'otus_default';
```

Данный запрос выводит информацию о частях таблицы на всех узлах кластера.

<img src="../screenshots/hw09_replication-and-background-processes/06_01_system_parts_remote.png" alt="system.parts через remote() для menu" width="600"/>

### 4.2 Просмотр статуса реплик на кластере

Для мониторинга состояния репликации и синхронизации выполняем запрос:

```sql
SELECT *
FROM system.replicas
WHERE table = 'menu' AND database = 'otus_default'
ON CLUSTER dwh_test;
```

Вывод содержит информацию о состоянии каждой реплики, включая состояние синхронизации и текущий лидер.

<img src="../screenshots/hw09_replication-and-background-processes/06_02_system_replicas.png" alt="system.replicas на кластере для menu" width="600"/>

---

## Шаг 5. Настройка TTL для автоматического удаления данных

Для автоматического удаления устаревших данных можно настроить TTL по дате (например, по колонке `date`, если она преобразована в тип Date или DateTime).

### 5.1 Создание реплицируемой таблицы с TTL

Создадим новую таблицу `menu_replicated_ttl` с TTL по колонке `date` (предварительно преобразовав её в Date, если необходимо):

```sql
CREATE TABLE otus_default.menu_replicated_ttl ON CLUSTER dwh_test
(
    id UInt32,
    name String,
    sponsor String,
    event String,
    venue String,
    place String,
    physical_description String,
    occasion String,
    notes String,
    call_number String,
    keywords String,
    language String,
    date Date,
    location String,
    location_type String,
    currency String,
    currency_symbol String,
    status String,
    page_count UInt16,
    dish_count UInt16
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/menu_replicated_ttl', '{replica}')
ORDER BY id
TTL date + INTERVAL 7 DAY;
```

### 5.2 Миграция данных в новую таблицу

Переносим данные из текущей реплицируемой таблицы:

```sql
INSERT INTO otus_default.menu_replicated_ttl
SELECT
    id,
    name,
    sponsor,
    event,
    venue,
    place,
    physical_description,
    occasion,
    notes,
    call_number,
    keywords,
    language,
    parseDateTimeBestEffortOrNull(date) as date,
    location,
    location_type,
    currency,
    currency_symbol,
    status,
    page_count,
    dish_count
FROM otus_default.menu_replicated
ON CLUSTER dwh_test;
```

**Примечание по использованию ON CLUSTER для INSERT:**

> В случае массовой миграции или инициализации данных в новую реплицируемую таблицу используем конструкцию `INSERT ... SELECT ... ON CLUSTER dwh_test`, чтобы обеспечить синхронную вставку данных на все узлы кластера. Это предотвращает временные расхождения и позволяет сразу стартовать с одинаковым набором данных на всех репликах. Подробнее: [ClickHouse docs](https://clickhouse.com/docs/en/sql-reference/statements/insert-into#insert-into-on-cluster)

<img src="../screenshots/hw09_replication-and-background-processes/07_ttl_configured.png" alt="Настроен TTL для хранения 7 дней в menu_replicated_ttl" width="600"/>

### 5.3 Проверка структуры таблицы и параметров TTL

Для проверки структуры и настроек выполните:

```sql
SHOW CREATE TABLE otus_default.menu_replicated_ttl ON CLUSTER dwh_test;
```

Данный вывод подтверждает наличие параметров репликации и TTL.

<img src="../screenshots/hw09_replication-and-background-processes/08_show_create_table.png" alt="SHOW CREATE TABLE с TTL и репликацией для menu_replicated_ttl" width="600"/>

### Как работает TTL в кластере

TTL выполняется локально на каждой реплике, удаляя данные старше 7 дней. Удаление происходит асинхронно и независимо на каждой ноде, что позволяет поддерживать актуальность данных без дополнительной нагрузки на кластер.

---

## Проверка отказоустойчивости и анализ репликации

### Эксперимент по отключению нод

Для проверки отказоустойчивости можно последовательно отключать ноды кластера и анализировать состояние реплик через запрос:

```sql
SELECT *
FROM system.replicas
WHERE table = 'menu' AND database = 'otus_default'
ON CLUSTER dwh_test;
```

### Анализ состояния

- При отключении одной из реплик остальные продолжают обслуживать запросы, обеспечивая доступность данных.  
- В кластере существует лидер (leader) для каждой шарды, который координирует запись данных. При отказе лидера происходит автоматический выбор нового лидера.  
- Статус реплик отображает их состояние, включая задержки и ошибки.  

### Выводы по отказоустойчивости

- Репликация с использованием `ReplicatedMergeTree` и ZooKeeper обеспечивает высокую доступность и согласованность данных.  
- Использование трёх Keeper-узлов гарантирует отказоустойчивость метаданных и корректный выбор лидера.  
- Мониторинг через `system.replicas` позволяет своевременно обнаруживать проблемы и принимать меры.  

---

## Итоговый вывод

В результате выполнения задания была создана отказоустойчивая реплицируемая таблица с автоматическим удалением устаревших данных. Используется полный реальный набор атрибутов из датасета NYPL, что обеспечивает корректную проверку репликации и TTL в условиях, близких к боевым. Использование макросов `{shard}` и `{replica}` в конфигурации и движках таблиц позволило централизованно управлять кластером. Масштабирование и добавление реплик осуществляется декларативно через Terraform, что упрощает поддержку и развитие инфраструктуры. Настройка TTL обеспечивает автоматическую очистку данных без ручного вмешательства.

Такой подход оптимален для аналитических систем с высокими требованиями к доступности и актуальности данных. В дальнейшем можно улучшить мониторинг, добавить алерты и автоматизировать процессы восстановления.

---

## Источники

- [Официальная документация ClickHouse: Репликация](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication/)  
- [Официальная документация ClickHouse: TTL](https://clickhouse.com/docs/en/sql-reference/statements/create/table/#ttl)  
- [Документация по мониторингу репликации](https://clickhouse.com/docs/en/operations/system-tables/replicas/)  
- [ClickHouse Keeper — отказоустойчивый сервис хранения метаданных](https://clickhouse.com/docs/en/operations/server-configuration-keeper/)
- [Вставка данных с ON CLUSTER (ClickHouse docs)](https://clickhouse.com/docs/en/sql-reference/statements/insert-into#insert-into-on-cluster)