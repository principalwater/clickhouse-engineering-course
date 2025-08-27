from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError, KafkaError
import json
import os
from dotenv import load_dotenv

# Load environment variables
dotenv_path = os.path.join(os.path.dirname(__file__), '../../infra/env/clickhouse.env')
load_dotenv(dotenv_path=dotenv_path)

# Определение параметров DAG
default_args = {
    'owner': 'kafka-topics',
    'depends_on_past': False,
    'start_date': datetime(2025, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=2),
}

# Создание DAG для создания топиков Kafka
kafka_topic_dag = DAG(
    'kafka_topic_create',
    default_args=default_args,
    description='Универсальное создание топиков Kafka на основе JSON конфигурации',
    schedule=None,  # Ручной запуск
    catchup=False,
    tags=['kafka', 'topics', 'create', 'universal'],
)

def get_topic_config(**context):
    """Получение конфигурации топика из параметров DAG"""
    try:
        # Получаем параметры из контекста DAG
        dag_run = context['dag_run']
        conf = dag_run.conf if dag_run else {}
        
        # Параметры по умолчанию для создания топика
        default_config = {
            'topic_name': 'covid_new_cases_1min',
            'partitions': 3,
            'replication_factor': 1,
            'retention_ms': 86400000,  # 1 день
            'cleanup_policy': 'delete',
            'compression_type': 'snappy',
            'description': 'Default COVID-19 new cases topic',
            'schema_description': {
                'date': 'Date in YYYY-MM-DD format',
                'location_key': 'Country/region code',
                'new_confirmed': 'New confirmed cases',
                'new_deceased': 'New deaths',
                'new_recovered': 'New recoveries',
                'new_tested': 'New tests performed'
            },
            'kafka_broker': 'kafka:9092',
            'recreate_topic': False  # пересоздавать топик (удалять существующий)
        }
        
        # Объединяем с переданными параметрами
        config = {**default_config, **conf}
        
        # Валидация обязательных параметров
        required_fields = ['topic_name', 'partitions', 'replication_factor']
        missing_fields = []
        
        for field in required_fields:
            if field not in config or config[field] is None:
                missing_fields.append(field)
        
        if missing_fields:
            raise ValueError(f"Отсутствуют обязательные параметры: {missing_fields}")
        
        # Валидация значений
        if config['partitions'] < 1:
            raise ValueError("Количество партиций должно быть >= 1")
        
        if config['replication_factor'] < 1:
            raise ValueError("Replication factor должен быть >= 1")
        
        print(f"📋 Конфигурация топика:")
        print(f"   Название: {config['topic_name']}")
        print(f"   Партиции: {config['partitions']}")
        print(f"   Replication Factor: {config['replication_factor']}")
        print(f"   Retention: {config['retention_ms']} мс")
        print(f"   Cleanup Policy: {config['cleanup_policy']}")
        print(f"   Compression: {config['compression_type']}")
        print(f"   Описание: {config['description']}")
        print(f"   Kafka Broker: {config['kafka_broker']}")
        print(f"   Пересоздание: {config.get('recreate_topic', False)}")
        
        # Сохраняем конфигурацию в XCom для использования в других задачах
        context['task_instance'].xcom_push(key='topic_config', value=config)
        
        return config
        
    except Exception as e:
        print(f"❌ Ошибка при получении конфигурации топика: {e}")
        raise

