# Stats SA - General Household Survey (GHS)

## ✅ What's actually in this folder (downloaded 2026-09-16)

### `GHS_2024_Report.pdf` (4.1 MB)
Downloaded directly, no login required:
- **Source:** https://www.statssa.gov.za/publications/P0318/P03182024.pdf
- **Published by:** Statistics South Africa (official statistical release, report code P0318)

**Contents:** the full published GHS 2024 results, including the education section — school attendance rates and **reasons for not attending** (no money, illness, pregnancy, distance, etc.), broken down by province. This is Stats SA's own analysis/tables, not raw respondent-level microdata — but the province-level attendance-reason breakdowns the plan needs (Section 3(e)) are in here.

## ⚠️ Still missing / needs manual step

**Raw microdata** (household-level, anonymized individual records) is NOT in this PDF — it's a separate download gated behind registration:
- Stats SA's own portal: https://isibaloweb.statssa.gov.za/pages/surveys/pss/ghs/2022/ghs2022.php
- Also on DataFirst: https://www.datafirst.uct.ac.za/dataportal/index.php/catalog/961 (2023 version) — same free-account process as the EMIS masterlist and SNAP survey
- Also on World Bank Microdata Library: https://microdata.worldbank.org/index.php/catalog/6792 (2024 version)

**Only get the microdata if you need it.** For this project's stated use (province-level context on WHY learners leave, to explain model results — not as a direct model input), the published PDF tables already downloaded here are likely sufficient. Raw microdata would only be needed if you wanted to build your own custom cross-tabulations beyond what Stats SA already publishes.

## Why we need it
Per Section 3(e) of the plan: this is the only source that explains WHY learners leave (financial, health, distance, etc.) at a province level — used to explain model results and to help decision-makers pick the right kind of intervention for a region, not as a direct predictive feature.
