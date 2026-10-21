{% macro default__hash(field) -%}
  sha1_binary(cast({{ field }} as {{ api.Column.translate_type('string') }}))
{%- endmacro %}