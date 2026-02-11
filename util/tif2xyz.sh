#!/bin/bash
for i in *.tif; do
    echo "$i"
    base="${i%.tif}"
    gdal2xyz.py -skipnodata "$i" "${base}.xyz"
    awk 'tolower($3) != "nan"' "${base}.xyz" > "${base}_nonan.xyz"
    mv "${base}_nonan.xyz" "${base}.xyz"
done
