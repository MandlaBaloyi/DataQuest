/* ============================================================
   IMPROVED LOGISTIC REGRESSION — FULL PIPELINE
   Goal: Push AUC from 0.68 toward 0.82 ceiling
   Approach: IV selection → WoE binning → feature engineering
             → diagnostics → scorecard scaling
   ============================================================ */


/* ============================================================
   PHASE 1: INFORMATION VALUE (IV) — VARIABLE RANKING
   Why: IV tells you which variables are predictively useful
        before you run a single regression.
        IV < 0.02  = useless  | 0.02-0.1  = weak
        0.1-0.3   = medium   | 0.3+      = strong
   ============================================================ */

/* Step 1a: Macro to compute IV for a BINARY variable */
/* (works on already-WoE variables or any flag column)   */
%macro calc_iv_binary(var=, data=WORK.Local_Train, target=default_flag);
    proc freq data=&data noprint;
        tables &var * &target / out=_freq_ outpct;
    run;
    data _iv_;
        set _freq_;
        where &target in (0,1);
        retain events non_events;
    run;
    proc sql;
        create table _iv_calc_ as
        select
            "&var" as Variable,
            sum(case when &target=1 then count else 0 end) as Events,
            sum(case when &target=0 then count else 0 end) as NonEvents,
            sum(count) as Total
        from _freq_;
    quit;
%mend;


/* Step 1b: Cleaner approach — PROC FREQ IV for ALL binary flags at once */
/* Run this to get a quick IV table for your flag/categorical variables  */

proc sql;
    create table WORK.IV_Summary as
    select
        variable,
        sum(woe * (pct_events - pct_nonevents)) as IV
    from (
        /* delinquency_flag */
        select 'delinquency_flag'     as variable,
               delinquency_flag       as bin,
               count(*)               as n,
               sum(default_flag)      as events,
               count(*) - sum(default_flag) as nonevents,
               sum(default_flag) / (select sum(default_flag) from WORK.Local_Train) as pct_events,
               (count(*)-sum(default_flag)) /
                   (select sum(1-default_flag) from WORK.Local_Train) as pct_nonevents,
               log(
                   (sum(default_flag) / (select sum(default_flag) from WORK.Local_Train)) /
                   ((count(*)-sum(default_flag)) /
                       (select sum(1-default_flag) from WORK.Local_Train))
               ) as woe
        from WORK.Local_Train
        group by delinquency_flag

        union all

        select 'high_utilisation_flag' as variable,
               high_utilisation_flag,
               count(*),
               sum(default_flag),
               count(*) - sum(default_flag),
               sum(default_flag) / (select sum(default_flag) from WORK.Local_Train),
               (count(*)-sum(default_flag)) /
                   (select sum(1-default_flag) from WORK.Local_Train),
               log(
                   (sum(default_flag) / (select sum(default_flag) from WORK.Local_Train)) /
                   ((count(*)-sum(default_flag)) /
                       (select sum(1-default_flag) from WORK.Local_Train))
               )
        from WORK.Local_Train
        group by high_utilisation_flag

        union all

        select 'ever_delinquent'        as variable,
               ever_delinquent,
               count(*),
               sum(default_flag),
               count(*) - sum(default_flag),
               sum(default_flag) / (select sum(default_flag) from WORK.Local_Train),
               (count(*)-sum(default_flag)) /
                   (select sum(1-default_flag) from WORK.Local_Train),
               log(
                   (sum(default_flag) / (select sum(default_flag) from WORK.Local_Train)) /
                   ((count(*)-sum(default_flag)) /
                       (select sum(1-default_flag) from WORK.Local_Train))
               )
        from WORK.Local_Train
        group by ever_delinquent
    ) all_vars
    group by variable
    order by IV desc;
quit;

proc print data=WORK.IV_Summary;
    title "Information Value Summary — Binary & Categorical Variables";
run;


