/* ============================================================================
   SECTION 4 — DATA PREPARATION, MULTICOLLINEARITY CHECKS, AND MODEL BUILDING
   ----------------------------------------------------------------------------
   Purpose   : Prepare the dataset, validate variable quality, check for
               multicollinearity, and train four candidate logistic regression
               models on the local training split.

   Datasets  : WORK.DataQuest  — full labelled dataset (train + test rows)
               WORK.Train      — rows where SET = 'train'
               WORK.Test       — rows where SET = 'test'
               WORK.Local_Train — 80% random split of WORK.Train (model fitting)
               WORK.Local_Val   — 20% random split of WORK.Train (model evaluation)

   Author    : [Your Name]
   Date      : [Today's Date]
   ============================================================================ */


/* ============================================================================
   STEP 4.1 — ROW COUNT AND DEFAULT RATE BY DATASET SPLIT
   ----------------------------------------------------------------------------
   Check that the train / test flag is balanced and that the default rate is
   consistent across splits.  A large difference in default rates between splits
   would indicate the split was not random.
   ============================================================================ */

PROC FREQ DATA = WORK.DataQuest;
    TABLES SET * default_flag / NOCOL NOPERCENT;
    TITLE "Step 4.1 — Row counts and default rates by dataset split (train vs test)";
RUN;


/* ============================================================================
   STEP 4.2 — MISSING VALUE CHECK ACROSS ALL MODEL-READY VARIABLES
   ----------------------------------------------------------------------------
   Before modelling, every variable should have zero missing values.
   NMISS = number of missing observations.  If NMISS > 0 for any variable,
   return to the feature engineering step and impute or drop those rows.
   ============================================================================ */

PROC MEANS DATA = WORK.DataQuest NMISS N MEAN STD MIN MAX;
    VAR
        /* --- Continuous and ratio features --- */
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

        /* --- Weight-of-Evidence encoded categorical variables --- */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* --- Binary engineered indicator flags --- */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent;

    TITLE "Step 4.2 — Missing value check across all model-ready variables (NMISS should be 0 for all)";
RUN;


/* ============================================================================
   STEP 4.3 — SPLIT WORK.DataQuest INTO TRAIN AND TEST SETS
   ----------------------------------------------------------------------------
   The SET variable identifies whether each row belongs to the train or test
   population.  We convert it to lowercase first to guard against mixed-case
   values such as 'Train', 'TRAIN', or 'train' being treated differently.
   ============================================================================ */

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

    TITLE "Step 4.3 — Train and Test split verification (row counts and default rates)";
QUIT;


/* ============================================================================
   STEP 4.4 — CREATE LOCAL TRAIN (80%) AND LOCAL VALIDATION (20%) SPLITS
   ----------------------------------------------------------------------------
   We hold out 20% of WORK.Train as a local validation set so we can compare
   candidate models without touching the blind test set (WORK.Test).

   CALL STREAMINIT(2024) sets the random seed so the split is reproducible.
   Anyone running this code with seed 2024 will get the same split.
   ============================================================================ */

DATA WORK.Local_Train  WORK.Local_Val;
    SET WORK.Train;
    CALL STREAMINIT(2024);                   /* Fix the random seed for reproducibility */

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

    TITLE "Step 4.4 — Local Train / Validation split verification (80% / 20%)";
QUIT;


/* ============================================================================
   STEP 4.5 — CORRELATION MATRIX
   ----------------------------------------------------------------------------
   High pairwise correlations (|r| > 0.70) between predictors indicate
   potential multicollinearity.  Variables that are highly correlated carry
   redundant information and can destabilise coefficient estimates.
   Use this output to flag pairs for investigation before the VIF check.
   ============================================================================ */

PROC CORR DATA = WORK.Local_Train NOSIMPLE;
    VAR
        /* --- Continuous and ratio features --- */
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

        /* --- Weight-of-Evidence encoded categorical variables --- */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* --- Binary engineered indicator flags --- */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent;

    TITLE "Step 4.5 — Pairwise correlation matrix (flag |r| > 0.70 for follow-up)";
RUN;


/* ============================================================================
   STEP 4.6 — FIRST MULTICOLLINEARITY CHECK: FULL VARIABLE LIST (VIF and TOL)
   ----------------------------------------------------------------------------
   NOTE FOR REVIEWERS:
   PROC LOGISTIC does not produce Variance Inflation Factor (VIF) statistics
   in this version of SAS.  As a standard workaround, we run PROC REG on the
   same dependent variable and predictor set for the sole purpose of extracting
   VIF and Tolerance diagnostics.  The linear regression coefficients themselves
   are not used or interpreted.

   Interpretation thresholds:
     VIF < 5           = acceptable
     5 <= VIF < 10     = moderate concern — monitor
     VIF >= 10         = severe multicollinearity — remove or merge the variable
     Tolerance (TOL)   = 1 / VIF  (close to 0 = problematic)
   ============================================================================ */

PROC REG DATA = WORK.Local_Train;
    MODEL default_flag =
        /* --- Continuous and ratio features --- */
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

        /* --- Weight-of-Evidence encoded categorical variables --- */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* --- Binary engineered indicator flags --- */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent

        / VIF TOL;

    TITLE "Step 4.6 — First VIF check: full variable list (identify variables to remove)";
QUIT;


