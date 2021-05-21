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
USAGETEXT
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

SERVER="https://histo.itksnap.org"
unset APIKEY TASKID OUTDIR SKIPPATCHES EXACTPATCHES
while getopts "s:k:t:o:PX" opt; do
  case $opt in

    s) SERVER=$OPTARG;;
    k) APIKEY=$OPTARG;;
    t) TASKID=$OPTARG;;
    o) OUTDIR=$OPTARG;;
    P) SKIPPATCHES=1;;
    X) EXACTPATCHES=1;;
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
curl -s -c $COOKIEFILE -d api_key=$(cat $APIKEY | jq -r .api_key) \
  $SERVER/auth/api/login -o $RESPFILE

if [[ $(cat $RESPFILE | jq -r .status) != "ok" ]]; then
  echo "Login failed: $(cat $RESPFILE | jq -r .error)"
  exit 2
fi

# Raw and filtered manifest files
MANI_RAW="$OUTDIR/manifest_server.csv"
MANI_FLT="$OUTDIR/manifest.csv"

# Download the manifest file
curl -s -b $COOKIEFILE -o "$MANI_RAW" \
  $SERVER/dltrain/api/task/$TASKID/samples/manifest.csv 

# Generate patches
mkdir -p $OUTDIR/all_patches
rm -rf $OUTDIR/all_patches/*
rm -rf $MANI_FLT

while IFS= read -r line; do

  # Get ID
  id=$(echo $line | awk -F, '{print $1}')

  # Download patch
  PATCH="$OUTDIR/all_patches/${id}.png"

  if [[ $SKIPPATCHES -eq 1 ]]; then

    echo "$line" >> "$MANI_FLT"

  elif [[ $EXACTPATCHES -eq 1 ]]; then

    # Read the dimensions, in integers
    DIMS=$(echo $line | awk -F, '{printf("%d_%d"), int($6), int($7)}')
    PURL="$SERVER/dltrain/api/sample/${id}/0/image_${DIMS}.png"

    curl -s -b $COOKIEFILE -o "$PATCH" "${PURL}" && \
      echo "downloaded $PATCH" && \
      identify "$PATCH" && \
      echo "$line" >> "$MANI_FLT"

    echo "cloned patch $id"

  else

    # Download default-size patch
    PURL="$SERVER/dltrain/api/sample/${id}/image.png"
    curl -s -b $COOKIEFILE -o "$PATCH" "$PURL" && \
      echo "downloaded $PATCH" && \
      identify "$PATCH" && \
      echo "$line" >> "$MANI_FLT"

    echo "cloned patch $id"
  fi

done < "$MANI_RAW"

# List unique specimens
cat "$MANI_FLT" | awk -F, 'NR > 1 {print $12}' | sort -u \
  > $OUTDIR/specimens.txt
