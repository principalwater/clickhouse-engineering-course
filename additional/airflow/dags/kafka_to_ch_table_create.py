from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.models import Variable
import json
import os
import sys
from dotenv import load_dotenv

# Load environment variables
dotenv_path = os.path.join(os.path.dirname(__file__), '../../infra/env/clickhouse.env')
load_dotenv(dotenv_path=dotenv_path)

# Поля для автоматического преобразования типов из Kafka в ClickHouse
# Эти поля будут автоматически преобразованы из String в соответствующие типы
# для корректной работы с партиционированием и функциями ClickHouse
DATE_FIELDS = ['date', 'event_date', 'created_date', 'updated_date']  # String -> Date
DATETIME_FIELDS = ['timestamp', 'created_at', 'updated_at', 'event_time']  # String -> DateTime

def fix_projection_order_by(order_by_clause):
    """
    Исправляет ORDER BY для ClickHouse projection.
    В projection ClickHouse не поддерживает явные ASC/DESC в том же синтаксисе.
    Для проекций с смешанной сортировкой нужно использовать простые поля.
    """
    if not order_by_clause:
        return order_by_clause
    
    # Проверяем есть ли DESC в строке
    if 'DESC' in order_by_clause.upper():
        # Для projection с DESC лучше оставить только основные поля без направлений
        # или использовать только поля с одинаковым направлением
        fields = [field.strip() for field in order_by_clause.split(',')]
        clean_fields = []
        
        for field in fields:
            # Убираем ASC/DESC из поля, оставляем только имя
            clean_field = field.replace(' DESC', '').replace(' ASC', '').strip()
            clean_fields.append(clean_field)
        
        result = ', '.join(clean_fields)
        if result != order_by_clause:
            print(f"🔧 Упрощен ORDER BY для projection (убраны ASC/DESC): '{order_by_clause}' → '{result}'")
        return result
    
    return order_by_clause

def check_existing_tables(client, target_table_name, database_name, kafka_database):
    """Проверка существующих таблиц"""
    existing_tables = []
    
    # Список таблиц для проверки
    tables_to_check = [
        (kafka_database, f"{target_table_name}_kafka"),
        (database_name, f"{target_table_name}_local"),
        (database_name, target_table_name),
        (database_name, f"{target_table_name}_mv")
    ]
    
    for db, table in tables_to_check:
        try:
            result = client.query(f"EXISTS {db}.{table}")
            if result.result_rows and result.result_rows[0][0] == 1:
                existing_tables.append(f"{db}.{table}")
        except Exception:
            # Таблица не существует или нет доступа
            pass
    
    return existing_tables

def get_clickhouse_config():
    """Получение конфигурации ClickHouse из переменных окружения"""
    host = os.getenv("CLICKHOUSE_HOST")
    port = os.getenv("CLICKHOUSE_PORT")
    username = os.getenv("CH_USER")
    password = os.getenv("CH_PASSWORD")
    
    missing_vars = []
    if not host:
        missing_vars.append("CLICKHOUSE_HOST")
    if not port:
        missing_vars.append("CLICKHOUSE_PORT")
    if not username:
        missing_vars.append("CH_USER")
    if not password:
        missing_vars.append("CH_PASSWORD")
    
    if missing_vars:
        raise ValueError(f"Отсутствуют переменные окружения для ClickHouse: {', '.join(missing_vars)}. Проверьте файл infra/env/clickhouse.env")
    
    return {
        'host': host,
        'port': int(port),
        'username': username,
        'password': password,
        'secure': False
    }

