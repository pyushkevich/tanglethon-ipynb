PICSL Histology Annotator Data Export Scripts
=============================================

These scripts are used to download samples for a particular task on the PICSL
Histology Annotator (PHA) and organize them for using with PyTorch dataloaders.

First you need to obtain an API key. Navigate to
`https://histo.itksnap.org/auth/api/generate_key` and save to a file with
read-only permissions in your home directory, e.g., `$HOME/pha_key.json`

To clone samples for a training task, run `clone_samples.sh`. The options to the
command are self-explanatory. This will copy all training samples and a manifest
file describing them.

To organize samples for a classification experiment you need to write a JSON
file describing which classes you have and how labels on PHA map to these
classes. Here is an example:

    [
      {
        "classname": "tangle",
        "labels": [ "GM_tangle", "GM_pretangle" ],
        "ignore": 0
      },
      {
        "classname": "ignore",
        "labels": [ "ask_dave", "ambiguous" ],
        "ignore": 1
      },
      {
        "classname": "nontangle",
        "labels": [ ".*" ],
        "ignore": 0
      }
    ]

