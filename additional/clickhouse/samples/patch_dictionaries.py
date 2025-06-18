import sys
from lxml import etree

if len(sys.argv) != 2:
    print("Usage: patch_dictionaries.py <config.xml>")
    sys.exit(1)

config_path = sys.argv[1]
DICTIONARIES_CONFIG_PATH = "/var/lib/clickhouse/dictionaries/*.xml"

parser = etree.XMLParser(remove_blank_text=True)
tree = etree.parse(config_path, parser)
root = tree.getroot()  # <clickhouse>

# Удаляем любые старые <dictionaries_config>
for elem in root.findall(".//dictionaries_config"):
    parent = elem.getparent()
    parent.remove(elem)

# Добавляем новый <dictionaries_config> в конец <clickhouse>
config_elem = etree.Element("dictionaries_config")
config_elem.text = DICTIONARIES_CONFIG_PATH
root.append(config_elem)
print(f"Added dictionaries_config: {DICTIONARIES_CONFIG_PATH}")

tree.write(config_path, pretty_print=True, encoding="utf-8", xml_declaration=False)