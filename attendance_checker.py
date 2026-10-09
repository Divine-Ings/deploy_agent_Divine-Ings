import csv
import json
import os
import sys
from datetime import datetime

CONFIG_PATH = "Helpers/config.json"
ROSTER_PATH = "Helpers/assets.csv"
REPORTS_DIRECTORY = "reports"
ATTENDANCE_LOG_PATH = os.path.join(REPORTS_DIRECTORY, "attendance.log")
ABSENT_LOG_PATH = os.path.join(REPORTS_DIRECTORY, "absent.log")

STUDENT_NAME_COLUMN = "Names"
EMAIL_COLUMN = "Email"
ATTENDANCE_COUNT_COLUMN = "Attendance Count"
ABSENCE_COUNT_COLUMN = "Absence Count"


def load_config(config_path):
    """Load and validate the app configuration."""
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, "r", encoding="utf-8") as config_file:
        try:
            config = json.load(config_file)
        except json.JSONDecodeError as exc:
            raise ValueError(f"Config file is not valid JSON: {exc}") from exc

    required_top_level_keys = ["thresholds", "run_mode", "total_sessions"]
    for key in required_top_level_keys:
        if key not in config:
            raise ValueError(f"Config is missing required key: '{key}'")

    for key in ["warning", "failure"]:
        if key not in config["thresholds"]:
            raise ValueError(f"Config['thresholds'] is missing key: '{key}'")

    if config["total_sessions"] <= 0:
        raise ValueError("Config 'total_sessions' must be greater than 0")

    return config


def load_roster(roster_path):
    """Read the student roster and return column names with parsed counts."""
    if not os.path.exists(roster_path):
        raise FileNotFoundError(f"Roster file not found: {roster_path}")

    with open(roster_path, mode="r", encoding="utf-8", newline="") as roster_file:
        reader = csv.DictReader(roster_file)
        fieldnames = reader.fieldnames
        rows = list(reader)

    if not fieldnames or not rows:
        raise ValueError(f"Roster file is empty: {roster_path}")

    required_columns = [
        STUDENT_NAME_COLUMN,
        EMAIL_COLUMN,
        ATTENDANCE_COUNT_COLUMN,
        ABSENCE_COUNT_COLUMN,
    ]
    missing_columns = [column for column in required_columns if column not in fieldnames]
    if missing_columns:
        raise ValueError(f"Roster is missing required column(s): {missing_columns}")

    for row_number, row in enumerate(rows, start=2):
        try:
            row[ATTENDANCE_COUNT_COLUMN] = int(row[ATTENDANCE_COUNT_COLUMN])
            row[ABSENCE_COUNT_COLUMN] = int(row[ABSENCE_COUNT_COLUMN])
        except ValueError as exc:
            raise ValueError(
                f"Roster row {row_number} has a non-numeric attendance/"
                f"absence count: {row}"
            ) from exc

    return fieldnames, rows


