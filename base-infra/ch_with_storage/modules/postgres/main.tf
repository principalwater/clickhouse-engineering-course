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
resource "docker_network" "postgres_network" {
  count  = var.enable_postgres ? 1 : 0
  name   = "postgres_network"
  driver = "bridge"
}

# --- PostgreSQL Container ---
resource "docker_image" "postgres" {
  count = var.enable_postgres ? 1 : 0
  name  = "postgres:${var.postgres_version}"
}

resource "docker_container" "postgres" {
  count    = var.enable_postgres ? 1 : 0
  name     = "postgres"
  image    = docker_image.postgres[0].name
  hostname = "postgres"
  networks_advanced {
    name    = docker_network.postgres_network[0].name
    aliases = ["postgres"]
  }
  dynamic "networks_advanced" {
    for_each = var.clickhouse_network_name != "" ? [var.clickhouse_network_name] : []
    content {
      name = networks_advanced.value
    }
  }
  env = [
    "POSTGRES_USER=postgres",
    "POSTGRES_PASSWORD=${local.effective_postgres_superuser_password}"
  ]
  restart = "unless-stopped"
  volumes {
    host_path      = abspath(var.postgres_data_path)
    container_path = "/var/lib/postgresql/data"
  }
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U postgres"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }

  # Лейблы для группировки контейнеров
  labels {
    label = "com.docker.compose.project"
    value = "clickhouse-engineering-course"
  }
  labels {
    label = "com.docker.compose.service"
    value = "postgres"
  }
  labels {
    label = "project.name"
    value = "clickhouse-engineering-course"
  }
  labels {
    label = "module.name"
    value = "postgres"
  }
  labels {
    label = "terraform.workspace"
    value = terraform.workspace
  }
  labels {
    label = "managed-by"
    value = "terraform"
  }
}

# --- Database and User Management ---

