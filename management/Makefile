.PHONY: apply
apply: hydrate
	anthoscli apply -f .build/

.PHONY: hydrate
hydrate:
	mkdir -p .build/
	kustomize build . > .build/manifest.yaml
