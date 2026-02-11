#!/bin/bash
#Muhammet Nergizci, 10/10/2025 COMET, University of Leeds
# ============================================================
# Convert Relax time-step settings to days/weeks and number of outputs
# Usage:
#   ./timestep2output.sh <total_time_yr> <time_step_yr>
# Example:
#   ./timestep2output.sh 2 0.0284
# ============================================================

if [ $# -ne 2 ]; then
  echo "Usage: $0 <total_time_yr> <time_step_yr>"
  echo "Example: $0 2 0.0284"
  exit 1
fi

t_total=$1
dt=$2
days_per_yr=365.25

# Convert dt to days and weeks
dt_days=$(awk -v dt="$dt" -v dpy="$days_per_yr" 'BEGIN { printf "%.2f", dt*dpy }')
dt_weeks=$(awk -v dt_days="$dt_days" 'BEGIN { printf "%.2f", dt_days/7 }')

# Calculate number of output steps
n_steps=$(awk -v t="$t_total" -v dt="$dt" 'BEGIN { printf "%d", t/dt }')

echo "-------------------------------------------"
echo "Total simulation time:  $t_total years"
echo "Time step (Δt):          $dt years"
echo "-------------------------------------------"
echo "Output interval:         $dt_days days  (~$dt_weeks weeks)"
echo "Number of output steps:  $n_steps"
echo "-------------------------------------------"
