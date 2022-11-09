#!/bin/sh

##############################################################################
# Copyright contributors to the IBM Security Verify Directory project.
##############################################################################

#
# This script is used to clean out the PVC for the specified replica.  It
# is only really required if the PV itself does not pay attention to the
# reclamation policy of the PV.
#

if [ $# -ne 1 ] ; then
    echo "usage: $0 [replica-num]"
    exit 1
fi

if [ -z "$PVC" ] ; then
    PVC=pvc.yaml
fi

echo "Recreating the PVC...."
sed "s|replica-xxx|replica-$1|g" $PVC | kubectl create -f -

echo "Creating the job to clean the contents of the PVC...."
sed "s|replica-xxx|replica-$1|g" clean-pvc.yaml | kubectl create -f -

kubectl wait --for=condition=complete --timeout=300s job/isvd-clean

kubectl delete job isvd-clean

echo "Deleting the PVC...."
sed "s|replica-xxx|replica-$1|g" $PVC | kubectl delete -f -

