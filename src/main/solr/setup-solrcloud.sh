#!/bin/bash

# setup-solrcloud.sh - Initialize SolrCloud with configurations and collections

set -e

echo "Setting up SolrCloud..."

sleep 120


# Wait for ZooKeeper to be ready
echo "Waiting for ZooKeeper to be ready..."
while ! nc -z zookeeper 2181; do
  echo "Waiting for ZooKeeper..."
  sleep 2
done
echo "ZooKeeper is ready!"

# Wait for Solr nodes to be ready
echo "Waiting for Solr nodes to be ready..."
for port in 8983; do
  for host in solr9-node1 solr9-node2; do
    echo "Checking $host:$port..."
    while ! curl -s "http://$host:$port/solr/admin/info/system" > /dev/null; do
      echo "Waiting for $host:$port..."
      sleep 3
    done
    echo "$host:$port is ready!"
  done
done

# Upload NLA configuration to ZooKeeper
echo "Uploading NLA configuration to ZooKeeper..."
if ! solr zk ls /configs/nla_config -z zookeeper:2181 2>/dev/null; then
  solr zk upconfig -n nla_config -d /opt/solr-config/nla/conf -z zookeeper:2181
  echo "NLA configuration uploaded successfully!"
fi

# Upload Discovery configuration to ZooKeeper  
echo "Uploading Discovery configuration to ZooKeeper..."
if ! solr zk ls /configs/discovery_config -z zookeeper:2181 2>/dev/null; then
  solr zk upconfig -n discovery_config -d /opt/solr-config/discovery/conf -z zookeeper:2181
  echo "Discovery configuration uploaded successfully!"
fi


# Create NLA collection with sharding and replication
echo "Creating NLA collection..."

curl -s "http://solr9-node1:8983/solr/admin/collections?action=CREATE&name=nla&numShards=2&replicationFactor=2&maxShardsPerNode=2&collection.configName=nla_config"


echo "Creating DISCOVERY collection..."
curl -s "http://solr9-node1:8983/solr/admin/collections?action=CREATE&name=discovery&numShards=2&replicationFactor=2&maxShardsPerNode=2&collection.configName=discovery_config"

sleep 10

echo ""
echo "Verifying collection configurations..."
NLA_CONFIG=$(curl -s "http://solr9-node1:8983/solr/admin/collections?action=CLUSTERSTATUS&collection=nla" | grep -o '"configName":"[^"]*"' || echo "configName not found")
DISCOVERY_CONFIG=$(curl -s "http://solr9-node1:8983/solr/admin/collections?action=CLUSTERSTATUS&collection=discovery" | grep -o '"configName":"[^"]*"' || echo "configName not found")

echo "NLA collection config: $NLA_CONFIG"
echo "Discovery collection config: $DISCOVERY_CONFIG"

#!/bin/bash

# populate.sh - Load sample data into Solr (supports both standalone and SolrCloud)

SOLR_URL=${SOLR_URL:-"http://solr9-node1:8983/solr/discovery"}
SOLR_MODE=${SOLR_MODE:-"standalone"}
DELAY=${DELAY:-30}
DATA_FILE=${DATA_FILE:-"/opt/scripts/solr-sample.json.gz"}

echo "Populating Solr with sample data..."
echo "Mode: ${SOLR_MODE}"
echo "URL: ${SOLR_URL}"
echo "Waiting ${DELAY} seconds for Solr to be ready..."

sleep ${DELAY}

# For SolrCloud, we need to ensure collections are created first
if [ "${SOLR_MODE}" = "cloud" ]; then
    echo "Checking if collections exist..."
    
    # Wait for collections to be available
    MAX_ATTEMPTS=30
    ATTEMPT=0
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if curl -s "${SOLR_URL}/admin/ping" | grep -q '"status":"OK"'; then
            echo "Collection is ready!"
            break
        fi
        echo "Waiting for collection to be ready... (attempt $((ATTEMPT+1))/$MAX_ATTEMPTS)"
        sleep 5
        ATTEMPT=$((ATTEMPT+1))
    done
    
    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo "ERROR: Collection not ready after ${MAX_ATTEMPTS} attempts"
        exit 1
    fi
fi

# Load the sample data
echo "Loading sample data from ${DATA_FILE}..."
if [ -f "${DATA_FILE}" ]; then
    gunzip -c "${DATA_FILE}" | curl "${SOLR_URL}/update?commit=true" --data-binary @- -H "Content-type:application/json"
    
    if [ $? -eq 0 ]; then
        echo "Sample data loaded successfully!"
        
        # Show some stats
        echo "Checking document count..."
        DOC_COUNT=$(curl -s "${SOLR_URL}/select?q=*:*&rows=0" | grep -o '"numFound":[0-9]*' | cut -d: -f2)
        echo "Documents indexed: ${DOC_COUNT:-"unknown"}"
    else
        echo "ERROR: Failed to load sample data"
        exit 1
    fi
else
    echo "ERROR: Sample data file ${DATA_FILE} not found"
    exit 1
fi


