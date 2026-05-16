/* ====================================================================
   FINAL LOGISTIC REGRESSION PIPELINE — FROM CLEAN DATASET
   Starting point: Work.DataQuest (already cleaned, WoE-encoded,
   log-transformed, imputed, and feature-engineered)
   Goal: Select the best logistic regression model, validate rigorously,
         retrain on 100% of train, score the test set.
   ==================================================================== */


/* ====================================================================
   SECTION 1 — DATA VERIFICATION
   ==================================================================== */

/* Confirm row counts and target distribution before doing anything */
proc freq data=WORK.DataQuest;
    tables SET * default_flag / nocol nopercent;
    title "Row counts and default rates by dataset split";
run;

/* Check for any remaining missing values in the model-ready variables */
proc means data=WORK.DataQuest nmiss n mean std min max;
    var age employment_length_years num_open_accounts num_delinquencies_2yr
        total_revolving_balance credit_utilisation_pct months_since_oldest_account
        num_hard_inquiries_6mo interest_rate dti_ratio months_since_last_delinquency
        pct_accounts_current months_at_current_address loan_to_income_ratio
        credit_risk_index log_annual_income log_loan_amount
        home_ownership_woe region_woe loan_purpose_woe
        email_domain_type_woe phone_verified_woe
        delinquency_flag high_utilisation_flag ever_delinquent;
    title "Missing value check — all model-ready variables";
run;


/* ====================================================================
   SECTION 2 — SPLIT TRAIN FROM TEST USING THE SET COLUMN
   ==================================================================== */

DATA WORK.Train WORK.Test;
    SET WORK.DataQuest;
    SET_lower = lowcase(SET);     /* normalise any mixed-case SET values */
    IF  SET_lower = 'train' THEN OUTPUT WORK.Train;
    ELSE IF SET_lower = 'test'  THEN OUTPUT WORK.Test;
    DROP SET_lower;
RUN;

proc sql;
    select 'Train' as Dataset, count(*) as Rows, sum(default_flag) as Defaults,
           mean(default_flag) as Default_Rate format=percent8.2
    from WORK.Train
    union all
    select 'Test', count(*), sum(default_flag), mean(default_flag)
    from WORK.Test;
    title "Train / Test split verification";
quit;


/* ====================================================================
   SECTION 3 — SPLIT WORK.TRAIN INTO 80% LOCAL TRAIN + 20% LOCAL VAL
   The validation set is your internal "exam" before touching the test set.
   Seed is fixed so every run produces the same split.
   ==================================================================== */

DATA WORK.Local_Train WORK.Local_Val;
    SET WORK.Train;
    CALL streaminit(2024);
    IF rand('uniform') <= 0.80 THEN OUTPUT WORK.Local_Train;
    ELSE                            OUTPUT WORK.Local_Val;
RUN;

proc sql;
    select 'Local_Train' as Split, count(*) as N, sum(default_flag) as Defaults,
           mean(default_flag) as Rate format=percent8.2
    from WORK.Local_Train
    union all
    select 'Local_Val',   count(*), sum(default_flag), mean(default_flag)
    from WORK.Local_Val;
    title "Local Train / Validation split verification";
quit;


/* ====================================================================
   SECTION 4 — FOUR CANDIDATE MODELS ON LOCAL_TRAIN
   We score each one onto Local_Val so we can compare on the same holdout.
   ==================================================================== */

/* ----------------------------------------------------------------
   MODEL 1 — STEPWISE: all 25 available predictors, data decides
   ---------------------------------------------------------------- */
proc logistic data=WORK.Local_Train descending plots=(roc);
    model default_flag =
        /* continuous / ratio features */
        age
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        total_revolving_balance
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        interest_rate
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        credit_risk_index
        log_annual_income
        log_loan_amount
        /* WoE-encoded categoricals */
        home_ownership_woe
        region_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        /* binary engineered flags */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent
        / selection=stepwise slentry=0.05 slstay=0.05
          lackfit          /* Hosmer-Lemeshow goodness-of-fit */
          outroc=WORK.ROC_M1;

    score data=WORK.Local_Val out=WORK.Pred_M1 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M1;
    title "Model 1 — Stepwise (all 25 predictors)";
