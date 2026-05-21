/* Prevent Java OOM crash when rendering large ROC plots */
ODS GRAPHICS OFF;  /* Visualization of ROC plots. Remove this line to enable and display ROC plots when running each code cell. */
ODS RTF;

/* ============================================================================
   Section 1 — DATA PREPARATION, MULTICOLLINEARITY CHECKS, AND MODEL BUILDING
   ----------------------------------------------------------------------------
   Purpose   : Prepare the dataset, validate variable quality, check for
               multicollinearity, and train four candidate logistic regression
               models on the local training split.

   Datasets  : WORK.DataQuest  — full labelled dataset (train + test rows)
               WORK.Train      — rows where SET = 'train'
               WORK.Test       — rows where SET = 'test'
               WORK.Local_Train — 80% random split of WORK.Train (model fitting)
               WORK.Local_Val   — 20% random split of WORK.Train (model evaluation)
   ============================================================================ */


/* ROW COUNT AND DEFAULT RATE BY DATASET SPLIT */

PROC FREQ DATA = WORK.DataQuest;
    TABLES SET * default_flag / NOCOL NOPERCENT;
    TITLE "Row counts and default rates by dataset split (train vs test)";
RUN;


/* MISSING VALUE CHECK ACROSS ALL MODEL-READY VARIABLES */

PROC MEANS DATA = WORK.DataQuest NMISS N MEAN STD MIN MAX;
    VAR
        /* Continuous and ratio features */
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        total_revolving_balance
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        credit_risk_index
        log_annual_income
        log_loan_amount

        /* Weight-of-Evidence encoded categorical variables */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* Binary engineered indicator flags */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent;

    TITLE "Missing value check across all model-ready variables";
RUN;


/* SPLIT WORK.DataQuest INTO TRAIN AND TEST SETS */

DATA WORK.Train  WORK.Test;
    SET WORK.DataQuest;
    SET_lower = LOWCASE(SET);

    IF      SET_lower = 'train' THEN OUTPUT WORK.Train;
    ELSE IF SET_lower = 'test'  THEN OUTPUT WORK.Test;

    DROP SET_lower;
RUN;


/* Verify the split: confirm row counts and that default rates are stable */
PROC SQL;
    SELECT
        'Train' AS Dataset,
        COUNT(*)            AS Row_Count,
        SUM(default_flag)   AS Number_of_Defaults,
        MEAN(default_flag)  AS Default_Rate FORMAT = PERCENT8.2
    FROM WORK.Train

    UNION ALL

    SELECT
        'Test',
        COUNT(*),
        SUM(default_flag),
        MEAN(default_flag)
    FROM WORK.Test;

    TITLE "Train and Test split verification (row counts and default rates)";
QUIT;


/* CREATE LOCAL TRAIN (80%) AND LOCAL VALIDATION (20%) SPLITS

   We hold out 20% of WORK.Train as a local validation set so we can compare
   candidate models without touching the blind test set (WORK.Test).

   CALL STREAMINIT(2024) sets the random seed so the split is reproducible.
   Anyone running this code with seed 2024 will get the same split. */

DATA WORK.Local_Train  WORK.Local_Val;
    SET WORK.Train;
    CALL STREAMINIT(2024);         

    IF   RAND('uniform') <= 0.80 THEN OUTPUT WORK.Local_Train;
    ELSE                              OUTPUT WORK.Local_Val;
RUN;


/* Verify that both splits are balanced and have similar default rates */
PROC SQL;
    SELECT
        'Local_Train' AS Split,
        COUNT(*)           AS Row_Count,
        SUM(default_flag)  AS Number_of_Defaults,
        MEAN(default_flag) AS Default_Rate FORMAT = PERCENT8.2
    FROM WORK.Local_Train

    UNION ALL

    SELECT
        'Local_Val',
        COUNT(*),
        SUM(default_flag),
        MEAN(default_flag)
    FROM WORK.Local_Val;

    TITLE "Local Train & Validation split verification (80% & 20%)";
QUIT;


/* CORRELATION MATRIX
   High pairwise correlations (|r| > 0.70) between predictors indicate
   potential multicollinearity.  Variables that are highly correlated carry
   redundant information and can destabilise coefficient estimates. */

PROC CORR DATA = WORK.Local_Train NOSIMPLE;
    VAR
        /* Continuous and ratio features */
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        total_revolving_balance
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        credit_risk_index
        log_annual_income
        log_loan_amount

        /* Weight-of-Evidence encoded categorical variables */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* Binary engineered indicator flags */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent;

    TITLE "Pairwise correlation matrix (flag |r| > 0.70 for follow-up)";