def save_roster(roster_path, fieldnames, rows):
    """Save the updated roster back to the CSV file."""
    with open(roster_path, mode="w", encoding="utf-8", newline="") as roster_file:
        writer = csv.DictWriter(roster_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def classify_attendance(attendance_percentage, thresholds):
    """Return the alert level and message, if any, based on attendance percentage."""
    if attendance_percentage < thresholds["failure"]:
        return "URGENT", "below the failure threshold - will fail this class"
    if attendance_percentage < thresholds["warning"]:
        return "WARNING", "below the warning threshold - please be careful"
    return None, ""


def prompt_for_presence(student_name, email_address):
    """Ask for a student's attendance status until a valid answer is entered."""
    while True:
        raw_answer = input(
            f"Mark {student_name} <{email_address}> - [P]resent or [A]bsent? "
        ).strip().lower()

        if raw_answer in ("p", "present", "y", "yes"):
            return True
        if raw_answer in ("a", "absent", "n", "no"):
            return False

        print("  Please enter 'P' for present or 'A' for absent.")


def mark_attendance_session(student_rows, total_sessions, thresholds, run_mode):
    """
    Prompt for each student in the current session and update their running totals.

    Returns a tuple of: (attendance_logs, absent_logs, marked_students, stopped_early)
    where stopped_early is one of None, "interrupted", or "input_ran_out".
    """
    attendance_logs = []
    absent_logs = []
    marked_students = 0
    stopped_early = None
    today = datetime.now().strftime("%Y-%m-%d")

    print(f"\nToday's session: {len(student_rows)} students, total_sessions={total_sessions}\n")

    for row in student_rows:
        student_name = row[STUDENT_NAME_COLUMN]
        email_address = row[EMAIL_COLUMN]
        prior_session_total = row[ATTENDANCE_COUNT_COLUMN] + row[ABSENCE_COUNT_COLUMN]
        expected_previous_sessions = total_sessions - 1

        if prior_session_total != expected_previous_sessions:
            print(
                f"  (note: {student_name} has {prior_session_total} prior sessions on "
                f"record, expected {expected_previous_sessions} - proceeding anyway)"
            )

        try:
            is_present = prompt_for_presence(student_name, email_address)
        except KeyboardInterrupt:
            stopped_early = "interrupted"
            break
        except EOFError:
            stopped_early = "input_ran_out"
            break

        timestamp = datetime.now()

        if is_present:
            row[ATTENDANCE_COUNT_COLUMN] += 1
            status = "PRESENT"
        else:
            row[ABSENCE_COUNT_COLUMN] += 1
            status = "ABSENT"

        attended_sessions = row[ATTENDANCE_COUNT_COLUMN]
        attendance_percentage = (attended_sessions / total_sessions) * 100
        alert_level, alert_message = classify_attendance(attendance_percentage, thresholds)

        alert_suffix = f" | {alert_level}: {alert_message}" if alert_level else ""
        log_line = (
            f"[{timestamp}] {student_name} <{email_address}>: {status} - "
            f"attended {attended_sessions}/{total_sessions} = {attendance_percentage:.1f}%{alert_suffix}"
        )
        attendance_logs.append(log_line)

        if alert_level:
            print(f"  -> {attendance_percentage:.1f}% attendance | {alert_level}: {alert_message}")
        else:
            print(f"  -> {attendance_percentage:.1f}% attendance | on track")

        if not is_present:
            absent_logs.append(
                f"[{today}] {student_name} <{email_address}> - absent "
                f"(now {attendance_percentage:.1f}% attendance){alert_suffix}"
            )
            if run_mode == "live" and alert_level:
                print(f"  Logged alert for {student_name}")

        marked_students += 1

    return attendance_logs, absent_logs, marked_students, stopped_early


def append_log(log_path, header, lines):
    """Append log entries to a report file if there is anything to log."""
    if not lines:
        return

    os.makedirs(REPORTS_DIRECTORY, exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as log_file:
        log_file.write(header + "\n")
        for line in lines:
            log_file.write(line + "\n")


def run_attendance_check():
    config = load_config(CONFIG_PATH)
    fieldnames, rows = load_roster(ROSTER_PATH)

    total_sessions = config["total_sessions"]
    thresholds = config["thresholds"]
    run_mode = config.get("run_mode", "dry_run")

    attendance_logs, absent_logs, marked_students, stopped_early = mark_attendance_session(
        rows, total_sessions, thresholds, run_mode
    )

    session_header = (
        f"=== Session recorded {datetime.now()} | "
        f"total_sessions={total_sessions} | mode={run_mode} ==="
    )
    append_log(ATTENDANCE_LOG_PATH, session_header, attendance_logs)
    append_log(ABSENT_LOG_PATH, session_header, absent_logs)
    save_roster(ROSTER_PATH, fieldnames, rows)

    if stopped_early == "interrupted":
        print(
            f"\nInterrupted - marked {marked_students}/{len(rows)} students "
            "before Ctrl+C. Their results were saved to the roster and "
            "logs; the rest of the roster is unchanged.",
            file=sys.stderr,
        )
        sys.exit(130)

    if stopped_early == "input_ran_out":
        print(
            f"\nInput ended early - marked {marked_students}/{len(rows)} "
            "students before running out of input. Their results were "
            "saved; the rest of the roster is unchanged.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(
        f"\nDone. Marked {marked_students} students, "
        f"{len(absent_logs)} absent. "
        f"Logs: {ATTENDANCE_LOG_PATH}, {ABSENT_LOG_PATH}"
    )


def main():
    try:
        run_attendance_check()
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
    except OSError as exc:
        print(f"ERROR: unexpected filesystem error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()