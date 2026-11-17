-- =====================================================================
-- TrackList – MySQL adatbázisséma (MySQL 8.0+ / 8.4 LTS)
-- Zenei adatok forrása: MusicBrainz API + Cover Art Archive
-- Az MB-ből érkező rekordokat az MBID (36 karakteres UUID) azonosítja,
-- a saját táblák belső INT kulcsokat használnak.
-- =====================================================================

DROP DATABASE IF EXISTS tracklist;
CREATE DATABASE tracklist
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE tracklist;

-- ---------------------------------------------------------------------
-- 1. Felhasználók
-- ---------------------------------------------------------------------
CREATE TABLE felhasznalok (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  felhasznalonev  VARCHAR(30)  NOT NULL,
  email           VARCHAR(255) NOT NULL,
  jelszo_hash     VARCHAR(255) NOT NULL,           -- pl. BCrypt / ASP.NET PasswordHasher kimenete
  bemutatkozas    VARCHAR(500) NULL,
  profilkep_url   VARCHAR(500) NULL,
  szerepkor       ENUM('felhasznalo','moderator','admin') NOT NULL DEFAULT 'felhasznalo',
  tiltva_eddig    DATETIME     NULL,               -- NULL = nincs tiltva
  letrehozva      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  utolso_belepes  DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_felhasznalok_nev   (felhasznalonev),
  UNIQUE KEY uq_felhasznalok_email (email)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. MusicBrainz gyorsítótár (cache)
-- ---------------------------------------------------------------------

-- MB "artist"
CREATE TABLE eloadok (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  mbid            CHAR(36) CHARACTER SET ascii NOT NULL,
  nev             VARCHAR(255) NOT NULL,
  rendezesi_nev   VARCHAR(255) NULL,               -- MB "sort-name", pl. "Beatles, The"
  tipus           VARCHAR(30)  NULL,               -- MB "type": Person, Group, Orchestra, ...
  orszag          CHAR(2)      NULL,               -- MB "country" (ISO 3166-1)
  egyertelmusito  VARCHAR(255) NULL,               -- MB "disambiguation"
  leiras          TEXT         NULL,               -- saját, admin által szerkeszthető bemutatkozás
  mb_frissitve    DATETIME     NULL,               -- mikor töltöttük le utoljára az MB-ből
  PRIMARY KEY (id),
  UNIQUE KEY uq_eloadok_mbid (mbid),
  KEY idx_eloadok_nev (nev)
) ENGINE=InnoDB;

-- MB "release group" = az "album" mint mű (minden kiadása egy csoportban)
CREATE TABLE albumok (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  mbid              CHAR(36) CHARACTER SET ascii NOT NULL,   -- release group MBID
  cim               VARCHAR(500) NOT NULL,
  eloado_szoveg     VARCHAR(500) NOT NULL,                   -- kiírt előadó-kredit, pl. "Simon & Garfunkel"
  tipus             ENUM('album','single','ep','broadcast','other') NULL,  -- MB "primary-type"
  elso_megjelenes   VARCHAR(10)  NULL,                       -- MB "first-release-date": "2012", "2012-05" vagy "2012-05-22"
  megjelenes_eve    SMALLINT UNSIGNED NULL,                  -- szűréshez/rendezéshez kiemelve
  kiadas_mbid       CHAR(36) CHARACTER SET ascii NULL,       -- az a "release", amelyből a tracklistát vettük
  borito_url        VARCHAR(500) NULL,                       -- pl. https://coverartarchive.org/release-group/{mbid}/front-500
  mb_frissitve      DATETIME     NULL,
  letrehozva        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_albumok_mbid (mbid),
  KEY idx_albumok_ev (megjelenes_eve),
  FULLTEXT KEY ft_albumok_cim (cim, eloado_szoveg)
) ENGINE=InnoDB;

-- MB "artist credit": egy albumnak több előadója is lehet, sorrenddel és összekötő szöveggel
CREATE TABLE album_eloadok (
  album_id     INT UNSIGNED NOT NULL,
  pozicio      TINYINT UNSIGNED NOT NULL,          -- 0, 1, 2 ... a kreditben
  eloado_id    INT UNSIGNED NOT NULL,
  kreditnev    VARCHAR(255) NOT NULL,              -- MB artist-credit "name" (eltérhet az előadó nevétől)
  osszekoto    VARCHAR(50)  NOT NULL DEFAULT '',   -- MB "joinphrase", pl. " & ", " feat. "
  PRIMARY KEY (album_id, pozicio),
  KEY idx_album_eloadok_eloado (eloado_id),
  CONSTRAINT fk_ae_album  FOREIGN KEY (album_id)  REFERENCES albumok(id) ON DELETE CASCADE,
  CONSTRAINT fk_ae_eloado FOREIGN KEY (eloado_id) REFERENCES eloadok(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Egy kiválasztott kiadás (release) tracklistája; MB "track" + hozzá tartozó "recording"
CREATE TABLE zeneszamok (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  album_id        INT UNSIGNED NOT NULL,
  recording_mbid  CHAR(36) CHARACTER SET ascii NOT NULL,   -- a felvétel MBID-ja (albumokon átívelő azonosító)
  lemez           TINYINT UNSIGNED NOT NULL DEFAULT 1,     -- MB "medium" position
  pozicio         SMALLINT UNSIGNED NOT NULL,              -- sorszám a lemezen
  cim             VARCHAR(500) NOT NULL,
  eloado_szoveg   VARCHAR(500) NULL,                       -- csak ha eltér az albumétól (pl. feat.)
  hossz_ms        INT UNSIGNED NULL,                       -- MB "length" ezredmásodpercben
  PRIMARY KEY (id),
  UNIQUE KEY uq_zeneszamok_hely (album_id, lemez, pozicio),
  KEY idx_zeneszamok_recording (recording_mbid),
  FULLTEXT KEY ft_zeneszamok_cim (cim),
  CONSTRAINT fk_zeneszamok_album FOREIGN KEY (album_id) REFERENCES albumok(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- MB genre (a hivatalos műfajlista; a szabad tageket nem tároljuk)
CREATE TABLE mufajok (
  id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  mbid  CHAR(36) CHARACTER SET ascii NULL,
  nev   VARCHAR(100) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mufajok_nev  (nev),
  UNIQUE KEY uq_mufajok_mbid (mbid)
) ENGINE=InnoDB;

CREATE TABLE album_mufajok (
  album_id   INT UNSIGNED NOT NULL,
  mufaj_id   INT UNSIGNED NOT NULL,
  szavazat   INT UNSIGNED NOT NULL DEFAULT 0,      -- MB "count": hány MB-szerkesztő adta meg
  PRIMARY KEY (album_id, mufaj_id),
  KEY idx_album_mufajok_mufaj (mufaj_id),
  CONSTRAINT fk_am_album FOREIGN KEY (album_id) REFERENCES albumok(id) ON DELETE CASCADE,
  CONSTRAINT fk_am_mufaj FOREIGN KEY (mufaj_id) REFERENCES mufajok(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Értékelések, listák, kedvencek
-- ---------------------------------------------------------------------

-- Albumértékelés + opcionális szöveges vélemény (felhasználónként albumonként egy)
CREATE TABLE ertekelesek (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  felhasznalo_id  INT UNSIGNED NOT NULL,
  album_id        INT UNSIGNED NOT NULL,
  pontszam        TINYINT UNSIGNED NOT NULL,       -- 1–5
  velemeny        TEXT NULL,                       -- NULL = csak pontszám
  rejtett         BOOLEAN NOT NULL DEFAULT FALSE,  -- moderátor elrejtette
  letrehozva      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modositva       DATETIME NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_ertekelesek_fa (felhasznalo_id, album_id),
  KEY idx_ertekelesek_album (album_id, letrehozva),
  CONSTRAINT ck_ertekelesek_pont CHECK (pontszam BETWEEN 1 AND 5),
  CONSTRAINT fk_ert_felh  FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE,
  CONSTRAINT fk_ert_album FOREIGN KEY (album_id)       REFERENCES albumok(id)      ON DELETE CASCADE
) ENGINE=InnoDB;

-- Zeneszámonkénti pontozás (szöveg nélkül)
CREATE TABLE zeneszam_ertekelesek (
  felhasznalo_id  INT UNSIGNED NOT NULL,
  zeneszam_id     INT UNSIGNED NOT NULL,
  pontszam        TINYINT UNSIGNED NOT NULL,
  letrehozva      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (felhasznalo_id, zeneszam_id),
  KEY idx_zert_zeneszam (zeneszam_id),
  CONSTRAINT ck_zert_pont CHECK (pontszam BETWEEN 1 AND 5),
  CONSTRAINT fk_zert_felh FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE,
  CONSTRAINT fk_zert_zsz  FOREIGN KEY (zeneszam_id)    REFERENCES zeneszamok(id)   ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE listak (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  felhasznalo_id  INT UNSIGNED NOT NULL,
  cim             VARCHAR(100) NOT NULL,
  leiras          TEXT NULL,
  publikus        BOOLEAN NOT NULL DEFAULT TRUE,
  rangsorolt      BOOLEAN NOT NULL DEFAULT FALSE,  -- számozott toplista-e
  letrehozva      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modositva       DATETIME NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_listak_felh (felhasznalo_id),
  CONSTRAINT fk_listak_felh FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE lista_elemek (
  lista_id    INT UNSIGNED NOT NULL,
  album_id    INT UNSIGNED NOT NULL,
  pozicio     SMALLINT UNSIGNED NOT NULL,
  megjegyzes  VARCHAR(500) NULL,
  hozzaadva   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (lista_id, album_id),               -- egy album egyszer szerepelhet egy listán
  KEY idx_lista_elemek_sorrend (lista_id, pozicio),
  KEY idx_lista_elemek_album (album_id),
  CONSTRAINT fk_le_lista FOREIGN KEY (lista_id) REFERENCES listak(id)  ON DELETE CASCADE,
  CONSTRAINT fk_le_album FOREIGN KEY (album_id) REFERENCES albumok(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Profil "Kedvenc albumok" blokkja
CREATE TABLE kedvenc_albumok (
  felhasznalo_id  INT UNSIGNED NOT NULL,
  album_id        INT UNSIGNED NOT NULL,
  pozicio         TINYINT UNSIGNED NOT NULL DEFAULT 0,
  hozzaadva       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (felhasznalo_id, album_id),
  KEY idx_kedvenc_album (album_id),
  CONSTRAINT fk_ked_felh  FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE,
  CONSTRAINT fk_ked_album FOREIGN KEY (album_id)       REFERENCES albumok(id)      ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. Közösség: követés, hírfolyam, hozzászólás, kedvelés
-- ---------------------------------------------------------------------

-- Felhasználó követ felhasználót (az önkövetést a backend tiltja, lásd megjegyzés a doksiban)
CREATE TABLE kovetesek (
  koveto_id    INT UNSIGNED NOT NULL,
  kovetett_id  INT UNSIGNED NOT NULL,
  letrehozva   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (koveto_id, kovetett_id),
  KEY idx_kovetesek_kovetett (kovetett_id),
  CONSTRAINT fk_kov_koveto   FOREIGN KEY (koveto_id)   REFERENCES felhasznalok(id) ON DELETE CASCADE,
  CONSTRAINT fk_kov_kovetett FOREIGN KEY (kovetett_id) REFERENCES felhasznalok(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Felhasználó követ előadót (előadó adatlap "Követés" gomb)
CREATE TABLE eloado_kovetesek (
  felhasznalo_id  INT UNSIGNED NOT NULL,
  eloado_id       INT UNSIGNED NOT NULL,
  letrehozva      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (felhasznalo_id, eloado_id),
  KEY idx_ekov_eloado (eloado_id),
  CONSTRAINT fk_ekov_felh   FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE,
  CONSTRAINT fk_ekov_eloado FOREIGN KEY (eloado_id)      REFERENCES eloadok(id)      ON DELETE CASCADE
) ENGINE=InnoDB;

-- Hírfolyam-bejegyzés. Lehet sima poszt, vagy egy értékelés / új lista megosztása.
CREATE TABLE bejegyzesek (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  felhasznalo_id  INT UNSIGNED NOT NULL,
  tipus           ENUM('poszt','ertekeles','lista') NOT NULL DEFAULT 'poszt',
  szoveg          TEXT NULL,
  album_id        INT UNSIGNED NULL,               -- poszthoz csatolt album (opcionális)
  ertekeles_id    INT UNSIGNED NULL,               -- tipus = 'ertekeles' esetén
  lista_id        INT UNSIGNED NULL,               -- tipus = 'lista' esetén
  rejtett         BOOLEAN NOT NULL DEFAULT FALSE,
  letrehozva      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_bejegyzesek_ido  (letrehozva),
  KEY idx_bejegyzesek_felh (felhasznalo_id, letrehozva),
  CONSTRAINT fk_bej_felh   FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE,
  CONSTRAINT fk_bej_album  FOREIGN KEY (album_id)       REFERENCES albumok(id)      ON DELETE SET NULL,
  CONSTRAINT fk_bej_ert    FOREIGN KEY (ertekeles_id)   REFERENCES ertekelesek(id)  ON DELETE CASCADE,
  CONSTRAINT fk_bej_lista  FOREIGN KEY (lista_id)       REFERENCES listak(id)       ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE hozzaszolasok (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  bejegyzes_id    INT UNSIGNED NOT NULL,
  felhasznalo_id  INT UNSIGNED NOT NULL,
  szoveg          VARCHAR(2000) NOT NULL,
  rejtett         BOOLEAN NOT NULL DEFAULT FALSE,
  letrehozva      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_hsz_bejegyzes (bejegyzes_id, letrehozva),
  KEY idx_hsz_felh (felhasznalo_id),
  CONSTRAINT fk_hsz_bej  FOREIGN KEY (bejegyzes_id)   REFERENCES bejegyzesek(id)  ON DELETE CASCADE,
  CONSTRAINT fk_hsz_felh FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE kedvelesek (
  felhasznalo_id  INT UNSIGNED NOT NULL,
  bejegyzes_id    INT UNSIGNED NOT NULL,
  letrehozva      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (felhasznalo_id, bejegyzes_id),
  KEY idx_kedv_bej (bejegyzes_id),
  CONSTRAINT fk_kedv_felh FOREIGN KEY (felhasznalo_id) REFERENCES felhasznalok(id) ON DELETE CASCADE,
  CONSTRAINT fk_kedv_bej  FOREIGN KEY (bejegyzes_id)   REFERENCES bejegyzesek(id)  ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. Moderáció (a WPF admin felület ezt kezeli)
-- ---------------------------------------------------------------------
-- Pontosan egy cél-oszlop van kitöltve a tipus szerint; ezt a backend ellenőrzi
-- (MySQL-ben CHECK nem tehető olyan oszlopra, amelyen ON DELETE művelet van).
CREATE TABLE bejelentesek (
  id                   INT UNSIGNED NOT NULL AUTO_INCREMENT,
  bejelento_id         INT UNSIGNED NULL,
  tipus                ENUM('ertekeles','bejegyzes','hozzaszolas','felhasznalo') NOT NULL,
  ertekeles_id         INT UNSIGNED NULL,
  bejegyzes_id         INT UNSIGNED NULL,
  hozzaszolas_id       INT UNSIGNED NULL,
  bejelentett_felh_id  INT UNSIGNED NULL,
  indok                VARCHAR(500) NOT NULL,
  allapot              ENUM('nyitott','elfogadva','elutasitva') NOT NULL DEFAULT 'nyitott',
  kezelo_id            INT UNSIGNED NULL,          -- az admin/moderátor, aki lezárta
  kezelve              DATETIME NULL,
  letrehozva           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_bejelentesek_allapot (allapot, letrehozva),
  CONSTRAINT fk_bjl_bejelento FOREIGN KEY (bejelento_id)        REFERENCES felhasznalok(id)  ON DELETE SET NULL,
  CONSTRAINT fk_bjl_ert       FOREIGN KEY (ertekeles_id)        REFERENCES ertekelesek(id)   ON DELETE CASCADE,
  CONSTRAINT fk_bjl_bej       FOREIGN KEY (bejegyzes_id)        REFERENCES bejegyzesek(id)   ON DELETE CASCADE,
  CONSTRAINT fk_bjl_hsz       FOREIGN KEY (hozzaszolas_id)      REFERENCES hozzaszolasok(id) ON DELETE CASCADE,
  CONSTRAINT fk_bjl_felh      FOREIGN KEY (bejelentett_felh_id) REFERENCES felhasznalok(id)  ON DELETE CASCADE,
  CONSTRAINT fk_bjl_kezelo    FOREIGN KEY (kezelo_id)           REFERENCES felhasznalok(id)  ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. Nézet: album statisztika (átlag, darabszám) – "Népszerű albumok", adatlap
-- ---------------------------------------------------------------------
CREATE VIEW album_statisztika AS
SELECT a.id                       AS album_id,
       COUNT(e.id)                AS ertekelesek_szama,
       ROUND(AVG(e.pontszam), 2)  AS atlag,
       SUM(e.velemeny IS NOT NULL) AS velemenyek_szama
FROM albumok a
LEFT JOIN ertekelesek e ON e.album_id = a.id AND e.rejtett = FALSE
GROUP BY a.id;
