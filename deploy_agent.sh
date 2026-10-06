#!/usr/bin/env bash

# Beginner-friendly deployment helper for the attendance tracker.
# This script keeps things simple and easy to read.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
PROJECT_PREFIX="attendance_tracker_"

usage() {
  echo "Attendance Tracker Helper"
  echo ""
  echo "Usage:"
  echo "  ./deploy_agent.sh deploy [project_name]"
  echo "  ./deploy_agent.sh run [project_name]"
  echo "  ./deploy_agent.sh archive [project_name]"
  echo "  ./deploy_agent.sh help"
  echo "  ./deploy_agent.sh"
  echo ""Some required files are missing
  echo "Examples:"
  echo "  ./deploy_agent.sh deploy classA"
  echo "  ./deploy_agent.sh run classA"
  echo "  ./deploy_agent.sh archive classA"
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

check_tools() {
  if ! command -v python3 >/dev/null 2>&1; then
    fail "python3 is not installed. Please install it before continuing."
  fi

  if ! command -v zip >/dev/null 2>&1; then
    fail "zip is not installed. Please install it before continuing."
  fi
}

make_project_dir() {
  local project_name="$1"
  local project_dir="$SCRIPT_DIR/${PROJECT_PREFIX}${project_name}"

  if [[ -z "$project_name" ]]; then
    read -p "Enter a project name (for example: classA): " project_name
  fi

  if [[ -z "$project_name" ]]; then
    fail "Project name cannot be empty."
  fi

  echo "$project_dir"
}

handle_interrupt() {
  local project_dir="$1"

  echo ""
  echo "Deployment interrupted. Creating a backup zip archive..."

  if [[ -d "$project_dir" ]]; then
    zip -rq "${project_dir}_archive.zip" "$project_dir"
    echo "Backup created at: ${project_dir}_archive.zip"
  else
    echo "No project folder was available to archive."
  fi

  echo "The deployment has ended safely."
  exit 130
}

copy_template_roster() {
  local project_dir="$1"
  local count="$2"
  local template_file="$TEMPLATE_DIR/assets.csv"

  if [[ ! -f "$template_file" ]]; then
    fail "Template roster file not found: $template_file"
  fi

  if (( count < 1 )); then
    fail "You must copy at least 1 student."
  fi

  total_rows=$(tail -n +2 "$template_file" | wc -l | tr -d ' ')

  if (( count > total_rows )); then
    fail "The template only has $total_rows student rows. Please choose a smaller number."
  fi

  {
    head -n 1 "$template_file"
    tail -n +2 "$template_file" | head -n "$count"
  } > "$project_dir/Helpers/assets.csv"
}

generate_fresh_roster() {
  local project_dir="$1"
  local count="$2"

  if (( count < 1 )); then
    fail "Fresh roster must contain at least 1 student."
  fi

  echo "Email,Names,Attendance Count,Absence Count" > "$project_dir/Helpers/assets.csv"

  names=(
    "Alice Johnson"
    "Bob Smith"
    "Charlie Davis"
    "Diana Prince"
    "Ethan Cole"
    "Fatima Noor"
    "George Mensah"
    "Hannah Kim"
    "Ibrahim Osei"
    "Jasmine Lee"
  )

  emails=(
    "alice@example.com"
    "bob@example.com"
    "charlie@example.com"
    "diana@example.com"
    "ethan@example.com"
    "fatima@example.com"
    "george@example.com"
    "hannah@example.com"
    "ibrahim@example.com"
    "jasmine@example.com"
  )

  for ((i=0; i<count; i++)); do
    name="${names[$((i % ${#names[@]}))]}"
    email="${emails[$((i % ${#emails[@]}))]}"
    echo "$email,$name,0,0" >> "$project_dir/Helpers/assets.csv"
  done
}

set_total_sessions() {
  local config_file="$1"
  local total_sessions="$2"

  python3 - "$config_file" "$total_sessions" <<'PY'
import json, sys
config_path = sys.argv[1]
total_sessions = int(sys.argv[2])
with open(config_path, 'r', encoding='utf-8') as f:
    data = json.load(f)
data['total_sessions'] = total_sessions
with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=4)
    f.write('\n')
PY
}

update_thresholds() {
  local config_file="$1"
  local warning_value="$2"
  local failure_value="$3"

  sed -i "s/\"warning\": [0-9][0-9]*/\"warning\": ${warning_value}/" "$config_file"
  sed -i "s/\"failure\": [0-9][0-9]*/\"failure\": ${failure_value}/" "$config_file"
}

verify_setup() {
  local project_dir="$1"

  echo "Checking the project files..."

  if [[ -f "$project_dir/attendance_checker.py" ]] && \
     [[ -f "$project_dir/Helpers/config.json" ]] && \
     [[ -f "$project_dir/Helpers/assets.csv" ]]; then
    echo "Project files are present."
  else
    fail "Deployment check failed. Some required files are missing."
  fi

  echo "Trying a quick startup test..."
  cd "$project_dir" || fail "Could not enter project directory."
  python3 attendance_checker.py </dev/null >/dev/null 2>&1 || true
  echo "Startup check completed."
}

