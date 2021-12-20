#!/usr/bin/python3
import os

dir='/home/dax/code_base/ansible_projects'

for root, dirs, files in os.walk(dir):
  for name in files:
    if name.endswith((".retry")):
      os.remove(os.path.join(root, name))
