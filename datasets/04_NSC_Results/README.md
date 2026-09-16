# National Senior Certificate (NSC) Examination Results by School

## ✅ What's actually in this folder (downloaded 2026-09-16)

### `NSC_School_Performance_Report_2024.pdf` (7.5 MB)
Downloaded directly, no login required:
- **Source:** https://www.education.gov.za/Portals/0/Documents/Reports/2024/2024%20NSC%20School%20Performance%20Report.pdf
- **Published by:** Department of Basic Education, alongside the official 2024 matric results release

**Contents:** pass rate and performance data for every public, special-needs, and independent school that wrote the 2024 NSC exam, including a **3-year performance history per school** (so it already gives you a mini pass-rate trend without needing separate files per year). This is a large, genuinely school-by-school national table — 7.5 MB reflects real per-school row data, not a summary.

This is a PDF, not a clean CSV — the tables need extraction (same approach as the No Fee Schools PDFs; see `02_No_Fee_Schools/README.md` for extraction options).

## ⚠️ Still missing / needs manual step

**Microdata (2010-2016), with more granular subject-level data:** hosted on DataFirst, requires the same free account/Data Access Agreement as the SNAP Survey (`03_SNAP_Survey/`). Not downloaded — registration required.

**2017-2023 School Performance Reports:** DBE publishes one of these every January for the previous year's matric results. Only the 2024 report was pulled so far. If you want prior years for a proper multi-year pass-rate trend, tell me and I'll search DBE's reports archive for each year's direct PDF link (the URL pattern is `education.gov.za/Portals/0/Documents/Reports/{year}/{year} NSC School Performance Report.pdf` — I'll verify each year individually since DBE's site structure isn't fully consistent year to year).

## Why we need it
Per Section 3(d) of the plan: pass-rate **trend** per school is a core model feature, and it's also how we'd eventually validate whether predicted dropout-risk schools show real subsequent outcomes.
