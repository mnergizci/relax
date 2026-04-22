#!/usr/bin/env bash
# Helper to change SDM slip model to relax input format (meter)
## Muhammet Nergizci, COMET, University of Leeds, 11/10/2025

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") --in input.dat --rlon <ref_lon> --rlat <ref_lat> [--utm <zone>] [--ll]"
  exit 1
}

IN=""; RLON=""; RLAT=""; UTM="${UTM:-}"; LL=0

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)   IN="$2"; shift 2;;
    --rlon) RLON="$2"; shift 2;;
    --rlat) RLAT="$2"; shift 2;;
    --utm)  UTM="$2"; shift 2;;
    --ll)   LL=1; shift 1;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

[[ -z "$IN" || -z "$RLON" || -z "$RLAT" ]] && usage
[[ -f "$IN" ]] || { echo "Input not found: $IN"; exit 2; }

BASENAME="$(basename "$IN")"
STEM="${BASENAME%.*}"

if [[ "$LL" -eq 1 ]]; then
  OUTFILE="${STEM}_ll.flt"
else
  OUTFILE="${STEM}_local.flt"
fi

# Folder where sdm2relax.sh lives (and where llh2local.m is)
SDM_PATH="$(dirname "$(readlink -f "$(command -v sdm2relax.sh)")")"

matlab -nodisplay -nosplash -r "try, addpath('$SDM_PATH'); inFile='$IN'; outFile='$OUTFILE'; rlon=$RLON; rlat=$RLAT; utm='$UTM'; use_ll=$LL; fid=fopen(inFile,'r'); h=0; while true, t=fgetl(fid); if ~ischar(t), break; end; s=strtrim(t); if isempty(s) || s(1)=='#', h=h+1; continue; end; m=regexp(s,'^([+-]?\d+(\.\d+)?([eE][+-]?\d+)?)[\s,]+([+-]?\d+(\.\d+)?([eE][+-]?\d+)?)','once'); if isempty(m), h=h+1; else, break; end; end; frewind(fid); C=textscan(fid,'%f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f','HeaderLines',h,'MultipleDelimsAsOne',true); fclose(fid); M=cell2mat(C); if isempty(M), error('No numeric rows parsed (after %d header lines).',h); end; lat=M(:,1); lon=M(:,2); depth_km=M(:,3)-0.5.*M(:,7).*sind(M(:,12)); N=numel(lat); if use_ll==1, x1_m=lon; x2_m=lat; else, llh=[lon.'; lat.'; zeros(1,N)]; origin=[rlon; rlat; 0]; xy=llh2local(llh, origin); x1_m=xy(2,:).'*1000; x2_m=xy(1,:).'*1000; end; x3_m=depth_km*1000; L_m=M(:,6)*1000; W_m=M(:,7)*1000; s_strk=M(:,8); s_ddip=M(:,9); s_amp=M(:,10); strike=M(:,11); dip=M(:,12); rake=M(:,13); slip_m=s_amp; idx=(~isfinite(slip_m))|slip_m==0; slip_m(idx)=hypot(s_strk(idx),s_ddip(idx)); slip_m(~isfinite(slip_m))=0; strike_out=round(strike); dip_out=round(dip); fid=fopen(outFile,'w'); if fid<0, error('Cannot open output'); end; fprintf(fid,'#  n  slip       x1       x2       x3   length  width strike  dip  rake\n'); for i=1:N, if use_ll==1, fprintf(fid,' %3d %7.2f %10.5f %10.5f %9.0f %8.2f %7.2f %7.0f %5.0f %7.1f\n', i, slip_m(i), x1_m(i), x2_m(i), x3_m(i), L_m(i), W_m(i), strike_out(i), dip_out(i), rake(i)); else, fprintf(fid,' %3d %7.2f %10.0f %10.0f %9.0f %8.2f %7.2f %7.0f %5.0f %7.1f\n', i, slip_m(i), x1_m(i), x2_m(i), x3_m(i), L_m(i), W_m(i), strike_out(i), dip_out(i), rake(i)); end; end; fclose(fid); catch ME, disp(getReport(ME,'extended')); exit(1); end; exit(0);"
echo "Wrote: $OUTFILE"