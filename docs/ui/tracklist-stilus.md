# TrackList stílusútmutató

A webes felület (React + Bootstrap 5.3) vizuális szabályai.

## Alapelvek

- Semleges szürke alap, egyetlen kobaltkék akciószín (gombok, linkek) és egy borostyán szín, ami csak az értékeléseknél jelenik meg.
- A színt elsősorban az albumborítók adják, a felület nem versenyez velük.
- Minden szín CSS változóként (token) van megadva, és a Bootstrap `--bs-*` változói ezekre mutatnak. Így a színeket egy helyen lehet módosítani.
- Van világos és sötét téma is, ugyanazokkal a tokenekkel.

## Színek

| Token | Világos | Sötét | Mire |
|---|---|---|---|
| `--tl-bg` | `#F4F4F4` | `#121212` | oldal háttere |
| `--tl-surface` | `#FFFFFF` | `#1C1C1D` | kártyák, posztok, űrlapok |
| `--tl-sunken` | `#ECECEC` | `#262627` | beütött mezők, keresőmező, aktív menüpont |
| `--tl-ink` | `#18181A` | `#EDEDED` | szöveg |
| `--tl-muted` | `#626266` | `#A3A3A6` | másodlagos szöveg (dátum, előadó, darabszám) |
| `--tl-line` | `#DEDEDE` | `#323234` | vonalak, keretek |
| `--tl-primary` | `#2C3BB3` | `#8E9BFF` | elsődleges gomb, linkek |
| `--tl-primary-hover` | `#22308F` | `#AAB4FF` | gomb hover |
| `--tl-on-primary` | `#FFFFFF` | `#121212` | szöveg a kobalt gombon |
| `--tl-primary-soft` | `#E3E6FA` | `#2A2C3E` | műfaj címke háttere |
| `--tl-rate` | `#E8960F` | `#F4AE3A` | értékelés-mérő, eloszlás diagram |
| `--tl-rate-soft` | `#FCEFD6` | `#3A2D12` | pontszám címke háttere |
| `--tl-rate-ink` | `#7A4B00` | `#FFD58C` | pontszám címke szövege |
| `--tl-meter-off` | `#DADADA` | `#38383A` | a mérő üres szegmensei |
| `--tl-like` | `#D23F57` | `#FF6B82` | „Tetszik” bekapcsolva |

A háttér szándékosan semleges szürke, nem kékes.

## Betű

Egyetlen betűcsalád: **Instrument Sans** (Google Fonts, teljes magyar ékezetkészlet).

```html
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600;700&display=swap">
```

| Szerep | Beállítás |
|---|---|
| Oldalcím, logó (`.h-display`) | 700, betűköz `-0.025em`, sormagasság 1.05, méret `clamp(1.7rem, 3.4vw, 2.6rem)` |
| Szakaszcím (`.section-title`) | 700, `1.05rem` |
| Szöveg | 400, `0.95rem`, sormagasság 1.55 |
| Másodlagos szöveg (`.meta`) | 400, `0.86rem`, `--tl-muted` szín |
| Számok (pontszám, időtartam) | ugyanaz a betű, `font-variant-numeric: tabular-nums` |

## Formák és térközök

- Lekerekítés: kártyák `10px`, kisebb elemek és borítók `6px`, gombok teljesen kerekek (`999px`).
- Kártya (`.panel`): `--tl-surface` háttér, 1px `--tl-line` keret, árnyék nélkül. Csak ott használjuk, ahol a doboz egy egységet jelöl: poszt, hozzászólás űrlap, listakártya, belépés űrlap.
- Szakasz (`.sec`): doboz helyett csak egy 1px felső vonal és 14px felső térköz. Ilyen az oldalsáv, az album oldal Tracklista és Vélemények része, és a profil.
- Rács: Bootstrap grid. A főoldal asztali nézetben 3 oszlop (menü `col-lg-2`, hírfolyam `col-lg-7`, oldalsáv `col-lg-3`), mobilon egy oszlop alsó navigációs sorral.
- Oldalszélesség: legfeljebb `1240px`, oldalsó margó legalább 16px.

## Komponensek

| Komponens | Bootstrap osztály / saját osztály | Megjegyzés |
|---|---|---|
| Elsődleges gomb | `btn btn-primary` | „Értékelem”, „Posztolás”, „+ Új lista” |
| Másodlagos gomb | `btn btn-outline-secondary` | „Listámhoz adom”, „Megosztás” |
| Szöveges gomb | `btn btn-ghost` (saját) | „Tetszik”, „Hozzászólás”, „Mégse” |
| Szűrő gombsor | `btn-group` + `btn-check` + `btn-outline-secondary` | kiválasztva fekete háttér |
| Műfaj címke | `.genre` | kobalt szöveg halvány kobalt alapon |
| Pontszám címke | `.score` | pl. „4,2”, borostyán alapon |
| Értékelés-mérő | `.meter` | 10 szegmens, egy szegmens = 0,5 pont |
| Borító | `.cover` | négyzet, `aspect-ratio: 1/1`, kép a Cover Art Archive-ból |
| Legördülő menü | `dropdown` | „Listámhoz adom” |

### Értékelés

- Skála: 0,5 és 5 között, félpontos lépésekben (10 lehetséges érték).
- Tizedesvessző: `4,2`, nem `4.2`.
- Megjelenítés: pontszám címke vagy a 10 szegmenses mérő (a kitöltött szegmensek száma = pontszám × 2).
- Szöveges címkék az értékeléskor: 0,5 Hallgathatatlan, 1 Nagyon gyenge, 1,5 Gyenge, 2 Közepes alatt, 2,5 Közepes, 3 Rendben van, 3,5 Jó, 4 Nagyon jó, 4,5 Kiváló, 5 Mestermű.

## Szövegezés

- Mondatkezdő nagybetű mindenhol, csupa nagybetűs címkék nélkül.
- Meta-adatok vesszővel elválasztva: „Kék Óra, 2025”, nem „Kék Óra · 2025”.
- A gomb azt mondja, ami történik: „Értékelem”, „Lista létrehozása”, és a visszajelzés ugyanazt a szót használja („Értékelés mentve”).

## Amit kerülünk

Ezeket szándékosan vettük ki, mert sablonos, „AI-generált” hatást keltenek:

- csupa nagybetűs, ritkított kis címkék a címek fölött,
- monospace betű a számokhoz és címkékhez,
- pontokkal (·) elválasztott meta-szövegek,
- minden blokk egyforma lekerekített dobozban, egyforma árnyékkal,
- díszítő színátmenetek (háttér, avatar, fényes réteg a borítón),
- felugró hover animáció minden kártyán.