# kubernetes-must-gather

Custom must-gather image and collection script for Kubernetes and OpenShift.

## Development

1. Build the image. For example:  
   ```
   podman build -t must-gather-custom-image -f Containerfile .
   ```
1. Push the image to some registry.
1. Use the image. For example:
   ```
   oc adm must-gather --image=image-registry.openshift-image-registry.svc:5000/testNamespace/testImage:20250513
   ```

## Files

* [LICENSE](LICENSE)
* [CONTRIBUTING.md](CONTRIBUTING.md)
* [MAINTAINERS.md](MAINTAINERS.md)
* [CHANGELOG.md](CHANGELOG.md)

## Notes

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
