/* ====================================================================
   FINAL LOGISTIC REGRESSION PIPELINE — UPDATED FOR NEW CLEAN DATASET
   Starting point: Work.DataQuest (cleaned, WoE-encoded,
   log-transformed, imputed, and feature-engineered)

   CHANGES vs original pipeline
   ─────────────────────────────────────────────────────────────────────
   REMOVED  : interest_rate  (not in new dataset)
   REMOVED  : region_woe     (not in new dataset)
   ADDED    : age_group_woe  (new WoE categorical now available)
   KEPT RAW : annual_income, loan_amount present in data but modelled
              via log_annual_income / log_loan_amount as before
   ─────────────────────────────────────────────────────────────────────
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

/* Check for any remaining missing values in the model-ready variables
   NOTE: interest_rate and region_woe removed; age_group_woe added     */
proc means data=WORK.DataQuest nmiss n mean std min max;
    var age
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
        /* WoE categoricals — updated list */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe           /* NEW */
        /* binary engineered flags */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent;
    title "Missing value check — all model-ready variables";
run;


/* ====================================================================
   SECTION 2 — SPLIT TRAIN FROM TEST USING THE SET COLUMN
   ==================================================================== */

DATA WORK.Train WORK.Test;
    SET WORK.DataQuest;
    SET_lower = lowcase(SET);
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
    select 'Local_Val', count(*), sum(default_flag), mean(default_flag)
    from WORK.Local_Val;
    title "Local Train / Validation split verification";
quit;


/* ====================================================================
   SECTION 4 — FOUR CANDIDATE MODELS ON LOCAL_TRAIN

   PREDICTOR POOL — 24 variables (was 25; interest_rate & region_woe
   removed; age_group_woe added — net change: −1)
   ──────────────────────────────────────────────────────────────────
   Continuous / ratio (15):
     age, employment_length_years, num_open_accounts,
     num_delinquencies_2yr, total_revolving_balance,
     credit_utilisation_pct, months_since_oldest_account,
     num_hard_inquiries_6mo, dti_ratio,
     months_since_last_delinquency, pct_accounts_current,
     months_at_current_address, loan_to_income_ratio,
     credit_risk_index, log_annual_income, log_loan_amount

   WoE categoricals (5):
     home_ownership_woe, loan_purpose_woe,
     email_domain_type_woe, phone_verified_woe, age_group_woe

   Binary flags (3):
     delinquency_flag, high_utilisation_flag, ever_delinquent
   ==================================================================== */

/* ----------------------------------------------------------------
   MODEL 1 — STEPWISE: all 24 available predictors, data decides
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
        dti_ratio                           /* interest_rate removed */
        months_since_last_delinquency
        pct_accounts_current
        months_at_current_address
        loan_to_income_ratio
        credit_risk_index
        log_annual_income
        log_loan_amount
        /* WoE-encoded categoricals (region_woe removed; age_group_woe added) */
        home_ownership_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        age_group_woe                       /* NEW */
        /* binary engineered flags */
        delinquency_flag
        high_utilisation_flag
        ever_delinquent
        / selection=stepwise slentry=0.05 slstay=0.05
          lackfit
          outroc=WORK.ROC_M1;

    score data=WORK.Local_Val out=WORK.Pred_M1 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M1;
    title "Model 1 — Stepwise (all 24 predictors)";
run;

data WORK.Pred_M1;
    set WORK.Pred_M1 (rename=(P_1=prob_M1));
run;


/* ----------------------------------------------------------------
   MODEL 2 — BACKWARD ELIMINATION: all 24 predictors, prune back
   ---------------------------------------------------------------- */
proc logistic data=WORK.Local_Train descending plots=(roc);
    model default_flag =
        age employment_length_years num_open_accounts num_delinquencies_2yr
        total_revolving_balance credit_utilisation_pct months_since_oldest_account
        num_hard_inquiries_6mo dti_ratio months_since_last_delinquency
        pct_accounts_current months_at_current_address loan_to_income_ratio
        credit_risk_index log_annual_income log_loan_amount
        home_ownership_woe loan_purpose_woe
        email_domain_type_woe phone_verified_woe age_group_woe
        delinquency_flag high_utilisation_flag ever_delinquent
        / selection=backward slstay=0.05
          lackfit outroc=WORK.ROC_M2;

    score data=WORK.Local_Val out=WORK.Pred_M2 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M2;
    title "Model 2 — Backward elimination (all 24 predictors)";
