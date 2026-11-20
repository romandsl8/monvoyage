#!/usr/bin/env python3
"""
Produit affluence.json pour l'appli MonVoyage.

Format :
{
  "updatedAt": "2026-11-20T05:00:00Z",
  "source": "…",
  "parks": { "<id Queue-Times>": { "YYYY-MM-DD": { "level": 1-10, "label": "…", "open": "09:00", "close": "21:00" } } }
}

Système d'adaptateurs (variable d'environnement ADAPTERS, séparés par des virgules) :
  - "calendar"        : estimation calendaire locale (saisons de Floride, jours fériés US,
                        vacances scolaires, jour de la semaine). Aucune donnée tierce.
  - "themeparks_wiki" : horaires d'ouverture officiels via l'API ouverte ThemeParks.wiki
                        (gratuite, sans clé, prévue pour un usage automatisé).
  - "empty"           : fichier vide valide (l'appli bascule sur la saisie manuelle).
Par défaut : "calendar,themeparks_wiki".

Règle d'or : on ne publie JAMAIS un fichier invalide. En cas d'erreur, le fichier
précédent (--previous) est conservé tel quel.

Python 3 standard uniquement.
"""
import argparse
import datetime as dt
import json
import os
import sys
import urllib.request

USER_AGENT = "MonVoyage-affluence/1.0 (GitHub Actions)"
HORIZON_DAYS = int(os.environ.get("HORIZON_DAYS", "400"))

# Parcs suivis : id Queue-Times → noms utilisés pour retrouver le parc dans chaque source.
PARKS = {
    "65": {"name": "Universal Studios Florida", "qt_match": "Universal Studios At Universal Orlando", "tpw_match": "Universal Studios Florida", "kind": "theme"},
    "64": {"name": "Islands of Adventure", "qt_match": "Islands Of Adventure", "tpw_match": "Islands of Adventure", "kind": "theme"},
    "334": {"name": "Epic Universe", "qt_match": "Epic Universe", "tpw_match": "Epic Universe", "kind": "theme"},
    "67": {"name": "Volcano Bay", "qt_match": "Volcano Bay", "tpw_match": "Volcano Bay", "kind": "water"},
}


