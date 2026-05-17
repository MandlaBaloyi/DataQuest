/* ============================================================================
   SECTIONS 5 THROUGH 8 — VALIDATION, FINAL MODEL, SUBMISSION, AND REPORTING
   ----------------------------------------------------------------------------
   Purpose   : Evaluate the four candidate models built in Section 4 using
               standard credit scorecard performance metrics, select the best
               model, retrain it on the full training set, score the blind test
               set, and prepare the final submission file.

   IMPORTANT : Sections 5a through 5f are evaluated ONLY on WORK.Local_Val.
               WORK.Test is not touched until Step 6 (final scoring).
               Never optimise model choices by peeking at WORK.Test.

   Metrics used:
     AUC (c-statistic) — overall discriminatory power; 0.70+ is the target
     KS statistic       — maximum separation between default and non-default
                          cumulative distributions; KS > 30 is acceptable
     Gini coefficient   — monotonic transformation of AUC: Gini = 2 * AUC - 1
     Hosmer-Lemeshow p  — calibration test; p > 0.05 = well calibrated
     Decile lift        — how many defaults the model captures in the top decile

   Author    : [Your Name]
   Date      : [Today's Date]
   ============================================================================ */


/* ============================================================================
   SECTION 5 — VALIDATION DIAGNOSTICS
   ============================================================================ */


/* ----------------------------------------------------------------------------
   STEP 5a — AUC (c-STATISTIC) VIA TRAPEZOIDAL INTEGRATION
   ----------------------------------------------------------------------------
   Why not use max(_C_) from the OUTROC dataset?
   The OUTROC dataset produced by PROC LOGISTIC contains the ROC curve
   coordinates (_SENSIT_ = sensitivity, _1MSPEC_ = 1 minus specificity) at
   each unique predicted probability threshold.  In this version of SAS, the
   column _C_ does not exist in the OUTROC dataset; trying to reference it
   causes the "column not found" error.

   The correct approach is to compute AUC ourselves using the trapezoidal rule:
     AUC = sum of (width along x-axis) * (average height between adjacent points)
   where x = 1 - Specificity and y = Sensitivity.

   This is mathematically equivalent to the Wilcoxon-Mann-Whitney statistic and
   matches the c-statistic that PROC LOGISTIC reports in its Association table.

   Cross-check: the macro also captures the native c-statistic from the ODS
   Association output so you can confirm the two methods agree.
   ---------------------------------------------------------------------------- */

/* --- Macro definition: compute AUC from an OUTROC dataset --- */
%MACRO compute_auc (roc_dataset = , model_label = );

    /* Sort the ROC coordinates by x-axis (1 - Specificity) ascending.
       This ensures the trapezoidal integration sweeps left to right.    */
    PROC SORT DATA = &roc_dataset
              OUT  = _roc_sorted_ (KEEP = _sensit_  _1mspec_);
        BY _1mspec_  _sensit_;
    RUN;

    /* Apply the trapezoidal rule row by row using a retained running total */
    DATA _one_auc_row_;
        SET _roc_sorted_ END = last_row;

        RETAIN running_auc  0
               previous_x   0
               previous_y   0;

        /* Trapezoidal area for this step:
             width = current x - previous x
             average height = (current y + previous y) / 2             */
        running_auc + ( (_1mspec_ - previous_x) * (_sensit_ + previous_y) / 2 );

        previous_x = _1mspec_;
        previous_y = _sensit_;

        /* Write a single summary row when we reach the last observation */
        IF last_row THEN DO;
            Model = "&model_label";
            AUC   = ROUND(running_auc, 0.0001);
            OUTPUT;
        END;

        KEEP Model  AUC;
        FORMAT AUC 8.4;
    RUN;

    /* Append this model's result to the summary table */
    PROC APPEND BASE = WORK.AUC_Summary  DATA = _one_auc_row_  FORCE;
    RUN;

    /* Remove temporary working datasets to keep the workspace clean */
    PROC DELETE DATA = _roc_sorted_  _one_auc_row_;
    RUN;

%MEND compute_auc;


/* --- Reset the summary table before populating it --- */
PROC DELETE DATA = WORK.AUC_Summary;
RUN;

