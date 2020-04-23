# Kubeflow Blueprint

This directory contains a blueprint for creating a Kubeflow deployment.

## Prerequisites

You must have created a management cluster and installed Config Connector. 
If you don't have a management cluster follow the [instructions](../management/README.md)
for setting one up. 

Your management cluster must have a namespace setup to administer the GCP project where
Kubeflow will be deployped. Follow the [instructions](../management/README.md) to create
one if you haven't already.


## Install the required tools

1. Install gcloud components

   ```
   gcloud components install kpt anthoscli beta
   gcloud components update
   ```

1. Follow these [instructions](https://cloud.google.com/service-mesh/docs/gke-install-new-cluster#download_the_installation_file) to
   install istioctl

## Fetch packages using kpt

1. Fetch the blueprint

   ```
   kpt pkg get https://github.com/jlewi/kf-templates-gcp.git/kubeflow@master ./
   ```

   * TODO(jlewi): Change to a Kubeflow repo


1. Change to the kubeflow directory

   ```
   cd kubeflow
   ```

1. Fetch Kubeflow manifests

   ```
   make pkg-get
   ```

  * This generates an error per [GoogleContainerTools/kpt#539](https://github.com/GoogleContainerTools/kpt/issues/539) but it looks like
    this can be ignored.

## Configure Kubeflow

1. Set the name of the KUBECONFIG context for the management cluster; this kubecontext will
   be used to create CNRM resources for your Kubeflow deployment.

   ```
   kpt cfg set mgmt-ctxt
   ```

   * Follow the [instructions](../README.md) to create a kubecontext for your managment context

1. Pick a name for the Kubeflow deployment

   ```
   export KFNAME=<some name>
   ```

1. Pick a location for the Kubeflow deployment

   ```
   export LOCATION=<zone or region>
   export ZONE=<zone for disks>
   ```

   * Location can be a zone or a region depending on whether you want a regional cluster
   * We recommend creating regional clusters for higher availability
   * The [cluster management fee](https://cloud.google.com/kubernetes-engine/pricing) is the same for regional
     and zonal clusters

   * TODO(jlewi): Metadata and Pipelines are still using zonal disks what do we have to do make that work with regional clusters? For metadata
     we could use CloudSQL.

1. Set the values for the kubeflow deployment.

   ```
   kpt cfg set ../manifests/gcp  cluster-name ${KFNAME}
   kpt cfg set ../manifests/gcp  gcloud.compute.zone ${ZONE}

   kpt cfg set . name ${KFNAME}
   kpt cfg set . cluster-name  ${KFNAME}
   kpt cfg set . location ${LOCATION}
   kpt cfg set . gcloud.core.project ${MANAGED_PROJECT}   
   ```

   * TODO(https://github.com/GoogleContainerTools/kpt/issues/541): If annotations are null kpt chokes. We have such files in manifests which is
     why we have a separate set statement for manifests once we fix that we should be able to just call it once on root

   * TODO(jlewi): Should we standardize on name rather than cluster-name?
   * TODO(jlewi): Need to figure out what to do about disk for metadata and pipelines when using regional clusters?. Maybe just 
     use Cloud SQL?

## Create the Kubeflow GCP resources

1. Set the name of all CNRM resources in the base kustomize package

   ```      
   kpt cfg set ../manifests/gcp/v2/cnrm cluster-name ${KFNAME}
   ```

1. Deploy the GCP resources

   ```
   make apply-gcp
   ```

1. Wait for the GKE cluster to be available

1. Create a kubectl config context for the cluster

   ```
   gcloud --project=${MANAGED_PROJECT} container clusters get-credentials --zone=${ZONE} ${KFNAME}
   ```

1. Edit the Makefile set `KFCTXT` to the context for the KF cluster. You can get the context by running

   ```
   kubectl config current-context
   ```
TODO(jlewi): Add instructions for deploying using ConfigSync and the management cluster

##  Install Anthos Service Mesh(ASM) on the Kubeflow Cluster 

Install ASM on the newly created kubeflow cluster `KFNAME`

* Connect kubectl to the new kubeflow cluster `KFNAME`
  
* [Set credentials and permissions](https://cloud.google.com/service-mesh/docs/gke-install-existing-cluster#set_credentials_and_permissions)

* [Download istioctl released by GCP](https://cloud.google.com/service-mesh/docs/gke-install-existing-cluster#download_the_installation_file)


* Enable ASM services

  ```  
  kpt cfg set asm/asm gcloud.core.project ${MANAGED_PROJECT}
  anthoscli apply --project=${MANAGED_PROJECT} -f ./asm/asm/project
  ```

  * **Note** If you get errors about services not found; wait an then retry.
    * It looks like some of the services require sequential activation and they aren't
      available immediately after enabling the previous service.

* Configure ASM

  ```
  kpt cfg set manifests/gcp/v2/asm gcloud.core.project ${MANAGED_PROJECT}
  kpt cfg set manifests/gcp/v2/asm cluster-name ${KFNAME}
  kpt cfg set manifests/gcp/v2/asm location ${LOCATION}
  ```

* Install the ISTIO operator

  ```
  make apply-asm
  ```

  * TODO(jlewi): Using anthoscli isn't working yet so we are using istioctl

  * TODO(jlewi): It looks like the operator config in manifests might be a little behind the latest ASM configs
    https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages/blob/master/asm/cluster/istio-operator.yaml

    * TODO(jlewi): Right now asm is a submodule but we are still using the ISTIO operator in the KF manifests repository.
    * We use asm submodule to enable the services

## Install Kubeflow Applications

1. Configure the Kubeflow applications

   ```
   kpt cfg set kustomize gcloud.core.project ${MANAGED_PROJECT}
   kpt cfg set kustomize name ${KFNAME}
   ```
1. Build the manifests

   ```
   make hydrate
   ```

1. Apply the manifests

   ```
   make apply
   ```

1. Set environment variables with OAuth Client ID and Secret for IAP

   ```
   export CLIENT_ID=
   export CLIENT_SECRET=
   ```

   * TODO(jlewi): Add link for instructions on creating an OAuth client id

1. Create the IAP secret

   ```
   make iap-secret
   ```