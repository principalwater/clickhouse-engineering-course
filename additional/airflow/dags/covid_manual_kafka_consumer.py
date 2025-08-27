from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
import json
import os
import logging
from dotenv import load_dotenv

# Load environment variables
dotenv_path = os.path.join(os.path.dirname(__file__), '../../infra/env/clickhouse.env')
load_dotenv(dotenv_path=dotenv_path)

# Настройки по умолчанию для DAG
default_args = {
    'owner': 'hw17-manual-consumer',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=2),
    'max_active_runs': 1,  # Только один запуск одновременно
}

def setup_manual_consumer_table(**context):
    """Создание целевой таблицы для ручного потребления данных без Kafka Engine"""
    try:
        import clickhouse_connect
        
        print("🔧 Настройка таблицы для ручного потребления данных...")
        
        # Получение конфигурации ClickHouse из переменных окружения
        ch_config = {
            'host': os.getenv('CLICKHOUSE_HOST', 'localhost'),
            'port': int(os.getenv('CLICKHOUSE_PORT', 8123)),
            'username': os.getenv('CH_USER'),
            'password': os.getenv('CH_PASSWORD'),
            'secure': False
        }
        
        # Подключение к ClickHouse
        client = clickhouse_connect.get_client(**ch_config)
        
        # SQL для создания таблицы без Kafka Engine
        create_sql = """
        CREATE TABLE IF NOT EXISTS raw.covid_manual_consumption ON CLUSTER dwh_test (
            -- Основные поля данных
            date Date,
            location_key LowCardinality(String),
            new_confirmed Int32,
            new_deceased Int32,
            new_recovered Int32,
            new_tested Int32,
            
            -- Метаданные для мониторинга ручного потребления
            batch_id String,
            kafka_partition Int32,
            kafka_offset Int64,
            processing_time DateTime DEFAULT now(),
            consumer_group_id String
        ) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/raw/covid_manual_consumption/{uuid}', '{replica}')
        PARTITION BY toYYYYMM(date)
        ORDER BY (date, location_key)
        SETTINGS index_granularity = 8192;
        """
        
        client.command(create_sql)
        print("✅ Таблица raw.covid_manual_consumption создана успешно")
        
        # Создаем распределенную таблицу для кластерной работы
        distributed_sql = """
        CREATE TABLE IF NOT EXISTS raw.covid_manual_consumption_dist ON CLUSTER dwh_test AS raw.covid_manual_consumption
        ENGINE = Distributed('dwh_test', 'raw', 'covid_manual_consumption', xxHash64(location_key));
        """
        
        try:
            client.command(distributed_sql)
            print("✅ Распределенная таблица covid_manual_consumption_dist создана")
        except Exception as e:
            print(f"⚠️ Распределенная таблица не создана (возможно, кластер не настроен): {e}")
        
        client.close()
        
        return {
            'table_created': True,
            'target_table': 'raw.covid_manual_consumption',
            'distributed_table': 'raw.covid_manual_consumption_dist'
        }
        
    except Exception as e:
        print(f"❌ Ошибка при создании таблицы: {e}")
        raise

def consume_kafka_messages_batch(**context):
    """
    Потребление батча сообщений из Kafka без использования Kafka Engine
    
    Этот подход демонстрирует альтернативу встроенному Kafka Engine ClickHouse:
    - Прямое подключение к Kafka через kafka-python
    - Ручная обработка сообщений и контроль offset'ов  
    - Батчевая вставка данных в ClickHouse
    - Детальная статистика обработки
    """
    try:
        from kafka import KafkaConsumer
        import clickhouse_connect
        
        processing_time = 0
        
        # Получаем параметры из контекста или используем значения по умолчанию
        batch_size = context.get('params', {}).get('batch_size', 50)
        timeout_seconds = context.get('params', {}).get('timeout_seconds', 60)
        topic = context.get('params', {}).get('topic', 'covid_new_cases_1min')
        
        print(f"🚀 Запуск ручного консьюмера Kafka")
        print(f"   Topic: {topic}")
        print(f"   Batch size: {batch_size}")
        print(f"   Timeout: {timeout_seconds}s")
        
        # Конфигурация Kafka
        kafka_broker = os.getenv('KAFKA_BROKER', 'kafka:9092')
        
        # Создаем Kafka консьюмер
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers=[kafka_broker],
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            group_id=f'manual-clickhouse-consumer-{topic}',
            auto_offset_reset='latest',
            consumer_timeout_ms=timeout_seconds * 1000,
            enable_auto_commit=True
        )
        
        print(f"✅ Kafka консьюмер подключен к {kafka_broker}")
        
        # Подключение к ClickHouse
        ch_config = {
            'host': os.getenv('CLICKHOUSE_HOST', 'localhost'),
            'port': int(os.getenv('CLICKHOUSE_PORT', 8123)),
            'username': os.getenv('CH_USER'),
            'password': os.getenv('CH_PASSWORD'),
            'secure': False
        }
        
        ch_client = clickhouse_connect.get_client(**ch_config)
        print("✅ ClickHouse клиент подключен")
        
        # Сбор батча сообщений
        batch = []
        batch_id = datetime.now().strftime('%Y%m%d_%H%M%S')
        processing_start = datetime.now()
        
        print(f"📥 Начинаем потребление сообщений (batch_id: {batch_id})...")
        
        message_count = 0
        for message in consumer:
            try:
                # Парсим данные из Kafka
                data = message.value
                
                # Преобразуем дату
                try:
                    date_parsed = datetime.strptime(data['date'], '%Y-%m-%d').date()
                except:
                    # Если дата в другом формате, попробуем parseDateTimeBestEffort
                    date_parsed = datetime.now().date()
                
                # Рассчитываем задержку обработки
                msg_timestamp = datetime.fromtimestamp(message.timestamp / 1000) if message.timestamp else datetime.now()
                processing_lag = int((datetime.now() - msg_timestamp).total_seconds())
                
                # Формируем запись для ClickHouse
                record = [
                    date_parsed,     # date
                    data.get('location_key', 'UNKNOWN'),
                    data.get('new_confirmed', 0),
                    data.get('new_deceased', 0),
                    data.get('new_recovered', 0),
                    data.get('new_tested', 0),
                    batch_id,
                    message.partition,
                    message.offset,
                    datetime.now(), # processing_time
                    f'manual-clickhouse-consumer-{topic}' # consumer_group_id
                ]
                
                batch.append(record)
                message_count += 1
                
                # Если собрали нужный батч - вставляем в ClickHouse
                if len(batch) >= batch_size:
                    break
                    
            except Exception as e:
                print(f"⚠️ Ошибка при обработке сообщения: {e}")
                continue
        
        # Вставляем собранный батч в ClickHouse
        if batch:
            column_names = [
                'date', 'location_key',
                'new_confirmed', 'new_deceased', 'new_recovered',
                'new_tested', 'batch_id', 'kafka_partition',
                'kafka_offset', 'processing_time', 'consumer_group_id'
            ]
            
            ch_client.insert(
                'raw.covid_manual_consumption',
                batch,
                column_names=column_names
            )
            
            processing_time = (datetime.now() - processing_start).total_seconds()
            
            print(f"✅ Вставлено {len(batch)} записей в raw.covid_manual_consumption")
            print(f"   Время обработки: {processing_time:.2f}s")
            print(f"   Throughput: {len(batch)/processing_time:.1f} записей/сек")
        else:
            print("ℹ️ Нет новых сообщений для обработки")
        
        # Закрываем соединения
        consumer.close()
        ch_client.close()
        
        return {
            'messages_processed': message_count,
            'records_inserted': len(batch),
            'batch_id': batch_id,
            'processing_time_seconds': processing_time,
            'topic': topic,
            'kafka_broker': kafka_broker
        }
        
    except Exception as e:
        print(f"❌ Ошибка в ручном консьюмере: {e}")
        raise