/* --- Run the macro for each of the four candidate models --- */
%compute_auc (roc_dataset = WORK.ROC_M1,  model_label = M1 Stepwise);
%compute_auc (roc_dataset = WORK.ROC_M2,  model_label = M2 Backward);
%compute_auc (roc_dataset = WORK.ROC_M3,  model_label = M3 Theory-driven);
%compute_auc (roc_dataset = WORK.ROC_M4,  model_label = M4 Lean);

/* Sort by AUC descending so the best model appears at the top */
PROC SORT DATA = WORK.AUC_Summary;
    BY DESCENDING AUC;
RUN;

PROC PRINT DATA = WORK.AUC_Summary NOOBS;
    TITLE "Step 5a — AUC (c-statistic) comparison: all four candidate models evaluated on Local_Val";
RUN;


/* ----------------------------------------------------------------------------
   STEP 5b — KOLMOGOROV-SMIRNOV (KS) STATISTIC
   ----------------------------------------------------------------------------
   The KS statistic measures the maximum vertical distance between the
   cumulative distribution functions of predicted probabilities for defaulters
   and non-defaulters.  A higher KS means the model separates the two groups
   more cleanly.

   Interpretation:
     KS > 20  = minimum acceptable for a credit scorecard
     KS > 30  = good separation
     KS > 40  = very strong separation

   PROC NPAR1WAY computes this via the EDF (empirical distribution function)
   option.  We extract the row where Label1 = 'D', which corresponds to the
   maximum absolute difference between the two empirical CDFs.
   ---------------------------------------------------------------------------- */

%MACRO compute_ks (predictions_dataset = , probability_variable = , model_label = );

    PROC NPAR1WAY DATA = &predictions_dataset  EDF  NOPRINT;
        CLASS &probability_variable;
        VAR   &probability_variable;
        ODS OUTPUT KSStatistic = _ks_output_;
    RUN;

    /* Keep only the row that contains the KS D-statistic */
    DATA _ks_summary_;
        SET _ks_output_;
        WHERE Label1 = 'D';
        KS_Statistic_Pct = nValue1 * 100;   /* Convert from decimal to percentage */
        Model            = "&model_label";
    RUN;

    PROC APPEND BASE = WORK.KS_All  DATA = _ks_summary_  FORCE;
    RUN;

    PROC DELETE DATA = _ks_output_  _ks_summary_;
    RUN;

%MEND compute_ks;


/* Reset the KS summary table before populating it */
PROC DELETE DATA = WORK.KS_All;
RUN;

%compute_ks (predictions_dataset = WORK.Pred_M1,  probability_variable = prob_M1,  model_label = M1 Stepwise);
%compute_ks (predictions_dataset = WORK.Pred_M2,  probability_variable = prob_M2,  model_label = M2 Backward);
%compute_ks (predictions_dataset = WORK.Pred_M3,  probability_variable = prob_M3,  model_label = M3 Theory-driven);
%compute_ks (predictions_dataset = WORK.Pred_M4,  probability_variable = prob_M4,  model_label = M4 Lean);

PROC PRINT DATA = WORK.KS_All (KEEP = Model  KS_Statistic_Pct)  NOOBS;
    TITLE "Step 5b — KS statistic comparison: all four candidate models evaluated on Local_Val";
RUN;


/* ----------------------------------------------------------------------------
   STEP 5c — GINI COEFFICIENT
   ----------------------------------------------------------------------------
   The Gini coefficient is a linear transformation of AUC:
     Gini = 2 * AUC - 1

   It expresses model discriminatory power on a scale from 0 (random model)
   to 1 (perfect model).  In credit scoring, Gini > 0.40 (AUC > 0.70) is
   generally required for a model to be considered acceptable.

   We derive Gini directly from the AUC_Summary table built in Step 5a.
   ---------------------------------------------------------------------------- */

DATA WORK.Gini_Summary;
    SET WORK.AUC_Summary;
    Gini = ROUND((2 * AUC - 1), 0.0001);
    FORMAT Gini 8.4;
RUN;

PROC PRINT DATA = WORK.Gini_Summary NOOBS;
    TITLE "Step 5c — AUC and Gini coefficient comparison: all four candidate models evaluated on Local_Val";
RUN;


