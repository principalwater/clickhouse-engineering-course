terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.1"
    }
    local = {
      source = "hashicorp/local"
      version = "2.5.3"
    }
    null = {
      source = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

provider "docker" {}

resource "docker_network" "metanet1" {
  name   = "metanet1"
  driver = "bridge"
}

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
  restart = "unless-stopped"
  depends_on = [docker_container.postgres]
  healthcheck {
    test     = ["CMD-SHELL", "curl --fail -I http://localhost:3000/api/health || exit 1"]
    interval = "15s"
    timeout  = "5s"
    retries  = 5
  }
}

# Интеграция с Superset
resource "local_file" "superset_config" {
  content  = templatefile("${path.module}/samples/superset/superset_config.py.tmpl", {
    superset_secret_key = var.superset_secret_key
  })
  filename = abspath("${path.module}/superset_config.py")
}

resource "null_resource" "init_superset_db" {
  provisioner "local-exec" {
    command = <<EOT
      # Создаём базу если нет
      docker exec -i postgres psql -U ${var.metabase_pg_user} -tc "SELECT 1 FROM pg_database WHERE datname = '${var.superset_pg_db}'" | grep -q 1 || \
        docker exec -i postgres createdb -U ${var.metabase_pg_user} ${var.superset_pg_db}
      # Создаём пользователя если нет
      docker exec -i postgres psql -U ${var.metabase_pg_user} -tc "SELECT 1 FROM pg_roles WHERE rolname = '${var.superset_pg_user}'" | grep -q 1 || \
        docker exec -i postgres psql -U ${var.metabase_pg_user} -c "CREATE USER ${var.superset_pg_user} WITH PASSWORD '${var.superset_pg_password}';"
      # Даем права
      docker exec -i postgres psql -U ${var.metabase_pg_user} -c "GRANT ALL PRIVILEGES ON DATABASE ${var.superset_pg_db} TO ${var.superset_pg_user};"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.postgres]
}

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

resource "null_resource" "superset_post_init" {
  provisioner "local-exec" {
    command = <<EOT
      for i in {1..30}; do
        docker exec superset curl -sf http://localhost:8088/health && break || sleep 5
      done

      # Обновляем pip и устанавливаем драйверы ClickHouse внутри контейнера Superset
      docker exec superset pip install --upgrade pip
      docker exec superset pip install clickhouse-connect clickhouse-driver

      # Далее — стандартная инициализация Superset
      docker exec superset superset db upgrade
      docker exec superset superset init
      docker exec superset superset fab create-admin \
        --username "${var.superset_sa_user}" \
        --firstname "Super" --lastname "User" \
        --email "${var.superset_sa_email}" \
        --password "${var.superset_sa_password}" || true
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [docker_container.superset]
}