/* ============================================================
   PHASE 2: FINE CLASSING — BIN CONTINUOUS VARS THEN COMPUTE WoE
   Why: Logistic regression assumes linearity in the log-odds.
        Binning + WoE replaces each raw variable with its
        monotone log-odds signal, which satisfies this assumption
        and handles outliers automatically.
   ============================================================ */

/* Step 2a: Create optimal bins using PROC HPBIN (equal-frequency) */
/* Uses 10 bins initially — you inspect and merge later (coarse classing) */

proc hpbin data=WORK.Local_Train output=WORK.Train_Binned numbin=10;
    input
        credit_utilisation_pct
        dti_ratio
        interest_rate
        loan_to_income_ratio
        num_delinquencies_2yr
        months_since_last_delinquency
        num_hard_inquiries_6mo
        pct_accounts_current
        months_since_oldest_account
        employment_length_years
        num_open_accounts
        log_annual_income
        age
        / numbin=10;
    target default_flag / level=nominal;
run;

/* Step 2b: Inspect event rates by bin — look for monotonicity */
/* Run this for EACH variable to decide how to coarse-class it */

%macro bin_event_rate(var_bin=, data=WORK.Train_Binned);
    proc freq data=&data;
        tables &var_bin * default_flag / norow nocol nopercent out=_temp_;
    run;
    proc sort data=_temp_; by &var_bin; run;
    proc print data=_temp_;
        title "Event rate by bin: &var_bin";
    run;
%mend;

%bin_event_rate(var_bin=BIN_credit_utilisation_pct);
%bin_event_rate(var_bin=BIN_interest_rate);
%bin_event_rate(var_bin=BIN_dti_ratio);
%bin_event_rate(var_bin=BIN_loan_to_income_ratio);
%bin_event_rate(var_bin=BIN_num_delinquencies_2yr);
%bin_event_rate(var_bin=BIN_months_since_last_delinquency);


/* Step 2c: Manual coarse classing — merge bins to enforce monotonicity */
/* Edit these cutpoints AFTER reviewing the event-rate tables above.     */
/* These are ILLUSTRATIVE; adjust based on your actual bin output.       */

data WORK.Train_WoE WORK.Val_WoE;
    set WORK.Local_Train (in=a) WORK.Local_Val (in=b);

    /* --- credit_utilisation_pct --- */
    if      credit_utilisation_pct < 20  then util_grp = 1;
    else if credit_utilisation_pct < 40  then util_grp = 2;
    else if credit_utilisation_pct < 60  then util_grp = 3;
    else if credit_utilisation_pct < 80  then util_grp = 4;
    else                                      util_grp = 5;

    /* --- interest_rate --- */
    if      interest_rate < 8   then rate_grp = 1;
    else if interest_rate < 11  then rate_grp = 2;
    else if interest_rate < 14  then rate_grp = 3;
    else if interest_rate < 18  then rate_grp = 4;
    else                             rate_grp = 5;

    /* --- dti_ratio --- */
    if      dti_ratio < 0.10 then dti_grp = 1;
    else if dti_ratio < 0.20 then dti_grp = 2;
    else if dti_ratio < 0.30 then dti_grp = 3;
    else if dti_ratio < 0.40 then dti_grp = 4;
    else                          dti_grp = 5;

    /* --- loan_to_income_ratio --- */
    if      loan_to_income_ratio < 0.15 then lti_grp = 1;
    else if loan_to_income_ratio < 0.30 then lti_grp = 2;
    else if loan_to_income_ratio < 0.50 then lti_grp = 3;
    else if loan_to_income_ratio < 0.70 then lti_grp = 4;
    else                                     lti_grp = 5;

    /* --- num_delinquencies_2yr — treat 0 separately, high counts matter */
    if      num_delinquencies_2yr = 0  then delinq_grp = 1;
    else if num_delinquencies_2yr = 1  then delinq_grp = 2;
    else if num_delinquencies_2yr <= 3 then delinq_grp = 3;
    else                                    delinq_grp = 4;

    /* --- months_since_last_delinquency — missing = never delinquent → best bin */
    if      months_since_last_delinquency = . then mdlq_grp = 1;   /* never */
    else if months_since_last_delinquency > 60 then mdlq_grp = 2;  /* old */
    else if months_since_last_delinquency > 24 then mdlq_grp = 3;  /* medium */
    else                                             mdlq_grp = 4;  /* recent */

    /* --- num_hard_inquiries_6mo --- */
    if      num_hard_inquiries_6mo = 0  then inq_grp = 1;
    else if num_hard_inquiries_6mo <= 2 then inq_grp = 2;
    else if num_hard_inquiries_6mo <= 4 then inq_grp = 3;
    else                                     inq_grp = 4;

    /* --- pct_accounts_current (low % = more delinquent) --- */
    if      pct_accounts_current >= 95 then curr_grp = 1;
    else if pct_accounts_current >= 85 then curr_grp = 2;
    else if pct_accounts_current >= 70 then curr_grp = 3;
    else                                    curr_grp = 4;

    /* --- age --- */
    if      age < 25 then age_grp = 1;
    else if age < 35 then age_grp = 2;
    else if age < 45 then age_grp = 3;
    else if age < 55 then age_grp = 4;
    else                  age_grp = 5;

    if a then output WORK.Train_WoE;
    else      output WORK.Val_WoE;
