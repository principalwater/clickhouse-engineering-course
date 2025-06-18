output "udf_files" {
  value = var.enable_copy_udf ? fileset("${path.module}/${var.udf_dir}", "*.py") : []
}

output "dictionary_files" {
  value = var.enable_dictionaries ? fileset("${path.module}/samples/dictionaries", "*.xml") : []
}