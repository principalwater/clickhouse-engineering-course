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
  name     = "postgres"
  image    = docker_image.postgres.name
  hostname = "postgres"
  networks_advanced {
    name    = docker_network.metanet1.name
    aliases = ["postgres"]
  }
  env = [
    # Postgres metadata user credentials (for Metabase and Superset DB setup)
    "POSTGRES_USER=${var.metabase_pg_user}",
    "POSTGRES_PASSWORD=${var.metabase_pg_password}",
    "POSTGRES_DB=${var.metabase_pg_db}",
  ]
  restart = "unless-stopped"
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.metabase_pg_user} -d ${var.metabase_pg_db}"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

######################################################################
# ---- Section: Metabase (image, container) ----
######################################################################
resource "docker_image" "metabase" {
  name = "metabase/metabase:${var.metabase_version}"
}

resource "docker_container" "metabase" {
  name     = "metabase"
  image    = docker_image.metabase.name
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
    "MB_DB_PASS=${var.metabase_pg_password}",
    "MB_DB_HOST=postgres"
  ]
  restart    = "unless-stopped"
  depends_on = [docker_container.postgres]
  healthcheck {
    test     = ["CMD-SHELL", "curl --fail -I http://localhost:3000/api/health || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 5
  }
}

######################################################################
# ---- Section: Metabase user automation ----
# Using local.metabase_local_users and local effective usernames/passwords from locals.tf
######################################################################
resource "null_resource" "metabase_create_local_users" {
  provisioner "local-exec" {
    command = <<EOT
      # Authenticate as Metabase admin to get session token
      SESSION_TOKEN=$(curl -s -X POST http://localhost:3000/api/session -H "Content-Type: application/json" -d '{
        "username": "${local.effective_metabase_sa_username}",
        "password": "${local.effective_metabase_sa_password}"
      }' | jq -r '.id')

      # Check if BI user already exists by username
      BI_USERNAME="${local.effective_metabase_bi_username}"
      USER_EXISTS=$(curl -s -H "X-Metabase-Session: $SESSION_TOKEN" http://localhost:3000/api/user | jq -r --arg username "$BI_USERNAME" '.[] | select(.username == $username) | .id // empty')

      if [ -z "$USER_EXISTS" ]; then
        # Find BI user details from local.metabase_local_users by username
        USER_DATA=$(echo '${jsonencode(local.metabase_local_users)}' | jq -c --arg username "$BI_USERNAME" '.[] | select(.username == $username)')

        if [ -n "$USER_DATA" ]; then
          EMAIL=$(echo "$USER_DATA" | jq -r '.username + "@local"')
          PASSWORD=$(echo "$USER_DATA" | jq -r '.password')
          FIRST_NAME=$(echo "$USER_DATA" | jq -r '.first_name')
          LAST_NAME=$(echo "$USER_DATA" | jq -r '.last_name')

          # Create BI user via Metabase API
          CREATE_USER_PAYLOAD=$(jq -n \
            --arg email "$EMAIL" \
            --arg password "$PASSWORD" \
            --arg firstName "$FIRST_NAME" \
            --arg lastName "$LAST_NAME" \
            '{email: $email, password: $password, firstName: $firstName, lastName: $lastName}')

          curl -s -X POST http://localhost:3000/api/user \
            -H "Content-Type: application/json" \
            -H "X-Metabase-Session: $SESSION_TOKEN" \
            -d "$CREATE_USER_PAYLOAD"
        else
          echo "BI user details not found in local.metabase_local_users for username: $BI_USERNAME"
          exit 1
        fi
      else
        echo "BI user '$BI_USERNAME' already exists with id $USER_EXISTS"
      fi

      # Disable initial setup wizard
      curl -s -X PUT http://localhost:3000/api/setup/admin \
        -H "Content-Type: application/json" \
        -H "X-Metabase-Session: $SESSION_TOKEN" \
        -d '{"setupComplete": true}'
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.metabase]
}

######################################################################
# ---- Section: Superset config ----
######################################################################
resource "local_file" "superset_config" {
  content = templatefile("${path.module}/samples/superset/superset_config.py.tmpl", {
    superset_secret_key = var.superset_secret_key
  })
  filename = abspath("${path.module}/superset_config.py")
}

######################################################################
# ---- Section: Superset DB init in Postgres ----
######################################################################
resource "null_resource" "init_superset_db" {
  provisioner "local-exec" {
    command = <<EOT
      # Создать роль superset, если не существует (от имени администратора)
      ROLE_EXISTS=$(docker exec -i postgres psql -U ${var.metabase_pg_user} -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.superset_pg_user}'" | grep -q 1 && echo yes || echo no)
      if [ "$ROLE_EXISTS" = "no" ]; then
        docker exec -i postgres psql -U ${var.metabase_pg_user} -d postgres -c "CREATE USER ${var.superset_pg_user} WITH PASSWORD '${var.superset_pg_password}';"
      fi

      # Создать базу superset, если не существует (от имени администратора)
      DB_EXISTS=$(docker exec -i postgres psql -U ${var.metabase_pg_user} -tc "SELECT 1 FROM pg_database WHERE datname = '${var.superset_pg_db}'" | grep -q 1 && echo yes || echo no)
      if [ "$DB_EXISTS" = "no" ]; then
        docker exec -i postgres createdb -U ${var.metabase_pg_user} ${var.superset_pg_db}
      fi

      # Назначить все права на базу пользователю superset
      docker exec -i postgres psql -U ${var.metabase_pg_user} -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${var.superset_pg_db} TO ${var.superset_pg_user};"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres]
}

######################################################################
# ---- Section: Superset (image, container) ----
######################################################################
resource "docker_image" "superset" {
  name = "apache/superset:${var.superset_version}"
}

resource "docker_container" "superset" {
  name     = "superset"
  image    = docker_image.superset.name
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
    "SUPERSET_DATABASE_URI=postgresql+psycopg2://${var.superset_pg_user}:${var.superset_pg_password}@postgres:5432/${var.superset_pg_db}",
    "SECRET_KEY=${var.superset_secret_key}",
    "PYTHONPATH=/app/pythonpath"
  ]
  volumes {
    host_path      = local_file.superset_config.filename
    container_path = "/app/pythonpath/superset_config.py"
    read_only      = true
  }
  restart = "unless-stopped"
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
# Using local effective admin username/password from locals.tf
######################################################################
resource "null_resource" "superset_post_init" {
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
  depends_on = [docker_container.superset]
}

######################################################################
# ---- Section: Superset user automation ----
# Using local.superset_local_users and local effective usernames/passwords from locals.tf
######################################################################
resource "null_resource" "superset_create_local_users" {
  provisioner "local-exec" {
    command = <<EOT
      # Automatic creation of admin and BI users with unified credentials from locals.tf.
      # Wait for Superset to become healthy (up to 150 seconds)
      for i in {1..30}; do
        docker exec superset curl -sf http://localhost:8088/health && break || sleep 5
      done

      USERS_JSON='${jsonencode(local.superset_local_users)}'
      echo "$USERS_JSON" | jq -c '.[]' | while read -r user; do
        username=$(echo "$user" | jq -r '.username')
        password=$(echo "$user" | jq -r '.password')
        first_name=$(echo "$user" | jq -r '.first_name')
        last_name=$(echo "$user" | jq -r '.last_name')
        is_admin=$(echo "$user" | jq -r '.is_admin')

        if [ "$is_admin" = "true" ]; then
          docker exec superset superset fab create-admin \
            --username "$username" \
            --firstname "$first_name" --lastname "$last_name" \
            --email "$username@local" \
            --password "$password" || true
        else
          docker exec superset superset fab create-user \
            --username "$username" \
            --firstname "$first_name" --lastname "$last_name" \
            --email "$username@local" \
            --password "$password" \
            --role "Gamma" || true
        fi
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.superset]
}