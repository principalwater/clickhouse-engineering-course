from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from covid_producer import CovidDataProducer
import os

# Настройки по умолчанию для DAG
default_args = {
    'owner': 'hw17-covid-cumulative',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=2),
    'max_active_runs': 1,  # Только один запуск одновременно
}

def produce_cumulative_data(**context):
    """
    Отправляет батч накопительных данных COVID-19 в Kafka топик covid_cumulative_data_5min
    
    Данные включают:
    - date: дата записи
    - location_key: код страны/региона
    - cumulative_confirmed: накопительные подтвержденные случаи
    - cumulative_deceased: накопительные смертельные случаи  
    - cumulative_recovered: накопительные выздоровевшие
    - cumulative_tested: накопительные проведенные тесты
    """
    try:
        # Получаем параметры из контекста или используем значения по умолчанию
        broker_url = context.get('params', {}).get('broker_url', 'kafka:9092')
        batch_size = context.get('params', {}).get('batch_size', 5)
        topic = context.get('params', {}).get('topic', 'covid_cumulative_data_5min')
        use_real_data = context.get('params', {}).get('use_real_data', False)
        locations_filter = context.get('params', {}).get('locations_filter', 
                                                         ['US', 'GB', 'DE', 'FR', 'IT', 'ES', 'RU'])
        
        print(f"🚀 Запуск продьюсера накопительных данных COVID-19")
        print(f"   Broker: {broker_url}")
        print(f"   Topic: {topic}")
        print(f"   Batch size: {batch_size}")
        print(f"   Real data: {use_real_data}")
        print(f"   Locations filter: {locations_filter}")
        
        # Создаем продьюсер
        producer = CovidDataProducer(
            broker_url=broker_url,
            use_real_data=use_real_data,
            data_limit=3000  # Больше данных для накопительной статистики
        )
        
        # Отправляем батч накопительных данных
        sent_count = producer.send_cumulative_data_batch(
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
            'data_type': 'cumulative',
            'timestamp': datetime.now().isoformat(),
            'locations_count': len(locations_filter),
            'producer_stats': stats,
            'broker_url': broker_url
        }
        
    except Exception as e:
        print(f"❌ Ошибка в продьюсере накопительных данных COVID-19: {e}")
        raise

def check_topic_availability(**context):
    """Проверяет доступность топика covid_cumulative_data_5min перед отправкой данных"""
    from kafka import KafkaProducer
    from kafka.errors import NoBrokersAvailable
    
    broker_url = context.get('params', {}).get('broker_url', 'kafka:9092')
    topic = context.get('params', {}).get('topic', 'covid_cumulative_data_5min')
    
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

def validate_cumulative_data(**context):
    """Валидирует корректность отправленных накопительных данных"""
    
    # Получаем результат отправки данных
    produce_result = context['task_instance'].xcom_pull(task_ids='produce_cumulative_data')
    
    if not produce_result:
        raise ValueError("Результат отправки данных не найден")
    
    sent_count = produce_result.get('sent_count', 0)
    batch_size = produce_result.get('batch_size', 0)
    
    print(f"🔍 Валидация отправленных накопительных данных")
    print(f"   Ожидалось отправить: {batch_size} сообщений")
    print(f"   Фактически отправлено: {sent_count} сообщений")
    
    # Проверяем соответствие количества отправленных сообщений
    if sent_count == batch_size:
        print(f"✅ Все сообщения отправлены корректно")
        validation_status = 'success'
    elif sent_count > 0:
        print(f"⚠️ Отправлено частично: {sent_count}/{batch_size}")
        validation_status = 'partial'
    else:
        print(f"❌ Ни одно сообщение не было отправлено")
        validation_status = 'failed'
        raise Exception("Не удалось отправить ни одного сообщения")
    
    # Проверяем тип данных
    data_type = produce_result.get('data_type')
    if data_type != 'cumulative':
        print(f"⚠️ Неожиданный тип данных: {data_type}")
    
    return {
        'validation_status': validation_status,
        'expected_count': batch_size,
        'actual_count': sent_count,
        'success_rate': (sent_count / batch_size * 100) if batch_size > 0 else 0,
        'data_type': data_type,
        'validation_timestamp': datetime.now().isoformat()
    }

