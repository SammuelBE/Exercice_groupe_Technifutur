"""
etl_rankings_staging.py
-----------------------
ETL : fichiers CSV ATP (players + rankings)  ->  base de Staging (SQL Server).

Périmètre : partie "atp_rankings" du projet collaboratif.
  - players  : dimension joueur (clé naturelle référencée par les rankings)
  - rankings : 6 fichiers décennaux -> une seule table de staging

Le nettoyage fait ICI (en Python) reste léger : on caste les types, on neutralise
les valeurs manquantes/mal formées, on rejette les lignes inexploitables.
La modélisation dimensionnelle (Dim/Fact) est faite ensuite EN SQL.

Pré-requis :
    pip install pyodbc
    + ODBC Driver 17 (ou 18) for SQL Server installé.
Lancer d'abord 01_staging_schema.sql pour créer la base et les tables.
"""

import csv
import glob
import os
from datetime import datetime

import pyodbc

# --------------------------------------------------------------------------
# CONFIGURATION  (à adapter à ton instance — ex. r"GEORGES\DATA")
# --------------------------------------------------------------------------
SERVER   = r"localhost\SQLEXPRESS"   # <-- mets ton instance ici
DATABASE = "TennisDW"
DRIVER   = "{ODBC Driver 17 for SQL Server}"
# Authentification Windows (Trusted_Connection) — sinon ajoute UID/PWD.
CONN_STR = (
    f"DRIVER={DRIVER};SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;"
)

# Dossier contenant les CSV (adapte au clone du repo)
DATA_DIR = "."

BATCH_SIZE = 20_000   # insertion par lots


# --------------------------------------------------------------------------
# HELPERS de nettoyage
# --------------------------------------------------------------------------
def clean_text(value):
    """Renvoie None si vide, sinon le texte trimé."""
    v = (value or "").strip()
    return v or None


def parse_date_yyyymmdd(value):
    """'19880101' -> date ; None si vide ou invalide (au lieu de planter)."""
    v = (value or "").strip()
    if len(v) != 8 or not v.isdigit():
        return None
    try:
        return datetime.strptime(v, "%Y%m%d").date()
    except ValueError:
        return None  # ex. 19880230 (date impossible)


def parse_int(value):
    """Cast int ; None si vide ou non numérique."""
    v = (value or "").strip()
    if not v:
        return None
    try:
        return int(v)
    except ValueError:
        return None


def normalize_hand(value):
    """Main du joueur : vide -> 'U' (Unknown). Garde R/L/U/A."""
    v = (value or "").strip().upper()
    return v if v in ("R", "L", "A") else "U"


# --------------------------------------------------------------------------
# EXTRACT + TRANSFORM
# --------------------------------------------------------------------------
def read_players(path):
    """Génère des tuples prêts pour stg_players. Aucune ligne rejetée :
    les champs manquants deviennent NULL."""
    src = os.path.basename(path)
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        for row in csv.reader(f):
            if len(row) < 6:
                continue  # ligne tronquée illisible -> on saute
            player_id, first_name, last_name, hand, birth_date, country = row[:6]
            yield (
                parse_int(player_id),
                clean_text(first_name),
                clean_text(last_name),
                normalize_hand(hand),
                parse_date_yyyymmdd(birth_date),
                clean_text(country),
                src,
            )


def read_rankings(paths):
    """Génère des tuples prêts pour stg_rankings.
    Rejette les lignes sans date ou sans player_id (inexploitables côté fait)."""
    rejected = 0
    for path in paths:
        src = os.path.basename(path)
        with open(path, newline="", encoding="utf-8", errors="replace") as f:
            for row in csv.reader(f):
                if len(row) < 4:
                    rejected += 1
                    continue
                ranking_date = parse_date_yyyymmdd(row[0])
                player_id = parse_int(row[2])
                if ranking_date is None or player_id is None:
                    rejected += 1   # ex. la ligne "20160613,1709,,2"
                    continue
                yield (
                    ranking_date,
                    parse_int(row[1]),       # position (NULL si absente)
                    player_id,
                    parse_int(row[3]),       # points (NULL si vides)
                    src,
                )
    print(f"  -> lignes rankings rejetées (date/player_id manquant) : {rejected}")


# --------------------------------------------------------------------------
# LOAD
# --------------------------------------------------------------------------
def bulk_insert(cursor, sql, rows, batch_size=BATCH_SIZE):
    """Insertion par lots avec fast_executemany (indispensable pour 2,6M lignes)."""
    cursor.fast_executemany = True
    batch, total = [], 0
    for r in rows:
        batch.append(r)
        if len(batch) >= batch_size:
            cursor.executemany(sql, batch)
            total += len(batch)
            batch.clear()
            print(f"    {total:,} lignes insérées...", end="\r")
    if batch:
        cursor.executemany(sql, batch)
        total += len(batch)
    print(f"    {total:,} lignes insérées au total.        ")
    return total


def main():
    players_path = os.path.join(DATA_DIR, "atp_players.csv")
    ranking_paths = sorted(glob.glob(os.path.join(DATA_DIR, "atp_rankings_*.csv")))

    if not os.path.exists(players_path):
        raise FileNotFoundError(f"Introuvable : {players_path}")
    if not ranking_paths:
        raise FileNotFoundError("Aucun fichier atp_rankings_*.csv trouvé.")

    print("Connexion à SQL Server...")
    with pyodbc.connect(CONN_STR, autocommit=False) as conn:
        cur = conn.cursor()

        # --- PLAYERS ---
        print("\n[1/2] Chargement staging.stg_players")
        cur.execute("TRUNCATE TABLE staging.stg_players;")
        sql_players = (
            "INSERT INTO staging.stg_players "
            "(player_id, first_name, last_name, hand, birth_date, country_code, source_file) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)"
        )
        bulk_insert(cur, sql_players, read_players(players_path))
        conn.commit()

        # --- RANKINGS ---
        print(f"\n[2/2] Chargement staging.stg_rankings ({len(ranking_paths)} fichiers)")
        for p in ranking_paths:
            print(f"  - {os.path.basename(p)}")
        cur.execute("TRUNCATE TABLE staging.stg_rankings;")
        sql_rankings = (
            "INSERT INTO staging.stg_rankings "
            "(ranking_date, ranking, player_id, ranking_points, source_file) "
            "VALUES (?, ?, ?, ?, ?)"
        )
        bulk_insert(cur, sql_rankings, read_rankings(ranking_paths))
        conn.commit()

    print("\nETL Staging terminé. Tu peux lancer 02_dw_schema.sql puis 03_staging_to_dw.sql.")


if __name__ == "__main__":
    main()