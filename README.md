# Attendance Tracker Deployment Helper

This project includes a shell-based deployment helper for the Student Attendance Tracker application.

## What the script does

The script in [deploy_agent.sh](./deploy_agent.sh) provides three features:

1. Deploy a new attendance tracker project
2. Run an existing project interactively
3. Archive the generated attendance/absence logs

It also traps Ctrl+C and Ctrl+Z while the deployment is in progress so the partially created project can be zipped before the script exits cleanly.

## How to use it

You can run the script either through the interactive menu or by direct commands.

### Interactive menu

```bash
./deploy_agent.sh
```

This opens a simple menu with options to deploy, run, archive, show help, or exit.

### Direct commands

```bash
./deploy_agent.sh deploy myclass
./deploy_agent.sh run myclass
./deploy_agent.sh archive myclass
./deploy_agent.sh help
```

The project name is the suffix used after `attendance_tracker_`.

Examples:

- `deploy myclass` creates `attendance_tracker_myclass/`
- `run myclass` runs the project in `attendance_tracker_myclass/`
- `archive myclass` archives the generated logs from the same directory

## Deployment behavior

During deployment, the script:

- checks that `python3` and `zip` are available
- creates a new project folder with the required directory structure
- copies the Python app and template config into the project
- builds the roster from either the bundled template or generated sample data
- keeps `config.json` consistent with the roster (`total_sessions` is 5 for template-based rosters and 1 for fresh rosters)
- sets executable permissions on the Python script
- restricts the config file to owner read/write access
- asks whether to update the warning and failure thresholds
- runs a startup check to confirm the project works together

## Roster rules

The script supports two roster options:

- Option A: copy rows from `templates/assets.csv`
- Option B: generate a fresh roster from arrays of sample names and emails

The relationship between the roster and total sessions is intentionally simple:

- Template roster rows already include prior session history, so the default is `total_sessions: 5`
- Fresh generated roster rows start at zero, so the default is `total_sessions: 1`

## Log archiving

After a run, the archive feature checks for `reports/attendance.log` and `reports/absent.log` and stores each file in its own archive folder using timestamps, for example:

```text
attendance_tracker_myclass/
├── archives/
│   ├── attendance/
│   │   └── attendance_20260927_143022.log
│   └── absent/
│       └── absent_20260927_143022.log
```

If a report does not exist, the script reports it without failing.

## Signal handling

While deployment is in progress, pressing Ctrl+C or Ctrl+Z triggers a trap that prints a clear interruption message, zips the partially created project into `attendance_tracker_<name>_archive.zip`, and exits cleanly.

This helps prevent a half-built project from being left behind.
