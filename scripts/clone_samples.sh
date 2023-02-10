#!/bin/bash

function usage()
{
  cat <<-USAGETEXT
    clone_samples: download training samples from a histoannot server
    usage:
      clone_samples.sh [options]
    required options:
      -s <url>    Server URL (default: https://histo.itksnap.org)
      -k <file>   Path to JSON file with your API key
      -t <int>    Task ID on the server
      -o <dir>    Output directory for the samples
    additional options:
      -P          Skip downloading patches (only gets manifest file)
      -X          Download exact size patches (slower)
      -l <n>      Limit download to <n> random samples per class
      -d <regex>  Drop samples with label matching regex
USAGETEXT
}

function checkpng()
{
  $(dirname "${BASH_SOURCE[0]}")/checkpng.py $1
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

SERVER="https://histo.itksnap.org"
unset APIKEY TASKID OUTDIR SKIPPATCHES EXACTPATCHES NMAX DROPREGEX
while getopts "s:k:t:o:l:d:PX" opt; do
  case $opt in

    s) SERVER=$OPTARG;;
    k) APIKEY=$OPTARG;;
    t) TASKID=$OPTARG;;
    o) OUTDIR=$OPTARG;;
    P) SKIPPATCHES=1;;
    X) EXACTPATCHES=1;;
    l) NMAX=$OPTARG;;
    d) DROPREGEX=$OPTARG;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;

  esac
done

if [[ ! $OUTDIR || ! $APIKEY || ! $TASKID ]]; then 
  echo "Missing required options, see usage"
  exit 2
fi

# Create the output directory
mkdir -p $OUTDIR

# Login using the api key
COOKIEFILE=$(mktemp /tmp/cookie.XXXXXX)
RESPFILE=$(mktemp /tmp/response.XXXXXX)
curl -sk -c $COOKIEFILE -d api_key=$(cat $APIKEY | jq -r .api_key) \
  $SERVER/auth/api/login -o $RESPFILE
chmod 600 $COOKIEFILE

if [[ $(cat $RESPFILE | jq -r .status) != "ok" ]]; then
  echo "Login failed: $(cat $RESPFILE | jq -r .error)"
  exit 2
fi

# Raw and filtered manifest files
MANI_RAW="$OUTDIR/manifest_server.csv"
MANI_FLT="$OUTDIR/manifest.csv"

# Download the manifest file
curl -sk -b $COOKIEFILE -o "$MANI_RAW" \
  $SERVER/dltrain/api/task/$TASKID/samples/manifest.csv 

# Optionally process the raw file to limit to NMAX per class
if [[ $NMAX || $DROPREGEX ]]; then
  head -n 1 $MANI_RAW > "$OUTDIR/manifest_subset.csv"
  awk -F, 'NR>1 {print $3}' < $MANI_RAW | sort -u > "$OUTDIR/unique_labels.csv"
  while IFS= read -r lab; do
    if [[ $DROPREGEX && $lab =~ $DROPREGEX ]]; then
      continue
    fi
    if [[ $NMAX ]]; then
      awk -F, -v x="$lab" '$3==x {print $0}' < $MANI_RAW | sort -R | head -n $NMAX >> "$OUTDIR/manifest_subset.csv"
    else
      awk -F, -v x="$lab" '$3==x {print $0}' < $MANI_RAW | sort -R >> "$OUTDIR/manifest_subset.csv"
    fi
    echo "Label $lab"
  done < "$OUTDIR/unique_labels.csv" 
  MANI_RAW="$OUTDIR/manifest_subset.csv"
fi

# Generate patches
mkdir -p $OUTDIR/all_patches
rm -rf $OUTDIR/all_patches/*
rm -rf $MANI_FLT

while IFS= read -r line; do

  # Get parts of the line
  IFS=, read -r id slide_name label_name x y w h args <<< "$line"
  if [[ $id == "id" ]]; then
    echo "$line" >> "$MANI_FLT"
    continue
  fi

  # Download patch
  PATCH="$OUTDIR/all_patches/${id}.png"

  if [[ $SKIPPATCHES -eq 1 ]]; then

    echo "$line" >> "$MANI_FLT"

  elif [[ $EXACTPATCHES -eq 1 ]]; then

    # Read the dimensions, in integers
    PURL="$SERVER/dltrain/api/sample/${id}/0/image_${w}_${h}.png"

    curl -sk -b $COOKIEFILE -o "$PATCH" "${PURL}" && \
      echo "downloaded $PATCH" && \
      checkpng "$PATCH" && \
      echo "$line" >> "$MANI_FLT"

    echo "cloned patch $id"

  else

    # Download default-size patch
    PURL="$SERVER/dltrain/api/sample/${id}/image.png"
    curl -sk -b $COOKIEFILE -o "$PATCH" "$PURL" && \
      echo "downloaded $PATCH" && \
      checkpng "$PATCH" && \
      echo "$line" >> "$MANI_FLT"

    echo "cloned patch $id"
  fi

done < "$MANI_RAW"

# List unique specimens
cat "$MANI_FLT" | awk -F, 'NR > 1 {print $12}' | sort -u \
  > $OUTDIR/specimens.txt