run;


/* Step 2d: Compute WoE values FROM TRAINING DATA ONLY */
/* Then apply those same values to both train and validation */

%macro compute_woe(var=, grp=, data=WORK.Train_WoE);
    proc sql noprint;
        create table _woe_&grp._ as
        select
            &grp,
            sum(default_flag) / (select sum(default_flag) from &data) as pct_ev,
            (count(*) - sum(default_flag)) /
                (select sum(1-default_flag) from &data) as pct_nev,
            log(
                (sum(default_flag) / (select sum(default_flag) from &data)) /
                ((count(*) - sum(default_flag)) /
                    (select sum(1-default_flag) from &data))
            ) as WoE_&grp,
            sum(default_flag)             as events,
            count(*)-sum(default_flag)    as nonevents,
            count(*)                      as n,
            (sum(default_flag)/count(*))  as event_rate
        from &data
        group by &grp
        order by &grp;
    quit;

    proc print data=_woe_&grp._;
        title "WoE table: &var (&grp)";
    run;
%mend;

%compute_woe(var=credit_utilisation_pct,         grp=util_grp);
%compute_woe(var=interest_rate,                  grp=rate_grp);
%compute_woe(var=dti_ratio,                      grp=dti_grp);
%compute_woe(var=loan_to_income_ratio,           grp=lti_grp);
%compute_woe(var=num_delinquencies_2yr,          grp=delinq_grp);
%compute_woe(var=months_since_last_delinquency,  grp=mdlq_grp);
%compute_woe(var=num_hard_inquiries_6mo,         grp=inq_grp);
%compute_woe(var=pct_accounts_current,           grp=curr_grp);
%compute_woe(var=age,                            grp=age_grp);


/* Step 2e: Merge WoE values back onto train and validation datasets */