/* ============================================================================
   STEP 4.7 — SECOND MULTICOLLINEARITY CHECK: CLEANED VARIABLE LIST
   ----------------------------------------------------------------------------
   Three variables were removed after reviewing Step 4.6 output:

     ever_delinquent          — zero or near-zero variance; causes listwise
                                deletion and unstable estimates.
     credit_risk_index        — severe multicollinearity (VIF > 11); this is a
                                composite index built from other predictors
                                already in the model.
     months_since_oldest_account — Pearson r = 0.95 with age_group_woe;
                                   the two variables carry essentially the
                                   same information.

   This step confirms that the remaining variables all have VIF < 5.
   ============================================================================ */

PROC REG DATA = WORK.Local_Train;
    MODEL default_flag =
        /* --- Continuous and ratio features (cleaned list) --- */
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

        /* --- Weight-of-Evidence encoded categorical variables --- */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* --- Binary engineered indicator flags --- */
        delinquency_flag
        high_utilisation_flag

        / VIF TOL;

    TITLE "Step 4.7 — Second VIF check: cleaned variable list (all VIF values should be below 5)";
QUIT;


/* ============================================================================
   STEP 4.8 — MODEL 1: STEPWISE LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Variable selection method : Stepwise
   Entry significance level  : p < 0.05  (SLENTRY)
   Stay significance level   : p < 0.05  (SLSTAY)
   Goodness-of-fit test      : Hosmer-Lemeshow (LACKFIT)
     - p > 0.05 = model is well-calibrated
     - p < 0.05 = systematic over- or under-prediction in some probability range

   Note: months_since_oldest_account is included here because its standalone
   VIF of 4.25 is acceptable; we removed it in the cleaned list only due to
   its very high correlation with age_group_woe.  Stepwise will resolve the
   redundancy automatically by selecting at most one of the two.

   Output:
     WORK.ROC_M1   — ROC curve coordinates (used to compute AUC in Section 5)
     WORK.Pred_M1  — Predicted probabilities on Local_Val
     WORK.Betas_M1 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING PLOTS = (ROC);
    MODEL default_flag =
        /* --- Continuous and ratio features --- */
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

        /* --- Weight-of-Evidence encoded categorical variables --- */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* --- Binary engineered indicator flags --- */
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

    TITLE "Step 4.8 — Model 1: Stepwise logistic regression (VIF-validated predictor set)";
RUN;

/* Rename the predicted probability column to a model-specific name
   so we can merge all four models' scores side by side later        */
DATA WORK.Pred_M1;
    SET WORK.Pred_M1 (RENAME = (P_1 = prob_M1));
RUN;


/* ============================================================================
   STEP 4.9 — MODEL 2: BACKWARD ELIMINATION LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Variable selection method : Backward elimination
   Stay significance level   : p < 0.05  (SLSTAY)

   Backward elimination starts with all predictors and removes the least
   significant one at each step until all remaining variables meet the
   stay criterion.  This often retains more variables than stepwise.

   Output:
     WORK.ROC_M2   — ROC curve coordinates
     WORK.Pred_M2  — Predicted probabilities on Local_Val
     WORK.Betas_M2 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING PLOTS = (ROC);
    MODEL default_flag =
        /* --- Continuous and ratio features --- */
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

        /* --- Weight-of-Evidence encoded categorical variables --- */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe

        /* --- Binary engineered indicator flags --- */
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

    TITLE "Step 4.9 — Model 2: Backward elimination logistic regression (VIF-validated predictor set)";
RUN;

DATA WORK.Pred_M2;
    SET WORK.Pred_M2 (RENAME = (P_1 = prob_M2));
RUN;


/* ============================================================================
   STEP 4.10 — MODEL 3: THEORY-DRIVEN LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Variable selection method : None — all 16 variables are forced into the model
   based on credit-risk domain knowledge.

   This model deliberately excludes variables that are statistically strong
   but operationally opaque (for example, email_domain_type_woe and
   phone_verified_woe), favouring variables that credit officers can explain
   to regulators and applicants.

   Output:
     WORK.ROC_M3   — ROC curve coordinates
     WORK.Pred_M3  — Predicted probabilities on Local_Val
     WORK.Betas_M3 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING PLOTS = (ROC);
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

    TITLE "Step 4.10 — Model 3: Theory-driven logistic regression (16 domain-informed variables, no automatic selection)";
RUN;

DATA WORK.Pred_M3;
    SET WORK.Pred_M3 (RENAME = (P_1 = prob_M3));
RUN;


/* ============================================================================
   STEP 4.11 — MODEL 4: PARSIMONIOUS LEAN LOGISTIC REGRESSION
   ----------------------------------------------------------------------------
   Variable selection method : None — 7 variables are forced into the model.

   This model uses only the 7 strongest predictors identified from the
   correlation matrix and stepwise output.  A lean model is easier to deploy,
   faster to score, and simpler to explain, though it may sacrifice some
   discriminatory power relative to more complex models.

   Output:
     WORK.ROC_M4   — ROC curve coordinates
     WORK.Pred_M4  — Predicted probabilities on Local_Val
     WORK.Betas_M4 — Model coefficient estimates
   ============================================================================ */

PROC LOGISTIC DATA = WORK.Local_Train DESCENDING PLOTS = (ROC);
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

    TITLE "Step 4.11 — Model 4: Parsimonious lean logistic regression (7 strongest predictors only)";
RUN;

DATA WORK.Pred_M4;
    SET WORK.Pred_M4 (RENAME = (P_1 = prob_M4));
RUN;

/* ============================================================================
   END OF SECTION 4
   Next step: run Section 5 to evaluate and compare all four models on
   the Local_Val holdout set before making any final selection.
   ============================================================================ */