# Создание DAG
dag = DAG(
    'covid_cumulative_data_5min',
    default_args=default_args,
    description='Продьюсер накопительных данных COVID-19 каждые 5 минут',
    schedule="*/5 * * * *",  # каждые 5 минут в :00 секунд (00:05:00, 00:10:00, etc.)
    catchup=False,
    max_active_runs=1,
    tags=['covid19', 'kafka', 'producer', 'cumulative', '5min', 'hw17'],
    params={
        'broker_url': 'kafka:9092',
        'topic': 'covid_cumulative_data_5min', 
        'batch_size': 5,
        'use_real_data': False,  # По умолчанию используем тестовые данные
        'locations_filter': ['US', 'GB', 'DE', 'FR', 'IT', 'ES', 'RU']
    },
    doc_md="""
    ## COVID-19 Cumulative Data Producer DAG (5min)
    
    Продьюсер для отправки накопительных данных COVID-19 в Kafka топик каждые 5 минут.
    
    ### Отправляемые данные:
    - **date**: дата записи в формате YYYY-MM-DD
    - **location_key**: код страны/региона (например: US, GB, DE)
    - **cumulative_confirmed**: накопительные подтвержденные случаи с начала пандемии
    - **cumulative_deceased**: накопительные смертельные случаи с начала пандемии
    - **cumulative_recovered**: накопительные выздоровевшие с начала пандемии
    - **cumulative_tested**: накопительные проведенные тесты с начала пандемии
    
    ### Параметры:
    - **broker_url**: адрес Kafka брокера (по умолчанию: kafka:9092)
    - **topic**: название топика (по умолчанию: covid_cumulative_data_5min)
    - **batch_size**: размер батча (по умолчанию: 5 сообщений)
    - **use_real_data**: использовать реальные данные COVID-19 (по умолчанию: False)
    - **locations_filter**: список кодов стран для отправки
    
    ### Пример JSON сообщения:
    ```json
    {
        "date": "2020-03-15",
        "location_key": "US", 
        "cumulative_confirmed": 123456,
        "cumulative_deceased": 4567,
        "cumulative_recovered": 98765,
        "cumulative_tested": 1234567
    }
    ```
    
    ### Особенности:
    - Накопительные данные показывают общую статистику с начала пандемии
    - Отправляется реже (каждые 5 минут) из-за большего размера данных
    - Включает дополнительную валидацию отправленных данных
    """
)

# Задача проверки доступности топика
check_topic_task = PythonOperator(
    task_id='check_topic_availability',
    python_callable=check_topic_availability,
    dag=dag,
    doc_md="""
    Проверяет доступность топика covid_cumulative_data_5min в Kafka кластере.
    Если топик не существует, задача выведет предупреждение, но не упадет.
    """
)

# Основная задача отправки данных
produce_task = PythonOperator(
    task_id='produce_cumulative_data',
    python_callable=produce_cumulative_data,
    dag=dag,
    doc_md="""
    Отправляет батч накопительных данных COVID-19 в Kafka топик.
    
    Использует CovidDataProducer для:
    1. Загрузки накопительных данных COVID-19 (реальных или тестовых)
    2. Фильтрации по выбранным странам/регионам
    3. Отправки батча в формате JSON в Kafka
    4. Логирования статистики отправки
    """
)

# Задача валидации отправленных данных
validate_task = PythonOperator(
    task_id='validate_cumulative_data',
    python_callable=validate_cumulative_data,
    dag=dag,
    doc_md="""
    Валидирует корректность отправленных накопительных данных COVID-19.
    
    Проверяет:
    - Соответствие количества отправленных сообщений ожидаемому
    - Корректность типа отправленных данных
    - Расчет процента успешности отправки
    """
)

# Определяем зависимости между задачами
check_topic_task >> produce_task >> validate_task