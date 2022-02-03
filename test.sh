#!/bin/sh


# There are two environment variable groups to connect two different database (blue & green)

export PUB_NAME=pub_for_upgrade
export PUB_USER=replica_user
export PUB_USER_PASSWORD=replica_pass%!
export PGDATABASE=dev
export BLUE_CLUSTER_ID=pg-lsn-tets
export GREEN_CLUSTER_ID=pg-lsn-copy-test

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

function checkReplUser() {
  # check if 'repl_user' has been already created in the blue cluster.
  export REPL_USER_CNT_FILE='./replica_user_cnt_tmp'

psql -h ${NEW_PGHOST} -t > ${REPL_USER_CNT_FILE} <<EOF
\copy (select count(1) from pg_user where usename='${PUB_USER}') to '${REPL_USER_CNT_FILE}';
EOF

  repl_user_cnt=`cat ${REPL_USER_CNT_FILE}`
  rm "${REPL_USER_CNT_FILE}"
  if [ -n "${PUB_USER}" ]; then
    if [ "${repl_user_cnt}" -ne 0 ]; then
      createReplUser
    fi
  fi
}

function checkPublication() {
  export PUB_CHECKCNT_FILE='./pub_checkcnt_tmp'
psql -h ${NEW_PGHOST} -t ${PUB_CHECKCNT_FILE} <<EOF
select count(1) as cnt from pg_publication where pubname = '${PUB_NAME}';
EOF

  pub_checkcnt=`cat ${PUB_CHECKCNT_FILE}`
  rm ${PUB_CHECKCNT_FILE}
  if [ "${pub_checkcnt}" -eq 0 ]; then
    createPublication
  fi
}

function createPublication() {
psql -h ${NEW_PGHOST} <<EOF
create publication ${PUB_NAME} for all tables;
EOF
}

function checkSlot() {
  export SLOT_CHECKCNT_FILE='./slot_checkcnt_tmp'
psql -h ${NEW_PGHOST} -t ${SLOT_CHECKCNT_FILE} <<EOF

EOF
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
  clusterArn=`aws rds describe-db-clusters | jq '.DBClusters[] | select(.DBClusterIdentifier == "${GREEN_CLUSTER_ID}") | .DBClusterArn' | sed "s/\"//g"`
  if [ -n "${clusterArn}" ]; then
    createGreenClusterStorage
  fi
}

function createGreenClusterInstance() {
  blueinstanceId=`aws rds describe-db-clusters | jq '.DBClusters[] | select(.DBClusterIdentifier == "${BLUE_CLUSTER_ID}") | .DBClusterMembers[0].DBInstanceIdentifier' | sed "s/\"//g"`
  aws rds describe-db-instances --db-instance-identifier ${blueinstanceId} > dbinstance.json
  instanceClass=`cat dbinstance.json | jq'.DBInstances[0].DBInstanceClass' | sed "s/\"//g"`
  engine=`cat dbinstance.json | jq'.DBInstances[0].Engine' | sed "s/\"//g"`
  dbname=`cat dbinstance.json | jq'.DBInstances[0].DBName' | sed "s/\"//g"`
  parameterGroupName=`cat dbinstance.json | jq'.DBInstances[0].DBParameterGroups.DBParameterGroupName' | sed "s/\"//g"`
  sgids=`cat dbinstance.json | jq'.DBInstances[0].VpcSecurityGroups.VpcSecurityGroupId' | sed "s/\"//g"`
  az=`cat dbinstance.json | jq'.DBInstances[0].AvailabilityZone' | sed "s/\"//g"`
  dbsubnet=`cat dbinstance.json | jq'.DBInstances[0].DBSubnetGroup.DBSubnetGroupName' | sed "s/\"//g"`
  enginever=`cat dbinstance.json | jq'.DBInstances[0].EngineVersion' | sed "s/\"//g"`
  storagetype=`cat dbinstance.json | jq'.DBInstances[0].StorageType' | sed "s/\"//g"`
  encrypted=`cat dbinstance.json | jq'.DBInstances[0].StorageEncrypted' | sed "s/\"//g"`
  kmskey=`cat dbinstance.json | jq'.DBInstances[0].KmsKeyId' | sed "s/\"//g"`
  aws rds create-db-instance \
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

}

function createGreenClusterInstance() {

}

makeSSHTunnel
checkReplUser
checkGreenClusterStorage