def check_kafka_connection(**context):
    """Проверка подключения к Kafka"""
    try:
        config = context['task_instance'].xcom_pull(task_ids='get_topic_config', key='topic_config')
        
        if not config:
            raise ValueError("Конфигурация топика не найдена")
        
        print("🔍 Проверка подключения к Kafka...")
        
        # Создаем клиент администратора для проверки подключения
        admin_client = KafkaAdminClient(
            bootstrap_servers=[config['kafka_broker']],
            request_timeout_ms=10000,
            api_version=(0, 10, 1)
        )
        
        # Получаем метаданные кластера
        metadata = admin_client.list_topics()
        broker_count = len(admin_client._client.cluster.brokers())
        
        admin_client.close()
        
        print(f"✅ Kafka подключение успешно")
        print(f"📊 Доступные брокеры: {broker_count}")
        print(f"📊 Существующих топиков: {len(metadata)}")
        
        return {
            'broker_url': config['kafka_broker'],
            'brokers_count': broker_count,
            'existing_topics_count': len(metadata),
            'connection_status': 'success'
        }
        
    except Exception as e:
        print(f"❌ Ошибка при проверке подключения к Kafka: {e}")
        raise

def check_topic_exists(**context):
    """Проверка существования топика"""
    try:
        config = context['task_instance'].xcom_pull(task_ids='get_topic_config', key='topic_config')
        
        if not config:
            raise ValueError("Конфигурация топика не найдена")
        
        topic_name = config['topic_name']
        
        print(f"🔍 Проверка существования топика: {topic_name}")
        
        # Создаем клиент администратора
        admin_client = KafkaAdminClient(
            bootstrap_servers=[config['kafka_broker']],
            request_timeout_ms=10000,
            api_version=(0, 10, 1)
        )
        
        # Получаем список существующих топиков
        existing_topics = admin_client.list_topics()
        
        admin_client.close()
        
        topic_exists = topic_name in existing_topics
        
        if topic_exists:
            print(f"⚠️ Топик {topic_name} уже существует")
        else:
            print(f"✅ Топик {topic_name} не существует, можно создавать")
        
        result = {
            'topic_name': topic_name,
            'topic_exists': topic_exists,
            'existing_topics': existing_topics,
            'total_topics': len(existing_topics)
        }
        
        # Сохраняем результат в XCom
        context['task_instance'].xcom_push(key='topic_check_result', value=result)
        
        return result
        
    except Exception as e:
        print(f"❌ Ошибка при проверке существования топика: {e}")
        raise