RUN;


/* FIRST MULTICOLLINEARITY CHECK: FULL VARIABLE LIST (VIF and TOL)

   NOTE FOR REVIEWERS:
   PROC LOGISTIC does not produce Variance Inflation Factor (VIF) statistics
   in this version of SAS.  As a standard workaround, we run PROC REG on the
   same dependent variable and predictor set for the sole purpose of extracting
   VIF and Tolerance diagnostics.  The linear regression coefficients themselves
   are not used or interpreted. */

PROC REG DATA = WORK.Local_Train PLOTS = NONE;
    MODEL default_flag =
        /* Continuous and ratio features */
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        total_revolving_balance
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        credit_risk_index
        log_annual_income
        log_loan_amount

        /* Weight-of-Evidence encoded categorical variables */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* Binary engineered indicator flags */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent

        / VIF TOL;

    TITLE "First VIF check: full variable list (identify variables to remove)";
QUIT;


/* SECOND MULTICOLLINEARITY CHECK: CLEANED VARIABLE LIST

   Variables removed after reviewing the first VIF check:

     ever_delinquent             — zero or near-zero variance
     credit_risk_index           — severe multicollinearity (VIF > 11)
     months_since_oldest_account — Pearson r = 0.95 with age_group_woe;
                                   the two variables carry essentially the
                                   same information.

   This step confirms that the remaining variables all have VIF < 5. */

PROC REG DATA = WORK.Local_Train PLOTS = NONE;
    MODEL default_flag =
        /* Continuous and ratio features (cleaned list) */
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        total_revolving_balance
        credit_utilisation_pct
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        log_annual_income
        log_loan_amount

        /* Weight-of-Evidence encoded categorical variables */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* Binary engineered indicator flags */
        delinquency_flag
        high_utilisation_flag

        / VIF TOL;

    TITLE "Second VIF check: cleaned variable list (all VIF values should be below 5)";
QUIT;


/* ============================================================================
   MODEL 1: STEPWISE LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Note: months_since_oldest_account is included here because its standalone
   VIF of 4.25 is acceptable; we removed it in the cleaned list only due to
   its very high correlation with age_group_woe.  Stepwise will resolve the
   redundancy automatically by selecting at most one of the two.

   Output:
     WORK.ROC_M1   — ROC curve coordinates
     WORK.Pred_M1  — Predicted probabilities on Local_Val
     WORK.Betas_M1 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING;
    MODEL default_flag =
        /* Continuous and ratio features */
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        total_revolving_balance
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        log_annual_income
        log_loan_amount

        /* Weight-of-Evidence encoded categorical variables */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* Binary engineered indicator flags */
        delinquency_flag
        high_utilisation_flag

        /* Removed: ever_delinquent (zero variance) and credit_risk_index (VIF > 11) */

        / SELECTION = STEPWISE
          SLENTRY   = 0.05
          SLSTAY    = 0.05
          LACKFIT
          OUTROC    = WORK.ROC_M1;

    SCORE DATA = WORK.Local_Val
          OUT  = WORK.Pred_M1 (KEEP = applicant_id_hash  default_flag  P_1);

    ODS OUTPUT ParameterEstimates = WORK.Betas_M1;

    TITLE "Model 1: Stepwise lLogistic Regression";
RUN;

/* Rename the predicted probability column to a model-specific name
   so we can merge all four models' scores side by side later */
DATA WORK.Pred_M1;
    SET WORK.Pred_M1 (RENAME = (P_1 = prob_M1));
RUN;


/* ============================================================================
   MODEL 2: BACKWARD ELIMINATION LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Output:
     WORK.ROC_M2   — ROC curve coordinates
     WORK.Pred_M2  — Predicted probabilities on Local_Val
     WORK.Betas_M2 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING;
    MODEL default_flag =
        /* Continuous and ratio features */
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        total_revolving_balance
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        log_annual_income
        log_loan_amount

        /* Weight-of-Evidence encoded categorical variables */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* Binary engineered indicator flags */
        delinquency_flag
        high_utilisation_flag

        /* Removed: ever_delinquent (zero variance) and credit_risk_index (VIF > 11) */

        / SELECTION = BACKWARD
          SLSTAY    = 0.05
          LACKFIT
          OUTROC    = WORK.ROC_M2;

    SCORE DATA = WORK.Local_Val
          OUT  = WORK.Pred_M2 (KEEP = applicant_id_hash  default_flag  P_1);

    ODS OUTPUT ParameterEstimates = WORK.Betas_M2;

    TITLE "Model 2: Backward Elimination Logistic Regression";
