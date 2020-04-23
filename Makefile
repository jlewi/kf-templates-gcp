# The kname of the context for the management cluster
# These can be read using yq from the settings file.
#
# If you don't have yq 
MGMTCTXT=$(shell yq r ./kubeflow/settings.yaml mgmt-ctxt)
# The name of the context for your Kubeflow cluster
KFCTXT=$(shell yq r ./kubeflow/settings.yaml kf-ctxt)

# Path to kustomize directories
GCP_CONFIG=kubeflow/gcp_config
KF_DIR=kubeflow/kustomize

APP_DIR=kubeflow

# Print out the context
.PHONY: echo
echo-ctxt:
	@echo MGMTCTXT=$(MGMTCTXT)
	@echo KFCTXT=$(KFCTXT)

# Get packages
.PHONY: hydrate
get-pkg:
	# TODO(jlewi): We should switch to using upstream kubeflow/manifests and pin
	# to a specific version
	# TODO(jlewi): We should think about how we layout packages in kubeflow/manifests so
	# users don't end up pulling tests or other things they don't need.
	kpt pkg get https://github.com/jlewi/manifests.git@blueprints ./kubeflow
	rm -rf ./manifests/tests
	# TODO(jlewi): Package appears to cause problems for kpt. We should delete in the upstream
	# since its not needed anymore.
	# https://github.com/GoogleContainerTools/kpt/issues/539
	rm -rf ./manifests/common/ambassador
	
.PHONY: hydrate
apply-gcp: hydrate-gcp
	# Apply management resources
	kubectl --context=$(MGMTCTXT) apply -f ./.build/gcp_config

.PHONY: apply-asm
apply-asm: hydrate-asm
	kubectl --context=${KFCTXT} apply -f ./.build/istio/Base
	# TODO(jlewi): Should we use the newer version in asm/asm
	# istioctl manifest --context=${KFCTXT} apply -f ./manifests/gcp/v2/asm/istio-operator.yaml 
	# TODO(jlewi): Switch to anthoscli once it supports generating manifests 
	# anthoscli apply -f ./manifests/gcp/v2/asm/istio-operator.yaml 

.PHONY: apply-kubeflow
apply-kubeflow: hydrate-kubeflow
	# Apply kubeflow apps
	kubectl --context=$(KFCTXT) apply -f ./.build/namespaces
	kubectl --context=$(KFCTXT) apply -f ./.build/kubeflow-istio
	kubectl --context=$(KFCTXT) apply -f ./.build/metacontroller
	kubectl --context=$(KFCTXT) apply -f ./.build/application
	kubectl --context=$(KFCTXT) apply -f ./.build/cloud-endpoints
	kubectl --context=$(KFCTXT) apply -f ./.build/iap-ingress
	# Due to https://github.com/jetstack/cert-manager/issues/2208
	# We need to skip validation on Kubernetes 1.14
	kubectl --context=$(KFCTXT) apply --validate=false -f ./.build/cert-manager-crds
	kubectl --context=$(KFCTXT) apply -f ./.build/cert-manager-kube-system-resources	
	kubectl --context=$(KFCTXT) apply -f ./.build/cert-manager
	kubectl --context=$(KFCTXT) apply -f ./.build/kubeflow-apps

# TODO(jlewi): If we use prune does that give us a complete upgrade solution?
# TODO(jlewi): Should we insert appropriate wait statements to wait for various services to
# be available before continuing?
.PHONY: apply
apply: clean-build apply-gcp apply-asm apply-kubeflow iap-secret

.PHONY: hydrate-gcp
hydrate-gcp:
	# ***********************************************************************************
	# Hydrate cnrm
	mkdir -p .build/gcp_config 
	kustomize build -o .build/gcp_config $(GCP_CONFIG)

.PHONY: hydrate-asm
hydrate-asm:	
	#************************************************************************************
	# hydrate asm
	istioctl manifest generate -f ./manifests/gcp/v2/asm/istio-operator.yaml -o .build/istio

.PHONY: hydrate-kubeflow
hydrate-kubeflow:	
	#************************************************************************************
	# Hydrate kubeflow applications
	mkdir -p .build/namespaces
	kustomize build --load_restrictor none -o .build/namespaces  ${KF_DIR}/namespaces

	mkdir -p .build/application
	kustomize build --load_restrictor none -o .build/application $(KF_DIR)/application
	mkdir -p .build/cert-manager
	kustomize build --load_restrictor none -o .build/cert-manager $(KF_DIR)/cert-manager
	mkdir -p .build/cert-manager-crds
	kustomize build --load_restrictor none -o .build/cert-manager-crds $(KF_DIR)/cert-manager-crds
	mkdir -p .build/cert-manager-kube-system-resources
	kustomize build --load_restrictor none -o .build/cert-manager-kube-system-resources $(KF_DIR)/cert-manager-kube-system-resources
	mkdir -p .build/cloud-endpoints
	kustomize build --load_restrictor none -o .build/cloud-endpoints $(KF_DIR)/cloud-endpoints
	mkdir -p .build/iap-ingress
	kustomize build --load_restrictor none -o .build/iap-ingress $(KF_DIR)/iap-ingress
	mkdir -p .build/kubeflow-apps
	kustomize build --load_restrictor none -o .build/kubeflow-apps $(KF_DIR)/kubeflow-apps
	mkdir -p .build/kubeflow-apps
	kustomize build --load_restrictor none -o .build/kubeflow-istio $(KF_DIR)/kubeflow-istio
	mkdir -p .build/metacontroller
	kustomize build --load_restrictor none -o .build/metacontroller $(KF_DIR)/metacontroller

.PHONEY: clean-build
clean-build:
	# Delete build because we want to prune any resources which are no longer defined in the manifests
	rm -rf .build
	mkdir -p .build/

# Hydrate all the application directories directories
# TODO(jlewi): We can't use a kustomization file to combine the top level packages
# because they might get vars conflicts. Also order is important when applying them.
.PHONY: hydrate
hydrate: clean-build hydrate-gcp hydrate-asm hydrate-kubeflow
			
# Create the iap secret from environment variables
.PHONY: iap-secret
iap-secret:
	kubectl --context=$(KFCTXT) -n istio-system create secret generic kubeflow-oauth --from-literal=client_id=${CLIENT_ID} --from-literal=client_secret=${CLIENT_SECRET}

# Create a kubeconfig context for your managed project
.PHONE: create-cnrm-ctxt
create-cnrm-ctxt:	
	# TODO(jlewi): How to use variables to store values from settings.yaml to make it cleaner?
	# Create a kubeconfig context;
	# TODO(jlewi): Make this a script to make it a bit cleaner; this will create an error if the context already exists
	gcloud --project=$(shell yq r ./management/settings.yaml project) container clusters get-credentials \
		--region=$(shell yq r ./management/settings.yaml location) $(shell yq r ./management/settings.yaml name)
	# Rename the context
	kubectl config rename-context $(shell kubectl config current-context) $(shell yq r ./management/settings.yaml name)-$(shell yq r $(APP_DIR)/settings.yaml project)
	# Set the name of the context
	kpt cfg set ./kubeflow mgmt-ctxt $(shell yq r management/settings.yaml name)-$(shell yq r $(APP_DIR)/settings.yaml project)
	# Set the namespace to the host project
	kubectl config set-context --current --namespace=$(shell yq r $(APP_DIR)/settings.yaml project)
