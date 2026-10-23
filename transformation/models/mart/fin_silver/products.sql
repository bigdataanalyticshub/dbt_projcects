{{
    config(
        materialized='incremental',
        unique_key='ORIGINAL_PRODUCT_ID'
    )
}}

WITH
-- Import CTEs
stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

-- Logical CTEs

-- Final CTE
final AS (
	SELECT  {{ dbt_utils.generate_surrogate_key(['PO.IRMS_PRODT_ID']) }} AS ID,
		PO.IRMS_PRODT_ID AS ORIGINAL_PRODUCT_ID,
		NULL AS LINE_OF_BUSINESS_ID,
		PO.PRODT_DESC,
		PO.RUN_ID,
		PO.LOB_REVNU_ID,
		PO.VAL_TYP_BLLNG_CALCTN_ID,
		PO.RSN_TYP_CD,
		PO.GL_ACCT_NUM,
		PO.GL_SUB_ACCT_NUM,
		PO.EFF_DT,
		PO.TRMNTN_DT,
		PO.DEFLT_FLG,
		PO.ERP_ACCT_ID,
		PO.ERP_PRODT,
		PO.ERP_PROJ,
		PO.GL_ORA_MAJOR_CD,
		PO.GL_ORA_MINOR_CD,
		PO.GL_ORA_PRODT_CD,
		PO.GL_ORA_SEGMENT,
		PO.NS_GL_ACCT_CD,
		PO.NS_CLASS_CD,
		PO.COST_CNTR
	FROM stg_irmsods__product AS PO
)

SELECT * FROM final
WHERE ORIGINAL_PRODUCT_ID IS NOT NULL