def create_kafka_topic(**context):
    """Создание топика Kafka"""
    try:
        config = context['task_instance'].xcom_pull(task_ids='get_topic_config', key='topic_config')
        check_result = context['task_instance'].xcom_pull(task_ids='check_topic_exists', key='topic_check_result')
        
        if not config:
            raise ValueError("Конфигурация топика не найдена")
        
        if not check_result:
            raise ValueError("Результат проверки топика не найден")
        
        topic_name = config['topic_name']
        recreate_topic = config.get('recreate_topic', False)
        
        # Обработка случая, когда топик уже существует
        if check_result['topic_exists']:
            if recreate_topic:
                print(f"🔥 Пересоздание топика {topic_name} (удаление существующего)")
                
                # Создаем клиент администратора
                admin_client = KafkaAdminClient(
                    bootstrap_servers=[config['kafka_broker']],
                    request_timeout_ms=30000,
                    api_version=(0, 10, 1)
                )
                
                try:
                    # Удаляем существующий топик через kafka-topics команду
                    print(f"🗑️ Удаление топика {topic_name}...")
                    
                    import subprocess
                    
                    # Используем kafka-topics команду для надежного удаления
                    delete_cmd = [
                        'docker', 'exec', 'kafka', 
                        'kafka-topics', '--delete', 
                        '--topic', topic_name,
                        '--bootstrap-server', 'localhost:9092'
                    ]
                    
                    result = subprocess.run(
                        delete_cmd, 
                        capture_output=True, 
                        text=True, 
                        timeout=30
                    )
                    
                    if result.returncode == 0:
                        print(f"✅ Топик {topic_name} успешно удален")
                        print(f"📄 Вывод команды: {result.stdout.strip()}")
                    else:
                        print(f"❌ Ошибка при удалении топика {topic_name}")
                        print(f"📄 Stderr: {result.stderr.strip()}")
                        raise RuntimeError(f"Не удалось удалить топик {topic_name}: {result.stderr}")
                    
                    print(f"⏳ Ожидание полного удаления топика (5 секунд)...")
                    import time
                    time.sleep(5)  # Ждем полного удаления
                    
                except subprocess.TimeoutExpired:
                    print(f"❌ Таймаут при удалении топика {topic_name}")
                    raise RuntimeError(f"Таймаут при удалении топика {topic_name}")
                except Exception as deletion_error:
                    print(f"❌ Общая ошибка при удалении топика: {deletion_error}")
                    raise
                finally:
                    admin_client.close()
                    
                print(f"🆕 Продолжаем создание нового топика {topic_name}")
            else:
                print(f"✅ Топик {topic_name} уже существует, создание не требуется")
                return {
                    'status': 'exists',
                    'topic_name': topic_name,
                    'message': f'Топик {topic_name} уже существует',
                    'created': False,
                    'existing': True
                }
        
        print(f"🚀 Создание нового топика: {topic_name}")
        
        # Создаем клиент администратора
        admin_client = KafkaAdminClient(
            bootstrap_servers=[config['kafka_broker']],
            request_timeout_ms=30000,
            api_version=(0, 10, 1)
        )
        
        # Подготавливаем конфигурацию топика
        topic_configs = {
            'retention.ms': str(config['retention_ms']),
            'cleanup.policy': config['cleanup_policy'],
            'compression.type': config['compression_type']
        }
        
        # Создаем объект топика
        topic = NewTopic(
            name=topic_name,
            num_partitions=config['partitions'],
            replication_factor=config['replication_factor'],
            topic_configs=topic_configs
        )
        
        print(f"📝 Параметры создаваемого топика:")
        print(f"   Партиции: {config['partitions']}")
        print(f"   Replication Factor: {config['replication_factor']}")
        print(f"   Retention: {config['retention_ms']} мс")
        print(f"   Cleanup Policy: {config['cleanup_policy']}")
        print(f"   Compression: {config['compression_type']}")
        
        try:
            # Создаем топик
            future_response = admin_client.create_topics([topic])
            
            # Проверяем результат создания
            for topic_name_result, error_code in future_response.topic_errors:
                if error_code == 0:
                    print(f"✅ Топик {topic_name_result} успешно создан")
                    
                    admin_client.close()
                    
                    return {
                        'status': 'created',
                        'topic_name': topic_name_result,
                        'message': f'Топик {topic_name_result} успешно создан',
                        'created': True,
                        'existing': False,
                        'partitions': config['partitions'],
                        'replication_factor': config['replication_factor'],
                        'config': topic_configs
                    }
                elif error_code == 36: # TOPIC_ALREADY_EXISTS
                    print(f"⚠️ Топик {topic_name_result} уже существует (race condition)")
                    admin_client.close()
                    
                    return {
                        'status': 'exists',
                        'topic_name': topic_name_result,
                        'message': f'Топик {topic_name_result} уже существует (создан во время выполнения)',
                        'created': False,
                        'existing': True
                    }
                else:
                    raise KafkaError(f"Ошибка Kafka: {error_code})")
                    
        except TopicAlreadyExistsError:
            print(f"⚠️ Топик {topic_name} уже существует (перехват исключения)")
            admin_client.close()
            return {
                'status': 'exists',
                'topic_name': topic_name,
                'message': f'Топик {topic_name} уже существует',
                'created': False,
                'existing': True
            }
        except Exception as e:
            print(f"❌ Ошибка при создании топика: {e}")
            raise
        
    except Exception as e:
        print(f"❌ Ошибка при создании топика: {e}")
        raise

