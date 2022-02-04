#!/bin/sh


# There are two environment variable groups to connect two different database (blue & green)

export PUB_NAME=pub_for_upgrade
export SLOT_NAME=slot_for_upgrade
export PUB_USER=replica_user
export PUB_USER_PASSWORD=replica_pass%!
export PGDATABASE=dev
export BLUE_CLUSTER_ID=pg-lsn-tets
export GREEN_CLUSTER_ID=pg-lsn-copy-test
export GREEN_INSTANCE_ID=pg-lsn-copy-test-instance1

# (in ./.pgenvb file, the following variables must be defined.)
# export PGHOST=
# export PGUSER=
# export PGPASSWORD=
# export SSH_HOST=
# export SSH_USER=
# export SSH_KEY=

. ./.pgenvb
export NEW_PGHOST=${PGHOST}

function makeSSHTunnel() {

  if [ -n "${SSH_HOST}" ]; then
    port_opended=`netstat -anp | grep 5432 | grep ssh | wc -l`
    if [ "${port_opended}" -ne "2" ]; then
      ssh -i ${SSH_KEY} -N -L 5432:${PGHOST}:5432 ${SSH_USER}@${SSH_HOST} &
      sleep 2
    fi
    export NEW_PGHOST=localhost
  fi
}

function createReplUser() {
psql -h ${NEW_PGHOST} <<EOF
create role ${PUB_USER} WITH LOGIN PASSWORD '${PUB_USER_PASSWORD}';
grant all privileges on database ${PGDATABASE} to ${PUB_USER};
grant all privileges on all tables in schema public to ${PUB_USER};
grant rds_replication to ${PUB_USER};
EOF
}

function createReplUserIfNotExist() {
  # check if 'repl_user' has been already created in the blue cluster.
  if [ -n "${PUB_USER}" ]; then
    repl_user_cnt=`psql -t -X -A -h ${NEW_PGHOST} -c "select count(1) from pg_user where usename='${PUB_USER}';"`
    echo "repl user count is ${repl_user_cnt}."
    # rm "${REPL_USER_CNT_FILE}"
    if [ "${repl_user_cnt}" -eq 0 ]; then
      createReplUser
    fi
  fi
}

function createPublication() {
psql -h ${NEW_PGHOST} <<EOF
create publication ${PUB_NAME} for all tables;
EOF
}

function createPublicationIfNotExist() {
  pub_checkcnt=`psql -t -X -A -h ${NEW_PGHOST} -c "select count(1) as cnt from pg_publication where pubname = '${PUB_NAME}';"`
  if [ "${pub_checkcnt}" -eq 0 ]; then
    createPublication
  fi
}

function createSlot() {
psql -h ${NEW_PGHOST} <<EOF
select pg_create_logical_replication_slot('${SLOT_NAME}', 'pgoutput');
EOF
}

function createSlotIfNotExist() {
  slot_checkcnt=`psql -t -X -A -h ${NEW_PGHOST} -c "select count(1) as cnt from pg_replication_slots where slot_name = '${SLOT_NAME}';"`
  if [ "${slot_checkcnt}" -eq 0 ]; then
    createSlot
  fi
}

function createGreenClusterStorage() {
  # clusterArn=`aws rds describe-db-clusters | jq '.DBClusters[] | select(.DBClusterIdentifier == "pg-lsn-tets") | .DBClusterArn' | sed "s/\"//g"`
  aws rds restore-db-cluster-to-point-in-time \
    --source-db-cluster-identifier ${BLUE_CLUSTER_ID} \
    --db-cluster-identifier ${GREEN_CLUSTER_ID} \
    --restore-type copy-on-write \
    --use-latest-restorable-time  
}

function checkGreenClusterStorage() {
  clusterArn=`aws rds describe-db-clusters | jq --arg GREEN_CLUSTER_ID ${GREEN_CLUSTER_ID} '.DBClusters[] | select(.DBClusterIdentifier == $GREEN_CLUSTER_ID) | .DBClusterArn' | sed "s/\"//g"`
  if [ -n "${clusterArn}" ]; then
    echo "clusterArn ${clusterArn}"
    createGreenClusterStorage
  fi
}

