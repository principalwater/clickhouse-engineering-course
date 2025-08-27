import time
import json
import argparse
from datetime import datetime
from typing import List, Dict, Optional
from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable, KafkaError
from covid_schemas import (
    load_covid_real_data, 
    load_covid_sample_data, 
    get_daily_record, 
    get_cumulative_record,
    filter_by_location,
    filter_by_date_range
)

class CovidDataProducer:
    """
    Продьюсер данных COVID-19 для Apache Kafka
    
    Поддерживает отправку данных в топики:
    - covid_daily_1min: новые случаи заболевания  
    - covid_cumulative_5min: накопительные данные
    """
    
    def __init__(self, 
                 broker_url: str = 'kafka:9092',
                 use_real_data: bool = True,
                 data_limit: int = 1000):
        """
        Инициализация продьюсера
        
        Args:
            broker_url: URL Kafka брокера
            use_real_data: Использовать реальные данные (True) или тестовые (False)
            data_limit: Количество записей для загрузки
        """
        self.broker_url = broker_url
        self.use_real_data = use_real_data
        self.data_limit = data_limit
        
        print(f"🚀 Инициализация CovidDataProducer")
        print(f"   Broker: {broker_url}")
        print(f"   Реальные данные: {use_real_data}")
        print(f"   Лимит данных: {data_limit}")
        
        # Создаем продьюсер
        self.producer = self._create_producer()
        
        # Загружаем данные
        self.data_source = self._load_data()
        self.data_index = 0
        
        print(f"✅ Продьюсер инициализирован с {len(self.data_source)} записями")
    
    def _create_producer(self) -> KafkaProducer:
        """Создает и возвращает Kafka продьюсер с повторными попытками"""
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
        retry_count = 0
        
        while retry_count < max_retries:
            try:
                producer = KafkaProducer(**producer_config)
                print(f"✅ Успешное подключение к Kafka брокеру {self.broker_url}")
                return producer
                
            except NoBrokersAvailable:
                retry_count += 1
                wait_time = min(10 * retry_count, 60)
                print(f"⚠️ Нет доступных брокеров. Попытка {retry_count}/{max_retries}. "
                      f"Ждем {wait_time}с...")
                time.sleep(wait_time)
                
            except Exception as e:
                retry_count += 1
                print(f"❌ Ошибка подключения к Kafka: {e}. "
                      f"Попытка {retry_count}/{max_retries}")
                time.sleep(5)
        
        raise Exception(f"Не удалось подключиться к Kafka после {max_retries} попыток")
    
    def _load_data(self) -> List[Dict]:
        """Загружает данные COVID-19"""
        if self.use_real_data:
            return load_covid_real_data(limit=self.data_limit)
        else:
            return load_covid_sample_data(limit=self.data_limit)
    
    def _send_message(self, topic: str, message: Dict, key: Optional[str] = None) -> bool:
        """
        Отправляет сообщение в Kafka топик
        
        Args:
            topic: Название топика
            message: Данные для отправки
            key: Ключ сообщения (опционально)
        
        Returns:
            bool: True если отправка успешна
        """
        try:
            # Создаем ключ на основе location_key и date для партиционирования
            if not key and 'location_key' in message and 'date' in message:
                key = f"{message['location_key']}_{message['date']}"
            
            future = self.producer.send(topic, value=message, key=key)
            
            # Ждем подтверждения отправки
            record_metadata = future.get(timeout=10)
            
            print(f"✅ Отправлено в {topic}: {message['location_key']} {message['date']} "
                  f"(partition={record_metadata.partition}, offset={record_metadata.offset})")
            return True
            
        except KafkaError as e:
            print(f"❌ Kafka ошибка при отправке в {topic}: {e}")
            return False
            
        except Exception as e:
            print(f"❌ Общая ошибка при отправке в {topic}: {e}")
            return False
    
    def send_daily_data_batch(self, 
                              topic: str = 'covid_daily_1min', 
                              batch_size: int = 10,
                              locations_filter: List[str] = None) -> int:
        """
        Отправляет батч новых случаев COVID-19 в топик
        
        Args:
            topic: Название топика
            batch_size: Размер батча
            locations_filter: Фильтр по локациям
        
        Returns:
            int: Количество успешно отправленных сообщений
        """
        print(f"📤 Отправка батча новых случаев COVID-19 (размер: {batch_size})")
        
        sent_count = 0
        batch_data = []
        
        # Собираем батч данных
        attempts = 0
        max_attempts = batch_size * 10  # предотвращаем бесконечный цикл
        
        while len(batch_data) < batch_size and attempts < max_attempts:
            if self.data_index >= len(self.data_source):
                self.data_index = 0  # Начинаем сначала
            
            record = self.data_source[self.data_index]
            self.data_index += 1
            attempts += 1
            
            # Фильтрация по локациям
            if locations_filter and record['location_key'] not in locations_filter:
                continue
                
            daily_record = get_daily_record(record)
            batch_data.append(daily_record)
        
        # Отправляем батч
        for record in batch_data:
            if self._send_message(topic, record):
                sent_count += 1
        
        self.producer.flush()
        print(f"📊 Отправлено {sent_count}/{len(batch_data)} сообщений новых случаев")
        return sent_count
    
    def send_cumulative_data_batch(self, 
                                   topic: str = 'covid_cumulative_5min', 
                                   batch_size: int = 5,
                                   locations_filter: List[str] = None) -> int:
        """
        Отправляет батч накопительных данных COVID-19 в топик
        
        Args:
            topic: Название топика  
            batch_size: Размер батча
            locations_filter: Фильтр по локациям
        
        Returns:
            int: Количество успешно отправленных сообщений
        """
        print(f"📤 Отправка батча накопительных данных COVID-19 (размер: {batch_size})")
        
        sent_count = 0
        batch_data = []
        
        # Собираем батч данных
        attempts = 0
        max_attempts = batch_size * 10  # предотвращаем бесконечный цикл
        
        while len(batch_data) < batch_size and attempts < max_attempts:
            if self.data_index >= len(self.data_source):
                self.data_index = 0  # Начинаем сначала
            
            record = self.data_source[self.data_index]
            self.data_index += 1
            attempts += 1
            
            # Фильтрация по локациям
            if locations_filter and record['location_key'] not in locations_filter:
                continue
                
            cumulative_record = get_cumulative_record(record)
            batch_data.append(cumulative_record)
        
        # Отправляем батч
        for record in batch_data:
            if self._send_message(topic, record):
                sent_count += 1
        
        self.producer.flush()
        print(f"📊 Отправлено {sent_count}/{len(batch_data)} сообщений накопительных данных")
        return sent_count
    
    def run_daily_producer(self, 
                           topic: str = 'covid_daily_1min',
                           batch_size: int = 10, 
                           interval_seconds: int = 60,
                           max_iterations: int = None,
                           locations_filter: List[str] = None):
        """
        Запускает продьюсер новых случаев с заданным интервалом
        
        Args:
            topic: Название топика
            batch_size: Размер батча
            interval_seconds: Интервал между отправками в секундах  
            max_iterations: Максимальное количество итераций (None = бесконечно)
            locations_filter: Фильтр по локациям
        """
        print(f"🚀 Запуск продьюсера новых случаев COVID-19")
        print(f"   Топик: {topic}")
        print(f"   Размер батча: {batch_size}")
        print(f"   Интервал: {interval_seconds} секунд")
        print(f"   Макс итераций: {max_iterations or 'бесконечно'}")
        print(f"   Фильтр локаций: {locations_filter or 'все'}")
        
        iteration = 0
        
        try:
            while max_iterations is None or iteration < max_iterations:
                iteration += 1
                start_time = time.time()
                
                print(f"\n--- Итерация {iteration} ({datetime.now().strftime('%H:%M:%S')}) ---")
                
                # Отправляем батч
                sent_count = self.send_daily_data_batch(
                    topic=topic,
                    batch_size=batch_size,
                    locations_filter=locations_filter
                )
                
                elapsed_time = time.time() - start_time
                print(f"⏱️ Время выполнения: {elapsed_time:.2f}s")
                
                # Ждем до следующей итерации
                if max_iterations is None or iteration < max_iterations:
                    print(f"⏳ Ожидание {interval_seconds} секунд...")
                    time.sleep(interval_seconds)
                    
        except KeyboardInterrupt:
            print(f"\n🛑 Остановка продьюсера пользователем")
        except Exception as e:
            print(f"❌ Ошибка в продьюсере: {e}")
        finally:
            self.close()
    
    def run_cumulative_producer(self, 
                                topic: str = 'covid_cumulative_5min',
                                batch_size: int = 5, 
                                interval_seconds: int = 300,
                                max_iterations: int = None,
                                locations_filter: List[str] = None):
        """
        Запускает продьюсер накопительных данных с заданным интервалом
        
        Args:
            topic: Название топика
            batch_size: Размер батча
            interval_seconds: Интервал между отправками в секундах
            max_iterations: Максимальное количество итераций (None = бесконечно)
            locations_filter: Фильтр по локациям
        """
        print(f"🚀 Запуск продьюсера накопительных данных COVID-19")
        print(f"   Топик: {topic}")
        print(f"   Размер батча: {batch_size}")
        print(f"   Интервал: {interval_seconds} секунд")
        print(f"   Макс итераций: {max_iterations or 'бесконечно'}")
        print(f"   Фильтр локаций: {locations_filter or 'все'}")
        
        iteration = 0
        
        try:
            while max_iterations is None or iteration < max_iterations:
                iteration += 1
                start_time = time.time()
                
                print(f"\n--- Итерация {iteration} ({datetime.now().strftime('%H:%M:%S')}) ---")
                
                # Отправляем батч
                sent_count = self.send_cumulative_data_batch(
                    topic=topic,
                    batch_size=batch_size,
                    locations_filter=locations_filter
                )
                
                elapsed_time = time.time() - start_time
                print(f"⏱️ Время выполнения: {elapsed_time:.2f}s")
                
                # Ждем до следующей итерации
                if max_iterations is None or iteration < max_iterations:
                    print(f"⏳ Ожидание {interval_seconds} секунд...")
                    time.sleep(interval_seconds)
                    
        except KeyboardInterrupt:
            print(f"\n🛑 Остановка продьюсера пользователем")
        except Exception as e:
            print(f"❌ Ошибка в продьюсере: {e}")
        finally:
            self.close()
    
    def get_stats(self) -> Dict:
        """Возвращает статистику продьюсера"""
        return {
            'total_records': len(self.data_source),
            'current_index': self.data_index,
            'broker_url': self.broker_url,
            'use_real_data': self.use_real_data
        }
    
    def close(self):
        """Закрывает продьюсер"""
        if hasattr(self, 'producer'):
            self.producer.flush()
            self.producer.close()
            print("🔒 Продьюсер закрыт")