# Airflow database and user
resource "null_resource" "init_airflow_db" {
  count = var.enable_postgres && var.enable_airflow ? 1 : 0
  provisioner "local-exec" {
    command     = <<EOT
      # Wait for Postgres readiness (up to 60 sec)
      for i in {1..30}; do
        docker exec -i postgres pg_isready -U postgres && break || sleep 2
      done
      
      # Check if Airflow user exists
      USER_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.airflow_pg_user}'" | grep -q 1 && echo yes || echo no)
      if [ "$USER_EXISTS" = "no" ]; then
        echo "Creating Airflow user: ${var.airflow_pg_user} with extended privileges"
        docker exec -i postgres psql -U postgres -d postgres -c "CREATE USER ${var.airflow_pg_user} WITH PASSWORD '${local.effective_airflow_pg_password}' CREATEDB CREATEROLE;"
      else
        echo "Updating Airflow user ${var.airflow_pg_user} with extended privileges"
        docker exec -i postgres psql -U postgres -d postgres -c "ALTER USER ${var.airflow_pg_user} WITH PASSWORD '${local.effective_airflow_pg_password}' CREATEDB CREATEROLE;"
      fi
      
      # Check if Airflow DB exists
      DB_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${var.airflow_pg_db}'" | grep -q 1 && echo yes || echo no)
      if [ "$DB_EXISTS" = "no" ]; then
        echo "Creating Airflow database: ${var.airflow_pg_db}"
        docker exec -i postgres createdb -U postgres -O ${var.airflow_pg_user} ${var.airflow_pg_db}
      fi
      
      # Grant comprehensive privileges to airflow user
      echo "Granting comprehensive privileges on ${var.airflow_pg_db} to ${var.airflow_pg_user}"
      docker exec -i postgres psql -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${var.airflow_pg_db} TO ${var.airflow_pg_user};"
      
      # Grant schema-level privileges in the airflow database
      echo "Granting schema privileges in ${var.airflow_pg_db} to ${var.airflow_pg_user}"
      docker exec -i postgres psql -U postgres -d ${var.airflow_pg_db} -c "
        GRANT ALL PRIVILEGES ON SCHEMA public TO ${var.airflow_pg_user};
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${var.airflow_pg_user};
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${var.airflow_pg_user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${var.airflow_pg_user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${var.airflow_pg_user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${var.airflow_pg_user};
      "
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres[0]]
}

# Metabase database and user (for future)
resource "null_resource" "init_metabase_db" {
  count = var.enable_postgres && var.enable_metabase ? 1 : 0
  provisioner "local-exec" {
    command     = <<EOT
      # Wait for Postgres readiness (up to 60 sec)
      for i in {1..30}; do
        docker exec -i postgres pg_isready -U postgres && break || sleep 2
      done
      
      # Check if Metabase user exists
      USER_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.metabase_pg_user}'" | grep -q 1 && echo yes || echo no)
      if [ "$USER_EXISTS" = "no" ]; then
        echo "Creating Metabase user: ${var.metabase_pg_user}"
        docker exec -i postgres psql -U postgres -d postgres -c "CREATE USER ${var.metabase_pg_user} WITH PASSWORD '${local.effective_metabase_pg_password}';"
      else
        echo "Updating password for Metabase user: ${var.metabase_pg_user}"
        docker exec -i postgres psql -U postgres -d postgres -c "ALTER USER ${var.metabase_pg_user} WITH PASSWORD '${local.effective_metabase_pg_password}';"
      fi
      
      # Check if Metabase DB exists
      DB_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${var.metabase_pg_db}'" | grep -q 1 && echo yes || echo no)
      if [ "$DB_EXISTS" = "no" ]; then
        echo "Creating Metabase database: ${var.metabase_pg_db}"
        docker exec -i postgres createdb -U postgres ${var.metabase_pg_db}
      fi
      
      # Grant CREATE and USAGE on schema public in metabase DB to metabase user
      echo "Granting CREATE, USAGE on schema public to ${var.metabase_pg_user} in ${var.metabase_pg_db}"
      docker exec -i postgres psql -U postgres -d ${var.metabase_pg_db} -c "GRANT CREATE, USAGE ON SCHEMA public TO ${var.metabase_pg_user};"
      docker exec -i postgres psql -U postgres -d ${var.metabase_pg_db} -c "GRANT CREATE ON DATABASE ${var.metabase_pg_db} TO ${var.metabase_pg_user};"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres[0]]
}

# Superset database and user (for future)
resource "null_resource" "init_superset_db" {
  count = var.enable_postgres && var.enable_superset ? 1 : 0
  provisioner "local-exec" {
    command     = <<EOT
      # Wait for Postgres readiness (up to 60 sec)
      for i in {1..30}; do
        docker exec -i postgres pg_isready -U postgres && break || sleep 2
      done
      
      # Check if Superset user exists
      USER_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.superset_pg_user}'" | grep -q 1 && echo yes || echo no)
      if [ "$USER_EXISTS" = "no" ]; then
        echo "Creating Superset user: ${var.superset_pg_user}"
        docker exec -i postgres psql -U postgres -d postgres -c "CREATE USER ${var.superset_pg_user} WITH PASSWORD '${local.effective_superset_pg_password}';"
      else
        echo "Updating password for Superset user: ${var.superset_pg_user}"
        docker exec -i postgres psql -U postgres -d postgres -c "ALTER USER ${var.superset_pg_user} WITH PASSWORD '${local.effective_superset_pg_password}';"
      fi
      
      # Check if Superset DB exists
      DB_EXISTS=$(docker exec -i postgres psql -U postgres -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '${var.superset_pg_db}'" | grep -q 1 && echo yes || echo no)
      if [ "$DB_EXISTS" = "no" ]; then
        echo "Creating Superset database: ${var.superset_pg_db}"
        docker exec -i postgres createdb -U postgres ${var.superset_pg_db}
      fi
      
      # Grant CREATE and USAGE on schema public in superset DB to superset user
      echo "Granting CREATE, USAGE on schema public to ${var.superset_pg_user} in ${var.superset_pg_db}"
      docker exec -i postgres psql -U postgres -d ${var.superset_pg_db} -c "GRANT CREATE, USAGE ON SCHEMA public TO ${var.superset_pg_user};"
      docker exec -i postgres psql -U postgres -d ${var.superset_pg_db} -c "GRANT CREATE ON DATABASE ${var.superset_pg_db} TO ${var.superset_pg_user};"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres[0]]
}