# The kname of the context for the management cluster
# These can be read using yq from the settings file.
#
# If you don't have yq 
MGMTCTXT=$(shell yq r ./settings.yaml mgmt-ctxt)
# The name of the context for your Kubeflow cluster
NAME=$(shell yq r ./settings.yaml name)
KFCTXT=$(NAME)

# Path to kustomize directories
GCP_CONFIG=gcp_config
KF_DIR=kustomize

APP_DIR=.
MANIFESTS_DIR=../manifests

# TODO(https://github.com/GoogleContainerTools/kpt/issues/539): 
# Using a subdirectory fo the current directory breaks our ability to run kpt set .
# So as a hack we use a $(BUILD_DIR)/ directory in the parent directory.
BUILD_DIR=../.build-kubeflow

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
	# The reason we  put this in a parent directory is as a workaround for https://github.com/GoogleContainerTools/kpt/issues/539
	# kpt will choke on some of our manifests because annotations is null. 
	# So if we check it out as a subdirectory of ${CWD} then 
	# ktp cfg {CWD} set ....
	# won't work. Hopefully this can be fixed in the future.
	kpt pkg get https://github.com/jlewi/manifests.git@blueprints ../
	rm -rf $(MANIFESTS_DIR)/tests
	# TODO(jlewi): Package appears to cause problems for kpt. We should delete in the upstream
	# since its not needed anymore.
	# https://github.com/GoogleContainerTools/kpt/issues/539
	rm -rf $(MANIFESTS_DIR)/common/ambassador
		
.PHONY: hydrate
apply-gcp: hydrate-gcp
	# Apply management resources
	kubectl --context=$(MGMTCTXT) apply -f ./$(BUILD_DIR)/gcp_config

.PHONY: apply-asm
apply-asm: hydrate-asm
	kubectl --context=${KFCTXT} apply --recursive=true -f ./$(BUILD_DIR)/istio/Base
	# TODO(jlewi): Should we use the newer version in asm/asm
	# istioctl manifest --context=${KFCTXT} apply -f ./manifests/gcp/v2/asm/istio-operator.yaml 
	# TODO(jlewi): Switch to anthoscli once it supports generating manifests 
	# anthoscli apply -f ./manifests/gcp/v2/asm/istio-operator.yaml 

.PHONY: apply-kubeflow
apply-kubeflow: hydrate-kubeflow
	# Apply kubeflow apps
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/namespaces
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/kubeflow-istio
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/metacontroller
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/application
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/cloud-endpoints
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/iap-ingress
	# Due to https://github.com/jetstack/cert-manager/issues/2208
	# We need to skip validation on Kubernetes 1.14
	kubectl --context=$(KFCTXT) apply --validate=false -f ./$(BUILD_DIR)/cert-manager-crds
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/cert-manager-kube-system-resources	
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/cert-manager
	kubectl --context=$(KFCTXT) apply -f ./$(BUILD_DIR)/kubeflow-apps

# TODO(jlewi): If we use prune does that give us a complete upgrade solution?
# TODO(jlewi): Should we insert appropriate wait statements to wait for various services to
# be available before continuing?
.PHONY: apply
apply: clean-build apply-gcp create-ctxt apply-asm apply-kubeflow iap-secret

.PHONY: hydrate-gcp
hydrate-gcp:
	# ***********************************************************************************
	# Hydrate cnrm
	mkdir -p $(BUILD_DIR)/gcp_config 
	kustomize build -o $(BUILD_DIR)/gcp_config $(GCP_CONFIG)

.PHONY: hydrate-asm
hydrate-asm:	
	#************************************************************************************
	# hydrate asm
	istioctl manifest generate -f $(MANIFESTS_DIR)/gcp/v2/asm/istio-operator.yaml -o $(BUILD_DIR)/istio

.PHONY: hydrate-kubeflow
hydrate-kubeflow:	
	#************************************************************************************
	# Hydrate kubeflow applications
	mkdir -p $(BUILD_DIR)/namespaces
	kustomize build --load_restrictor none -o $(BUILD_DIR)/namespaces  ${KF_DIR}/namespaces

	mkdir -p $(BUILD_DIR)/application
	kustomize build --load_restrictor none -o $(BUILD_DIR)/application $(KF_DIR)/application
	mkdir -p $(BUILD_DIR)/cert-manager
	kustomize build --load_restrictor none -o $(BUILD_DIR)/cert-manager $(KF_DIR)/cert-manager
	mkdir -p $(BUILD_DIR)/cert-manager-crds
	kustomize build --load_restrictor none -o $(BUILD_DIR)/cert-manager-crds $(KF_DIR)/cert-manager-crds
	mkdir -p $(BUILD_DIR)/cert-manager-kube-system-resources
	kustomize build --load_restrictor none -o $(BUILD_DIR)/cert-manager-kube-system-resources $(KF_DIR)/cert-manager-kube-system-resources
	mkdir -p $(BUILD_DIR)/cloud-endpoints
	kustomize build --load_restrictor none -o $(BUILD_DIR)/cloud-endpoints $(KF_DIR)/cloud-endpoints
	mkdir -p $(BUILD_DIR)/iap-ingress
	kustomize build --load_restrictor none -o $(BUILD_DIR)/iap-ingress $(KF_DIR)/iap-ingress
	mkdir -p $(BUILD_DIR)/kubeflow-apps
	kustomize build --load_restrictor none -o $(BUILD_DIR)/kubeflow-apps $(KF_DIR)/kubeflow-apps
	mkdir -p $(BUILD_DIR)/kubeflow-apps
	kustomize build --load_restrictor none -o $(BUILD_DIR)/kubeflow-istio $(KF_DIR)/kubeflow-istio
	mkdir -p $(BUILD_DIR)/metacontroller
	kustomize build --load_restrictor none -o $(BUILD_DIR)/metacontroller $(KF_DIR)/metacontroller

.PHONY: clean-build
clean-build:
	# Delete build because we want to prune any resources which are no longer defined in the manifests
	rm -rf $(BUILD_DIR)/
	mkdir -p $(BUILD_DIR)/

# Hydrate all the application directories directories
# TODO(jlewi): We can't use a kustomization file to combine the top level packages
# because they might get vars conflicts. Also order is important when applying them.
.PHONY: hydrate
hydrate: clean-build hydrate-gcp hydrate-asm hydrate-kubeflow
			
# Create the iap secret from environment variables
# TODO(jlewi): How can we test to make sure CLIENT_ID is set so we don't create an empty secret.
.PHONY: iap-secret
iap-secret:
	kubectl --context=$(KFCTXT) -n istio-system create secret generic kubeflow-oauth --from-literal=client_id=${CLIENT_ID} --from-literal=client_secret=${CLIENT_SECRET}

.PHONE: wait-gcp	
wait-gcp:
	kubectl --context=$(MGMTCTXT) wait --for=condition=Ready --timeout=600s  containercluster $(NAME)

# Create a kubeconfig context for the kubeflow cluster
.PHONE: create-cnrm-ctxt
create-ctxt:
	PROJECT=$(shell yq r ./settings.yaml project) \
	   REGION=$(shell yq r ./settings.yaml location) \
	   NAME=$(NAME) ./hack/create_context.sh