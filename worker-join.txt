#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: sudo $0 '<join-command>'"
    echo "Paste the full join command from the master (e.g., kubeadm join ...)"
    exit 1
fi

# Run the join command
$1

echo "Worker joined the cluster."