def verify_topic_creation(**context):
    """Проверка успешного создания топика"""
    try:
        config = context['task_instance'].xcom_pull(task_ids='get_topic_config', key='topic_config')
        creation_result = context['task_instance'].xcom_pull(task_ids='create_kafka_topic')
        
        if not config or not creation_result:
            raise ValueError("Не найдены необходимые данные для проверки")
        
        topic_name = config['topic_name']
        
        print(f"🔍 Верификация создания топика: {topic_name}")
        
        # Создаем клиент администратора
        admin_client = KafkaAdminClient(
            bootstrap_servers=[config['kafka_broker']],
            request_timeout_ms=10000,
            api_version=(0, 10, 1)
        )
        
        # Получаем актуальный список топиков
        current_topics = admin_client.list_topics()
        
        admin_client.close()
        
        if topic_name in current_topics:
            print(f"✅ Топик {topic_name} подтвержден в списке топиков")
            
            verification_result = {
                'verification_status': 'success',
                'topic_name': topic_name,
                'topic_found': True,
                'creation_result': creation_result,
                'total_topics': len(current_topics)
            }
        else:
            print(f"❌ Топик {topic_name} НЕ найден в списке топиков")
            
            verification_result = {
                'verification_status': 'failed',
                'topic_name': topic_name,
                'topic_found': False,
                'creation_result': creation_result,
                'total_topics': len(current_topics),
                'current_topics': current_topics
            }
            
            raise Exception(f"Топик {topic_name} не найден после создания")
        
        return verification_result
        
    except Exception as e:
        print(f"❌ Ошибка при верификации топика: {e}")
        raise

def generate_topic_summary(**context):
    """Генерация итогового отчета о создании топика"""
    try:
        config = context['task_instance'].xcom_pull(task_ids='get_topic_config', key='topic_config')
        creation_result = context['task_instance'].xcom_pull(task_ids='create_kafka_topic')
        verification_result = context['task_instance'].xcom_pull(task_ids='verify_topic_creation')
        
        print(f"📋 Итоговый отчет о создании топика")
        print(f"=" * 50)
        
        if config:
            print(f"Конфигурация:")
            print(f"  Название: {config['topic_name']}")
            print(f"  Партиции: {config['partitions']}")
            print(f"  Replication Factor: {config['replication_factor']}")
            print(f"  Описание: {config['description']}")
        
        if creation_result:
            print(f"Результат создания:")
            print(f"  Статус: {creation_result['status']}")
            print(f"  Создан: {creation_result['created']}")
            print(f"  Существовал: {creation_result['existing']}")
            print(f"  Сообщение: {creation_result['message']}")
        
        if verification_result:
            print(f"Верификация:")
            print(f"  Статус: {verification_result['verification_status']}")
            print(f"  Топик найден: {verification_result['topic_found']}")
        
        print(f"=" * 50)
        print(f"✅ Операция завершена успешно")
        
        return {
            'summary': {
                'topic_name': config['topic_name'],
                'operation_status': 'success',
                'creation_status': creation_result['status'],
                'verification_status': verification_result['verification_status'],
                'config': config,
                'creation_result': creation_result,
                'verification_result': verification_result
            }
        }
        
    except Exception as e:
        print(f"❌ Ошибка при генерации отчета: {e}")
        raise

# Определение задач
get_config_task = PythonOperator(
    task_id='get_topic_config',
    python_callable=get_topic_config,
    dag=kafka_topic_dag,
)

check_connection_task = PythonOperator(
    task_id='check_kafka_connection',
    python_callable=check_kafka_connection,
    dag=kafka_topic_dag,
)

check_exists_task = PythonOperator(
    task_id='check_topic_exists',
    python_callable=check_topic_exists,
    dag=kafka_topic_dag,
)

create_topic_task = PythonOperator(
    task_id='create_kafka_topic',
    python_callable=create_kafka_topic,
    dag=kafka_topic_dag,
)

verify_creation_task = PythonOperator(
    task_id='verify_topic_creation',
    python_callable=verify_topic_creation,
    dag=kafka_topic_dag,
)

generate_summary_task = PythonOperator(
    task_id='generate_topic_summary',
    python_callable=generate_topic_summary,
    dag=kafka_topic_dag,
)

# Определение зависимостей
get_config_task >> check_connection_task >> check_exists_task >> create_topic_task >> verify_creation_task >> generate_summary_task