run;

/* Rename scored probability column for clarity */
data WORK.Pred_M1;
    set WORK.Pred_M1 (rename=(P_1=prob_M1));
run;


/* ----------------------------------------------------------------
   MODEL 2 — BACKWARD ELIMINATION: all 25 predictors, prune back
   ---------------------------------------------------------------- */
proc logistic data=WORK.Local_Train descending plots=(roc);
    model default_flag =
        age employment_length_years num_open_accounts num_delinquencies_2yr
        total_revolving_balance credit_utilisation_pct months_since_oldest_account
        num_hard_inquiries_6mo interest_rate dti_ratio months_since_last_delinquency
        pct_accounts_current months_at_current_address loan_to_income_ratio
        credit_risk_index log_annual_income log_loan_amount
        home_ownership_woe region_woe loan_purpose_woe
        email_domain_type_woe phone_verified_woe
        delinquency_flag high_utilisation_flag ever_delinquent
        / selection=backward slstay=0.05
          lackfit outroc=WORK.ROC_M2;

    score data=WORK.Local_Val out=WORK.Pred_M2 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M2;
    title "Model 2 — Backward elimination (all 25 predictors)";
run;

data WORK.Pred_M2;
    set WORK.Pred_M2 (rename=(P_1=prob_M2));
run;


/* ----------------------------------------------------------------
   MODEL 3 — THEORY-DRIVEN: 17 domain-informed variables
   Selected based on credit science, not purely data-driven.
   Delinquency history + utilisation + burden + income signal.
   ---------------------------------------------------------------- */
proc logistic data=WORK.Local_Train descending plots=(roc);
    model default_flag =
        age
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        interest_rate
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        home_ownership_woe
        loan_purpose_woe
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        log_annual_income
        / lackfit outroc=WORK.ROC_M3;

    score data=WORK.Local_Val out=WORK.Pred_M3 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M3;
    title "Model 3 — Theory-driven (17 domain variables)";
run;

data WORK.Pred_M3;
    set WORK.Pred_M3 (rename=(P_1=prob_M3));
run;


/* ----------------------------------------------------------------
   MODEL 4 — PARSIMONIOUS LEAN: 8 strongest predictors only
   Purpose: establish a clean baseline; also the most interpretable.
   ---------------------------------------------------------------- */
proc logistic data=WORK.Local_Train descending plots=(roc);
    model default_flag =
        credit_utilisation_pct
        dti_ratio
        num_delinquencies_2yr
        months_since_last_delinquency
        delinquency_flag
        interest_rate
        log_annual_income
        loan_to_income_ratio
        / lackfit outroc=WORK.ROC_M4;

    score data=WORK.Local_Val out=WORK.Pred_M4 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M4;
    title "Model 4 — Lean (8 core predictors)";
run;

data WORK.Pred_M4;
    set WORK.Pred_M4 (rename=(P_1=prob_M4));
run;


/* ====================================================================
   SECTION 5 — VALIDATION DIAGNOSTICS
   Compute AUC, KS, Gini, and decile lift for EVERY model.
   Always evaluate on Local_Val — NEVER peek at Test here.
   ==================================================================== */

/* ---- 5a: AUC (c-statistic) from ROC datasets ---- */
/* PROC LOGISTIC writes the ROC table; max(_c_) = AUC              */
proc sql;
    create table WORK.AUC_Summary as
    select 'M1 Stepwise'   as Model, max(_c_) as AUC format=8.4 from WORK.ROC_M1 union all
    select 'M2 Backward'          , max(_c_)           from WORK.ROC_M2 union all
    select 'M3 Theory-driven'     , max(_c_)           from WORK.ROC_M3 union all
    select 'M4 Lean'              , max(_c_)           from WORK.ROC_M4
    order by AUC desc;
