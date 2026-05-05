#!/usr/bin/env bash
set -euo pipefail
# Muhammet Nergizci — Unified RELAX sweeper (depth / p γdot / raw)
# COMET — University of Leeds — 31/10/2025

usage() {
  cat <<EOF
Usage: $(basename "$0") <template.sh> \\
  --t1 min/max/step | --t1 min max step \\
  --t2 min/max/step | --t2 min max step \\
  [--t3 min/max/step | --t3 min max step] \\
  [--t4 min/max/step | --t4 min max step] \\
  [--t5 min/max/step | --t5 min max step] \\
  [--t1-kind depth|p|raw|gdot] [--t2-kind depth|p|raw|gdot] \\
  [--t3-kind depth|p|raw|gdot] [--t4-kind depth|p|raw|gdot] \\
  [--t5-kind depth|p|raw|gdot] \\
  [--dgamma1] [--dgamma2] \\
  [--strategy row|placeholder] [--mu 3e10] [--sec-per-yr 3.1536e7] [--run]
Inference (if kind omitted): >=10000 ⇒ depth (m); 10..30 ⇒ p; -10..10 ⇒ raw

--dgamma1:
  Adds an internal target-p loop over the same range as --t1.
  Replaces target_dgamma1 using:
    dgamma1 = gamma(target_p) - gamma(base_p)
    gamma(p) = (mu / 10^p) * sec_per_yr

--dgamma2:
  Adds an internal target-p loop over the same range as --t2.
  Replaces target_dgamma2 using the same formula.
EOF
}