RUN;

DATA WORK.Pred_M2;
    SET WORK.Pred_M2 (RENAME = (P_1 = prob_M2));
RUN;



/* ============================================================================
   MODEL 3: THEORY-DRIVEN LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Variable selection method: None — all 16 variables are forced into the model
   based on credit-risk domain knowledge.

   Output:
     WORK.ROC_M3   — ROC curve coordinates
     WORK.Pred_M3  — Predicted probabilities on Local_Val
     WORK.Betas_M3 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING;
    MODEL default_flag =
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

        / LACKFIT
          OUTROC = WORK.ROC_M3;

    SCORE DATA = WORK.Local_Val
          OUT  = WORK.Pred_M3 (KEEP = applicant_id_hash  default_flag  P_1);

    ODS OUTPUT ParameterEstimates = WORK.Betas_M3;

    TITLE "Model 3: Theory-Driven Logistic Regression";
RUN;

DATA WORK.Pred_M3;
    SET WORK.Pred_M3 (RENAME = (P_1 = prob_M3));
RUN;


/* ============================================================================
   MODEL 4: PARSIMONIOUS LEAN LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Variable selection method: None — 7 variables are forced into the model.

   This model uses only the 7 strongest predictors identified from the
   correlation matrix, stepwise and backward output.

   Output:
     WORK.ROC_M4   — ROC curve coordinates
     WORK.Pred_M4  — Predicted probabilities on Local_Val
     WORK.Betas_M4 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING;
    MODEL default_flag =
        credit_utilisation_pct
        dti_ratio
        num_delinquencies_2yr
        months_since_last_delinquency
        delinquency_flag
        log_annual_income
        loan_to_income_ratio

        / LACKFIT
          OUTROC = WORK.ROC_M4;

    SCORE DATA = WORK.Local_Val
          OUT  = WORK.Pred_M4 (KEEP = applicant_id_hash  default_flag  P_1);

    ODS OUTPUT ParameterEstimates = WORK.Betas_M4;

    TITLE "Model 4: Parsimonious Lean Logistic Regression (7 strongest predictors only)";
RUN;

DATA WORK.Pred_M4;
    SET WORK.Pred_M4 (RENAME = (P_1 = prob_M4));
RUN;


/* ============================================================================
   SECTION 2 — VALIDATION DIAGNOSTICS
   ============================================================================ */


/* ----------------------------------------------------------------------------
   — AUC (c-STATISTIC) VIA TRAPEZOIDAL INTEGRATION
   ----------------------------------------------------------------------------
   The goal is to compute AUC using the trapezoidal rule:
     AUC = sum of (width along x-axis) * (average height between adjacent points)
   where x = 1 - Specificity and y = Sensitivity.

   This is mathematically equivalent to the Wilcoxon-Mann-Whitney statistic and
   matches the c-statistic that PROC LOGISTIC reports in its Association table.
   ---------------------------------------------------------------------------- */

%MACRO compute_auc (roc_dataset = , model_label = );

    /* Sort the ROC coordinates by x-axis (1 - Specificity) ascending.
       This ensures the trapezoidal integration sweeps left to right. */
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
             width         = current x - previous x
             average height = (current y + previous y) / 2 */
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

    /* Remove temporary working datasets */
    PROC DELETE DATA = _roc_sorted_  _one_auc_row_;
    RUN;

%MEND compute_auc;


/* Reset the summary table before populating it */
PROC DELETE DATA = WORK.AUC_Summary;
RUN;

/* Run the macro for each of the four candidate models */
%compute_auc (roc_dataset = WORK.ROC_M1,  model_label = M1 Stepwise);
%compute_auc (roc_dataset = WORK.ROC_M2,  model_label = M2 Backward);
%compute_auc (roc_dataset = WORK.ROC_M3,  model_label = M3 Theory-driven);
%compute_auc (roc_dataset = WORK.ROC_M4,  model_label = M4 Lean);

/* Sort by AUC descending so the best model appears at the top */
PROC SORT DATA = WORK.AUC_Summary;
    BY DESCENDING AUC;
RUN;

