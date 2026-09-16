# Early Warning System for School Dropout - Datasets Index

**Project Goal:** Predict school-level dropout rates for Grade 10-12 cohorts in South Africa to enable targeted intervention.

**Last updated:** 2026-09-16 — real files downloaded from live public sources (not placeholders).

---

## ✅ What's actually downloaded right now

| File | Location | Records | Source Type |
|---|---|---|---|
| `WesternCape_Public_Ordinary_Schools_2025.csv` | `01_DBE_EMIS/` | 1,480 schools | Live API (ArcGIS, WCG) |
| `WesternCape_Independent_Ordinary_Schools_2025.csv` | `01_DBE_EMIS/` | 343 schools | Live API (ArcGIS, WCG) |
| `WC_No_Fee_Schools_2023.pdf` | `02_No_Fee_Schools/` | ~province-wide | DBE PDF (needs table extraction) |
| `WC_No_Fee_Schools_2025.pdf` | `02_No_Fee_Schools/` | ~province-wide | DBE PDF (needs table extraction) |
| `NSC_School_Performance_Report_2024.pdf` | `04_NSC_Results/` | National, all schools | DBE PDF (needs table extraction) |
| `GHS_2024_Report.pdf` | `05_Stats_SA_GHS/` | National, by province | Stats SA official report |
| `SA_Education_District_Boundaries_Attributes.csv` | `06_Provincial_Data/` | 86 districts, all provinces | Live API (ArcGIS) |

**Total: 7 real files, ~19 MB, covering identity/quintile/geography for ~1,823 Western Cape schools plus national district structure, matric results, and provincial dropout-reason context.**

## ⚠️ What still needs YOU to act (registration-gated — I can't do this part)

All three of these are on **DataFirst** (UCT) and require a **free account** (just an email address, no cost):

1. **National EMIS Schools Masterlist** (all provinces) → https://www.datafirst.uct.ac.za/dataportal/index.php/catalog/985
2. **SNAP Survey** (teacher/learner staffing ratios) → https://www.datafirst.uct.ac.za/dataportal/index.php/catalog/689/study-description
3. **NSC microdata 2010-2016** (subject-level detail) → registered via DataFirst, linked from the NSC results page

Register once, and all three become accessible from the same account. Drop the downloaded files into the matching folder (`01_DBE_EMIS/`, `03_SNAP_Survey/`, `04_NSC_Results/`) when you have them.

---

## Folder-by-folder status

### 1. `01_DBE_EMIS/` — School identity & join key
**Status: Strong — real, current, live data for Western Cape.** 1,823 schools with EMIS number, quintile, no-fee flag, district, coordinates. National masterlist still needs DataFirst registration (see above).

### 2. `02_No_Fee_Schools/` — Funding quintile & yearly learner counts
**Status: Partial.** 2023 and 2025 PDFs downloaded directly from DBE (no login). Still PDFs — need table extraction to become usable CSV. Note: quintile/no-fee status is already available more easily via the CSV in `01_DBE_EMIS/`; these PDFs mainly add year-by-year learner headcounts for trend calculation.

### 3. `03_SNAP_Survey/` — Teacher-to-learner ratio
**Status: Blocked on registration.** Nothing downloaded — DataFirst explicitly licenses this dataset (not open). Free account + Data Access Agreement required.

### 4. `04_NSC_Results/` — Pass-rate trend
**Status: Partial.** 2024 School Performance Report downloaded directly from DBE (7.5MB, national, school-by-school, includes 3-year history per school). Still a PDF needing extraction. Earlier years (2017-2023) and full microdata (2010-2016) not yet retrieved.

### 5. `05_Stats_SA_GHS/` — Why learners leave (context, by province)
**Status: Good enough for stated use.** 2024 official report downloaded directly (no login) — has the province-level attendance-reason tables the plan calls for. Raw microdata exists but requires registration and likely isn't needed unless custom cross-tabs are wanted.

### 6. `06_Provincial_Data/` — Geography & research benchmarks
**Status: Partial.** National education district boundaries downloaded (86 districts, all provinces, live API). Several more WC-specific layers identified and ready to pull on request. DG Murray Trust / Zero Dropout Campaign research not yet retrieved (these are reports, not datasets — no bulk download exists).

---

## Data Join Strategy

All Western-Cape-specific datasets link via **EMIS number**:

```
No Fee Schools PDF (learner counts by year)
     ↓
   [EMIS]  ← WesternCape_Public_Ordinary_Schools_2025.csv (school identity, quintile, location)
     ↓
SNAP Survey (educator counts) — pending registration
     ↓
NSC Results PDF (pass rates) — needs extraction
```

**Result:** One table, one row per school per year, with all features combined.

---

## Recommended Next Steps (in order)

1. **You:** Register a free DataFirst account and download the 3 gated files listed above.
2. **Me (on request):** Extract the tables from the 3 PDFs already downloaded (No Fee Schools x2, NSC Report) into clean CSVs — I can do this now if you want.
3. **Me (on request):** Pull the remaining WC ArcGIS layers listed in `06_Provincial_Data/README.md` (district offices, facilities app, education barometer dashboard).
4. **Together:** Once EMIS-keyed tables exist for identity + quintile + staffing + pass-rate, join them into the single per-school-per-year table described in Section 4, Step 2 of the plan.

---

## Important Notes (confirmed during this download session)

- **DBE's EMIS Downloads page no longer hosts an ordinary-schools masterlist** — only ECD (early childhood) centre data. This contradicts the earlier assumption in the plan; the real masterlist source is DataFirst (gated) or the WCG live API (open, WC-only) used here.
- **The WCG ArcGIS layer is actually MORE current and more structured than the No Fee Schools PDF** for identity/quintile purposes — it's updated weekly and already machine-readable.
- **PDFs (No Fee Schools, NSC Report) are real DBE-published documents**, not fabricated — but they need table-extraction work before they're model-ready.
