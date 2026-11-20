#!/usr/bin/env python3
"""
Génère le schéma CloudKit (.ckdb) correspondant au modèle Core Data de MonVoyage,
selon la correspondance utilisée par NSPersistentCloudKitContainer :

  entité X            -> type d'enregistrement CD_X
  attribut a          -> champ CD_a
  relation to-one r   -> champ CD_r (STRING : nom de l'enregistrement lié)
  relation to-many    -> rien (portée par la relation inverse to-one)
  + CD_entityName (STRING), CD_moveReceipt (ASSET)
  + CD_a_ckAsset (ASSET) pour les textes et données binaires (valeurs volumineuses)

Pourquoi : les builds TestFlight utilisent toujours l'environnement Production ;
le schéma ne peut donc pas être créé depuis l'appli. GitHub Actions importe ce fichier
dans l'environnement Development avec `xcrun cktool import-schema`, puis on le
déploie vers Production depuis la console CloudKit.

Usage : python3 scripts/make_cloudkit_schema.py [sortie.ckdb]
Python 3 standard uniquement. Les champs en trop sont sans effet ; un champ manquant
serait signalé par l'appli (écran caché CloudKit) avec son nom exact.
"""
import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIR = os.path.join(ROOT, "MonVoyage", "Persistence", "MonVoyage.xcdatamodeld")

TYPE_MAP = {
    "String": "STRING",
    "UUID": "STRING",
    "URI": "STRING",
    "Decimal": "STRING",
    "Date": "TIMESTAMP",
    "Double": "DOUBLE",
    "Float": "DOUBLE",
    "Integer 16": "INT64",
    "Integer 32": "INT64",
    "Integer 64": "INT64",
    "Boolean": "INT64",
    "Binary": "BYTES",
}
LARGE_VALUE_TYPES = {"String", "Binary"}

SYSTEM_FIELDS = [
    ('"___createTime"', "TIMESTAMP"),
    ('"___createdBy"', "REFERENCE"),
    ('"___etag"', "STRING"),
    ('"___modTime"', "TIMESTAMP"),
    ('"___modifiedBy"', "REFERENCE"),
    ('"___recordID"', "REFERENCE QUERYABLE"),
]


def current_model_path():
    """Version courante du modèle (lue dans .xccurrentversion)."""
    current = os.path.join(MODEL_DIR, ".xccurrentversion")
    name = "MonVoyage.xcdatamodel"
    if os.path.exists(current):
        tree = ET.parse(current)
        strings = [e.text for e in tree.iter("string") if e.text]
        if strings:
            name = strings[0]
    return os.path.join(MODEL_DIR, name, "contents")


def record_type(entity):
    name = entity.get("name")
    fields = list(SYSTEM_FIELDS)
    fields.append(('"CD_entityName"', "STRING QUERYABLE"))
    fields.append(('"CD_moveReceipt"', "ASSET"))
    for attr in entity.findall("attribute"):
        if attr.get("transient") == "YES":
            continue
        a_name, a_type = attr.get("name"), attr.get("attributeType")
        if a_type not in TYPE_MAP:
            raise SystemExit(f"Type d'attribut non géré : {name}.{a_name} ({a_type})")
        fields.append((f'"CD_{a_name}"', TYPE_MAP[a_type]))
        if a_type in LARGE_VALUE_TYPES:
            fields.append((f'"CD_{a_name}_ckAsset"', "ASSET"))
    for rel in entity.findall("relationship"):
        if rel.get("toMany") == "YES":
            inverse = rel.get("inverseEntity"), rel.get("inverseName")
            for other in ENTITIES:
                if other.get("name") == inverse[0]:
                    for r2 in other.findall("relationship"):
                        if r2.get("name") == inverse[1] and r2.get("toMany") == "YES":
                            raise SystemExit(f"Relation plusieurs-à-plusieurs non gérée : {name}.{rel.get('name')}")
            continue
        fields.append((f'"CD_{rel.get("name")}"', "STRING"))

    width = max(len(f[0]) for f in fields)
    lines = [f"    RECORD TYPE CD_{name} ("]
    for field, ftype in fields:
        lines.append(f"        {field.ljust(width)} {ftype},")
    lines.append('        GRANT WRITE TO "_creator",')
    lines.append('        GRANT CREATE TO "_icloud",')
    lines.append('        GRANT READ TO "_world"')
    lines.append("    );")
    return "\n".join(lines)


USERS = """    RECORD TYPE Users (
        "___createTime" TIMESTAMP,
        "___createdBy"  REFERENCE,
        "___etag"       STRING,
        "___modTime"    TIMESTAMP,
        "___modifiedBy" REFERENCE,
        "___recordID"   REFERENCE,
        roles           LIST<INT64>,
        GRANT WRITE TO "_creator",
        GRANT READ TO "_world"
    );"""

ENTITIES = []


def main():
    global ENTITIES
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "cloudkit-schema.ckdb")
    model = ET.parse(current_model_path()).getroot()
    ENTITIES = model.findall("entity")
    parts = ["DEFINE SCHEMA", "", USERS, ""]
    for entity in ENTITIES:
        parts.append(record_type(entity))
        parts.append("")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))
    print(f"Schéma écrit : {out} ({len(ENTITIES)} types CD_*)")


if __name__ == "__main__":
    main()