# Определение параметров DAG
default_args = {
    'owner': 'energy-hub',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

# Создание DAG для создания таблиц из Kafka в ClickHouse
kafka_to_ch_dag = DAG(
    'kafka_to_ch_table_create',
    default_args=default_args,
    description='Создание таблиц ClickHouse из Kafka топиков (Kafka → Materialized View → Distributed)',
    schedule=None,  # Ручной запуск
    catchup=False,
    tags=['clickhouse', 'kafka', 'tables', 'kafka-to-clickhouse'],
)

def get_table_config(**context):
    """Получение конфигурации таблицы из параметров DAG"""
    try:
        # Получаем параметры из контекста DAG
        dag_run = context['dag_run']
        conf = dag_run.conf if dag_run else {}
        
        # Параметры по умолчанию для схемы Kafka → Materialized View → Distributed в DWH архитектуре
        default_config = {
            'kafka_topic': 'covid_new_cases_1min',
            'target_table_name': 'covid_new_cases',
            'dwh_layer': 'raw',  # raw, ods, dds, cdm
            'kafka_database': 'otus_kafka',  # база данных для Kafka таблиц
            'sort_key': 'date, location_key',
            'partition_key': 'toYYYYMM(date)',
            'shard_key': 'xxHash64(location_key)',
            'cluster_name': 'dwh_test',
            'kafka_broker': 'kafka:9092',
            # Дополнительные настройки оптимизации
            'create_projection': True,  # создавать ли проекцию для оптимизации
            'projection_order_by': None,  # если None, используется sort_key
            'create_indexes': True,  # создавать ли дополнительные индексы
            'index_fields': [],  # поля для создания индексов, по умолчанию пусто
            'table_settings': {},  # дополнительные настройки таблицы
            'skip_alter_on_error': True,  # пропускать ALTER запросы при ошибках
            'recreate_tables': False,  # пересоздавать таблицы (удалять существующие)
            'schema': {
                'date': 'String',
                'location_key': 'String',
                'new_confirmed': 'Int32',
                'new_deceased': 'Int32',
                'new_recovered': 'Int32',
                'new_tested': 'Int32'
            }
        }
        
        # Объединяем с переданными параметрами
        config = {**default_config, **conf}
        
        # Определяем базу данных на основе слоя DWH
        dwh_layer = config['dwh_layer']
        if dwh_layer == 'raw':
            database_name = 'raw'
        elif dwh_layer == 'ods':
            database_name = 'ods'
        elif dwh_layer == 'dds':
            database_name = 'dds'
        elif dwh_layer == 'cdm':
            database_name = 'cdm'
        else:
            database_name = 'raw'  # по умолчанию
        
        config['database_name'] = database_name
        
        print(f"📋 Конфигурация таблицы по схеме Kafka → Materialized View → Distributed:")
        print(f"   Kafka топик: {config['kafka_topic']}")
        print(f"   Целевая таблица: {config['target_table_name']}")
        print(f"   Слой DWH: {config['dwh_layer']}")
        print(f"   База данных DWH: {config['database_name']}")
        print(f"   База данных Kafka: {config['kafka_database']}")
        print(f"   Ключ сортировки: {config['sort_key']}")
        print(f"   Ключ партиционирования: {config['partition_key']}")
        print(f"   Ключ шардирования: {config['shard_key']}")
        print(f"   Кластер: {config['cluster_name']}")
        
        # Сохраняем конфигурацию в XCom для использования в других задачах
        context['task_instance'].xcom_push(key='table_config', value=config)
        
        return config
        
    except Exception as e:
        print(f"❌ Ошибка при получении конфигурации: {e}")
        raise

def check_connections(**context):
    """Проверка подключений к ClickHouse и Kafka"""
    try:
        import clickhouse_connect
        from kafka import KafkaConsumer
        
        config = context['task_instance'].xcom_pull(task_ids='get_table_config', key='table_config')
        
        if not config:
            raise ValueError("Конфигурация таблицы не найдена. Убедитесь, что задача get_table_config выполнилась успешно.")
        
        print("🔍 Проверка подключений...")
        
        # Получение конфигурации ClickHouse
        ch_config = get_clickhouse_config()
        
        # Проверка ClickHouse через HTTP порт
        client = clickhouse_connect.get_client(**ch_config)
        
        result = client.query('SELECT version()')
        version = result.result_rows[0][0]
        print(f"✅ ClickHouse: версия {version}")
        
        # Проверка кластера
        cluster_result = client.query(f"SELECT name, host_name, port FROM system.clusters WHERE name = '{config['cluster_name']}'")
        if cluster_result.result_rows:
            print(f"✅ Кластер {config['cluster_name']}: {len(cluster_result.result_rows)} узлов")
        else:
            print(f"⚠️ Кластер {config['cluster_name']} не найден")
        
        client.close()
        
        # Проверка Kafka
        consumer = KafkaConsumer(
            bootstrap_servers=[config['kafka_broker']],
            consumer_timeout_ms=5000
        )
        
        topics = consumer.topics()
        if config['kafka_topic'] in topics:
            print(f"✅ Kafka топик {config['kafka_topic']} найден")
        else:
            print(f"⚠️ Kafka топик {config['kafka_topic']} не найден")
        
        consumer.close()
        
        return "Success"
        
    except Exception as e:
        print(f"❌ Ошибка при проверке подключений: {e}")
        raise

def generate_sql_script(**context):
    """Генерация SQL-скрипта на основе конфигурации"""
    try:
        config = context['task_instance'].xcom_pull(task_ids='get_table_config', key='table_config')
        
        if not config:
            raise ValueError("Конфигурация таблицы не найдена. Убедитесь, что задача get_table_config выполнилась успешно.")
        
        print("🔄 Генерация SQL-скрипта...")
        
        # Извлекаем параметры для схемы Kafka → Materialized View → Distributed
        kafka_topic = config['kafka_topic']
        target_table_name = config['target_table_name']
        database_name = config['database_name']
        kafka_database = config['kafka_database']
        dwh_layer = config['dwh_layer']
        sort_key = config['sort_key']
        partition_key = config['partition_key']
        shard_key = config['shard_key']
        cluster_name = config['cluster_name']
        kafka_broker = config['kafka_broker']
        schema = config['schema']
        
        # Генерируем SQL-скрипт по схеме Kafka → Materialized View → Distributed в DWH архитектуре
        sql_script = f"""
-- =====================================================
-- Автоматически сгенерированный SQL-скрипт для таблицы {target_table_name}
-- Схема: Kafka Topic → Kafka Table Engine → Materialized View → ReplicatedMergeTree/Distributed
-- Слой DWH: {dwh_layer}
-- Топик: {kafka_topic}
-- База Kafka: {kafka_database}
-- Пересоздание таблиц: {config.get('recreate_tables', False)}
-- =====================================================
"""
        
        # Добавляем команды удаления если нужно пересоздать таблицы
        if config.get('recreate_tables', False):
            sql_script += f"""

-- Удаление существующих таблиц для пересоздания
DROP TABLE IF EXISTS {database_name}.{target_table_name}_mv ON CLUSTER {cluster_name};
DROP TABLE IF EXISTS {database_name}.{target_table_name} ON CLUSTER {cluster_name};
DROP TABLE IF EXISTS {database_name}.{target_table_name}_local ON CLUSTER {cluster_name};
DROP TABLE IF EXISTS {kafka_database}.{target_table_name}_kafka ON CLUSTER {cluster_name};

"""
        
        sql_script += f"""
-- Создание баз данных для DWH архитектуры
CREATE DATABASE IF NOT EXISTS {kafka_database} ON CLUSTER {cluster_name};
CREATE DATABASE IF NOT EXISTS raw ON CLUSTER {cluster_name};
CREATE DATABASE IF NOT EXISTS ods ON CLUSTER {cluster_name};
CREATE DATABASE IF NOT EXISTS dds ON CLUSTER {cluster_name};
CREATE DATABASE IF NOT EXISTS cdm ON CLUSTER {cluster_name};

-- 1. Создание таблицы с движком Kafka для получения данных из топика
CREATE TABLE IF NOT EXISTS {kafka_database}.{target_table_name}_kafka ON CLUSTER {cluster_name} (
"""
        
        # Добавляем поля схемы
        for field_name, field_type in schema.items():
            sql_script += f"    {field_name} {field_type},\n"
        
        sql_script = sql_script.rstrip(',\n') + f"""
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = '{kafka_broker}',
    kafka_topic_list = '{kafka_topic}',
    kafka_group_name = 'clickhouse-{target_table_name}-consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1,
    kafka_skip_broken_messages = 1000,
    kafka_row_delimiter = '\\n';

-- 2. Создание конечной таблицы с движком семейства MergeTree (ReplicatedMergeTree)
CREATE TABLE IF NOT EXISTS {database_name}.{target_table_name}_local ON CLUSTER {cluster_name} (
"""
        
        # Добавляем поля схемы с автоматическим преобразованием типов
        for field_name, field_type in schema.items():
            if field_name in DATETIME_FIELDS:
                sql_script += f"    {field_name} DateTime,\n"
            elif field_name in DATE_FIELDS and field_type == 'String':
                sql_script += f"    {field_name} Date,\n"
            else:
                sql_script += f"    {field_name} {field_type},\n"
        
        sql_script = sql_script.rstrip(',\n') + f"""
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{{shard}}/{database_name}/{target_table_name}_local/{{uuid}}/', '{{replica}}')
PARTITION BY {partition_key}
ORDER BY ({sort_key})
PRIMARY KEY ({sort_key});

-- Распределенная таблица
CREATE TABLE IF NOT EXISTS {database_name}.{target_table_name} ON CLUSTER {cluster_name} (
"""
        
        # Добавляем поля схемы с автоматическим преобразованием типов
        for field_name, field_type in schema.items():
            if field_name in DATETIME_FIELDS:
                sql_script += f"    {field_name} DateTime,\n"
            elif field_name in DATE_FIELDS and field_type == 'String':
                sql_script += f"    {field_name} Date,\n"
            else:
                sql_script += f"    {field_name} {field_type},\n"
        
        sql_script = sql_script.rstrip(',\n') + f"""
) ENGINE = Distributed('{cluster_name}', '{database_name}', '{target_table_name}_local', {shard_key});

-- Materialized View
CREATE MATERIALIZED VIEW IF NOT EXISTS {database_name}.{target_table_name}_mv ON CLUSTER {cluster_name} 
TO {database_name}.{target_table_name} AS
SELECT
"""
        
        # Добавляем поля с автоматическим преобразованием типов
        for field_name, field_type in schema.items():
            if field_name in DATETIME_FIELDS:
                sql_script += f"    parseDateTimeBestEffort({field_name}) AS {field_name},\n"
            elif field_name in DATE_FIELDS and field_type == 'String':
                sql_script += f"    parseDateTimeBestEffort({field_name}) AS {field_name},\n"
            else:
                sql_script += f"    {field_name},\n"
        
        sql_script = sql_script.rstrip(',\n') + f"""
FROM {kafka_database}.{target_table_name}_kafka;
"""
        
        # Добавляем дополнительные оптимизации (только если настроено)
        if config.get('create_indexes', True) and config.get('index_fields'):
            for field in config['index_fields']:
                if field in schema:
                    sql_script += f"""
-- Индекс по полю {field}
ALTER TABLE {database_name}.{target_table_name}_local ON CLUSTER {cluster_name} 
ADD INDEX IF NOT EXISTS idx_{field} {field} TYPE minmax GRANULARITY 4;

"""
        
        if config.get('create_projection', True):
            projection_order = config.get('projection_order_by') or sort_key
            
            # Валидация и исправление ORDER BY для projection
            # ClickHouse требует явного указания направления для всех полей при смешанной сортировке
            projection_order = fix_projection_order_by(projection_order)
            sql_script += f"""
-- Проекция для оптимизации
ALTER TABLE {database_name}.{target_table_name}_local ON CLUSTER {cluster_name} 
ADD PROJECTION IF NOT EXISTS {target_table_name}_projection (
    SELECT * ORDER BY {projection_order}
);

-- Материализация проекции
ALTER TABLE {database_name}.{target_table_name}_local ON CLUSTER {cluster_name} 
MATERIALIZE PROJECTION {target_table_name}_projection;

"""
        
        # Сохраняем SQL-скрипт в XCom
        context['task_instance'].xcom_push(key='sql_script', value=sql_script)
        
        print(f"✅ SQL-скрипт сгенерирован для таблицы {target_table_name}")
        print(f"📋 Размер скрипта: {len(sql_script)} символов")
        print(f"📋 Первые 500 символов: {sql_script[:500]}")
        
        return "Success"
        
    except Exception as e:
        print(f"❌ Ошибка при генерации SQL-скрипта: {e}")
        raise

def execute_sql_script(**context):
    """Выполнение SQL-скрипта"""
    try:
        import clickhouse_connect
        
        config = context['task_instance'].xcom_pull(task_ids='get_table_config', key='table_config')
        sql_script = context['task_instance'].xcom_pull(task_ids='generate_sql_script', key='sql_script')
        
        if not config:
            raise ValueError("Конфигурация таблицы не найдена. Убедитесь, что задача get_table_config выполнилась успешно.")
        
        if not sql_script:
            raise ValueError("SQL-скрипт не найден. Убедитесь, что задача generate_sql_script выполнилась успешно.")
        
        print("🔄 Выполнение SQL-скрипта...")
        
        # Получение конфигурации ClickHouse
        ch_config = get_clickhouse_config()
        
        # Подключение к ClickHouse
        client = clickhouse_connect.get_client(**ch_config)
        
        # Разделение скрипта на запросы (более умное разделение)
        # Убираем комментарии и пустые строки
        lines = []
        for line in sql_script.split('\n'):
            line = line.strip()
            if line and not line.startswith('--'):
                lines.append(line)
        
        # Собираем запросы
        queries = []
        current_query = []
        in_multiline = False
        
        for line in lines:
            if line.startswith('CREATE') or line.startswith('ALTER') or line.startswith('DROP'):
                # Начинается новый запрос
                if current_query:
                    queries.append(' '.join(current_query))
                current_query = [line]
                in_multiline = True
            elif in_multiline:
                current_query.append(line)
                if line.endswith(';'):
                    # Завершается запрос
                    queries.append(' '.join(current_query))
                    current_query = []
                    in_multiline = False
            else:
                # Простой запрос
                if line.endswith(';'):
                    queries.append(line)
        
        # Добавляем последний запрос, если он есть
        if current_query:
            queries.append(' '.join(current_query))
        
        print(f"📋 Выполнение {len(queries)} SQL-запросов...")
        print(f"📋 Размер SQL-скрипта: {len(sql_script)} символов")
        print(f"📋 Первые 500 символов SQL: {sql_script[:500]}")
        
        # Проверка существующих таблиц перед выполнением
        target_table_name = config['target_table_name']
        database_name = config['database_name'] 
        kafka_database = config['kafka_database']
        recreate_tables = config.get('recreate_tables', False)
        
        existing_tables = check_existing_tables(client, target_table_name, database_name, kafka_database)
        
        # Проверяем, все ли необходимые таблицы существуют
        expected_tables = [
            f"{kafka_database}.{target_table_name}_kafka",
            f"{database_name}.{target_table_name}_local", 
            f"{database_name}.{target_table_name}",
            f"{database_name}.{target_table_name}_mv"
        ]
        
        all_tables_exist = all(table in existing_tables for table in expected_tables)
        
        if not recreate_tables and existing_tables:
            print("ℹ️  ИНФОРМАЦИЯ О СУЩЕСТВУЮЩИХ ТАБЛИЦАХ:")
            for table_info in existing_tables:
                print(f"   ✅ {table_info} уже существует")
            
            if all_tables_exist:
                print("🎯 Все необходимые таблицы уже созданы, пропускаем выполнение SQL-запросов")
                print("✅ SQL-скрипт завершен успешно: все таблицы уже существуют")
                
                # Завершаем с успехом
                client.close()
                return {
                    'status': 'success_skip',
                    'message': 'Все таблицы уже существуют',
                    'existing_tables': existing_tables,
                    'skipped_queries': len(queries)
                }
        
        # Отладочная информация о запросах
        for i, query in enumerate(queries, 1):
            print(f"📋 Запрос {i}: {query[:100]}...")
        
        failed_queries = []
        for i, query in enumerate(queries, 1):
            if query.strip():
                try:
                    print(f"🔄 Запрос {i}/{len(queries)}: {query[:100]}...")
                    client.command(query)
                    print(f"✅ Запрос {i} выполнен")
                except Exception as e:
                    error_str = str(e)
                    
                    # Проверяем, является ли это ошибкой о уже существующих объектах
                    is_already_exists = (
                        "already exists" in error_str.lower() or 
                        "ILLEGAL_COLUMN" in error_str or  # индекс уже существует
                        "ILLEGAL_PROJECTION" in error_str or  # проекция уже существует
                        "583" in error_str  # код ошибки для существующей проекции
                    )
                    
                    if is_already_exists and not recreate_tables:
                        # Обрабатываем как успешный случай для существующих объектов
                        print(f"ℹ️  Запрос {i}: объект уже существует, пропускаем")
                        if "projection" in query.lower():
                            print(f"   ✅ Проекция уже создана")
                        elif "index" in query.lower():
                            print(f"   ✅ Индекс уже создан")
                        else:
                            print(f"   ✅ Объект уже существует")
                    else:
                        print(f"❌ КРИТИЧЕСКАЯ ошибка в запросе {i}: {e}")
                        print(f"❌ Проблемный запрос: {query}")
                        failed_queries.append((i, query, str(e)))
                    # Продолжаем выполнение для диагностики
        
        # Проверка созданных таблиц
        target_table_name = config['target_table_name']
        database_name = config['database_name']
        kafka_database = config['kafka_database']
        
        missing_tables = []
        verification_errors = []
        
        # Проверка Kafka-таблицы
        try:
            kafka_tables = client.query(f"SHOW TABLES FROM {kafka_database} LIKE '{target_table_name}_kafka'")
            if kafka_tables.result_rows:
                print(f"✅ Kafka-таблица {kafka_database}.{target_table_name}_kafka создана")
            else:
                print(f"❌ Kafka-таблица {kafka_database}.{target_table_name}_kafka не найдена")
                missing_tables.append(f"{kafka_database}.{target_table_name}_kafka")
        except Exception as e:
            print(f"❌ Ошибка при проверке Kafka-таблицы: {e}")
            verification_errors.append(f"Kafka table check: {e}")
        
        # Проверка локальной таблицы
        try:
            local_tables = client.query(f"SHOW TABLES FROM {database_name} LIKE '{target_table_name}_local'")
            if local_tables.result_rows:
                print(f"✅ Локальная таблица {database_name}.{target_table_name}_local создана")
            else:
                print(f"❌ Локальная таблица {database_name}.{target_table_name}_local не найдена")
                missing_tables.append(f"{database_name}.{target_table_name}_local")
        except Exception as e:
            print(f"❌ Ошибка при проверке локальной таблицы: {e}")
            verification_errors.append(f"Local table check: {e}")
        
        # Проверка распределенной таблицы
        try:
            dist_tables = client.query(f"SHOW TABLES FROM {database_name} LIKE '{target_table_name}'")
            if dist_tables.result_rows:
                print(f"✅ Распределенная таблица {database_name}.{target_table_name} создана")
            else:
                print(f"❌ Распределенная таблица {database_name}.{target_table_name} не найдена")
                missing_tables.append(f"{database_name}.{target_table_name}")
        except Exception as e:
            print(f"❌ Ошибка при проверке распределенной таблицы: {e}")
            verification_errors.append(f"Distributed table check: {e}")
        
        # Проверка Materialized View
        try:
            mv_tables = client.query(f"SHOW TABLES FROM {database_name} LIKE '{target_table_name}_mv'")
            if mv_tables.result_rows:
                print(f"✅ Materialized View {database_name}.{target_table_name}_mv создана")
            else:
                print(f"❌ Materialized View {database_name}.{target_table_name}_mv не найдена")
                missing_tables.append(f"{database_name}.{target_table_name}_mv")
        except Exception as e:
            print(f"❌ Ошибка при проверке Materialized View: {e}")
            verification_errors.append(f"Materialized View check: {e}")
        
        client.close()
        
        # Анализ результатов и принятие решения об успехе/неудаче
        if failed_queries or missing_tables or verification_errors:
            print("\n❌ ОШИБКИ ОБНАРУЖЕНЫ:")
            if failed_queries:
                print(f"   Неудачных SQL-запросов: {len(failed_queries)}")
                for i, query, error in failed_queries:
                    print(f"     - Запрос {i}: {error}")
            if missing_tables:
                print(f"   Отсутствующих таблиц: {len(missing_tables)}")
                for table in missing_tables:
                    print(f"     - {table}")
            if verification_errors:
                print(f"   Ошибок верификации: {len(verification_errors)}")
                for error in verification_errors:
                    print(f"     - {error}")
            
            error_msg = f"SQL выполнение завершилось с ошибками: {len(failed_queries)} неудачных запросов, {len(missing_tables)} отсутствующих таблиц, {len(verification_errors)} ошибок верификации"
            raise RuntimeError(error_msg)
        
        print("✅ SQL-скрипт выполнен успешно - все таблицы созданы")
        return "Success"
        
    except Exception as e:
        print(f"❌ Ошибка при выполнении SQL-скрипта: {e}")
        raise

def verify_data_flow(**context):
    """Проверка потока данных"""
    try:
        import clickhouse_connect
        import time
        
        config = context['task_instance'].xcom_pull(task_ids='get_table_config', key='table_config')
        
        if not config:
            raise ValueError("Конфигурация таблицы не найдена. Убедитесь, что задача get_table_config выполнилась успешно.")
        
        target_table_name = config['target_table_name']
        database_name = config['database_name']
        
        print("🔍 Проверка потока данных...")
        
        # Ждем накопления данных
        print("⏳ Ожидание накопления данных (30 секунд)...")
        time.sleep(30)
        
        # Получение конфигурации ClickHouse
        ch_config = get_clickhouse_config()
        
        # Подключение к ClickHouse
        client = clickhouse_connect.get_client(**ch_config)
        
        # Проверка данных в таблице
        try:
            count_result = client.query(f'SELECT count() FROM {database_name}.{target_table_name}')
            count = count_result.result_rows[0][0]
            print(f"📊 Таблица {database_name}.{target_table_name}: {count} записей")
            
            if count > 0:
                # Показываем пример данных
                sample_result = client.query(f'SELECT * FROM {database_name}.{target_table_name} ORDER BY date DESC LIMIT 1')
                if sample_result.result_rows:
                    print(f"📋 Пример данных из {database_name}.{target_table_name}:")
                    print(f"   {sample_result.result_rows[0]}")
            else:
                print(f"⚠️ В таблице {database_name}.{target_table_name} пока нет данных")
                
        except Exception as e:
            print(f"⚠️ Ошибка при проверке данных: {e}")
        
        client.close()
        
        print("✅ Проверка потока данных завершена")
        return "Success"
        
    except Exception as e:
        print(f"❌ Ошибка при проверке потока данных: {e}")
        raise

def health_check(**context):
    """Проверка здоровья созданных таблиц"""
    try:
        import clickhouse_connect
        
        config = context['task_instance'].xcom_pull(task_ids='get_table_config', key='table_config')
        
        if not config:
            raise ValueError("Конфигурация таблицы не найдена. Убедитесь, что задача get_table_config выполнилась успешно.")
        
        target_table_name = config['target_table_name']
        database_name = config['database_name']
        kafka_database = config['kafka_database']
        
        print("🔍 Проверка здоровья таблиц...")
        
        # Получение конфигурации ClickHouse
        ch_config = get_clickhouse_config()
        
        # Подключение к ClickHouse
        client = clickhouse_connect.get_client(**ch_config)
        
        # Проверка статуса таблиц
        tables_status = client.query(f'''
            SELECT 
                database,
                table,
                engine,
                total_rows,
                total_bytes
            FROM system.tables 
            WHERE database IN ('{database_name}', '{kafka_database}')
            AND table LIKE '{target_table_name}%'
            ORDER BY database, table
        ''')
        
        print("📋 Статус созданных таблиц:")
        for row in tables_status.result_rows:
            print(f"   {row[0]}.{row[1]} ({row[2]}): {row[3]} строк, {row[4]} байт")
        
        # Проверка Materialized Views
        mv_status = client.query(f'''
            SELECT 
                database,
                table,
                engine,
                engine_full
            FROM system.tables 
            WHERE engine = 'MaterializedView' 
            AND database IN ('{database_name}', '{kafka_database}')
            AND table LIKE '{target_table_name}%'
        ''')
        
        print("📋 Materialized Views:")
        for row in mv_status.result_rows:
            print(f"   {row[0]}.{row[1]} ({row[2]})")
        
        client.close()
        
        print("✅ Проверка здоровья таблиц завершена")
        return "Healthy"
        
    except Exception as e:
        print(f"❌ Ошибка при проверке здоровья таблиц: {e}")
        raise

# Определение задач
get_config_task = PythonOperator(
    task_id='get_table_config',
    python_callable=get_table_config,
    dag=kafka_to_ch_dag,
)

check_connections_task = PythonOperator(
    task_id='check_connections',
    python_callable=check_connections,
    dag=kafka_to_ch_dag,
)

generate_sql_task = PythonOperator(
    task_id='generate_sql_script',
    python_callable=generate_sql_script,
    dag=kafka_to_ch_dag,
)

execute_sql_task = PythonOperator(
    task_id='execute_sql_script',
    python_callable=execute_sql_script,
    dag=kafka_to_ch_dag,
)

verify_flow_task = PythonOperator(
    task_id='verify_data_flow',
    python_callable=verify_data_flow,
    dag=kafka_to_ch_dag,
)

health_check_task = PythonOperator(
    task_id='health_check',
    python_callable=health_check,
    dag=kafka_to_ch_dag,
)

# Определение зависимостей
get_config_task >> check_connections_task >> generate_sql_task >> execute_sql_task >> verify_flow_task >> health_check_task
