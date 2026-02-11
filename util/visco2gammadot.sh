#!/bin/bash
# Muhammet Nergizci, COMET — 2025
# Convert viscosity → gamma_dot, also supports log10 input like e18.5

mu=3e10
sec_per_yr=3.1536e7

if [ -z "$1" ]; then
  echo "Usage: $0 <viscosity>"
  echo "Examples:"
  echo "  $0 3e18"
  echo "  $0 e18.5   (means 10^18.5)"
  echo "  $0 1e18.5  (means 1 × 10^18.5)"
  exit 1
fi

inp="$1"

# Case 1 → plain scientific notation (contains e or E AND digit after e)
if [[ "$inp" =~ ^[0-9.]+[eE][0-9.+-]+$ ]]; then
  eta="$inp"

# Case 2 → pure exponent like e18.5 or E18.5
elif [[ "$inp" =~ ^[eE][0-9.+-]+$ ]]; then
  exp=${inp:1}
  eta=$(awk -v x="$exp" 'BEGIN { printf("%.10e", 10^x) }')

# Case 3 → 1e18.5 (coefficient + exponent with decimal)
elif [[ "$inp" =~ ^[0-9.]+[eE][0-9.]+$ ]]; then
  coef=$(echo "$inp" | sed -E 's/[eE].*$//')
  exp=$(echo "$inp" | sed -E 's/^[0-9.]+[eE]//')
  eta=$(awk -v c="$coef" -v x="$exp" 'BEGIN { printf("%.10e", c*(10^x)) }')

else
  echo "Input format not recognized: $inp"
  echo "Try: 3e18, e18.5, 1e18.5"
  exit 1
fi

# gamma_dot and outputs
gamma_dot=$(awk -v mu="$mu" -v eta="$eta" -v s="$sec_per_yr" \
  'BEGIN { g=(mu/eta)*s; printf("%.10f", g) }')

tmaxwell=$(awk -v g="$gamma_dot" 'BEGIN { printf("%.10f", 1/g) }')

echo "------------------------------------------"
echo "Shear modulus (μ): $mu Pa"
echo "Viscosity (η):     $eta Pa·s"
echo "Log10(η):          e$(awk -v e="$eta" 'BEGIN{ printf("%.3f", log(e)/log(10)) }')"
echo "------------------------------------------"
echo "γ̇₀ (mu/eta):      $gamma_dot yr⁻¹"
echo "Maxwell time:      $tmaxwell years"
echo "------------------------------------------"