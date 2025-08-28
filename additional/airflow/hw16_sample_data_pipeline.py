from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# Определение параметров DAG
default_args = {
    'owner': 'airflow-team',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Создание DAG
dag = DAG(
    'hw16_sample_data_pipeline',
    default_args=default_args,
    description='Sample data processing pipeline for hw16',
    schedule=timedelta(hours=1),
    catchup=False,
    tags=['hw16', 'data-loading'],
)

def extract_data(**context):
    """Извлечение данных из источников"""
    print("Извлечение данных...")
    # Здесь будет логика извлечения данных
    return "Data extracted successfully"

def transform_data(**context):
    """Трансформация данных"""
    print("Трансформация данных...")
    # Здесь будет логика трансформации данных
    return "Data transformed successfully"

def load_data(**context):
    """Загрузка данных в хранилище"""
    print("Загрузка данных...")
    # Здесь будет логика загрузки данных
    return "Data loaded successfully"

# Определение задач
extract_task = PythonOperator(
    task_id='extract_data',
    python_callable=extract_data,
    dag=dag,
)

transform_task = PythonOperator(
    task_id='transform_data',
    python_callable=transform_data,
    dag=dag,
)

load_task = PythonOperator(
    task_id='load_data',
    python_callable=load_data,
    dag=dag,
)

health_check = BashOperator(
    task_id='health_check',
    bash_command='echo "hw16 pipeline is healthy"',
    dag=dag,
)

# Определение зависимостей задач
extract_task >> transform_task >> load_task >> health_check
