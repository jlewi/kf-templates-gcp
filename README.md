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

1. TODO(jlewi): We need to annotate all the configmap patches with kpt setter commands

   ```
   kpt cfg set ./kustomize gcloud.core.project $(gcloud config get-value project)
   kpt cfg set ./kustomize name ${NAME}
   ```

   * Name should be the name for the kubeflow deployment; it should match the name given to all the KCC resources.

1. Set zone and name
   
   ```
   kpt cfg set v2 gcloud.core.project $(gcloud config get-value project)
   kpt cfg set v2 cluster-name $(CLUSTER_NAME)
   kpt cfg set v2 gcloud.compute.zone $(gcloud config get-value compute/zone)
   ```

   * TODO(jlewi): This won't work. kfctl isn't compatible with kpt setters because comments get stripped out when kfctl overwrites the files. 


1. Hydrate the manifests

   ```
   make hydrate
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


* Install the ISTIO operator by following the [istioctl instructions](https://github.com/kubeflow/manifests/tree/master/gcp/v2#step-2-install-asm)

  
  * TODO(jlewi): Using anthoscli isn't working yet. Looks like export subcommand isn't available yet.

    ```
    anthoscli apply -f v2/asm/istio-operator.yaml
    ```

  * TODO(jlewi): It looks like the operator might be a little behind the latest ASM configs
    https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages/blob/master/asm/cluster/istio-operator.yaml

    * TODO(jlewi): Right now asm is a submodule but we are still using the ISTIO operator in the KF manifests repository.
    * We use asm submodule to enable the services

## Install Kubeflow

TODO(jlewi): Need to change this to use v3 style manifests

1. Configure kfdef

   ```
   kpt cfg set kfctl_gcp_asm_exp.yaml name ${CLUSTER_NAME}
   kpt cfg set kfctl_gcp_asm_exp.yaml gcloud.core.project ${PROJECT}
   kpt cfg set kfctl_gcp_asm_exp.yaml zone ${ZONE}
   kpt cfg set kfctl_gcp_asm_exp.yaml email ${EMAIL}
   ```

   * Name must be the same value as the name you gave the cluster in the previous step

1. Delete the existing directories to force a regeneration of the config

   ```
   ```

   * TODO(jlewi): This is hacky; need to clean this up.


1. Set environmetn variables with OAuth Client ID and Secret for IAP

   ```
   export CLIENT_ID=
   export CLIENT_SECRET=
   ```

1. Build the manifests

   ```
   kfctl build -V -f kfctl_gcp_asm_exp.yaml
   ```