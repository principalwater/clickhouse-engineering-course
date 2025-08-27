from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
import clickhouse_connect
import os
import random

# Определение параметров DAG
default_args = {
    'owner': 'hw16-student',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

# Создание DAG для загрузки демо-данных в ClickHouse
data_loading_dag = DAG(
    'hw16_data_loading_pipeline',
    default_args=default_args,
    description='HW16: Загрузка демонстрационных данных в ClickHouse',
    schedule=None,  # Запуск вручную
    catchup=False,
    tags=['hw16', 'clickhouse', 'data-loading', 'demo'],
)

def create_tables_in_clickhouse():
    """Создание таблиц в ClickHouse с использованием clickhouse-connect."""
    try:
        print("Подключение к ClickHouse для создания таблиц...")
        client = clickhouse_connect.get_client(
            host=os.getenv('CLICKHOUSE_HOST', 'clickhouse-01'),
            port=int(os.getenv('CLICKHOUSE_PORT', '8123')),
            username=os.getenv('CLICKHOUSE_USER', 'default'),
            password=os.getenv('CLICKHOUSE_PASSWORD', ''),
            database='otus_default'
        )
        
        create_local_table_sql = """
        CREATE TABLE IF NOT EXISTS otus_default.hw16_demo_products_local ON CLUSTER dwh_test (
            id UInt32,
            name String,
            category String,
            price Decimal(10, 2),
            created_at DateTime
        ) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/otus_default/hw16_demo_products_local/{uuid}', '{replica}')
        ORDER BY id
        PARTITION BY toYYYYMM(created_at)
        """
        
        create_distributed_table_sql = """
        CREATE TABLE IF NOT EXISTS otus_default.hw16_demo_products ON CLUSTER dwh_test 
        AS otus_default.hw16_demo_products_local
        ENGINE = Distributed('dwh_test', 'otus_default', 'hw16_demo_products_local', cityHash64(id))
        """
        
        print("Создание локальной таблицы...")
        client.command(create_local_table_sql)
        
        print("Создание распределенной таблицы...")
        client.command(create_distributed_table_sql)
        
        print("Таблицы успешно созданы.")
        
    except Exception as e:
        print(f"Ошибка при создании таблиц: {e}")
        raise

def create_sample_data():
    """Генерация демонстрационных данных"""
    data = []
    for i in range(100):
        data.append({
            'id': i + 1,
            'name': f'Product_{i+1}',
            'category': random.choice(['Electronics', 'Books', 'Clothing', 'Home', 'Sports']),
            'price': round(random.uniform(10.0, 1000.0), 2),
            'created_at': datetime.now() - timedelta(days=random.randint(1, 365))
        })
    return data

def load_data_to_clickhouse(**context):
    """Загрузка данных в ClickHouse"""
    try:
        print("Подключение к ClickHouse...")
        
        client = clickhouse_connect.get_client(
            host=os.getenv('CLICKHOUSE_HOST', 'clickhouse-01'),
            port=int(os.getenv('CLICKHOUSE_PORT', '8123')),
            username=os.getenv('CLICKHOUSE_USER', 'default'),
            password=os.getenv('CLICKHOUSE_PASSWORD', ''),
            database='otus_default'
        )
        
        print("Генерация демонстрационных данных...")
        data = create_sample_data()
        
        print("Загрузка данных в ClickHouse...")
        values = []
        for item in data:
            values.append([
                item['id'], 
                item['name'], 
                item['category'], 
                item['price'], 
                item['created_at']
            ])
        
        client.insert(
            'hw16_demo_products',
            values,
            column_names=['id', 'name', 'category', 'price', 'created_at']
        )
        
        result = client.query('SELECT count() FROM hw16_demo_products')
        count = result.first_row[0]
        
        shards_result = client.query('''
            SELECT 
                hostName() as host,
                count() as records_count
            FROM otus_default.hw16_demo_products_local 
            GROUP BY hostName() 
            ORDER BY host
        ''')
        
        print(f"Успешно загружено {len(data)} записей в распределенную таблицу hw16_demo_products")
        print(f"Общее количество записей в кластере: {count}")
        print("Распределение данных по шардам:")
        for row in shards_result.result_rows:
            print(f"  - {row[0]}: {row[1]} записей")
        
        return f"Successfully loaded {len(data)} records"
        
    except Exception as e:
        print(f"Ошибка при загрузке данных: {e}")
        raise

def validate_data(**context):
    """Проверка загруженных данных"""
    try:
        print("Проверка загруженных данных...")
        
        client = clickhouse_connect.get_client(
            host=os.getenv('CLICKHOUSE_HOST', 'clickhouse-01'),
            port=int(os.getenv('CLICKHOUSE_PORT', '8123')),
            username=os.getenv('CLICKHOUSE_USER', 'default'),
            password=os.getenv('CLICKHOUSE_PASSWORD', ''),
            database='otus_default'
        )
        
        total_count = client.query('SELECT count() FROM hw16_demo_products').first_row[0]
        
        category_stats = client.query('''
            SELECT category, count() as cnt 
            FROM hw16_demo_products 
            GROUP BY category 
            ORDER BY cnt DESC
        ''').result_rows
        
        avg_price = client.query('SELECT round(avg(price), 2) FROM hw16_demo_products').first_row[0]
        
        replication_stats = client.query('''
            SELECT 
                hostName() as host,
                count() as local_records
            FROM otus_default.hw16_demo_products_local 
            GROUP BY hostName() 
            ORDER BY host
        ''').result_rows
        
        partition_stats = client.query('''
            SELECT 
                partition,
                count() as records_in_partition
            FROM system.parts 
            WHERE database = 'otus_default' 
                AND table = 'hw16_demo_products_local' 
                AND active = 1
            GROUP BY partition 
            ORDER BY partition
        ''').result_rows
        
        print(f"Общее количество записей в кластере: {total_count}")
        print(f"Средняя цена товара: ${avg_price}")
        print("Статистика по категориям:")
        for category, count in category_stats:
            print(f"  - {category}: {count} товаров")
        
        print("Состояние репликации по узлам:")
        for host, local_count in replication_stats:
            print(f"  - {host}: {local_count} записей")
        
        print("Распределение по партициям:")
        for partition, part_count in partition_stats:
            print(f"  - Партиция {partition}: {part_count} частей")
        
        if total_count > 0:
            print("Валидация данных прошла успешно")
            return "Data validation successful"
        else:
            raise Exception("No data found in table")
            
    except Exception as e:
        print(f"Ошибка при валидации данных: {e}")
        raise

# Определение задач
create_table_task = PythonOperator(
    task_id='create_demo_tables',
    python_callable=create_tables_in_clickhouse,
    dag=data_loading_dag,
)

load_data_task = PythonOperator(
    task_id='load_sample_data',
    python_callable=load_data_to_clickhouse,
    dag=data_loading_dag,
)

validate_data_task = PythonOperator(
    task_id='validate_loaded_data',
    python_callable=validate_data,
    dag=data_loading_dag,
)

# Определение зависимостей
create_table_task >> load_data_task >> validate_data_task