def http_json(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def label_for(level):
    if level <= 2:
        return "Très calme"
    if level <= 4:
        return "Calme"
    if level <= 6:
        return "Modéré"
    if level <= 8:
        return "Chargé"
    return "Très chargé"


# --------------------------------------------------------------------------
# Adaptateur « calendar » : estimation calendaire
# --------------------------------------------------------------------------

def nth_weekday(year, month, weekday, n):
    """n-ième jour de semaine (0 = lundi) du mois ; n = -1 pour le dernier."""
    if n > 0:
        d = dt.date(year, month, 1)
        while d.weekday() != weekday:
            d += dt.timedelta(days=1)
        return d + dt.timedelta(weeks=n - 1)
    d = dt.date(year + (month == 12), month % 12 + 1, 1) - dt.timedelta(days=1)
    while d.weekday() != weekday:
        d -= dt.timedelta(days=1)
    return d


def easter(year):
    a = year % 19
    b, c = divmod(year, 100)
    d, e = divmod(b, 4)
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = divmod(c, 4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return dt.date(year, month, day)


def special_periods(year):
    """Périodes chargées : (début, fin, bonus)."""
    thanksgiving = nth_weekday(year, 11, 3, 4)
    e = easter(year)
    return [
        (dt.date(year, 1, 1), dt.date(year, 1, 2), 3),                       # Nouvel An
        (nth_weekday(year, 1, 0, 3) - dt.timedelta(days=2), nth_weekday(year, 1, 0, 3), 2),   # MLK
        (nth_weekday(year, 2, 0, 3) - dt.timedelta(days=2), nth_weekday(year, 2, 0, 3), 2),   # Presidents' Day
        (dt.date(year, 3, 7), dt.date(year, 4, 5), 2),                      # Spring break
        (e - dt.timedelta(days=8), e + dt.timedelta(days=1), 2),            # Pâques
        (nth_weekday(year, 5, 0, -1) - dt.timedelta(days=2), nth_weekday(year, 5, 0, -1), 2),  # Memorial Day
        (dt.date(year, 7, 3), dt.date(year, 7, 5), 2),                      # Fête nationale US
        (nth_weekday(year, 9, 0, 1) - dt.timedelta(days=2), nth_weekday(year, 9, 0, 1), 1),   # Labor Day
        (dt.date(year, 10, 1), dt.date(year, 10, 31), 1),                   # Halloween Horror Nights
        (thanksgiving - dt.timedelta(days=3), thanksgiving + dt.timedelta(days=3), 3),        # Thanksgiving
        (dt.date(year, 12, 20), dt.date(year, 12, 31), 4),                  # Fêtes de fin d'année
    ]


MONTH_BASE = {1: 4, 2: 5, 3: 6, 4: 6, 5: 4, 6: 7, 7: 7, 8: 5, 9: 3, 10: 5, 11: 5, 12: 6}
WEEKDAY_ADJ = {0: 0, 1: -1, 2: -1, 3: -0.5, 4: 0.5, 5: 1.5, 6: 0.5}


def calendar_level(park_id, day):
    level = MONTH_BASE[day.month] + WEEKDAY_ADJ[day.weekday()]
    for start, end, bonus in special_periods(day.year):
        if start <= day <= end:
            level += bonus
            break
    info = PARKS[park_id]
    if park_id == "334":
        level += 1          # parc le plus récent, très demandé
    if info["kind"] == "water":
        level += 1 if day.month in (6, 7, 8) else (-2 if day.month in (11, 12, 1, 2) else 0)
    return max(1, min(10, int(round(level))))


def adapter_calendar(data, today):
    for park_id in PARKS:
        days = data.setdefault(park_id, {})
        for offset in range(HORIZON_DAYS):
            day = today + dt.timedelta(days=offset)
            level = calendar_level(park_id, day)
            entry = days.setdefault(day.isoformat(), {})
            entry["level"] = level
            entry["label"] = label_for(level)
    return "Estimation calendaire MonVoyage"


# --------------------------------------------------------------------------
# Adaptateur « themeparks_wiki » : horaires officiels
# --------------------------------------------------------------------------

def adapter_themeparks_wiki(data, today):
    destinations = http_json("https://api.themeparks.wiki/v1/destinations").get("destinations", [])
    orlando = next((d for d in destinations if "Universal Orlando" in d.get("name", "")), None)
    if not orlando:
        raise RuntimeError("Universal Orlando introuvable sur ThemeParks.wiki")
    found = 0
    for park_id, info in PARKS.items():
        entity = next((p for p in orlando.get("parks", []) if info["tpw_match"].lower() in p.get("name", "").lower()), None)
        if not entity:
            print(f"  ! {info['name']} absent de ThemeParks.wiki", file=sys.stderr)
            continue
        schedule = http_json(f"https://api.themeparks.wiki/v1/entity/{entity['id']}/schedule").get("schedule", [])
        days = data.setdefault(park_id, {})
        for item in schedule:
            if item.get("type") != "OPERATING":
                continue
            date = item.get("date")
            opening, closing = item.get("openingTime", ""), item.get("closingTime", "")
            if not date or len(opening) < 16 or len(closing) < 16:
                continue
            entry = days.setdefault(date, {})
            # Heure locale du parc (l'API renvoie l'heure avec son décalage, ex. 2026-11-20T09:00:00-05:00).
            open_time, close_time = opening[11:16], closing[11:16]
            if "open" not in entry or open_time < entry["open"]:
                entry["open"] = open_time
            if "close" not in entry or close_time > entry["close"]:
                entry["close"] = close_time
            found += 1
    print(f"  horaires trouvés : {found}")
    return "Horaires ThemeParks.wiki"


def adapter_empty(data, today):
    return "Aucune source (saisie manuelle)"


ADAPTERS = {
    "calendar": adapter_calendar,
    "themeparks_wiki": adapter_themeparks_wiki,
    "empty": adapter_empty,
}


# --------------------------------------------------------------------------
# Validation et écriture
# --------------------------------------------------------------------------

def validate(doc):
    assert isinstance(doc, dict)
    assert isinstance(doc.get("updatedAt"), str) and doc["updatedAt"]
    assert isinstance(doc.get("source"), str)
    parks = doc.get("parks")
    assert isinstance(parks, dict)
    for park_id, days in parks.items():
        assert isinstance(park_id, str) and isinstance(days, dict)
        for day, entry in days.items():
            dt.date.fromisoformat(day)
            assert isinstance(entry, dict)
            if "level" in entry:
                assert isinstance(entry["level"], int) and 1 <= entry["level"] <= 10
            for key in ("open", "close"):
                if key in entry:
                    assert isinstance(entry[key], str) and len(entry[key]) == 5 and entry[key][2] == ":"
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="public/affluence.json")
    parser.add_argument("--previous", default=None, help="fichier publié précédemment (conservé en cas d'erreur)")
    args = parser.parse_args()

    names = [n.strip() for n in os.environ.get("ADAPTERS", "calendar,themeparks_wiki").split(",") if n.strip()]
    today = dt.datetime.now(dt.timezone.utc).date()
    data = {}
    sources = []
    for name in names:
        adapter = ADAPTERS.get(name)
        if not adapter:
            print(f"Adaptateur inconnu : {name}", file=sys.stderr)
            continue
        try:
            print(f"Adaptateur {name}…")
            sources.append(adapter(data, today))
        except Exception as exc:  # une source en panne ne bloque pas les autres
            print(f"  ! échec de {name} : {exc}", file=sys.stderr)

    doc = {
        "updatedAt": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "source": " + ".join(sources) if sources else "Aucune source (saisie manuelle)",
        "parks": data,
    }

    try:
        validate(doc)
        payload = json.dumps(doc, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        json.loads(payload)
    except Exception as exc:
        print(f"Fichier généré invalide ({exc}) : on garde le précédent.", file=sys.stderr)
        keep_previous(args)
        return 0

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    tmp = args.out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(payload)
    os.replace(tmp, args.out)
    total = sum(len(v) for v in data.values())
    print(f"OK : {args.out} ({total} jours, source : {doc['source']})")
    return 0


def keep_previous(args):
    if args.previous and os.path.exists(args.previous) and os.path.abspath(args.previous) != os.path.abspath(args.out):
        with open(args.previous, encoding="utf-8") as src, open(args.out, "w", encoding="utf-8") as dst:
            dst.write(src.read())


if __name__ == "__main__":
    sys.exit(main())
