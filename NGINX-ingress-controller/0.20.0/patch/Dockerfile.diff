--- images/e2e/Dockerfile.original	2019-02-21 03:43:07.905538714 -0500
+++ images/e2e/Dockerfile	2019-02-21 03:45:57.055385765 -0500
@@ -12,7 +12,7 @@
 # See the License for the specific language governing permissions and
 # limitations under the License.
 
-FROM quay.io/kubernetes-ingress-controller/nginx-amd64:0.63
+FROM quay.io/kubernetes-ingress-controller/nginx-s390x:0.63
 
 RUN clean-install \
   g++ \
@@ -26,8 +26,8 @@
   pkg-config
 
 ENV GOLANG_VERSION 1.11
-ENV GO_ARCH        linux-amd64
-ENV GOLANG_SHA     b3fcf280ff86558e0559e185b601c9eade0fd24c900b4c63cd14d1d38613e499
+ENV GO_ARCH        linux-s390x
+ENV GOLANG_SHA     c113495fbb175d6beb1b881750de1dd034c7ae8657c30b3de8808032c9af0a15
 
 RUN set -eux; \
   url="https://golang.org/dl/go${GOLANG_VERSION}.${GO_ARCH}.tar.gz"; \
