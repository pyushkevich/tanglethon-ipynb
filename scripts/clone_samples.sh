#!/bin/bash

function usage()
{
  cat <<-USAGETEXT
    clone_samples: download training samples from a histoannot server
    usage:
      clone_samples.sh [options]
    options:
      -s <url>    Server URL (default: https://histo.itksnap.org)
      -k <file>   Path to JSON file with your API key
      -t <int>    Task ID on the server
      -o <dir>    Output directory for the samples
USAGETEXT
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

SERVER="https://histo.itksnap.org"
unset APIKEY TASKID OUTDIR
while getopts "s:k:t:o:" opt; do
  case $opt in

    s) SERVER=$OPTARG;;
    k) APIKEY=$OPTARG;;
    t) TASKID=$OPTARG;;
    o) OUTDIR=$OPTARG;;
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

# Download the manifest file
curl -s -b $COOKIEFILE -o $OUTDIR/manifest.csv \
  $SERVER/dltrain/api/task/$TASKID/samples/manifest.csv 

# List unique specimens
cat $OUTDIR/manifest.csv | awk -F, 'NR > 1 {print $12}' | sort -u \
  > $OUTDIR/specimens.txt

# Generate patches
mkdir -p $OUTDIR/all_patches
rm -rf $OUTDIR/all_patches/*

for id in $(cat $OUTDIR/manifest.csv | awk -F, 'NR > 1 {print $1}'); do

  curl -s -b $COOKIEFILE -o $OUTDIR/all_patches/${id}.png \
    $SERVER/dltrain/api/sample/${id}/image.png          

  echo "cloned patch $id"

done

