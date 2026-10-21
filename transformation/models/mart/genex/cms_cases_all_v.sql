{{ save_history(
    input_rel = ref('stg_genexodsdmcmsusr__cms_cases_all_v'),
    key_column = 'CASEID,Case_Number,Date_of_Referral,reopenid,udw_referral_id',
    diff_column = 'record_hash_key',
    load_ts_column = 'LOAD_TS_UTC'
) }}