PROC PRINT DATA = WORK.AUC_Summary NOOBS;
    TITLE "AUC (c-statistic) comparison: All four candidate models evaluated on Local_Val";
RUN;


/* ----------------------------------------------------------------------------
    — KOLMOGOROV-SMIRNOV (KS) STATISTIC
   ----------------------------------------------------------------------------
   The KS statistic measures the maximum vertical distance between the
   cumulative distribution functions of predicted probabilities for defaulters
   (default_flag = 1) and non-defaulters (default_flag = 0).

   Interpretation:
     KS > 20  = minimum acceptable for a deployed credit scorecard
     KS > 30  = good separation between defaulters and non-defaulters
     KS > 40  = very strong model performance
   ---------------------------------------------------------------------------- */

%MACRO compute_ks (predictions_dataset  = ,
                   probability_variable = ,
                   model_label          = );

    /* CLASS = default_flag splits observations into two groups:
         Group 0 = non-defaulters
         Group 1 = defaulters
       VAR = the predicted probability we want to evaluate.
       NOPRINT is intentionally omitted so ODS OUTPUT can work. */
    PROC NPAR1WAY DATA = &predictions_dataset  EDF;
        CLASS default_flag;
        VAR   &probability_variable;
        ODS OUTPUT KSStatistic = _ks_output_;
    RUN;

    /* Label1 = 'D' identifies the row holding the maximum
       absolute difference — the KS D-statistic we need. */
    DATA _ks_summary_;
        SET _ks_output_;
        WHERE Label1 = 'D';
        KS_Statistic_Pct = nValue1 * 100;    /* Convert decimal to percentage */
        Model            = "&model_label";
        KEEP Model  KS_Statistic_Pct;
        FORMAT KS_Statistic_Pct 8.2;
    RUN;

    PROC APPEND BASE = WORK.KS_All  DATA = _ks_summary_  FORCE;
    RUN;

    PROC DELETE DATA = _ks_output_  _ks_summary_;
    RUN;

%MEND compute_ks;


/* Initialise a fresh summary table with explicit column lengths
   to prevent variable-length truncation warnings on PROC APPEND */
DATA WORK.KS_All;
    LENGTH Model $20.;
    KS_Statistic_Pct = .;
    DELETE;    /* Creates the table structure without writing any rows */
RUN;

%compute_ks (predictions_dataset = WORK.Pred_M1,
             probability_variable = prob_M1,
             model_label          = M1 Stepwise);

%compute_ks (predictions_dataset = WORK.Pred_M2,
             probability_variable = prob_M2,
             model_label          = M2 Backward);

%compute_ks (predictions_dataset = WORK.Pred_M3,
             probability_variable = prob_M3,
             model_label          = M3 Theory-driven);

%compute_ks (predictions_dataset = WORK.Pred_M4,
             probability_variable = prob_M4,
             model_label          = M4 Lean);

PROC PRINT DATA = WORK.KS_All  NOOBS;
    TITLE "KS Statistic Comparison: All four candidate models evaluated on Local_Val";
RUN;


/* ----------------------------------------------------------------------------
    — GINI COEFFICIENT
   ----------------------------------------------------------------------------
   The Gini coefficient is a linear transformation of AUC:
     Gini = 2 * AUC - 1

   It expresses model discriminatory power on a scale from 0 (random model)
   to 1 (perfect model).  In credit scoring, Gini > 0.40 (AUC > 0.70) is
   generally required for a model to be considered acceptable.

   We derive Gini directly from the AUC_Summary table.
   ---------------------------------------------------------------------------- */

DATA WORK.Gini_Summary;
    SET WORK.AUC_Summary;
    Gini = ROUND((2 * AUC - 1), 0.0001);
    FORMAT Gini 8.4;
RUN;

PROC PRINT DATA = WORK.Gini_Summary NOOBS;
    TITLE " AUC and Gini coefficient comparison: All four candidate models evaluated on Local_Val";
RUN;


