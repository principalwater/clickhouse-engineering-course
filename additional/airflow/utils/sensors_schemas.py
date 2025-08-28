import random
import polars as pl
import polars_streaming_csv_decompression
import hashlib
import boto3
from botocore.config import Config
from botocore import UNSIGNED
import tempfile
import os
import zstandard as zstd
from datetime import datetime, timedelta
from typing import List, Dict, Optional

SENSOR_TYPES = [
    'BME280', 'BMP180', 'BMP280', 'DHT11', 'DHT22', 'DS18B20',
    'HTU21D', 'PMS1003', 'PMS3003', 'PMS5003', 'PMS7003',
    'SDS011', 'SDS021', 'SHT15', 'SHT30', 'SHT85', 'PPD42NS'
]

SAMPLE_LOCATIONS = [
    {'lat': 52.5200, 'lon': 13.4050, 'location': 1001, 'region': 'Berlin'},
    {'lat': 48.8566, 'lon': 2.3522, 'location': 1002, 'region': 'Paris'},
    {'lat': 51.5074, 'lon': -0.1278, 'location': 1003, 'region': 'London'},
    {'lat': 40.7128, 'lon': -74.0060, 'location': 2001, 'region': 'NYC'},
    {'lat': 35.6762, 'lon': 139.6503, 'location': 3001, 'region': 'Tokyo'},
]