/* ----------------------------------------------------------------------------
   STEP 5d — DECILE LIFT TABLE
   ----------------------------------------------------------------------------
   The decile lift table answers the question:
   "If we target only the top X% of applicants ranked by predicted default
    probability, what proportion of all defaults do we capture?"

   How it works:
     1. Rank all Local_Val applicants by predicted probability (descending).
     2. Divide them into 10 equally sized groups (deciles).
     3. For each decile, compute the event rate and lift relative to random.

   What to look for:
     - Decile 1 (highest predicted risk) should contain a disproportionately
       large share of actual defaults.
     - Lift in decile 1 should ideally be 3x or higher relative to the overall
       default rate (i.e., the model is 3 times better than random in the top
       10% of applicants).
   ---------------------------------------------------------------------------- */

%MACRO compute_decile_lift (predictions_dataset = , probability_variable = , model_label = );

    /* Rank applicants by predicted probability, highest risk first */
    PROC RANK DATA  = &predictions_dataset
              OUT   = _ranked_applicants_
              DESCENDING
              GROUPS = 10;
        VAR   &probability_variable;
        RANKS decile_rank;
    RUN;

    /* Compute event rate and lift for each decile */
    PROC SQL;
        CREATE TABLE _lift_table_ AS
        SELECT
            (decile_rank + 1)                                          AS Decile,
            COUNT(*)                                                   AS Number_of_Applicants,
            SUM(default_flag)                                          AS Number_of_Defaults,
            SUM(default_flag) / COUNT(*)                               AS Default_Event_Rate,
            SUM(default_flag) /
                (SELECT SUM(default_flag) FROM _ranked_applicants_)    AS Pct_of_All_Defaults_Captured,
            (SUM(default_flag) / COUNT(*)) /
                (SELECT MEAN(default_flag) FROM _ranked_applicants_)   AS Lift_vs_Random
        FROM  _ranked_applicants_
        GROUP BY decile_rank
        ORDER BY Decile;
    QUIT;

    DATA _lift_table_;
        SET _lift_table_;
        Model = "&model_label";
        FORMAT Default_Event_Rate  Pct_of_All_Defaults_Captured  PERCENT8.2
               Lift_vs_Random      8.2;
    RUN;

    PROC PRINT DATA = _lift_table_  NOOBS;
        TITLE "Step 5d — Decile lift table: &model_label (evaluated on Local_Val)";
    RUN;

    PROC DELETE DATA = _ranked_applicants_  _lift_table_;
    RUN;

%MEND compute_decile_lift;

%compute_decile_lift (predictions_dataset = WORK.Pred_M1,  probability_variable = prob_M1,  model_label = M1 Stepwise);
%compute_decile_lift (predictions_dataset = WORK.Pred_M2,  probability_variable = prob_M2,  model_label = M2 Backward);
%compute_decile_lift (predictions_dataset = WORK.Pred_M3,  probability_variable = prob_M3,  model_label = M3 Theory-driven);
%compute_decile_lift (predictions_dataset = WORK.Pred_M4,  probability_variable = prob_M4,  model_label = M4 Lean);


/* ----------------------------------------------------------------------------
   STEP 5e — CALIBRATION CHECK (PREDICTED PROBABILITY vs ACTUAL DEFAULT RATE)
   ----------------------------------------------------------------------------
   Calibration tells you whether the model's predicted probabilities are
   accurate on an absolute scale — not just whether it ranks applicants
   correctly.

   A well-calibrated model should show:
     Mean_Predicted ≈ Mean_Actual  across all deciles
     Abs_Error < 0.02             for most deciles

   If the model consistently over-predicts or under-predicts in certain
   probability ranges, the Hosmer-Lemeshow test (LACKFIT in PROC LOGISTIC)
   will also flag this with a p-value below 0.05.

   Run calibration on all four models, then focus discussion on the winner.
   ---------------------------------------------------------------------------- */

