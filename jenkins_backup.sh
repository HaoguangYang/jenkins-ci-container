#!/bin/bash

# backup settings
mkdir -p jenkins-backup
cp jenkins-data/config.xml jenkins-backup/
cp -r jenkins-data/users jenkins-backup/
