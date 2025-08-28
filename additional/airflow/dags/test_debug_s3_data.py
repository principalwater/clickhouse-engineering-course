import sys
sys.path.append('/opt/airflow')

from datetime import datetime
from airflow import DAG
from airflow.operators.python import PythonOperator
import boto3
from botocore.config import Config
from botocore import UNSIGNED
import zstandard as zstd
import os

SENSOR_TYPES = [
    'BME280', 'BMP180', 'BMP280', 'DHT11', 'DHT22', 'DS18B20', 
    'HTU21D', 'PMS1003', 'PMS3003', 'PMS5003', 'PMS7003', 
    'SDS011', 'SDS021', 'SHT15', 'SHT30', 'SHT85', 'PPD42NS'
]

def debug_all_sensor_schemas(**context):
    """
    Для каждого типа сенсора находит файл в S3 и выводит первые 5 строк.
    """
    bucket_name = 'clickhouse-public-datasets'
    prefix = 'sensors/monthly/'
    s3_client = boto3.client('s3', config=Config(signature_version=UNSIGNED))
    paginator = s3_client.get_paginator('list_objects_v2')

    all_files = []
    print("Собираем список всех файлов из S3...")
    for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
        if 'Contents' in page:
            all_files.extend([obj['Key'] for obj in page['Contents'] if obj['Key'].endswith('.csv.zst')])
    print(f"Найдено {len(all_files)} файлов.")

    for sensor_type in SENSOR_TYPES:
        print(f"\n{'='*20} АНАЛИЗ СЕНСОРА: {sensor_type} {'='*20}")
        
        target_file_key = None
        # Ищем файл, который содержит имя типа сенсора
        for f in all_files:
            if f"_{sensor_type.lower()}.csv.zst" in f:
                target_file_key = f
                break
        
        if not target_file_key:
            print(f"Файл для сенсора {sensor_type} не найден. Пропускаем.")
            continue
            
        print(f"Найден файл для анализа: {target_file_key}")

        try:
            response = s3_client.get_object(Bucket=bucket_name, Key=target_file_key)
            compressed_stream = response['Body']
            
            dctx = zstd.ZstdDecompressor()
            
            print("--- ПЕРВЫЕ 5 СТРОК ---")
            line_count = 0
            buffer = b""
            with dctx.stream_reader(compressed_stream) as reader:
                while True:
                    chunk = reader.read(16384)
                    if not chunk:
                        break
                    buffer += chunk
                    lines = buffer.split(b'\n')
                    buffer = lines.pop()

                    for line in lines:
                        if line_count < 5:
                            print(line.decode('utf-8', errors='ignore'))
                            line_count += 1
                        else:
                            break
                    if line_count >= 5:
                        break
            print("--- КОНЕЦ ВЫВОДА ---")

        except Exception as e:
            print(f"Ошибка при обработке файла {target_file_key}: {e}")

    return {"status": "success", "sensors_analyzed": SENSOR_TYPES}


with DAG(
    'test_debug_s3_data',
    default_args={
        'owner': 'debug',
        'start_date': datetime(2025, 1, 1),
    },
    schedule=None,
    catchup=False,
    tags=['debug', 's3', 'sensors'],
) as dag:
    debug_task = PythonOperator(
        task_id='debug_all_sensor_schemas',
        python_callable=debug_all_sensor_schemas,
    )
