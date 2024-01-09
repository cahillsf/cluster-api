## Testing ProwJobs Locally
- [test-infra](https://github.com/kubernetes/test-infra) provides tools that can be used to generate ProwJob specs and run them locally: 
  - [mkpj](https://docs.prow.k8s.io/docs/components/cli-tools/mkpj/) to generate the `ProwJob` yaml manifest
  - [Phaino](https://docs.prow.k8s.io/docs/components/cli-tools/phaino/) to read in the yaml manifest, convert it to a `docker run` command and run the job locally

## Example using `post-cluster-api-push-images`
- to run this example you will need:
  - Docker installed locally: https://docs.docker.com/get-docker/
  - a local clone of [test-infra](https://github.com/kubernetes/test-infra) 
  - a GCP project with the following services:
    - an [object storage](https://cloud.google.com/storage?hl=en) bucket to upload the source tarball for the cloudbuild job
    - an [artifact registry](https://cloud.google.com/artifact-registry) as the destination for the built images and manifests
    - [Cloudbuild](https://cloud.google.com/build?hl=en) enabled to run the build
    - the [Gcloud CLI](https://cloud.google.com/sdk/gcloud) installed locally and authorized to perform the actions above
- in the Makefile, we will make the following modifications:
  - update the `STAGING_REGISTRY` var to your artifact registry
  - 3 lines exporting the required envvars for customizing the job: 
    ```
    export TEST_TAG = <DESIRED_IMAGE_TAG>
    export GCP_PROJECT = <SANDBOX_GCP_PROJECT>
    export SCRATCH_BUCKET = <SANDBOX_OBJECT_STORAGE_BUCKET_NAME>
    ```
- run the Make target `test-post-cluster-api-push-images` to generate the required ProwJob yaml and Cloudbuild yaml
  - this will substitute your exported variables in the template files and write them to the root of `cluster-api` project and 
  - the ProwJob yaml template originated from the following command in the `test-infra` repo:
    ```
    go run ./prow/cmd/mkpj \
      --config-path=./config/prow/config.yaml \
      --job-config-path=./config/jobs/image-pushing/k8s-staging-cluster-api.yaml \
      --job=post-cluster-api-push-images \
      --base-ref=main \
      > test.yaml
    ```
  - I've added the placeholder for the variable substitutions as well as a `--allow-dirty=true` option to the container args for faster testing/iteration (without this option the job will fail with a dirty git state)
- to kick off the job run the following command from the `test-infra` repo:
  ```
  go run ./prow/cmd/phaino \
    --use-local-gcloud-credentials=true \
    <CLUSTER_API_REPO>/local-prow.yaml
  ```
  - the container will use your local gcloud credentials by mounting your local gcloud config directory into the container
  - `phaino` will try to find the `cluster-api` repo locally using this logic: https://github.com/kubernetes/test-infra/blob/7c313e4089802b5849ff973e6137efb9b86d0261/prow/cmd/phaino/local.go#L121-L124
    - you will see the location it finds in the `docker run` output on the command line (e.g. ` "-v" \ "/Users/stephen.cahill/cluster-api:/home/prow/go/src/github.com/kubernetes-sigs/cluster-api"`)

## Proving out https://github.com/kubernetes-sigs/cluster-api/issues/9752#issuecomment-1873048812
- run `touch` on the Dockerfiles to line up their timestamps (in our CD the repo is being cloned directly into the container so we need to mimic this)
  ```
  touch <RELEVANT_LOCAL_PATH>/cluster-api/test/infrastructure/docker/Dockerfile & touch <RELEVANT_LOCAL_PATH>/cluster-api/test/extension/Dockerfile
  ```
- in this branch I've updated the Makefile's `ALL_DOCKER_BUILD` parameter so that only the two components we saw exhibit this behavior are built, which exposes the underlying bug without adding the `-j` option
- after the job completes, verify the images using the following command: `  ./verify.sh "<TEST_TAG>" "<STAGING_REGISTRY>"`
  - example output:
    ```
    ➜ ./verify.sh "dev4" "us-central1-docker.pkg.dev/datadog-sandbox/cahillsf"
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:dev4 ARCH=amd64
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:dev4 ARCH=arm
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:dev4 ARCH=arm64
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:dev4 ARCH=ppc64le
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:dev4 ARCH=s390x
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=amd64
    FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=amd64, expected value for path: "sigs.k8s.io/cluster-api/test/extension$"
            path    command-line-arguments
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=arm
    FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=arm, expected value for path: "sigs.k8s.io/cluster-api/test/extension$"
            path    command-line-arguments
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=arm64
    FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=arm64, expected value for path: "sigs.k8s.io/cluster-api/test/extension$"
            path    command-line-arguments
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=ppc64le
    FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=ppc64le, expected value for path: "sigs.k8s.io/cluster-api/test/extension$"
            path    command-line-arguments
    > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=s390x
    FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/test-extension:dev4 ARCH=s390x, expected value for path: "sigs.k8s.io/cluster-api/test/extension$"
            path    command-line-arguments
    ```
- if you switch the order of the `ALL_DOCKER_BUILD` option with `test-extenstion` first and run the build, you will see the failures flip to the CAPD image in the verify output:
  ```
  > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=amd64
  FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=amd64, expected value for path: "command-line-arguments$"
        path    sigs.k8s.io/cluster-api/test/extension
  > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=arm
  FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=arm, expected value for path: "command-line-arguments$"
          path    sigs.k8s.io/cluster-api/test/extension
  > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=arm64
  FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=arm64, expected value for path: "command-line-arguments$"
          path    sigs.k8s.io/cluster-api/test/extension
  > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=ppc64le
  FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=ppc64le, expected value for path: "command-line-arguments$"
          path    sigs.k8s.io/cluster-api/test/extension
  > Testing us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=s390x
  FAILED us-central1-docker.pkg.dev/datadog-sandbox/cahillsf/capd-manager:test5 ARCH=s390x, expected value for path: "command-line-arguments$"
          path    sigs.k8s.io/cluster-api/test/extension
  ```
- by parallelizing the build job with `-j 8`, the order in the Makefile was no longer respected as Make can run 8 jobs at once, thereby opening up the possibility for the CAPD manager and test-extension to be built in sequence by one of the jobs and exposing the behavior of the bug in the `BuildKit` version packaged with the Docker server version in use with CloudBuild