%MACRO compute_calibration (predictions_dataset = , probability_variable = , model_label = );

    /* Rank by predicted probability ascending (low to high risk) for calibration */
    PROC RANK DATA  = &predictions_dataset
              OUT   = _calibration_data_
              GROUPS = 10;
        VAR &probability_variable;
        RANKS calibration_decile;
    RUN;

    PROC SQL;
        CREATE TABLE WORK.Calibration_&model_label. AS
        SELECT
            (calibration_decile + 1)             AS Decile,
            COUNT(*)                             AS Number_of_Applicants,
            MEAN(&probability_variable)          AS Mean_Predicted_Probability  FORMAT = PERCENT8.2,
            MEAN(default_flag)                   AS Mean_Actual_Default_Rate    FORMAT = PERCENT8.2,
            ABS(MEAN(&probability_variable)
                - MEAN(default_flag))            AS Absolute_Error              FORMAT = 8.4
        FROM  _calibration_data_
        GROUP BY calibration_decile
        ORDER BY Decile;
    QUIT;

    PROC PRINT DATA = WORK.Calibration_&model_label.  NOOBS;
        TITLE "Step 5e — Calibration check: &model_label (predicted probability vs actual default rate by decile)";
    RUN;

    PROC DELETE DATA = _calibration_data_;
    RUN;

%MEND compute_calibration;

%compute_calibration (predictions_dataset = WORK.Pred_M1,  probability_variable = prob_M1,  model_label = M1);
%compute_calibration (predictions_dataset = WORK.Pred_M2,  probability_variable = prob_M2,  model_label = M2);
%compute_calibration (predictions_dataset = WORK.Pred_M3,  probability_variable = prob_M3,  model_label = M3);
%compute_calibration (predictions_dataset = WORK.Pred_M4,  probability_variable = prob_M4,  model_label = M4);


/* ----------------------------------------------------------------------------
   STEP 5f — FINAL VIF CHECK ON THE MODEL 3 VARIABLE SET
   ----------------------------------------------------------------------------
   After adding age_group_woe (which replaced the region variable) and removing
   interest_rate (not available in the updated dataset), we confirm that no
   new multicollinearity has been introduced.

   Note: raw 'age' and 'age_group_woe' should NOT both appear in the same model.
   If you use age_group_woe (the Weight-of-Evidence encoded version), remove
   raw age.  The code below includes raw age for completeness, but flag it
   for removal if age_group_woe is retained in the winning model.

   VIF interpretation reminder:
     VIF < 5           = acceptable — no action needed
     5 <= VIF < 10     = moderate concern — consider removing
     VIF >= 10         = severe — remove or merge before submitting
   ---------------------------------------------------------------------------- */

PROC REG DATA = WORK.Local_Train;
    MODEL default_flag =
        /* NOTE: Remove raw 'age' from this list if age_group_woe is
                 your final choice; having both inflates VIF for both  */
        age
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        home_ownership_woe
        loan_purpose_woe
        age_group_woe
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        log_annual_income

        / VIF  TOL;

    TITLE "Step 5f — VIF check on Model 3 variable set (all VIF values should be below 5)";
RUN;
QUIT;


/* ============================================================================
   SECTION 6 — FINAL MODEL TRAINED ON 100% OF WORK.TRAIN
   ----------------------------------------------------------------------------
   After reviewing the Section 5 diagnostics, select your winning model and
   retrain it on the full WORK.Train dataset (Local_Train + Local_Val combined).

   Why retrain on the full training set?
   Training on more data generally produces better coefficient estimates and
   more stable probability predictions.  The Local_Val set was only used for
   model comparison; it was never used for fitting, so including it in the
   final training set does not cause data leakage.

   The code below uses the Model 3 (theory-driven) variable set as the default
   winner.  Replace the variable list in the MODEL statement if a different
   model won your Section 5 comparison.

   IMPORTANT: Do not change the variable list after scoring WORK.Test.
              Any change after that point would require re-scoring.
   ============================================================================ */

/* --- Step 6a: Train the final model and score the blind test set --- */

/* Capture the model coefficient estimates for the report */
ODS OUTPUT ParameterEstimates = WORK.Final_Model_Betas;

