# Copyright IBM Corporation. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# Assisted by watsonx Code Assistant
FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf install -y jq git rsync && \
    dnf clean all && \
    curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux-$(uname -m | sed 's/aarch64/arm64/g' | sed 's/x86_64/amd64/g')-rhel9.tar.gz && \
    tar -xvzf openshift-client-linux*.tar.gz -C /usr/local/bin oc && \
    rm -f openshift-client-linux*.tar.gz

RUN git clone https://github.com/openshift/must-gather && \
    rm -rf must-gather/.git && \
    cp must-gather/collection-scripts/* /usr/bin/

# Overwrite our customizations
COPY collection-scripts/. /usr/bin/

CMD ["/usr/bin/gather"]
