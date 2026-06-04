/* ============================================================
   03_staging_to_dw.sql
   Chargement Staging -> DW (dimensions puis fait).
   Idempotent : on vide le fait, on (ré)alimente les dimensions.
   ============================================================ */

USE TennisDW;
GO

/* ------------------------------------------------------------
   1) DIM PLAYER
   On déduplique sur la clé naturelle player_id. Le full_name
   gère les prénoms/noms manquants proprement.
   ------------------------------------------------------------ */
TRUNCATE TABLE dw.FactRanking;   -- on vide le fait avant de toucher aux dims (FK)
GO
DELETE FROM dw.DimPlayer;
DBCC CHECKIDENT ('dw.DimPlayer', RESEED, 0);   -- repart de player_key = 1
GO

-- Membre "Inconnu" (-1) pour les joueurs présents dans rankings mais absents de players
SET IDENTITY_INSERT dw.DimPlayer ON;
INSERT INTO dw.DimPlayer (player_key, player_id, first_name, last_name, full_name, hand, birth_date, country_code)
VALUES (-1, NULL, N'Unknown', N'Player', N'Unknown Player', 'U', NULL, NULL);
SET IDENTITY_INSERT dw.DimPlayer OFF;
GO

INSERT INTO dw.DimPlayer (player_id, first_name, last_name, full_name, hand, birth_date, country_code)
SELECT
    p.player_id,
    p.first_name,
    p.last_name,
    LTRIM(RTRIM(
        CONCAT(ISNULL(p.first_name, N''), N' ', ISNULL(p.last_name, N''))
    )),
    p.hand,
    p.birth_date,
    p.country_code
FROM (
    -- déduplication : une seule ligne par player_id
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY player_id) AS rn
    FROM staging.stg_players
    WHERE player_id IS NOT NULL
) p
WHERE p.rn = 1;
GO

/* ------------------------------------------------------------
   2) DIM DATE
   Générée à partir de la plage de dates réellement présente
   dans les classements (tally table via cross join système).
   ------------------------------------------------------------ */
DELETE FROM dw.DimDate;
GO

DECLARE @min DATE = (SELECT MIN(ranking_date) FROM staging.stg_rankings);
DECLARE @max DATE = (SELECT MAX(ranking_date) FROM staging.stg_rankings);

;WITH n AS (   -- table de nombres 0..N (suffisant pour ~16 000 jours)
    SELECT TOP (DATEDIFF(DAY, @min, @max) + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS num
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
dates AS (
    SELECT DATEADD(DAY, num, @min) AS d FROM n
)
INSERT INTO dw.DimDate (date_key, full_date, [year], [quarter], [month],
                        month_name, [day], day_of_week, week_of_year)
SELECT
    CONVERT(INT, FORMAT(d, 'yyyyMMdd')),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    MONTH(d),
    DATENAME(MONTH, d),
    DAY(d),
    DATEPART(WEEKDAY, d),
    DATEPART(WEEK, d)
FROM dates;
GO

/* ------------------------------------------------------------
   3) FACT RANKING
   Jointure sur les clés naturelles -> clés de substitution.
   ISNULL(player_key, -1) : rattache au membre Inconnu si besoin.
   ------------------------------------------------------------ */
INSERT INTO dw.FactRanking (ranking_date_key, player_key, ranking_position, ranking_points)
SELECT
    dd.date_key,
    ISNULL(dp.player_key, -1),
    r.ranking,
    r.ranking_points
FROM staging.stg_rankings r
INNER JOIN dw.DimDate   dd ON dd.full_date  = r.ranking_date
LEFT  JOIN dw.DimPlayer dp ON dp.player_id  = r.player_id;
GO

/* ------------------------------------------------------------
   4) Contrôles rapides
   ------------------------------------------------------------ */
PRINT '--- Contrôles ---';
SELECT 'DimPlayer'   AS objet, COUNT(*) AS lignes FROM dw.DimPlayer
UNION ALL SELECT 'DimDate',    COUNT(*) FROM dw.DimDate
UNION ALL SELECT 'FactRanking',COUNT(*) FROM dw.FactRanking;

-- Faits rattachés au joueur Inconnu (devrait être ~0)
SELECT COUNT(*) AS faits_joueur_inconnu
FROM dw.FactRanking WHERE player_key = -1;
GO
