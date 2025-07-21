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
    { name = "clickhouse-keeper-03", id = 3, host = "clickhouse-keeper-03", tcp_port = 9181, raft_port = 9234 }
  ]

  # Определяем ноды для разных топологий
  clickhouse_nodes_2s_2r = [
    { name = "clickhouse-01", shard = 1, replica = 1, host = "clickhouse-01", http_port = var.use_standard_ports ? var.ch_http_port : 8123, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9000 },
    { name = "clickhouse-02", shard = 2, replica = 1, host = "clickhouse-02", http_port = var.use_standard_ports ? var.ch_http_port : 8124, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9001 },
    { name = "clickhouse-03", shard = 1, replica = 2, host = "clickhouse-03", http_port = var.use_standard_ports ? var.ch_http_port : 8125, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9002 },
    { name = "clickhouse-04", shard = 2, replica = 2, host = "clickhouse-04", http_port = var.use_standard_ports ? var.ch_http_port : 8126, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9003 },
  ]

  clickhouse_nodes_4s_1r = [
    { name = "clickhouse-01", shard = 1, replica = 1, host = "clickhouse-01", http_port = var.use_standard_ports ? var.ch_http_port : 8123, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9000 },
    { name = "clickhouse-02", shard = 2, replica = 1, host = "clickhouse-02", http_port = var.use_standard_ports ? var.ch_http_port : 8124, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9001 },
    { name = "clickhouse-03", shard = 3, replica = 1, host = "clickhouse-03", http_port = var.use_standard_ports ? var.ch_http_port : 8125, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9002 },
    { name = "clickhouse-04", shard = 4, replica = 1, host = "clickhouse-04", http_port = var.use_standard_ports ? var.ch_http_port : 8126, tcp_port = var.use_standard_ports ? var.ch_tcp_port : 9003 },
  ]

  # Выбираем топологию в зависимости от переменной
  clickhouse_nodes_map = {
    "2s_2r" = local.clickhouse_nodes_2s_2r
    "4s_1r" = local.clickhouse_nodes_4s_1r
  }
  
  clickhouse_nodes = local.clickhouse_nodes_map[var.cluster_topology]

  # Для генерации remote_servers в config.xml.tpl — динамическая карта шардов с их репликами.
  # Это гарантирует, что при добавлении новых нод конфиги на старых нодах обновятся.
  remote_servers = [
    for shard_num in distinct([for n in local.clickhouse_nodes : n.shard]) : {
      shard = shard_num
      replicas = [
        for n in local.clickhouse_nodes : {
          host = n.host
          port = var.use_standard_ports ? var.ch_tcp_port : n.tcp_port
        } if n.shard == shard_num
      ]
    }
  ]

  # Готовим контент для всех конфигов заранее, чтобы избежать дублирования
  # и использовать его и для хеша в лейбле, и для записи на диск.
  clickhouse_configs = {
    for n in local.clickhouse_nodes : n.name => templatefile("${path.module}/samples/config.xml.tpl", {
      node                = n
      remote_servers      = local.remote_servers
      keepers             = local.keeper_nodes
      cluster_name        = local.cluster_name
      super_user_name     = local.super_user_name
      super_user_password = var.super_user_password
      ch_http_port        = var.use_standard_ports ? var.ch_http_port : n.http_port
      ch_tcp_port         = var.use_standard_ports ? var.ch_tcp_port : n.tcp_port
      ch_replication_port = var.ch_replication_port
      macros = {
        shard   = n.shard
        replica = n.replica
      }
    })
  }
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

# 4. Генерируем config.xml для каждой ClickHouse-ноды с помощью null_resource и local-exec.
# Это решает проблему с race condition при замене контейнеров, так как файл
# не удаляется, а перезаписывается, что является атомарной операцией для Docker.
resource "null_resource" "write_config_xml" {
  for_each = local.clickhouse_configs

  triggers = {
    # Триггер для перезапуска provisioner'а при изменении контента конфига
    content_sha256 = sha256(each.value)
  }

  provisioner "local-exec" {
    command = <<EOT
cat > "${var.clickhouse_base_path}/${each.key}/etc/clickhouse-server/config.d/config.xml" <<EOF
${each.value}
EOF
EOT
  }

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

  # Добавляем label с хешем конфига, чтобы контейнер пересоздавался при его изменении.
  # Хеш берем из заранее подготовленной карты `local.clickhouse_configs`.
  labels {
    label = "config_hash"
    value = sha256(local.clickhouse_configs[each.key])
  }

  user = "${var.ch_uid}:${var.ch_gid}"
  networks_advanced {
    name    = docker_network.ch_net.name
    aliases = [each.key]
  }

  dynamic "ports" {
    for_each = each.key == "clickhouse-01" ? [1] : []
    content {
      internal = var.use_standard_ports ? var.ch_http_port : each.value.http_port
      external = var.use_standard_ports ? var.ch_http_port : each.value.http_port
    }
  }

  dynamic "ports" {
    for_each = each.key == "clickhouse-01" ? [1] : []
    content {
      internal = var.use_standard_ports ? var.ch_tcp_port : each.value.tcp_port
      external = var.use_standard_ports ? var.ch_tcp_port : each.value.tcp_port
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
    null_resource.write_config_xml,
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
