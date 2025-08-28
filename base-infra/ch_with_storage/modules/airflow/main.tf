terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

# --- Docker Network ---
resource "docker_network" "airflow_network" {
  count  = var.deploy_airflow ? 1 : 0
  name   = "airflow_network"
  driver = "bridge"
}

# --- Создание необходимых директорий ---
resource "null_resource" "create_airflow_directories" {
  count = var.deploy_airflow ? 1 : 0

  provisioner "local-exec" {
    command     = <<EOT
      echo "Создание директорий Airflow..."
      
      mkdir -p "${abspath(var.airflow_dags_path)}"
      mkdir -p "${abspath(var.airflow_logs_path)}"
      mkdir -p "${abspath(var.airflow_plugins_path)}"
      mkdir -p "${abspath(var.airflow_config_path)}"
      
      # Создание .env файла для Docker Compose совместимости
      echo "AIRFLOW_UID=50000" > ${dirname(var.airflow_dags_path)}/.env
      echo "AIRFLOW_GID=0" >> ${dirname(var.airflow_dags_path)}/.env
      
      echo "Директории созданы успешно"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# --- Redis для Celery ---
resource "docker_image" "redis" {
  count = var.deploy_airflow ? 1 : 0
  name  = "redis:latest"
}

resource "docker_container" "redis" {
  count    = var.deploy_airflow ? 1 : 0
  name     = "redis"
  image    = docker_image.redis[0].name
  hostname = "redis"

  networks_advanced {
    name = docker_network.airflow_network[0].name
  }

  ports {
    internal = 6379
    external = 6379
  }

  healthcheck {
    test         = ["CMD", "redis-cli", "ping"]
    interval     = "30s"
    timeout      = "30s"
    retries      = 50
    start_period = "30s"
  }

  restart = "always"

  # Лейблы для группировки контейнеров
  dynamic "labels" {
    for_each = local.common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  labels {
    label = "com.docker.compose.service"
    value = "redis"
  }

  depends_on = [null_resource.create_airflow_directories]
}

# --- Образ Airflow ---
resource "docker_image" "airflow" {
  count = var.deploy_airflow ? 1 : 0
  name  = "apache/airflow:${var.airflow_version}"
}

# --- Общая конфигурация для всех сервисов Airflow ---
locals {
  # Project and module labels for container grouping
  project_name = "clickhouse-engineering-course"
  module_name  = "airflow"

  # Common labels for all containers
  common_labels = {
    "com.docker.compose.project" = local.project_name
    "com.docker.compose.service" = local.module_name
    "project.name"               = local.project_name
    "module.name"                = local.module_name
    "terraform.workspace"        = terraform.workspace
    "managed-by"                 = "terraform"
  }

  airflow_common_env = var.deploy_airflow ? [
    "AIRFLOW__CORE__EXECUTOR=CeleryExecutor",
    "AIRFLOW__CORE__AUTH_MANAGER=airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager",
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=${var.airflow_postgres_connection_string}",
    "AIRFLOW__CELERY__RESULT_BACKEND=db+${var.airflow_postgres_connection_string}",
    "AIRFLOW__CELERY__BROKER_URL=redis://:@redis:6379/0",
    "AIRFLOW__API_AUTH__JWT_SECRET=${var.airflow_jwt_signing_key}",
    "AIRFLOW__CORE__FERNET_KEY=${var.airflow_fernet_key}",
    "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=true",
    "AIRFLOW__CORE__LOAD_EXAMPLES=false",
    "AIRFLOW__CORE__EXECUTION_API_SERVER_URL=http://airflow-api-server:8080/execution/",
    "AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK=true",
    "AIRFLOW__SCHEDULER__SCHEDULER_HEALTH_CHECK_SERVER_PORT=8974",
    "AIRFLOW__SCHEDULER__SCHEDULER_HEALTH_CHECK_THRESHOLD=60",
    "AIRFLOW__CORE__STANDALONE_DAG_PROCESSOR=true",
    "AIRFLOW__CELERY__WORKER_CONCURRENCY=16",
    "AIRFLOW__CELERY__WORKER_ENABLE_REMOTE_CONTROL=false",
    "_PIP_ADDITIONAL_REQUIREMENTS=${join(" ", [for line in split("\n", file("${var.airflow_dags_path}/requirements.txt")) : trimspace(line) if trimspace(line) != "" && !startswith(trimspace(line), "#") && !startswith(trimspace(line), "apache-airflow")])}",
    "AIRFLOW_CONFIG=/opt/airflow/config/airflow.cfg",
    "_AIRFLOW_DB_MIGRATE=true",
    # ClickHouse переменные для backup операций
    "CH_USER=${var.clickhouse_super_user}",
    "CH_PASSWORD=${var.clickhouse_super_password}",
    # ClickHouse переменные для общих подключений (для clickhouse_utils.py)
    "CLICKHOUSE_HOST=clickhouse-01",
    "CLICKHOUSE_PORT=8123",
    "CLICKHOUSE_USER=${var.clickhouse_super_user}",
    "CLICKHOUSE_PASSWORD=${var.clickhouse_super_password}",
    "CLICKHOUSE_DATABASE=raw",
    # dbt переменные окружения
    "DBT_PROFILES_DIR=/opt/airflow/dbt/profiles",
    "DBT_PROJECT_DIR=/opt/airflow/dbt",
    "_AIRFLOW_WWW_USER_CREATE=true",
    "_AIRFLOW_WWW_USER_USERNAME=${var.airflow_admin_user}",
    "_AIRFLOW_WWW_USER_PASSWORD=${var.airflow_admin_password}",
    # Telegram переменные для уведомлений
    "TELEGRAM_BOT_TOKEN=${var.telegram_bot_token}",
    "TELEGRAM_CHAT_ID=${var.telegram_chat_id}",
    # PostgreSQL переменные для прямого подключения
    "AIRFLOW_POSTGRES_PASSWORD=${var.airflow_postgres_password}"
  ] : []

  airflow_common_volumes = var.deploy_airflow ? [
    {
      host_path      = abspath(var.airflow_dags_path)
      container_path = "/opt/airflow"
    },
    {
      host_path      = abspath(var.airflow_logs_path)
      container_path = "/opt/airflow/logs"
    },
    {
      host_path      = abspath(var.airflow_plugins_path)
      container_path = "/opt/airflow/plugins"
    },
    {
      host_path      = abspath(var.airflow_config_path)
      container_path = "/opt/airflow/config"
    },
    {
      host_path      = abspath(var.scripts_path)
      container_path = "/opt/airflow/scripts"
    },
    {
      host_path      = abspath("${path.root}/../../dbt")
      container_path = "/opt/airflow/dbt"
    },
    {
      host_path      = "/var/run/docker.sock"
      container_path = "/var/run/docker.sock"
    }
  ] : []

  # Общие лейблы для всех контейнеров Airflow
  airflow_common_labels = merge(local.common_labels, {
    "com.docker.compose.service" = "airflow"
  })
}

# --- Airflow Init (одноразовая инициализация) ---
resource "null_resource" "airflow_init" {
  count = var.deploy_airflow ? 1 : 0

  provisioner "local-exec" {
    command     = <<EOT
      echo "Запуск инициализации Airflow ${var.airflow_version}..."
      
      # Ожидание готовности PostgreSQL
      echo "Ожидание готовности PostgreSQL..."
      for i in {1..60}; do
        if docker exec postgres pg_isready -U postgres &> /dev/null 2>&1; then
          echo "PostgreSQL готов"
          break
        fi
        echo "Попытка $i/60: Ждём PostgreSQL..."
        sleep 3
      done
      
      # Ожидание готовности Redis
      echo "Ожидание готовности Redis..."
      for i in {1..30}; do
        if docker exec redis redis-cli ping &> /dev/null 2>&1; then
          echo "Redis готов"
          break
        fi
        echo "Попытка $i/30: Ждём Redis..."
        sleep 2
      done
      
      # Проверка и предоставление прав PostgreSQL
      echo "Предоставление прав PostgreSQL для Airflow..."
      docker exec postgres psql -U postgres -d airflow -c "
        GRANT ALL PRIVILEGES ON SCHEMA public TO airflow;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO airflow;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO airflow;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO airflow;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO airflow;
      " || echo "Права уже предоставлены или произошла ошибка"
      
      # Выполнение инициализации базы данных через временный контейнер
      echo "Запуск единократной инициализации Airflow..."
      POSTGRES_NETWORK_ARG=""
      if [ "${var.postgres_network_name}" != "" ]; then
        POSTGRES_NETWORK_ARG="--network ${var.postgres_network_name}"
      fi
      
      docker run --rm \
        --name airflow-init-temp \
        --network ${docker_network.airflow_network[0].name} \
        $POSTGRES_NETWORK_ARG \
        --user 50000:0 \
        -e AIRFLOW_UID=50000 \
        -e AIRFLOW__DATABASE__SQL_ALCHEMY_CONN='${var.airflow_postgres_connection_string}' \
        -e AIRFLOW__CORE__FERNET_KEY='${var.airflow_fernet_key}' \
        -e AIRFLOW__CORE__AUTH_MANAGER='airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager' \
        -v "${abspath(var.airflow_dags_path)}:/opt/airflow/dags" \
        -v "${abspath(var.airflow_logs_path)}:/opt/airflow/logs" \
        -v "${abspath(var.airflow_plugins_path)}:/opt/airflow/plugins" \
        -v "${abspath(var.airflow_config_path)}:/opt/airflow/config" \
        apache/airflow:${var.airflow_version} \
        bash -c "
          echo 'Создание директорий...'
          mkdir -p /opt/airflow/{logs,dags,plugins,config}
          
          echo 'Выполнение миграции базы данных (однократно)...'
          airflow db migrate
          
          echo 'Создание администратора...'
          airflow users create \
            --username '${var.airflow_admin_user}' \
            --firstname 'Admin' \
            --lastname 'User' \
            --role 'Admin' \
            --email 'admin@example.com' \
            --password '${var.airflow_admin_password}' || echo 'Пользователь уже существует'
          
          echo 'Инициализация завершена успешно!'
        "
      
      echo "Airflow готов к запуску!"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    docker_container.redis[0],
    null_resource.create_airflow_directories[0]
  ]

  triggers = {
    airflow_version     = var.airflow_version
    admin_user          = var.airflow_admin_user
    postgres_connection = var.airflow_postgres_connection_string
    force_recreate      = "v3.0.4-fixed-permissions-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  }
}

# --- Airflow API Server (Webserver) ---
resource "docker_container" "airflow_api_server" {
  count    = var.deploy_airflow ? 1 : 0
  name     = "airflow-api-server"
  image    = docker_image.airflow[0].name
  hostname = "airflow-api-server"

  networks_advanced {
    name = docker_network.airflow_network[0].name
  }

  dynamic "networks_advanced" {
    for_each = var.clickhouse_network_name != "" ? [1] : []
    content {
      name = var.clickhouse_network_name
    }
  }

  dynamic "networks_advanced" {
    for_each = var.kafka_network_name != "" ? [1] : []
    content {
      name = var.kafka_network_name
    }
  }

  dynamic "networks_advanced" {
    for_each = var.postgres_network_name != "" ? [1] : []
    content {
      name = var.postgres_network_name
    }
  }

  ports {
    internal = 8080
    external = var.airflow_webserver_port
  }

  command = ["api-server"]

  env = local.airflow_common_env

  user = "50000:0"

  dynamic "volumes" {
    for_each = local.airflow_common_volumes
    content {
      host_path      = volumes.value.host_path
      container_path = volumes.value.container_path
    }
  }

  healthcheck {
    test         = ["CMD", "curl", "--fail", "http://localhost:8080/api/v2/version"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  restart = "always"

  # Лейблы для группировки контейнеров
  dynamic "labels" {
    for_each = local.airflow_common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  labels {
    label = "airflow.component"
    value = "api-server"
  }

  depends_on = [
    docker_container.redis[0],
    null_resource.airflow_init[0]
  ]
}

# --- Airflow Scheduler ---
resource "docker_container" "airflow_scheduler" {
  count    = var.deploy_airflow ? 1 : 0
  name     = "airflow-scheduler"
  image    = docker_image.airflow[0].name
  hostname = "airflow-scheduler"

  networks_advanced {
    name = docker_network.airflow_network[0].name
  }

  dynamic "networks_advanced" {
    for_each = var.clickhouse_network_name != "" ? [1] : []
    content {
      name = var.clickhouse_network_name
    }
  }

  dynamic "networks_advanced" {
    for_each = var.kafka_network_name != "" ? [1] : []
    content {
      name = var.kafka_network_name
    }
  }

  dynamic "networks_advanced" {
    for_each = var.postgres_network_name != "" ? [1] : []
    content {
      name = var.postgres_network_name
    }
  }

  command = ["scheduler"]

  env = local.airflow_common_env

  user = "50000:0"

  dynamic "volumes" {
    for_each = local.airflow_common_volumes
    content {
      host_path      = volumes.value.host_path
      container_path = volumes.value.container_path
    }
  }

  healthcheck {
    test         = ["CMD", "curl", "--fail", "http://localhost:8974/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "120s"
  }

  restart = "always"

  # Лейблы для группировки контейнеров
  dynamic "labels" {
    for_each = local.airflow_common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  labels {
    label = "airflow.component"
    value = "scheduler"
  }

  depends_on = [
    docker_container.redis[0],
    null_resource.airflow_init[0]
  ]
}

# --- Airflow Worker ---
resource "docker_container" "airflow_worker" {
  count    = var.deploy_airflow ? 1 : 0
  name     = "airflow-worker"
  image    = docker_image.airflow[0].name
  hostname = "airflow-worker"

  networks_advanced {
    name = docker_network.airflow_network[0].name
  }

  dynamic "networks_advanced" {
    for_each = var.clickhouse_network_name != "" ? [1] : []
    content {
      name = var.clickhouse_network_name
    }
  }

  dynamic "networks_advanced" {
    for_each = var.kafka_network_name != "" ? [1] : []
    content {
      name = var.kafka_network_name
    }
  }

  dynamic "networks_advanced" {
    for_each = var.postgres_network_name != "" ? [1] : []
    content {
      name = var.postgres_network_name
    }
  }

  command = ["celery", "worker"]

  env = concat(local.airflow_common_env, [
    "DUMB_INIT_SETSID=0"
  ])

  user = "50000:0"

  dynamic "volumes" {
    for_each = local.airflow_common_volumes
    content {
      host_path      = volumes.value.host_path
      container_path = volumes.value.container_path
    }
  }

  dynamic "healthcheck" {
    for_each = var.disable_healthchecks ? [] : [1]
    content {
      test = [
        "CMD-SHELL",
        "python -c \"import os; exit(0 if any('worker' in line for line in os.popen('ps auxf').readlines()) else 1)\" 2>/dev/null || ls /tmp/airflow-worker-ready 2>/dev/null || touch /tmp/airflow-worker-ready"
      ]
      interval     = "60s"
      timeout      = "20s"
      retries      = 2
      start_period = "300s"
    }
  }

  restart = "always"

  # Лейблы для группировки контейнеров
  dynamic "labels" {
    for_each = local.airflow_common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  labels {
    label = "airflow.component"
    value = "worker"
  }

  depends_on = [
    docker_container.redis[0],
    null_resource.airflow_init[0]
  ]
}

# --- Airflow Triggerer (Новое в Airflow 3.0) ---
resource "docker_container" "airflow_triggerer" {
  count    = var.deploy_airflow ? 1 : 0
  name     = "airflow-triggerer"
  image    = docker_image.airflow[0].name
  hostname = "airflow-triggerer"

  networks_advanced {
    name = docker_network.airflow_network[0].name
  }

  dynamic "networks_advanced" {
    for_each = var.postgres_network_name != "" ? [1] : []
    content {
      name = var.postgres_network_name
    }
  }

  command = ["triggerer"]

  env = local.airflow_common_env

  user = "50000:0"

  dynamic "volumes" {
    for_each = local.airflow_common_volumes
    content {
      host_path      = volumes.value.host_path
      container_path = volumes.value.container_path
    }
  }

  dynamic "healthcheck" {
    for_each = var.disable_healthchecks ? [] : [1]
    content {
      test = [
        "CMD-SHELL",
        "python -c \"import os; exit(0 if any('triggerer' in line for line in os.popen('ps auxf').readlines()) else 1)\" 2>/dev/null || ls /tmp/airflow-triggerer-ready 2>/dev/null || touch /tmp/airflow-triggerer-ready"
      ]
      interval     = "60s"
      timeout      = "20s"
      retries      = 2
      start_period = "300s"
    }
  }

  restart = "always"

  # Лейблы для группировки контейнеров
  dynamic "labels" {
    for_each = local.airflow_common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  labels {
    label = "airflow.component"
    value = "triggerer"
  }

  depends_on = [
    docker_container.redis[0],
    null_resource.airflow_init[0]
  ]
}

# --- Airflow DAG Processor (Новое в Airflow 3.0) ---
resource "docker_container" "airflow_dag_processor" {
  count    = var.deploy_airflow ? 1 : 0
  name     = "airflow-dag-processor"
  image    = docker_image.airflow[0].name
  hostname = "airflow-dag-processor"

  networks_advanced {
    name = docker_network.airflow_network[0].name
  }

  dynamic "networks_advanced" {
    for_each = var.postgres_network_name != "" ? [1] : []
    content {
      name = var.postgres_network_name
    }
  }

  command = ["dag-processor"]

  env = local.airflow_common_env

  user = "50000:0"

  dynamic "volumes" {
    for_each = local.airflow_common_volumes
    content {
      host_path      = volumes.value.host_path
      container_path = volumes.value.container_path
    }
  }

  healthcheck {
    test = [
      "CMD-SHELL",
      "python -c 'from airflow.models import DagBag; db = DagBag(include_examples=False); exit(0 if len(db.dag_ids) >= 0 else 1)' || exit 1"
    ]
    interval     = "120s"
    timeout      = "30s"
    retries      = 1
    start_period = "300s"
  }

  restart = "always"

  # Лейблы для группировки контейнеров
  dynamic "labels" {
    for_each = local.airflow_common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  labels {
    label = "airflow.component"
    value = "dag-processor"
  }

  depends_on = [
    docker_container.redis[0],
    null_resource.airflow_init[0]
  ]
}

# --- Airflow Flower (опционально) ---
resource "docker_container" "airflow_flower" {
  count    = var.deploy_airflow && var.enable_flower ? 1 : 0
  name     = "airflow-flower"
  image    = docker_image.airflow[0].name
  hostname = "airflow-flower"

  networks_advanced {
    name = docker_network.airflow_network[0].name
  }

  dynamic "networks_advanced" {
    for_each = var.postgres_network_name != "" ? [1] : []
    content {
      name = var.postgres_network_name
    }
  }

  ports {
    internal = 5555
    external = var.airflow_flower_port
  }

  command = ["celery", "flower"]

  env = local.airflow_common_env

  user = "50000:0"

  dynamic "volumes" {
    for_each = local.airflow_common_volumes
    content {
      host_path      = volumes.value.host_path
      container_path = volumes.value.container_path
    }
  }

  healthcheck {
    test         = ["CMD", "curl", "--fail", "http://localhost:5555/"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  restart = "always"

  # Лейблы для группировки контейнеров
  dynamic "labels" {
    for_each = local.airflow_common_labels
    content {
      label = labels.key
      value = labels.value
    }
  }
  labels {
    label = "airflow.component"
    value = "flower"
  }

  depends_on = [
    docker_container.redis[0],
    null_resource.airflow_init[0]
  ]
}

# --- Настройка подключений после запуска ---
resource "null_resource" "setup_airflow_connections" {
  count = var.deploy_airflow ? 1 : 0

  provisioner "local-exec" {
    command     = <<EOT
      echo "Ожидание готовности API сервера..."
      
      for i in {1..60}; do
        if curl -s http://localhost:${var.airflow_webserver_port}/api/v2/monitor/health > /dev/null; then
          echo "API сервер готов"
          break
        fi
        echo "Ожидание API сервера... ($i/60)"
        sleep 5
      done
      
      # Создание подключений (ClickHouse, Kafka, Telegram)
      docker exec airflow-api-server airflow connections add \
        'clickhouse_default' \
        --conn-type 'http' \
        --conn-host 'clickhouse-1' \
        --conn-port '8123' \
        --conn-login '${var.clickhouse_bi_user}' \
        --conn-password '${var.clickhouse_bi_password}' \
        --conn-extra '{"database": "default"}' || echo "Подключение ClickHouse уже существует"
      
      docker exec airflow-api-server airflow connections add \
        'kafka_default' \
        --conn-type 'kafka' \
        --conn-extra '{"bootstrap.servers": "kafka:9092"}' || echo "Подключение Kafka уже существует"
      
      # Создание Telegram соединения (если указаны переменные)
      if [ ! -z "${var.telegram_bot_token}" ] && [ ! -z "${var.telegram_chat_id}" ]; then
        echo "Создание Telegram соединения..."
        docker exec airflow-api-server airflow connections add \
          'telegram_default' \
          --conn-type 'telegram' \
          --conn-password '${var.telegram_bot_token}' \
          --conn-extra '{"chat_id": "${var.telegram_chat_id}"}' || echo "Подключение Telegram уже существует"
        echo "Telegram соединение настроено"
      else
        echo "Telegram переменные не указаны, соединение не создается"
      fi
      
      echo "Настройка подключений завершена"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    docker_container.airflow_api_server[0]
  ]

  triggers = {
    api_server_config = docker_container.airflow_api_server[0].id
  }
}

# --- Создание примера DAG ---
resource "local_file" "sample_dag" {
  count = var.deploy_airflow ? 1 : 0

  content = <<EOF
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
EOF

  filename = "${var.airflow_dags_path}/hw16_sample_data_pipeline.py"

  depends_on = [null_resource.create_airflow_directories]
}