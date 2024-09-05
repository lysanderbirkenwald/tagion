#!/usr/bin/env bash

# Initialize default values
nodes=5
image=tagion/tagion:current
outfile=docker-compose.yml

usage() { 
    echo "Usage: $0
        -n <nodes=$nodes, the number of nodes>
        -i <image=$image, the docker image to use>
        -o <outfile=$outfile>" 1>&2;
    exit 1;
}

ADDRESS_FORMAT=${ADDRESS_FORMAT:=tcp://[::1]:7000}

# Process command-line options
while getopts "h:n:i:o:" opt
do
    case $opt in
        h)  usage ;;
        n)  nodes=$OPTARG ;;
        i)  image=$OPTARG ;;
        o)  outfile=$OPTARG ;;
        *)  usage ;;
    esac
done

foreach_node() {
    for ((i = 0; i < nodes; i++)); 
    do
        # Substitute any %NODE string in the command with the node number
        "${@//\%NODE/$i}"
    done
}

cat > "$outfile" << EOL
# Generated by $0

volumes: 
  setup-volume:
$(foreach_node printf \
"  node%NODE:\n"
)

services:
  setup-volumes:
    environment:
      - ADDRESS_FORMAT=tcp://node%NODE:%PORT
    image: $image
    volumes:
      - setup-volume:/usr/local/app
    command: create_wallets.sh -m1 -n$nodes

$(foreach_node printf \
"  node%NODE:
    image: $image
    depends_on: 
      setup-volumes:
        condition: service_completed_successfully
    volumes: 
      - setup-volume:/data
      - node%NODE:/usr/local/app
    environment:
        - NODE_NUMBER=%NODE
    command: sh -c \"cp -r /data/. /usr/local/app && echo 0000 | neuewelle /usr/local/app/mode1/node%NODE/tagionwave.json\"

")
EOL