/* ----------------------------------------------------------------------------
    — DECILE LIFT TABLE
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
       default rate.
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
        TITLE "Decile lift table: &model_label (evaluated on Local_Val)";
    RUN;

    PROC DELETE DATA = _ranked_applicants_  _lift_table_;
    RUN;

%MEND compute_decile_lift;

%compute_decile_lift (predictions_dataset = WORK.Pred_M1,  probability_variable = prob_M1,  model_label = M1 Stepwise);
%compute_decile_lift (predictions_dataset = WORK.Pred_M2,  probability_variable = prob_M2,  model_label = M2 Backward);
%compute_decile_lift (predictions_dataset = WORK.Pred_M3,  probability_variable = prob_M3,  model_label = M3 Theory-driven);
%compute_decile_lift (predictions_dataset = WORK.Pred_M4,  probability_variable = prob_M4,  model_label = M4 Lean);


/* ----------------------------------------------------------------------------
    — CALIBRATION CHECK (PREDICTED PROBABILITY vs ACTUAL DEFAULT RATE)
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
        TITLE "Calibration check: &model_label (predicted probability vs actual default rate by decile)";
    RUN;

    PROC DELETE DATA = _calibration_data_;
    RUN;

%MEND compute_calibration;

%compute_calibration (predictions_dataset = WORK.Pred_M1,  probability_variable = prob_M1,  model_label = M1);
%compute_calibration (predictions_dataset = WORK.Pred_M2,  probability_variable = prob_M2,  model_label = M2);
%compute_calibration (predictions_dataset = WORK.Pred_M3,  probability_variable = prob_M3,  model_label = M3);
%compute_calibration (predictions_dataset = WORK.Pred_M4,  probability_variable = prob_M4,  model_label = M4);




/* ============================================================================
   SECTION 3 — FINAL MODEL TRAINED ON 100% OF WORK.TRAIN
   ----------------------------------------------------------------------------
   After reviewing the Section 2 diagnostics,we select the  winning model(Model 1) and
   retrain it on the full WORK.Train dataset
   ============================================================================ */

/*  Train the final model and score the blind test set  */
/* Capture the model coefficient estimates*/
ODS OUTPUT ParameterEstimates = WORK.Final_Model_Betas;

PROC LOGISTIC DATA = WORK.Train  DESCENDING  PLOTS = (ROC);

    MODEL default_flag =
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        dti_ratio                         
        months_since_last_delinquency
        pct_accounts_current
		loan_to_income_ratio
		log_annual_income
        home_ownership_woe
        age_group_woe
        delinquency_flag
        high_utilisation_flag

        / LACKFIT
          OUTROC = WORK.ROC_Final;

               
    SCORE DATA = WORK.Test
          OUT  = WORK.Dataquest_Submission;

    TITLE "Final Logistic Regression Model trained on 100% of Work.Train and scored on Work.Test";
RUN;

ODS OUTPUT CLOSE;


/* Print the final model coefficients for the report */

PROC PRINT DATA = WORK.Final_Model_Betas;
    TITLE " Final model: parameter estimates (beta coefficients)";
RUN;



/* ============================================================================
   SECTION 4 FORMAT AND VERIFY THE SUBMISSION FILE
   ----------------------------------------------------------------------------
  
   Three sanity checks are run:
     1. Probability range check: no value should be below 0 or above 1.
     2. Row count check: the submission should have exactly as many rows as
        WORK.Test.
     3. Preview: print the first 20 rows for a visual spot-check.
   ============================================================================ */

DATA WORK.Submission_Final;
    SET WORK.Dataquest_Submission;
    default_probability = P_1;
    KEEP applicant_id_hash  default_probability;
    FORMAT default_probability 8.6;
RUN;


/* Sanity check 1: summary statistics on the predicted probabilities */
PROC MEANS DATA = WORK.Submission_Final  N  NMISS  MIN  MEAN  MAX;
    VAR default_probability;
    TITLE " Submission sanity check: summary statistics on predicted probabilities";
RUN;


/* Sanity check 2: count rows outside the valid [0, 1] range (result should be 0) */
PROC SQL;
    SELECT COUNT(*) AS Rows_Outside_Valid_Range
    FROM WORK.Submission_Final
    WHERE default_probability < 0
       OR default_probability > 1;
    TITLE "Rows with invalid probability value (this count must equal 0)";
QUIT;


/* Sanity check 3: confirm the submission has the same row count as WORK.Test */
PROC SQL;
    SELECT COUNT(*) AS Submission_Row_Count FROM WORK.Submission_Final;
    SELECT COUNT(*) AS Test_Set_Row_Count    FROM WORK.Test;
    TITLE " Row count verification: submission file must match the test set exactly";
QUIT;


/* Preview: print the first 20 rows of the submission file for a visual check */
PROC PRINT DATA = WORK.Submission_Final (OBS = 20);
    TITLE " Submission file preview: first 20 rows";
RUN;


ODS RTF CLOSE;