function createGreenClusterInstance() {
  blueinstanceId=`aws rds describe-db-clusters | jq --arg BLUE_CLUSTER_ID ${BLUE_CLUSTER_ID} '.DBClusters[] | select(.DBClusterIdentifier == $BLUE_CLUSTER_ID) | .DBClusterMembers[0].DBInstanceIdentifier' | sed "s/\"//g"`
  echo "blueinstanceId ${blueinstanceId}"
  aws rds describe-db-instances --db-instance-identifier ${blueinstanceId} > dbinstance.json
  instanceClass=`cat dbinstance.json | jq '.DBInstances[0].DBInstanceClass' | sed "s/\"//g"`
  engine=`cat dbinstance.json | jq '.DBInstances[0].Engine' | sed "s/\"//g"`
  dbname=`cat dbinstance.json | jq '.DBInstances[0].DBName' | sed "s/\"//g"`
  parameterGroupName=`cat dbinstance.json | jq '.DBInstances[0].DBParameterGroups.DBParameterGroupName' | sed "s/\"//g"`
  sgids=`cat dbinstance.json | jq '.DBInstances[0].VpcSecurityGroups.VpcSecurityGroupId' | sed "s/\"//g"`
  az=`cat dbinstance.json | jq '.DBInstances[0].AvailabilityZone' | sed "s/\"//g"`
  dbsubnet=`cat dbinstance.json | jq '.DBInstances[0].DBSubnetGroup.DBSubnetGroupName' | sed "s/\"//g"`
  enginever=`cat dbinstance.json | jq '.DBInstances[0].EngineVersion' | sed "s/\"//g"`
  storagetype=`cat dbinstance.json | jq '.DBInstances[0].StorageType' | sed "s/\"//g"`
  encrypted=`cat dbinstance.json | jq '.DBInstances[0].StorageEncrypted' | sed "s/\"//g"`
  kmskey=`cat dbinstance.json | jq '.DBInstances[0].KmsKeyId' | sed "s/\"//g"`
  echo "engine ${engine}"
  echo "instanceClass ${instanceClass}"
  echo "dbname ${dbname}"
  echo "parameterGroupName ${parameterGroupName}"
  echo "sgids ${sgids}"
  echo "az ${az}"
  echo "dbsubnet ${dbsubnet}"
  echo "enginever ${enginever}"
  echo "storagetype ${storagetype}"
  echo "encrypted ${encrypted}"
  echo "kmskey ${kmskey}"
  aws rds create-db-instance \
    --db-instance-identifier ${GREEN_INSTANCE_ID} \
    --db-cluster-identifier ${GREEN_CLUSTER_ID} \
    --db-name ${dbname} \
    --db-instance-class ${instacleClass} \
    --engine ${engine} \
    --db-parameter-group-name ${parameterGroupName} \
    --vpc-security-group-ids ${sgids} \
    --availability-zone ${az} \
    --db-subnet-group-name ${dbsunet} \
    --engine-version ${enginever} \
    --storage-type ${storagetype} \
    --storage-encrypted ${encrypted} \
    --kms-key-id ${kmskey}
}

function checkGreenClusterInstance() {
  # instanceArn=`aws rds describe-db-instances --db-instance-identifier ${GREEN_INSTANCE_ID} 
  createGreenClusterInstance
}

echo 'making ssh tunnel.'
makeSSHTunnel
echo 'making replication user in blue cluster'
createReplUserIfNotExist
echo 'making publication if not exist'
createPublicationIfNotExist
echo 'making slot if not exist'
createSlotIfNotExist
echo 'create green cluster storage if not exist'
checkGreenClusterStorage
echo 'create green db instance if not exist'
checkGreenClusterInstance


