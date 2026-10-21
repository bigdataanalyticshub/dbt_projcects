-- First, let's fix the error handling in our ADM.CREATE_TABLES_FROM_VIEWS procedure.
CREATE OR REPLACE PROCEDURE ADM.CREATE_TABLES_FROM_VIEWS (
    source_schema STRING ,
    target_schema STRING ,
    view_list STRING DEFAULT NULL
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
AS
$$
def main(session, source_schema, target_schema, view_list):
    import json

    results = {
        'successful_tables': [],
        'failed_tables': [],
        'total_views_requested': 0,
        'total_tables_created': 0,
        'errors': [],
        'warnings': []
    }

    # Flag to track if we should throw an error at the end
    has_critical_errors = False

    # debug
    try:
        current_role_result = session.sql("SELECT CURRENT_ROLE()").collect()
        current_role = current_role_result[0][0]
        results['debug_info'] = {'current_role': current_role}

        secondary_roles_result = session.sql("SELECT CURRENT_SECONDARY_ROLES()").collect()
        secondary_roles = secondary_roles_result[0][0]
        results['debug_info']['secondary_roles'] = secondary_roles

    except Exception as debug_error:
        results['warnings'].append(f"Could not get debug info: {str(debug_error)}")

    try:
        # Get current database name
        current_db_result = session.sql("SELECT CURRENT_DATABASE()").collect()
        current_database = current_db_result[0][0]

        if not current_database:
            error_msg = 'No current database set. Please USE a database first.'
            results['errors'].append(error_msg)
            has_critical_errors = True
            raise Exception(error_msg)

        # Check if target schema exists - fail if it doesn''t
        try:
            schema_check_query = f"""
            SELECT SCHEMA_NAME
            FROM INFORMATION_SCHEMA.SCHEMATA
            WHERE SCHEMA_NAME = '{target_schema.upper()}'
            AND CATALOG_NAME = '{current_database}'
            """
            schema_result = session.sql(schema_check_query).collect()

            if len(schema_result) == 0:
                error_msg = f"Target schema '{target_schema}' does not exist in database '{current_database}'. Please create the schema first."
                results['errors'].append(error_msg)
                has_critical_errors = True
                raise Exception(error_msg)

        except Exception as e:
            if "does not exist" not in str(e):  # Don''t double-log the schema not found error
                error_msg = f"Failed to check if target schema {target_schema} exists: {str(e)}"
                results['errors'].append(error_msg)
                has_critical_errors = True
            raise e

        # Process view list
        if view_list is None or view_list.strip() == '':
            # If no view list provided, get all views from source schema
            views_query = f"""
            SELECT TABLE_NAME
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_SCHEMA = '{source_schema.upper()}'
            AND TABLE_CATALOG = '{current_database}'
            ORDER BY TABLE_NAME
            """

            try:
                views_result = session.sql(views_query).collect()
                ordered_views = [row[0] for row in views_result]

                if len(ordered_views) == 0:
                    error_msg = f"No views found in schema {source_schema}"
                    results['errors'].append(error_msg)
                    has_critical_errors = True
                    raise Exception(error_msg)

            except Exception as e:
                if "No views found" not in str(e):  # Don''t double-log
                    error_msg = f"Failed to query views in schema {source_schema}: {str(e)}"
                    results['errors'].append(error_msg)
                    has_critical_errors = True
                raise e
        else:
            # Parse the comma-separated view list
            ordered_views = [name.strip() for name in view_list.split(',') if name.strip()]

            if not ordered_views:
                error_msg = "View list is empty or invalid"
                results['errors'].append(error_msg)
                has_critical_errors = True
                raise Exception(error_msg)

        results['total_views_requested'] = len(ordered_views)
        results['execution_order'] = [{'order': i+1, 'view_name': view} for i, view in enumerate(ordered_views)]

        # Verify all requested views exist in source schema
        existing_views_query = f"""
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.VIEWS
        WHERE TABLE_SCHEMA = '{source_schema.upper()}'
        AND TABLE_CATALOG = '{current_database}'
        """

        try:
            existing_views_result = session.sql(existing_views_query).collect()
            existing_views = {row[0].upper() for row in existing_views_result}

            # Check for non-existent views
            missing_views = []
            for view_name in ordered_views:
                if view_name.upper() not in existing_views:
                    missing_views.append(view_name)

            if missing_views:
                error_msg = f"The following views do not exist in schema {source_schema}: {', '.join(missing_views)}"
                results['errors'].append(error_msg)
                has_critical_errors = True
                raise Exception(error_msg)

        except Exception as e:
            if "do not exist in schema" not in str(e):  # Don''t double-log
                error_msg = f"Failed to verify views exist in schema {source_schema}: {str(e)}"
                results['errors'].append(error_msg)
                has_critical_errors = True
            raise e

        # Process each view in the order specified - CONTINUE ON ERRORS
        for i, view_name in enumerate(ordered_views):
            table_result = {
                'table_name': view_name,
                'execution_order': i + 1,
                'table_created': False,
                'grant_applied': False
            }

            try:
                # Create the table from the view
                create_table_sql = f"""
                CREATE OR REPLACE TABLE {target_schema}.{view_name}
                AS SELECT * FROM {source_schema}.{view_name}
                """

                session.sql(create_table_sql).collect()
                table_result['table_created'] = True

                # Verify the table was created and get row count
                count_sql = f"SELECT COUNT(*) FROM {target_schema}.{view_name}"
                count_result = session.sql(count_sql).collect()
                row_count = count_result[0][0]
                table_result['row_count'] = row_count

                # Always attempt to grant SELECT permission to ANALYSIS role
                try:
                    grant_sql = f"GRANT SELECT ON TABLE {target_schema}.{view_name} TO ROLE ANALYSIS"
                    session.sql(grant_sql).collect()
                    table_result['grant_applied'] = True

                except Exception as grant_error:
                    # Record grant failure as an error
                    grant_error_msg = f"Failed to grant SELECT on table {view_name} to ANALYSIS role: {str(grant_error)}"
                    results['errors'].append(grant_error_msg)
                    table_result['grant_applied'] = False
                    table_result['grant_error'] = str(grant_error)

                results['successful_tables'].append(table_result)
                results['total_tables_created'] += 1

            except Exception as e:
                # Record error but CONTINUE processing other views
                error_msg = f"Failed to create table {view_name}: {str(e)}"
                table_result['error'] = str(e)
                results['failed_tables'].append(table_result)
                results['errors'].append(error_msg)
                has_critical_errors = True  # Mark that we had errors
                continue  # Continue to next view

        # Add summary message
        successful_grants = sum(1 for table in results['successful_tables'] if table.get('grant_applied', False))
        failed_grants = sum(1 for table in results['successful_tables'] if not table.get('grant_applied', False))

        summary = f"Process completed. Created {results['total_tables_created']} tables out of {results['total_views_requested']} views requested."
        summary += f" Successfully applied SELECT grants to ANALYSIS role for {successful_grants} tables."

        if failed_grants > 0:
            summary += f" Failed to apply grants for {failed_grants} tables."

        results['summary'] = summary

        # If we had any critical errors during processing, throw an exception with full details
        if has_critical_errors:
            error_summary = f"Procedure completed with errors. {len(results['errors'])} error(s) occurred. "
            error_summary += f"Successfully created {results['total_tables_created']} out of {results['total_views_requested']} requested tables. "
            error_summary += f"Failed tables: {len(results['failed_tables'])}. "
            error_summary += f"Grant failures: {failed_grants}. "
            error_summary += f"See full results for details: {json.dumps(results, indent=2)}"
            raise Exception(error_summary)

        return json.dumps(results, indent=2)

    except Exception as e:
        # If this is our intentional error with full results, re-raise it
        if "Procedure completed with errors" in str(e):
            raise e

        # For unexpected errors, add to results and throw
        if f"Unexpected error in main process: {str(e)}" not in results['errors']:
            results['errors'].append(f"Unexpected error in main process: {str(e)}")

        error_with_results = f"Procedure failed with error: {str(e)}. Results: {json.dumps(results, indent=2)}"
        raise Exception(error_with_results)
$$;