{{
  config(
    materialized='table'
  )
}}

WITH

stg_dwctshex__nco_test_mapping as (
    select * from {{ ref('stg_dwctshex__nco_test_mapping') }}
),

stg_genexodscareconnect__care_connect_v_t as (
    select * from {{ ref('stg_genexodscareconnect__care_connect_v_t') }}
),

care_connect_calls AS (
    SELECT
        cc.*,
        COALESCE(
            NULLIF(TRIM(cc.DISPOSITION_DESCRIPTION), ''),
            NULLIF(TRIM(cc.DISPOSITION_GROUP_DESCRIPTION), ''),
            NULLIF(TRIM(cc.DISPOSITION_GROUP_NAME), '')
        ) AS POST_DISPOSITION_RAW,
        COALESCE(
            NULLIF(TRIM(cc.PRE_DISPOSITION_DESCRIPTION), ''),
            NULLIF(TRIM(cc.PRE_DISPOSITION_GROUP_DESCRIPTION), ''),
            NULLIF(TRIM(cc.PRE_DISPOSITION_GROUP_NAME), '')
        ) AS PRE_DISPOSITION_RAW
    FROM stg_genexodscareconnect__care_connect_v_t AS cc
),

standardized_calls AS (
    SELECT
        cc.*,
        CASE
            WHEN UPPER(cc.POST_DISPOSITION_RAW) LIKE '%911%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%POISON%'
                THEN '911'
            WHEN UPPER(cc.POST_DISPOSITION_RAW) LIKE '%EMERGENCY ROOM%'
                OR UPPER(cc.POST_DISPOSITION_RAW) = 'ER'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE 'ER %'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '% ER'
                THEN 'ER'
            WHEN UPPER(cc.POST_DISPOSITION_RAW) LIKE '%URGENT CARE%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%UCC%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%CLINIC%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%OCC MED%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%DENTIST%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%LAB%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%DOCTOR%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%PRIMARY CARE%'
                OR UPPER(cc.POST_DISPOSITION_RAW) LIKE '%TELEMED%'
                THEN 'Clinic'
            WHEN UPPER(cc.POST_DISPOSITION_RAW) LIKE '%SELF%CARE%'
                THEN 'Self-Care'
            ELSE cc.POST_DISPOSITION_RAW
        END AS POST_DISPOSITION_CATEGORY,
        CASE
            WHEN UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%911%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%POISON%'
                THEN '911'
            WHEN UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%EMERGENCY ROOM%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) = 'ER'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE 'ER %'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '% ER'
                THEN 'ER'
            WHEN UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%URGENT CARE%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%UCC%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%CLINIC%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%OCC MED%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%DENTIST%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%LAB%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%DOCTOR%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%PRIMARY CARE%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%TELEMED%'
                THEN 'Clinic'
            WHEN UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%SELF%CARE%'
                OR UPPER(cc.PRE_DISPOSITION_RAW) LIKE '%FNOL%'
                THEN 'Self-Care'
            ELSE cc.PRE_DISPOSITION_RAW
        END AS PRE_DISPOSITION_CATEGORY,
        CASE
            WHEN cc.DATE_OF_CALL IS NULL OR cc.DATE_OF_INJURY IS NULL THEN 'Unknown'
            WHEN DATEDIFF('day', cc.DATE_OF_INJURY, cc.DATE_OF_CALL) <= 1 THEN 'Within 24 Hours'
            WHEN DATEDIFF('day', cc.DATE_OF_INJURY, cc.DATE_OF_CALL) <= 3 THEN '2-3 Days'
            WHEN DATEDIFF('day', cc.DATE_OF_INJURY, cc.DATE_OF_CALL) <= 7 THEN '4-7 Days'
            WHEN DATEDIFF('day', cc.DATE_OF_INJURY, cc.DATE_OF_CALL) <= 30 THEN '8-30 Days'
            ELSE '30+ Days'
        END AS LAG_TIME_GROUPED
    FROM care_connect_calls AS cc
),

