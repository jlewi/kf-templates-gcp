# The name of the context for the management cluster
MGMTCTXT=gke_jlewi-dev_us-central1-f_jlewi-management
# The name of the context for your Kubeflow cluster
KFCTXT=gke_jlewi-dev_us-east1-d_kf-kcc-0415-001

# TODO(jlewi): If we use prune does that give us a complete upgrade solution?
# TODO(jlewi): Should we insert appropriate wait statements to wait for various services to
# be available before continuing?
.PHONY: apply
apply: hydrate
	# Apply management resources
	kubectl --context=$(MGMTCTXT) apply -f ./.build/gcp_config

	# Apply kubeflow apps
	kubectl --context=$(KFCTXT) apply -f ./.build/namespaces.yaml
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

# Hydrate all the application directories directories
# TODO(jlewi): We can't use a kustomization file to combine the top level packages
# because they might get vars conflicts. Also order is important when applying them.
.PHONY: hydrate
hydrate:
	# Delete build because we want to prune any resources which are no longer defined in the manifests
	rm -rf .build
	mkdir -p .build/

	# ***********************************************************************************
	# Hydrate cnrm
	mkdir -p .build/gcp_config 
	kustomize build -o .build/gcp_config gcp_config

	#***********************************************************************************
	# Hydrate kubeflow applications
	cp -f ./kustomize/namespaces.yaml ./.build/
	mkdir -p .build/application
	kustomize build --load_restrictor none -o .build/application kustomize/application
	mkdir -p .build/cert-manager
	kustomize build --load_restrictor none -o .build/cert-manager kustomize/cert-manager
	mkdir -p .build/cert-manager-crds
	kustomize build --load_restrictor none -o .build/cert-manager-crds kustomize/cert-manager-crds
	mkdir -p .build/cert-manager-kube-system-resources
	kustomize build --load_restrictor none -o .build/cert-manager-kube-system-resources kustomize/cert-manager-kube-system-resources
	mkdir -p .build/cloud-endpoints
	kustomize build --load_restrictor none -o .build/cloud-endpoints kustomize/cloud-endpoints
	mkdir -p .build/iap-ingress
	kustomize build --load_restrictor none -o .build/iap-ingress kustomize/iap-ingress
	mkdir -p .build/kubeflow-apps
	kustomize build --load_restrictor none -o .build/kubeflow-apps kustomize/kubeflow-apps
	mkdir -p .build/kubeflow-apps
	kustomize build --load_restrictor none -o .build/kubeflow-istio kustomize/kubeflow-istio
	mkdir -p .build/metacontroller
	kustomize build --load_restrictor none -o .build/metacontroller kustomize/metacontroller
	
# Create the iap secret from environment variables
.PHONY: iap-secret
iap-secret:
	kubectl -n istio-system create secret generic kubeflow-oauth --from-literal=client_id=${CLIENT_ID} --from-literal=client_secret=${CLIENT_SECRET}