run;

data WORK.Pred_M2;
    set WORK.Pred_M2 (rename=(P_1=prob_M2));
run;


/* ----------------------------------------------------------------
   MODEL 3 — THEORY-DRIVEN: 16 domain-informed variables
   (was 17; interest_rate removed — replaced with age_group_woe
   to preserve breadth of signal coverage)
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
        dti_ratio                           /* interest_rate removed */
        months_since_last_delinquency
        pct_accounts_current
        home_ownership_woe
        loan_purpose_woe
        age_group_woe                       /* NEW replacement signal */
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        log_annual_income
        / lackfit outroc=WORK.ROC_M3;

    score data=WORK.Local_Val out=WORK.Pred_M3 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M3;
    title "Model 3 — Theory-driven (17 domain variables, updated set)";
run;

data WORK.Pred_M3;
    set WORK.Pred_M3 (rename=(P_1=prob_M3));
run;


/* ----------------------------------------------------------------
   MODEL 4 — PARSIMONIOUS LEAN: 7 strongest predictors
   (was 8; interest_rate removed and not replaced — keep it lean)
   Purpose: clean interpretable baseline.
   ---------------------------------------------------------------- */
proc logistic data=WORK.Local_Train descending plots=(roc);
    model default_flag =
        credit_utilisation_pct
        dti_ratio                           /* interest_rate removed */
        num_delinquencies_2yr
        months_since_last_delinquency
        delinquency_flag
        log_annual_income
        loan_to_income_ratio
        / lackfit outroc=WORK.ROC_M4;

    score data=WORK.Local_Val out=WORK.Pred_M4 (keep=applicant_id_hash default_flag P_1);
    ods output ParameterEstimates = WORK.Betas_M4;
    title "Model 4 — Lean (7 core predictors)";
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
proc sql;
    create table WORK.AUC_Summary as
    select 'M1 Stepwise'        as Model, max(_c_) as AUC format=8.4 from WORK.ROC_M1 union all
    select 'M2 Backward'               , max(_c_)           from WORK.ROC_M2 union all
    select 'M3 Theory-driven'          , max(_c_)           from WORK.ROC_M3 union all
    select 'M4 Lean'                   , max(_c_)           from WORK.ROC_M4
    order by AUC desc;
quit;

proc print data=WORK.AUC_Summary noobs;
    title "AUC comparison — all four candidate models on Local_Val";
run;


/* ---- 5b: KS statistic ---- */
%macro ks_stat(pred=, prob=, label=);
    proc npar1way data=&pred edf noprint;
        class default_flag;
        var &prob;
        ods output KSStatistic = _ks_;
    run;
    data _ks_;
        set _ks_;
        where Label1 = 'D';
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


/* ---- 5c: Gini coefficient ---- */
data WORK.Gini_Summary;
    set WORK.AUC_Summary;
    Gini = round((2 * AUC - 1), 0.0001);
    format Gini 8.4;
run;

proc print data=WORK.Gini_Summary noobs;
    title "AUC and Gini — all four models";
run;


/* ---- 5d: Decile lift table ---- */
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


/* ---- 5e: Calibration check (predicted vs actual by decile) ---- */
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

/* Run on best-performing model after reviewing AUC table.
   Replace M3 with your winner if a different model wins.          */
%calibration_check(pred=WORK.Pred_M3, prob=prob_M3, label=M3);


/* ---- 5f: Multicollinearity check (VIF) on Model 3 variable set ----
   Updated to reflect removed (interest_rate) and added (age_group_woe)
   variables.  VIF > 5 = concern; VIF > 10 = drop or merge.        */

proc reg data=WORK.Local_Train;
    model default_flag =
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
        age_group_woe                       /* NEW */
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        log_annual_income
        / vif tol;
    title "VIF / tolerance — Model 3 variable set (want VIF < 5)";
run;
quit;


