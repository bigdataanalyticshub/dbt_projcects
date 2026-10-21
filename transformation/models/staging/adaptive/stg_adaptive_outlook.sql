-- Outlook / reforecast: long, one row per (account, level, item, customer, month).
{{ flatten_adaptive_fact('adaptive', 'adaptive_outlook_raw', 'OUTLOOK', none, 'Outlook') }}
