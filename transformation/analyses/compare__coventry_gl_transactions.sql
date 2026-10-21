{% set old_relation = adapter.get_relation(
      database = "DATAWAREHOUSE_CTS",
      schema = "ECB_FIN_SILVER",
      identifier = "coventry_gl_transactions"
) -%}

{% set dbt_relation = ref('coventry_gl_transactions') %}

{% if execute %}

{{ audit_helper.compare_relations (
    a_relation = old_relation,
    b_relation = dbt_relation,
    primary_key = 'trns_id'
) }}

{% endif %}