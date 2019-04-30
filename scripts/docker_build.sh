#!/bin/bash

# Copyright 2019 Apinf Oy
#This file is covered by the EUPL license.
#You may obtain a copy of the licence at
#https://joinup.ec.europa.eu/community/eupl/og_page/european-union-public-licence-eupl-v11

set -ev

pwd

cd docker

#docker build -t apinf/apinf-umbrella:$DOCKER_TAG .
docker build -t apinf/apinf-umbrella:test .

if [ "${TRAVIS_PULL_REQUEST}" = "false" -a "${TRAVIS_REPO_SLUG}" = "apinf/apinf-umbrella" ]
then
docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"
#docker push apinf/platform:$DOCKER_TAG
fi