proc sql;
    create table WORK.Train_WoE2 as
    select t.*,
           a.WoE_util_grp,
           b.WoE_rate_grp,
           c.WoE_dti_grp,
           d.WoE_lti_grp,
           e.WoE_delinq_grp,
           f.WoE_mdlq_grp,
           g.WoE_inq_grp,
           h.WoE_curr_grp,
           i.WoE_age_grp
    from WORK.Train_WoE t
    left join _woe_util_grp_   a on t.util_grp   = a.util_grp
    left join _woe_rate_grp_   b on t.rate_grp   = b.rate_grp
    left join _woe_dti_grp_    c on t.dti_grp    = c.dti_grp
    left join _woe_lti_grp_    d on t.lti_grp    = d.lti_grp
    left join _woe_delinq_grp_ e on t.delinq_grp = e.delinq_grp
    left join _woe_mdlq_grp_   f on t.mdlq_grp   = f.mdlq_grp
    left join _woe_inq_grp_    g on t.inq_grp    = g.inq_grp
    left join _woe_curr_grp_   h on t.curr_grp   = h.curr_grp
    left join _woe_age_grp_    i on t.age_grp    = i.age_grp;

    create table WORK.Val_WoE2 as
    select t.*,
           a.WoE_util_grp,
           b.WoE_rate_grp,
           c.WoE_dti_grp,
           d.WoE_lti_grp,
           e.WoE_delinq_grp,
           f.WoE_mdlq_grp,
           g.WoE_inq_grp,
           h.WoE_curr_grp,
           i.WoE_age_grp
    from WORK.Val_WoE t
    left join _woe_util_grp_   a on t.util_grp   = a.util_grp
    left join _woe_rate_grp_   b on t.rate_grp   = b.rate_grp
    left join _woe_dti_grp_    c on t.dti_grp    = c.dti_grp
    left join _woe_lti_grp_    d on t.lti_grp    = d.lti_grp
    left join _woe_delinq_grp_ e on t.delinq_grp = e.delinq_grp
    left join _woe_mdlq_grp_   f on t.mdlq_grp   = f.mdlq_grp
    left join _woe_inq_grp_    g on t.inq_grp    = g.inq_grp
    left join _woe_curr_grp_   h on t.curr_grp   = h.curr_grp
    left join _woe_age_grp_    i on t.age_grp    = i.age_grp;
quit;


/* ============================================================
   PHASE 3: FEATURE ENGINEERING — DOMAIN-INFORMED INTERACTIONS
   Why: Credit risk is multiplicative, not just additive.
        A person with HIGH utilisation AND HIGH DTI is FAR
        riskier than either alone. Interactions capture this.
   ============================================================ */

data WORK.Train_FE WORK.Val_FE;
    set WORK.Train_WoE2 (in=a) WORK.Val_WoE2 (in=b);

    /* ---- Interaction 1: Utilisation × DTI
       Both measures of "borrower is stretched" — together they're
       more powerful than either alone */
    util_x_dti = credit_utilisation_pct * dti_ratio;

    /* ---- Interaction 2: Interest rate × Loan-to-income
       High rate + high loan burden = compounding repayment stress */
    rate_x_lti = interest_rate * loan_to_income_ratio;

    /* ---- Interaction 3: Delinquency flag × Utilisation
       Someone who has been delinquent AND is maxing credit = very high risk */
    delinq_x_util = delinquency_flag * credit_utilisation_pct;

    /* ---- Interaction 4: Inquiries × Delinquency flag
       Desperate credit seeking + poor history */
    inq_x_delinq = num_hard_inquiries_6mo * delinquency_flag;

    /* ---- Interaction 5: ever_delinquent × DTI
       Past problems + current strain */
    ever_delinq_x_dti = ever_delinquent * dti_ratio;

    /* ---- Polynomial: credit_utilisation squared
       The log-odds of default accelerates steeply above ~70% utilisation */
    util_sq = credit_utilisation_pct ** 2;

    /* ---- Polynomial: interest_rate squared
       Similarly non-linear — very high rates signal subprime risk */
    rate_sq = interest_rate ** 2;

    /* ---- Polynomial: dti_ratio squared */
    dti_sq = dti_ratio ** 2;

    /* ---- Ratio: delinquencies per open account
       Normalises delinquencies by credit exposure breadth */
    if num_open_accounts > 0 then
        delinq_per_account = num_delinquencies_2yr / num_open_accounts;
    else delinq_per_account = 0;

    /* ---- Credit stress index (composite) */
    credit_stress = (credit_utilisation_pct / 100)
                  + (dti_ratio)
                  + (delinquency_flag * 0.5)
                  + (high_utilisation_flag * 0.3);

    /* ---- Log transforms for skewed continuous variables */
    /* (already have log_annual_income and log_loan_amount) */
    if num_delinquencies_2yr > 0 then log_delinq = log(num_delinquencies_2yr + 1);
    else log_delinq = 0;

    if total_revolving_balance > 0 then log_revbal = log(total_revolving_balance + 1);
    else log_revbal = 0;

    /* ---- Months since last delinquency: cap at 120 & scale */
    /* Missing = never delinquent; set to a very safe 120 months */
    if months_since_last_delinquency = . then mdlq_capped = 120;
    else mdlq_capped = min(months_since_last_delinquency, 120);

    if a then output WORK.Train_FE;
    else      output WORK.Val_FE;
