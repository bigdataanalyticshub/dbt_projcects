import git
import os
from pathlib import Path
from datetime import datetime


def get_filtered_changes(repo_path='.', include_paths=None):
    """Get git changes with filtering options for SQL files only."""
    try:
        repo = git.Repo(repo_path)

        all_changes = []

        # Get all types of changes
        for item in repo.index.diff("HEAD"):
            # Handle potential None values
            change_type = item.change_type or 'unknown'
            file_path = item.a_path or ''

            if change_type == 'M':
                status_suffix = 'modified'
            elif change_type == 'A':
                status_suffix = 'added'
            elif change_type == 'D':
                status_suffix = 'deleted'
            else:
                status_suffix = change_type.lower()

            all_changes.append({
                'file': file_path,
                'status': 'staged_' + status_suffix,
                'full_path': os.path.join(repo_path, file_path)
            })

        for item in repo.index.diff(None):
            # Handle potential None values
            change_type = item.change_type or 'unknown'
            file_path = item.a_path or ''

            if change_type == 'M':
                status_suffix = 'modified'
            elif change_type == 'D':
                status_suffix = 'deleted'
            else:
                status_suffix = change_type.lower()

            all_changes.append({
                'file': file_path,
                'status': 'unstaged_' + status_suffix,
                'full_path': os.path.join(repo_path, file_path)
            })

        for file in repo.untracked_files:
            all_changes.append({
                'file': file,
                'status': 'untracked',
                'full_path': os.path.join(repo_path, file)
            })

        # Apply filters
        filtered_changes = []
        for change in all_changes:
            file_path = Path(change['file'])

            # Filter by .sql extension only
            if file_path.suffix.lower() != '.sql':
                continue

            # Include only certain paths
            if include_paths:
                # Check if the file path contains any of the included paths
                path_matches = False
                for include_path in include_paths:
                    # Convert to Path object for better comparison
                    include_path_obj = Path(include_path)

                    # Check if the file is in the included path or subdirectory
                    try:
                        # This will succeed if file_path is relative to include_path
                        file_path.relative_to(include_path_obj)
                        path_matches = True
                        break
                    except ValueError:
                        # Check if include_path is a substring of the file path
                        if include_path in str(file_path):
                            path_matches = True
                            break

                if not path_matches:
                    continue

            filtered_changes.append(change)

        return filtered_changes

    except Exception as e:
        print(f"Error: {e}")
        return None


def get_next_version_prefix(repo_path='.', migrations_folder='database/migrations'):
    """
    Determine the next version prefix by examining the last file in the migrations folder.
    Returns V[###]_ format where ### is incremented from the last file, or B001_ if no files exist.

    Args:
        repo_path: Path to git repository
        migrations_folder: Path to migrations folder relative to repo_path

    Returns:
        str: Version prefix in format V[###]_ or B001_
    """
    try:
        migrations_path = Path(repo_path) / migrations_folder

        # Check if migrations folder exists
        if not migrations_path.exists():
            print(f"Migrations folder '{migrations_folder}' not found. Using default prefix B001_")
            return "B001_"

        # Get all files in migrations folder and sort alphabetically
        migration_files = []
        for file_path in migrations_path.iterdir():
            if file_path.is_file():
                migration_files.append(file_path.name)

        # Sort files alphabetically
        migration_files.sort()

        # If no files exist, return B001_
        if not migration_files:
            print("No files found in migrations folder. Using default prefix B001_")
            return "B001_"

        # Get the last file name
        last_file = migration_files[-1]
        print(f"Last migration file found: {last_file}")

        # Extract number from positions 2-4 (0-indexed: positions 1-3)
        if len(last_file) >= 4:
            try:
                # Extract characters at positions 1, 2, 3 (2nd, 3rd, 4th characters)
                number_str = last_file[1:4]

                # Try to parse as integer
                current_number = int(number_str)

                # Increment by 1
                next_number = current_number + 1

                # Format as 3-digit number with leading zeros
                next_prefix = f"V{next_number:03d}_"

                print(f"Extracted number: {current_number}, Next version: {next_prefix}")
                return next_prefix

            except ValueError:
                print(f"Could not parse number from positions 2-4 in '{last_file}'. Using default prefix B001_")
                return "B001_"
        else:
            print(
                f"Last file '{last_file}' is too short to extract number from positions 2-4. Using default prefix B001_")
            return "B001_"

    except Exception as e:
        print(f"Error determining version prefix: {e}. Using default prefix B001_")
        return "B001_"


