# SNAP Survey of Ordinary Schools

## ⚠️ Nothing downloaded here — this one requires a manual step from you

I checked directly: the SNAP Survey (1997-2016, v1.6) on DataFirst is explicitly marked as a **"Licensed dataset, accessible under conditions"** — not open-download like the schools masterlist. There is no public API or direct file link I can pull from automatically.

- **Dataset page:** https://www.datafirst.uct.ac.za/dataportal/index.php/catalog/689/study-description
- **2023 version also exists:** https://www.datafirst.uct.ac.za/dataportal/index.php/catalog/study/zaf-dbe-snaps-2023-v1
- **DOI:** https://doi.org/10.25828/2e3e-9x02

## What you need to do
1. Create a free DataFirst account (same one as for the EMIS masterlist in `01_DBE_EMIS/`)
2. Open the dataset page above, click "Get Microdata"
3. Accept DataFirst's Data Access Agreement (standard academic/research terms — no cost, just requires stating your intended use)
4. Download the Stata (.dta) or equivalent file and place it in this folder

## What it contains (per DataFirst's own documentation)
- Learner and educator numbers per school, per year
- Staff category (educators, support staff, admin staff)
- Full-time/part-time status, gender
- Originally an Access Database, converted to Stata format in v1.1

## Why we need it
This is the only confirmed source for calculating **teacher-to-learner ratio** per school per year — one of the model's core features per Section 3(c) of the plan.

## Known limitation (confirmed, not assumed)
Public/registered access only clearly covers **1997-2016**. A 2023 version exists on DataFirst (see link above) but access conditions for it weren't verified — check when you register. If recent years aren't available even with an account, the fallback is contacting DBE's EMIS directorate or DataFirst support directly to ask about 2017-2025 coverage.
