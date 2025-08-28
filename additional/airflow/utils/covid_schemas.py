import random
import requests
import polars as pl
from datetime import datetime, timedelta
from typing import List, Dict

# Реальные коды стран для COVID-19 данных
SAMPLE_LOCATIONS = [
    'US', 'GB', 'DE', 'FR', 'IT', 'ES', 'RU', 'CN', 'JP', 'KR',
    'BR', 'IN', 'CA', 'AU', 'MX', 'AR', 'TR', 'SA', 'ZA', 'EG'
]

def load_covid_real_data(limit: int = 10000, start_date: str = None, locations_filter: List[str] = None) -> List[Dict]:
    """
    Загружает и фильтрует реальные данные COVID-19 из Google Cloud Storage с использованием Polars и lazy evaluation.
    
    Args:
        limit: Максимальное количество записей для загрузки.
        start_date: Дата, с которой начинать загрузку (не включительно).
        locations_filter: Список кодов стран для фильтрации.
    
    Returns:
        List[Dict]: Список записей COVID-19
    """
    try:
        if start_date:
            print(f"🔄 Загрузка данных с Polars lazy evaluation (после {start_date}, лимит {limit}, страны: {locations_filter or 'все'})...")
        else:
            print(f"🔄 Загрузка данных с Polars lazy evaluation (лимит {limit}, страны: {locations_filter or 'все'})...")
            
        url = "https://storage.googleapis.com/covid19-open-data/v3/epidemiology.csv"
        print(f"   URL: {url}")
        
        print("   Шаг 1: Создание lazy query с pushdown фильтрацией...")
        
        # Создаем lazy dataframe с автоматическим определением схемы
        lazy_df = pl.scan_csv(url, try_parse_dates=True)
        
        # Применяем фильтры с pushdown оптимизацией
        print("   Шаг 2: Применение фильтров...")
        
        # Убираем записи с пустыми date и location_key
        lazy_df = lazy_df.filter(
            pl.col("date").is_not_null() & 
            pl.col("location_key").is_not_null()
        )
        
        # Фильтр по дате (pushdown)
        if start_date:
            print(f"   ...фильтр по дате > {start_date}")
            # Конвертируем строку даты в datetime для корректного сравнения
            start_date_dt = pl.datetime(int(start_date[:4]), int(start_date[5:7]), int(start_date[8:10]))
            lazy_df = lazy_df.filter(pl.col("date") > start_date_dt)
        
        # Фильтр по странам (pushdown) 
        if locations_filter:
            print(f"   ...фильтр по странам: {locations_filter}")
            lazy_df = lazy_df.filter(pl.col("location_key").is_in(locations_filter))
        
        # Сортировка для стабильного порядка
        lazy_df = lazy_df.sort(["date", "location_key"])
        
        # Применяем лимит (pushdown)
        if limit:
            lazy_df = lazy_df.limit(limit)
        
        print("   Шаг 3: Выполнение lazy query с оптимизациями...")
        
        # Выполняем lazy query - здесь происходит вся магия оптимизации
        df = lazy_df.collect()
        
        if df.height == 0:
            print("✅ Не найдено новых записей, соответствующих фильтрам.")
            return []
        
        print("   Шаг 4: Обработка данных...")
        
        # Заполняем пропуски нулями для численных колонок
        numeric_cols = ['new_confirmed', 'new_deceased', 'new_recovered', 'new_tested', 
                       'cumulative_confirmed', 'cumulative_deceased', 'cumulative_recovered', 'cumulative_tested']
        
        # Проверяем какие колонки действительно существуют в данных
        existing_numeric_cols = [col for col in numeric_cols if col in df.columns]
        
        if existing_numeric_cols:
            df = df.with_columns([
                pl.col(col).fill_null(0).cast(pl.Int64, strict=False) for col in existing_numeric_cols
            ])
        
        # Форматируем дату в YYYY-MM-DD
        df = df.with_columns([
            pl.col("date").dt.strftime("%Y-%m-%d").alias("date")
        ])
        
        print(f"✅ Успешно обработано {df.height} записей реальных данных COVID-19 с Polars")
        
        # Конвертируем в список словарей
        return df.to_dicts()
        
    except Exception as e:
        import traceback
        print(f"❌ Критическая ошибка при загрузке реальных данных с Polars: {e}")
        print(traceback.format_exc())
        print("🔄 Переходим на генерацию тестовых данных...")
        return load_covid_sample_data(limit)

