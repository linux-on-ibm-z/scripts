--- a/bin/init_helm.sh
+++ b/bin/init_helm.sh
@@ -67,10 +67,7 @@ if [ ! -f "${ISTIO_OUT}/version.helm.${HELM_VER}" ] ; then
     TD=$(mktemp -d)
     # Install helm. Please keep it in sync with .circleci
     cd "${TD}" && \
-        curl -Lo "${TD}/helm.tgz" "https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VER}-${LOCAL_OS}-amd64.tar.gz" && \
-        tar xfz helm.tgz && \
-        mv ${LOCAL_OS}-amd64/helm "${ISTIO_OUT}/helm-${HELM_VER}" && \
-        cp "${ISTIO_OUT}/helm-${HELM_VER}" "${ISTIO_OUT}/helm" && \
+        cp <path-to-Helm-binary/helm> "${ISTIO_OUT}/helm" && \
         rm -rf "${TD}" && \
         touch "${ISTIO_OUT}/version.helm.${HELM_VER}"
 fi
