from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from kafka import KafkaProducer
import json
import random
import time

# --- Kafka Producer Configuration ---
def get_kafka_producer():
    """Creates and returns a Kafka producer."""
    return KafkaProducer(
        bootstrap_servers=['kafka:9092'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )

# --- Data Generation ---
def generate_data(topic):
    """Generates sample data for river flow and power output."""
    timestamp = datetime.now().isoformat()
    data = {
        'timestamp': timestamp,
        'river_name': 'Volga',
        'ges_name': 'Zhiguli_GES',
        'water_level_m': round(random.uniform(50, 53), 2),
        'flow_rate_m3_s': round(random.uniform(5000, 8000), 2),
        'power_output_mw': round(random.uniform(2000, 2300), 2)
    }
    return data

# --- Task Functions ---
def generate_and_send_to_kafka(topic, interval_seconds, duration_minutes):
    """Generates data and sends it to a Kafka topic for a specified duration."""
    producer = get_kafka_producer()
    start_time = time.time()
    end_time = start_time + duration_minutes * 60
    
    while time.time() < end_time:
        data = generate_data(topic)
        producer.send(topic, value=data)
        print(f"Sent to {topic}: {data}")
        time.sleep(interval_seconds)
        
    producer.flush()
    producer.close()

# --- DAG Definition ---
default_args = {
    'owner': 'energy-hub',
    'start_date': datetime(2025, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'data_generation_pipeline',
    default_args=default_args,
    description='Pipeline for generating and sending data to Kafka topics',
    schedule=None,  # Manual trigger
    catchup=False,
    tags=['kafka', 'data-generation']
)

# --- Tasks ---

# Task for 1-minute data generation (runs for 10 minutes)
generate_1min_data = PythonOperator(
    task_id='generate_1min_data',
    python_callable=generate_and_send_to_kafka,
    op_kwargs={
        'topic': 'topic_1min',
        'interval_seconds': 5, # Faster for demo purposes
        'duration_minutes': 10
    },
    dag=dag,
)

# Task for 5-minute data generation (runs for 10 minutes)
generate_5min_data = PythonOperator(
    task_id='generate_5min_data',
    python_callable=generate_and_send_to_kafka,
    op_kwargs={
        'topic': 'topic_5min',
        'interval_seconds': 10, # Faster for demo purposes
        'duration_minutes': 10
    },
    dag=dag,
)

# --- Task Dependencies ---
# Tasks run in parallel
[generate_1min_data, generate_5min_data]
