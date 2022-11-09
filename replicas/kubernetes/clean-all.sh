#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script will remove all of the deployment/configmap/service definitions
# from the environment.
#

clean_replica_type()
{
    echo "Cleaning any remaining $1...."

    entries=`kubectl get $1 --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep replica-`

    for entry in $entries; do
        kubectl delete $1 $entry
    done
}

echo "Cleaning any seed jobs...."

kubectl delete job isvd-seed
kubectl delete configmap isvd-seed-config
kubectl delete -f proxy.yaml
kubectl delete -f proxy-config.yaml

clean_replica_type deployment
clean_replica_type service
clean_replica_type configmap
clean_replica_type pvc
clean_replica_type pv