quit;

proc print data=WORK.AUC_Summary noobs;
    title "AUC comparison — all four candidate models on Local_Val";
run;


/* ---- 5b: KS statistic ----
   KS = maximum vertical separation between cumulative event and
   non-event distributions across score ranks.
   In credit: KS > 30 = acceptable; KS > 40 = good.             */

%macro ks_stat(pred=, prob=, label=);
    proc npar1way data=&pred edf noprint;
        class default_flag;
        var &prob;
        ods output KSStatistic = _ks_;
    run;
    data _ks_;
        set _ks_;
        where Label1 = 'D';         /* D statistic = KS */
        KS_pct = nValue1 * 100;
        Model  = "&label";
    run;
    proc append base=WORK.KS_All data=_ks_ force; run;
%mend;

proc delete data=WORK.KS_All; run;

%ks_stat(pred=WORK.Pred_M1, prob=prob_M1, label=M1 Stepwise);
%ks_stat(pred=WORK.Pred_M2, prob=prob_M2, label=M2 Backward);
%ks_stat(pred=WORK.Pred_M3, prob=prob_M3, label=M3 Theory-driven);
%ks_stat(pred=WORK.Pred_M4, prob=prob_M4, label=M4 Lean);

proc print data=WORK.KS_All (keep=Model KS_pct) noobs;
    title "KS statistic — all four models on Local_Val";
run;


/* ---- 5c: Gini coefficient ----
   Gini = 2 × AUC − 1.
   Equivalent to the area between the Lorenz curve and the diagonal.
   A Gini of 0.40 = AUC of 0.70.                                  */
data WORK.Gini_Summary;
    set WORK.AUC_Summary;
    Gini = round((2 * AUC - 1), 0.0001);
    format Gini 8.4;
run;

proc print data=WORK.Gini_Summary noobs;
    title "AUC and Gini — all four models";
run;


/* ---- 5d: Decile lift table ----
   Ranks scored validation records into 10 equal groups.
   Shows how much better each model is than random in the top deciles.
   A good model captures > 30% of all defaults in decile 1.         */

%macro decile_lift(pred=, prob=, label=);
    proc rank data=&pred out=_ranked_ descending groups=10;
        var &prob;
        ranks decile_rank;
    run;

    proc sql;
        create table _lift_ as
        select
            (decile_rank + 1)                                         as Decile,
            count(*)                                                  as N,
            sum(default_flag)                                         as Events,
            sum(default_flag) / count(*)                              as Event_Rate,
            (sum(default_flag) / (select sum(default_flag) from _ranked_)) as Pct_Defaults_Captured,
            (sum(default_flag) / count(*)) /
                (select mean(default_flag) from _ranked_)            as Lift
        from _ranked_
        group by decile_rank
        order by Decile;
    quit;

    data _lift_;
        set _lift_;
        Model = "&label";
        format Event_Rate Pct_Defaults_Captured percent8.2  Lift 8.2;
    run;

    proc print data=_lift_ noobs;
        title "Decile lift — &label";
    run;
%mend;

%decile_lift(pred=WORK.Pred_M1, prob=prob_M1, label=M1 Stepwise);
%decile_lift(pred=WORK.Pred_M2, prob=prob_M2, label=M2 Backward);
%decile_lift(pred=WORK.Pred_M3, prob=prob_M3, label=M3 Theory-driven);
%decile_lift(pred=WORK.Pred_M4, prob=prob_M4, label=M4 Lean);


/* ---- 5e: Hosmer-Lemeshow calibration summary ----
   Already printed by PROC LOGISTIC (lackfit option above).
   Here we also compute mean predicted vs actual by decile
   to visually confirm calibration.
   A well-calibrated model has p_predicted ≈ p_actual per group.  */

