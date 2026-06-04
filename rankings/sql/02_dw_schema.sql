/* ============================================================
   02_dw_schema.sql
   Couche DW — schéma en étoile pour le sujet "classements ATP".
   Grain du fait : 1 ligne = 1 joueur à 1 date de classement.
   A exécuter après le chargement du staging par Python.
   ============================================================ */

USE TennisDW;
GO

IF SCHEMA_ID('dw') IS NULL
    EXEC('CREATE SCHEMA dw');
GO

/* -------- DIMENSION JOUEUR (conforme) --------------------- */
IF OBJECT_ID('dw.DimPlayer', 'U') IS NOT NULL DROP TABLE dw.DimPlayer;
GO
CREATE TABLE dw.DimPlayer (
    player_key    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,  -- clé de substitution
    player_id     INT           NULL,    -- clé naturelle (depuis le CSV)
    first_name    NVARCHAR(100) NULL,
    last_name     NVARCHAR(100) NULL,
    full_name     NVARCHAR(205) NULL,
    hand          CHAR(1)       NULL,
    birth_date    DATE          NULL,
    country_code  CHAR(3)       NULL
);
GO

/* -------- DIMENSION DATE (conforme) ----------------------- */
IF OBJECT_ID('dw.DimDate', 'U') IS NOT NULL DROP TABLE dw.DimDate;
GO
CREATE TABLE dw.DimDate (
    date_key     INT      NOT NULL PRIMARY KEY,   -- format AAAAMMJJ (ex. 20170102)
    full_date    DATE     NOT NULL,
    [year]       SMALLINT NOT NULL,
    [quarter]    TINYINT  NOT NULL,
    [month]      TINYINT  NOT NULL,
    month_name   NVARCHAR(20) NOT NULL,
    [day]        TINYINT  NOT NULL,
    day_of_week  TINYINT  NOT NULL,
    week_of_year TINYINT  NOT NULL
);
GO

/* -------- FAIT CLASSEMENT ---------------------------------- */
IF OBJECT_ID('dw.FactRanking', 'U') IS NOT NULL DROP TABLE dw.FactRanking;
GO
CREATE TABLE dw.FactRanking (
    ranking_date_key INT NOT NULL,
    player_key       INT NOT NULL,
    ranking_position INT NULL,    -- mesure : position au classement
    ranking_points   INT NULL,    -- mesure : points
    CONSTRAINT FK_FactRanking_Date
        FOREIGN KEY (ranking_date_key) REFERENCES dw.DimDate(date_key),
    CONSTRAINT FK_FactRanking_Player
        FOREIGN KEY (player_key)       REFERENCES dw.DimPlayer(player_key)
);
GO

PRINT 'Schéma DW (étoile) créé.';
