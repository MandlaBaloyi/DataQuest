# DBE EMIS - Schools Masterlist / Identity Data

## ✅ What's actually in this folder (downloaded 2026-09-16)

### `WesternCape_Public_Ordinary_Schools_2025.csv` — 1,480 schools
Pulled live from the Western Cape Government's public GIS feature service (no login needed):
- **Source:** WCG Open Data Portal — "Western Cape Education Department: Public Ordinary Schools"
- **Live API used:** `https://utility.arcgis.com/usrsvcs/servers/f8e1d4c9005743c78fe85757fbdda236/rest/services/OpenDataPortal/Open_Spatial_Data_Map/MapServer/53/query`
- **Portal page:** https://wcg-opendataportal-westerncapegov.hub.arcgis.com/datasets/f8e1d4c9005743c78fe85757fbdda236
- **License:** CC BY (open, attribution only)
- **Updated:** WCED refreshes this weekly via an automated script, so this is genuinely current data, not a static old export.

**Columns:** EMIS, NAME, SCHOOLTYPE (Primary/Secondary), EDUCATIONDISTRICT, CIRCUIT, SECTOR, CONTROL (Public), QUINTILES (NQ1-NQ5), NOFEESCHOOL (Y/N), MEDIUMOFINSTRUCTION, SCHOOL_STATUS (Open/Pending Closed), LATITUDE, LONGITUDE

This single file actually already covers most of what Section 3(a) and 3(b) of the plan asked for, for the Western Cape: EMIS number (join key), quintile, no-fee flag, district, and even GPS coordinates — all in one clean CSV, no PDF-scraping needed.

### `WesternCape_Independent_Ordinary_Schools_2025.csv` — 343 schools
Same source/service, sibling layer for private/independent schools (item id `0b3a754215244c1193bb38df947f9094`, layer 56). Useful if you want to include independent schools in the model, or at least know they exist so you don't miscount total enrollment per district.

## ⚠️ What's still missing (needs manual step)

**National EMIS Schools Masterlist (all 9 provinces)** is NOT freely downloadable as a file — DBE's own EMIS Downloads page (education.gov.za/Programmes/EMIS/EMISDownloads.aspx) only hosts **ECD (Early Childhood Development) centre** data now, not the ordinary-schools masterlist.

The real national masterlist lives on DataFirst and is gated behind a **free account**:
- https://www.datafirst.uct.ac.za/dataportal/index.php/catalog/985 (Master List of Schools 2023)
- Listed as "public access" / CC-BY license, but you must register/log in to click through to the actual file.

**Action needed from you:** create a free DataFirst account (2 minutes, just an email) and download the 2023 masterlist from that link, then drop it in this folder. I can't create the account on your behalf.

## Why this matters for the model
EMIS number is the join key across every other dataset (No Fee Schools list, SNAP, NSC results). The Western Cape CSV here already gives you that key for ~1,823 schools (1,480 public + 343 independent) — enough to build and test the full Western-Cape pilot pipeline described in Section 4 of the plan without waiting on the national file.