run;


/* ============================================================
   PHASE 4: LOGISTIC REGRESSION ON WoE + ENGINEERED FEATURES
   Model A: Pure WoE inputs (most interpretable, scorecard-ready)
   Model B: WoE + interactions (may gain 2-4 AUC points)
   ============================================================ */

/* --- Model A: WoE-only (scorecard aligned) --- */
proc logistic data=WORK.Train_WoE2 descending plots=(roc(id=prob) effect);
    model default_flag =
        WoE_util_grp
        WoE_rate_grp
        WoE_dti_grp
        WoE_lti_grp
        WoE_delinq_grp
        WoE_mdlq_grp
        WoE_inq_grp
        WoE_curr_grp
        WoE_age_grp
        home_ownership_woe
        region_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        / selection=stepwise slentry=0.05 slstay=0.05
          lackfit outroc=WORK.ROC_ModelA;

    /* Hosmer-Lemeshow goodness of fit */
    /* lackfit option above enables this */

    score data=WORK.Val_WoE2 out=WORK.Pred_ModelA (rename=(P_1=p_modelA));
    title "Model A — WoE Stepwise Logistic Regression";
run;


/* --- Model B: WoE + domain interactions --- */
proc logistic data=WORK.Train_FE descending plots=(roc(id=prob));
    model default_flag =
        WoE_util_grp
        WoE_rate_grp
        WoE_dti_grp
        WoE_lti_grp
        WoE_delinq_grp
        WoE_mdlq_grp
        WoE_inq_grp
        WoE_curr_grp
        WoE_age_grp
        home_ownership_woe
        region_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        util_x_dti
        rate_x_lti
        delinq_x_util
        inq_x_delinq
        ever_delinq_x_dti
        credit_stress
        log_delinq
        log_revbal
        mdlq_capped
        delinq_per_account
        / selection=stepwise slentry=0.05 slstay=0.05
          lackfit outroc=WORK.ROC_ModelB;

    score data=WORK.Val_FE out=WORK.Pred_ModelB (rename=(P_1=p_modelB));
    title "Model B — WoE + Engineered Features Stepwise";
run;


/* ============================================================
   PHASE 5: DIAGNOSTICS — AUC, KS STATISTIC, GINI COEFFICIENT
   These are the three numbers that matter for credit models.
   ============================================================ */

/* Step 5a: AUC from the ROC datasets produced above */
proc sql;
    /* Model A AUC (area under ROC = c-statistic) */
    select max(_c_) as AUC_ModelA
    from WORK.ROC_ModelA;

    /* Model B AUC */
    select max(_c_) as AUC_ModelB
    from WORK.ROC_ModelB;
quit;


/* Step 5b: KS Statistic — maximum separation between
            cumulative event and non-event distributions.
            KS > 30 is acceptable; > 40 is good for credit. */

