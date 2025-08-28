######################################################################
# BI Tools Module (Metabase + Superset)
# Основан на additional/bi-infra и адаптирован для модульной архитектуры
# Использует существующий модуль postgres
######################################################################

# --- Locals ---
locals {
  # Project and module labels for container grouping
  project_name = "clickhouse-engineering-course"
  module_name  = "bi-tools"

  # Common labels for all containers
  common_labels = {
    "com.docker.compose.project" = local.project_name
    "project.name"               = local.project_name
    "module.name"                = local.module_name
    "terraform.workspace"        = terraform.workspace
    "managed-by"                 = "terraform"
  }
}
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

######################################################################
# --- Section: Metabase - image, container, api_init ---
######################################################################
resource "docker_image" "metabase" {
  count = local.metabase_enabled ? 1 : 0
  name  = "metabase/metabase:${var.metabase_version}"
}

resource "docker_container" "metabase" {
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
    name    = var.postgres_network_name
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
    # PostgreSQL управляется внешним модулем postgres
    # Зависимость от модуля postgres обеспечивается на уровне корневого main.tf
  ]

  healthcheck {
    test     = ["CMD-SHELL", "curl --fail -I http://localhost:3000/api/health || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 5
  }

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
    value = "metabase"
  }
}

resource "null_resource" "metabase_api_init" {
  count = local.metabase_enabled ? 1 : 0
  provisioner "local-exec" {
    command     = <<EOT
set -e
set -o pipefail

METABASE_URL="http://localhost:${var.metabase_port}"
ADMIN_EMAIL="${local.effective_metabase_sa_username}@local.com"
ADMIN_PASSWORD="${local.effective_metabase_sa_password}"
ADMIN_FIRSTNAME="Super"
ADMIN_LASTNAME="Admin"

USERS_JSON=$(jq -c --arg admin_email "$ADMIN_EMAIL" '
  [
    .[] | select(.email == $admin_email)
  ] +
  [
    .[] | select(.email != $admin_email)
  ]
  | map(del(.username))
' <<< '${jsonencode(local.metabase_local_users)}')

# 1. Ждать health API (только status=ok)
for i in {1..48}; do
  STATUS=$(curl -sf "$METABASE_URL/api/health" | jq -r '.status // empty' 2>/dev/null || echo "")
  if [ "$STATUS" = "ok" ]; then
    echo "Metabase is healthy"
    break
  else
    echo "Waiting for Metabase to become healthy..."
    sleep 5
  fi
  if [ $i -eq 48 ]; then
    echo "ERROR: Metabase is not healthy after 4 minutes, aborting"
    exit 1
  fi
done

# 2. Check for setup-token
SETUP_TOKEN=$(curl -sf "$METABASE_URL/api/session/properties" | jq -r '."setup-token" // empty' 2>/dev/null || echo "")

SESSION_ID=""
if [ -n "$SETUP_TOKEN" ]; then
  echo "Metabase not initialized, performing setup via API"
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
  RESPONSE=$(curl -sf -X POST \
      -H "Content-type: application/json" \
      "$METABASE_URL/api/setup" \
      -d "$SETUP_PAYLOAD" || true)
  SESSION_ID=$(echo "$RESPONSE" | jq -r '.id // .session_id // empty')
  if [ -z "$SESSION_ID" ]; then
    LOGIN_PAYLOAD=$(cat <<EOF
{
  "username": "$ADMIN_EMAIL",
  "password": "$ADMIN_PASSWORD"
}
EOF
)
    RESPONSE=$(curl -sf -X POST "$METABASE_URL/api/session" -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD" || true)
    SESSION_ID=$(echo "$RESPONSE" | jq -r '.id // .session_id // empty')
  fi
else
  echo "Metabase already initialized, logging in via /api/session"
  LOGIN_PAYLOAD=$(cat <<EOF
{
  "username": "$ADMIN_EMAIL",
  "password": "$ADMIN_PASSWORD"
}
EOF
)
  RESPONSE=$(curl -sf -X POST "$METABASE_URL/api/session" -H "Content-Type: application/json" -d "$LOGIN_PAYLOAD" || true)
  SESSION_ID=$(echo "$RESPONSE" | jq -r '.id // .session_id // empty')
fi

if [ -z "$SESSION_ID" ]; then
  echo "ERROR: No session_id received after setup/login"
  exit 1
fi

# 3. Create other users via /api/user
echo "$USERS_JSON" | jq -c '.[]' | while read -r user; do
  email=$(echo "$user" | jq -r '.email')
  password=$(echo "$user" | jq -r '.password')
  first_name=$(echo "$user" | jq -r '.first_name')
  last_name=$(echo "$user" | jq -r '.last_name')
  is_superuser=$(echo "$user" | jq -r 'if has("is_superuser") then .is_superuser else empty end')

  if [ "$email" = "$ADMIN_EMAIL" ]; then
    echo "Skipping admin user $email"
    continue
  fi

  EXISTING=$(curl -sf -H "X-Metabase-Session: $SESSION_ID" "$METABASE_URL/api/user" | jq -r '.[] | select(.email=="'"$email"'") | .id' || true)
  if [ -n "$EXISTING" ]; then
    echo "User $email already exists (id=$EXISTING), skipping"
    continue
  fi

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

  CREATE_RESP=$(curl -sf -X POST "$METABASE_URL/api/user" -H "Content-Type: application/json" -H "X-Metabase-Session: $SESSION_ID" -d "$USER_PAYLOAD" || true)
  if echo "$CREATE_RESP" | grep -q '"email".*already'; then
    echo "User $email already exists (race condition), skipping"
    continue
  fi
  if [ -z "$(echo "$CREATE_RESP" | jq -r '.id // empty')" ]; then
    echo "WARNING: Failed to create user $email (non-fatal)"
    echo "Response: $CREATE_RESP"
    continue
  fi
  echo "User $email created"
done
EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.metabase]
}

######################################################################
# --- Section: Superset configuration and container ---
######################################################################
resource "local_file" "superset_config" {
  count = local.superset_enabled ? 1 : 0
  content = templatefile("${path.module}/samples/superset_config.py.tmpl", {
    superset_secret_key = var.superset_secret_key
  })
  filename = "${path.root}/env/superset_config.py"
}

resource "docker_image" "superset" {
  count = local.superset_enabled ? 1 : 0
  name  = "apache/superset:${var.superset_version}"
}

resource "docker_container" "superset" {
  count    = local.superset_enabled ? 1 : 0
  name     = "superset"
  image    = docker_image.superset[0].name
  hostname = "superset"
  ports {
    internal = 8088
    external = var.superset_port
  }
  networks_advanced {
    name    = var.postgres_network_name
    aliases = ["superset"]
  }
  env = [
    "SUPERSET_ENV=production",
    "SUPERSET_DATABASE_URI=postgresql+psycopg2://${var.superset_pg_user}:${local.effective_superset_pg_password}@postgres:5432/${var.superset_pg_db}",
    "SECRET_KEY=${var.superset_secret_key}",
    "PYTHONPATH=/app/pythonpath"
  ]
  volumes {
    host_path      = abspath(local_file.superset_config[0].filename)
    container_path = "/app/pythonpath/superset_config.py"
    read_only      = true
  }
  restart = "unless-stopped"
  depends_on = [
    # PostgreSQL управляется внешним модулем postgres
    local_file.superset_config
  ]
  healthcheck {
    test     = ["CMD-SHELL", "curl --fail -I http://localhost:8088/health || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 5
  }

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
    value = "superset"
  }
}

resource "null_resource" "superset_post_init" {
  count = local.superset_enabled ? 1 : 0
  provisioner "local-exec" {
    command     = <<EOT
      for i in {1..30}; do
        docker exec superset curl -sf http://localhost:8088/health && break || sleep 5
      done

      echo "Upgrading pip and installing ClickHouse drivers in Superset container"
      docker exec superset pip install --upgrade pip
      docker exec superset pip install "clickhouse-connect>=0.6.8" "clickhouse-driver"

      echo "Restarting Superset container to apply new libraries"
      docker restart superset

      for i in {1..30}; do
        docker exec superset curl -sf http://localhost:8088/health && break || sleep 5
      done

      echo "Initializing Superset database and creating admin user"
      docker exec superset superset db upgrade
      docker exec superset superset init
      docker exec superset superset fab create-admin \
        --username "${local.effective_superset_sa_username}" \
        --firstname "Super" --lastname "User" \
        --email "${local.effective_superset_sa_username}@local" \
        --password "${local.effective_superset_sa_password}" || true

      echo '${jsonencode(local.superset_local_users)}' | jq -c '.[]' | while read -r user; do
        username=$(echo "$user" | jq -r '.username')
        password=$(echo "$user" | jq -r '.password')
        first_name=$(echo "$user" | jq -r '.first_name')
        last_name=$(echo "$user" | jq -r '.last_name')
        is_admin=$(echo "$user" | jq -r '.is_admin')

        if [ "$is_admin" = "true" ]; then
          continue
        fi

        echo "Creating regular Superset user: $username"
        docker exec superset superset fab create-user \
          --username "$username" \
          --firstname "$first_name" --lastname "$last_name" \
          --email "$username@local" \
          --password "$password" \
          --role "Gamma" || true
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.superset]
}