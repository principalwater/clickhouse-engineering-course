import sys
import os
sys.path.append('/opt/airflow')

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.models import Variable
from utils.sensors_producer import SensorsDataProducer

# Настройки по умолчанию для DAG
default_args = {
    'owner': 'principalwater',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
    'max_active_runs': 1,
}

def produce_sensors_data(**context):
    """
    Отправляет батч данных Environmental Sensors в единый Kafka топик,
    используя "водяной знак" (watermark) для инкрементальной загрузки.
    """
    try:
        params = context.get('params', {})
        broker_url = params.get('broker_url', 'kafka:9092')
        batch_size = params.get('batch_size', 1000)
        topic = params.get('topic', 'sensors')
        use_real_data = params.get('use_real_data', False)
        sensor_types_filter = params.get('sensor_types_filter', context['dag'].params.get('sensor_types_filter'))
        locations_filter = params.get('locations_filter', context['dag'].params.get('locations_filter'))

        last_processed_timestamp = None
        last_timestamp_variable_name = f"{context['dag'].dag_id}_last_timestamp"
        if use_real_data:
            manual_watermark = params.get('initial_watermark_timestamp')
            if manual_watermark:
                print(f"   💧 Используется ручной Watermark, заданный при запуске: {manual_watermark}")
                last_processed_timestamp = manual_watermark
            else:
                last_processed_timestamp = Variable.get(last_timestamp_variable_name, default_var=None)
        
        print(f"🚀 Запуск продьюсера Environmental Sensors")
        print(f"   Broker: {broker_url}")
        print(f"   Topic: {topic}")
        print(f"   Batch size: {batch_size}")
        print(f"   Real data: {use_real_data}")
        print(f"   Sensor types filter: {sensor_types_filter}")
        print(f"   Locations filter: {locations_filter}")
        if use_real_data and last_processed_timestamp:
            print(f"   💧 Watermark (загрузка после timestamp): {last_processed_timestamp}")
        
        producer = SensorsDataProducer(
            broker_url=broker_url,
            use_real_data=use_real_data,
            data_limit=batch_size * 2, # Загружаем с запасом
            start_timestamp=last_processed_timestamp,
            sensor_types_filter=sensor_types_filter if use_real_data else None,
            locations_filter=locations_filter if use_real_data else None
        )
        
        sent_count, max_timestamp_in_batch = producer.send_data_batch(
            topic=topic,
            batch_size=batch_size
        )
        
        stats = producer.get_stats()
        producer.close()
        
        print(f"✅ Успешно отправлено {sent_count} сообщений в топик {topic}")
        
        if use_real_data and max_timestamp_in_batch and max_timestamp_in_batch != last_processed_timestamp:
            print(f"   💧 Обновление Watermark на новый timestamp: {max_timestamp_in_batch}")
            Variable.set(last_timestamp_variable_name, max_timestamp_in_batch)
        elif use_real_data:
            print(f"   💧 Watermark не изменился ({last_processed_timestamp}). Новых данных нет.")

        return {
            'sent_count': sent_count,
            'topic': topic,
            'batch_size': batch_size,
            'timestamp': datetime.now().isoformat(),
            'producer_stats': stats,
            'last_processed_timestamp': last_processed_timestamp,
            'new_watermark': max_timestamp_in_batch
        }
        
    except Exception as e:
        print(f"❌ Ошибка в продьюсере Environmental Sensors: {e}")
        raise

# Создание DAG
dag = DAG(
    'sensors_pipeline',
    default_args=default_args,
    description='Единый пайплайн для отправки данных Environmental Sensors в Kafka',
    schedule=None,
    catchup=False,
    max_active_runs=1,
    tags=['environmental-sensors', 'kafka', 'producer', 'hw18'],
    params={
        'broker_url': 'kafka:9092',
        'topic': 'sensors', 
        'batch_size': 1000,
        'use_real_data': True,
        'sensor_types_filter': [],
        'locations_filter': [],
        'initial_watermark_timestamp': None,
        'max_files_per_run': 10,
    },
)

produce_task = PythonOperator(
    task_id='produce_sensors_data',
    python_callable=produce_sensors_data,
    dag=dag,
)
