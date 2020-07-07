#!/bin/bash
mkdir -p all_patches

for id in $(cat manifest.csv | awk -F, '{print $1}'); do

  wget -b -o /dev/null -O all_patches/${id}.png http://histo.itksnap.org/dltrain/api/sample/${id}/image.png


done

