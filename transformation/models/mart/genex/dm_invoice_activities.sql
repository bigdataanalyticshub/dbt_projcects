{{ save_history(
    input_rel = ref('stg_genexodsdmcms__dm_invoice_activities'),
    key_column = 'inv_act_id',
    diff_column = 'record_hash_key',
    load_ts_column = 'LOAD_TS_UTC'
) }}