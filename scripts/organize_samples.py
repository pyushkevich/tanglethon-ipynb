#!/usr/bin/env python3
import os
import sys
import csv
import argparse
import re
import random
import json
import glob


def nsam(n, k_max):
    """helper function to compute number of samples needed"""
    return n if k_max == 0 else min(n, k_max)


# Set up the arguments to the script
parser = argparse.ArgumentParser()
parser.add_argument('-w', '--workdir', type=str, required=True, metavar='dir',
                    help='Working directory (created by clone_samples)')
parser.add_argument('-e', '--expid', type=str, required=True, metavar='id',
                    help='Experiment id/name (folder created in working directory)')
parser.add_argument('-l', '--label-info', type=str, required=True, metavar='file',
                    help='JSON file describing the classes and how they map to labels')
parser.add_argument('-n', '--max-samples', type=int, default=0, metavar='N',
                    help='Maximum number of samples to include (per fold)')
parser.add_argument('-t', '--max-train', type=int, default=2000, metavar='N',
                    help='Max number of samples per class to take for train')
parser.add_argument('-v', '--max-val', type=int, default=1000, metavar='N',
                    help='Max number of samples per class to take for val')
parser.add_argument('-T', '--max-test', type=int, default=0, metavar='N',
                    help='Max number of samples per class to take for test')
parser.add_argument('-R', '--random-seed', type=int, default=0, metavar='N',
                    help='Random seed')
parser.add_argument('-s', '--test-specimens', type=str, metavar='file',
                    help=('File listing specimens ids to use for testing. These specimens ',
                          'will not be included in training'))
args = parser.parse_args()

# Fields in the manifest file
fld_manifest = [
    "id", "slide", "label", "x", "y", "w", "h",
    "t_create", "u_create", "t_modify", "u_modify",
    "specimen", "block", "stain" ]

# Read the test specimen name
test_specimens = set()
if args.test_specimens is not None:
    with open(args.test_specimens, 'rt') as f_test_specimens:
        reader = csv.DictReader(f_test_specimens, fieldnames=['specimen'])
        test_specimens = set([row['specimen'] for row in reader])

# Read the label json
with open(args.label_info, 'rt') as f_label_info:
    label_info = json.load(f_label_info)

# Map labels to classes
for li in label_info:
    li['re'] = [ re.compile(l) for l in li['labels'] ]

# As we read the manifest, we will assign its elements to classes
c_sam = { x['classname'] : [] for x in label_info }

# Keep track of ignored classes
c_ign = { x['classname'] : x['ignore'] > 0 for x in label_info }

# Read the manifest file
with open(os.path.join(args.workdir, 'manifest.csv'), 'rt') as f_manifest:
    reader = csv.DictReader(f_manifest, fieldnames=fld_manifest)
    for row in reader:

        # Determine the class of the sample
        s_class = None
        for li in label_info:
            if any(lre.match(row['label']) for lre in li['re']):
                s_class = li['classname']
                break

        c_sam[s_class].append(row)

# Table header
print('%20s  %8s  %8s  %8s  %8s' % ('class','total','train','val','test'))
print('%20s  %8s  %8s  %8s  %8s' % ('-----','-----','-----','---','----'))

# For each class, map samples to test, train, val
for cls, sam in c_sam.items():

    # Save the number of available samples
    n_total = len(sam)

    # Shuffle the samples
    random.shuffle(sam)

    # If test specimens are specified, the test set is filtered out
    if c_ign[cls] is False:
        if len(test_specimens):

            # Select test samples
            sam_test = list(filter(lambda x: x['specimen'] in test_specimens, sam))
            n_test = nsam(len(sam_test), args.max_test)
            sam_test = sam_test[:n_test]

            # Select training samples
            sam_tv = list(filter(lambda x: x['specimen'] not in test_specimens, sam))
            n_train = nsam(int(len(sam_tv) * 0.67), args.max_train)
            sam_train,sam_tv = sam_tv[:n_train], sam_tv[n_train:]

            # Select validation samples
            n_val = nsam(len(sam_tv), args.max_val)
            sam_val = sam_tv[:n_val]

        else:

            # Select training samples
            n_train = nsam(len(sam) // 2, args.max_train)
            sam_train,sam = sam[:n_train], sam[n_train:]

            # Select validation samples
            n_val = nsam(len(sam) // 2, args.max_val)
            sam_val,sam = sam[:n_val], sam[n_val:]

            # Select test samples
            n_test = nsam(len(sam), args.max_test)
            sam_test = sam[:n_test]

        # Print statistics for this class
        print('%20s  %8d  %8d  %8d  %8d' % (cls, n_total, len(sam_train), len(sam_val), len(sam_test)))

        # Turn into a dictionary
        sd = {'train': sam_train, 'val': sam_val, 'test': sam_test}

        # Iterate over train, val, test
        for fold, fsam in sd.items():

            # Create the directory
            wdir = os.path.join(args.workdir, args.expid, 'patches', fold, cls)
            os.makedirs(wdir, exist_ok=True)

            # Remove old links
            for fn in glob.glob(os.path.join(wdir, '*.png')):
                os.remove(fn)

            # Create new links
            for s in fsam:
                os.symlink(
                   '../../../../all_patches/%s.png' % s['id'],
                   os.path.join(wdir, '%s.png' % s['id']))

    else:
        print('%20s  %8d  %8d  %8d  %8d' % (cls, n_total, 0, 0, 0))

