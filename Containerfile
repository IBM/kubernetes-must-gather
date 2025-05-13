# Copyright IBM Corporation. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Assisted by watsonx Code Assistant

FROM registry.access.redhat.com/ubi9/ubi:latest
RUN curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz && \
    tar -xvzf openshift-client-linux.tar.gz -C /usr/local/bin oc && \
    rm -f openshift-client-linux.tar.gz

COPY gather /usr/bin/
ENTRYPOINT ["/usr/bin/gather"]
