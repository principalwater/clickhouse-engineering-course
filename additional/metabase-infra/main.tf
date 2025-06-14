terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "metanet1" {
  name = "metanet1"
  driver = "bridge"
}

resource "docker_image" "postgres" {
  name = "postgres:${var.postgres_version}"
}

resource "docker_container" "postgres" {
  name  = "postgres"
  image = docker_image.postgres.name
  hostname = "postgres"
  networks_advanced {
    name = docker_network.metanet1.name
    aliases = ["postgres"]
  }
  env = [
    "POSTGRES_USER=${var.pg_user}",
    "POSTGRES_PASSWORD=${var.pg_password}",
    "POSTGRES_DB=${var.pg_db}",
  ]
  restart = "unless-stopped"
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.pg_user} -d ${var.pg_db}"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

resource "docker_image" "metabase" {
  name = "metabase/metabase:${var.metabase_version}"
}

resource "docker_container" "metabase" {
  name  = "metabase"
  image = docker_image.metabase.name
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
    name = docker_network.metanet1.name
    aliases = ["metabase"]
  }
  env = [
    "MB_DB_TYPE=postgres",
    "MB_DB_DBNAME=${var.pg_db}",
    "MB_DB_PORT=5432",
    "MB_DB_USER=${var.pg_user}",
    "MB_DB_PASS=${var.pg_password}",
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

# Пример задела под Superset и другие сервисы:
# resource "docker_image" "superset" {
#   name = "apache/superset:3.0.0"
# }
# resource "docker_container" "superset" { ... }