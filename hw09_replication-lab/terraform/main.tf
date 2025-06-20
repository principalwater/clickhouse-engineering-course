###############################################################################
# Terraform ClickHouse cluster (2S_2R, 3 Keeper) — структура из cluster_2S_2R
###############################################################################

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.1"
    }
  }
}

provider "docker" {}

locals {
  # Пользовательские имена
  super_user_name = var.super_user_name
  bi_user_name    = var.bi_user_name

  # Пароли для пользователей (sha256)
  super_user_password_sha256 = sha256(var.super_user_password)
  bi_user_password_sha256    = sha256(var.bi_user_password)

  # Настройки кластера
  cluster_name = "dwh_test"

  # Keeper-ноды (ручная конфигурация для кастомных имен, портов, id)
  keeper_nodes = [
    { name = "clickhouse-keeper-01", id = 1, host = "clickhouse-keeper-01", tcp_port = 9181, raft_port = 9234 },
    { name = "clickhouse-keeper-02", id = 2, host = "clickhouse-keeper-02", tcp_port = 9181, raft_port = 9234 },
    { name = "clickhouse-keeper-03", id = 3, host = "clickhouse-keeper-03", tcp_port = 9181, raft_port = 9234 },
  ]

  # ClickHouse-ноды (ручная карта для схемы 2S_2R, с кастомными портами и шардами/репликами)
  clickhouse_nodes = [
    { name = "clickhouse-01", shard = 1, replica = 1, host = "clickhouse-01", http_port = 8123, tcp_port = 9000 },
    { name = "clickhouse-02", shard = 2, replica = 1, host = "clickhouse-02", http_port = 8124, tcp_port = 9001 },
    { name = "clickhouse-03", shard = 1, replica = 2, host = "clickhouse-03", http_port = 8125, tcp_port = 9002 },
    { name = "clickhouse-04", shard = 2, replica = 2, host = "clickhouse-04", http_port = 8126, tcp_port = 9003 },
    # Новые реплики:
    { name = "clickhouse-05", shard = 1, replica = 3, host = "clickhouse-05", http_port = 8127, tcp_port = 9004 },
    { name = "clickhouse-06", shard = 2, replica = 3, host = "clickhouse-06", http_port = 8128, tcp_port = 9005 },
  ]

  # Для генерации remote_servers в config.xml.tpl — карта шардов с их репликами
  remote_servers = [
    {
      shard = 1
      replicas = [
        { host = "clickhouse-01", port = 9000 },
        { host = "clickhouse-03", port = 9002 },
        { host = "clickhouse-05", port = 9004 },
      ]
    },
    {
      shard = 2
      replicas = [
        { host = "clickhouse-02", port = 9001 },
        { host = "clickhouse-04", port = 9003 },
        { host = "clickhouse-06", port = 9005 },
      ]
    },
  ]
}

# Общая сеть для корректного сообщения контейнеров
resource "docker_network" "ch_net" {
  name = "clickhouse-net"
}

# 1. Скачиваем образы с фиксированной версией (по состоянию на июнь 2025)
resource "docker_image" "clickhouse_server" {
  name = "clickhouse/clickhouse-server:25.5.2-alpine"
}

resource "docker_image" "clickhouse_keeper" {
  name = "clickhouse/clickhouse-keeper:25.5.2-alpine"
}

# 2. Создаём директории для каждой ClickHouse-ноды
resource "null_resource" "mk_clickhouse_dirs" {
  for_each = { for n in local.clickhouse_nodes : n.name => n }
  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/config.d
      mkdir -p ${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/users.d
      mkdir -p ${var.clickhouse_base_path}/${each.key}/data
      mkdir -p ${var.clickhouse_base_path}/${each.key}/logs
    EOT
  }
}

# 3. Генерируем users.xml для каждой ClickHouse-ноды
resource "local_file" "users_xml" {
  for_each = { for n in local.clickhouse_nodes : n.name => n }
  content = templatefile("${path.module}/samples/users.xml.tpl", {
    super_user_name            = local.super_user_name
    super_user_password_sha256 = local.super_user_password_sha256
    bi_user_name               = local.bi_user_name
    bi_user_password_sha256    = local.bi_user_password_sha256
  })
  filename = "${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/users.d/users.xml"

  depends_on = [
    null_resource.mk_clickhouse_dirs
  ]
}

