######################################################################
# ---- Section: Local service enable flags ----
# Логика выбора сервисов вынесена в locals.tf
######################################################################
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
provider "docker" {}

######################################################################
# ---- Section: Docker network ----
######################################################################
resource "docker_network" "metanet1" {
  name   = "metanet1"
  driver = "bridge"
}

######################################################################
# ---- Section: Postgres (image, container) ----
######################################################################
resource "docker_image" "postgres" {
  name = "postgres:${var.postgres_version}"
}

resource "docker_container" "postgres" {
  # ---- Контейнер Postgres: только суперпользователь и его пароль ----
  # Инициализация пользователя/БД для Metabase — только через отдельный блок ниже!
  name     = "postgres"
  image    = docker_image.postgres.name
  hostname = "postgres"
  networks_advanced {
    name    = docker_network.metanet1.name
    aliases = ["postgres"]
  }
  env = [
    "POSTGRES_USER=postgres",
    "POSTGRES_PASSWORD=${local.effective_postgres_superuser_password}"
  ]
  restart = "unless-stopped"
  volumes {
    host_path      = abspath("${path.module}/../../base-infra/clickhouse/volumes/pgdata")
    container_path = "/var/lib/postgresql/data"
  }
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U postgres"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}
######################################################################
# ---- Metabase DB/user init (однократно при пустом каталоге pgdata) ----
# Этот блок создаёт пользователя и базу данных Metabase только если каталог данных Postgres пустой.
# Миграция и первичная инициализация Metabase БД и пользователя запускаются только один раз при пустом pgdata, после чего больше не выполняются.
######################################################################
resource "null_resource" "init_metabase_db" {
  # ---- Инициализация пользователя Metabase и создание БД, если не существует ----
  provisioner "local-exec" {
    command = <<EOT
      # Ждать readiness Postgres (до 60 сек)
      for i in {1..30}; do
        docker exec -i postgres pg_isready -U postgres && break || sleep 2
      done
      # Проверить существование пользователя
      USER_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.metabase_pg_user}'" | grep -q 1 && echo yes || echo no)
      if [ "$USER_EXISTS" = "no" ]; then
        docker exec -i postgres psql -U postgres -d postgres -c "CREATE USER ${var.metabase_pg_user} WITH PASSWORD '${local.effective_metabase_pg_password}';"
        echo "Metabase user '${var.metabase_pg_user}' created."
      else
        docker exec -i postgres psql -U postgres -d postgres -c "ALTER USER ${var.metabase_pg_user} WITH PASSWORD '${local.effective_metabase_pg_password}';"
        echo "Metabase user '${var.metabase_pg_user}' password updated."
      fi
      # Проверить существование БД Metabase
      DB_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${var.metabase_pg_db}'" | grep -q 1 && echo yes || echo no)
      if [ "$DB_EXISTS" = "no" ]; then
        docker exec -i postgres createdb -U postgres ${var.metabase_pg_db}
        echo "Metabase database '${var.metabase_pg_db}' created."
      else
        echo "Metabase database '${var.metabase_pg_db}' already exists."
      fi
      # Выдать права CREATE и USAGE на схему public в БД metabase для пользователя metabase
      docker exec -i postgres psql -U postgres -d ${var.metabase_pg_db} -c "GRANT CREATE, USAGE ON SCHEMA public TO ${var.metabase_pg_user};"
      docker exec -i postgres psql -U postgres -d ${var.metabase_pg_db} -c "GRANT CREATE ON DATABASE ${var.metabase_pg_db} TO ${var.metabase_pg_user};"
      echo "Granted CREATE, USAGE on schema public and CREATE on database to '${var.metabase_pg_user}'."
      # Не создаём схемы/таблицы — это делает Metabase при первом запуске
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres]
}

