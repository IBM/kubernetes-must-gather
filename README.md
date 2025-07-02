# kubernetes-must-gather

`kubernetes-must-gather` is a custom must-gather image and collection script for Kubernetes and OpenShift. It should work on AMD/x64, ARM/AARCH, PPC64, and z/Linux. The image is published to Red Hat's Quay.io at [quay.io/ibm/kubernetes-must-gather](https://quay.io/repository/ibm/kubernetes-must-gather). The image is based on the [`oc adm must-gather` image](https://github.com/openshift/must-gather).

## Usage

### Basic usage

```
oc adm must-gather --image=quay.io/ibm/kubernetes-must-gather:0.1.20250702006
```

### Customized usage

#### Default Behavior

`kubernetes-must-gather` gathers significantly less than the `oc adm must-gather` image because `kubernetes-must-gather` is designed for a more lightweight and iterative workflow using command line flags. By default, `kubernetes-must-gather` gathers:

1. `oc describe` YAMLs for all namespaces for the following resources: `nodes pods events securitycontextconstraints`
1. Pod logs of pods in CrashLoopBackOff state for all namespaces. Disable with `--no-logs-crashloopbackoff`

#### Usage help

```
oc adm must-gather --image=quay.io/ibm/kubernetes-must-gather:0.1.20250702006 -- gather -h
```

#### oc adm must-gather collection-scripts

`kubernetes-must-gather` can run any of the other collection scripts available in the upstream `oc adm must-gather` [collection-scripts](https://github.com/openshift/must-gather/tree/main/collection-scripts). Just pass `--` and the name of the script (multiple allowed and they're executed in sequence). For example, to run `gather_apirequestcounts`:

```
oc adm must-gather --image=quay.io/ibm/kubernetes-must-gather:latest -- gather --gather_apirequestcounts
```

This calls <https://github.com/openshift/must-gather/blob/main/collection-scripts/gather_apirequestcounts> and extra output is in the download at `must-gather.local.*/quay-io-ibm-kubernetes-must-gather*/requests/`

---

## Development

### Steps to build locally and publish to an OpenShift registry

1. Build the image for your cluster platform; for example:
   ```
   podman build --platform linux/amd64 -t kubernetes-must-gather .
   ```
1. Get your cluster registry URL:
   ```
   REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
   ```
1. Find the local image ID:
   ```
   IMAGE_ID=$(podman images | grep "localhost/kubernetes-must-gather" | awk '{print $3}')
   ```
1. Set a unique version of the image:
   ```
   VERSION="..."
   ```
1. Set the namespace/project to push the image to (make sure this namespace exists):
   ```
   NAMESPACE="customimages"
   ```
1. Login to your remote image registry with podman:
   ```
   podman login ${REGISTRY}
   ```
1. Tag the local image for the remote image registry:
   ```
   podman tag ${IMAGE_ID} ${REGISTRY}/${NAMESPACE}/kubernetes-must-gather:${VERSION}
   ```
1. Push the image to the remote image registry (may require [exposing the registry](https://docs.openshift.com/container-platform/latest/registry/securing-exposing-registry.html)):
   ```
   podman push ${IMAGE_ID} ${REGISTRY}/${NAMESPACE}/kubernetes-must-gather:${VERSION}
   ```
1. Use the image. For example:
   ```
   oc adm must-gather --image=image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/kubernetes-must-gather:${VERSION}
   ```

### Steps to publish a new image to Quay

1. Update the `VERSION=` line in `gather`
1. Set a variable to this version in your shell:
   ```
   VERSION="..."
   ```
1. Create the manifest (error if it exists is okay):
   ```
   podman manifest create quay.io/ibm/kubernetes-must-gather:latest
   ```
1. Remove any existing manifest images:
   ```
   for i in $(podman manifest inspect quay.io/ibm/kubernetes-must-gather:latest | jq '.manifests[].digest' | tr '\n' ' ' | sed 's/"//g'); do podman manifest remove quay.io/ibm/kubernetes-must-gather:latest $i; done
   ```
1. Build the images:
   ```
   podman build --platform linux/amd64,linux/ppc64le,linux/s390x,linux/arm64 --jobs=1 --manifest quay.io/ibm/kubernetes-must-gather:latest .
   ```
1. Log into Quay:
   ```
   podman login quay.io
   ```
1. Push with the version in step 1:
   ```
   podman manifest push --all quay.io/ibm/kubernetes-must-gather:latest docker://quay.io/ibm/kubernetes-must-gather:$VERSION
   ```
1. Test the tag:
    1. Make sure it basically works with usage:
       ```
       oc adm must-gather --image=quay.io/ibm/kubernetes-must-gather:$VERSION -- gather -h
       ```
    1. Run the default must gather:
       ```
       oc adm must-gather --image=quay.io/ibm/kubernetes-must-gather:$VERSION
       ```
1. If testing looks good, push to the `latest` tag:
   ```
   podman manifest push --all quay.io/ibm/kubernetes-must-gather:latest docker://quay.io/ibm/kubernetes-must-gather:latest
   ```
1. Test the `latest` tag:
   ```
   oc adm must-gather --image=quay.io/ibm/kubernetes-must-gather:latest
   ```
1. If all looks good, update the version above in the README.

## Notes

We generally recommend using a specific tag rather than `latest` because `oc adm must-gather` [uses an `ImagePullPolicy` of `PullIfNotPresent`](https://github.com/openshift/oc/issues/2029) so if you were to use `--image=quay.io/ibm/kubernetes-must-gather:latest` once, then you could not get a newer version of the `latest` image in the same cluster unless you manually deleted that image from the internal image registry.

## Files

* [LICENSE](LICENSE)
* [CONTRIBUTING.md](CONTRIBUTING.md)
* [MAINTAINERS.md](MAINTAINERS.md)
* [CHANGELOG.md](CHANGELOG.md)

## Issues and Pull Requests

If you have any questions or issues you can create a new [issue here][issues].

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

All source files must include a Copyright and License header. The SPDX license header is 
preferred because it can be easily scanned.

If you would like to see the detailed LICENSE click [here](LICENSE).

```text
#
# Copyright IBM Corporation. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
```
## Authors

- Author: Kevin Grigorenko - <mailto:kevin.grigorenko@us.ibm.com>
- Author: Leon Foret - <mailto:ljforet@us.ibm.com>
- Author: Amar Kalsi - <mailto:amarkalsi@uk.ibm.com>
- Author: Kaifu Wu - <mailto:kfwu@tw.ibm.com>

[issues]: https://github.com/IBM/kubernetes-must-gather/issues/new
