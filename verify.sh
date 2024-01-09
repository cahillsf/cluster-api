function TESTIMAGE() {
  IMAGE="${1}"
  GREPVALUE="${2}"
  BINARYPATH="${3:-manager}"

  MANIFEST="$(crane manifest "${IMAGE}")"
  for ARCHITECTURE in $(echo "${MANIFEST}" | jq -r '.manifests[].platform.architecture'); do
    echo "> Testing ${IMAGE} ARCH=$ARCHITECTURE"
    rm -rf extracted || true
    digest=$(echo "${MANIFEST}" | jq -r '.manifests[] | select(.platform.architecture == "'${ARCHITECTURE}'") | .digest')
    imgpkg pull -i ${IMAGE}@${digest} -o extracted > /dev/null
    go version -m extracted/${BINARYPATH} | grep "\tpath" | grep -q ${GREPVALUE} || (echo "FAILED ${IMAGE} ARCH=${ARCHITECTURE}, expected value for path: \"${GREPVALUE}\""; go version -m extracted/${BINARYPATH} | grep "\tpath")
  done
}


# function TESTIMAGES() {
  TAG="${1}"
  REGISTRY="${2}"
  TESTIMAGE "${REGISTRY}/capd-manager:${TAG}" "command-line-arguments$"
  TESTIMAGE "${REGISTRY}/test-extension:${TAG}" "sigs.k8s.io/cluster-api/test/extension$"
# }

# TESTIMAGES "dev4" "us-central1-docker.pkg.dev/datadog-sandbox/cahillsf