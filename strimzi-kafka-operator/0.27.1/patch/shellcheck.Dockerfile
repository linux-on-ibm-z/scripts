# © Copyright IBM Corporation 2022.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
########################## Dockerfile for getting shellcheck (0.7.0) #######################

# Base Image
ARG BASE_IMG=s390x/ubuntu:20.04
FROM $BASE_IMG

# The author
LABEL maintainer="LoZ Open Source Ecosystem (https://www.ibm.com/developerworks/community/groups/community/lozopensource)"

RUN apt-get update && apt-get install -y shellcheck && \
# Tidy up (Clear cache data)
    apt-get clean

WORKDIR /opt/project
# End of Dockerfile
