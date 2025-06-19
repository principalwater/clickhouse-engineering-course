output "copy_udf_status" {
  value = var.enable_eudf ? "UDF скрипты скопированы и настроены." : "UDF скрипты не копировались."
}

output "patch_user_defined_status" {
  value = var.enable_eudf ? "patch_user_defined.py был применён к каждой ноде." : "patch_user_defined.py не применялся."
}

output "udf_files" {
  value = var.enable_eudf ? fileset("${path.module}/${var.udf_dir}", "*.py") : []
}

output "dictionaries_status" {
  value = var.enable_dictionaries ? "Словари скопированы, сгенерированы и подключены." : "Словари не настраивались."
}

output "patch_dictionaries_status" {
  value = var.enable_dictionaries ? "patch_dictionaries.py был применён к каждой ноде, <dictionaries_config> добавлен." : "patch_dictionaries.py не применялся, конфиг не менялся."
}

output "dictionary_files" {
  value = var.enable_dictionaries ? fileset("${path.module}/samples/dictionaries", "*.xml") : []
}