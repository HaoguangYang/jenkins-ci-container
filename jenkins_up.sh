#!/bin/bash

# build or pull containers
docker build --pull -t ubuntu-dind:latest -f ./dind.dockerfile .
docker build --pull -t jenkins-customized:latest -f ./jenkins-server.dockerfile .
# docker build --pull -t jenkins-docker-ssh-agent:latest -f ./agent.dockerfile .

# fresh setup, copy the backup over
if [[ ! -d jenkins-data ]]; then
    mkdir jenkins-data
    if [[ -d jenkins-backup ]]; then
        cp -r jenkins-backup/ jenkins-data/
    else
        cp init-config.xml jenkins-data/config.xml
    fi
fi
#mkdir -p jenkins-certs
mkdir -p jenkins-workspace

if [[ ! $(docker network ls | grep jenkins) ]]; then
    docker network create jenkins
fi

# mount hardware accelerators
HARDWARE_EXTRA_ARGS=""
# NVIDIA GPUs
if [[ $(which nvidia-smi) && $(ls /dev | grep nvidia) ]]; then
    HARDWARE_EXTRA_ARGS="${HARDWARE_EXTRA_ARGS} --gpus all --env NVIDIA_DRIVER_CAPABILITIES=graphics,video,compute,utility,display"
fi
if [[ -d /usr/local/cuda ]]; then
    HARDWARE_EXTRA_ARGS="${HARDWARE_EXTRA_ARGS} -v /usr/local/cuda:/usr/local/cuda:ro"
fi
# AMD GPUs
if [[ $(ls /dev | grep kfd) ]]; then
    HARDWARE_EXTRA_ARGS="${HARDWARE_EXTRA_ARGS} --device=/dev/kfd -v /dev/kfd:/dev/kfd"
fi
# Xilinx FPGAs
if [[ $(ls /dev | grep xclmgmt) ]]; then
    for ITEM in $(ls /dev | grep xclmgmt); do
        HARDWARE_EXTRA_ARGS="${HARDWARE_EXTRA_ARGS} --device=/dev/${ITEM} -v /dev/${ITEM}:/dev/${ITEM}"
    done
fi
# AMD/Intel GPUs
if [[ $(ls /dev/dri | grep render) ]]; then
    HARDWARE_EXTRA_ARGS="${HARDWARE_EXTRA_ARGS} --device=/dev/dri -v /dev/dri:/dev/dri"
fi

# prep work to allow jenkins use docker command within its docker container
docker run \
  --name jenkins-docker-bridge \
  --rm \
  --detach \
  --privileged \
  --network jenkins \
  --network-alias docker \
  --env DOCKER_TLS_CERTDIR="" \
  --volume $(pwd)/jenkins-workspace:/home/jenkins/agent/workspace \
  --volume ${HOME}/.ssh:/home/jenkins/.ssh \
  --publish 2375:2375 \
  --publish 2376:2376 \
  ${HARDWARE_EXTRA_ARGS} \
  ubuntu-dind:latest \
  --storage-driver overlay2 \
  --insecure-registry docker:5000
#--env DOCKER_TLS_CERTDIR=/certs \
#--volume $(pwd)/jenkins-certs:/certs/client \
#--volume $(pwd)/jenkins-data:/var/jenkins_home \
#--volume $(pwd)/jenkins-workspace:/var/jenkins_home/workspace \

if [[ ! $(docker container ls -a | grep jenkins-customized-instance) ]]; then
    # the main jenkins instance
    docker run \
      --name jenkins-customized-instance \
      --restart=on-failure \
      --detach \
      --network jenkins \
      --env DOCKER_HOST=tcp://docker:2375 \
      --env JENKINS_OPTS="--prefix=/jenkins" \
      --publish 8080:8080 \
      --publish 50000:50000 \
      --volume $(pwd)/jenkins-data:/var/jenkins_home \
      --volume $(pwd)/jenkins-workspace:/var/jenkins_home/workspace \
      --volume ${HOME}/.ssh:/home/jenkins/.ssh \
      jenkins-customized:latest
    #--env DOCKER_HOST=tcp://docker:2376 \
    #--env DOCKER_CERT_PATH=/certs/client \
    #--env DOCKER_TLS_VERIFY=1 \
    #--volume $(pwd)/jenkins-certs:/certs/client:ro \

    # build internal agent image and push to local registry
    docker cp ./agent.dockerfile jenkins-docker-bridge:/home/jenkins/agent/agent.dockerfile
    docker exec -t jenkins-docker-bridge /bin/bash -c "\
        while ( ! docker stats --no-stream &> /dev/null ); do \
            echo 'Waiting for docker host to come online...'; \
            sleep 10; \
        done && \
        docker run --detach --publish 5000:5000 --restart always --name registry registry:latest && \
        docker build --pull -t jenkins-docker-agent:latest -f /home/jenkins/agent/agent.dockerfile . && \
        docker tag jenkins-docker-agent docker:5000/jenkins-docker-agent && \
        docker push docker:5000/jenkins-docker-agent && \
        docker image rm jenkins-docker-agent:latest && \
        docker system prune --volumes --force"
fi
