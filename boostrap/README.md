TODO(jlewi): Not sure these configs are up to date.



This directory bootstraps the root management GKE cluster, from which
we create all our other projects etc.

This management cluster must run Nomos & KCC, and we point it to a
SourceRepo that we use as our gitops source of truth here.