[[ $# -ge 1 ]] || { usage; exit 1; }
TEMPLATE="$1"; shift
[[ -f "$TEMPLATE" ]] || { echo "Template not found: $TEMPLATE"; exit 1; }

# --- defaults ---
T1MIN=""; T1MAX=""; T1STEP=""
T2MIN=""; T2MAX=""; T2STEP=""
T3MIN=""; T3MAX=""; T3STEP=""
T4MIN=""; T4MAX=""; T4STEP=""
T5MIN=""; T5MAX=""; T5STEP=""
T1_KIND=""             # if empty -> infer (depth|p|raw|gdot)
T2_KIND=""             # if empty -> infer (depth|p|raw|gdot)
T3_KIND=""             # optional axis
T4_KIND=""             # optional axis
T5_KIND=""             # optional axis
STRATEGY="${STRATEGY:-placeholder}"  # row | placeholder
MU="${MU:-3e10}"
SEC_PER_YR="${SEC_PER_YR:-3.1536e7}"
RUN="no"
DGAMMA1="no"
DGAMMA2="no"

need3() { [[ $# -ge 3 ]] || { echo "Error: $1 expects 3 args: min max step"; exit 1; }; }

# --- robust sweep parsing that NEVER returns non-zero (safe with set -e) ---
# Sets globals: PARSE_MN PARSE_MX PARSE_ST PARSE_SHIFT
parse_t_triplet_or_three() {
  local which="$1"; shift || true
  local tok="${1-}"

  if [[ -z "${tok-}" ]]; then
    echo "Error: --$which missing arguments"; exit 1
  fi

  if [[ "$tok" == */* ]]; then
    IFS=/ read -r PARSE_MN PARSE_MX PARSE_ST <<< "$tok" || { echo "Bad --$which triplet: $tok"; exit 1; }
    [[ -n "$PARSE_MN" && -n "$PARSE_MX" && -n "$PARSE_ST" ]] || { echo "Bad --$which triplet: $tok"; exit 1; }
    PARSE_SHIFT=1
  else
    need3 "--$which" "$@"
    PARSE_MN="$1"; PARSE_MX="$2"; PARSE_ST="$3"
    PARSE_SHIFT=3
  fi
}

# ---- argument parsing (compact/legacy/override) ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --t1)
      shift
      parse_t_triplet_or_three t1 "$@"
      T1MIN="$PARSE_MN"; T1MAX="$PARSE_MX"; T1STEP="$PARSE_ST"
      shift "$PARSE_SHIFT"
      ;;
    --t2)
      shift
      parse_t_triplet_or_three t2 "$@"
      T2MIN="$PARSE_MN"; T2MAX="$PARSE_MX"; T2STEP="$PARSE_ST"
      shift "$PARSE_SHIFT"
      ;;
    --t3)
      shift
      parse_t_triplet_or_three t3 "$@"
      T3MIN="$PARSE_MN"; T3MAX="$PARSE_MX"; T3STEP="$PARSE_ST"
      shift "$PARSE_SHIFT"
      ;;
    --t4)
      shift
      parse_t_triplet_or_three t4 "$@"
      T4MIN="$PARSE_MN"; T4MAX="$PARSE_MX"; T4STEP="$PARSE_ST"
      shift "$PARSE_SHIFT"
      ;;
    --t5)
      shift
      parse_t_triplet_or_three t5 "$@"
      T5MIN="$PARSE_MN"; T5MAX="$PARSE_MX"; T5STEP="$PARSE_ST"
      shift "$PARSE_SHIFT"
      ;;
    # legacy flags (kept)
    --t1min)  T1MIN="$2"; shift 2;;
    --t1max)  T1MAX="$2"; shift 2;;
    --t1step) T1STEP="$2"; shift 2;;
    --t2min)  T2MIN="$2"; shift 2;;
    --t2max)  T2MAX="$2"; shift 2;;
    --t2step) T2STEP="$2"; shift 2;;
    # explicit kind overrides
    --t1-kind) T1_KIND="$2"; shift 2;;
    --t2-kind) T2_KIND="$2"; shift 2;;
    --t3-kind) T3_KIND="$2"; shift 2;;
    --t4-kind) T4_KIND="$2"; shift 2;;
    --t5-kind) T5_KIND="$2"; shift 2;;
    --dgamma1) DGAMMA1="yes"; shift;;
    --dgamma2) DGAMMA2="yes"; shift;;
    # strategy & physics
    --strategy) STRATEGY="$2"; shift 2;;
    --mu) MU="$2"; shift 2;;
    --sec-per-yr) SEC_PER_YR="$2"; shift 2;;
    --run) RUN="yes"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1"; usage; exit 1;;
  esac
done

# Validate presence
for v in T1MIN T1MAX T1STEP T2MIN T2MAX T2STEP; do
  [[ -n "${!v}" ]] || { echo "Missing sweep parameters. Use --t1 min/max/step and --t2 min/max/step."; exit 1; }
done
# Optional axes must be complete if any piece is provided
if [[ -n "$T3MIN" || -n "$T3MAX" || -n "$T3STEP" ]]; then
  [[ -n "$T3MIN" && -n "$T3MAX" && -n "$T3STEP" ]] || { echo "If using --t3, provide min max step"; exit 1; }
fi
if [[ -n "$T4MIN" || -n "$T4MAX" || -n "$T4STEP" ]]; then
  [[ -n "$T4MIN" && -n "$T4MAX" && -n "$T4STEP" ]] || { echo "If using --t4, provide min max step"; exit 1; }
fi
if [[ -n "$T5MIN" || -n "$T5MAX" || -n "$T5STEP" ]]; then
  [[ -n "$T5MIN" && -n "$T5MAX" && -n "$T5STEP" ]] || { echo "If using --t5, provide min max step"; exit 1; }
fi

# ---- inference helpers ----
infer_kind() {
  # decide kind from min/max: depth|p|raw
  # rule: >=10000 -> depth; 10..30 -> p; -10..10 -> raw
  awk -v mn="$1" -v mx="$2" '
    BEGIN{
      if (mn>=10000 || mx>=10000) { print "depth"; exit }
      if (mn>=10 && mx<=30)       { print "p";     exit }
      if (mn>=-10 && mx<=10)      { print "raw";   exit }
      if (mn>=0 && mx>0) { print "p"; } else { print "raw"; }
    }'
}
[[ -z "$T1_KIND" ]] && T1_KIND="$(infer_kind "$T1MIN" "$T1MAX")"
[[ -z "$T2_KIND" ]] && T2_KIND="$(infer_kind "$T2MIN" "$T2MAX")"
[[ -n "$T3MIN" && -z "$T3_KIND" ]] && T3_KIND="$(infer_kind "$T3MIN" "$T3MAX")"
[[ -n "$T4MIN" && -z "$T4_KIND" ]] && T4_KIND="$(infer_kind "$T4MIN" "$T4MAX")"
[[ -n "$T5MIN" && -z "$T5_KIND" ]] && T5_KIND="$(infer_kind "$T5MIN" "$T5MAX")"

if [[ "$DGAMMA1" == "yes" && "$T1_KIND" != "p" ]]; then
  echo "Error: --dgamma1 requires --t1-kind p because dgamma is computed from p-viscosity exponents."
  exit 1
fi
if [[ "$DGAMMA2" == "yes" && "$T2_KIND" != "p" ]]; then
  echo "Error: --dgamma2 requires --t2-kind p because dgamma is computed from p-viscosity exponents."
  exit 1
fi

# ---- math helpers ----
fadd(){ awk -v a="$1" -v s="$2" 'BEGIN{printf("%.10g", a+s)}'; }
fle(){ awk -v a="$1" -v b="$2" 'BEGIN{exit !(a<=b)}'; }
eta_from_p(){ awk -v p="$1" 'BEGIN{printf("%.10g", exp(p*log(10)))}'; }
gdot_from_eta(){ awk -v mu="$MU" -v eta="$1" -v s="$SEC_PER_YR" 'BEGIN{printf("%.10g", (mu/eta)*s)}'; }
dgamma_from_p(){
  awk -v pbase="$1" -v ptarget="$2" -v mu="$MU" -v s="$SEC_PER_YR" '
    BEGIN{
      gbase = (mu / exp(pbase*log(10))) * s
      gtarget = (mu / exp(ptarget*log(10))) * s
      printf("%.10g", gtarget - gbase)
    }'
}

to_insert_value() {
  case "$2" in
    depth) awk -v x="$1" 'BEGIN{printf("%.0f", x)}' ;;             # meters
    p)     eta=$(eta_from_p "$1"); gdot_from_eta "$eta" ;;          # γdot [1/yr]
    raw)   awk -v x="$1" 'BEGIN{printf("%.10g", x)}' ;;             # literal
    gdot)  awk -v x="$1" 'BEGIN{printf("%.10g", x)}' ;;             # direct γdot
  esac
}

# ---- tags (FILENAME PARTS) ----
tag_depth(){ awk -v x="$1" 'BEGIN{printf("%.0f", x)}'; }                 # 17000
tag_p(){     awk -v x="$1" 'BEGIN{gsub(/\./,"p",x); printf("%s", x)}'; } # 17p1
tag_raw_signed_p(){
  awk -v x="$1" '
    BEGIN{
      abs = (x < 0 ? -x : x)
      s = sprintf("%.15g", abs)
      gsub(/\./, "p", s)
      printf("%s%s", (x < 0 ? "m" : ""), s)
    }'
}

# --- OUTROOT ---
BASE="$(basename "$TEMPLATE" .sh)"
OUTROOT="${BASE}_t1_${T1MIN}-${T1MAX}-${T1STEP}_t2_${T2MIN}-${T2MAX}-${T2STEP}"
[[ -n "$T3MIN" ]] && OUTROOT="${OUTROOT}_t3_${T3MIN}-${T3MAX}-${T3STEP}"
[[ -n "$T4MIN" ]] && OUTROOT="${OUTROOT}_t4_${T4MIN}-${T4MAX}-${T4STEP}"
[[ -n "$T5MIN" ]] && OUTROOT="${OUTROOT}_t5_${T5MIN}-${T5MAX}-${T5STEP}"
[[ "$DGAMMA1" == "yes" ]] && OUTROOT="${OUTROOT}_dgamma1"
[[ "$DGAMMA2" == "yes" ]] && OUTROOT="${OUTROOT}_dgamma2"
mkdir -p "$OUTROOT"

echo "[info] Kinds: t1=${T1_KIND}, t2=${T2_KIND}; t3=${T3_KIND:-none}, t4=${T4_KIND:-none}, t5=${T5_KIND:-none}; dgamma1=${DGAMMA1}, dgamma2=${DGAMMA2}; OUT=${OUTROOT}"

# ---- tag + insertion wrappers ----
mk_tag() {
  case "$2" in
    depth) tag_depth "$1" ;;
    p)     tag_p "$1" ;;
    raw|gdot) tag_raw_signed_p "$1" ;;
    *) echo "UNK" ;;
  esac
}
mk_insert() { to_insert_value "$1" "$2"; }

# ---- main sweep ----
COUNT=0
t1="$T1MIN"
while fle "$t1" "$T1MAX"; do
  T1_INS="$(mk_insert "$t1" "$T1_KIND")"
  T1_TAG="$(mk_tag "$t1" "$T1_KIND")"

  t2="$T2MIN"
  while fle "$t2" "$T2MAX"; do
    T2_INS="$(mk_insert "$t2" "$T2_KIND")"
    T2_TAG="$(mk_tag "$t2" "$T2_KIND")"

    # Optional t3 loop (single pass if not provided)
    if [[ -n "$T3MIN" ]]; then t3="$T3MIN"; else t3=""; fi
    while :; do
      if [[ -n "$t3" ]]; then
        T3_INS="$(mk_insert "$t3" "$T3_KIND")"
        T3_TAG="_$(mk_tag "$t3" "$T3_KIND")"
      else
        T3_INS=""; T3_TAG=""
      fi

      # Optional t4 loop (single pass if not provided)
      if [[ -n "$T4MIN" ]]; then t4="$T4MIN"; else t4=""; fi
      while :; do
        if [[ -n "$t4" ]]; then
          T4_INS="$(mk_insert "$t4" "$T4_KIND")"
          T4_TAG="_$(mk_tag "$t4" "$T4_KIND")"
        else
          T4_INS=""; T4_TAG=""
        fi

        # Optional t5 loop (single pass if not provided)
        if [[ -n "$T5MIN" ]]; then t5="$T5MIN"; else t5=""; fi
        while :; do
          if [[ -n "$t5" ]]; then
            T5_INS="$(mk_insert "$t5" "$T5_KIND")"
            T5_TAG="_$(mk_tag "$t5" "$T5_KIND")"
          else
            T5_INS=""; T5_TAG=""
          fi

          if [[ "$DGAMMA1" == "yes" ]]; then dg1="$T1MIN"; else dg1=""; fi
          while :; do
            if [[ "$DGAMMA1" == "yes" ]]; then
              DGAMMA1_INS="$(dgamma_from_p "$t1" "$dg1")"
              DGAMMA1_TAG="_dg1$(mk_tag "$dg1" p)"
            else
              DGAMMA1_INS=""
              DGAMMA1_TAG=""
            fi

            if [[ "$DGAMMA2" == "yes" ]]; then dg2="$T2MIN"; else dg2=""; fi
            while :; do
              if [[ "$DGAMMA2" == "yes" ]]; then
                DGAMMA2_INS="$(dgamma_from_p "$t2" "$dg2")"
                DGAMMA2_TAG="_dg2$(mk_tag "$dg2" p)"
              else
                DGAMMA2_INS=""
                DGAMMA2_TAG=""
              fi

              OUT="${OUTROOT}/${BASE}_${T1_TAG}_${T2_TAG}${T3_TAG}${T4_TAG}${T5_TAG}${DGAMMA1_TAG}${DGAMMA2_TAG}.sh"

              if [[ "$STRATEGY" == "placeholder" ]]; then
                # Replace ALL occurrences of target1/target2[/target3/target4/target5] and optional dgamma placeholders.
                awk -v a1="$T1_INS" -v a2="$T2_INS" -v a3="$T3_INS" -v a4="$T4_INS" -v a5="$T5_INS" -v dg1="$DGAMMA1_INS" -v dg2="$DGAMMA2_INS" '{
                line = $0
                gsub(/target1/, a1, line)
                gsub(/target2/, a2, line)
                if (a3 != "") gsub(/target3/, a3, line)
                if (a4 != "") gsub(/target4/, a4, line)
                if (a5 != "") gsub(/target5/, a5, line)
                if (dg1 != "") gsub(/target_dgamma1/, dg1, line)
                if (dg2 != "") gsub(/target_dgamma2/, dg2, line)
                print line
              }' "$TEMPLATE" > "$OUT"
              else
                # STRATEGY=row: edit t1/t2 rows in the special block; other values via placeholder anywhere
                if grep -qE '^# no depth gammadot0 cohesion[[:space:]]*$' "$TEMPLATE"; then
                  awk -v t1kind="$T1_KIND" -v t1d="$T1_INS" -v g2="$T2_INS" -v a3="$T3_INS" -v a4="$T4_INS" -v a5="$T5_INS" -v dg1="$DGAMMA1_INS" -v dg2="$DGAMMA2_INS" '
                  BEGIN { inblk=0 }
                  {
                    if ($0 ~ /^# no depth gammadot0 cohesion[[:space:]]*$/) { print; inblk=1; next }
                    if (inblk==1) {
                      if ($1=="1") {
                        depth = (t1kind=="depth") ? t1d : $2
                        printf("    1  %s     %s     %s\n", depth, g2, (NF>=4 ? $4 : "0.0"))
                        next
                      } else if ($1=="2") {
                        printf("    2  %s     %s     %s\n", (NF>=2 ? $2 : "100000"), g2, (NF>=4 ? $4 : "0.0"))
                        next
                      } else if ($0 ~ /^#/) {
                        inblk=0
                      }
                    }
                    line=$0
                    if (a3 != "") gsub(/target3/, a3, line)
                    if (a4 != "") gsub(/target4/, a4, line)
                    if (a5 != "") gsub(/target5/, a5, line)
                    if (dg1 != "") gsub(/target_dgamma1/, dg1, line)
                    if (dg2 != "") gsub(/target_dgamma2/, dg2, line)
                    print line
                  }' "$TEMPLATE" > "$OUT"
                else
                  echo "[warn] STRATEGY=row but marker not found; falling back to global placeholder for $OUT" >&2
                  awk -v a1="$T1_INS" -v a2="$T2_INS" -v a3="$T3_INS" -v a4="$T4_INS" -v a5="$T5_INS" -v dg1="$DGAMMA1_INS" -v dg2="$DGAMMA2_INS" '{
                  line = $0
                  gsub(/target1/, a1, line)
                  gsub(/target2/, a2, line)
                  if (a3 != "") gsub(/target3/, a3, line)
                  if (a4 != "") gsub(/target4/, a4, line)
                  if (a5 != "") gsub(/target5/, a5, line)
                  if (dg1 != "") gsub(/target_dgamma1/, dg1, line)
                  if (dg2 != "") gsub(/target_dgamma2/, dg2, line)
                  print line
                }' "$TEMPLATE" > "$OUT"
                fi
              fi

              chmod +x "$OUT"
              echo "Made: $OUT"
              COUNT=$((COUNT+1))

              if [[ "$DGAMMA2" == "yes" ]]; then
                dg2=$(fadd "$dg2" "$T2STEP")
                if ! fle "$dg2" "$T2MAX"; then break; fi
              else
                break
              fi
            done

            if [[ "$DGAMMA1" == "yes" ]]; then
              dg1=$(fadd "$dg1" "$T1STEP")
              if ! fle "$dg1" "$T1MAX"; then break; fi
            else
              break
            fi
          done

          # advance t5 or break
          if [[ -n "$T5MIN" ]]; then
            if fle "$t5" "$T5MAX"; then
              t5=$(fadd "$t5" "$T5STEP")
              if ! fle "$t5" "$T5MAX"; then break; fi
            fi
          else
            break
          fi
        done

        # advance t4 or break
        if [[ -n "$T4MIN" ]]; then
          if fle "$t4" "$T4MAX"; then
            t4=$(fadd "$t4" "$T4STEP")
            if ! fle "$t4" "$T4MAX"; then break; fi
          fi
        else
          break
        fi
      done

      # advance t3 or break
      if [[ -n "$T3MIN" ]]; then
        if fle "$t3" "$T3MAX"; then
          t3=$(fadd "$t3" "$T3STEP")
          if ! fle "$t3" "$T3MAX"; then break; fi
        fi
      else
        break
      fi
    done

    t2=$(fadd "$t2" "$T2STEP")
  done
  t1=$(fadd "$t1" "$T1STEP")
done

echo "[done] Generated $COUNT files under: $OUTROOT"

# ---- optional run ----
if [[ "$RUN" == "yes" ]]; then
  echo "[run] Executing generated scripts..."
  find "$OUTROOT" -maxdepth 1 -type f -name "${BASE}_*.sh" -print0 | while IFS= read -r -d '' f; do
    echo "[run] $f"
    "$f"
  done
fi
