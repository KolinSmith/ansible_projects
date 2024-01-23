#!/usr/bin/python3
#run this before doing any git pushes so you don't expose any secrets
import os

dir = '/home/dax/'

for root, dirs, files in os.walk(dir):
    for name in files:
        if name == "ansible.log":
            os.remove(os.path.join(root, name))