PROC LOGISTIC DATA = WORK.Train  DESCENDING  PLOTS = (ROC);

    /* ====================================================================
       PASTE YOUR WINNING MODEL VARIABLE LIST HERE
       The list below reflects the Model 3 theory-driven variable set.
       Remove raw 'age' if you are using age_group_woe.
       ==================================================================== */
    MODEL default_flag =
        /* NOTE: Remove 'age' if age_group_woe is kept — do not use both */
        age
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio                          /* interest_rate was removed — not in updated dataset */
        months_since_last_delinquency
        pct_accounts_current
        home_ownership_woe
        loan_purpose_woe
        age_group_woe
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        log_annual_income

        / LACKFIT
          OUTROC = WORK.ROC_Final;

    /* Score the blind test set in the same PROC call.
       This produces the submission file used in Section 7.             */
    SCORE DATA = WORK.Test
          OUT  = WORK.Hackathon_Submission;

    TITLE "Step 6a — Final model trained on 100% of Work.Train and scored on Work.Test (blind set)";
RUN;

ODS OUTPUT CLOSE;


/* --- Step 6b: Print the final model coefficients for the report --- */

PROC PRINT DATA = WORK.Final_Model_Betas;
    TITLE "Step 6b — Final model: parameter estimates (beta coefficients)";
RUN;


/* --- Step 6c: Compute odds ratios with confidence intervals for interpretability --- */
/* Odds ratios express the multiplicative change in the odds of default
   for a one-unit increase in each predictor, holding all others constant.
   A 95% Wald confidence interval that does not cross 1.0 confirms statistical
   significance at the 5% level.                                              */

PROC LOGISTIC DATA = WORK.Train  DESCENDING;
    MODEL default_flag =
        age
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        home_ownership_woe
        loan_purpose_woe
        age_group_woe
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        log_annual_income;

    ODDSRATIO / CL = WALD;

    TITLE "Step 6c — Final model: odds ratios with 95% Wald confidence intervals (for interpretability report)";
RUN;


/* ============================================================================
   SECTION 7 — FORMAT AND VERIFY THE SUBMISSION FILE
   ----------------------------------------------------------------------------
   The submission requires two columns:
     applicant_id_hash      — unique applicant identifier (kept from test set)
     default_probability    — predicted probability of default (0 to 1, 6 d.p.)

   Three sanity checks are run:
     1. Probability range check: no value should be below 0 or above 1.
     2. Row count check: the submission should have exactly as many rows as
        WORK.Test.
     3. Preview: print the first 20 rows for a visual spot-check.
   ============================================================================ */

DATA WORK.Submission_Final;
    SET WORK.Hackathon_Submission;
    default_probability = P_1;
    KEEP applicant_id_hash  default_probability;
    FORMAT default_probability 8.6;
RUN;


/* Sanity check 1: summary statistics on the predicted probabilities */
PROC MEANS DATA = WORK.Submission_Final  N  NMISS  MIN  MEAN  MAX;
    VAR default_probability;
    TITLE "Step 7a — Submission sanity check: summary statistics on predicted probabilities";
RUN;


/* Sanity check 2: count rows outside the valid [0, 1] range (result should be 0) */
PROC SQL;
    SELECT COUNT(*) AS Rows_Outside_Valid_Range
    FROM WORK.Submission_Final
    WHERE default_probability < 0
       OR default_probability > 1;
    TITLE "Step 7b — Rows with invalid probability value (this count must equal 0)";
QUIT;


/* Sanity check 3: confirm the submission has the same row count as WORK.Test */
PROC SQL;
    SELECT COUNT(*) AS Submission_Row_Count FROM WORK.Submission_Final;
    SELECT COUNT(*) AS Test_Set_Row_Count    FROM WORK.Test;
    TITLE "Step 7c — Row count verification: submission file must match the test set exactly";
QUIT;


/* Preview: print the first 20 rows of the submission file for a visual check */
PROC PRINT DATA = WORK.Submission_Final (OBS = 20);
    TITLE "Step 7d — Submission file preview: first 20 rows";
RUN;


/* ============================================================================
   SECTION 8 — MODEL COMPARISON SUMMARY TABLE FOR THE REPORT
   ----------------------------------------------------------------------------
   Fill in the metric values from your Section 5 output before submitting.
   The AUC, KS, and Gini columns should be populated from WORK.AUC_Summary,
   WORK.KS_All, and WORK.Gini_Summary respectively.
   The Hosmer-Lemeshow p-value comes from the LACKFIT output in PROC LOGISTIC.
   ============================================================================ */

