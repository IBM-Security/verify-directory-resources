# Introduction
The files within this directory can be used to test the set-up of replicas within a Docker environment.  The directory data itself will be stored in a named volume, of the format: `isvd_replica_<num>`

The idea is that each time the `create-replica.sh` script is executed a new replica will be created, and each time the `remove-last-replica.sh` script is called the replica which was last created will be removed.

# Environment Variables

|File|Description
|----|-----------
|IMAGE\_REPO|The image repository which will be used (defaults to 'icr.io/isvd').
|IMAGE\_TAG|The tag of the Verify Directory images which will be used (defaults to 'latest').
|LICENSE\_KEY|The license key which will be used by the images.
|SECURE|By default the LDAP protocol will be used for all communications.  If the `SECURE` environment variable is set, prior to creating the environent, the LDAPS protocol will be used.



# Files

The files contained within this directory include:

|File|Description
|----|-----------
|check-user.sh | List the created users, against all LDAP replicas.
|create-replica.sh | Create a new replica.
|create-user.sh | Create a user, using the specified replica.
|remove-last-replica.sh | Remove the replica which was most recently created.
|replica-server.yaml | The YAML configuration for a replica.
|sds-seed.yaml | The YAML configuration for the seed container, which is used to copy the replica data.
|show-suffix.sh | A script which is used to show the `o=sample` suffix data at the specified replica.
