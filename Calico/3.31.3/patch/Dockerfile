FROM registry.suse.com/bci/bci-base:15.7 AS build

ARG TARGETPLATFORM=linux/s390x
ARG KUBERNETES_RELEASE=v1.33.3
WORKDIR /bin
RUN set -x \
 && curl -fsSLO "https://dl.k8s.io/release/${KUBERNETES_RELEASE}/bin/${TARGETPLATFORM}/kubectl" \
 && curl -LO "https://dl.k8s.io/release/${KUBERNETES_RELEASE}/bin/${TARGETPLATFORM}/kubectl.sha256" \
 && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check \
 && chmod +x kubectl
RUN useradd -u 1000 -U -m kubectl

FROM scratch
COPY --from=build /bin/kubectl /bin/kubectl
COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group
USER kubectl
ENTRYPOINT ["/bin/kubectl"]
CMD ["help"]