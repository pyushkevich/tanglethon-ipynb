#!/usr/bin/env python3
from PIL import Image
import sys

try:
    x = Image.open(sys.argv[1])
    print(x)
    sys.exit(0)
except Exception as e: 
    print(e)
    sys.exit(255)