def get_consumption_statistics(**context):
    """Получение статистики ручного потребления для сравнения с Kafka Engine"""
    try:
        import clickhouse_connect
        
        print("📊 Получение статистики ручного потребления...")
        
        # Подключение к ClickHouse
        ch_config = {
            'host': os.getenv('CLICKHOUSE_HOST', 'localhost'),
            'port': int(os.getenv('CLICKHOUSE_PORT', 8123)),
            'username': os.getenv('CH_USER'),
            'password': os.getenv('CH_PASSWORD'),
            'secure': False
        }
        
        client = clickhouse_connect.get_client(**ch_config)
        
        # Статистика ручного потребления
        manual_stats_sql = """
        SELECT 
            'Manual Consumer' as method,
            count() as total_records,
            uniq(location_key) as unique_locations,
            min(date) as earliest_date,
            max(date) as latest_date,
            max(processing_time) as last_insertion,
            uniq(batch_id) as total_batches
        FROM raw.covid_manual_consumption
        WHERE processing_time >= today()
        """
        
        manual_result = client.query(manual_stats_sql)
        
        # Статистика Kafka Engine для сравнения
        kafka_engine_stats_sql = """
        SELECT 
            'Kafka Engine' as method,
            count() as total_records,
            uniq(location_key) as unique_locations,
            min(date) as earliest_date,
            max(date) as latest_date,
            0 as avg_lag_seconds,
            max(date) as last_insertion,
            0 as total_batches
        FROM raw.covid_new_cases
        """
        
        kafka_result = client.query(kafka_engine_stats_sql)
        
        print("📋 Статистика потребления данных:")
        
        if manual_result.result_rows:
            row = manual_result.result_rows[0]
            print(f"   Manual Consumer: {row[1]} записей, {row[2]} стран, {row[6]} батчей")
        
        if kafka_result.result_rows:
            row = kafka_result.result_rows[0]
            print(f"   Kafka Engine: {row[1]} записей, {row[2]} стран")
        
        client.close()
        
        return {
            'manual_consumer_stats': manual_result.result_rows[0] if manual_result.result_rows else None,
            'kafka_engine_stats': kafka_result.result_rows[0] if kafka_result.result_rows else None
        }
        
    except Exception as e:
        print(f"❌ Ошибка при получении статистики: {e}")
        raise

# Создание DAG
dag = DAG(
    'covid_manual_kafka_consumer',
    default_args=default_args,
    description='Ручное потребление данных Kafka без использования Kafka Engine (альтернативный подход)',
    schedule='*/10 * * * *',  # Запуск каждые 10 минут в 00 секунд
    catchup=False,
    tags=['covid19', 'kafka', 'manual-consumer', 'hw17', 'alternative'],
)

# Определение задач DAG
setup_table_task = PythonOperator(
    task_id='setup_manual_consumer_table',
    python_callable=setup_manual_consumer_table,
    dag=dag,
)

consume_batch_task = PythonOperator(
    task_id='consume_kafka_batch',
    python_callable=consume_kafka_messages_batch,
    dag=dag,
)

get_stats_task = PythonOperator(
    task_id='get_consumption_statistics',
    python_callable=get_consumption_statistics,
    dag=dag,
)

# Определение зависимостей
setup_table_task >> consume_batch_task >> get_stats_task