#!/bin/bash

# tear down the containers
docker container stop jenkins-docker-bridge jenkins-customized-instance
docker container rm jenkins-customized-instance
