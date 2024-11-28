ARG UBUNTU=s390x/ubuntu:22.04
FROM ${UBUNTU} AS ubuntu
ARG ARCH=s390x
ARG K8S_VERSION=v1.29.9
WORKDIR /bin
RUN set -x \
 && apt update && apt install -y sudo curl \
 && curl -fsSLO https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/kubectl \
 && chmod +x kubectl

FROM scratch
COPY --from=ubuntu /bin/kubectl /bin/kubectl
ENTRYPOINT ["/bin/kubectl"]