######################################################################
# ---- Postgres restore/инициализация при пустом каталоге ----
# Этот блок демонстрирует логику проверки необходимости восстановления/инициализации.
######################################################################
resource "null_resource" "postgres_restore_if_empty" {
  count = local.postgres_restore_enabled ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
if [ -z "$(ls -A "${path.module}/../../base-infra/clickhouse/volumes/pgdata" 2>/dev/null)" ]; then
  echo "Postgres data dir empty. Restore needed."
  # Здесь должна быть команда восстановления из backup (например, pg_restore ...), требует дополнительного задания.
else
  echo "Postgres data dir not empty. Skipping restore."
fi
EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres]
}

######################################################################
# ---- Section: Metabase (image, container) ----
# Создание ресурсов Metabase зависит от флага var.enable_metabase
######################################################################
resource "docker_image" "metabase" {
  # Логика выбора сервиса вынесена в locals.tf
  count = local.metabase_enabled ? 1 : 0
  name  = "metabase/metabase:${var.metabase_version}"
}

resource "docker_container" "metabase" {
  # ---- Контейнер Metabase: только переменные для подключения к БД ----
  # Админ Metabase создаётся через API после запуска (см. ниже).
  count    = local.metabase_enabled ? 1 : 0
  name     = "metabase"
  image    = docker_image.metabase[0].name
  hostname = "metabase"
  ports {
    internal = 3000
    external = var.metabase_port
  }
  volumes {
    host_path      = "/dev/urandom"
    container_path = "/dev/random"
    read_only      = true
  }
  networks_advanced {
    name    = docker_network.metanet1.name
    aliases = ["metabase"]
  }
  env = [
    "MB_DB_TYPE=postgres",
    "MB_DB_DBNAME=${var.metabase_pg_db}",
    "MB_DB_PORT=5432",
    "MB_DB_USER=${var.metabase_pg_user}",
    "MB_DB_PASS=${local.effective_metabase_pg_password}",
    "MB_DB_HOST=postgres"
  ]
  restart = "unless-stopped"
  depends_on = [
    docker_container.postgres,
    null_resource.postgres_restore_if_empty,
    null_resource.init_metabase_db
  ]
  healthcheck {
    test     = ["CMD-SHELL", "curl --fail -I http://localhost:3000/api/health || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 5
  }
}



######################################################################
# ---- Section: Metabase automation via API (инициализация и пользователи) ----
# Вся инициализация Metabase и создание пользователей выполняется через API,
# провайдер Terraform metabase не используется (см. документацию).
# Это позволяет корректно инициализировать Metabase при headless-запуске с пустой БД.
######################################################################

resource "null_resource" "metabase_api_init" {
  # Автоматизация: инициализация Metabase и создание пользователей через API.
  # - Ждёт readiness Metabase (curl /api/health).
  # - Проверяет, доступен ли /api/setup (наличие setup_token).
  # - Если доступен, POST /api/setup с параметрами первого пользователя (email, password, first_name, last_name).
  # - Если уже инициализировано — логин через /api/session (только email).
  # - Создаёт остальных пользователей через /api/user (только email, password, first_name, last_name, is_superuser если определён).
  # - Проверяет, если пользователь уже есть — пропускает создание.
  # - Явная проверка: если SESSION_ID получен — логирует успех, иначе выход с ошибкой.
  # - USERS_JSON: первым всегда админ principalwater (principalwater@local.com), остальные после.
  count = local.metabase_enabled ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
set -e
set -o pipefail

# --- Константы для админа
METABASE_URL="http://localhost:${var.metabase_port}"
ADMIN_EMAIL="${local.effective_metabase_sa_username}@local.com"
ADMIN_PASSWORD="${local.effective_metabase_sa_password}"
ADMIN_FIRSTNAME="Super"
ADMIN_LASTNAME="Admin"

# --- Генерация USERS_JSON: первым всегда админ principalwater, остальные после ---
# Удаляем username у всех пользователей, переставляем principalwater первым
USERS_JSON=$(jq -c --arg admin_email "$ADMIN_EMAIL" '
  [
    .[] | select(.email == $admin_email)
  ] +
  [
    .[] | select(.email != $admin_email)
  ]
  | map(del(.username))
' <<< '${jsonencode(local.metabase_local_users)}')

# --- Ожидание Metabase readiness (до 120 сек)
for i in {1..24}; do
  if curl -sf "$METABASE_URL/api/health" | grep -q '"ok"'; then
    echo "Metabase is healthy"
    break
  else
    echo "Waiting for Metabase to become healthy..."
    sleep 5
  fi
done

# --- Проверяем доступность /api/setup (setup_token)
# Новый способ получения setup_token
SETUP_TOKEN=$(curl -s -m 5 -X GET \
    -H "Content-Type: application/json" \
    "$METABASE_URL/api/session/properties" \
    | jq -r '."setup-token" // empty')
if [ -n "$SETUP_TOKEN" ]; then
  echo "Metabase not initialized, performing setup via API"
  # --- Формируем payload для /api/setup (структура user, prefs как в документации)
  SETUP_PAYLOAD=$(cat <<EOF
{
  "token": "$SETUP_TOKEN",
  "user": {
    "email": "$ADMIN_EMAIL",
    "first_name": "$ADMIN_FIRSTNAME",
    "last_name": "$ADMIN_LASTNAME",
    "password": "$ADMIN_PASSWORD"
  },
  "prefs": {
    "allow_tracking": false,
    "site_name": "Metabase"
  }
}
EOF
)
  # --- Выполняем setup
  RESPONSE=$(curl -s -X POST \
      -H "Content-type: application/json" \
      "$METABASE_URL/api/setup" \
      -d "$SETUP_PAYLOAD" || true)
  SESSION_ID=$(echo "$RESPONSE" | jq -r '.id // .session_id // empty')
  if [ -n "$SESSION_ID" ]; then
    echo "Metabase setup complete, session: $SESSION_ID"
  else
    echo "ERROR: Failed to initialize Metabase via /api/setup"
    echo "Response: $RESPONSE"
    exit 1
  fi
else
  echo "Metabase already initialized, logging in via /api/session"
  # --- Логин только по email (username не нужен)
  LOGIN_PAYLOAD=$(cat <<EOF
{
  "email": "$ADMIN_EMAIL",
  "password": "$ADMIN_PASSWORD"
}
EOF
)
  RESPONSE=$(curl -sf -X POST "$METABASE_URL/api/session" -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD" || true)
  SESSION_ID=$(echo "$RESPONSE" | jq -r '.id // .session_id // empty')
  if [ -n "$SESSION_ID" ]; then
    echo "Metabase login successful, session: $SESSION_ID"
  else
    echo "ERROR: Failed to login to Metabase API"
    echo "Response: $RESPONSE"
    exit 1
  fi
fi

# --- Создаём остальных пользователей через /api/user (кроме админа principalwater)
echo "$USERS_JSON" | jq -c '.[]' | while read -r user; do
  email=$(echo "$user" | jq -r '.email')
  password=$(echo "$user" | jq -r '.password')
  first_name=$(echo "$user" | jq -r '.first_name')
  last_name=$(echo "$user" | jq -r '.last_name')
  # .is_superuser может быть null/отсутствовать
  is_superuser=$(echo "$user" | jq -r 'if has("is_superuser") then .is_superuser else empty end')

  # --- Не создавать админа повторно
  if [ "$email" = "$ADMIN_EMAIL" ]; then
    echo "Skipping admin user $email"
    continue
  fi

  # --- Проверяем, существует ли пользователь с таким email
  EXISTING=$(curl -sf -H "X-Metabase-Session: $SESSION_ID" "$METABASE_URL/api/user" | jq -r '.[] | select(.email=="'"$email"'") | .id' || true)
  if [ -n "$EXISTING" ]; then
    echo "User $email already exists (id=$EXISTING), skipping"
    continue
  fi

  # --- Формируем payload для /api/user только с нужными полями
  if [ -n "$is_superuser" ] && [ "$is_superuser" != "null" ]; then
    USER_PAYLOAD=$(cat <<EOF
{
  "first_name": "$first_name",
  "last_name": "$last_name",
  "email": "$email",
  "password": "$password",
  "is_superuser": $is_superuser
}
EOF
)
  else
    USER_PAYLOAD=$(cat <<EOF
{
  "first_name": "$first_name",
  "last_name": "$last_name",
  "email": "$email",
  "password": "$password"
}
EOF
)
  fi

  # --- Создаём пользователя через API
  CREATE_RESP=$(curl -sf -X POST "$METABASE_URL/api/user" -H "Content-Type: application/json" -H "X-Metabase-Session: $SESSION_ID" -d "$USER_PAYLOAD" || true)
  if echo "$CREATE_RESP" | grep -q '"email".*already'; then
    echo "User $email already exists (race condition), skipping"
    continue
  fi
  if [ -z "$(echo "$CREATE_RESP" | jq -r '.id // empty')" ]; then
    echo "ERROR: Failed to create user $email"
    echo "Response: $CREATE_RESP"
    exit 1
  fi
  echo "User $email created"
done
EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.metabase]
}

######################################################################
# ---- Section: Superset config ----
# Создание ресурса зависит от флага var.enable_superset
######################################################################
resource "local_file" "superset_config" {
  # Логика выбора сервиса вынесена в locals.tf
  count = local.superset_enabled ? 1 : 0
  content = templatefile("${path.module}/samples/superset/superset_config.py.tmpl", {
    superset_secret_key = var.superset_secret_key
  })
  filename = abspath("${path.module}/superset_config.py")
}

######################################################################
# ---- Section: Superset DB init in Postgres ----
# Создание ресурса зависит от флага var.enable_superset
######################################################################
resource "null_resource" "init_superset_db" {
  # Логика выбора сервиса вынесена в locals.tf
  count = local.superset_enabled ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
      for i in {1..30}; do
        docker exec -i postgres pg_isready -U ${var.metabase_pg_user} && break || sleep 3
      done

      # Создать роль superset, если не существует (от имени администратора)
      ROLE_EXISTS=$(docker exec -i postgres psql -U ${var.metabase_pg_user} -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.superset_pg_user}'" | grep -q 1 && echo yes || echo no)
      if [ "$ROLE_EXISTS" = "no" ]; then
        docker exec -i postgres psql -U ${var.metabase_pg_user} -d postgres -c "CREATE USER ${var.superset_pg_user} WITH PASSWORD '${local.effective_superset_pg_password}';"
      fi

      # Создать базу superset, если не существует (от имени администратора)
      DB_EXISTS=$(docker exec -i postgres psql -U ${var.metabase_pg_user} -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${var.superset_pg_db}'" | grep -q 1 && echo yes || echo no)
      if [ "$DB_EXISTS" = "no" ]; then
        docker exec -i postgres createdb -U ${var.metabase_pg_user} ${var.superset_pg_db}
      fi

      # Назначить все права на базу пользователю superset
      docker exec -i postgres psql -U ${var.metabase_pg_user} -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${var.superset_pg_db} TO ${var.superset_pg_user};"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  # Статический depends_on, как требует Terraform: инициализация БД Superset зависит от Postgres
  depends_on = [docker_container.postgres]
}

######################################################################
# ---- Section: Superset (image, container) ----
# Создание ресурсов Superset зависит от флага var.enable_superset
######################################################################
resource "docker_image" "superset" {
  # Логика выбора сервиса вынесена в locals.tf
  count = local.superset_enabled ? 1 : 0
  name  = "apache/superset:${var.superset_version}"
}

resource "docker_container" "superset" {
  # Логика выбора сервиса вынесена в locals.tf
  count    = local.superset_enabled ? 1 : 0
  name     = "superset"
  image    = docker_image.superset[0].name
  hostname = "superset"
  ports {
    internal = 8088
    external = var.superset_port
  }
  networks_advanced {
    name    = docker_network.metanet1.name
    aliases = ["superset"]
  }
  env = [
    "SUPERSET_ENV=production",
    "SUPERSET_DATABASE_URI=postgresql+psycopg2://${var.superset_pg_user}:${local.effective_superset_pg_password}@postgres:5432/${var.superset_pg_db}",
    "SECRET_KEY=${var.superset_secret_key}",
    "PYTHONPATH=/app/pythonpath"
  ]
  volumes {
    host_path      = local_file.superset_config[0].filename
    container_path = "/app/pythonpath/superset_config.py"
    read_only      = true
  }
  restart = "unless-stopped"
  # Статический depends_on, как требует Terraform: Superset зависит от Postgres, init_superset_db и superset_config
  depends_on = [
    docker_container.postgres,
    null_resource.init_superset_db,
    local_file.superset_config
  ]
  healthcheck {
    test     = ["CMD-SHELL", "curl --fail -I http://localhost:8088/health || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 5
  }
}

######################################################################
# ---- Section: Superset post-init (drivers, admin) ----
# Создание ресурса зависит от флага var.enable_superset
######################################################################
resource "null_resource" "superset_post_init" {
  # Логика выбора сервиса вынесена в locals.tf
  count = local.superset_enabled ? 1 : 0
  provisioner "local-exec" {
    command     = <<EOT
      # Wait for Superset container to become healthy (up to 150 seconds)
      for i in {1..30}; do
        docker exec superset curl -sf http://localhost:8088/health && break || sleep 5
      done

      # Upgrade pip and install ClickHouse drivers inside Superset container
      docker exec superset pip install --upgrade pip
      docker exec superset pip install clickhouse-connect clickhouse-driver

      # Restart Superset container to load new libraries
      docker restart superset

      # Wait again for Superset to become healthy after restart
      for i in {1..30}; do
        docker exec superset curl -sf http://localhost:8088/health && break || sleep 5
      done

      # Initialize Superset database and create admin user (using local effective admin user variables)
      docker exec superset superset db upgrade
      docker exec superset superset init
      docker exec superset superset fab create-admin \
        --username "${local.effective_superset_sa_username}" \
        --firstname "Super" --lastname "User" \
        --email "${local.effective_superset_sa_username}@local" \
        --password "${local.effective_superset_sa_password}" || true
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  # Статический depends_on, как требует Terraform: post-init зависит от Superset
  depends_on = [docker_container.superset]
}

######################################################################
# ---- Section: Superset user automation ----
# Создание ресурса зависит от флага var.enable_superset
######################################################################
resource "null_resource" "superset_create_local_users" {
  # Логика выбора сервиса вынесена в locals.tf
  count = local.superset_enabled ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
  set -e
  set -x

  # Wait for Superset to become healthy (up to 150 seconds)
  for i in {1..30}; do
    if docker exec superset curl -sf http://localhost:8088/health; then
      echo "Superset is healthy"
      break
    else
      echo "Waiting for Superset to be healthy..."
      sleep 5
    fi
  done

  USERS_JSON='${jsonencode(local.superset_local_users)}'
  echo "Superset users JSON: $USERS_JSON"

  echo "$USERS_JSON" | jq -c '.[]' | while read -r user; do
    username=$(echo "$user" | jq -r '.username')
    password=$(echo "$user" | jq -r '.password')
    first_name=$(echo "$user" | jq -r '.first_name')
    last_name=$(echo "$user" | jq -r '.last_name')
    is_admin=$(echo "$user" | jq -r '.is_admin')

    echo "Processing user: $username, admin: $is_admin"

    # Check if user exists
    EXISTS=$(docker exec superset superset fab list-users | grep -w "$username" || true)
    echo "User existence check for '$username': $${EXISTS:-not found}"

    if [ -n "$EXISTS" ]; then
      echo "User $username already exists, skipping creation"
      continue
    fi

    if [ "$is_admin" = "true" ]; then
      echo "Creating admin user: $username"
      docker exec superset superset fab create-admin \
        --username "$username" \
        --firstname "$first_name" --lastname "$last_name" \
        --email "$username@local" \
        --password "$password"
    else
      echo "Creating regular user: $username with role Gamma"
      docker exec superset superset fab create-user \
        --username "$username" \
        --firstname "$first_name" --lastname "$last_name" \
        --email "$username@local" \
        --password "$password" \
        --role "Gamma"
    fi
  done
EOT
    interpreter = ["/bin/bash", "-c"]
  }
  # Статический depends_on, как требует Terraform: создание пользователей зависит от Superset
  depends_on = [docker_container.superset]
}