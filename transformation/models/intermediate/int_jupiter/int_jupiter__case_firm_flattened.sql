-- LEGAL CASE FIRM ROLES: one row per distinct case / contact / role / firm link
-- Includes all five contact-role types. Representatives without a resolved
-- firm are retained with legal_firm_matched = false.

{{
  config(
    materialized='view'
  )
}}

WITH

stg_jupiterodsglobal__legalcasecontactxref as (
    select * from {{ ref('stg_jupiterodsglobal__legalcasecontactxref') }}
),

stg_jupiterodsglobal__legalcasecontacttype as (
    select * from {{ ref('stg_jupiterodsglobal__legalcasecontacttype') }}
),

stg_jupiterodsglobal__legalfirmcontactxref as (
    select * from {{ ref('stg_jupiterodsglobal__legalfirmcontactxref') }}
),

stg_jupiterodsglobal__legalfirm as (
    select * from {{ ref('stg_jupiterodsglobal__legalfirm') }}
),

final as (
    select distinct
        case_contact.ODSCUSTOMERID as ods_customer_id,
        case_contact.LEGALCASE as legal_case_id,
        case_contact.CONTACT as contact_id,
        case_contact.CONTACTROLE as legal_firm_role_id,
        role.CODE as legal_firm_role_code,
        role.DESCRIPTION as legal_firm_role_description,
        firm_contact.LEGALFIRM as legal_firm_id,
        firm.NAME as legal_firm_name,
        firm.ID is not null as legal_firm_matched,
        case_contact.CREATEDATE as case_contact_linked_at
    from stg_jupiterodsglobal__legalcasecontactxref case_contact
    left join stg_jupiterodsglobal__legalcasecontacttype role
        on role.ID = case_contact.CONTACTROLE
        and role.ODSCUSTOMERID = case_contact.ODSCUSTOMERID
    left join stg_jupiterodsglobal__legalfirmcontactxref firm_contact
        on firm_contact.CONTACT = case_contact.CONTACT
        and firm_contact.ODSCUSTOMERID = case_contact.ODSCUSTOMERID
    left join stg_jupiterodsglobal__legalfirm firm
        on firm.ID = firm_contact.LEGALFIRM
        and firm.ODSCUSTOMERID = firm_contact.ODSCUSTOMERID
)

select * from final