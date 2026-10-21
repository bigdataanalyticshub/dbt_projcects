{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = ['occurred_at', 'actor_id', 'target_id', 'target_type'],
    on_schema_change = 'sync_all_columns'
) }}

WITH base AS (

    SELECT *
    FROM  {{ source('dwctshexraw', 'hex_auditlog') }} h

    {% if is_incremental() %}
      WHERE h.loaded_at >=
            (SELECT MAX(loaded_at) FROM {{ this }})
    {% endif %}

)

SELECT
    -- ingestion metadata
    base.file_name,
    base.loaded_at,

    -- event info
    base.raw_json:action::string              AS action,
    base.raw_json:occurred_at::timestamp_ntz  AS occurred_at,
    base.raw_json:version::number             AS version,

    -- actor
    base.raw_json:actor.id::string            AS actor_id,
    base.raw_json:actor.type::string          AS actor_type,
    base.raw_json:actor.metadata.email::string AS actor_email,
    base.raw_json:actor.metadata.workspace::string AS workspace,
    base.raw_json:actor.metadata.workspaceId::string AS workspace_id,

    -- context
    base.raw_json:context.location::string    AS ip_address,
    base.raw_json:context.user_agent::string  AS user_agent,

    -- result metadata
    base.raw_json:metadata.result::string     AS result,
    base.raw_json:metadata.failureReason::string AS failure_reason,

    -- target
    t.value:id::string                        AS target_id,
    t.value:type::string                      AS target_type,
    t.value:metadata.representation::string   AS target_representation_raw

FROM base
CROSS JOIN LATERAL FLATTEN(
  input => CASE
             WHEN TYPEOF(base.raw_json:targets) = 'ARRAY'
             THEN base.raw_json:targets
             ELSE ARRAY_CONSTRUCT(base.raw_json:targets)
           END
) t