final AS (SELECT

    --------- CALL IDENTIFIERS & STATUS ---------
        cc.REFERENCE_NO_IN_REPORTS,          -- unique per reportable call; the grain
        cc.TRIAGE_ID,                        -- NOT unique; 1 triage -> many calls
        cc.TRIAGE_SEQ_NUMBER,                -- > 1 = call-back / follow-up leg
        cc.MASTER_CONTACT_ID,                -- only populated from Dec 2025 forward
        cc.CLAIM_NO,
        cc.EXTERNAL_REFERENCE_ID,
        cc.GB_LOSS_REFERENCE_NO,
        cc.CALL_STATUS,
        cc.CALL_PATHWAY,                     -- Triage / FNOL / Non Work Related Triage
        1 AS CALL_VOLUME,                    -- SUM this for call counts
        IFF(TRY_TO_NUMBER(cc.TRIAGE_SEQ_NUMBER) > 1, 1, 0) AS CALL_BACK_FLAG, -- 1 = call-back / SUM this for call-back volume.

    --------- CLIENT & ACCOUNT IDENTIFIERS ---------
        -- Normalized exact match to the NCO mapping, keyed on CUSTOMER_NAME.
        COALESCE(nco.SP_NAME, 'N/A') AS SP_NAME,
        cc.REPORT_ID,
        cc.REPORT_ID_NAME,
        cc.C_CODE,
        cc.C_CODE_ORG,
        cc.E_CODE,
        cc.E_CODE_NAME,
        cc.CUSTOMER_NAME,                    -- primary client field for SP_NAME mapping
        cc.ACCOUNT_NAME,                     -- alternate client field
        cc.CLIENT_NAME,
        cc.CLIENT_GROUP_DESCRIPTION,
        cc.CLIENT_SEGMENT_DESCRIPTION,
        cc.EMPLOYER_NAME,
        cc.TPA_ID,
        cc.TPA_NAME,

    --------- KEY DATES & LAG TIME ---------
        cc.DATE_OF_CALL,                     -- THE date field for this table
        DATE_TRUNC('month', cc.DATE_OF_CALL)::DATE AS REPORT_MONTH,
        cc.CALL_START_TIME,
        cc.CALL_END_TIME,
        cc.DATE_OF_INJURY,
        cc.DATE_REPORTED_TO_SUPERVISOR,
        cc.INJURY_TO_REPORT_LAG_TIME,
        cc.LAG_TIME_GROUPED,                 -- date of injury / date of call -> call lag bucket

    --------- INJURY & CLINICAL DETAILS ---------
        cc.EMPLOYEE_FULL_NAME,
        cc.BODY_PART,
        cc.INJURY_TYPE,
        cc.CAUSE_OF_INJURY,
        cc.MAIN_COMPLAINT_DESCRIPTION,
        cc.INJURY_STATEMENT,
        cc.STATE_OF_JURISDICTION,            -- USE THIS for state analysis (juris state)
        cc.LANGUAGE,
        cc.INTERPRETER,
        cc.NURSE,

    --------- PRE- & POST-DISPOSITION ---------
        cc.PRE_DISPOSITION_CODE,
        cc.PRE_DISPOSITION_RAW AS PRE_DISPOSITION_DESCRIPTION,
        cc.PRE_DISPOSITION_GROUP_DESCRIPTION,
        cc.PRE_DISPOSITION_CATEGORY,         -- derived field: Self-Care / Clinic / ER / 911
        cc.DISPOSITION_CODE AS POST_DISPOSITION_CODE,
        cc.POST_DISPOSITION_RAW AS POST_DISPOSITION_DESCRIPTION,
        cc.DISPOSITION_GROUP_DESCRIPTION AS POST_DISPOSITION_GROUP_DESCRIPTION,
        cc.POST_DISPOSITION_CATEGORY,        -- derived field: Self-Care / Clinic / ER / 911
        IFF(
            COALESCE(cc.PRE_DISPOSITION_CATEGORY, 'Unknown')
                <> COALESCE(cc.POST_DISPOSITION_CATEGORY, 'Unknown'),
            1,
            0
        ) AS DISPOSITION_CHANGED_FLAG,       -- nurse redirected the caller's plan
        cc.CC_DISPOSITION_OVERRIDE,
        cc.OVERRIDE_REASON,
        cc.PROVIDER_OVERRIDE_REASON,
        cc.TELEMEDICINE_REASON,
        cc.DIRECTION_OF_CARE,

    --------- SAVINGS ---------
        cc.AMOUNT_SAVED                      -- modeled care-steering savings; SUM this

    FROM standardized_calls AS cc
    LEFT JOIN stg_dwctshex__nco_test_mapping AS nco
        ON nco.NORM_OTHER_NAMES = REPLACE(LOWER(cc.CUSTOMER_NAME), ' ', '')
        AND nco.RN_NORM = 1
    WHERE 1=1

        -- STANDARD EXCLUSIONS
        AND cc.EXCLUDE_CALL_FLAG IS NULL
        AND cc.CANCEL_REASON IS NULL
)

select * from final