def concatenate_changed_files(repo_path='.', include_paths=None, migrations_folder='database/migrations'):
    """
    Create a SQL file containing concatenated contents of all changed SQL files.
    Places the file in the same directory as the migrations folder.
    Automatically generates filename with version prefix and timestamp: V[###]_[YYYYMMDDHHMMSS]__view_updates.sql

    Args:
        repo_path: Path to git repository
        include_paths: List of paths to include
        migrations_folder: Path to migrations folder relative to repo_path
    """

    # Get version prefix based on migrations folder
    version_prefix = get_next_version_prefix(repo_path, migrations_folder)

    # Generate automatic filename with version prefix and timestamp
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
    filename = f"{version_prefix}{timestamp}__view_updates.sql"

    # Determine output directory (same as migrations folder)
    migrations_path = Path(repo_path) / migrations_folder
    if migrations_path.exists():
        output_dir = migrations_path
    else:
        # If migrations folder doesn't exist, create it
        print(f"Creating migrations folder: {migrations_folder}")
        migrations_path.mkdir(parents=True, exist_ok=True)
        output_dir = migrations_path

    # Full path for output file
    output_file = output_dir / filename

    # Get filtered changes (SQL files only)
    changes = get_filtered_changes(repo_path, include_paths)

    if not changes:
        print("No SQL file changes found matching the specified criteria.")
        return

    # Create output file
    try:
        with open(output_file, 'w', encoding='utf-8') as outfile:
            # Write table of contents in SQL comment block
            outfile.write("\n/*\n\n")
            outfile.write("VIEWS TO MIGRATE IN THIS SCRIPT:\n")
            outfile.write("-" * 38 + "\n")
            for i, change in enumerate(changes, 1):
                outfile.write(f"{i:2d}. [{change['status'].upper()}] {change['file']}\n")
            outfile.write("\n*/\n\n")

            # Process each changed file
            for i, change in enumerate(changes, 1):
                file_path = change['full_path']
                relative_path = change['file']
                status = change['status']

                # Write file header in SQL comment block
                outfile.write("\n/*\n\n")
                outfile.write(f"FILE {i}: {relative_path}\n")
                outfile.write(f"STATUS: {status.upper()}\n")
                outfile.write(f"FULL PATH: {file_path}\n")
                outfile.write("\n*/\n\n")

                # Check if this is a deleted file
                is_deleted = 'deleted' in status.lower()

                if is_deleted:
                    # Generate DROP VIEW statement for deleted files
                    file_name_without_extension = Path(relative_path).stem
                    outfile.write(f"DROP VIEW IF EXISTS {file_name_without_extension};\n\n")
                    outfile.write("/* [FILE DELETED - DROP VIEW statement generated] */\n")
                else:
                    # Try to read and write file contents for non-deleted files
                    try:
                        # Check if file exists (it might be deleted)
                        if not os.path.exists(file_path):
                            outfile.write("/* [FILE DELETED - No content to display] */\n")
                        else:
                            # Read SQL file content
                            try:
                                with open(file_path, 'r', encoding='utf-8') as infile:
                                    content = infile.read()
                                    if content.strip():
                                        outfile.write(content)
                                        if not content.endswith('\n'):
                                            outfile.write('\n')
                                    else:
                                        outfile.write("/* [EMPTY FILE] */\n")
                            except UnicodeDecodeError:
                                # Try with different encoding
                                try:
                                    with open(file_path, 'r', encoding='latin-1') as infile:
                                        content = infile.read()
                                        outfile.write(f"/* [FILE READ WITH LATIN-1 ENCODING] */\n{content}")
                                        if not content.endswith('\n'):
                                            outfile.write('\n')
                                except Exception as e:
                                    outfile.write(f"/* [ERROR READING FILE: {str(e)}] */\n")
                            except Exception as e:
                                outfile.write(f"/* [ERROR READING FILE: {str(e)}] */\n")

                    except Exception as e:
                        outfile.write(f"/* [ERROR PROCESSING FILE: {str(e)}] */\n")

        print(f"Successfully created '{output_file}' with contents of {len(changes)} changed SQL files.")
        print(f"File location: {os.path.abspath(output_file)}")
        print(f"Files included:")
        for change in changes:
            print(f"  [{change['status'].upper()}] {change['file']}")

    except Exception as e:
        print(f"Error creating output file: {e}")


if __name__ == "__main__":
    # Create concatenated file for SQL changes in Views directory
    print("Creating concatenated file for SQL changes in Views directory...")
    concatenate_changed_files(
        repo_path='.',
        include_paths=['database/schema-model/Views/'],
        migrations_folder='database/migrations'
    )
