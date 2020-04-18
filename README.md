# Kubeflow Blueprint

Blueprints for Kubeflow.

Kubeflow is deployed as follows

* A mangement cluster is setup using the manifests in **bootstrap**
  * The management cluster runs KCC and optionally ConfigSync
  * The management cluster is used to create all GCP resources for Kubeflow (e.g. the GKE cluster)
  * A single management cluster could be used for multiple projects or multiple KF deployments

* Once the Kubeflow cluster is created we use kustomize to deploy the KF applications on it.

* **manifests** Uses Git submodules to reference the Kubeflow manifests

  * This makes it easy to pull in upgrades just by updating the submodule to point to
    an updated link.

  * **caveat** For kustomize to work with KCC the names of the resources must be the same.
    So we need to use kpt to modify the names of the resources in **manifests**

## Install the required tools

```
gcloud components install kpt anthoscli beta
gcloud components update
```

## Setting up the management cluster

TODO(jlewi): Add instructions

## Create the Kubeflow GCP resources

1. Configure the KCC manifests for Kubeflow
 
   ```
   cd manifests gcp/v2
   ```

1. Set zone and name
   
   ```
   kpt cfg set v2 gcloud.core.project $(gcloud config get-value project)
   kpt cfg set v2 cluster-name $(CLUSTER_NAME)
   kpt cfg set v2 gcloud.compute.zone $(gcloud config get-value compute/zone)
   ```

1. Connect kubectl to the management cluster

 
   ```
   gcloud container clusters get-credentials <cluster-name> --zone <> --project <kcc-host-project-id>
   ```

1. Create the resources.

   ```
   kustomize build v2/cnrm | kubectl apply -n <kubeflow-project-id> -f -
   ```

   * TODO(jlewi): Add instructions for deploying using ConfigSync and the management cluster

##  Install Anthos Service Mesh(ASM) on the Kubeflow Cluster 

Install ASM on the newly created kubeflow cluster `CLUSTER_NAME`

* Connect kubectl to the new kubeflow cluster `CLUSTER_NAME`

  `gcloud container clusters get-credentials $(CLUSTER_NAME) --zone <> --project <kubeflow-project-id>`

* [Set credentials and permissions](https://cloud.google.com/service-mesh/docs/gke-install-existing-cluster#set_credentials_and_permissions)

* [Download istioctl released by GCP](https://cloud.google.com/service-mesh/docs/gke-install-existing-cluster#download_the_installation_file)


* Enable ASM services

  ```
  cd ${REPO}/asm/asm
  kpt cfg set . gcloud.core.project jlewi-dev 
  anthoscli apply -f ./project
  ```

  * **Note** If you get errors about services not found; wait an then retry.
    * It looks like some of the services require sequential activation and they aren't
      available immediately after enabling the previous service.


* Install the ISTIO operator

  ```
  anthoscli apply -f v2/asm/istio-operator.yaml
  ```

  * TODO(jlewi): It looks like the operator might be a little behind the latest ASM configs
    https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages/blob/master/asm/cluster/istio-operator.yaml

    * TODO(jlewi): Right now asm is a submodule but we are still using the ISTIO operator in the KF manifests repository.
    * We use asm submodule to enable the services