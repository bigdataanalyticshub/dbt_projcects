-- Adaptive version dimension, one row per version.
-- Keyed on version_id; version_name is the join key the fact carries
-- (set per source table from the OpenFlow export's versionName parameter).
select
    version_id,
    version_name,
    version_short_name,
    version_type,
    version_description,
    is_default_version,
    is_locked,
    is_virtual,
    is_predictive,
    is_folder,
    version_path,
    start_plan,
    end_plan
from {{ ref('stg_adaptive__versions') }}
