

/* Verify the first 50 rowa of the imported dataset */
PROC PRINT DATA = Work.DataQuest(OBS = 50);
TITLE "Data verification: First 50 rows of Clean Dataset";
RUN;

/* Sepearting the dataset into Train and Test */
DATA Work.Train Work.Test;
SET Work.DataQuest;
IF SET = 'train' THEN OUTPUT Work.Train;
ELSE IF SET = 'test' THEN OUTPUT Work.Test;
RUN;

/* verifying the Train datset */
PROC PRINT DATA = Work.Train(OBS = 50);
    TITLE "DATA Verification: First 50 train rows";
RUN;

/* Split WORK.Train into 80% Local Training and 20% Local Validation */
DATA WORK.Local_Train WORK.Local_Val;
    SET WORK.Train;
    
    /* Set a seed so the random split is exactly the same every time you run it */
    CALL streaminit(12345); 
    
    /* Give every row a random ticket between 0.0 and 1.0 */
    random_ticket = rand('uniform');
    
    /* If the ticket is 0.80 or less, send to the 80% Training group */
    IF random_ticket <= 0.80 THEN OUTPUT WORK.Local_Train;
    
    /* If the ticket is higher than 0.80, send to the 20% Validation group */
    ELSE OUTPUT WORK.Local_Val;
    
    /* Drop the temporary ticket column so it doesn't mess up our model */
    DROP random_ticket;
RUN;


/* Let SAS automatically pick the best features from your Feature Engineering */
proc logistic data=WORK.Local_Train descending plots=roc;
    
    /* Put EVERY variable you want to test in here (including age!) */
    model default_flag = 
        age
        loan_to_income_ratio
        credit_risk_index
        log_annual_income
        log_loan_amount
        home_ownership_woe
        region_woe
        loan_purpose_woe
        /* The MAGIC CODE: Stepwise Selection */
        / selection=stepwise slentry=0.05 slstay=0.05; 
        
    /* Grade the 20% Practice Exam to get your score */
    score data=WORK.Local_Val out=WORK.Val_Predictions;
run;

/* The TRUE Kitchen Sink Stepwise Selection */
proc logistic data=WORK.Local_Train descending plots=roc;
    
    /* Testing ALL valid variables to find the ultimate combination */
    model default_flag = 
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
        home_ownership_woe
        region_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        ever_delinquent
        credit_risk_index
        log_annual_income
        log_loan_amount
        / selection=stepwise slentry=0.05 slstay=0.05; 
        
    /* Grade the 20% Practice Exam */
    score data=WORK.Local_Val out=WORK.Val_Predictions;
run;


/* The Kitchen Sink: BACKWARD Elimination Method */
proc logistic data=WORK.Local_Train descending plots=roc;
    
    /* Testing ALL valid variables */
    model default_flag = 
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
        home_ownership_woe
        region_woe
        loan_purpose_woe
        email_domain_type_woe
        phone_verified_woe
        loan_to_income_ratio
        delinquency_flag
        high_utilisation_flag
        ever_delinquent
        credit_risk_index
        log_annual_income
        log_loan_amount
        /* The MAGIC CODE: Backward Selection */
        / selection=backward slstay=0.05; 
        
    /* Grade the 20% Practice Exam */
    score data=WORK.Local_Val out=WORK.Val_Predictions_Backward;
run;


/* THE FINAL CRAM: Training on 100% of the Data */
proc logistic data=WORK.Train descending;
    
    /* Our mathematically proven 17-variable Dream Team */
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
        log_annual_income;
        
    /* Grade the actual Hackathon Test Set! */
    score data=WORK.Test out=WORK.Hackathon_Submission;
run;