# 4. Генерируем config.xml для каждой ClickHouse-ноды (динамика remote_servers, zookeeper, макросы, порты)
resource "local_file" "config_xml" {
  for_each = { for n in local.clickhouse_nodes : n.name => n }
  content = templatefile("${path.module}/samples/config.xml.tpl", {
    node                = each.value
    remote_servers      = local.remote_servers
    keepers             = local.keeper_nodes
    cluster_name        = local.cluster_name
    super_user_name     = local.super_user_name
    super_user_password = var.super_user_password
  })
  filename = "${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/config.d/config.xml"
  depends_on = [
    null_resource.mk_clickhouse_dirs
  ]
}

# 5. Keeper: каталоги (host bind mounts)
resource "null_resource" "mk_keeper_dirs" {
  for_each = { for k in local.keeper_nodes : k.name => k }
  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ${var.clickhouse_base_path}/${each.key}/etc/clickhouse-keeper
      mkdir -p ${var.clickhouse_base_path}/${each.key}/data/coordination/log
      mkdir -p ${var.clickhouse_base_path}/${each.key}/data/coordination/snapshots
      mkdir -p ${var.clickhouse_base_path}/${each.key}/logs
    EOT
  }
}

# 6. Keeper: динамический конфиг для каждой keeper-ноды
resource "local_file" "keeper_config" {
  for_each = { for k in local.keeper_nodes : k.name => k }
  content = templatefile("${path.module}/samples/keeper_config.xml.tpl", {
    keeper      = each.value
    keepers_all = local.keeper_nodes
  })
  filename = "${var.clickhouse_base_path}/${each.key}/etc/clickhouse-keeper/keeper_config.xml"

  depends_on = [
    null_resource.mk_keeper_dirs
  ]
}

# 7. Запускаем контейнеры Keeper-ноды
resource "docker_container" "keeper" {
  for_each = { for k in local.keeper_nodes : k.name => k }
  name     = each.key
  hostname = each.key
  image    = docker_image.clickhouse_keeper.name

  user = "${var.ch_uid}:${var.ch_gid}"
  networks_advanced {
    name    = docker_network.ch_net.name
    aliases = [each.key]
  }

  restart = "unless-stopped"

  mounts {
    target    = "/etc/clickhouse-keeper/keeper_config.xml"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/etc/clickhouse-keeper/keeper_config.xml")
    type      = "bind"
    read_only = true
  }
  mounts {
    target    = "/var/lib/clickhouse/coordination"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/data/coordination")
    type      = "bind"
    read_only = false
  }
  mounts {
    target    = "/var/log/clickhouse-keeper"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/logs")
    type      = "bind"
    read_only = false
  }

  depends_on = [
    null_resource.mk_keeper_dirs,
    local_file.keeper_config
  ]
}

# 8. Запускаем контейнеры ClickHouse-ноды
resource "docker_container" "ch_nodes" {
  for_each = { for n in local.clickhouse_nodes : n.name => n }
  name     = each.key
  image    = docker_image.clickhouse_server.name
  # optimization part
  memory = var.memory_limit

  user = "${var.ch_uid}:${var.ch_gid}"
  networks_advanced {
    name    = docker_network.ch_net.name
    aliases = [each.key]
  }

  dynamic "ports" {
    for_each = each.key == "clickhouse-01" ? [1] : []
    content {
      internal = 8123
      external = 8123
    }
  }
  dynamic "ports" {
    for_each = each.key == "clickhouse-01" ? [1] : []
    content {
      internal = 9000
      external = 9000
    }
  }

  restart = "unless-stopped"

  mounts {
    target    = "/etc/clickhouse-server/config.d/config.xml"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/config.d/config.xml")
    type      = "bind"
    read_only = true
  }

  mounts {
    target    = "/etc/clickhouse-server/users.d/users.xml"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/users.d/users.xml")
    type      = "bind"
    read_only = true
  }

  mounts {
    target    = "/var/lib/clickhouse"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/data")
    type      = "bind"
    read_only = false
  }

  mounts {
    target    = "/var/log/clickhouse-server"
    source    = abspath("${var.clickhouse_base_path}/${each.key}/logs")
    type      = "bind"
    read_only = false
  }

  depends_on = [
    docker_container.keeper,
    null_resource.mk_clickhouse_dirs,
    local_file.config_xml,
    local_file.users_xml
  ]
}

# 9. Генерируем .env файл для скриптов (env/clickhouse.env)
resource "null_resource" "mk_env_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.root}/../env"
  }
}

resource "local_file" "env_file" {
  content = <<EOT
CH_USER=${local.super_user_name}
CH_PASSWORD=${var.super_user_password}
BI_USER=${local.bi_user_name}
BI_PASSWORD=${var.bi_user_password}
EOT

  filename   = "${path.root}/../env/clickhouse.env"
  depends_on = [null_resource.mk_env_dir]
}