import time
import json
import argparse
from datetime import datetime
from typing import List, Dict, Optional, Set
from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable, KafkaError
import redis
from .sensors_schemas import (
    load_sensors_real_data,
    load_sensors_sample_data,
    get_full_record
)

class SensorsDataProducer:
    def __init__(self,
                 broker_url: str = 'kafka:9092',
                 use_real_data: bool = True,
                 data_limit: int = 1000,
                 start_timestamp: str = None,
                 sensor_types_filter: List[str] = None,
                 locations_filter: List[int] = None,
                 max_files_per_run: int = 10):
        self.broker_url = broker_url
        self.use_real_data = use_real_data
        self.data_limit = data_limit
        self.start_timestamp = start_timestamp
        self.sensor_types_filter = sensor_types_filter
        self.locations_filter = locations_filter
        self.max_files_per_run = max_files_per_run
        
        self.redis_client = self._create_redis_client()
        self.redis_key = "sensors:sent_hashes"
        
        print(f"🚀 Инициализация SensorsDataProducer")
        print(f"   Broker: {broker_url}")
        print(f"   Реальные данные: {use_real_data}")
        print(f"   Лимит данных: {data_limit}")
        print(f"   Start timestamp: {start_timestamp or 'не задан'}")
        
        self.producer = self._create_producer()
        
        self.data_source = self._load_data()
        self.data_index = 0
        
        print(f"✅ Продьюсер инициализирован с {len(self.data_source)} записями")

    def _create_producer(self) -> KafkaProducer:
        producer_config = {
            'bootstrap_servers': [self.broker_url],
            'value_serializer': lambda v: json.dumps(v, ensure_ascii=False).encode('utf-8'),
            'key_serializer': lambda v: v.encode('utf-8') if v else None,
            'retries': 5,
            'retry_backoff_ms': 1000,
            'batch_size': 16384,
            'linger_ms': 10,
            'buffer_memory': 33554432
        }
        max_retries = 10
        for i in range(max_retries):
            try:
                producer = KafkaProducer(**producer_config)
                print(f"✅ Успешное подключение к Kafka брокеру {self.broker_url}")
                return producer
            except NoBrokersAvailable:
                wait_time = min(10 * (i + 1), 60)
                print(f"⚠️ Нет доступных брокеров. Попытка {i+1}/{max_retries}. Ждем {wait_time}с...")
                time.sleep(wait_time)
        raise Exception(f"Не удалось подключиться к Kafka после {max_retries} попыток")

    def _create_redis_client(self) -> redis.Redis:
        try:
            redis_client = redis.Redis(host='redis', port=6379, db=0, decode_responses=True, socket_connect_timeout=5, socket_timeout=5)
            redis_client.ping()
            print(f"✅ Успешное подключение к Redis для дедупликации")
            return redis_client
        except Exception as e:
            print(f"⚠️ Ошибка подключения к Redis: {e}. Дедупликация будет работать только в рамках текущей сессии")
            return None

    def _is_hash_sent(self, record_hash: str) -> bool:
        if not record_hash: return False
        try:
            if self.redis_client:
                return self.redis_client.sismember(self.redis_key, record_hash)
            if not hasattr(self, '_local_sent_hashes'):
                self._local_sent_hashes = set()
            return record_hash in self._local_sent_hashes
        except Exception as e:
            print(f"⚠️ Ошибка проверки дедупликации: {e}")
            return False

    def _mark_hash_sent(self, record_hash: str) -> bool:
        if not record_hash: return False
        try:
            if self.redis_client:
                if self.redis_client.sadd(self.redis_key, record_hash):
                    self.redis_client.expire(self.redis_key, 604800)
                return True
            if not hasattr(self, '_local_sent_hashes'):
                self._local_sent_hashes = set()
            self._local_sent_hashes.add(record_hash)
            return True
        except Exception as e:
            print(f"⚠️ Ошибка сохранения hash дедупликации: {e}")
            return False

    def _load_data(self) -> List[Dict]:
        if self.use_real_data:
            return load_sensors_real_data(
                limit=self.data_limit,
                start_timestamp=self.start_timestamp,
                sensor_types_filter=self.sensor_types_filter,
                location_filter=self.locations_filter,
                fallback_to_test_generation=False,
                max_files_per_run=self.max_files_per_run
            )
        return load_sensors_sample_data(limit=self.data_limit)

    def _send_message(self, topic: str, message: Dict, key: Optional[str] = None) -> bool:
        try:
            if not key and 'sensor_id' in message and 'timestamp' in message:
                key = f"{message['sensor_id']}_{message['timestamp'][:19].replace(' ', '_')}"
            future = self.producer.send(topic, value=message, key=key)
            record_metadata = future.get(timeout=10)
            print(f"✅ Отправлено в {topic}: sensor_id={message.get('sensor_id')} {message.get('timestamp', '')[:19]} (partition={record_metadata.partition}, offset={record_metadata.offset})")
            return True
        except KafkaError as e:
            print(f"❌ Kafka ошибка при отправке в {topic}: {e}")
            return False
        except Exception as e:
            print(f"❌ Общая ошибка при отправке в {topic}: {e}")
            return False

    def send_data_batch(self, topic: str, batch_size: int) -> (int, Optional[str]):
        print(f"📤 Отправка батча данных Environmental Sensors (размер: {batch_size})")
        if not self.data_source:
            print("   ... источник данных пуст, отправлять нечего.")
            return 0, None
        
        sent_count = 0
        batch_data = []
        max_timestamp = None
        
        attempts = 0
        max_attempts = batch_size * 10
        
        while len(batch_data) < batch_size and attempts < max_attempts:
            if self.data_index >= len(self.data_source):
                self.data_index = 0
            
            record = self.data_source[self.data_index]
            self.data_index += 1
            attempts += 1
            
            full_record = get_full_record(record)
            if not full_record:
                continue

            record_hash = full_record.get('record_hash')
            if record_hash and self._is_hash_sent(record_hash):
                print(f"   🔄 Пропуск дубля: hash {record_hash}")
                continue
                
            batch_data.append(full_record)
        
        for record in batch_data:
            if self._send_message(topic, record):
                sent_count += 1
                record_hash = record.get('record_hash')
                if record_hash:
                    self._mark_hash_sent(record_hash)
                if max_timestamp is None or record['timestamp'] > max_timestamp:
                    max_timestamp = record['timestamp']
        
        self.producer.flush()
        print(f"📊 Отправлено {sent_count}/{len(batch_data)} сообщений")
        if max_timestamp:
            print(f"   Максимальный timestamp в батче: {max_timestamp}")
        return sent_count, max_timestamp

    def get_stats(self) -> Dict:
        hashes_count = 0
        try:
            if self.redis_client:
                hashes_count = self.redis_client.scard(self.redis_key)
            elif hasattr(self, '_local_sent_hashes'):
                hashes_count = len(self._local_sent_hashes)
        except Exception as e:
            print(f"⚠️ Ошибка получения статистики дедупликации: {e}")
        
        return {
            'total_records': len(self.data_source),
            'current_index': self.data_index,
            'sent_hashes': hashes_count,
            'redis_connected': self.redis_client is not None
        }
    
    def close(self):
        if hasattr(self, 'producer'):
            self.producer.flush()
            self.producer.close()
        if hasattr(self, 'redis_client') and self.redis_client:
            try:
                self.redis_client.close()
                print("🔒 Redis соединение закрыто")
            except Exception as e:
                print(f"⚠️ Ошибка при закрытии Redis: {e}")
        print("🔒 Продьюсер Environmental Sensors закрыт")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Environmental Sensors Kafka Producer")
    parser.add_argument("--broker", default='kafka:9092', help="URL Kafka брокера")
    parser.add_argument("--topic", default='sensors', help="Название топика")
    parser.add_argument("--batch-size", type=int, default=1000, help="Размер батча")
    parser.add_argument("--real-data", action='store_true', help="Использовать реальные данные")
    parser.add_argument("--data-limit", type=int, default=2000, help="Количество записей для загрузки")
    args = parser.parse_args()
    
    producer = SensorsDataProducer(
        broker_url=args.broker,
        use_real_data=args.real_data,
        data_limit=args.data_limit
    )
    
    try:
        sent_count, _ = producer.send_data_batch(
            topic=args.topic,
            batch_size=args.batch_size
        )
        print(f"✅ Отправлено {sent_count} сообщений.")
    finally:
        producer.close()