%macro calibration_check(pred=, prob=, label=);
    proc rank data=&pred out=_cal_ groups=10;
        var &prob;
        ranks cal_decile;
    run;
    proc sql;
        create table WORK.Cal_&label. as
        select
            cal_decile + 1                  as Decile,
            count(*)                        as N,
            mean(&prob)                     as Mean_Predicted format=percent8.2,
            mean(default_flag)              as Mean_Actual    format=percent8.2,
            abs(mean(&prob)-mean(default_flag)) as Abs_Error  format=8.4
        from _cal_
        group by cal_decile
        order by Decile;
    quit;
    proc print data=WORK.Cal_&label. noobs;
        title "Calibration check — &label (predicted vs actual by decile)";
    run;
%mend;

/* Run on the best-performing model after reviewing AUC table */
/* Replace M3 with whichever model wins */
%calibration_check(pred=WORK.Pred_M3, prob=prob_M3, label=M3);


/* ---- 5f: Multicollinearity check (VIF) on chosen model's variables ----
   VIF > 5 = concern; VIF > 10 = drop or merge variables.
   Use this before finalising the variable list.                    */

proc reg data=WORK.Local_Train;
    model default_flag =
        age employment_length_years num_open_accounts num_delinquencies_2yr
        credit_utilisation_pct months_since_oldest_account
        num_hard_inquiries_6mo interest_rate dti_ratio months_since_last_delinquency
        pct_accounts_current home_ownership_woe loan_purpose_woe
        loan_to_income_ratio delinquency_flag high_utilisation_flag log_annual_income
        / vif tol;
    title "VIF / tolerance — Model 3 variable set (want VIF < 5)";
run;
quit;


/* ====================================================================
   SECTION 6 — FINAL MODEL ON 100% OF WORK.TRAIN
   After choosing the winner from Section 5, retrain on ALL of Train.
   This gives the model maximum data before scoring the blind test set.

   IMPORTANT: replace the variable list below with the variables from
   YOUR winning model. The example uses the M3 theory-driven set.
   ==================================================================== */

/* Step 6a: Capture betas for the report */
ods output ParameterEstimates = WORK.Final_Betas;

proc logistic data=WORK.Train descending plots=(roc);

    /* === PASTE YOUR WINNING MODEL VARIABLE LIST HERE === */
    model default_flag =
        age
        employment_length_years
        num_open_accounts
        num_delinquencies_2yr
        credit_utilisation_pct
        months_since_oldest_account
        num_hard_inquiries_6mo
        interest_rate
        dti_ratio
        months_since_last_delinquency
        pct_accounts_current
        home_ownership_woe
        loan_purpose_woe
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        log_annual_income
        / lackfit outroc=WORK.ROC_Final;

    /* Score the blind test set in the same PROC call */
    score data=WORK.Test out=WORK.Hackathon_Submission;
    title "Final model — trained on 100% of Work.Train, scored on Work.Test";
run;

ods output close;

/* Step 6b: Print final coefficients */
proc print data=WORK.Final_Betas;
    title "Final model — parameter estimates (betas)";
run;

/* Step 6c: Compute odds ratios for interpretability report */
proc logistic data=WORK.Train descending;
    model default_flag =
        age employment_length_years num_open_accounts num_delinquencies_2yr
        credit_utilisation_pct months_since_oldest_account
        num_hard_inquiries_6mo interest_rate dti_ratio months_since_last_delinquency
        pct_accounts_current home_ownership_woe loan_purpose_woe
        loan_to_income_ratio delinquency_flag high_utilisation_flag log_annual_income;
    oddsratio / cl=wald;
    title "Final model — odds ratios with 95% Wald confidence intervals";
run;


/* ====================================================================
   SECTION 7 — FORMAT AND VERIFY SUBMISSION FILE
   ==================================================================== */