%macro ks_stat(pred_data=, prob_var=, target=default_flag, label=);
    proc npar1way data=&pred_data edf;
        class &target;
        var &prob_var;
        ods output KSStatistic = _ks_&label._;
    run;

    data _ks_display_;
        set _ks_&label._;
        KS_pct = nValue1 * 100;
        label KS_pct = "KS Statistic (%)";
    run;

    proc print data=_ks_display_;
        title "KS Statistic — &label";
    run;
%mend;

%ks_stat(pred_data=WORK.Pred_ModelA, prob_var=p_modelA, label=ModelA);
%ks_stat(pred_data=WORK.Pred_ModelB, prob_var=p_modelB, label=ModelB);


/* Step 5c: Gini Coefficient = 2 × AUC − 1 */
/* (Computed from the PROC LOGISTIC c-statistic output)  */
/* A Gini of 0.40 = AUC of 0.70; Gini of 0.64 = AUC 0.82 */


/* Step 5d: Decile analysis — lift table */
/* Shows how much better the model is than random across score bands */

%macro decile_lift(pred_data=, prob_var=, target=default_flag, label=);
    /* Rank predictions into 10 equal groups */
    proc rank data=&pred_data out=_ranked_ descending groups=10;
        var &prob_var;
        ranks decile;
    run;

    proc sql;
        create table WORK.Decile_&label. as
        select
            decile + 1                    as Decile,
            count(*)                      as N,
            sum(&target)                  as Events,
            count(*) - sum(&target)       as NonEvents,
            sum(&target) / count(*)       as Event_Rate,
            sum(&target) / (select sum(&target) from _ranked_) as Pct_Events_Captured
        from _ranked_
        group by decile
        order by decile;
    quit;

    proc print data=WORK.Decile_&label.;
        format Event_Rate Pct_Events_Captured percent8.2;
        title "Decile Lift Table — &label";
    run;
%mend;

%decile_lift(pred_data=WORK.Pred_ModelA, prob_var=p_modelA, label=ModelA);
%decile_lift(pred_data=WORK.Pred_ModelB, prob_var=p_modelB, label=ModelB);


/* Step 5e: Hosmer-Lemeshow test (already triggered by lackfit option above) */
/* p-value > 0.05 means the model is well-calibrated (good).
   p-value < 0.05 means predictions are systematically off (bad). */


/* Step 5f: Population Stability Index (PSI)
   Checks whether validation set has same distribution as training.
   PSI < 0.10: stable | 0.10-0.25: slight shift | > 0.25: major shift */

%macro psi(train=, val=, prob_var=, label=);
    proc rank data=&train out=_tr_rank_ descending groups=10;
        var &prob_var; ranks decile;
    run;
    proc rank data=&val out=_v_rank_ descending groups=10;
        var &prob_var; ranks decile;
    run;

    proc sql;
        create table _tr_dist_ as
        select decile, count(*)/( select count(*) from _tr_rank_) as pct_train
        from _tr_rank_ group by decile;

        create table _v_dist_ as
        select decile, count(*)/( select count(*) from _v_rank_) as pct_val
        from _v_rank_ group by decile;

        create table WORK.PSI_&label. as
        select t.decile,
               t.pct_train,
               v.pct_val,
               (v.pct_val - t.pct_train) * log(v.pct_val / t.pct_train) as psi_bin
        from _tr_dist_ t
        join _v_dist_  v on t.decile = v.decile;

        select sum(psi_bin) as Total_PSI
        from WORK.PSI_&label.;
    quit;

    proc print data=WORK.PSI_&label.;
        title "PSI — &label (want < 0.10)";
    run;
%mend;

/* Note: score both train and validation with same model first */
/* Then run PSI to confirm no distribution shift */


/* Step 5g: Multicollinearity check among WoE inputs */
/* VIF > 5 is a warning; > 10 means the variable should be dropped */

