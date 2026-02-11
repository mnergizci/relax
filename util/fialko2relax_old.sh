#!/usr/bin/env bash

# fialko2relax.sh
# Convert inversion output (with Us, Ud, Un) to .flt format
# Muhammet Nergizci, COMET-University of Leeds, 18/08/2025

infile="$1"
outfile="${2:-$(basename "$infile" .inv).flt}"   # default name: slip.inv -> slip.flt
in_units="${3:-m}"    # default input units
out_units="${4:-km}"  # default output units

if [[ -z "$infile" ]]; then
  echo "Usage: $0 INPUT.inv [OUTPUT.flt] [in_units=m|km] [out_units=m|km]"
  exit 1
fi

# ---- the awk conversion ----
in_u2m=1; [[ "$in_units" =~ ^[Kk][Mm]$ ]] && in_u2m=1000
out_u2m=1; [[ "$out_units" =~ ^[Kk][Mm]$ ]] && out_u2m=1000
factor=$(awk -v a="$in_u2m" -v b="$out_u2m" 'BEGIN{printf("%.12f", a/b)}')

gawk -v f="$factor" '
BEGIN{
  pi = atan2(0,-1)
  print "# n   slip       x1           x2           x3       length    width   strike   dip   rake"
}
NF >= 13 && $1 !~ /^#/ {
  id     = $1
  xs     = $5 * f
  ys     = $4 * f
  zs     = $6 * f * -1 
  L      = $7 * f
  W      = $8 * f
  dip    = $9
  strike = $10
  Us     = $11
  Ud     = $12
  slip   = sqrt(Us*Us + Ud*Ud)
  rake   = atan2(Ud, Us) * 180.0 / pi

  printf("%03d %8.4f %12.3f %12.3f %12.3f %8.3f %8.3f %8.2f %6.2f %7.2f\n",
         id, slip, xs, ys, zs, L, W, strike, dip, rake)
}
' "$infile" > "$outfile"

echo "Wrote $outfile"

