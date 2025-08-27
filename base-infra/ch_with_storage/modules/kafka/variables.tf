variable "kafka_version" {
  description = "Версия для Docker-образов Confluent Platform (Kafka, Zookeeper)."
  type        = string
}

variable "docker_network_name" {
  description = "Имя Docker-сети, к которой будут подключены контейнеры."
  type        = string
}

variable "kafka_admin_user" {
  description = "Имя пользователя-администратора для Kafka."
  type        = string
}

variable "kafka_admin_password" {
  description = "Пароль для пользователя-администратора Kafka."
  type        = string
  sensitive   = true
}

variable "kafka_ssl_keystore_password" {
  description = "Пароль для Keystore и Truststore Kafka."
  type        = string
  sensitive   = true
}

variable "secrets_path" {
  description = "Абсолютный путь к директории с секретами для Kafka."
  type        = string
}

variable "enable_kafka_acl" {
  description = "Включить ACL авторизацию в Kafka"
  type        = bool
  default     = false
}
