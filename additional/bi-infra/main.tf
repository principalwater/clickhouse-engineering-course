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

locals {
  metabase_local_users = [
    {
      username   = var.metabase_sa_username
      password   = var.metabase_sa_password
      first_name = "Admin"
      last_name  = "User"
    },
    {
      username   = var.metabase_bi_username
      password   = var.metabase_bi_password
      first_name = "BI"
      last_name  = "User"
    }
  ]
  superset_local_users = [
    {
      username   = var.superset_sa_username
      password   = var.superset_sa_password
      first_name = "Admin"
      last_name  = "User"
      is_admin   = true
    },
    {
      username   = var.superset_bi_username
      password   = var.superset_bi_password
      first_name = "BI"
      last_name  = "User"
      is_admin   = false
    }
  ]
}

######################################################################
# Docker network setup
######################################################################
resource "docker_network" "metanet1" {
  name   = "metanet1"
  driver = "bridge"
}

######################################################################
# PostgreSQL Docker image and container setup
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
# Metabase Docker image and container setup
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
# Automate creation of local Metabase BI users
######################################################################
resource "null_resource" "metabase_create_local_users" {
  provisioner "local-exec" {
    command = <<EOT
      # Wait for Metabase to become healthy (up to 150 seconds)
      for i in {1..30}; do
        curl --fail -I http://localhost:${var.metabase_port}/api/health && break || sleep 5
      done

      # Authenticate as Metabase admin to get session token
      SESSION_TOKEN=$(curl -s -X POST http://localhost:${var.metabase_port}/api/session -H "Content-Type: application/json" -d '{
        "username": "${var.metabase_sa_username}",
        "password": "${var.metabase_sa_password}"
      }' | jq -r '.id')

      # Loop through local users JSON, skip admin (already exists), create others via API
      USERS_JSON='${jsonencode(local.metabase_local_users)}'
      echo "$USERS_JSON" | jq -c '.[]' | while read -r user; do
        username=$(echo "$user" | jq -r '.username')
        password=$(echo "$user" | jq -r '.password')
        first_name=$(echo "$user" | jq -r '.first_name')
        last_name=$(echo "$user" | jq -r '.last_name')

        # Skip admin user since it's created during superset_post_init or manually
        if [ "$username" = "${var.metabase_sa_username}" ]; then
          continue
        fi

        # Create user via Metabase API with session token for authorization
        curl -s -X POST http://localhost:${var.metabase_port}/api/user \
          -H "Content-Type: application/json" \
          -H "X-Metabase-Session: $SESSION_TOKEN" \
          -d '{
            "email": "'"${username}@local"'",
            "password": "'"${password}"'",
            "firstName": "'"${first_name}"'",
            "lastName": "'"${last_name}"'"
          }'

        # Optionally, assign groups to user via API here
        # curl -s -X POST http://localhost:${var.metabase_port}/api/user/${user_id}/group -H "X-Metabase-Session: $SESSION_TOKEN" -d '{"groupId": group_id}'
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.metabase]
}

######################################################################
# Superset configuration file generation
######################################################################
resource "local_file" "superset_config" {
  content = templatefile("${path.module}/samples/superset/superset_config.py.tmpl", {
    superset_secret_key = var.superset_secret_key
  })
  filename = abspath("${path.module}/superset_config.py")
}

######################################################################
# Initialize Superset database and user in PostgreSQL
######################################################################
resource "null_resource" "init_superset_db" {
  provisioner "local-exec" {
    command     = <<EOT
      # Create Superset database if it does not exist (using Superset Postgres metadata user credentials)
      docker exec -i postgres psql -U ${var.superset_pg_user} -tc "SELECT 1 FROM pg_database WHERE datname = '${var.superset_pg_db}'" | grep -q 1 || \
        docker exec -i postgres createdb -U ${var.superset_pg_user} ${var.superset_pg_db}
      # Create Superset user if it does not exist
      docker exec -i postgres psql -U ${var.superset_pg_user} -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.superset_pg_user}'" | grep -q 1 || \
        docker exec -i postgres psql -U ${var.superset_pg_user} -c "CREATE USER ${var.superset_pg_user} WITH PASSWORD '${var.superset_pg_password}';"
      # Grant all privileges on Superset database to the Superset user
      docker exec -i postgres psql -U ${var.superset_pg_user} -c "GRANT ALL PRIVILEGES ON DATABASE ${var.superset_pg_db} TO ${var.superset_pg_user};"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres]
}

######################################################################
# Superset Docker image and container setup
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
# Superset post-initialization automation
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

      # Initialize Superset database and create admin user (using BI app login user variables)
      docker exec superset superset db upgrade
      docker exec superset superset init
      docker exec superset superset fab create-admin \
        --username "${var.superset_sa_username}" \
        --firstname "Super" --lastname "User" \
        --email "${var.superset_sa_username}@local" \
        --password "${var.superset_sa_password}" || true
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.superset]
}

######################################################################
# Automate creation of local Superset BI users
######################################################################
resource "null_resource" "superset_create_local_users" {
  provisioner "local-exec" {
    command = <<EOT
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