/* ====================================================================
   SECTION 6 — FINAL MODEL ON 100% OF WORK.TRAIN
   After choosing your winner from Section 5, retrain on ALL of Train.

   IMPORTANT: replace the variable list below with the variables from
   YOUR winning model. The example below uses the updated M3 set.
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
        dti_ratio                           /* interest_rate removed */
        months_since_last_delinquency
        pct_accounts_current
        home_ownership_woe
        loan_purpose_woe
        age_group_woe                       /* NEW */
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

/* Step 6c: Odds ratios for interpretability report */
proc logistic data=WORK.Train descending;
    model default_flag =
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
    oddsratio / cl=wald;
    title "Final model — odds ratios with 95% Wald confidence intervals";
run;


/* ====================================================================
   SECTION 7 — FORMAT AND VERIFY SUBMISSION FILE
   ==================================================================== */

data WORK.Submission_Final;
    set WORK.Hackathon_Submission;
    default_probability = P_1;
    keep applicant_id_hash default_probability;
    format default_probability 8.6;
run;

proc means data=WORK.Submission_Final n nmiss min mean max;
    var default_probability;
    title "Submission sanity check — predicted probabilities";
run;

proc sql;
    select count(*) as Out_of_Range
    from WORK.Submission_Final
    where default_probability < 0 or default_probability > 1;
    title "Rows with invalid probability (should be 0)";
quit;

proc sql;
    select count(*) as Submission_Rows from WORK.Submission_Final;
    select count(*) as Test_Rows        from WORK.Test;
    title "Row count check — submission vs test set";
quit;

proc print data=WORK.Submission_Final (obs=20);
    title "Submission file — first 20 rows";
run;


/* ====================================================================
   SECTION 8 — MODEL SUMMARY TABLE FOR REPORT
   Fill in metric values after running Sections 4 and 5.
   ==================================================================== */

data WORK.Model_Report;
    infile datalines dlm='|';
    input Model $35. Variables AUC_Val 8.4 KS_Val 8.2 Gini 8.4 HL_pval 8.4;
    datalines;
Baseline (original code)         | 17 | 0.6800 | .    | 0.3600 | .
M1 Stepwise (all 24)             | 24 | .      | .    | .      | .
M2 Backward (all 24)             | 24 | .      | .    | .      | .
M3 Theory-driven (17, updated)   | 17 | .      | .    | .      | .
M4 Lean (7)                      |  7 | .      | .    | .      | .
Final (winner retrained)         |  . | .      | .    | .      | .
;
run;

proc print data=WORK.Model_Report noobs;
    title "Model comparison summary — fill in from Section 5 output";
run;


/* ====================================================================
   NOTES — HOW TO INTERPRET RESULTS
   ====================================================================
   AUC (c-statistic):
     0.50 = random | 0.68 = baseline | 0.70+ = improvement | 0.82 = LGBM ceiling

   KS statistic:
     KS > 30 = acceptable | KS > 40 = good

   Gini coefficient:
     Gini = 2 × AUC − 1 | Gini > 0.40 means AUC > 0.70

   Hosmer-Lemeshow (lackfit):
     p > 0.05 = well-calibrated | p < 0.05 = systematic mismatch

   Decile lift:
     Decile 1 should capture > 25-30% of all defaults
     Lift in decile 1 should be > 3× the random default rate

   Variable sign check — each beta should match credit theory:
     credit_utilisation_pct        → POSITIVE (higher util  = more risk)
     dti_ratio                     → POSITIVE (higher burden = more risk)
     num_delinquencies_2yr         → POSITIVE (more delinquencies = more risk)
     months_since_last_delinquency → NEGATIVE (longer ago = safer)
     pct_accounts_current          → NEGATIVE (more current = safer)
     log_annual_income             → NEGATIVE (higher income = safer)
     delinquency_flag              → POSITIVE (has delinquency = more risk)
     high_utilisation_flag         → POSITIVE (maxed credit = more risk)
     loan_to_income_ratio          → POSITIVE (higher burden = more risk)
     age_group_woe                 → CHECK SIGN against WoE encoding direction

   NOTE: interest_rate was removed because it is not present in the
   updated dataset. dti_ratio and loan_to_income_ratio together
   capture most of the debt-burden signal that interest_rate carried.

   NOTE: age_group_woe replaces region_woe in the categorical set.
   Inspect its WoE values in the source data to confirm the sign
   direction is meaningful before trusting the coefficient.
   ==================================================================== */