def _get_s3_sensor_files_with_wildcard(sensor_types_filter: List[str] = None, start_timestamp: str = None, limit: int = 10000, max_files_per_run: int = 10) -> List[str]:
    """
    Получает список файлов Environmental Sensors из S3 с wildcard поддержкой.
    
    Args:
        sensor_types_filter: Список типов сенсоров для фильтрации имен файлов.
        start_timestamp: Timestamp для определения начальной партиции.
        limit: Лимит записей (влияет на количество файлов).
        max_files_per_run: Максимальное количество файлов для обработки за один запуск.
    
    Returns:
        List[str]: Список ключей файлов в S3.
    """
    bucket_name = 'clickhouse-public-datasets'
    prefix = 'sensors/monthly/'
    
    try:
        s3_client = boto3.client('s3', config=Config(signature_version=UNSIGNED))
        objects = []
        paginator = s3_client.get_paginator('list_objects_v2')
        
        allowed_sensor_types = [s.lower() for s in sensor_types_filter] if sensor_types_filter else []

        for page in paginator.paginate(Bucket=bucket_name, Prefix=prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    key = obj['Key']
                    if key.endswith('.csv.zst'):
                        if not allowed_sensor_types or any(f"_{sensor_type}.csv.zst" in key for sensor_type in allowed_sensor_types):
                            objects.append({
                                'key': key, 
                                'last_modified': obj['LastModified'],
                                'size': obj['Size']
                            })
        
        from dateutil import parser
        import pytz

        if start_timestamp:
            start_ts_dt = parser.parse(start_timestamp).replace(tzinfo=pytz.UTC)
            objects = [obj for obj in objects if obj['last_modified'] > start_ts_dt]

        objects.sort(key=lambda x: x['last_modified'], reverse=False)
        
        selected_files = [obj['key'] for obj in objects[:max_files_per_run]]
        print(f"   📂 Найдено {len(objects)} новых файлов в S3, выбрано {len(selected_files)} для обработки (лимит: {max_files_per_run})")
        return selected_files
        
    except Exception as e:
        print(f"   ⚠️ Ошибка получения списка файлов S3: {e}")
        return []

def _process_s3_files_with_polars(file_keys: List[str], 
                                 limit: int,
                                 start_timestamp: str = None,
                                 sensor_types_filter: List[str] = None,
                                 location_filter: List[int] = None) -> List[Dict]:
    bucket_name = 'clickhouse-public-datasets'
    all_records = []
    
    full_schema = {
        'sensor_id': pl.Int32, 'sensor_type': pl.Utf8, 'location': pl.Int32,
        'lat': pl.Float64, 'lon': pl.Float64, 'timestamp': pl.Utf8,
        'P1': pl.Float64, 'P2': pl.Float64, 'P0': pl.Float64,
        'durP1': pl.Float64, 'ratioP1': pl.Float64, 'durP2': pl.Float64,
        'ratioP2': pl.Float64, 'pressure': pl.Float64, 'altitude': pl.Float64,
        'pressure_sealevel': pl.Float64, 'temperature': pl.Float64, 'humidity': pl.Float64
    }

    for i, key in enumerate(file_keys):
        if len(all_records) >= limit:
            break
        try:
            print(f"   📂 Обработка файла {i+1}/{len(file_keys)}: {key}")
            s3_client = boto3.client('s3', config=Config(signature_version=UNSIGNED))
            response = s3_client.get_object(Bucket=bucket_name, Key=key)
            
            with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.csv') as temp_file:
                temp_path = temp_file.name
                dctx = zstd.ZstdDecompressor()
                with dctx.stream_reader(response['Body']) as reader:
                    while True:
                        chunk = reader.read(65536)
                        if not chunk: break
                        temp_file.write(chunk)
            
            try:
                with open(temp_path, 'r', encoding='utf-8') as f:
                    header = f.readline().strip().split(';')
                
                current_schema = {k: v for k, v in full_schema.items() if k in header}

                lazy_df = pl.scan_csv(
                    temp_path, separator=';', has_header=True,
                    schema=current_schema, try_parse_dates=False, ignore_errors=True
                )
            
                lazy_df = lazy_df.filter(pl.col("timestamp").is_not_null() & pl.col("sensor_id").is_not_null())
                lazy_df = lazy_df.with_columns([pl.col("timestamp").str.to_datetime(strict=False).alias("timestamp")])
                
                if start_timestamp:
                    from dateutil import parser
                    import pytz
                    start_ts_dt = parser.parse(start_timestamp).replace(tzinfo=pytz.UTC)
                    lazy_df = lazy_df.filter(pl.col("timestamp") > start_ts_dt)
                
                if sensor_types_filter:
                    lazy_df = lazy_df.filter(pl.col("sensor_type").is_in(sensor_types_filter))
                
                if location_filter:
                    lazy_df = lazy_df.filter(pl.col("location").is_in(location_filter))
                
                lazy_df = lazy_df.sort(["timestamp", "sensor_id"])
                
                remaining_limit = limit - len(all_records)
                if remaining_limit > 0:
                    lazy_df = lazy_df.limit(min(remaining_limit, 50000))
                else:
                    break
                
                df = lazy_df.collect()
                
                if df.height > 0:
                    for col, dtype in full_schema.items():
                        if col not in df.columns:
                            if dtype == pl.Int32:
                                df = df.with_columns(pl.lit(0, dtype=dtype).alias(col))
                            elif dtype == pl.Float64:
                                df = df.with_columns(pl.lit(0.0, dtype=dtype).alias(col))
                            else:
                                df = df.with_columns(pl.lit(None, dtype=dtype).alias(col))

                    df = df.with_columns([pl.col("timestamp").dt.strftime("%Y-%m-%d %H:%M:%S").alias("timestamp")])
                    all_records.extend(df.to_dicts())
                    print(f"   ✅ Обработано {len(df)} записей из файла {key}")
                else:
                    print(f"   📭 Файл {key} не содержит записей после фильтрации")
            finally:
                if 'temp_path' in locals(): os.unlink(temp_path)
        except Exception as e:
            print(f"   ❌ Ошибка обработки файла {key}: {e}")
            continue
    
    print(f"   📊 Итого обработано {len(all_records)} записей")
    return all_records

def load_sensors_real_data(limit: int = 10000, start_timestamp: str = None, 
                          sensor_types_filter: List[str] = None, 
                          location_filter: List[int] = None,
                          fallback_to_test_generation: bool = False,
                          max_files_per_run: int = 10) -> List[Dict]:
    try:
        print(f"🔄 Загрузка Environmental Sensors с Polars (лимит {limit})...")
        file_keys = _get_s3_sensor_files_with_wildcard(
            sensor_types_filter=sensor_types_filter, 
            start_timestamp=start_timestamp, 
            limit=limit,
            max_files_per_run=max_files_per_run
        )
        all_records = _process_s3_files_with_polars(
            file_keys=file_keys, limit=limit, start_timestamp=start_timestamp,
            sensor_types_filter=sensor_types_filter, location_filter=location_filter
        )
        if not all_records and not fallback_to_test_generation:
            raise ValueError("Не найдено записей Environmental Sensors, соответствующих заданным критериям")
        print(f"✅ Успешно обработано {len(all_records)} записей")
        return all_records
    except Exception as e:
        import traceback
        print(f"❌ Критическая ошибка при загрузке реальных данных: {e}")
        print(traceback.format_exc())
        if fallback_to_test_generation:
            return load_sensors_sample_data(limit)
        raise

def get_full_record(record: Dict) -> Dict:
    ts = record.get('timestamp')
    if not ts: return None
    
    full_record = {k: record.get(k, 0.0) for k in [
        'temperature', 'humidity', 'pressure', 'P1', 'P2', 'P0', 
        'durP1', 'ratioP1', 'durP2', 'ratioP2', 'altitude', 'pressure_sealevel'
    ]}
    full_record.update({
        'timestamp': ts,
        'sensor_id': record.get('sensor_id'),
        'sensor_type': record.get('sensor_type', ''),
        'location': record.get('location', 0),
        'lat': record.get('lat', 0.0),
        'lon': record.get('lon', 0.0)
    })
    
    hash_data = "".join(map(str, sorted(full_record.items())))
    full_record['record_hash'] = hashlib.md5(hash_data.encode()).hexdigest()[:8]
    return full_record

def load_sensors_sample_data(limit: int = 1000) -> List[Dict]:
    print(f"🔄 Генерация {limit} тестовых записей Environmental Sensors...")
    sample_data = []
    base_timestamp = datetime.now() - timedelta(hours=24)
    for i in range(limit):
        timestamp = base_timestamp + timedelta(seconds=i * 10)
        location_info = random.choice(SAMPLE_LOCATIONS)
        sensor_id = random.randint(1, 1000)
        sensor_type = random.choice(SENSOR_TYPES)
        
        record = {
            'sensor_id': sensor_id,
            'sensor_type': sensor_type,
            'location': location_info['location'],
            'lat': location_info['lat'],
            'lon': location_info['lon'],
            'timestamp': timestamp.strftime('%Y-%m-%d %H:%M:%S'),
            'P1': round(random.uniform(0, 150), 2),
            'P2': round(random.uniform(0, 200), 2),
            'pressure': round(random.uniform(980, 1030), 2),
            'temperature': round(random.uniform(-5, 45), 2),
            'humidity': round(random.uniform(20, 90), 2)
        }
        sample_data.append(record)
    print(f"✅ Сгенерировано {len(sample_data)} тестовых записей")
    return sample_data
