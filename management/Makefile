
# The kname of the context for the management cluster
MGMTCTXT=gke_jlewi-dev_us-central1_jlewi-mgmt-0420

.PHONY: apply
apply: hydrate
	anthoscli apply -f .build/cluster

.PHONY: hydrate
hydrate:
	# Delete the directory so any resources that have been removed
	# from the manifests will be pruned
	rm -rf .build
	mkdir -p .build/
	mkdir -p .build/cluster
	kustomize build ./cluster -o .build/cluster 


install-kcc:
	kustomize build ./cnrm-install-system | kubectl --context=$(MGMTCTXT) apply -f -