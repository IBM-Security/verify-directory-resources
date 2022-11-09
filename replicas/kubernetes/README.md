# Introduction
The files within this directory can be used to test the set-up of replicas within a Kubernetes environment.  The directory data itself will be stored in a persistent volume claim, of the format: `replica-<num>-pvc`.  You will need to ensure that the persistent volume storage class, specified within `pvc.yaml`, is available within the Kubernetes environment.  

The idea is that each time the `create-replica.sh` script is executed a new replica will be created, and each time the `remove-last-replica.sh` script is called the replica which was last created will be removed.

# Environment Variables

|Name|Description
|----|-----------
|PVC|If you wish to use a different PVC yaml file (e.g. pvc-ibmcloud.yaml) you can export the PVC environment variable prior to running the scripts.
|IMAGE\_REPO|The image repository which will be used (defaults to 'icr.io/isvd').
|IMAGE\_TAG|The tag of the Verify Directory images which will be used (defaults to 'latest').
|LICENSE\_KEY|The license key which will be used by the images.
|PROXY\_ADDR|This environment variable should be set to the IP address used to access the environment.  In an IBM cloud environment the address can be obtained by calling: `ibmcloud cs workers -c <cluster-name> --json | jq -r .[0].publicIP`
|SECURE|By default the LDAP protocol will be used for all communications.  If the `SECURE` environment variable is set, prior to creating the environent, the LDAPS protocol will be used.

# Files

The files contained within this directory include:

|File|Description
|----|-----------
|check-user.sh | List the created users, against all LDAP replicas.
|clean-all.sh | Clean up the environment, removing all deployments, config maps and persistent volumes.
|clean-pvc.sh | Force the PVC for the specified replica to be cleaned, removing all files from the PVC.
|clean-pvc.yaml | The job descriptor, used by the clean-pvc.sh script, to clean a PVC.
|create-replica.sh | Create a new replica.
|create-secret.sh | Create the secret which supplies the credential information used when pulling the directory container images.
|create-user.sh | Create a user, using the specified replica.
|deploy.yaml | The deployment descriptor for a new replica, including the config map, deployment and service definitions.
|proxy.yaml | The deployment and service definition for the proxy.
|proxy-config.yaml | The YAML configuration for the proxy.
|pvc.yaml | The persistent volume claim definition for a replica.
|pvc-ibmcloud.yaml | The persistent volume claim definition for a replica when running in IBM cloud. 
|remove-last-replica.sh | Remove the replica which was most recently created.
|seed.yaml | The deployment descriptor for a new seed job, including the config map and job definitions.
|show-suffix.sh | A script which is used to show the `o=sample` suffix data at the specified replica.
