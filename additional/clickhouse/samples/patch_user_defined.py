import sys
from lxml import etree

if len(sys.argv) != 2:
    print("Usage: patch_user_defined.py <config.xml>")
    sys.exit(1)

config_path = sys.argv[1]
UDF_CONFIG_PATH = "/var/lib/clickhouse/user_defined/user_defined_functions.xml"
USER_SCRIPTS_PATH = "/var/lib/clickhouse/user_scripts/"

parser = etree.XMLParser(remove_blank_text=True)
tree = etree.parse(config_path, parser)
root = tree.getroot()  # <clickhouse>

# Удаляем старые user_defined_executable_functions_config и user_scripts_path
for elem in root.findall(".//user_defined_executable_functions_config"):
    parent = elem.getparent()
    parent.remove(elem)
for elem in root.findall(".//user_scripts_path"):
    parent = elem.getparent()
    parent.remove(elem)

# Добавляем новые параметры в конец <clickhouse>
udf_config_elem = etree.Element("user_defined_executable_functions_config")
udf_config_elem.text = UDF_CONFIG_PATH
root.append(udf_config_elem)

scripts_path_elem = etree.Element("user_scripts_path")
scripts_path_elem.text = USER_SCRIPTS_PATH
root.append(scripts_path_elem)

tree.write(config_path, pretty_print=True, encoding="utf-8", xml_declaration=False)