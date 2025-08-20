#!/bin/sh
COMMAND="$(echo "export $(grep "^VERSION" collection-scripts/utilities/constants.sh)")"
eval $COMMAND
echo "VERSION=${VERSION}"
rm -rf must-gather.local*
podman manifest create quay.io/ibm/kubernetes-must-gather:latest
for i in $(podman manifest inspect quay.io/ibm/kubernetes-must-gather:latest | jq '.manifests[].digest' | tr '\n' ' ' | sed 's/"//g'); do podman manifest remove quay.io/ibm/kubernetes-must-gather:latest $i; done
podman build --platform linux/amd64,linux/ppc64le,linux/s390x,linux/arm64 --jobs=1 --manifest quay.io/ibm/kubernetes-must-gather:latest . && \
  podman login quay.io
podman manifest push --all quay.io/ibm/kubernetes-must-gather:latest docker://quay.io/ibm/kubernetes-must-gather:$VERSION && \
  podman manifest push --all quay.io/ibm/kubernetes-must-gather:latest docker://quay.io/ibm/kubernetes-must-gather:latest && \
  echo "" && \
  echo "=======" && \
  echo "export VERSION=${VERSION}" && \
  echo 'oc adm must-gather --image=quay.io/ibm/kubernetes-must-gather:$VERSION -- gather -h'
