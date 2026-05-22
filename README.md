# DataQuest 2026 — Credit Risk Modelling
## SAS Code README

---

## Overview

This SAS project builds, evaluates, and selects a logistic regression model to predict the probability of loan default. It covers four stages:

1. **Data Preparation** — splitting data and checking for missing values and multicollinearity
2. **Model Training** — training four candidate logistic regression models
3. **Model Evaluation** — comparing models using AUC, KS statistic, Gini coefficient, decile lift, and calibration
4. **Final Submission** — retraining the best model on the full training set and scoring the test set

---

## Requirements

### SAS Version

This code was written and tested on **SAS 9.4 (English with DBCS)** on a Windows 64-bit workstation.

> Minimum required: **SAS 9.4**  

---

## Step 1 — Load the Dataset into SAS

Before running any code, the dataset must be loaded into the **WORK** library and named **DataQuest**.

You have two options:

---

### Option A — Import Manually via the SAS GUI (Point and Click)

1. Open **SAS 9.4**
2. In the top menu, click **File → Import Data**
3. Select your file type (e.g. `.csv`, `.xlsx`)
4. Browse to your dataset file and click **Next**
5. Set the output library to **WORK** and the dataset name to **DataQuest**
6. Click **Finish**

> Your dataset will now be available as `WORK.DataQuest`

---

### Option B — Import Using SAS Code

Copy and run **one** of the following code blocks depending on your file type.

#### If your file is a CSV:

```sas
/* ============================================================
   IMPORT: Load the DataQuest dataset from a CSV file
   Replace the file path below with the actual path to your file
   ============================================================ */

PROC IMPORT
    DATAFILE = "C:\Your\File\Path\dataquest_dataset.csv"   /* <-- Update this path */
    OUT      = WORK.DataQuest
    DBMS     = CSV
    REPLACE;
    GETNAMES = YES;   /* First row contains column headers */
RUN;
```

#### If your file is an Excel (.xlsx):

```sas
/* ============================================================
   IMPORT: Load the DataQuest dataset from an Excel file
   Replace the file path and sheet name as needed
   ============================================================ */

PROC IMPORT
    DATAFILE = "C:\Your\File\Path\dataquest_dataset.xlsx"   /* <-- Update this path */
    OUT      = WORK.DataQuest
    DBMS     = XLSX
    REPLACE;
    SHEET    = "Sheet1";    /* <-- Update with your actual sheet name */
    GETNAMES = YES;
RUN;
```

#### Verify the import was successful:

```sas
/* Quick check: print first 10 rows and confirm row count */
PROC PRINT DATA = WORK.DataQuest (OBS = 10);
    TITLE "Preview: First 10 rows of WORK.DataQuest";
RUN;

PROC SQL;
    SELECT COUNT(*) AS Total_Rows FROM WORK.DataQuest;
    TITLE "Total row count in WORK.DataQuest";
QUIT;
```

---

## Step 2 — Run the Main SAS Script

Once the dataset is loaded as `WORK.DataQuest`, open and run the main SAS file:

```
DataQuest_Credit_Risk_Model.sas
```

The script is divided into four sections. You can run them all at once or section by section.

---

## Code Structure

| Section | Description |
|---------|-------------|
| **Section 1** | Data preparation, missing value checks, multicollinearity checks (VIF), and training of four candidate models |
| **Section 2** | Validation diagnostics — AUC, KS statistic, Gini coefficient, decile lift tables, and calibration checks |
| **Section 3** | Final model retrained on 100% of the training data and scored on the blind test set |
| **Section 4** | Submission file formatting and sanity checks |

---

## Models Trained

| Model | Selection Method | Variables |
|-------|-----------------|-----------|
| **M1 — Stepwise** | Automatic stepwise selection (p ≤ 0.05 entry and stay) | 20 candidates |
| **M2 — Backward** | Backward elimination (p ≤ 0.05 to stay) | 20 candidates |
| **M3 — Theory-Driven** | No selection — 16 variables forced in based on domain knowledge | 16 fixed |
| **M4 — Parsimonious** | No selection — 7 strongest predictors only | 7 fixed |

---

## Evaluation Metrics

The following metrics are computed for all four models on a held-out local validation set (20% of the training data):

| Metric | What It Measures | Good Threshold |
|--------|-----------------|----------------|
| **AUC (c-statistic)** | Overall discriminatory ability | > 0.70 |
| **KS Statistic** | Maximum separation between defaulters and non-defaulters | > 30% |
| **Gini Coefficient** | Discriminatory power (= 2 × AUC − 1) | > 0.40 |
| **Decile Lift** | Concentration of defaults in top-ranked deciles | Decile 1 lift ≥ 3× |
| **Calibration** | Accuracy of predicted probabilities vs actual rates | Abs. error < 0.02 |

---

## Output Datasets Created

| Dataset | Contents |
|---------|----------|
| `WORK.Train` | Training rows from the full dataset |
| `WORK.Test` | Test rows from the full dataset |
| `WORK.Local_Train` | 80% random split of Train used for model fitting |
| `WORK.Local_Val` | 20% random split of Train used for validation |
| `WORK.Pred_M1` to `WORK.Pred_M4` | Predicted probabilities for each model on Local_Val |
| `WORK.AUC_Summary` | AUC comparison table across all four models |
| `WORK.KS_All` | KS statistic comparison table |
| `WORK.Gini_Summary` | Gini coefficient comparison table |
| `WORK.Final_Model_Betas` | Coefficient estimates for the final model |
| `WORK.Submission_Final` | Final submission file with `applicant_id_hash` and `default_probability` |

---

## Important Notes

- **Random seed:** `CALL STREAMINIT(2024)` is used for the 80/20 local split. This ensures the split is reproducible — anyone running the code with this seed will get the same split.
- **ROC plots are disabled** by default (`ODS GRAPHICS OFF`) to prevent memory issues in SAS 9.4 when processing large datasets. To enable them, remove or comment out the `ODS GRAPHICS OFF;` line at the top of the script.
- **Variables removed due to multicollinearity:**
  - `ever_delinquent` — zero or near-zero variance
  - `credit_risk_index` — severe multicollinearity (VIF > 11)
 
- **WORK library is temporary.** All datasets in WORK are lost when SAS is closed. Export any output you wish to keep before closing the session.

---

## Required Column Names

The dataset loaded as `WORK.DataQuest` must contain the following columns:

```
applicant_id_hash              SET (values: 'train' / 'test')
default_flag                   employment_length_years
num_open_accounts              num_delinquencies_2yr
total_revolving_balance        credit_utilisation_pct
months_since_oldest_account    num_hard_inquiries_6mo
dti_ratio                      months_since_last_delinquency
pct_accounts_current           months_at_current_address
loan_to_income_ratio           credit_risk_index
log_annual_income              log_loan_amount
home_ownership_woe             loan_purpose_woe
email_domain_type_woe          phone_verified_woe
age_group_woe                  delinquency_flag
high_utilisation_flag          ever_delinquent
```

---

*DataQuest 2026 — Credit Risk Modelling Project*