def main():
    """Основная функция для запуска продьюсера из командной строки"""
    parser = argparse.ArgumentParser(description="COVID-19 Kafka Producer")
    
    parser.add_argument("--type", 
                        choices=['daily', 'cumulative'], 
                        required=True,
                        help="Тип данных для отправки")
    
    parser.add_argument("--broker", 
                        default='kafka:9092',
                        help="URL Kafka брокера")
    
    parser.add_argument("--batch-size", 
                        type=int, 
                        default=10,
                        help="Размер батча для отправки")
    
    parser.add_argument("--interval", 
                        type=int, 
                        default=60,
                        help="Интервал между отправками в секундах")
    
    parser.add_argument("--iterations", 
                        type=int,
                        help="Максимальное количество итераций")
    
    parser.add_argument("--real-data", 
                        action='store_true',
                        help="Использовать реальные данные COVID-19")
    
    parser.add_argument("--data-limit", 
                        type=int, 
                        default=1000,
                        help="Количество записей для загрузки")
    
    parser.add_argument("--locations",
                        nargs='+',
                        help="Фильтр по кодам локаций (например: US GB DE)")
    
    parser.add_argument("--topic-daily", 
                        default='covid_daily_1min',
                        help="Название топика для новых случаев")
    
    parser.add_argument("--topic-cumulative", 
                        default='covid_cumulative_5min',
                        help="Название топика для накопительных данных")
    
    args = parser.parse_args()
    
    # Создаем продьюсер
    producer = CovidDataProducer(
        broker_url=args.broker,
        use_real_data=args.real_data,
        data_limit=args.data_limit
    )
    
    try:
        if args.type == 'daily':
            # Продьюсер новых случаев
            producer.run_daily_producer(
                topic=args.topic_daily,
                batch_size=args.batch_size,
                interval_seconds=args.interval,
                max_iterations=args.iterations,
                locations_filter=args.locations
            )
        else:
            # Продьюсер накопительных данных
            producer.run_cumulative_producer(
                topic=args.topic_cumulative,
                batch_size=args.batch_size,
                interval_seconds=args.interval,
                max_iterations=args.iterations,
                locations_filter=args.locations
            )
    finally:
        producer.close()

if __name__ == "__main__":
    main()