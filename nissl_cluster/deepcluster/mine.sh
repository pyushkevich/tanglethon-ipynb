# Copyright (c) 2017-present, Facebook, Inc.
# All rights reserved.
#
# This source code is licensed under the license found in the
# LICENSE file in the root directory of this source tree.
#
#!/bin/bash

DIR="/home/pyushkevich/data/nissl/patches/train"
ARCH="alexnet"
LR=0.05
WD=-5
K=20
WORKERS=12
EXP="/home/pyushkevich/resnet/nissl_cluster/exp01"
PYTHON="/home/pyushkevich/miniconda3/envs/deepcluster/bin/python2.7"

mkdir -p ${EXP}

CUDA_VISIBLE_DEVICES=0 ${PYTHON} main.py ${DIR} --exp ${EXP} --arch ${ARCH} \
  --lr ${LR} --wd ${WD} --k ${K} --sobel --verbose --workers ${WORKERS}
