# Management Blueprint

This directory contains the configuration needed to setup a management GKE cluster.

This management cluster must run [Cloud Config Connector](https://cloud.google.com/config-connector/docs/overview). The management cluster is configured in namespace mode.
Each namespace is associated with a Google Service Account which has owner permissions on 
one or more GCP projects. You can then create GCP resources by creating CNRM resources
in that namespace.

Optionally, the cluster can be configured with [Anthos Config Managmenet](https://cloud.google.com/anthos-config-management/docs) 
to manage GCP infrastructure using GitOps.

## Install the required tools

1. Install gcloud components

   ```
   gcloud components install kpt anthoscli beta
   gcloud components update
   ```

## Setting up the management cluster

TODO(jlewi): Instructions below need a bit of updating; the predate some of the move to kpt packages

1. Fetch the config files

   ```
   kpt pkg get https://github.com/jlewi/kf-templates-gcp.git/management@master ./
   ```

   * TODO(jlewi): Change to a Kubeflow repo once its in kubeflow.

1. Set the name for the management resources in the base kustomize package

   ```
   kpt cfg set ../manifests/gcp/v2/management/ cluster-name $(MGMT_NAME)   
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

### Create a KUBECONFIG CNRM context for your managed project

Follow these instructions to create a conveniently KUBECONFIG context in your CNRM host cluster
to manage a specific project. This will be used in subsequent steps when deploying Kubeflow.

1. Create a kubeconfig entry for your management cluster

   ```
   make create-cnrm-ctxt
   ```

## References

[CNRM Reference Documentation](https://cloud.google.com/config-connector/docs/reference/resources) 