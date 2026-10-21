-- Actuals: long, one row per (account, level, item, customer, month).
{{ flatten_adaptive_fact('adaptive', 'adaptive_actuals_raw', 'ACTUAL', none, 'Actuals') }}