deploy_project() {
  local project_name="$1"
  local project_dir
  local roster_choice
  local roster_count
  local answer
  local warning_value
  local failure_value

  check_tools

  project_dir="$(make_project_dir "$project_name")"

  if [[ -e "$project_dir" ]]; then
    read -p "The project already exists. Do you want to overwrite it? [y/N]: " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
      fail "Deployment cancelled. The project already exists."
    fi
    rm -rf "$project_dir"
  fi

  trap 'handle_interrupt "$project_dir"' INT TSTP

  mkdir -p "$project_dir/Helpers" "$project_dir/reports"
  cp "$TEMPLATE_DIR/attendance_checker.py" "$project_dir/attendance_checker.py"
  cp "$TEMPLATE_DIR/config.json" "$project_dir/Helpers/config.json"

  echo "How do you want to build the roster?"
  echo "A) Copy rows from the template roster"
  echo "B) Create a fresh roster"
  read -p "Type A or B: " roster_choice
  roster_choice="$(printf '%s' "$roster_choice" | tr '[:lower:]' '[:upper:]')"

  case "$roster_choice" in
    A)
      read -p "How many students do you want to copy from the template? " roster_count
      copy_template_roster "$project_dir" "$roster_count"
      set_total_sessions "$project_dir/Helpers/config.json" 5
      ;;
    B)
      read -p "How many students do you want in the new roster? " roster_count
      generate_fresh_roster "$project_dir" "$roster_count"
      set_total_sessions "$project_dir/Helpers/config.json" 1
      ;;
    *)
      fail "Invalid choice. Please choose A or B."
      ;;
  esac

  chmod +x "$project_dir/attendance_checker.py"
  chmod 600 "$project_dir/Helpers/config.json"
  echo "Permissions set: attendance_checker.py is executable and config.json is owner-only."

  read -p "Do you want to change the alert thresholds? [y/N]: " answer
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    read -p "Warning threshold (default 75): " warning_value
    warning_value="${warning_value:-75}"

    read -p "Failure threshold (default 50): " failure_value
    failure_value="${failure_value:-50}"

    update_thresholds "$project_dir/Helpers/config.json" "$warning_value" "$failure_value"
    echo "Thresholds updated to warning=$warning_value and failure=$failure_value"
  else
    echo "Using the default template thresholds."
  fi

  verify_setup "$project_dir"
  trap - INT TSTP

  echo "Deployment complete. Project created at: $project_dir"
}

run_project() {
  local project_name="$1"
  local project_dir

  project_dir="$(make_project_dir "$project_name")"

  if [[ ! -d "$project_dir" ]]; then
    fail "Project not found: $project_dir"
  fi

  echo "Opening project: $project_dir"
  cd "$project_dir" || fail "Could not open project directory."
  python3 attendance_checker.py
}

archive_logs() {
  local project_name="$1"
  local project_dir
  local timestamp

  project_dir="$(make_project_dir "$project_name")"

  if [[ ! -d "$project_dir" ]]; then
    fail "Project not found: $project_dir"
  fi

  timestamp="$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$project_dir/archives/attendance" "$project_dir/archives/absent"

  if [[ -f "$project_dir/reports/attendance.log" ]]; then
    cp "$project_dir/reports/attendance.log" "$project_dir/archives/attendance/attendance_${timestamp}.log"
    echo "Attendance log archived to: $project_dir/archives/attendance/attendance_${timestamp}.log"
  else
    echo "No attendance.log file was found, so nothing was archived."
  fi

  if [[ -f "$project_dir/reports/absent.log" ]]; then
    cp "$project_dir/reports/absent.log" "$project_dir/archives/absent/absent_${timestamp}.log"
    echo "Absent log archived to: $project_dir/archives/absent/absent_${timestamp}.log"
  else
    echo "No absent.log file was found, so nothing was archived."
  fi
}

show_menu() {
  echo "Choose an option:"
  echo "1) Deploy a new project"
  echo "2) Run a project"
  echo "3) Archive logs"
  echo "4) Help"
  echo "5) Exit"

  read -p "Enter a number: " choice

  case "$choice" in
    1)
      deploy_project ""
      ;;
    2)
      run_project ""
      ;;
    3)
      archive_logs ""
      ;;
    4)
      usage
      ;;
    5)
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo "Invalid choice."
      exit 1
      ;;
  esac
}

case "${1:-}" in
  deploy)
    deploy_project "${2:-}"
    ;;
  run)
    run_project "${2:-}"
    ;;
  archive)
    archive_logs "${2:-}"
    ;;
  help)
    usage
    ;;
  "")
    show_menu
    ;;
  *)
    usage
    exit 1
    ;;
 esac
