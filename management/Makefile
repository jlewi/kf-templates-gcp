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
