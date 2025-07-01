# Copyright IBM Corporation. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Assisted by watsonx Code Assistant

FROM registry.access.redhat.com/ubi10/ubi:latest

RUN yum install -y jq && \
    yum clean all && \
    curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux-$(uname -m | sed 's/aarch64/arm64/g' | sed 's/x86_64/amd64/g')-rhel9.tar.gz && \
    tar -xvzf openshift-client-linux*.tar.gz -C /usr/local/bin oc && \
    rm -f openshift-client-linux*.tar.gz

# https://github.com/openshift/must-gather/tree/main/collection-scripts
COPY --from=quay.io/openshift/origin-must-gather:latest /usr/bin/gather* /usr/bin/

COPY collection-scripts/* /usr/bin/

CMD ["/usr/bin/gather"]
