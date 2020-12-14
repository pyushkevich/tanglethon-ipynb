#!/bin/bash

function usage()
{
  cat <<-USAGETEXT

    organize_folds: generate train/val/test folds for samples from histoannot
    usage: 
      organize_folds.sh [options] 
    required options:
      -w <dir>    Working directory (created by clone_samples)
      -e <string> Experiment id/name (folder created in working directory)
      -l <file>   JSON file describing the classes and how they map to labels
    optional:
      -n <int>    Maximum number of samples to include (per fold)
      -t <int>    Max number of samples per class to take for train (2000)
      -v <int>    Max number of samples per class to take for val (1000)
      -T <int>    Max number of samples per class to take for test (0, i.e., all)
      -R <int>    Random seed 
      -s <file>   File listing specimens ids to use for testing. These specimens
                  will not be included in training
USAGETEXT
}


# Print usage by default
if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi


# Read the parameters
unset NMAX RSEED WDIR EXPID LFILE STEST SKIPORG
F_TRAIN=2000
F_VAL=1000
F_TEST=0
while getopts "w:e:l:n:t:v:T:R:s:x" opt; do
  case $opt in

    w) WDIR=$OPTARG;;
    e) EXPID=$OPTARG;;
    l) LFILE=$OPTARG;;
    n) NMAX=$OPTARG;;
    t) F_TRAIN=$OPTARG;;
    v) F_VAL=$OPTARG;;
    T) F_TEST=$OPTARG;;
    R) NFOLDS=$OPTARG;;
    s) STEST=$OPTARG;;
    x) SKIPORG=1;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;

  esac
done

# Check the parameters
if [[ ! $WDIR || ! $EXPID || ! $LFILE ]]; then
  echo "Missing required parameters"
  exit 2
fi

# Check working directory
CSV=$WDIR/manifest.csv
if [[ ! -f $CSV ]]; then
  echo "Missing manifest.csv in the working directory"
  exit 2
fi

# Number of classes
N_CLASSES=$(cat $LFILE | jq -r '. | length')
set -a CLASSES
for ((i=0;i<$N_CLASSES;i++)); do
  CLASSES[$i]=$(cat $LFILE | jq -r ".[$i].classname")
done

# Test specimens
if [[ $STEST ]]; then
  TEST_SPECIMENS=$(cat $STEST)
fi

# File where the initial sample assignment goes
EDIR=$WDIR/$EXPID
ASSIGN_CSV=$EDIR/init_assignment.csv
mkdir -p $EDIR

# Assign samples to test/val/train buckets. 
#   - if STEST exists, all samples in STEST go to the test bucket
#   - for each label, split into train/val/test based on proportion
#     so that train and test are balanced on label
if [[ $SKIPORG && -f $ASSIGN_CSV ]]; then
  echo "Skipping initial assignment"
else
  rm $ASSIGN_CSV
  cat $CSV | tail -n +2 | while IFS= read -r line; do

    # Read sample
    ID="$(echo "$line" | awk -F ',' '{print $1}')"
    LABEL="$(echo "$line" | awk -F ',' '{print $3}')"
    SPECIMEN="$(echo "$line" | awk -F ',' '{print $12}')"
    unset SAMPLE_CLASS

    # Determine the class
    for ((i=0; i<$N_CLASSES; i++)); do

      # Careful here: labels may have spaces
      NPAT=$(jq -r ".[$i].labels | length" $LFILE)

      for ((j=0; j<$NPAT; j++)); do
        pat=$(jq -r ".[$i].labels[$j]" $LFILE)
        if [[ $LABEL =~ $pat ]]; then
          SAMPLE_CLASS=${CLASSES[i]}
          break
        fi 
      done

      if [[ $SAMPLE_CLASS ]]; then break; fi
    done

    # Determine if the sample is destined for test, train/val, or either
    if [[ $STEST ]]; then
      # Check if the specimen is in the test
      TARGET="train_val"
      for t in $TEST_SPECIMENS; do
        if [[ $SPECIMEN == $t ]]; then
          TARGET="test"
          break
        fi
      done
    else
      TARGET="any"
    fi

    # Report class assignment
    echo $ID,$LABEL,$SAMPLE_CLASS,$SPECIMEN,$TARGET >> $ASSIGN_CSV
    echo "sample $ID with label '$LABEL' assigned to class $SAMPLE_CLASS target $TARGET"

  done
fi

function calc_n_samples()
{
  local NSAM=$1
  local FRAC=$2
  local NMAX=$3

  echo $NSAM | awk -v f=$FRAC -v m=$NMAX \
    '{k=int(f * $1); if (m > 0 && k > m) k=m; print k}'
}

