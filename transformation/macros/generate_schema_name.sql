{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}

    {%- if target.name|lower == 'prod' -%}
        {%- if custom_schema_name is none -%}
            {{ default_schema }}
        {%- else -%}
            {{ custom_schema_name | trim }}
        {%- endif -%}

    {%- else -%}
        {%- set developer_name = target.user.split('@')[0].replace('.', '_') -%}
        {%- if custom_schema_name is none -%}
            {{ default_schema }}__{{ developer_name }}
        {%- else -%}
            {{ custom_schema_name | trim }}__{{ developer_name }}
        {%- endif -%}

    {%- endif -%}
{%- endmacro %}