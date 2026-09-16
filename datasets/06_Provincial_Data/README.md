# Provincial Open Data Portals & Research

## ✅ What's actually in this folder (downloaded 2026-09-16)

### `SA_Education_District_Boundaries_Attributes.csv` (86 rows — NATIONAL, all 9 provinces)
Pulled live, no login required, from a public ArcGIS feature service:
- **Source:** "South African Education District Boundaries" — hosted feature service
- **Live API used:** `https://services7.arcgis.com/jbdCPRrwkIrZb0KZ/arcgis/rest/services/RSA_Education_Districts/FeatureServer/0/query`

**Columns:** FID, PROVINCE (2-letter code, e.g. WC/EC/FS/GP), EIDISTRICT (district name), DMUNCODE, DMUNNAME (district municipality), EID_DMUN, Comments, Area_sq_km, Category, Shape__Area, Shape__Length

**Note:** this file has attribute data only (province + district names, no geometry/shapes) — good enough to know which districts exist and which province they belong to, and to join district-level stats. If you need the actual map polygons for choropleth mapping in Flourish, tell me — I can re-pull with `f=geojson` to get the shapes too.

## ⚠️ Not yet downloaded (identified, real, and pullable)

I found these live, public, no-login-needed layers on the Western Cape Government's ArcGIS Open Data Portal but haven't pulled them yet — say the word and I will:

| Dataset | What it gives | Item ID |
|---|---|---|
| Education District Offices (WC) | Physical addresses/locations of WCED district offices | `western-cape-education-department-education-district-offices` |
| WCED Facilities App | Combined layer of all WCED facility types | `d56da2fa4bfb40c09854336d3fc103e7` |
| WCG Socio-Economic Dashboard: Education Barometer | Pre-built province indicators dashboard (may include repeater/dropout-adjacent stats) | `b4f7a2940cbe43a09ef0a487a98a4eac` — https://wcg-opendataportal-westerncapegov.hub.arcgis.com/items/b4f7a2940cbe43a09ef0a487a98a4eac |

The **Education Barometer** dashboard link is worth checking manually in a browser — it may already have pre-computed indicators relevant to dropout risk (repetition, retention) that could save modeling work or serve as a validation benchmark.

## DG Murray Trust / Zero Dropout Campaign Research — not yet downloaded
- dgmt.co.za and zerodropout.co.za publish the ~40% national dropout figure and Early Warning System case studies referenced in Section 1 of the plan.
- These are research reports/articles, not structured datasets — no bulk "download" exists. If useful, I can search their sites for the specific reports that contain the source statistics and save direct PDF links here.

## Recommendation
Western Cape remains the right pilot province: between this folder and `01_DBE_EMIS/`, you now have real, current, structured (not PDF) data covering school identity, quintile, no-fee status, geography, and district boundaries for the entire province — enough to start Step 1-3 of the pipeline (Section 4 of the plan) while the DataFirst-gated datasets (SNAP, full NSC microdata) are being requested.