/* Keep only what is needed: applicant ID + predicted probability */
data WORK.Submission_Final;
    set WORK.Hackathon_Submission;
    default_probability = P_1;
    keep applicant_id_hash default_probability;
    format default_probability 8.6;
run;

/* Quick sanity checks on the submission */
proc means data=WORK.Submission_Final n nmiss min mean max;
    var default_probability;
    title "Submission sanity check — predicted probabilities";
run;

/* All probabilities must be between 0 and 1 */
proc sql;
    select count(*) as Out_of_Range
    from WORK.Submission_Final
    where default_probability < 0 or default_probability > 1;
    title "Rows with invalid probability (should be 0)";
quit;

/* Confirm test row count matches raw test set */
proc sql;
    select count(*) as Submission_Rows from WORK.Submission_Final;
    select count(*) as Test_Rows        from WORK.Test;
    title "Row count check — submission vs test set";
quit;

/* Print first 20 rows to visually confirm layout */
proc print data=WORK.Submission_Final (obs=20);
    title "Submission file — first 20 rows";
run;


/* ====================================================================
   SECTION 8 — MODEL SUMMARY TABLE FOR REPORT
   Consolidate all metrics into a single comparison table.
   Fill in the metric values after running Sections 4 and 5.
   ==================================================================== */

data WORK.Model_Report;
    infile datalines dlm='|';
    input Model $30. Variables AUC_Val 8.4 KS_Val 8.2 Gini 8.4 HL_pval 8.4;
    datalines;
Baseline (original code)       | 17 | 0.6800 | .    | 0.3600 | .
M1 Stepwise (all 25)           |  . | .      | .    | .      | .
M2 Backward (all 25)           |  . | .      | .    | .      | .
M3 Theory-driven (17)          | 17 | .      | .    | .      | .
M4 Lean (8)                    |  8 | .      | .    | .      | .
Final (winner retrained)       |  . | .      | .    | .      | .
;
run;

/* Replace the dots above with your actual metric values, then print */
proc print data=WORK.Model_Report noobs;
    title "Model comparison summary — fill in from Section 5 output";
run;


/* ====================================================================
   NOTES — HOW TO INTERPRET RESULTS
   ====================================================================
   AUC (c-statistic):
     0.50 = random | 0.68 = baseline | 0.70+ = improvement | 0.82 = LGBM ceiling
     Read directly from the ROC dataset: max(_c_)

   KS statistic:
     KS > 30 = acceptable for credit scoring
     KS > 40 = good
     Printed by %ks_stat macro above

   Gini coefficient:
     Gini = 2 × AUC − 1
     Gini > 0.40 means AUC > 0.70

   Hosmer-Lemeshow (lackfit):
     p > 0.05 = model is well-calibrated (good)
     p < 0.05 = systematic mismatch between predicted and actual rates

   Decile lift:
     Decile 1 (highest-risk) should capture > 3x the random default rate
     "Pct_Defaults_Captured" in decile 1 should be > 25-30% for a good model

   Variable sign check — each beta should match credit theory:
     credit_utilisation_pct      → POSITIVE (higher util = more risk)
     dti_ratio                   → POSITIVE (higher burden = more risk)
     interest_rate               → POSITIVE (riskier borrowers get higher rates)
     num_delinquencies_2yr       → POSITIVE (more delinquencies = more risk)
     months_since_last_delinquency → NEGATIVE (longer ago = safer)
     pct_accounts_current        → NEGATIVE (more current accounts = safer)
     log_annual_income           → NEGATIVE (higher income = safer)
     delinquency_flag            → POSITIVE (1 = has delinquency = more risk)
     high_utilisation_flag       → POSITIVE (1 = maxed credit = more risk)

   If any beta sign is OPPOSITE to the above, that variable has a
   monotonicity problem — investigate before using it.
   ==================================================================== */
