from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from covid_producer import CovidDataProducer
import os

# Настройки по умолчанию для DAG
default_args = {
    'owner': 'hw17-covid-new-cases',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
    'max_active_runs': 1,  # Только один запуск одновременно
}

def produce_new_cases_data(**context):
    """
    Отправляет батч новых случаев COVID-19 в Kafka топик covid_new_cases_1min
    
    Данные включают:
    - date: дата записи
    - location_key: код страны/региона  
    - new_confirmed: новые подтвержденные случаи
    - new_deceased: новые смертельные случаи
    - new_recovered: новые выздоровевшие
    - new_tested: новые проведенные тесты
    """
    try:
        # Получаем параметры из контекста или используем значения по умолчанию
        broker_url = context.get('params', {}).get('broker_url', 'kafka:9092')
        batch_size = context.get('params', {}).get('batch_size', 8)
        topic = context.get('params', {}).get('topic', 'covid_new_cases_1min')
        use_real_data = context.get('params', {}).get('use_real_data', False)
        locations_filter = context.get('params', {}).get('locations_filter', 
                                                         ['US', 'GB', 'DE', 'FR', 'IT', 'ES', 'RU', 'CN'])
        
        print(f"🚀 Запуск продьюсера новых случаев COVID-19")
        print(f"   Broker: {broker_url}")
        print(f"   Topic: {topic}")
        print(f"   Batch size: {batch_size}")
        print(f"   Real data: {use_real_data}")
        print(f"   Locations filter: {locations_filter}")
        
        # Создаем продьюсер
        producer = CovidDataProducer(
            broker_url=broker_url,
            use_real_data=use_real_data,
            data_limit=2000  # Загружаем достаточно данных для цикличной работы
        )
        
        # Отправляем батч новых случаев
        sent_count = producer.send_daily_data_batch(
            topic=topic,
            batch_size=batch_size,
            locations_filter=locations_filter
        )
        
        # Получаем статистику продьюсера
        stats = producer.get_stats()
        
        # Закрываем продьюсер
        producer.close()
        
        print(f"✅ Успешно отправлено {sent_count} сообщений в топик {topic}")
        
        # Возвращаем результат для XCom и мониторинга
        return {
            'sent_count': sent_count,
            'topic': topic,
            'batch_size': batch_size,
            'data_type': 'new_cases',
            'timestamp': datetime.now().isoformat(),
            'locations_count': len(locations_filter),
            'producer_stats': stats,
            'broker_url': broker_url
        }
        
    except Exception as e:
        print(f"❌ Ошибка в продьюсере новых случаев COVID-19: {e}")
        raise

def check_topic_availability(**context):
    """Проверяет доступность топика covid_new_cases_1min перед отправкой данных"""
    from kafka import KafkaProducer
    from kafka.errors import NoBrokersAvailable
    
    broker_url = context.get('params', {}).get('broker_url', 'kafka:9092')
    topic = context.get('params', {}).get('topic', 'covid_new_cases_1min')
    
    try:
        print(f"🔍 Проверка доступности топика {topic}")
        
        # Создаем продьюсер для проверки
        producer = KafkaProducer(
            bootstrap_servers=[broker_url],
            request_timeout_ms=5000,
            api_version=(0, 10, 1)
        )
        
        # Получаем метаданные топиков (совместимый способ)
        try:
            # Пытаемся получить метаданные через KafkaAdminClient
            from kafka import KafkaAdminClient
            admin_client = KafkaAdminClient(
                bootstrap_servers=[broker_url],
                request_timeout_ms=5000,
                api_version=(0, 10, 1)
            )
            metadata = admin_client.list_topics()
            available_topics = list(metadata)
            admin_client.close()
        except Exception:
            # Fallback: используем альтернативный способ через consumer
            from kafka import KafkaConsumer
            consumer = KafkaConsumer(
                bootstrap_servers=[broker_url],
                request_timeout_ms=5000,
                api_version=(0, 10, 1)
            )
            available_topics = list(consumer.topics())
            consumer.close()
        
        producer.close()
        
        topic_available = topic in available_topics
        
        if topic_available:
            print(f"✅ Топик {topic} доступен для записи")
        else:
            print(f"⚠️ Топик {topic} не найден среди доступных топиков")
            print(f"📋 Доступные топики: {available_topics}")
        
        return {
            'topic': topic,
            'topic_available': topic_available,
            'available_topics': available_topics,
            'broker_url': broker_url,
            'check_status': 'success' if topic_available else 'warning'
        }
        
    except NoBrokersAvailable:
        print(f"❌ Kafka брокеры недоступны: {broker_url}")
        raise
    except Exception as e:
        print(f"❌ Ошибка проверки топика: {e}")
        raise

# Создание DAG
dag = DAG(
    'covid_new_cases_1min',
    default_args=default_args,
    description='Продьюсер новых случаев COVID-19 каждую минуту',
    schedule="* * * * *",  # каждую минуту в :00 секунд
    catchup=False,
    max_active_runs=1,
    tags=['covid19', 'kafka', 'producer', 'new-cases', '1min', 'hw17'],
    params={
        'broker_url': 'kafka:9092',
        'topic': 'covid_new_cases_1min', 
        'batch_size': 8,
        'use_real_data': False,  # По умолчанию используем тестовые данные
        'locations_filter': ['US', 'GB', 'DE', 'FR', 'IT', 'ES', 'RU', 'CN', 'JP', 'KR']
    },
    doc_md="""
    ## COVID-19 New Cases Producer DAG (1min)
    
    Продьюсер для отправки данных о новых случаях COVID-19 в Kafka топик каждую минуту.
    
    ### Отправляемые данные:
    - **date**: дата записи в формате YYYY-MM-DD
    - **location_key**: код страны/региона (например: US, GB, DE)
    - **new_confirmed**: количество новых подтвержденных случаев
    - **new_deceased**: количество новых смертельных случаев  
    - **new_recovered**: количество новых выздоровевших
    - **new_tested**: количество новых проведенных тестов
    
    ### Параметры:
    - **broker_url**: адрес Kafka брокера (по умолчанию: kafka:9092)
    - **topic**: название топика (по умолчанию: covid_new_cases_1min)
    - **batch_size**: размер батча (по умолчанию: 8 сообщений)
    - **use_real_data**: использовать реальные данные COVID-19 (по умолчанию: False)
    - **locations_filter**: список кодов стран для отправки
    
    ### Пример JSON сообщения:
    ```json
    {
        "date": "2020-03-15",
        "location_key": "US",
        "new_confirmed": 1234,
        "new_deceased": 45,
        "new_recovered": 567,
        "new_tested": 12340
    }
    ```
    """
)

# Задача проверки доступности топика
check_topic_task = PythonOperator(
    task_id='check_topic_availability',
    python_callable=check_topic_availability,
    dag=dag,
    doc_md="""
    Проверяет доступность топика covid_new_cases_1min в Kafka кластере.
    Если топик не существует, задача выведет предупреждение, но не упадет.
    """
)

# Основная задача отправки данных
produce_task = PythonOperator(
    task_id='produce_new_cases_data',
    python_callable=produce_new_cases_data,
    dag=dag,
    doc_md="""
    Отправляет батч данных о новых случаях COVID-19 в Kafka топик.
    
    Использует CovidDataProducer для:
    1. Загрузки данных COVID-19 (реальных или тестовых)
    2. Фильтрации по выбранным странам/регионам
    3. Отправки батча в формате JSON в Kafka
    4. Логирования статистики отправки
    """
)

# Определяем зависимости между задачами
check_topic_task >> produce_task