def load_covid_sample_data(limit: int = 1000) -> List[Dict]:
    """
    Генерирует образец данных COVID-19 для тестирования
    
    Args:
        limit: Количество записей для генерации
    
    Returns:
        List[Dict]: Список сгенерированных записей COVID-19
    """
    print(f"🔄 Генерация {limit} тестовых записей COVID-19...")
    
    base_date = datetime(2020, 3, 1)
    sample_data = []
    
    for i in range(limit):
        # Случайная дата в период пандемии
        days_offset = i % 1000  # Распределяем по ~3 годам
        date = base_date + timedelta(days=days_offset)
        
        # Случайная локация
        location = random.choice(SAMPLE_LOCATIONS)
        
        # Генерируем реалистичные данные COVID-19
        # Новые случаи с трендом (больше в начале пандемии)
        base_new = max(0, random.randint(0, 50000) - days_offset * 10)
        
        new_confirmed = max(0, base_new + random.randint(-base_new//4, base_new//4))
        new_deceased = max(0, int(new_confirmed * random.uniform(0.005, 0.05)))  # 0.5-5% CFR
        new_recovered = max(0, int(new_confirmed * random.uniform(0.7, 0.95)))   # 70-95% recovery
        new_tested = max(new_confirmed, int(new_confirmed * random.uniform(5, 20)))  # Тестируем больше
        
        # Накопительные данные (растут со временем)
        cumulative_multiplier = 1 + days_offset * 0.1
        cumulative_confirmed = max(new_confirmed, int(new_confirmed * cumulative_multiplier))
        cumulative_deceased = max(new_deceased, int(new_deceased * cumulative_multiplier))  
        cumulative_recovered = max(new_recovered, int(new_recovered * cumulative_multiplier))
        cumulative_tested = max(new_tested, int(new_tested * cumulative_multiplier))
        
        record = {
            'date': date.strftime('%Y-%m-%d'),
            'location_key': location,
            'new_confirmed': new_confirmed,
            'new_deceased': new_deceased,
            'new_recovered': new_recovered,
            'new_tested': new_tested,
            'cumulative_confirmed': cumulative_confirmed,
            'cumulative_deceased': cumulative_deceased,
            'cumulative_recovered': cumulative_recovered,
            'cumulative_tested': cumulative_tested
        }
        sample_data.append(record)
    
    print(f"✅ Сгенерировано {len(sample_data)} тестовых записей COVID-19")
    return sample_data

def get_daily_record(record: Dict) -> Dict:
    """
    Извлекает данные для топика covid_daily_1min (новые случаи)
    
    Args:
        record: Полная запись COVID-19
    
    Returns:
        Dict: Данные новых случаев для Kafka
    """
    return {
        'date': record['date'],
        'location_key': record['location_key'],
        'new_confirmed': record.get('new_confirmed', 0),
        'new_deceased': record.get('new_deceased', 0),
        'new_recovered': record.get('new_recovered', 0),
        'new_tested': record.get('new_tested', 0)
    }

def get_cumulative_record(record: Dict) -> Dict:
    """
    Извлекает данные для топика covid_cumulative_5min (накопительные данные)
    
    Args:
        record: Полная запись COVID-19
    
    Returns:
        Dict: Накопительные данные для Kafka
    """
    return {
        'date': record['date'],
        'location_key': record['location_key'],
        'cumulative_confirmed': record.get('cumulative_confirmed', 0),
        'cumulative_deceased': record.get('cumulative_deceased', 0),
        'cumulative_recovered': record.get('cumulative_recovered', 0),
        'cumulative_tested': record.get('cumulative_tested', 0)
    }

def filter_by_location(data: List[Dict], locations: List[str] = None) -> List[Dict]:
    """
    Фильтрует данные по списку локаций
    
    Args:
        data: Исходные данные
        locations: Список кодов локаций для фильтрации
    
    Returns:
        List[Dict]: Отфильтрованные данные
    """
    if not locations:
        return data
    
    filtered = [record for record in data if record['location_key'] in locations]
    print(f"🔍 Отфильтровано {len(filtered)} записей для локаций: {locations}")
    return filtered

def filter_by_date_range(data: List[Dict], start_date: str = None, end_date: str = None) -> List[Dict]:
    """
    Фильтрует данные по диапазону дат
    
    Args:
        data: Исходные данные
        start_date: Начальная дата (YYYY-MM-DD)
        end_date: Конечная дата (YYYY-MM-DD)
    
    Returns:
        List[Dict]: Отфильтрованные данные
    """
    filtered = data
    
    if start_date:
        filtered = [record for record in filtered if record['date'] >= start_date]
    
    if end_date:
        filtered = [record for record in filtered if record['date'] <= end_date]
    
    if start_date or end_date:
        print(f"📅 Отфильтровано {len(filtered)} записей для периода {start_date} - {end_date}")
    
    return filtered

# Пример использования
if __name__ == "__main__":
    # Тест загрузки данных
    print("=== Тест загрузки данных COVID-19 ===")
    
    # Загрузка реальных данных (небольшой объем для теста)
    real_data = load_covid_real_data(limit=100)
    
    if real_data:
        print(f"Пример реальной записи:")
        print(real_data[0])
        
        print(f"Данные для топика covid_daily_1min:")
        print(get_daily_record(real_data[0]))
        
        print(f"Данные для топика covid_cumulative_5min:")
        print(get_cumulative_record(real_data[0]))
    
    # Тест генерации тестовых данных
    print("\n=== Тест генерации тестовых данных ===")
    sample_data = load_covid_sample_data(limit=50)
    
    if sample_data:
        print(f"Пример тестовой записи:")
        print(sample_data[0])
        
        # Фильтрация по локациям
        us_data = filter_by_location(sample_data, ['US', 'GB'])
        print(f"Записей для US и GB: {len(us_data)}")
        
        # Фильтрация по дате
        recent_data = filter_by_date_range(sample_data, start_date='2020-06-01')
        print(f"Записей с июня 2020: {len(recent_data)}")
