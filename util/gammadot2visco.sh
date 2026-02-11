#!/bin/bash
# Muhammet Nergizci, 10/10/2025 COMET, University of Leeds
# ============================================================
# Convert gammadot (1/yr) to viscosity (Pa·s)
# Usage:
#   ./gammadot2visco.sh 0.095
# ============================================================

mu=3e10
sec_per_yr=3.1536e7

if [ -z "$1" ]; then
  echo "Usage: $0 <gammadot_in_1/yr>"
  exit 1
fi

gammadot_yr="$1"
gammadot_sec=$(awk -v g="$gammadot_yr" -v s="$sec_per_yr" 'BEGIN { print g/s }')

# viscosity (η)
viscosity=$(awk -v mu="$mu" -v g="$gammadot_sec" 'BEGIN { printf "%.3e", mu/g }')

# log10(η) → exponent form: e18.5
vis_log10=$(awk -v mu="$mu" -v g="$gammadot_sec" 'BEGIN { printf "e%.3f", log(mu/g)/log(10) }')

tmaxwell=$(awk -v g="$gammadot_yr" 'BEGIN { printf "%.3f", 1/g }')

echo "------------------------------------------"
echo "Shear modulus (μ): $mu Pa (30 GPa)"
echo "γ̇₀ (input):       $gammadot_yr yr⁻¹"
echo "------------------------------------------"
echo "Viscosity (η):     $viscosity Pa·s"
echo "Viscosity (log10): $vis_log10"
echo "Maxwell time:      $tmaxwell years"
echo "------------------------------------------"
