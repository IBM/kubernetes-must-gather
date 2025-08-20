#!/bin/sh
COMMAND="$(echo "export $(grep "^VERSION" collection-scripts/utilities/constants.sh)")"
eval $COMMAND
if [ "${IMAGENAMESPACE}" = "" ]; then
  echo "Required (for example):"
  echo "export IMAGENAMESPACE=\"customimages\""
  exit 1
fi
echo "VERSION=${VERSION}"
echo "IMAGENAMESPACE=${IMAGENAMESPACE}"
rm -rf must-gather.local*
podman build --platform linux/amd64 -t kubernetes-must-gather . && \
  REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}') && \
  podman login --tls-verify=false -u $(oc whoami | sed 's/://g') -p $(oc whoami -t) ${REGISTRY}
podman push --tls-verify=false localhost/kubernetes-must-gather:latest ${REGISTRY}/${IMAGENAMESPACE}/kubernetes-must-gather:${VERSION} && \
  echo "" && \
  echo "=======" && \
  echo "export VERSION=${VERSION}" && \
  echo 'oc adm must-gather --image=image-registry.openshift-image-registry.svc:5000/${IMAGENAMESPACE}/kubernetes-must-gather:${VERSION} -- gather'