# Loop over each class
for ((i=0; i<$N_CLASSES; i++)); do

  # Create the training, validation and test csvs
  CSV_TRAIN=$EDIR/samples_train_${CLASSES[i]}.csv
  CSV_VAL=$EDIR/samples_val_${CLASSES[i]}.csv
  CSV_TEST=$EDIR/samples_test_${CLASSES[i]}.csv
  rm -f $CSV_TEST $CSV_VAL $CSV_TRAIN

  if [[ $(cat $LFILE | jq -r ".[$i].ignore") == 0 ]]; then

    if [[ $STEST ]]; then

      SAMP_TV=$(mktemp /tmp/samples_trainval.XXXXXX)
      SAMP_TEST=$(mktemp /tmp/samples_test.XXXXXX)

      # Get eligible train/val samples for this class
      cat $ASSIGN_CSV | awk -F, -v c="${CLASSES[i]}" \
        '$3==c && $5 != "test" {print $0}' | sort -r > $SAMP_TV

      cat $ASSIGN_CSV | awk -F, -v c="${CLASSES[i]}" \
        '$3==c && $5 == "test" {print $0}' | sort -r > $SAMP_TEST

      # Get number of training samples and test samples
      NSAMP_TV=$(cat $SAMP_TV | wc -l)
      NSAMP_TEST=$(cat $SAMP_TEST | wc -l)

      # This is the number of training samples for this class
      NTRAIN=$(calc_n_samples $NSAMP_TV 0.67 $F_TRAIN)
      NVAL=$(calc_n_samples $NSAMP_TV 0.33 $F_VAL)
      NTEST=$(calc_n_samples $NSAMP_TEST 1.0 $F_TEST)

      # Take the training samples off the top
      cat $SAMP_TV | awk -F, -v n1=$NTRAIN -v n2=$NVAL \
        'BEGIN {OFS=","} NR <= n1 {print $1,$2,$3,$4} ' >> $CSV_TRAIN

      # Take the validation samples
      cat $SAMP_TV | awk -F, -v n1=$NTRAIN -v n2=$NVAL \
        'BEGIN {OFS=","} NR > n1 && NR <= n1+n2 {print $1,$2,$3,$4} ' >> $CSV_VAL

      # Take the test samples
      cat $SAMP_TEST | awk -F, -v n1=$NTEST \
        'BEGIN {OFS=","} NR <= n1 {print $1,$2,$3,$4} ' >> $CSV_TEST

    else

      SAMP_ALL=$(mktemp /tmp/samples_all.XXXXXX)

      # Get eligible train/val/test samples for this class
      cat $ASSIGN_CSV | awk -F, -v c="${CLASSES[i]}" \
        '$3==c {print $0}' | sort -r > $SAMP_ALL

      # Get number of training samples and test samples
      NSAMP_ALL=$(cat $SAMP_ALL | wc -l)

      # This is the number of training samples for this class
      NTRAIN=$(calc_n_samples $NSAMP_ALL 0.5 $F_TRAIN)
      NVAL=$(calc_n_samples $NSAMP_ALL 0.25 $F_VAL)
      NTEST=$(calc_n_samples $NSAMP_ALL 0.25 $F_TEST)

      # Take the training samples off the top
      cat $SAMP_ALL | awk -F, -v n1=$NTRAIN -v n2=$NVAL -v n3=$NTEST \
        'BEGIN {OFS=","} NR <= n1 {print $1,$2,$3,$4} ' >> $CSV_TRAIN

      # Take the validation samples
      cat $SAMP_ALL | awk -F, -v n1=$NTRAIN -v n2=$NVAL -v n3=$NTEST \
        'BEGIN {OFS=","} NR <= n1+n2 && NR > n1 {print $1,$2,$3,$4} ' >> $CSV_VAL

      # Take the test samples
      cat $SAMP_ALL | awk -F, -v n1=$NTRAIN -v n2=$NVAL -v n3=$NTEST \
        'BEGIN {OFS=","} NR <= n1+n2+n3 && NR > n1+n2 {print $1,$2,$3,$4} ' >> $CSV_TEST
    fi

    # These are the patches we are linking
    echo "Train/Val/Test for label ${CLASSES[i]}: $NTRAIN/$NVAL/$NTEST"

    # Link each patch
    for STAGE in "train" "val" "test"; do

      PDIR=$EDIR/patches/$STAGE/${CLASSES[i]}
      mkdir -p $PDIR
      rm -rf $PDIR/*.png
      for id in $(cat $EDIR/samples_${STAGE}_${CLASSES[i]}.csv | awk -F, '{print $1}'); do
        ln -sf "../../../../all_patches/${id}.png" $PDIR/
      done

    done

  fi
done
