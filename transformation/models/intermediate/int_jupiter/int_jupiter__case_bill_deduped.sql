version: 2

models:

  ###########################################################################
  # INT_JUPITER__CASE_FIRM_FLATTENED
  # Flattens case contact → role → firm contact → firm into one row per
  # distinct (case, contact, role, firm) association.
  ###########################################################################
  - name: int_jupiter__case_firm_flattened
    description: >
      Flattened case-contact-firm chain. One row per distinct association
      of a legal case, contact, role type, and firm. Contacts without a
      resolved firm are retained with legal_firm_matched = false.
      Consumed by jupiter_bill_level and jupiter_legal_case.
    columns:
      - name: ods_customer_id
        tests:
          - not_null
      - name: legal_case_id
        tests:
          - not_null
      - name: contact_id
        tests:
          - not_null
      - name: legal_firm_role_code
        description: "PROVATTRNY, DEFATTRNY, CLIENTREP, INSREP, AGENCYREP. NULL if role lookup failed."
      - name: legal_firm_matched
        description: "True when the contact resolved to a firm in the LEGALFIRM table."
      - name: case_contact_linked_at
        description: "CREATEDATE from the case-contact xref. Used for most-recently-linked firm selection."

  ###########################################################################
  # INT_JUPITER__CASE_BILL_DEDUPED
  # Deduplicates the raw case ↔ bill xref into one row per pair with
  # aggregated flags.
  ###########################################################################
  - name: int_jupiter__case_bill_deduped
    description: >
      Deduplicated case-to-bill bridge. One row per (ods_customer_id,
      legal_case_id, bill_header_id). Aggregates ISPRIMARY and
      EXCLUDEFROMSETTLEMENTPCNT flags across duplicate source rows.
      Consumed by jupiter_bill_level.
    columns:
      - name: ods_customer_id
        tests:
          - not_null
      - name: legal_case_id
        tests:
          - not_null
      - name: bill_header_id
        tests:
          - not_null
      - name: source_link_count
        description: "Number of raw xref rows that were deduplicated into this pair. Expected 1 for most rows."