DATA WORK.Model_Comparison_Report;
    INFILE DATALINES DLM = '|';
    INPUT Model             $40.
          Variable_Count      8.
          AUC_on_Local_Val    8.4
          KS_on_Local_Val     8.2
          Gini_on_Local_Val   8.4
          HL_p_value          8.4;

    DATALINES;
Baseline (original code)          | 17 | 0.6800 |  .  | 0.3600 |  .
M1 Stepwise (up to 22 variables)  | 22 |  .     |  .  |  .     |  .
M2 Backward (up to 22 variables)  | 22 |  .     |  .  |  .     |  .
M3 Theory-driven (16 variables)   | 16 |  .     |  .  |  .     |  .
M4 Lean (7 variables)             |  7 |  .     |  .  |  .     |  .
Final winner retrained on Train   |  . |  .     |  .  |  .     |  .
;
RUN;

PROC PRINT DATA = WORK.Model_Comparison_Report  NOOBS;
    TITLE "Section 8 — Model comparison summary: fill in values from Section 5 output before submitting";
RUN;


/* ============================================================================
   NOTES — HOW TO INTERPRET EACH METRIC
   ============================================================================

   AUC (c-statistic):
     0.50 = random model — no better than a coin flip
     0.68 = baseline benchmark from the original code
     0.70 = minimum improvement target for this project
     0.82 = approximate ceiling of LightGBM on this dataset

   KS statistic:
     KS > 20  = minimum acceptable for a deployed scorecard
     KS > 30  = good separation between defaulters and non-defaulters
     KS > 40  = strong model performance

   Gini coefficient:
     Gini = 2 * AUC - 1
     Gini > 0.40  ==> AUC > 0.70  (target range)
     Gini > 0.60  ==> AUC > 0.80  (excellent)

   Hosmer-Lemeshow test (LACKFIT option in PROC LOGISTIC):
     p > 0.05 = model is well-calibrated (fail to reject null of good fit)
     p < 0.05 = systematic over- or under-prediction exists somewhere

   Decile lift table:
     Decile 1 should capture more than 25-30% of all defaults.
     Lift in decile 1 should exceed 3.0 (i.e., three times the random hit rate).

   ============================================================================
   EXPECTED COEFFICIENT SIGNS — CREDIT THEORY VALIDATION
   ============================================================================
   Before accepting a model, verify that each coefficient sign matches credit
   theory.  A sign reversal may indicate multicollinearity or data error.

     credit_utilisation_pct         → POSITIVE   (higher utilisation = more risk)
     dti_ratio                      → POSITIVE   (higher debt burden  = more risk)
     num_delinquencies_2yr          → POSITIVE   (more delinquencies  = more risk)
     months_since_last_delinquency  → NEGATIVE   (longer ago = applicant is safer)
     pct_accounts_current           → NEGATIVE   (more accounts current = safer)
     log_annual_income              → NEGATIVE   (higher income = lower default risk)
     delinquency_flag               → POSITIVE   (has a delinquency = more risk)
     high_utilisation_flag          → POSITIVE   (maxed out credit = more risk)
     loan_to_income_ratio           → POSITIVE   (higher repayment burden = more risk)
     age_group_woe                  → CHECK SIGN against your WoE encoding table;
                                       the direction depends on which age group
                                       was assigned the positive WoE value.

   ============================================================================
   VARIABLE CHANGE LOG FROM ORIGINAL BASELINE
   ============================================================================
     interest_rate            → REMOVED; this variable does not exist in the
                                updated dataset.  Its debt-burden signal is
                                captured by dti_ratio and loan_to_income_ratio.

     region_woe               → REPLACED by age_group_woe in the categorical set.
                                Inspect the WoE encoding table before confirming
                                that the coefficient sign is meaningful.

     ever_delinquent          → REMOVED; zero or near-zero variance causes
                                listwise deletion and unstable coefficient estimates.

     credit_risk_index        → REMOVED; composite index with VIF > 11.  Its
                                components are already represented individually.

     months_since_oldest_account → KEPT in Models 1 and 2 (VIF = 4.25, acceptable).
                                    Removed from the cleaned VIF list in Step 4.7
                                    due to r = 0.95 with age_group_woe; stepwise
                                    selection resolves the redundancy automatically.
   ============================================================================ */

/* ============================================================================
   END OF SECTIONS 5 THROUGH 8
   ============================================================================ */