proc reg data=WORK.Train_WoE2;
    model default_flag =
        WoE_util_grp
        WoE_rate_grp
        WoE_dti_grp
        WoE_lti_grp
        WoE_delinq_grp
        WoE_mdlq_grp
        WoE_inq_grp
        WoE_curr_grp
        WoE_age_grp
        home_ownership_woe
        loan_purpose_woe
        / vif tol;
    title "VIF Check — WoE Inputs (want VIF < 5)";
run;
quit;


/* ============================================================
   PHASE 6: CROSS-VALIDATION — 5-FOLD
   Why: A single 80/20 split can be lucky or unlucky.
        5-fold CV gives you a stable estimate of true AUC.
   ============================================================ */

data WORK.Train_CV;
    set WORK.Train_WoE2;
    call streaminit(42);
    fold = ceil(rand('uniform') * 5);   /* assign each row to fold 1-5 */
run;

%macro cross_validate(folds=5);
    %do f = 1 %to &folds;
        data _cv_train_;
            set WORK.Train_CV;
            where fold ^= &f;
        run;
        data _cv_val_;
            set WORK.Train_CV;
            where fold = &f;
        run;

        proc logistic data=_cv_train_ descending noprint;
            model default_flag =
                WoE_util_grp WoE_rate_grp WoE_dti_grp
                WoE_lti_grp WoE_delinq_grp WoE_mdlq_grp
                WoE_inq_grp WoE_curr_grp WoE_age_grp
                home_ownership_woe loan_purpose_woe
                / outroc=_roc_f&f._;
            score data=_cv_val_ out=_pred_f&f._;
        run;

        proc sql noprint;
            select max(_c_) into :auc_f&f.
            from _roc_f&f.;
        quit;
        %put Fold &f AUC = &&auc_f&f;
    %end;
%mend;

%cross_validate(folds=5);

/* After running, compute mean AUC across folds manually or via PROC MEANS */


/* ============================================================
   PHASE 7: FINAL SCORECARD SCALING
   Converts log-odds from logistic regression into integer score points.
   Standard formula: Score = Offset + Factor × log(odds)
   Typical setup: 600 points = odds of 50:1 (2% default rate)
                  every 20 points = double the odds (PDO = 20)
   ============================================================ */

/* Step 7a: Extract model coefficients */
/* After running your FINAL model on 100% of WORK.Train, use ODS to get betas */

ods output ParameterEstimates = WORK.Betas;
proc logistic data=WORK.Train_WoE2 descending;
    model default_flag =
        WoE_util_grp
        WoE_rate_grp
        WoE_dti_grp
        WoE_lti_grp
        WoE_delinq_grp
        WoE_mdlq_grp
        WoE_inq_grp
        WoE_curr_grp
        WoE_age_grp
        home_ownership_woe
        loan_purpose_woe;
    title "Final Model — Full Training Data";
run;
ods output close;


/* Step 7b: Define scaling constants */
%let target_score = 600;    /* score at base odds              */
%let base_odds    = 50;     /* 50:1 odds = ~2% default rate    */
%let pdo          = 20;     /* points to double the odds       */

data _null_;
    Factor = &pdo / log(2);       /* = PDO / ln(2) ≈ 28.85     */
    Offset = &target_score - Factor * log(&base_odds);
    call symputx('Factor', Factor);
    call symputx('Offset', Offset);
    put "Factor = " Factor;
    put "Offset = " Offset;
run;


/* Step 7c: Compute points contribution per variable × bin        */
/* Points = Factor × (WoE × beta_coefficient) + Offset/n_vars    */
/* n_vars = number of variables in the model                      */

data WORK.Scorecard_Points;
    set WORK.Betas;
    where Variable ^= 'Intercept';
    /* Each variable's per-bin points = Factor × beta × WoE_bin_value */
    /* The offset is distributed equally across n predictors         */
    n_vars   = 11;  /* update to match your final model variable count */
    Points_Contribution = &Factor * Estimate;
    Offset_Share        = &Offset / n_vars;
    /* Final score for a given record = sum of (beta_i × WoE_i) × Factor + Offset */
run;

