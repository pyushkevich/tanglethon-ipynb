#!/bin/bash
EXP=${1?}
NTRAIN=2000
NVAL=1000
NTEST=1000

CSV=manifest.csv

# Loop over the cross-validation fold
SUBJUNIQ=$(cat $CSV | awk -F, '{print $12}' | sort -u)

# For each cross-validation subject, create a fold
for S in $SUBJUNIQ; do

  # Create dir for fold
  FOLDDIR=./$EXP/fold_${S}
  mkdir -p $FOLDDIR

  echo "FOLD $S"

  # Parse lines
  for line in $(cat $CSV); do

    VALS=$(echo $line | awk -F, '{print $1,$3,$12}')
    read -r ID LABEL SPEC <<< $VALS

    # Determine the class
    if echo $LABEL | egrep "^(tangle|pretangle)$" > /dev/null; then
      CLASS="tangle"
    elif echo $LABEL | egrep "^(ambiguous|ask_dave)$" > /dev/null; then
      CLASS="ignore"
    else
      CLASS="nontangle"
    fi

    # Determine the destination
    if [[ $SPEC == $S ]]; then
      DEST="test"
    else
      DEST="train_val"
    fi

    echo $ID $LABEL $SPEC $CLASS $DEST 

  done | sort -R > $FOLDDIR/fold_master.csv

  # Direct into separate files
  for C in tangle nontangle; do

    cat $FOLDDIR/fold_master.csv | awk -v c=$C '$4==c && $5=="train_val" {print $1,$2,$3}' \
      | head -n $NTRAIN > $FOLDDIR/fold_train_${C}.txt
    cat $FOLDDIR/fold_master.csv | awk -v c=$C '$4==c && $5=="train_val" {print $1,$2,$3}' \
      | tail -n +$NTRAIN | head -n $NVAL > $FOLDDIR/fold_val_${C}.txt
    cat $FOLDDIR/fold_master.csv | awk -v c=$C '$4==c && $5=="test" {print $1,$2,$3}' \
      | head -n $NTEST > $FOLDDIR/fold_test_${C}.txt

  done

for CLASS in tangle nontangle; do
  for STAGE in train val "test"; do
    mkdir -p $FOLDDIR/$STAGE/$CLASS
    rm -rf $FOLDDIR/$STAGE/$CLASS/*.png
    for id in $(cat $FOLDDIR/fold_${STAGE}_${CLASS}.txt | awk '{print $1}'); do
      ln -sf $PWD/all_patches/${id}.png $FOLDDIR/$STAGE/$CLASS/
    done
  done
done
  





done
