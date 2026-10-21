{% snapshot pricingprodlist__hist %}

{{
    config(
        unique_key=['productcode'],
        strategy='check',
        check_cols=[
            'productcode',
            'productfamily',
            'productsubfamily',
            'lineofbusiness',
            'businessunit',
            'pricebookname',
            'productname',
            'component',
            'package',
            'salesforcestatus',
            'componentorpackage',
            'productdescription',
            'productmanager',
            'productmanageremail',
            'pricingtype',
            'unitofmeasure',
            'listprice',
            'productcostsf',
            'marginprofile',
            'productcostsp',
            'cost_project',
            'cost_project_notes',
            'costtypempuc',
            'rgo_product',
            'rgo_sub_product',
            'rgo_sub_sub_product',
            'primaryapprover1',
            'primaryapprover1email',
            'primaryapprover2',
            'primaryapprover2email',
            'created_date'
        ]
    )
}}

select *
from  {{ ref('stg_strategy_and_planning__pricingprodlist') }}

{% endsnapshot %}