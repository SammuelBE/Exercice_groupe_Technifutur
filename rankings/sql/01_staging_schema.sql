/* ============================================================
   01_staging_schema.sql
   Couche STAGING — reflet propre des CSV rankings/players.
   A exécuter UNE FOIS pour créer la base et les tables.
   Le chargement des données se fait ensuite via Python.
   ============================================================ */

-- 1) Base (à adapter / commenter si la base existe déjà côté groupe)
IF DB_ID('TennisDW') IS NULL
    CREATE DATABASE TennisDW;
GO

USE TennisDW;
GO

-- 2) Schéma dédié
IF SCHEMA_ID('staging') IS NULL
    EXEC('CREATE SCHEMA staging');
GO

-- 3) Table staging des joueurs
IF OBJECT_ID('staging.stg_players', 'U') IS NOT NULL
    DROP TABLE staging.stg_players;
GO
CREATE TABLE staging.stg_players (
    player_id     INT            NULL,   -- clé naturelle
    first_name    NVARCHAR(100)  NULL,
    last_name     NVARCHAR(100)  NULL,
    hand          CHAR(1)        NULL,   -- R / L / U / A (vide normalisé en U par Python)
    birth_date    DATE           NULL,   -- NULL si manquante ou mal formée
    country_code  CHAR(3)        NULL,
    source_file   NVARCHAR(100)  NULL,   -- traçabilité
    load_dt       DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- 4) Table staging des classements
IF OBJECT_ID('staging.stg_rankings', 'U') IS NOT NULL
    DROP TABLE staging.stg_rankings;
GO
CREATE TABLE staging.stg_rankings (
    ranking_date    DATE          NOT NULL,
    ranking         INT           NULL,   -- position au classement
    player_id       INT           NOT NULL,  -- les lignes sans player_id sont rejetées par Python
    ranking_points  INT           NULL,   -- NULL si vide à la source
    source_file     NVARCHAR(100) NULL,
    load_dt         DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Index utiles pour la phase Staging -> DW (jointures)
CREATE INDEX IX_stg_rankings_player ON staging.stg_rankings(player_id);
CREATE INDEX IX_stg_rankings_date   ON staging.stg_rankings(ranking_date);
GO

PRINT 'Schéma staging créé.';
