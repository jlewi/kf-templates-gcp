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

TODO:

 * Use kpt packages to pull in upstream packages rather than git submodules?
 * I think when we create the cluster we need to set the [ASM mesh labels](https://cloud.google.com/service-mesh/docs/gke-install-new-cluster)
 * I think we need our GKE clusters to be in a release channel rather than pinning to a specific GKE version.

## Install the required tools

```
gcloud components install kpt anthoscli beta
gcloud components update
```

## Clone the Blueprint

1. Clone the blueprint

   ```
   git clone https://github.com/jlewi/kf-templates-gcp.git ${REPO}
   ```

## Fetch packages using kpt

```

make pkg-get
```

  * This generates an error per [GoogleContainerTools/kpt#539](https://github.com/GoogleContainerTools/kpt/issues/539) but it looks like
    this can be ignored.


1. Initialize the submodules

   ```
   git submodule init
   git submodule update
   ```

## Setting up the management cluster

The management cluster is a GKE cluster running [Config Connector](https://cloud.google.com/config-connector/docs/how-to/getting-started).
The management cluster should be configured in namespace mode so there is a different namespace for each GCP project
under management. 

If you already have a management cluster you can skip this step. Otherwise follow these instructions to setup the management cluster.


1. Set the name for the management resources in the base kustomize package

   ```
   cd ${REPO}/manifests/gcp/v2/management/
   
   kpt cfg set . cluster-name $(MGMT_NAME)   
   ```

1. Set the same names in the kustomize package defining overlays

   ```
   cd ${REPO}/management
   
   kpt cfg set . cluster-name $(MGMT_NAME)   
   kpt cfg set . gcloud.compute.zone $(MGMT_ZONE)
   kpt cfg set . gcloud.core.project $(MGMT_PROJECT)   
   ```

   * This directory defines kustomize overlays applied to `manifests/gcp/v2/management`

   * The names of the CNRM resources need to be set in both the base 
     package and the overlays

1. Hydrate and apply the manifests to create the cluster

   ```
   make apply
   ```

1. Create a kubeconfig context for the cluster

   ```
   gcloud --project=${PROJECT} container clusters get-credentials --region=${REGION} ${MGMT_ZONE}
   ```

1. Get the current context

   ```
   kubectl config current-context
   ```

1. Set MGMTCTXT in the Makefiles

1. Install the CNRM system components

   ```
   make install-kcc
   ```

### Setup KCC Namespace For Each Project

You will configure Config Connector in [Namespaced Mode](https://cloud.google.com/config-connector/docs/concepts/installation-types#namespaced_mode). This means

* There will be a separate namespace for each GCP project under management
* CNRM resources will be created in the namespace matching the GCP project
  in which the resource lives.
* There will be multiple instances of the CNRM controller each managing
  resources in a different namespace
* Each CNRM controller can use a different K8s account which can be bound
  through workload identity to a different GCP Service Account with permissions to manage the project

For each project you want to setup follow the instructions below.

1. Create a copy of the per namespace/project resources

   ```
   cp -r ../manifests/gcp/v2/management/cnrm-install/install-per-namespace ./management/cnrm-install-${PROJECT}
   ```
1. Set the project to be mananged

   ```
   kpt cfg set cnrm-install-jlewi-dev managed_project ${MANAGED_PROJECT}
   ```

1. Set the host project where kcc is running

   ```
   kpt cfg set cnrm-install-jlewi-dev host_project ${HOST_PROJECT}
   kpt cfg set cnrm-install-jlewi-dev host_id_pool ${HOST_PROJECT}.svc.id.goog
   ```

   * host_id_pool should be the workload identity pool used for the host project

1. Apply this manifest to the mgmt cluster


   ```
   kubectl --context=$(MGMTCTXT) apply -f ./management/cnrm-install-${PROJECT}/per-namespace-components.yaml
   ```

1. Create the GSA and workload identity binding

   ```
   anthoscli apply --project=${MANAGED_PROJECt} -f service_account.yaml
   ```

1. anthoscli doesn't support IAMPolicyMember resources yet so we use this as a workaround
   to make the newly created GSA an owner of the hosted project

   ```
   gcloud projects add-iam-policy-binding ${MANAGED_PROJECT} \
    --member=serviceAccount:cnrm-system-${MANAGED_PROJECT}@${MANAGED_PROJECT}.iam.gserviceaccount.com  \
    --role roles/owner
   ```
## Create the Kubeflow GCP resources

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

1. Set the name of all CNRM resources in the base kustomize package

   ```      
   kpt cfg set manifests/gcp/v2/cnrm cluster-name ${KFNAME}
   ```

1. Configure CNRM patches
   
   ```
   kpt cfg set gcp_config gcloud.core.project ${MANAGED_PROJECT}
   kpt cfg set gcp_config name ${KFNAME}
   kpt cfg set gcp_config cluster-name ${KFNAME}
   kpt cfg set gcp_config location ${LOCATION}
   kpt cfg set gcp_config gcloud.compute.zone ${ZONE}
   ```

   * TODO(jlewi): Should we standardize on name rather than cluster-name?

1. Edit `Makefile` change the values of `MGMTCTXT` to the context for the managmenet cluster


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