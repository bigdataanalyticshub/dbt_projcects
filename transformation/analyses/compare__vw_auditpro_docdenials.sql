{% set old_relation = adapter.get_relation(
      database = "DATAWAREHOUSE_CTS",
      schema = "AUDITPRO_STG",
      identifier = "vw_auditpro_docdenials"
) -%}

{% set dbt_relation = ref('vw_auditpro_docdenials') %}

{% if execute %}

{{ audit_helper.compare_relations (
    a_relation = old_relation,
    b_relation = dbt_relation
) }}

{% endif %}