proc print data=WORK.Scorecard_Points;
    title "Scorecard — Coefficient × Factor (points weight per variable)";
run;


/* Step 7d: Score EVERY record with the final integer scorecard */

data WORK.Final_Scored;
    set WORK.Train_WoE2;  /* swap to WORK.Test for submission */

    /* Paste in exact beta estimates from WORK.Betas after running above */
    /* Replace 0.000 with the actual estimate values */
    b_intercept    =  0.000;   /* <-- replace */
    b_util         =  0.000;
    b_rate         =  0.000;
    b_dti          =  0.000;
    b_lti          =  0.000;
    b_delinq       =  0.000;
    b_mdlq         =  0.000;
    b_inq          =  0.000;
    b_curr         =  0.000;
    b_age          =  0.000;
    b_home         =  0.000;
    b_purpose      =  0.000;

    /* Compute log-odds */
    log_odds = b_intercept
             + b_util    * WoE_util_grp
             + b_rate    * WoE_rate_grp
             + b_dti     * WoE_dti_grp
             + b_lti     * WoE_lti_grp
             + b_delinq  * WoE_delinq_grp
             + b_mdlq    * WoE_mdlq_grp
             + b_inq     * WoE_inq_grp
             + b_curr    * WoE_curr_grp
             + b_age     * WoE_age_grp
             + b_home    * home_ownership_woe
             + b_purpose * loan_purpose_woe;

    /* Predicted probability */
    p_default = 1 / (1 + exp(-log_odds));

    /* Integer credit score (higher = safer) */
    credit_score = round(&Offset + &Factor * log_odds, 1);

    /* Risk band */
    if      credit_score >= 650 then risk_band = 'Low';
    else if credit_score >= 580 then risk_band = 'Medium';
    else if credit_score >= 500 then risk_band = 'High';
    else                             risk_band = 'Very High';

    format p_default percent8.2;
    keep applicant_id_hash credit_score risk_band p_default default_flag;
run;

proc freq data=WORK.Final_Scored;
    tables risk_band;
    title "Score Distribution by Risk Band";
run;

proc means data=WORK.Final_Scored n mean std min max;
    var credit_score;
    title "Credit Score Distribution Summary";
run;


/* ============================================================
   PHASE 8: MODEL COMPARISON — SIDE BY SIDE
   ============================================================ */

proc sql;
    create table WORK.Model_Comparison as
    select
        'Baseline (raw vars, stepwise)'          as Model,
        0.68                                      as Val_AUC,
        .                                         as KS,
        .                                         as Gini
    union all
    select 'Model A (WoE inputs)', ., ., .
    union all
    select 'Model B (WoE + interactions)', ., ., .;
quit;
/* Fill in AUC/KS/Gini from macro outputs above, then print this table */

proc print data=WORK.Model_Comparison;
    title "Model Comparison Summary";
run;


/* ============================================================
   NOTES ON WHAT TO CHECK / ITERATE
   ============================================================
   1. If IV < 0.02 for a WoE variable, drop it from the model.
   2. If event rate per bin is NOT monotone, merge bins until it is.
   3. If VIF > 5, consider dropping the more correlated of the pair.
   4. If Hosmer-Lemeshow p < 0.05, your probability calibration is off —
      consider Platt scaling or a calibration data step.
   5. If PSI > 0.25, something is very different between train and val —
      check for data leakage or sampling issues.
   6. If a WoE variable gets a NEGATIVE coefficient in logistic regression,
      this indicates a monotonicity violation — re-examine and rebin.
   7. Target AUC improvement order of magnitude:
      WoE transformation alone:     +0.03 to +0.05
      Better binning:               +0.01 to +0.02
      Domain interactions:          +0.02 to +0.04
      Composite stress features:    +0.01 to +0.03
      Total realistic gain:        ~0.07 to 0.14  (from 0.68 → up to 0.80)
   ============================================================ */
